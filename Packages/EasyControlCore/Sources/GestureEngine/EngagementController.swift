import Signal

public enum InteractionMode: String, Codable, Sendable {
    case command, cursor
}

public enum EngagementState: Equatable, Sendable {
    case paused
    case idle
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

/// Decides when gestures count: an open palm held briefly engages; idleness or losing the hand disengages.
public struct EngagementController {
    private let config: GestureConfig
    public private(set) var state: EngagementState = .idle

    private var holdStart: [HandID: Double] = [:]
    /// Hands that were present at disengagement; they must leave the open-palm pose before they can wake again.
    private var spent: Set<HandID> = []
    private var lastSeen: Double = 0
    private var lastActivity: Double = 0
    private var lastPose: PoseClass = .none

    public init(config: GestureConfig) {
        self.config = config
    }

    /// Returns the new state when it changes, otherwise nil.
    public mutating func update(hands: [HandObservation], at t: Double) -> EngagementState? {
        if state == .paused { return nil }
        let present = Dictionary(hands.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        spent = spent.filter { present[$0]?.pose == .openPalm }

        switch state {
        case .paused:
            return nil

        case .idle:
            for (id, hand) in present {
                if hand.pose == .openPalm, hand.palmSize >= config.minPalmSize, !spent.contains(id) {
                    holdStart[id] = holdStart[id] ?? t
                } else {
                    holdStart[id] = nil
                }
            }
            holdStart = holdStart.filter { present[$0.key] != nil }
            let ready = holdStart.filter { t - $0.value + 1e-6 >= config.wakeHold }.compactMap { present[$0.key] }
            guard let winner = ready.max(by: { $0.palmSize < $1.palmSize }) else { return nil }
            state = .engaged(hand: winner.id, mode: .command)
            holdStart = [:]
            lastSeen = t
            lastActivity = t
            lastPose = winner.pose
            return state

        case .engaged(let id, _):
            if let hand = present[id] {
                lastSeen = t
                if hand.pose != lastPose {
                    lastActivity = t
                    lastPose = hand.pose
                }
            }
            guard t - lastSeen > config.handLostTimeout || t - lastActivity > config.idleTimeout else { return nil }
            state = .idle
            holdStart = [:]
            spent = Set(present.keys)
            return state
        }
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
