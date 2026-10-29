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

    public init(chirality: Chirality, joints: [Joint]) {
        precondition(joints.count == JointName.allCases.count, "a hand has 21 joints")
        self.chirality = chirality
        self.joints = joints
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
