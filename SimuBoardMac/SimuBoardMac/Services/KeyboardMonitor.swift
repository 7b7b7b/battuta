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

    @discardableResult
    func start(handler: @escaping @MainActor (KeyboardEvent) -> Void) -> Bool {
        stop()
        self.handler = handler

        let keyDownMask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let keyUpMask = CGEventMask(1) << CGEventType.keyUp.rawValue
        let eventMask = keyDownMask | keyUpMask
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
        let payload: KeyboardEvent? = if type == .keyDown || type == .keyUp {
            KeyboardEvent(
                kind: type == .keyDown ? .keyDown : .keyUp,
                keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            )
        } else {
            nil
        }

        precondition(Thread.isMainThread)
        MainActor.assumeIsolated {
            if wasDisabled {
                monitor.reenableTap()
            } else if let payload {
                monitor.receive(payload)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    private func reenableTap() {
        if let port = runState?.port { CGEvent.tapEnable(tap: port, enable: true) }
    }

    private func receive(_ payload: KeyboardEvent) {
        guard let handler else { return }
        handler(payload)
    }

    isolated deinit {
        guard let runState else { return }
        CGEvent.tapEnable(tap: runState.port, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runState.source, .commonModes)
        CFMachPortInvalidate(runState.port)
    }
}
