/// Thresholds for pinch-as-touch. Times in seconds; distances in isotropic frame heights; ratios relative to
/// palm size.
public struct TouchConfig: Sendable {
    public var closeRatio: Float = 0.22
    public var openRatio: Float = 0.35
    public var tipConfidence: Float = 0.3
    public var confidenceHold: Double = 0.2
    public var tapMax: Double = 0.25
    public var holdTime: Double = 0.4
    public var slop: Float = 0.015
    public var doubleTapWindow: Double = 0.35
    public var doubleTapDistance: Float = 0.02
    public var anchorLookback: Double = 0.12
    public var historyWindow: Double = 0.15

    public init() {}

    public static let `default` = TouchConfig()
}
