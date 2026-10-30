import Foundation
import HandTracking

/// Maps a hand into a canonical frame: wrist at the origin, palm size 1, wrist→middle MCP pointing −y,
/// and left hands mirrored onto right hands so one classifier serves both.
public enum HandNormalizer {
    /// Joint position with x scaled by the image aspect ratio, so both axes share one unit (image heights).
    public static func isotropic(_ hand: Hand, _ joint: JointName) -> SIMD2<Float> {
        let p = hand[joint].position
        return [p.x * hand.aspectRatio, p.y]
    }

    /// |wrist − middle MCP|, in image heights.
    public static func palmSize(_ hand: Hand) -> Float {
        let d = isotropic(hand, .middleMCP) - isotropic(hand, .wrist)
        return (d * d).sum().squareRoot()
    }

    public static func normalize(_ hand: Hand) -> [SIMD2<Float>] {
        let wrist = isotropic(hand, .wrist)
        let axis = isotropic(hand, .middleMCP) - wrist
        let size = max(palmSize(hand), 1e-6)
        // Rotate so `axis` maps onto (0, -1).
        let angle = atan2(axis.x, -axis.y)
        let (c, s) = (cos(angle), sin(angle))
        let mirror: Float = hand.chirality == .left ? -1 : 1
        return JointName.allCases.map { name in
            let p = (isotropic(hand, name) - wrist) / size
            let r = SIMD2<Float>(c * p.x + s * p.y, -s * p.x + c * p.y)
            return [mirror * r.x, r.y]
        }
    }
}
