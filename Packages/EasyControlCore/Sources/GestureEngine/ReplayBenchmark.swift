import HandTracking

public struct ReplayStats: Sendable, Equatable {
    public var duration: Double
    public var engagements: Int
    public var discreteEvents: Int
    public var scrollsBegan: Int
    public var clicks: Int = 0
    public var drags: Int = 0
    /// Edge glides started and seconds spent gliding: pointer motion the hand didn't make directly (not counted
    /// as actions, but a glide nobody meant is a pointer that wanders off).
    public var glides: Int = 0
    public var glideSeconds: Double = 0
    /// (discrete events + scrolls/Dock drags begun + clicks + drags) per hour. On a normal-use recording every
    /// action is a false one.
    public var actionsPerHour: Double
}

/// Replays a landmark recording through the engine and counts what it would have done.
public enum ReplayBenchmark {
    /// - Parameter forceEngaged: treat any visible hand as engaged (whenever the engine isn't), to measure what an
    ///   engaged hand that isn't trying to do anything would trigger.
    public static func run(_ frames: [HandFrame], engine: GestureEngine, forceEngaged: Bool = false) -> ReplayStats {
        var stats = ReplayStats(duration: 0, engagements: 0, discreteEvents: 0, scrollsBegan: 0, actionsPerHour: 0)
        var glidingSince: Double?
        for frame in frames {
            let events = engine.process(frame, lastUserInput: nil)
            if forceEngaged { engine.forceEngageLargestHand(at: frame.timestamp) }
            for event in events {
                switch event {
                case .engagement(.engaged): stats.engagements += 1
                case .discrete: stats.discreteEvents += 1
                case .continuous(_, .began, _): stats.scrollsBegan += 1
                case .button(_, .click, _): stats.clicks += 1
                case .button(_, .down, _): stats.drags += 1
                case .pointerGlide(let v, let t):
                    if v != .zero, glidingSince == nil { glidingSince = t; stats.glides += 1 }
                    if v == .zero, let since = glidingSince { stats.glideSeconds += t - since; glidingSince = nil }
                default: break
                }
            }
        }
        if let first = frames.first, let last = frames.last {
            stats.duration = last.timestamp - first.timestamp
            if let since = glidingSince { stats.glideSeconds += last.timestamp - since }
        }
        let actions = Double(stats.discreteEvents + stats.scrollsBegan + stats.clicks + stats.drags)
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
