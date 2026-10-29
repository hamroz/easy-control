import Foundation
import HandTracking

public enum SyntheticPose: Sendable {
    case openPalm, fist, point, two, three

    /// Which fingers (thumb...little) are extended.
    var extended: [Bool] {
        switch self {
        case .openPalm: [true, true, true, true, true]
        case .fist: [false, false, false, false, false]
        case .point: [false, true, false, false, false]
        case .two: [false, true, true, false, false]
        case .three: [false, true, true, true, false]
        }
    }
}

/// Builds plausible 21-joint hands for tests. Coordinates follow the mirrored, top-left convention.
public enum SyntheticHand {
    public static func make(
        _ pose: SyntheticPose,
        center: SIMD2<Float> = [0.5, 0.5],
        palmSize: Float = 0.12,
        chirality: Chirality = .right,
        confidence: Float = 1
    ) -> Hand {
        // Build a right hand around the origin (palm centre), then mirror for left and translate.
        let s = palmSize
        var points = [SIMD2<Float>](repeating: .zero, count: 21)
        points[JointName.wrist.rawValue] = [0, s]
        let extended = pose.extended
        let segment = 0.35 * s

        // Fingers index...little: MCPs across the top of the palm. For a right hand seen mirrored,
        // the thumb is on the user's left (-x), so index sits at -x and little at +x.
        let mcpX: [Float] = [-0.4 * s, -0.13 * s, 0.13 * s, 0.4 * s]
        for (i, finger) in JointName.fingers.dropFirst().enumerated() {
            let mcp = SIMD2<Float>(mcpX[i], 0)
            points[finger[0].rawValue] = mcp
            if extended[i + 1] {
                for k in 1...3 { points[finger[k].rawValue] = mcp + [0, -segment * Float(k)] }
            } else {
                points[finger[1].rawValue] = mcp + [0, -0.2 * s]
                points[finger[2].rawValue] = mcp + [0, -0.05 * s]
                points[finger[3].rawValue] = mcp + [0, 0.15 * s]
            }
        }

        // Thumb: CMC near the wrist on the -x side.
        let thumb = JointName.fingers[0]
        let cmc = SIMD2<Float>(-0.35 * s, 0.7 * s)
        points[thumb[0].rawValue] = cmc
        if extended[0] {
            let dir = SIMD2<Float>(-0.7071, -0.7071)
            for k in 1...3 { points[thumb[k].rawValue] = cmc + dir * (0.3 * s * Float(k)) }
        } else {
            points[thumb[1].rawValue] = cmc + [0.1 * s, -0.25 * s]
            points[thumb[2].rawValue] = cmc + [0.25 * s, -0.4 * s]
            points[thumb[3].rawValue] = cmc + [0.4 * s, -0.45 * s]
        }

        let mirror: Float = chirality == .left ? -1 : 1
        let joints = points.map { p in
            Joint(position: [center.x + mirror * p.x, center.y + p.y], confidence: confidence)
        }
        return Hand(chirality: chirality, joints: joints)
    }
}
