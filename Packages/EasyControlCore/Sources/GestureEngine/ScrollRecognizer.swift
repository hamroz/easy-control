/// Two-finger pose + hand motion → continuous scroll.
public struct ScrollRecognizer {
    private let config: GestureConfig
    /// Palm position that the last emitted delta brought us to; nil when not scrolling.
    private var reference: SIMD2<Float>?

    public init(config: GestureConfig) {
        self.config = config
    }

    public var isActive: Bool { reference != nil }

    /// - Parameters:
    ///   - palmCenter: normalized frame coordinates.
    ///   - aspect: frame width / height; deltas are reported in isotropic units (frame heights).
    public mutating func update(pose: PoseClass, palmCenter: SIMD2<Float>?, aspect: Float = 1, at t: Double) -> GestureEvent? {
        guard let normalized = palmCenter else { return cancel() }
        let center = SIMD2<Float>(normalized.x * aspect, normalized.y)
        guard pose == .two else { return release() }
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

    /// Interrupts an active scroll (hand lost, suppression, disengagement): no momentum.
    public mutating func cancel() -> GestureEvent? {
        guard reference != nil else { return nil }
        reference = nil
        return .continuous(.scroll, phase: .cancelled, delta: .zero)
    }

    /// The user left the scroll pose: a normal end, which may coast.
    private mutating func release() -> GestureEvent? {
        guard reference != nil else { return nil }
        reference = nil
        return .continuous(.scroll, phase: .ended, delta: .zero)
    }
}
