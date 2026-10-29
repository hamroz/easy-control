import Signal

public enum PoseClass: String, CaseIterable, Codable, Sendable {
    case openPalm, fist, point, two, three, pinch, ok, thumbsUp, thumbsDown, none
}

public protocol PoseClassifying {
    /// Per-class probabilities summing to 1.
    func classify(_ features: HandFeatures) -> [PoseClass: Float]
}
