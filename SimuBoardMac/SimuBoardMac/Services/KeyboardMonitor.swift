import CoreGraphics
import Foundation

struct KeyboardEvent: Sendable {
    enum Kind: Sendable {
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
    private var handler: (@MainActor (KeyboardEvent) -> Void)?
    private var pressedModifierKeyCodes: Set<UInt16> = []

    @discardableResult
    func start(handler: @escaping @MainActor (KeyboardEvent) -> Void) -> Bool {
        stop()
        self.handler = handler

        let keyDownMask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let keyUpMask = CGEventMask(1) << CGEventType.keyUp.rawValue
        let flagsChangedMask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
        let eventMask = keyDownMask | keyUpMask | flagsChangedMask
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
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
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let payload: KeyboardEvent? = if type == .keyDown || type == .keyUp {
            KeyboardEvent(
                kind: type == .keyDown ? .keyDown : .keyUp,
                keyCode: keyCode,
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            )
        } else {
            nil
        }
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

    private func reenableTap() {
        pressedModifierKeyCodes.removeAll()
        if let port = runState?.port { CGEvent.tapEnable(tap: port, enable: true) }
    }

    private func receive(_ payload: KeyboardEvent) {
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
        receive(KeyboardEvent(kind: kind, keyCode: keyCode, isRepeat: false))
    }

    isolated deinit {
        guard let runState else { return }
        CGEvent.tapEnable(tap: runState.port, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runState.source, .commonModes)
        CFMachPortInvalidate(runState.port)
    }
}
