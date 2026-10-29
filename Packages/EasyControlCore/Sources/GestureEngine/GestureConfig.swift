/// Tunable thresholds for the gesture engine. Times in seconds; distances in normalized image units.
public struct GestureConfig: Sendable {
    public var poseEnter: Float = 0.85
    public var poseExit: Float = 0.60
    public var poseEnterFrames = 3
    public var wakeHold: Double = 0.4
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
    public var scrollDeadZone: Float = 0.004

    public init() {}

    public static let `default` = GestureConfig()
}
