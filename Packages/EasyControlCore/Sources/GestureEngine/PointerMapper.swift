import CoreGraphics

/// Hand movement → pointer pixels, like a trackpad: slow movement is precise, fast movement crosses the screen.
public struct PointerMapper: Sendable {
    public var speedMultiplier: Double
    private static let precisionSpeed = 0.15, precisionGain = 0.6
    private static let fullSpeed = 1.2, fullGain = 2.5

    public init(speedMultiplier: Double = 1) {
        self.speedMultiplier = speedMultiplier
    }

    /// - Parameter speed: hand speed in frame heights per second.
    public func gain(speed: Double) -> Double {
        if speed <= Self.precisionSpeed { return Self.precisionGain }
        if speed >= Self.fullSpeed { return Self.fullGain }
        let f = (speed - Self.precisionSpeed) / (Self.fullSpeed - Self.precisionSpeed)
        return Self.precisionGain + f * (Self.fullGain - Self.precisionGain)
    }

    /// - Parameter handDelta: isotropic frame heights; +y down, matching screen coordinates.
    public func pixels(handDelta: SIMD2<Float>, speed: Double, screenHeight: Double) -> SIMD2<Double> {
        let k = gain(speed: speed) * speedMultiplier * screenHeight
        return [Double(handDelta.x) * k, Double(handDelta.y) * k]
    }

    /// The nearest point inside any display (global coordinates, origin top-left of the main display).
    public static func clamp(_ p: CGPoint, to displays: [CGRect]) -> CGPoint {
        guard !displays.isEmpty else { return p }
        let candidates = displays.map { d in
            CGPoint(x: min(max(p.x, d.minX), d.maxX - 1), y: min(max(p.y, d.minY), d.maxY - 1))
        }
        return candidates.min { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) }!
    }
}
