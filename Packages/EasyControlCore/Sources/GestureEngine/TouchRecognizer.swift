import Signal

/// Pinch as touch, on top of the pointer (spec §2.1): hover moves the pointer; a quick pinch clicks where the
/// pinch began; pinch-and-move scrolls (content follows the hand); pinch held still then moved drags.
/// Thumb + middle tap is a right click. Positions are isotropic frame heights of the index knuckle.
public struct TouchRecognizer {
    private enum State {
        case hover
        /// `contact`: the knuckle when the pinch closed (tap/scroll travel is measured from here);
        /// `anchorTime`: when the fingers started closing (clicks and presses land where the pointer was then).
        case pressed(start: Double, contact: SIMD2<Float>, anchorTime: Double, button: MouseButton)
        case scrolling(last: SIMD2<Float>)
        case dragging
    }

    private let config: TouchConfig
    private var state: State = .hover
    private var tracking = false
    private var history: [(t: Double, ratio: Float, anchor: SIMD2<Float>)] = []
    private var lastTap: (t: Double, position: SIMD2<Float>, button: MouseButton)?
    private var lostSince: Double?
    private var scrollBand = Deadband()
    /// A pinch must be seen open before it can press (e.g. one already closed when engagement starts).
    private var armed = false
    private let grace: Double

    public init(config: TouchConfig, gesture: GestureConfig) {
        self.config = config
        grace = gesture.continuousGrace
    }

    /// Pressed, scrolling or dragging: other gestures must not start.
    public var isBusy: Bool {
        if case .hover = state { return false }
        return true
    }

    /// - Parameters:
    ///   - anchor: the engaged hand's index knuckle from **raw** joints — touch decisions (tap vs scroll, travel)
    ///     must not see smoothing lag; nil when the hand isn't tracked this frame.
    ///   - pointer: the smoothed knuckle reported for the pointer (defaults to `anchor`).
    ///   - pinch: the pinch reading, or nil when the fingertips can't be read.
    public mutating func update(anchor: SIMD2<Float>?, pointer: SIMD2<Float>? = nil, pinch: PinchReading?,
                                at t: Double) -> [GestureEvent] {
        guard let anchor, let pinch else { return lost(at: t, unreadable: anchor != nil) }
        let pointer = pointer ?? anchor
        lostSince = nil
        history.append((t, pinch.ratio, anchor))
        history.removeAll { t - $0.t > config.historyWindow }

        switch state {
        case .hover:
            if !pinch.index && !pinch.middle { armed = true }
            if armed, pinch.index || pinch.middle {
                state = .pressed(start: t, contact: anchor, anchorTime: pressAnchorTime(at: t), button: pinch.index ? .left : .right)
                return lift()
            }
            tracking = true
            return [.pointerTrack(position: pointer, at: t)]

        case let .pressed(start, contact, anchorTime, button):
            let released = button == .left ? !pinch.index : !pinch.middle
            let travel = Self.length(anchor - contact)
            if released {
                state = .hover
                guard t - start <= config.tapMax, travel < config.slop else { return [] }
                return [.button(button, .click(count: clickCount(at: t, position: contact, button: button)), anchorTime: anchorTime)]
            }
            guard button == .left else { return [] }
            let held = t - start >= config.holdTime
            if travel >= config.slop {
                // Moving starts a scroll — also when the first frame past the slop arrives after the hold time.
                scrollBand = Deadband(radius: config.scrollDeadband)
                _ = scrollBand.filter(contact)
                let filtered = scrollBand.filter(anchor)
                state = .scrolling(last: filtered)
                return [.continuous(.scroll, phase: .began, delta: filtered - contact)]
            }
            if held {
                state = .dragging
                tracking = true
                return [.button(.left, .down, anchorTime: anchorTime), .pointerTrack(position: pointer, at: t)]
            }
            return []

        case .scrolling(let last):
            guard pinch.index else {
                state = .hover
                return [.continuous(.scroll, phase: .ended, delta: .zero)]
            }
            let filtered = scrollBand.filter(anchor) // jitter while holding a scroll is ignored
            state = .scrolling(last: filtered)
            let delta = filtered - last
            return delta == .zero ? [] : [.continuous(.scroll, phase: .changed, delta: delta)]

        case .dragging:
            guard pinch.index else {
                state = .hover
                return [.button(.left, .up, anchorTime: t)]
            }
            return [.pointerTrack(position: pointer, at: t)]
        }
    }

    /// Ends whatever is in progress (typing, pause, disengage): no click, scroll cancelled, button released.
    public mutating func cancel(at t: Double) -> [GestureEvent] {
        defer {
            state = .hover
            history.removeAll()
            lostSince = nil
            armed = false
        }
        switch state {
        case .hover, .pressed: return lift()
        case .scrolling: return [.continuous(.scroll, phase: .cancelled, delta: .zero)] + lift()
        case .dragging: return [.button(.left, .up, anchorTime: t)] + lift()
        }
    }

    /// Hand not tracked (or fingertips unreadable past the detector's hold): ride out `grace`, then end.
    private mutating func lost(at t: Double, unreadable: Bool) -> [GestureEvent] {
        let since = lostSince ?? t
        lostSince = since
        switch state {
        case .hover:
            // One blurred frame shouldn't stop the pointer; a hand that's really gone lifts after `grace`.
            return t - since > grace ? lift() : []
        case .pressed:
            state = .hover // no click from a pinch we lost sight of
            return []
        case .scrolling, .dragging:
            guard unreadable || t - since > grace else { return [] }
            return cancel(at: t)
        }
    }

    private mutating func lift() -> [GestureEvent] {
        guard tracking else { return [] }
        tracking = false
        return [.pointerLift]
    }

    /// Fingers start closing before the pinch registers and drag the knuckle with them: a click belongs where
    /// the pointer was when the steady fall of the pinch ratio began, at most `anchorLookback` earlier.
    private func pressAnchorTime(at t: Double) -> Double {
        var start = history.count - 1
        while start > 0, history[start - 1].ratio + 0.005 >= history[start].ratio,
              t - history[start - 1].t <= config.anchorLookback + 1e-9 {
            start -= 1
        }
        return start >= 0 && start < history.count ? history[start].t : t
    }

    private mutating func clickCount(at t: Double, position: SIMD2<Float>, button: MouseButton) -> Int {
        defer { lastTap = (t, position, button) }
        guard let last = lastTap, last.button == button, t - last.t <= config.doubleTapWindow,
              Self.length(position - last.position) <= config.doubleTapDistance else { return 1 }
        lastTap = nil
        return 2
    }

    private static func length(_ v: SIMD2<Float>) -> Float { (v * v).sum().squareRoot() }
}
