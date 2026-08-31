import CoreGraphics
import Foundation

struct KeyboardEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case keyDown
        case keyUp
    }

    let kind: Kind
    let keyCode: UInt16
    let isRepeat: Bool
    let isShortcutModified: Bool

    init(
        kind: Kind,
        keyCode: UInt16,
        isRepeat: Bool,
        isShortcutModified: Bool = false
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.isRepeat = isRepeat
        self.isShortcutModified = isShortcutModified
    }
}

@MainActor
final class KeyboardMonitor {
    struct EventInterest: Equatable, Sendable {
        let keyboardPresses: Bool
        let keyboardReleases: Bool
        let pointerPresses: Bool
        let pointerReleases: Bool

        static let all = EventInterest(
            keyboardPresses: true,
            keyboardReleases: true,
            pointerPresses: true,
            pointerReleases: true
        )

        var eventTypes: [CGEventType] {
            var types: [CGEventType] = []
            if keyboardPresses { types.append(.keyDown) }
            if keyboardReleases { types.append(.keyUp) }
            // Modifier keys arrive only as flagsChanged, which represents both
            // transitions even when a future caller asks only for releases.
            if keyboardPresses || keyboardReleases { types.append(.flagsChanged) }
            if pointerPresses { types.append(.leftMouseDown) }
            if pointerReleases { types.append(.leftMouseUp) }
            if pointerPresses { types.append(.rightMouseDown) }
            if pointerReleases { types.append(.rightMouseUp) }
            if pointerPresses { types.append(.otherMouseDown) }
            if pointerReleases { types.append(.otherMouseUp) }
            return types
        }

        var eventMask: CGEventMask {
            eventTypes.reduce(CGEventMask(0)) { mask, type in
                mask | (CGEventMask(1) << type.rawValue)
            }
        }

        var isEmpty: Bool { eventTypes.isEmpty }
    }

    private struct RunState {
        let port: CFMachPort
        let source: CFRunLoopSource
    }

    private var runState: RunState?
    private var handler: (@MainActor (GlobalInputEvent) -> Void)?
    private var pressedModifierKeyCodes: Set<UInt16> = []

    static let observedEventTypes = EventInterest.all.eventTypes
    static let observedEventMask = EventInterest.all.eventMask

    @discardableResult
    func start(
        interest: EventInterest = .all,
        handler: @escaping @MainActor (GlobalInputEvent) -> Void
    ) -> Bool {
        stop()
        guard !interest.isEmpty else { return true }
        self.handler = handler

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: interest.eventMask,
            callback: Self.eventTapCallback,
            userInfo: userInfo
        ), let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            self.handler = nil
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        runState = RunState(port: port, source: source)
        return true
    }

    func stop() {
        pressedModifierKeyCodes.removeAll()
        guard let runState else {
            handler = nil
            return
        }
        CGEvent.tapEnable(tap: runState.port, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runState.source, .commonModes)
        CFMachPortInvalidate(runState.port)
        self.runState = nil
        handler = nil
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        let wasDisabled = type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
        let payload = decodedInputEvent(type: type, event: event)
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifierKeyCode = type == .flagsChanged ? keyCode : nil
        let modifierIsDown = modifierKeyCode.map {
            CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0))
        }

        precondition(Thread.isMainThread)
        MainActor.assumeIsolated {
            if wasDisabled {
                monitor.reenableTap()
            } else if let payload {
                monitor.receive(payload)
            } else if let modifierKeyCode, let modifierIsDown {
                monitor.receiveModifierChange(
                    keyCode: modifierKeyCode,
                    isDown: modifierIsDown
                )
            }
        }
        return Unmanaged.passUnretained(event)
    }

    static func decodedInputEvent(type: CGEventType, event: CGEvent) -> GlobalInputEvent? {
        switch type {
        case .keyDown, .keyUp:
            let keyboardEvent = KeyboardEvent(
                kind: type == .keyDown ? .keyDown : .keyUp,
                keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                isShortcutModified: event.flags.contains(.maskCommand)
                    || event.flags.contains(.maskControl)
            )
            return .keyboard(keyboardEvent)
        case .leftMouseDown, .leftMouseUp:
            return .pointer(PointerEvent(
                phase: type == .leftMouseDown ? .press : .release,
                button: .primary
            ))
        case .rightMouseDown, .rightMouseUp:
            return .pointer(PointerEvent(
                phase: type == .rightMouseDown ? .press : .release,
                button: .secondary
            ))
        case .otherMouseDown, .otherMouseUp:
            return .pointer(PointerEvent(
                phase: type == .otherMouseDown ? .press : .release,
                button: PointerButton(
                    mouseButtonNumber: event.getIntegerValueField(.mouseEventButtonNumber)
                )
            ))
        default:
            return nil
        }
    }

    private func reenableTap() {
        pressedModifierKeyCodes.removeAll()
        if let port = runState?.port { CGEvent.tapEnable(tap: port, enable: true) }
    }

    private func receive(_ payload: GlobalInputEvent) {
        guard let handler else { return }
        handler(payload)
    }

    private func receiveModifierChange(keyCode: UInt16, isDown: Bool) {
        let wasDown = pressedModifierKeyCodes.contains(keyCode)
        guard wasDown != isDown else { return }

        if isDown {
            pressedModifierKeyCodes.insert(keyCode)
        } else {
            pressedModifierKeyCodes.remove(keyCode)
        }
        let kind: KeyboardEvent.Kind = isDown ? .keyDown : .keyUp
        receive(.keyboard(KeyboardEvent(kind: kind, keyCode: keyCode, isRepeat: false)))
    }

    isolated deinit {
        guard let runState else { return }
        CGEvent.tapEnable(tap: runState.port, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runState.source, .commonModes)
        CFMachPortInvalidate(runState.port)
    }
}
