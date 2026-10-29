import HandTracking
import Signal

public struct HandDebugInfo: Sendable {
    public var id: HandID
    public var pose: PoseClass
    public var probabilities: [PoseClass: Float]
    public var features: HandFeatures
    /// Smoothed joints.
    public var hand: Hand
    /// Unsmoothed palm centre: velocity-based detectors use it so smoothing lag doesn't hide fast motion.
    public var rawPalmCenter: SIMD2<Float>
}

public struct EngineSnapshot: Sendable {
    public var state: EngagementState = .idle
    public var hands: [HandDebugInfo] = []
    public var lastEvent: GestureEvent?
    public var suppressed = false
}

/// Landmarks in, gesture events out. Pure and deterministic given frame timestamps, so it can be replay-tested.
/// Not thread-safe: own it from a single serial queue.
public final class GestureEngine {
    private let config: GestureConfig
    private let classifier: any PoseClassifying
    private let tracker = HandIdentityTracker()
    private var stabilizers: [HandID: PoseStabilizer] = [:]
    private var engagement: EngagementController
    private var scroll: ScrollRecognizer
    private var swipe: SwipeRecognizer
    public private(set) var snapshot = EngineSnapshot()

    public init(config: GestureConfig = .default, classifier: any PoseClassifying = RuleBasedPoseClassifier()) {
        self.config = config
        self.classifier = classifier
        engagement = EngagementController(config: config)
        scroll = ScrollRecognizer(config: config)
        swipe = SwipeRecognizer(config: config)
    }

    /// - Parameter lastUserInput: host time of the most recent real keyboard/mouse input, if any.
    public func process(_ frame: HandFrame, lastUserInput: Double?) -> [GestureEvent] {
        let t = frame.timestamp
        var events: [GestureEvent] = []

        // Per-hand perception.
        var infos: [HandDebugInfo] = []
        for tracked in tracker.update(frame) {
            let features = HandFeatureExtractor.extract(tracked.hand)
            let probs = classifier.classify(features)
            var stabilizer = stabilizers[tracked.id] ?? PoseStabilizer(config: config)
            let stable = stabilizer.update(probs)
            stabilizers[tracked.id] = stabilizer
            // Unreliable frames never drive gestures, even while the stabilizer is still holding a pose.
            let pose = features.isReliable ? stable : .none
            infos.append(HandDebugInfo(id: tracked.id, pose: pose, probabilities: probs, features: features, hand: tracked.hand,
                                       rawPalmCenter: HandIdentityTracker.palmCenter(tracked.raw)))
        }
        let present = Set(infos.map(\.id))
        stabilizers = stabilizers.filter { present.contains($0.key) }

        let suppressed = lastUserInput.map { t - $0 < config.inputSuppression } ?? false
        var observations = infos.map { HandObservation(id: $0.id, pose: $0.pose, palmSize: $0.features.palmSize, palmCenter: $0.features.palmCenter) }
        if suppressed, engagement.state == .idle { observations = [] } // typing never wakes the engine

        if let newState = engagement.update(hands: observations, at: t) {
            if case .engaged = newState {} else { events += endGestures() }
            events.append(.engagement(newState))
        }

        if suppressed {
            events += endGestures()
        } else if case .engaged(let id, .command) = engagement.state {
            let hand = infos.first { $0.id == id }
            let pose = hand?.pose ?? .none
            let reliable = hand?.features.isReliable == true
            let center = reliable ? hand?.features.palmCenter : nil
            if let e = scroll.update(pose: pose, palmCenter: center, at: t) { events.append(e) }
            if scroll.isActive {
                swipe.reset()
            } else if let e = swipe.update(pose: pose, palmCenter: reliable ? hand?.rawPalmCenter : nil, at: t) {
                events.append(e)
            }
            if events.contains(where: Self.isActivity) { engagement.noteActivity(at: t) }
        }

        snapshot = EngineSnapshot(state: engagement.state, hands: infos,
                                  lastEvent: events.last ?? snapshot.lastEvent, suppressed: suppressed)
        return events
    }

    public func setPaused(_ paused: Bool, at t: Double) -> [GestureEvent] {
        guard let newState = engagement.setPaused(paused, at: t) else { return [] }
        snapshot.state = newState
        return endGestures() + [.engagement(newState)]
    }

    private func endGestures() -> [GestureEvent] {
        swipe.reset()
        return scroll.cancel().map { [$0] } ?? []
    }

    private static func isActivity(_ e: GestureEvent) -> Bool {
        switch e {
        case .discrete, .continuous, .cursor: true
        case .engagement: false
        }
    }
}
