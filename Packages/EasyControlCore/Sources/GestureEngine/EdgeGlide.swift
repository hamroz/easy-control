/// Edge glide: a pointing hand held in the outer band of the camera view keeps the pointer moving toward that
/// edge, so it can travel across the screen without the hand leaving the view. Positions are normalized image
/// coordinates (mirrored, top-left origin, 0…1 on each axis).
public struct EdgeGlide {
    private let config: GestureConfig
    /// The hand has been in the middle of the view since it appeared: a hand coming back in at the edge
    /// mustn't send the pointer off toward the side it came from.
    private var armed = false
    private var enteredAt: Double?
    private var lostSince: Double?
    private var gliding = false

    public init(config: GestureConfig) {
        self.config = config
    }

    /// - Parameters:
    ///   - position: the hand's anchor, or nil when the hand isn't tracked this frame.
    ///   - enabled: whether the hand may glide now (pointing or dragging); a hand that may not keeps its arming.
    public mutating func update(position: SIMD2<Float>?, enabled: Bool, at t: Double) -> [GestureEvent] {
        guard let position else {
            let since = lostSince ?? t
            lostSince = since
            if t - since > config.continuousGrace { armed = false }
            enteredAt = nil
            return stop(at: t)
        }
        lostSince = nil
        let depth = SIMD2(Self.depth(position.x, zone: config.glideZone), Self.depth(position.y, zone: config.glideZone))
        guard depth != .zero else {
            armed = true
            enteredAt = nil
            return stop(at: t)
        }
        let entered = enteredAt ?? t
        enteredAt = entered
        guard armed, enabled else { return stop(at: t) }
        let ramp = Float(min(1, (t - entered) / config.glideRamp))
        let velocity = depth * SIMD2(abs(depth.x), abs(depth.y)) * config.glideMaxSpeed * ramp // eases in with depth, keeps the sign
        guard velocity != .zero else { return stop(at: t) }
        gliding = true
        return [.pointerGlide(velocity: velocity, at: t)]
    }

    /// Fist lift, a press that isn't a drag, the Dock taking over: stop gliding but stay armed.
    public mutating func stop(at t: Double) -> [GestureEvent] {
        guard gliding else { return [] }
        gliding = false
        return [.pointerGlide(velocity: .zero, at: t)]
    }

    /// Disengaged or paused: stop and require the middle again.
    public mutating func reset(at t: Double) -> [GestureEvent] {
        armed = false
        enteredAt = nil
        return stop(at: t)
    }

    /// −1…0 inside the low band, 0 in the middle, 0…1 inside the high band.
    private static func depth(_ v: Float, zone: Float) -> Float {
        if v < zone { return -min(1, (zone - v) / zone) }
        if v > 1 - zone { return min(1, (v - (1 - zone)) / zone) }
        return 0
    }
}
