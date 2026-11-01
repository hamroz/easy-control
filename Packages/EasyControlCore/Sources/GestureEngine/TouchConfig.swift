/// Thresholds for pinch-as-touch. Times in seconds; distances in isotropic frame heights; ratios relative to
/// palm size.
public struct TouchConfig: Sendable {
    public var closeRatio: Float = 0.22
    public var openRatio: Float = 0.35
    /// A pinch needs the index tip at least this far from the wrist (palm sizes): a fist's curled index with the
    /// thumb resting on it also "touches" (calibrated on the user's recordings: fist p50 0.70, pinch p5 0.93).
    public var minIndexReach: Float = 0.85
    public var tipConfidence: Float = 0.3
    public var confidenceHold: Double = 0.2
    public var tapMax: Double = 0.25
    public var holdTime: Double = 0.4
    public var slop: Float = 0.015
    public var doubleTapWindow: Double = 0.35
    public var doubleTapDistance: Float = 0.02
    public var anchorLookback: Double = 0.12
    public var historyWindow: Double = 0.15
    /// While scrolling, knuckle jitter within this radius (frame heights) is ignored, so a held scroll stays put.
    public var scrollDeadband: Float = 0.003

    public init() {}

    public static let `default` = TouchConfig()
}
