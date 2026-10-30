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

    public init(id: HandID, pose: PoseClass, palmSize: Float, palmCenter: SIMD2<Float>) {
        self.id = id
        self.pose = pose
        self.palmSize = palmSize
        self.palmCenter = palmCenter
    }
}

/// Decides when gestures count.
///
/// - idle → engaged: open palm held `wakeHold`, or two/three fingers held `directEngageHold` (hand close enough).
/// - engaged → standby: the hand is gone for `handLostTimeout` or quiet for `idleTimeout`.
/// - standby → engaged: any hand moving *into* a gesture pose (a still pose doesn't count, so a raised palm
///   can't flap between states); standby → idle after `standbyDuration`.
public struct EngagementController {
    private static let gesturePoses: Set<PoseClass> = [.openPalm, .two, .three]

    private let config: GestureConfig
    public private(set) var state: EngagementState = .idle

    private var holdStart: [HandID: Double] = [:]
    /// Hands present when engagement lapsed to idle; they must leave their gesture pose before they can wake it.
    private var spent: Set<HandID> = []
    private var lastSeen: Double = 0
    private var lastActivity: Double = 0
    private var lastPose: PoseClass = .none
    private var standbyUntil: Double = 0
    private var previousPoses: [HandID: PoseClass] = [:]

    public init(config: GestureConfig) {
        self.config = config
    }

    /// Returns the new state when it changes, otherwise nil.
    public mutating func update(hands: [HandObservation], at t: Double) -> EngagementState? {
        if state == .paused { return nil }
        let present = Dictionary(hands.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        defer { previousPoses = present.mapValues(\.pose) }
        spent = spent.filter { present[$0].map { Self.gesturePoses.contains($0.pose) } ?? false }

        switch state {
        case .paused:
            return nil

        case .idle:
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
            let resuming = present.values.filter { hand in
                Self.gesturePoses.contains(hand.pose) && hand.palmSize >= config.minPalmSize
                    && previousPoses[hand.id] != hand.pose
            }
            guard let winner = resuming.max(by: { $0.palmSize < $1.palmSize }) else { return nil }
            return engage(winner, at: t)

        case .engaged(let id, _):
            if let hand = present[id] {
                lastSeen = t
                if hand.pose != lastPose {
                    lastActivity = t
                    lastPose = hand.pose
                }
            }
            guard t - lastSeen > config.handLostTimeout || t - lastActivity > config.idleTimeout else { return nil }
            state = .standby
            standbyUntil = t + config.standbyDuration
            return state
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
