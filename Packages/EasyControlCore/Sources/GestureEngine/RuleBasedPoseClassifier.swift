import Signal

/// Bootstrap classifier from finger-extension flags. Replaced by the Core ML classifier in M3.
public struct RuleBasedPoseClassifier: PoseClassifying {
    public let name = "rules"

    public init() {}

    public func classify(_ features: HandFeatures) -> [PoseClass: Float] {
        guard features.isReliable, !features.fingerKnown.contains(false) else { return [.none: 1] }
        let e = features.fingerExtended
        let fingers = Array(e.dropFirst()) // index, middle, ring, little
        let pose: PoseClass = switch (e[0], fingers) {
        case (true, [true, true, true, true]): .openPalm
        case (_, [true, true, false, false]): .two
        case (_, [true, false, false, false]): .point
        case (_, [true, true, true, false]): .three
        case (_, [false, false, false, false]): .fist
        default: .none
        }
        return [pose: 1]
    }
}
