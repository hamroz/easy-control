import Foundation

/// One Euro filter (Casiez et al. 2012) for 2D points: smooths jitter at low speed, follows quickly at high speed.
public struct OneEuroFilter: Sendable {
    public var minCutoff: Float
    public var beta: Float
    public var dCutoff: Float
    /// A gap longer than this (or time going backwards) restarts the filter instead of smoothing across it.
    public var resetGap: Double

    private var last: (t: Double, x: SIMD2<Float>, dx: SIMD2<Float>)?

    public init(minCutoff: Float = 1.7, beta: Float = 0.3, dCutoff: Float = 1.0, resetGap: Double = 0.25) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
        self.resetGap = resetGap
    }

    public mutating func reset() { last = nil }

    public mutating func filter(_ x: SIMD2<Float>, at t: Double) -> SIMD2<Float> {
        guard let prev = last, t > prev.t, t - prev.t <= resetGap else {
            last = (t, x, .zero)
            return x
        }
        let dt = Float(t - prev.t)
        let dx = (x - prev.x) / dt
        let dxHat = Self.lowPass(dx, prev.dx, alpha: Self.alpha(cutoff: dCutoff, dt: dt))
        let cutoff = minCutoff + beta * (dxHat * dxHat).sum().squareRoot()
        let xHat = Self.lowPass(x, prev.x, alpha: Self.alpha(cutoff: cutoff, dt: dt))
        last = (t, xHat, dxHat)
        return xHat
    }

    private static func alpha(cutoff: Float, dt: Float) -> Float {
        let tau = 1 / (2 * Float.pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    private static func lowPass(_ x: SIMD2<Float>, _ prev: SIMD2<Float>, alpha: Float) -> SIMD2<Float> {
        alpha * x + (1 - alpha) * prev
    }
}
