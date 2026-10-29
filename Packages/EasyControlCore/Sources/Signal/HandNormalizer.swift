import Foundation
import HandTracking

/// Maps a hand into a canonical frame: wrist at the origin, palm size 1, wrist→middle MCP pointing −y,
/// and left hands mirrored onto right hands so one classifier serves both.
public enum HandNormalizer {
    /// |wrist − middle MCP| in the hand's own coordinates.
    public static func palmSize(_ hand: Hand) -> Float {
        let d = hand[.middleMCP].position - hand[.wrist].position
        return (d * d).sum().squareRoot()
    }

    public static func normalize(_ hand: Hand) -> [SIMD2<Float>] {
        let wrist = hand[.wrist].position
        let axis = hand[.middleMCP].position - wrist
        let size = max(palmSize(hand), 1e-6)
        // Rotate so `axis` maps onto (0, -1).
        let angle = atan2(axis.x, -axis.y)
        let (c, s) = (cos(angle), sin(angle))
        let mirror: Float = hand.chirality == .left ? -1 : 1
        return hand.joints.map { joint in
            let p = (joint.position - wrist) / size
            let r = SIMD2<Float>(c * p.x + s * p.y, -s * p.x + c * p.y)
            return [mirror * r.x, r.y]
        }
    }
}
