import Signal

public enum InteractionMode: String, Codable, Sendable {
    case command, cursor
}

public enum EngagementState: Equatable, Sendable {
    case paused
    case idle
    /// Engagement recently ended; moving into a gesture pose resumes it with no hold.
    case standby
    case engaged(hand: HandID, mode: InteractionMode)
}

public struct HandObservation: Sendable {
    public var id: HandID
    public var pose: PoseClass
    public var palmSize: Float
    public var palmCenter: SIMD2<Float>
    /// False when the frame's landmarks were too uncertain to read a pose; such frames never count as a change.
    public var reliable: Bool

    public init(id: HandID, pose: PoseClass, palmSize: Float, palmCenter: SIMD2<Float>, reliable: Bool = true) {
        self.id = id
        self.pose = pose
        self.palmSize = palmSize
        self.palmCenter = palmCenter
        self.reliable = reliable
    }
}

/// Decides when gestures count.
///
/// - idle → engaged: open palm held `wakeHold`, or two/three fingers held `directEngageHold` (hand close enough).
/// - engaged → standby: the hand is gone for `handLostTimeout` or quiet for `idleTimeout`.
/// - standby → engaged: a hand that is new, or that genuinely changed pose (to another gesture, or relaxed for
///   `resumeRelax`), holds a gesture pose for `resumeHold` — never while typing. Unreliable frames don't count
///   as changes, so a still palm with tracking noise can't flap between states. standby → idle after
///   `standbyDuration`.
public struct EngagementController {
    private static let gesturePoses: Set<PoseClass> = [.openPalm, .two, .three]

    private let config: GestureConfig
    public private(set) var state: EngagementState = .idle

    private var holdStart: [HandID: Double] = [:]
    /// Hands present when engagement lapsed to idle; they must leave their gesture pose before they can wake it.
    private var spent: Set<HandID> = []
    private var relaxedSince: [HandID: Double] = [:]
    private var lastSeen: Double = 0
    private var lastActivity: Double = 0
    private var lastPose: PoseClass = .none
    private var standbyUntil: Double = 0
    private var previousPoses: [HandID: PoseClass] = [:]
    /// Standby bookkeeping, from reliable frames only.
    private struct Watch {
        var pose: PoseClass
        var since: Double
        var armed: Bool
    }
    private var watches: [HandID: Watch] = [:]

    public init(config: GestureConfig) {
        self.config = config
    }

    /// Returns the new state when it changes, otherwise nil.
    /// - Parameter suppressed: real keyboard/mouse input happened just now; typing must never wake the engine.
    public mutating func update(hands: [HandObservation], at t: Double, suppressed: Bool = false) -> EngagementState? {
        if state == .paused { return nil }
        let present = Dictionary(hands.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        defer { previousPoses = present.mapValues(\.pose) }
        releaseSpent(present, at: t)

        switch state {
        case .paused:
            return nil

        case .idle:
            if suppressed {
                holdStart = [:]
                return nil
            }
            for (id, hand) in present {
                guard Self.gesturePoses.contains(hand.pose), hand.palmSize >= config.minPalmSize, !spent.contains(id) else {
                    holdStart[id] = nil
                    continue
                }
                // A new hand or a changed pose starts the hold over.
                holdStart[id] = previousPoses[id] == hand.pose ? (holdStart[id] ?? t) : t
            }
            holdStart = holdStart.filter { present[$0.key] != nil }
            let ready = holdStart.compactMap { id, start -> HandObservation? in
                guard let hand = present[id] else { return nil }
                let hold = hand.pose == .openPalm ? config.wakeHold : config.directEngageHold
                return t - start + 1e-6 >= hold ? hand : nil
            }
            guard let winner = ready.max(by: { $0.palmSize < $1.palmSize }) else { return nil }
            return engage(winner, at: t)

        case .standby:
            if t > standbyUntil {
                state = .idle
                holdStart = [:]
                spent = Set(present.keys)
                return state
            }
            watch(present, at: t, suppressed: suppressed)
            guard !suppressed else { return nil }
            let resuming = present.values.filter { hand in
                guard let w = watches[hand.id] else { return false }
                return w.armed && Self.gesturePoses.contains(w.pose) && t - w.since + 1e-6 >= config.resumeHold
                    && hand.palmSize >= config.minPalmSize
            }
            guard let winner = resuming.max(by: { $0.palmSize < $1.palmSize }) else { return nil }
            return engage(winner, at: t)

        case .engaged(let id, _):
            if let hand = present[id] {
                lastSeen = t
                if hand.reliable, hand.pose != lastPose { // tracking noise is not activity
                    lastActivity = t
                    lastPose = hand.pose
                }
            }
            guard t - lastSeen > config.handLostTimeout || t - lastActivity > config.idleTimeout else { return nil }
            state = .standby
            standbyUntil = t + config.standbyDuration
            // Hands in view now must change pose before they can resume; hands that appear later are armed.
            watches = present.mapValues { Watch(pose: $0.pose, since: t, armed: false) }
            return state
        }
    }

    /// A spent hand may wake the engine again once it leaves the view or is reliably relaxed for `resumeRelax`;
    /// a single noisy frame doesn't count.
    private mutating func releaseSpent(_ present: [HandID: HandObservation], at t: Double) {
        for id in spent {
            guard let hand = present[id] else {
                spent.remove(id)
                relaxedSince[id] = nil
                continue
            }
            guard hand.reliable else { continue }
            if Self.gesturePoses.contains(hand.pose) {
                relaxedSince[id] = nil
            } else {
                let since = relaxedSince[id] ?? t
                relaxedSince[id] = since
                if t - since >= config.resumeRelax {
                    spent.remove(id)
                    relaxedSince[id] = nil
                }
            }
        }
    }

    /// Tracks each hand's reliable pose in standby and arms it once it has genuinely changed.
    private mutating func watch(_ present: [HandID: HandObservation], at t: Double, suppressed: Bool) {
        watches = watches.filter { present[$0.key] != nil || t - $0.value.since < config.handLostTimeout }
        for (id, hand) in present where hand.reliable {
            guard var w = watches[id] else {
                watches[id] = Watch(pose: hand.pose, since: t, armed: true) // a hand that came (back) into view
                continue
            }
            if hand.pose != w.pose {
                let wasRelaxedLongEnough = !Self.gesturePoses.contains(w.pose) && t - w.since >= config.resumeRelax
                let switchedGesture = Self.gesturePoses.contains(w.pose) && Self.gesturePoses.contains(hand.pose)
                w.armed = w.armed || wasRelaxedLongEnough || switchedGesture
                w.pose = hand.pose
                w.since = t
            }
            if suppressed { w.since = t } // the hold starts only once typing stops
            watches[id] = w
        }
    }

    private mutating func engage(_ hand: HandObservation, at t: Double) -> EngagementState {
        state = .engaged(hand: hand.id, mode: .command)
        holdStart = [:]
        lastSeen = t
        lastActivity = t
        lastPose = hand.pose
        return state
    }

    /// A recognized gesture keeps engagement alive.
    public mutating func noteActivity(at t: Double) {
        if case .engaged = state { lastActivity = t }
    }

    public mutating func setPaused(_ paused: Bool, at t: Double) -> EngagementState? {
        if paused {
            guard state != .paused else { return nil }
            state = .paused
        } else {
            guard state == .paused else { return nil }
            state = .idle
        }
        holdStart = [:]
        spent = []
        return state
    }
}
