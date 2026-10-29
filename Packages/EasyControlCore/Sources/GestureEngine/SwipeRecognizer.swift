/// Fast open-palm movement along one axis → discrete swipe.
public struct SwipeRecognizer {
    private let config: GestureConfig
    private var samples: [(t: Double, p: SIMD2<Float>)] = []
    private var cooldownUntil: Double = -.infinity

    public init(config: GestureConfig) {
        self.config = config
    }

    public mutating func reset() { samples.removeAll() }

    public mutating func update(pose: PoseClass, palmCenter: SIMD2<Float>?, at t: Double) -> GestureEvent? {
        guard pose == .openPalm, let p = palmCenter, t >= cooldownUntil else {
            samples.removeAll()
            return nil
        }
        if let last = samples.last, t - last.t > config.frameGapReset || t <= last.t { samples.removeAll() }
        samples.append((t, p))
        samples.removeAll { t - $0.t > config.swipeWindow + 1e-9 }

        guard let first = samples.first, t > first.t else { return nil }
        let d = p - first.p
        let (ax, ay) = (abs(d.x), abs(d.y))
        let (major, minor) = (max(ax, ay), min(ax, ay))
        let speed = major / Float(t - first.t)
        guard major >= config.swipeMinDistance, speed >= config.swipeMinSpeed,
              major >= config.swipeDominance * minor else { return nil }

        samples.removeAll()
        cooldownUntil = t + config.discreteCooldown
        if ax > ay { return .discrete(d.x < 0 ? .swipeLeft : .swipeRight) }
        return .discrete(d.y < 0 ? .swipeUp : .swipeDown)
    }
}
