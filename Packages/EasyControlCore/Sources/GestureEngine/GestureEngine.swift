import HandTracking
import Signal

public struct HandDebugInfo: Sendable {
    public var id: HandID
    public var pose: PoseClass
    public var probabilities: [PoseClass: Float]
    public var features: HandFeatures
    /// Smoothed joints (pointer, overlay).
    public var hand: Hand
    /// Unsmoothed joints: pinch uses these, since smoothing lags a quick finger closure.
    public var rawHand: Hand
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
    private let touchConfig: TouchConfig
    private var touch: TouchRecognizer
    private var pinch: PinchDetector
    private var dock: DockSwipeRecognizer
    private var threeEvidence: [(t: Double, p: Float)] = []
    private var threeOn = false
    private var touchHand: HandID?
    private var activityAnchor: SIMD2<Float>?
    /// Exclusive lock: after a scroll or drag ends, nothing else starts until then.
    private var settleUntil: Double = -.infinity
    private var lastTimestamp: Double = 0
    public private(set) var snapshot = EngineSnapshot()

    public init(config: GestureConfig = .default, touchConfig: TouchConfig = .default,
                classifier: any PoseClassifying = RuleBasedPoseClassifier()) {
        self.config = config
        self.touchConfig = touchConfig
        self.classifier = classifier
        engagement = EngagementController(config: config)
        touch = TouchRecognizer(config: touchConfig, gesture: config)
        pinch = PinchDetector(config: touchConfig)
        dock = DockSwipeRecognizer(config: config)
    }

    /// - Parameter lastUserInput: host time of the most recent real keyboard/mouse input, if any.
    public func process(_ frame: HandFrame, lastUserInput: Double?) -> [GestureEvent] {
        let t = frame.timestamp
        lastTimestamp = t
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
                                       rawHand: tracked.raw,
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
            events += command(hand: infos.first { $0.id == id }, id: id, at: t)
            if events.contains(where: isActivity) { engagement.noteActivity(at: t) }
        }

        snapshot = EngineSnapshot(state: engagement.state, hands: infos, lastEvent: events.last ?? snapshot.lastEvent,
                                  suppressed: suppressed, classifierName: classifier.name)
        return events
    }

    /// The engaged hand in command mode: three fingers drive the Dock; otherwise the hand is a pointer and a
    /// pinch is a touch. A running touch (press, scroll, drag) or Dock drag owns the hand until it ends.
    private func command(hand: HandDebugInfo?, id: HandID, at t: Double) -> [GestureEvent] {
        if touchHand != id {
            pinch = PinchDetector(config: touchConfig)
            touchHand = id
        }
        let reliable = hand?.features.isReliable == true
        let aspect = hand?.hand.aspectRatio ?? 1
        let center = reliable ? hand?.features.palmCenter : nil

        threeEvidence.append((t, reliable ? hand?.probabilities[.three] ?? 0 : 0))
        threeEvidence.removeAll { t - $0.t > config.threeWindow }
        let mean = threeEvidence.reduce(Float(0)) { $0 + $1.p } / Float(max(threeEvidence.count, 1))
        threeOn = threeOn ? mean >= config.threeExit : mean > config.threeEnter

        var events: [GestureEvent] = []
        let settled = t >= settleUntil
        if dock.isActive || (threeOn && !touch.isBusy && settled) {
            events += touch.cancel(at: t)
            if let e = dock.update(pose: threeOn ? .three : .none, palmCenter: center, aspect: aspect, at: t) { events.append(e) }
        } else {
            _ = dock.update(pose: .none, palmCenter: center, aspect: aspect, at: t)
            let anchor: SIMD2<Float>? = reliable ? hand.map { HandNormalizer.isotropic($0.rawHand, .indexMCP) } : nil
            let pointer: SIMD2<Float>? = reliable ? hand.map { HandNormalizer.isotropic($0.hand, .indexMCP) } : nil
            let reading = hand.flatMap { pinch.update($0.rawHand, at: t) }
            events += touch.update(anchor: anchor, pointer: pointer, pinch: reading, at: t)
        }
        if events.contains(where: Self.endsContinuous) { settleUntil = t + config.continuousSettle }
        return events
    }

    private static func endsContinuous(_ e: GestureEvent) -> Bool {
        if case .continuous(_, let phase, _) = e { return phase == .ended || phase == .cancelled }
        return false
    }

    public func setPaused(_ paused: Bool, at t: Double) -> [GestureEvent] {
        guard let newState = engagement.setPaused(paused, at: t) else { return [] }
        snapshot.state = newState
        return endGestures() + [.engagement(newState)]
    }

    private func endGestures() -> [GestureEvent] {
        touch.cancel(at: lastTimestamp) + [dock.cancel()].compactMap { $0 }
    }

    /// Gestures, clicks, and moving the pointer keep engagement alive; a still hand doesn't.
    private func isActivity(_ e: GestureEvent) -> Bool {
        switch e {
        case .discrete, .continuous, .button: return true
        case .pointerTrack(let position, _):
            guard let last = activityAnchor else {
                activityAnchor = position
                return false
            }
            let d = position - last
            guard (d * d).sum().squareRoot() >= config.pointerActivityDistance else { return false }
            activityAnchor = position
            return true
        case .pointerLift, .engagement: return false
        }
    }
}
