import Foundation

/// Spreads deltas that arrive at camera rate (30 Hz) over display frames (120 Hz): each frame releases a share
/// of what is pending, so motion glides instead of jumping once per camera frame.
struct RateSmoother {
    private let tau: Double
    private(set) var pending: SIMD2<Double> = .zero

    init(tau: Double = 0.025) {
        self.tau = tau
    }

    mutating func add(_ v: SIMD2<Double>) {
        pending += v
    }

    mutating func take(dt: Double) -> SIMD2<Double> {
        var out = pending * (1 - exp(-max(dt, 0) / tau))
        if ((pending - out) * (pending - out)).sum() < 1e-12 { out = pending }
        pending -= out
        return out
    }

    mutating func flush() -> SIMD2<Double> {
        defer { pending = .zero }
        return pending
    }

    mutating func clear() {
        pending = .zero
    }

    var isEmpty: Bool { (pending * pending).sum() < 1e-12 }
}
