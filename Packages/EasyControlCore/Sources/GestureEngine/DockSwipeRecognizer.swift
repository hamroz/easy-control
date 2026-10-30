/// Three fingers held and moved → a continuous, axis-locked drag, like the trackpad's three-finger swipe.
/// Deltas are in isotropic units (frame heights); the drag ends normally when the pose changes and is
/// cancelled when the hand is lost or the engine interrupts it.
public struct DockSwipeRecognizer {
    private let config: GestureConfig
    private var start: SIMD2<Float>?
    private var last: SIMD2<Float> = .zero
    private var axis: GestureID?

    public init(config: GestureConfig) {
        self.config = config
    }

    public var isActive: Bool { axis != nil }

    public mutating func update(pose: PoseClass, palmCenter: SIMD2<Float>?, aspect: Float = 1, at t: Double) -> GestureEvent? {
        guard let normalized = palmCenter else { return cancel() }
        guard pose == .three else { return release() }
        let p = SIMD2<Float>(normalized.x * aspect, normalized.y)
        guard let origin = start else {
            start = p
            last = p
            return nil
        }
        guard let locked = axis else {
            let d = p - origin
            guard max(abs(d.x), abs(d.y)) >= config.dockSwipeLock else { return nil }
            let chosen: GestureID = abs(d.x) >= abs(d.y) ? .dockSwipeHorizontal : .dockSwipeVertical
            axis = chosen
            last = p
            return .continuous(chosen, phase: .began, delta: Self.project(d, on: chosen))
        }
        let delta = Self.project(p - last, on: locked)
        last = p
        return delta == .zero ? nil : .continuous(locked, phase: .changed, delta: delta)
    }

    /// Interrupted (hand lost, typing, pause, disengage): the Dock should snap back.
    public mutating func cancel() -> GestureEvent? {
        defer { reset() }
        return axis.map { .continuous($0, phase: .cancelled, delta: .zero) }
    }

    /// The user changed pose: like lifting fingers off the trackpad.
    private mutating func release() -> GestureEvent? {
        defer { reset() }
        return axis.map { .continuous($0, phase: .ended, delta: .zero) }
    }

    private mutating func reset() {
        start = nil
        axis = nil
    }

    private static func project(_ d: SIMD2<Float>, on axis: GestureID) -> SIMD2<Float> {
        axis == .dockSwipeHorizontal ? [d.x, 0] : [0, d.y]
    }
}
