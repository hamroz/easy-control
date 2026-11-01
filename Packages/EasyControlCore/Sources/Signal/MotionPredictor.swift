/// Predicts where a tracked point is *now*, between and slightly after camera frames, so output can be
/// rendered at display rate. Constant velocity from the last two samples, extrapolation capped at
/// `horizon`, no extrapolation below `speedFloor` (so a still hand doesn't drift), reset after a gap.
public struct MotionPredictor: Sendable {
    private let horizon: Double
    private let speedFloor: Float
    private let resetGap: Double
    private var last: (p: SIMD2<Float>, t: Double)?
    private var velocity: SIMD2<Float> = .zero

    public init(horizon: Double = 0.033, speedFloor: Float = 0.02, resetGap: Double = 0.25) {
        self.horizon = horizon
        self.speedFloor = speedFloor
        self.resetGap = resetGap
    }

    public mutating func update(_ p: SIMD2<Float>, at t: Double) {
        if let prev = last, t > prev.t, t - prev.t <= resetGap {
            velocity = (p - prev.p) / Float(t - prev.t)
        } else {
            velocity = .zero
        }
        last = (p, t)
    }

    public func sample(at t: Double) -> SIMD2<Float>? {
        guard let last else { return nil }
        guard (velocity * velocity).sum().squareRoot() >= speedFloor else { return last.p }
        let dt = Float(min(max(t - last.t, 0), horizon))
        return last.p + velocity * dt
    }

    public mutating func reset() {
        last = nil
        velocity = .zero
    }
}
