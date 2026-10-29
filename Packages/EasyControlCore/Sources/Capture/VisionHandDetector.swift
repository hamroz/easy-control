import CoreGraphics
import CoreVideo
import HandTracking
import Vision

/// Runs Apple Vision hand-pose detection and converts results to `HandFrame`s in our coordinate convention.
/// Call from one serial queue (the request object is reused).
public final class VisionHandDetector: @unchecked Sendable {
    private let request: VNDetectHumanHandPoseRequest

    public init(maxHands: Int = 2) {
        request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = maxHands
    }

    public func detect(_ buffer: CVPixelBuffer, timestamp: Double) throws -> HandFrame {
        try perform(VNImageRequestHandler(cvPixelBuffer: buffer, options: [:]), timestamp: timestamp)
    }

    public func detect(cgImage: CGImage, timestamp: Double) throws -> HandFrame {
        try perform(VNImageRequestHandler(cgImage: cgImage, options: [:]), timestamp: timestamp)
    }

    private func perform(_ handler: VNImageRequestHandler, timestamp: Double) throws -> HandFrame {
        try handler.perform([request])
        let hands = try (request.results ?? []).map(Self.hand(from:))
        return HandFrame(timestamp: timestamp, hands: hands)
    }

    static func hand(from observation: VNHumanHandPoseObservation) throws -> Hand {
        var joints = [HandTracking.Joint](repeating: HandTracking.Joint.missing, count: JointName.allCases.count)
        for (name, point) in try observation.recognizedPoints(.all) {
            joints[jointName(for: name).rawValue] = HandTracking.Joint(position: convert(point.location), confidence: point.confidence)
        }
        let chirality: HandTracking.Chirality = switch observation.chirality {
        case .left: .left
        case .right: .right
        default: .unknown
        }
        return Hand(chirality: chirality, joints: joints)
    }

    /// Vision: origin bottom-left, as the camera sees you. Ours: origin top-left, mirrored (+x = user's right).
    public static func convert(_ p: CGPoint) -> SIMD2<Float> {
        [Float(1 - p.x), Float(1 - p.y)]
    }

    static let visionJoints: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip,
    ]

    public static func jointName(for name: VNHumanHandPoseObservation.JointName) -> JointName {
        JointName(rawValue: visionJoints.firstIndex(of: name) ?? 0) ?? .wrist
    }
}
