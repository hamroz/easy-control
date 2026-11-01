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
    /// Three fingers dragged sideways: the trackpad's Spaces swipe.
    public static let dockSwipeHorizontal = GestureID(rawValue: "dockSwipe.horizontal")
    /// Three fingers dragged up/down: the trackpad's Mission Control / App Exposé swipe.
    public static let dockSwipeVertical = GestureID(rawValue: "dockSwipe.vertical")
}

public enum Phase: String, Codable, Sendable {
    case began, changed
    /// The user finished the gesture (e.g. changed pose): continuous actions may coast (scroll momentum).
    case ended
    /// The gesture was interrupted (hand lost, typing, pause, disengage): stop immediately, no momentum.
    case cancelled
}

public enum MouseButton: Sendable, Equatable {
    case left, right
}

public enum ButtonAction: Sendable, Equatable {
    case click(count: Int)
    case down, up
}

public enum GestureEvent: Equatable, Sendable {
    case discrete(GestureID)
    /// `delta` is hand displacement in isotropic frame heights (mirrored, +y down) since the previous event.
    case continuous(GestureID, phase: Phase, delta: SIMD2<Float>)
    /// Where the hand's pointer anchor (index knuckle) is, in isotropic frame heights, at camera time `at`.
    case pointerTrack(position: SIMD2<Float>, at: Double)
    /// The pointer stops following the hand (press, hand lost): output must not extrapolate further.
    case pointerLift
    /// Fist: the pointer stays where it is while the hand moves (a mouse picked up); tracking resumes,
    /// relative to wherever the hand is then, on the next `pointerTrack`.
    case pointerRest
    /// Edge glide: keep moving the pointer at `velocity` screen heights per second (+y down) until renewed or
    /// stopped by a zero velocity. Camera time `at`.
    case pointerGlide(velocity: SIMD2<Float>, at: Double)
    /// A mouse button action. Clicks and presses happen where the pointer was at `anchorTime`, before the
    /// closing fingers dragged it.
    case button(MouseButton, ButtonAction, anchorTime: Double)
    case engagement(EngagementState)
}
