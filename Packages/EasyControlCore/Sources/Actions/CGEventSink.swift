import CoreGraphics

/// Posts events to the HID event tap. Requires the Accessibility permission.
public struct CGEventSink: EventSink {
    /// Stamped into `eventSourceUserData` so our own input monitor can ignore what we inject ("EC").
    public static let syntheticMarker: Int64 = 0x4543_0001

    public init() {}

    public func post(_ event: SyntheticEvent) {
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
