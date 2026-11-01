import HandTracking
import Signal

public struct PinchReading: Sendable, Equatable {
    /// Thumb touching the index tip (left click / touch).
    public var index: Bool
    /// Thumb touching the middle tip (right click).
    public var middle: Bool
    /// |thumb tip − index tip| / palm size.
    public var ratio: Float
}

/// Pinch from finger geometry rather than the pose classifier: far more reliable for touch.
public struct PinchDetector {
    private let config: TouchConfig
    private var index = false
    private var middle = false
    private var last: (reading: PinchReading, t: Double)?

    public init(config: TouchConfig) {
        self.config = config
    }

    /// nil when the tips have been unreadable for longer than `confidenceHold`.
    public mutating func update(_ hand: Hand, at t: Double) -> PinchReading? {
        let size = max(HandNormalizer.palmSize(hand), 1e-6)
        func ratio(_ tip: JointName) -> Float? {
            guard hand[.thumbTip].confidence >= config.tipConfidence, hand[tip].confidence >= config.tipConfidence else {
                return nil
            }
            let d = HandNormalizer.isotropic(hand, .thumbTip) - HandNormalizer.isotropic(hand, tip)
            return (d * d).sum().squareRoot() / size
        }
        guard let indexRatio = ratio(.indexTip) else {
            guard let last, t - last.t <= config.confidenceHold else { return nil }
            return last.reading
        }
        let reach = HandNormalizer.isotropic(hand, .indexTip) - HandNormalizer.isotropic(hand, .wrist)
        let extended = (reach * reach).sum().squareRoot() / size >= config.minIndexReach
        index = index ? indexRatio <= config.openRatio : indexRatio < config.closeRatio && extended
        if let middleRatio = ratio(.middleTip) {
            middle = middle ? middleRatio <= config.openRatio : middleRatio < config.closeRatio
        } else {
            middle = false // an unreadable middle tip must not hold a right press forever
        }
        // A thumb on the index is never also a right click.
        let reading = PinchReading(index: index, middle: middle && !index, ratio: indexRatio)
        last = (reading, t)
        return reading
    }
}
