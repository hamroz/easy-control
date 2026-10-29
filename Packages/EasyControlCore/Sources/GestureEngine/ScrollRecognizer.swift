/// Two-finger pose + hand motion → continuous scroll.
public struct ScrollRecognizer {
    private let config: GestureConfig
    /// Palm position that the last emitted delta brought us to; nil when not scrolling.
    private var reference: SIMD2<Float>?

    public init(config: GestureConfig) {
        self.config = config
    }

    public var isActive: Bool { reference != nil }

    public mutating func update(pose: PoseClass, palmCenter: SIMD2<Float>?, at t: Double) -> GestureEvent? {
        guard pose == .two, let center = palmCenter else { return cancel() }
        guard let ref = reference else {
            reference = center
            return .continuous(.scroll, phase: .began, delta: .zero)
        }
        var delta = center - ref
        if abs(delta.x) < config.scrollDeadZone { delta.x = 0 }
        if abs(delta.y) < config.scrollDeadZone { delta.y = 0 }
        guard delta != .zero else { return nil }
        reference = ref + delta
        return .continuous(.scroll, phase: .changed, delta: delta)
    }

    /// Ends an active scroll (hand lost, suppression, disengagement).
    public mutating func cancel() -> GestureEvent? {
        guard reference != nil else { return nil }
        reference = nil
        return .continuous(.scroll, phase: .ended, delta: .zero)
    }
}
