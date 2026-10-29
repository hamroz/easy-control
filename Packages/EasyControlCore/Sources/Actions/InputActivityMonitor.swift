import CoreGraphics
import Foundation
import QuartzCore
import Synchronization

/// Watches real keyboard/mouse/trackpad input (listen-only) so gestures can pause while the user types.
/// Ignores events we injected ourselves. Requires the Accessibility permission.
public final class InputActivityMonitor: @unchecked Sendable {
    private let last = Mutex<Double?>(nil)
    private var tap: CFMachPort?
    private var thread: Thread?
    private var runLoop: CFRunLoop?

    public init() {}

    /// Host time (`CACurrentMediaTime`) of the latest real input, if any.
    public var lastUserInput: Double? { last.withLock { $0 } }

    /// Returns false if the event tap can't be created (Accessibility not granted).
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown,
                                    .leftMouseDragged, .rightMouseDragged, .scrollWheel, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self, let tap = self.tap, let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
                ready.signal()
                return
            }
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "EasyControl.InputActivityMonitor"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
        ready.wait()
        return true
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop { CFRunLoopStop(runLoop) }
        tap = nil
        runLoop = nil
        thread = nil
    }

    fileprivate func record(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
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
