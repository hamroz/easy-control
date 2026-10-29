import CoreGraphics
import Foundation
import QuartzCore
import Synchronization

/// Watches real keyboard/mouse/trackpad input (listen-only) so gestures can pause while the user types.
/// Ignores events we injected ourselves. Requires the Accessibility permission.
/// Safe to call from any thread.
public final class InputActivityMonitor: Sendable {
    private struct State {
        var tap: CFMachPort?
        var runLoop: CFRunLoop?
        var tapsCreated = 0
    }

    /// Hands non-Sendable CF objects to the tap thread.
    private final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    private let state = Mutex(State())
    private let last = Mutex<Double?>(nil)

    public init() {}

    /// Host time (`CACurrentMediaTime`) of the latest real input, if any.
    public var lastUserInput: Double? { last.withLock { $0 } }

    /// True while the event tap exists and is enabled. Revoking Accessibility invalidates it.
    public var isRunning: Bool {
        state.withLock { s in s.tap.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } ?? false }
    }

    var tapsCreated: Int { state.withLock { $0.tapsCreated } }

    /// Creates the tap if it isn't running (also after an Accessibility re-grant).
    /// Returns false if the tap can't be created (Accessibility not granted).
    @discardableResult
    public func start() -> Bool {
        state.withLock { s in
            if let tap = s.tap, CFMachPortIsValid(tap), CGEvent.tapIsEnabled(tap: tap) { return true }
            Self.teardown(&s)

            let types: [CGEventType] = [.keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown,
                                        .leftMouseDragged, .rightMouseDragged, .scrollWheel, .otherMouseDown]
            let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                eventsOfInterest: mask, callback: Self.callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ), let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else { return false }

            let tapBox = Box(tap)
            let sourceBox = Box(source)
            let loopBox = Box<CFRunLoop?>(nil)
            let ready = DispatchSemaphore(value: 0)
            let thread = Thread {
                loopBox.value = CFRunLoopGetCurrent()
                CFRunLoopAddSource(CFRunLoopGetCurrent(), sourceBox.value, .commonModes)
                CGEvent.tapEnable(tap: tapBox.value, enable: true)
                ready.signal()
                CFRunLoopRun()
            }
            thread.name = "EasyControl.InputActivityMonitor"
            thread.qualityOfService = .userInteractive
            thread.start()
            ready.wait()

            s.tap = tap
            s.runLoop = loopBox.value
            s.tapsCreated += 1
            return true
        }
    }

    public func stop() {
        state.withLock { Self.teardown(&$0) }
    }

    /// Simulates what revoking Accessibility does to a live tap.
    func invalidateTapForTesting() {
        state.withLock { s in s.tap.map(CFMachPortInvalidate) }
    }

    private static func teardown(_ s: inout State) {
        if let tap = s.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop = s.runLoop { CFRunLoopStop(runLoop) }
        s.tap = nil
        s.runLoop = nil
    }

    fileprivate func record(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            state.withLock { s in
                if let tap = s.tap, CFMachPortIsValid(tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            }
        default:
            guard event.getIntegerValueField(.eventSourceUserData) != CGEventSink.syntheticMarker else { return }
            let now = CACurrentMediaTime()
            last.withLock { $0 = now }
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, info in
        if let info {
            Unmanaged<InputActivityMonitor>.fromOpaque(info).takeUnretainedValue().record(type, event)
        }
        return Unmanaged.passUnretained(event)
    }
}
