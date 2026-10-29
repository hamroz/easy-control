/// Turns noisy per-frame probabilities into a stable pose with hysteresis.
public struct PoseStabilizer {
    private let config: GestureConfig
    public private(set) var current: PoseClass = .none
    private var candidate: PoseClass?
    private var candidateFrames = 0

    public init(config: GestureConfig) {
        self.config = config
    }

    public mutating func update(_ probs: [PoseClass: Float]) -> PoseClass {
        let (top, topP) = probs.max { $0.value < $1.value }.map { ($0.key, $0.value) } ?? (.none, 1)

        // Track a competing pose that is confidently present.
        if top != current, topP >= config.poseEnter {
            candidateFrames = candidate == top ? candidateFrames + 1 : 1
            candidate = top
        } else {
            candidate = nil
            candidateFrames = 0
        }

        if let c = candidate, candidateFrames >= config.poseEnterFrames {
            current = c
            candidate = nil
            candidateFrames = 0
        } else if current != .none, (probs[current] ?? 0) < config.poseExit, candidate == nil {
            // Current pose faded with no confident competitor: drop to none now.
            current = .none
        }
        return current
    }
}
