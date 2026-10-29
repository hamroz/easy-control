import Foundation
import HandTracking

public struct HandFeatures: Sendable, Equatable {
    /// 21 points in the canonical frame (see `HandNormalizer`).
    public var normalized: [SIMD2<Float>]
    /// Thumb...little.
    public var fingerExtended: [Bool]
    /// Thumb...little: false when the finger's middle joint or tip was detected below the confidence threshold
    /// (cut off by the frame edge, occluded), so its extension flag can't be trusted.
    public var fingerKnown: [Bool]
    /// Bend angle in radians at each finger's middle joint (thumb: MP; others: PIP). π = straight.
    public var bendAngles: [Float]
    /// Mean of wrist and the four MCPs, in image coordinates.
    public var palmCenter: SIMD2<Float>
    /// |wrist − middle MCP| in image coordinates; a proxy for distance from the camera.
    public var palmSize: Float
    public var isReliable: Bool

    /// 42 normalized coordinates + 5 extension flags (0/1) + 5 bend angles.
    public var vector: [Float] {
        normalized.flatMap { [$0.x, $0.y] } + fingerExtended.map { $0 ? 1 : 0 } + bendAngles
    }
}

public enum HandFeatureExtractor {
    static let requiredJoints: [JointName] = [.wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP]

    public static func extract(_ hand: Hand, minConfidence: Float = 0.3) -> HandFeatures {
        let points = HandNormalizer.normalize(hand)
        func p(_ j: JointName) -> SIMD2<Float> { points[j.rawValue] }
        func dist(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { let d = a - b; return (d * d).sum().squareRoot() }
        func angle(at mid: JointName, _ a: JointName, _ b: JointName) -> Float {
            let u = p(a) - p(mid), v = p(b) - p(mid)
            let denom = max(dist(u, .zero) * dist(v, .zero), 1e-6)
            return acos(min(max((u * v).sum() / denom, -1), 1))
        }

        var extended: [Bool] = []
        var known: [Bool] = []
        var bends: [Float] = []
        for (i, finger) in JointName.fingers.enumerated() {
            known.append(hand[finger[1]].confidence >= minConfidence && hand[finger[3]].confidence >= minConfidence)
            let bend = angle(at: finger[1], finger[0], finger[2])
            bends.append(bend)
            if i == 0 {
                extended.append(dist(p(.thumbTip), p(.indexMCP)) > 0.55)
            } else {
                let tipFar = dist(p(finger[3]), p(.wrist)) > 1.15 * dist(p(finger[1]), p(.wrist))
                extended.append(tipFar && bend > 2.4)
            }
        }

        let size = HandNormalizer.palmSize(hand)
        let confident = requiredJoints.allSatisfy { hand[$0].confidence >= minConfidence }
        let center = requiredJoints.reduce(SIMD2<Float>.zero) { $0 + hand[$1].position } / Float(requiredJoints.count)
        return HandFeatures(
            normalized: points,
            fingerExtended: extended,
            fingerKnown: known,
            bendAngles: bends,
            palmCenter: center,
            palmSize: size,
            isReliable: confident && size >= 0.02
        )
    }
}
