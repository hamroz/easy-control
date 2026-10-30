import HandTracking

public struct ReplayStats: Sendable, Equatable {
    public var duration: Double
    public var engagements: Int
    public var discreteEvents: Int
    public var scrollsBegan: Int
    /// (discrete events + scrolls begun) per hour. On a normal-use recording every action is a false one.
    public var actionsPerHour: Double
}

/// Replays a landmark recording through the engine and counts what it would have done.
public enum ReplayBenchmark {
    public static func run(_ frames: [HandFrame], engine: GestureEngine) -> ReplayStats {
        var stats = ReplayStats(duration: 0, engagements: 0, discreteEvents: 0, scrollsBegan: 0, actionsPerHour: 0)
        for frame in frames {
            for event in engine.process(frame, lastUserInput: nil) {
                switch event {
                case .engagement(.engaged): stats.engagements += 1
                case .discrete: stats.discreteEvents += 1
                case .continuous(_, .began, _): stats.scrollsBegan += 1
                default: break
                }
            }
        }
        if let first = frames.first, let last = frames.last { stats.duration = last.timestamp - first.timestamp }
        let actions = Double(stats.discreteEvents + stats.scrollsBegan)
        stats.actionsPerHour = stats.duration > 0 ? actions / stats.duration * 3600 : 0
        return stats
    }
}

extension ReplayBenchmark {
    /// Stable pose of the most confident hand in each frame that has one (how the engine read a recording).
    public static func poseHistogram(_ frames: [HandFrame], engine: GestureEngine) -> [PoseClass: Int] {
        var histogram: [PoseClass: Int] = [:]
        for frame in frames {
            _ = engine.process(frame, lastUserInput: nil)
            guard let hand = engine.snapshot.hands.max(by: { $0.features.palmSize < $1.features.palmSize }) else { continue }
            histogram[hand.pose, default: 0] += 1
        }
        return histogram
    }
}
