import Signal

public enum PoseClass: String, CaseIterable, Codable, Sendable {
    case openPalm, fist, point, two, three, pinch, ok, thumbsUp, thumbsDown, none
}

public protocol PoseClassifying {
    /// Short identifier shown in the debug window ("rules", "coreml").
    var name: String { get }
    /// Per-class probabilities summing to 1.
    func classify(_ features: HandFeatures) -> [PoseClass: Float]
}
