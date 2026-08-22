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
}

@MainActor
final class KeyboardMonitor {
    private struct RunState {
        let port: CFMachPort
        let source: CFRunLoopSource
    }

    private var runState: RunState?
    private var handler: (@MainActor (GlobalInputEvent) -> Void)?
    private var pressedModifierKeyCodes: Set<UInt16> = []

    static let observedEventTypes: [CGEventType] = [
        .keyDown,
        .keyUp,
        .flagsChanged,
        .leftMouseDown,
        .leftMouseUp,
        .rightMouseDown,
        .rightMouseUp,
        .otherMouseDown,
        .otherMouseUp,
    ]

    static let observedEventMask = observedEventTypes.reduce(CGEventMask(0)) { mask, type in
        mask | (CGEventMask(1) << type.rawValue)
    }

    @discardableResult
    func start(handler: @escaping @MainActor (GlobalInputEvent) -> Void) -> Bool {
        stop()
        self.handler = handler

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: Self.observedEventMask,
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
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
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
