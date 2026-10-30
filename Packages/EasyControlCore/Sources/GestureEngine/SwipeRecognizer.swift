/// Fast open-palm movement along one axis → discrete swipe.
///
/// A stroke that crosses the distance/speed thresholds becomes *pending*. It fires only when the hand then
/// settles (slows below the swipe speed) for `swipeSettleFrames` frames while still an open palm, reliably
/// tracked and away from the frame edges. Lowering the hand out of view, a stroke that never settles, or a
/// return stroke within `swipeOppositeLockout` never fires.
public struct SwipeRecognizer {
    private struct Pending {
        var direction: GestureID
        var detectedAt: Double
        var settledFrames = 0
    }

    private let config: GestureConfig
    private var samples: [(t: Double, p: SIMD2<Float>)] = []
    private var pending: Pending?
    private var cooldownUntil: Double = -.infinity
    private var lockedOut: (direction: GestureID, until: Double)?

    public init(config: GestureConfig) {
        self.config = config
    }

    public mutating func reset() {
        samples.removeAll()
        pending = nil
    }

    /// - Parameters:
    ///   - palmCenter: normalized frame coordinates (edge checks use these).
    ///   - aspect: frame width / height; distances and speeds are measured in isotropic units (frame heights),
    ///     so a horizontal swipe in a 16:9 frame needs the same hand travel as a vertical one.
    public mutating func update(pose: PoseClass, palmCenter: SIMD2<Float>?, aspect: Float = 1, at t: Double) -> GestureEvent? {
        guard pose == .openPalm, let normalized = palmCenter, t >= cooldownUntil else {
            reset()
            return nil
        }
        let p = SIMD2<Float>(normalized.x * aspect, normalized.y)
        if let last = samples.last, t - last.t > config.frameGapReset || t <= last.t { reset() }
        let previous = samples.last
        samples.append((t, p))
        samples.removeAll { t - $0.t > config.swipeWindow + 1e-9 }

        if pending != nil { return settle(p, normalized: normalized, previous: previous, at: t) }
        guard let direction = detectStroke(to: p, at: t) else { return nil }
        if let lock = lockedOut, lock.direction == direction, t < lock.until { return nil }
        pending = Pending(direction: direction, detectedAt: t)
        return nil
    }

    private func detectStroke(to p: SIMD2<Float>, at t: Double) -> GestureID? {
        guard let first = samples.first, t > first.t else { return nil }
        let d = p - first.p
        let (ax, ay) = (abs(d.x), abs(d.y))
        let (major, minor) = (max(ax, ay), min(ax, ay))
        guard major >= config.swipeMinDistance, major / Float(t - first.t) >= config.swipeMinSpeed,
              major >= config.swipeDominance * minor else { return nil }
        if ax > ay { return d.x < 0 ? .swipeLeft : .swipeRight }
        return d.y < 0 ? .swipeUp : .swipeDown
    }

    private mutating func settle(_ p: SIMD2<Float>, normalized: SIMD2<Float>, previous: (t: Double, p: SIMD2<Float>)?,
                                 at t: Double) -> GestureEvent? {
        guard var stroke = pending else { return nil }
        let m = config.swipeEdgeMargin
        let atEdge = normalized.x < m || normalized.x > 1 - m || normalized.y < m || normalized.y > 1 - m
        if atEdge || t - stroke.detectedAt > config.swipeSettleTimeout {
            reset()
            return nil
        }
        if let previous, t > previous.t {
            let step = p - previous.p
            let speed = (step * step).sum().squareRoot() / Float(t - previous.t)
            stroke.settledFrames = speed < config.swipeMinSpeed ? stroke.settledFrames + 1 : 0
        }
        pending = stroke
        guard stroke.settledFrames >= config.swipeSettleFrames else { return nil }

        reset()
        cooldownUntil = t + config.discreteCooldown
        lockedOut = (Self.opposite(stroke.direction), t + config.swipeOppositeLockout)
        return .discrete(stroke.direction)
    }

    private static func opposite(_ id: GestureID) -> GestureID {
        switch id {
        case .swipeLeft: .swipeRight
        case .swipeRight: .swipeLeft
        case .swipeUp: .swipeDown
        default: .swipeUp
        }
    }
}
