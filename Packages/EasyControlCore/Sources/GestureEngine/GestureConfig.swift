/// Tunable thresholds for the gesture engine. Times in seconds; distances in normalized image units.
public struct GestureConfig: Sendable {
    public var poseEnter: Float = 0.85
    public var poseExit: Float = 0.60
    public var poseEnterFrames = 3
    public var wakeHold: Double = 0.4
    /// Two or three fingers held this long engage directly from idle.
    public var directEngageHold: Double = 0.3
    /// After engagement ends (hand left or went idle), any move into a gesture pose resumes it instantly.
    public var standbyDuration: Double = 15
    public var idleTimeout: Double = 3.0
    public var handLostTimeout: Double = 1.0
    public var inputSuppression: Double = 0.5
    public var discreteCooldown: Double = 0.4
    public var minPalmSize: Float = 0.06
    public var frameGapReset: Double = 0.25
    public var swipeMinSpeed: Float = 1.0
    public var swipeMinDistance: Float = 0.15
    public var swipeDominance: Float = 2.0
    public var swipeWindow: Double = 0.25
    /// A detected stroke only fires once the hand has settled for this many frames, still open and in frame.
    public var swipeSettleFrames = 2
    /// A stroke that hasn't settled within this time is dropped (continuous waving, gesturing while talking).
    public var swipeSettleTimeout: Double = 0.5
    /// Strokes ending this close to any frame edge are dropped: that's a hand leaving, not a swipe.
    public var swipeEdgeMargin: Float = 0.1
    /// After a swipe, the opposite direction is ignored this long, so the return stroke doesn't undo it.
    public var swipeOppositeLockout: Double = 1.0
    public var scrollDeadZone: Float = 0.004

    public init() {}

    public static let `default` = GestureConfig()
}
