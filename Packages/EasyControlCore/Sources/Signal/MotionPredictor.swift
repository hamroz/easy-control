/// Predicts where a tracked point is *now*, between and slightly after camera frames, so output can be
/// rendered at display rate. Constant velocity from the last two samples, extrapolation capped at
/// `horizon`, no extrapolation below `speedFloor` (so a still hand doesn't drift), reset after a gap.
public struct MotionPredictor: Sendable {
    private let horizon: Double
    private let speedFloor: Float
    private let resetGap: Double
    /// Extrapolate only part of the velocity: a full constant-velocity guess overshoots when the hand stops.
    private let gain: Float
    private var last: (p: SIMD2<Float>, t: Double)?
    private var velocity: SIMD2<Float> = .zero

    public init(horizon: Double = 0.033, speedFloor: Float = 0.02, resetGap: Double = 0.25, gain: Float = 0.5) {
        self.horizon = horizon
        self.speedFloor = speedFloor
        self.resetGap = resetGap
        self.gain = gain
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
        return last.p + velocity * dt * gain
    }

    public mutating func reset() {
        last = nil
        velocity = .zero
    }
}

/// A "sticky" point: movement within `radius` of the resting point is ignored (hand tremor); beyond it, the
/// resting point is dragged along, staying `radius` behind.
public struct Deadband: Sendable {
    private let radius: Float
    private var rest: SIMD2<Float>?

    public init(radius: Float = 0.004) {
        self.radius = radius
    }

    public mutating func filter(_ p: SIMD2<Float>) -> SIMD2<Float> {
        guard let r = rest else {
            rest = p
            return p
        }
        let d = p - r
        let distance = (d * d).sum().squareRoot()
        guard distance > radius else { return r }
        let moved = p - d / distance * radius
        rest = moved
        return moved
    }

    public mutating func reset() {
        rest = nil
    }
}
