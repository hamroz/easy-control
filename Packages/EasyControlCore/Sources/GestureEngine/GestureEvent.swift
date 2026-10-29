/// Identifies a gesture for bindings. String-backed so custom poses can add their own ids later.
public struct GestureID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }

    public static let scroll = GestureID(rawValue: "scroll")
    public static let swipeLeft = GestureID(rawValue: "swipe.left")
    public static let swipeRight = GestureID(rawValue: "swipe.right")
    public static let swipeUp = GestureID(rawValue: "swipe.up")
    public static let swipeDown = GestureID(rawValue: "swipe.down")
}

public enum Phase: String, Codable, Sendable {
    case began, changed
    /// The user finished the gesture (e.g. changed pose): continuous actions may coast (scroll momentum).
    case ended
    /// The gesture was interrupted (hand lost, typing, pause, disengage): stop immediately, no momentum.
    case cancelled
}

public enum GestureEvent: Equatable, Sendable {
    case discrete(GestureID)
    /// `delta` is palm displacement in normalized image units (mirrored, +y down) since the previous event.
    case continuous(GestureID, phase: Phase, delta: SIMD2<Float>)
    case cursor(position: SIMD2<Float>)
    case engagement(EngagementState)
}
