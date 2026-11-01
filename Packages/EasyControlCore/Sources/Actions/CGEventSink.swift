import CoreGraphics

/// Posts events to the HID event tap. Requires the Accessibility permission.
public struct CGEventSink: EventSink {
    /// Stamped into `eventSourceUserData` so our own input monitor can ignore what we inject ("EC").
    public static let syntheticMarker: Int64 = 0x4543_0001

    public init() {}

    public var supportsDockSwipe: Bool { DockSwipeBridge.shared.isAvailable }

    public func post(_ event: SyntheticEvent) {
        if case let .dockSwipe(motion, phase, progress, velocity) = event {
            DockSwipeBridge.shared.post(motion: motion, phase: phase, progress: progress, velocity: velocity,
                                        marker: Self.syntheticMarker)
            return
        }
        guard let cgEvent = Self.makeEvent(event) else { return }
        cgEvent.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        cgEvent.post(tap: .cghidEventTap)
    }

    static func makeEvent(_ event: SyntheticEvent) -> CGEvent? {
        let source = CGEventSource(stateID: .hidSystemState)
        switch event {
        case let .scroll(dx, dy, phase, momentum):
            guard let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: dy, wheel2: dx, wheel3: 0) else { return nil }
            e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase.cgValue)
            e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum.cgValue)
            return e
        case let .key(code, flags, down):
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return nil }
            e.flags = CGEventFlags(rawValue: flags)
            return e
        case .dockSwipe:
            return nil
        case let .mouse(kind, x, y, clickCount):
            let (type, button): (CGEventType, CGMouseButton) = switch kind {
            case .moved: (.mouseMoved, .left)
            case .leftDown: (.leftMouseDown, .left)
            case .leftUp: (.leftMouseUp, .left)
            case .leftDragged: (.leftMouseDragged, .left)
            case .rightDown: (.rightMouseDown, .right)
            case .rightUp: (.rightMouseUp, .right)
            }
            guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y),
                                  mouseButton: button) else { return nil }
            e.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
            return e
        }
    }
}

private extension ScrollPhase {
    /// kCGScrollPhase* values.
    var cgValue: Int64 {
        switch self {
        case .none: 0
        case .began: 1
        case .changed: 2
        case .ended: 4
        }
    }
}

private extension MomentumPhase {
    /// kCGMomentumScrollPhase* values.
    var cgValue: Int64 {
        switch self {
        case .none: 0
        case .began: 1
        case .continue: 2
        case .ended: 3
        }
    }
}
