public enum Chirality: String, Codable, Sendable {
    case left, right, unknown
}

/// A joint position in normalized image coordinates.
///
/// Convention: origin top-left, x mirrored so +x is the user's right, +y is down, range 0...1.
public struct Joint: Codable, Sendable, Equatable {
    public var position: SIMD2<Float>
    public var confidence: Float

    public init(position: SIMD2<Float>, confidence: Float) {
        self.position = position
        self.confidence = confidence
    }

    public static let missing = Joint(position: .zero, confidence: 0)
}

public struct Hand: Codable, Sendable, Equatable {
    public var chirality: Chirality
    /// Exactly 21 joints, indexed by `JointName.rawValue`. Undetected joints have confidence 0.
    public var joints: [Joint]
    /// Width / height of the image the joints were normalized against. x and y are normalized separately,
    /// so shape features must scale x by this to be the same for a 4:3 webcam and a 3:4 photo.
    public var aspectRatio: Float

    public init(chirality: Chirality, joints: [Joint], aspectRatio: Float = 1) {
        precondition(joints.count == JointName.allCases.count, "a hand has 21 joints")
        self.chirality = chirality
        self.joints = joints
        self.aspectRatio = aspectRatio
    }

    private enum CodingKeys: String, CodingKey { case chirality, joints, aspectRatio }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chirality = try c.decode(Chirality.self, forKey: .chirality)
        joints = try c.decode([Joint].self, forKey: .joints)
        aspectRatio = try c.decodeIfPresent(Float.self, forKey: .aspectRatio) ?? 1 // recordings before M3
    }

    public subscript(_ name: JointName) -> Joint {
        get { joints[name.rawValue] }
        set { joints[name.rawValue] = newValue }
    }
}

public struct HandFrame: Codable, Sendable, Equatable {
    /// Seconds on the host clock.
    public var timestamp: Double
    public var hands: [Hand]

    public init(timestamp: Double, hands: [Hand]) {
        self.timestamp = timestamp
        self.hands = hands
    }
}

/// Anything that produces hand frames: the camera + Vision, a recording replay, or another platform's detector.
public protocol HandLandmarkSource: Sendable {
    var frames: AsyncStream<HandFrame> { get }
}

extension Hand {
    /// Mean of the wrist and the four finger MCPs: a stable point that doesn't move when fingers do.
    public var palmCenter: SIMD2<Float> {
        let joints: [JointName] = [.wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP]
        return joints.reduce(SIMD2<Float>.zero) { $0 + self[$1].position } / Float(joints.count)
    }
}

extension Hand {
    /// The same joints with the left/right guess swapped (training augmentation against chirality errors).
    public func withFlippedChirality() -> Hand {
        var out = self
        switch chirality {
        case .left: out.chirality = .right
        case .right: out.chirality = .left
        case .unknown: break
        }
        return out
    }
}
