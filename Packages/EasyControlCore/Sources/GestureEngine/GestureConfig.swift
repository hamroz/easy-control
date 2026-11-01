/// Tunable thresholds for the gesture engine. Times in seconds; distances in normalized image units.
public struct GestureConfig: Sendable {
    public var poseEnter: Float = 0.85
    public var poseExit: Float = 0.60
    public var poseEnterFrames = 3
    public var wakeHold: Double = 0.3
    /// Three fingers held this long engage directly from idle.
    public var directEngageHold: Double = 0.3
    /// After engagement ends (hand left or went idle), any move into a gesture pose resumes it instantly.
    public var standbyDuration: Double = 15
    /// In standby, a gesture pose must be held this long to resume…
    public var resumeHold: Double = 0.15
    /// …by a hand that changed pose: to another gesture, or relaxed for at least this long.
    public var resumeRelax: Double = 0.2
    public var idleTimeout: Double = 4.0
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
    /// Three-finger drag: travel (frame heights) before the drag commits to horizontal or vertical.
    public var dockSwipeLock: Float = 0.03
    /// A running scroll / three-finger drag rides through this much missing or uncertain tracking.
    public var continuousGrace: Double = 0.2
    /// …and ends only after a different confident pose lasts this many frames.
    public var continuousReleaseFrames = 3
    /// After a scroll or drag ends, no other gesture may start for this long (exclusive lock + settle).
    public var continuousSettle: Double = 0.2
    /// Three fingers count when their mean probability over `threeWindow` rises above `threeEnter`
    /// (and stop below `threeExit`): steadier than requiring consecutive confident frames.
    public var threeWindow: Double = 0.15
    public var threeEnter: Float = 0.7
    public var threeExit: Float = 0.5
    /// Pointer movement (frame heights) that counts as activity — only while the hand is clearly pointing.
    public var pointerActivityDistance: Float = 0.02
    /// A press needs the hand to have shown a pointing or pinch pose within this window (intent evidence).
    public var presentedWindow: Double = 0.3
    /// …or to have made an intentional touch (click, scroll, drag) within this window: follow-up taps and
    /// double-clicks don't need the hand re-presented.
    public var touchIntentWindow: Double = 2.0

    public init() {}

    public static let `default` = GestureConfig()
}
