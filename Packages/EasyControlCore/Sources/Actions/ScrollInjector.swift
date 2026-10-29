import GestureEngine

/// Turns scroll gesture phases into trackpad-like scroll events, including momentum after a flick.
/// Not thread-safe: own it from the pipeline's serial queue.
public final class ScrollInjector {
    private let sink: any EventSink
    private let pixelsPerUnit: Float
    private let natural: Bool
    private let friction: Float
    private let minMomentumSpeed: Float
    private static let velocityWindow = 0.1
    private static let tickInterval: Float = 1.0 / 60

    private var recent: [(t: Double, delta: SIMD2<Float>)] = []
    private var momentumVelocity: SIMD2<Float>?
    private var momentumStarted = false

    public init(sink: any EventSink, pixelsPerUnit: Float = 1800, natural: Bool = true,
                friction: Float = 0.92, minMomentumSpeed: Float = 20) {
        self.sink = sink
        self.pixelsPerUnit = pixelsPerUnit
        self.natural = natural
        self.friction = friction
        self.minMomentumSpeed = minMomentumSpeed
    }

    public var isMomentumActive: Bool { momentumVelocity != nil }

    /// - Parameter delta: palm displacement in normalized image units (+y = hand moved down).
    public func handle(phase: Phase, delta: SIMD2<Float>, at t: Double) {
        switch phase {
        case .began:
            stopMomentum()
            recent.removeAll()
            sink.post(.scroll(dx: 0, dy: 0, phase: .began, momentum: .none))
        case .changed:
            let px = pixels(delta)
            recent.append((t, px))
            recent.removeAll { t - $0.t > Self.velocityWindow }
            sink.post(.scroll(dx: Int32(px.x.rounded()), dy: Int32(px.y.rounded()), phase: .changed, momentum: .none))
        case .ended:
            sink.post(.scroll(dx: 0, dy: 0, phase: .ended, momentum: .none))
            let window = recent.filter { t - $0.t <= Self.velocityWindow }
            let velocity = window.reduce(SIMD2<Float>.zero) { $0 + $1.delta } / Float(Self.velocityWindow)
            recent.removeAll()
            if (velocity * velocity).sum().squareRoot() >= minMomentumSpeed {
                momentumVelocity = velocity
                momentumStarted = false
            }
        }
    }

    /// Advances momentum by one 60 Hz step.
    public func tick(at t: Double) {
        guard var v = momentumVelocity else { return }
        v *= friction
        if (v * v).sum().squareRoot() < minMomentumSpeed {
            stopMomentum()
            return
        }
        let step = v * Self.tickInterval
        sink.post(.scroll(dx: Int32(step.x.rounded()), dy: Int32(step.y.rounded()), phase: .none,
                          momentum: momentumStarted ? .continue : .began))
        momentumStarted = true
        momentumVelocity = v
    }

    private func stopMomentum() {
        guard momentumVelocity != nil else { return }
        momentumVelocity = nil
        if momentumStarted { sink.post(.scroll(dx: 0, dy: 0, phase: .none, momentum: .ended)) }
        momentumStarted = false
    }

    private func pixels(_ delta: SIMD2<Float>) -> SIMD2<Float> {
        natural ? delta * pixelsPerUnit : -delta * pixelsPerUnit
    }
}
