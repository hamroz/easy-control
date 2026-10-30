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
    public var classifierName = ""
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
    private var dock: DockSwipeRecognizer
    /// Exclusive lock: after a scroll or drag ends, nothing else starts until then.
    private var settleUntil: Double = -.infinity
    public private(set) var snapshot = EngineSnapshot()

    public init(config: GestureConfig = .default, classifier: any PoseClassifying = RuleBasedPoseClassifier()) {
        self.config = config
        self.classifier = classifier
        engagement = EngagementController(config: config)
        scroll = ScrollRecognizer(config: config)
        swipe = SwipeRecognizer(config: config)
        dock = DockSwipeRecognizer(config: config)
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
        let active = tracker.activeIDs
        stabilizers = stabilizers.filter { active.contains($0.key) }

        let suppressed = lastUserInput.map { t - $0 < config.inputSuppression } ?? false
        let observations = infos.map {
            HandObservation(id: $0.id, pose: $0.pose, palmSize: $0.features.palmSize, palmCenter: $0.features.palmCenter,
                            reliable: $0.features.isReliable)
        }
        if let newState = engagement.update(hands: observations, at: t, suppressed: suppressed) {
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
            let aspect = hand?.hand.aspectRatio ?? 1
            // A running continuous gesture owns the hand; a new one may start only when none is running
            // and the previous one has settled, so a misread pose can't hand a scroll over to a Space swipe.
            let settled = t >= settleUntil
            let scrollPose = scroll.isActive || (settled && !dock.isActive) ? pose : .none
            let dockPose = dock.isActive || (settled && !scroll.isActive) ? pose : .none
            for e in [scroll.update(pose: scrollPose, palmCenter: center, aspect: aspect, at: t),
                      dock.update(pose: dockPose, palmCenter: center, aspect: aspect, at: t)].compactMap({ $0 }) {
                events.append(e)
                if case .continuous(_, let phase, _) = e, phase == .ended || phase == .cancelled {
                    settleUntil = t + config.continuousSettle
                }
            }
            if scroll.isActive || dock.isActive || t < settleUntil {
                swipe.reset()
            } else if let e = swipe.update(pose: pose, palmCenter: reliable ? hand?.rawPalmCenter : nil, aspect: aspect, at: t) {
                events.append(e)
            }
            if events.contains(where: Self.isActivity) { engagement.noteActivity(at: t) }
        }

        snapshot = EngineSnapshot(state: engagement.state, hands: infos, lastEvent: events.last ?? snapshot.lastEvent,
                                  suppressed: suppressed, classifierName: classifier.name)
        return events
    }

    public func setPaused(_ paused: Bool, at t: Double) -> [GestureEvent] {
        guard let newState = engagement.setPaused(paused, at: t) else { return [] }
        snapshot.state = newState
        return endGestures() + [.engagement(newState)]
    }

    private func endGestures() -> [GestureEvent] {
        swipe.reset()
        return [scroll.cancel(), dock.cancel()].compactMap { $0 }
    }

    private static func isActivity(_ e: GestureEvent) -> Bool {
        switch e {
        case .discrete, .continuous, .cursor: true
        case .engagement: false
        }
    }
}
