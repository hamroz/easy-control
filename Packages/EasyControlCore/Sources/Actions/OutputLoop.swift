import CoreGraphics
import Foundation
import GestureEngine
import Signal
import Synchronization

public enum OverlayMode: Sendable, Equatable {
    case hidden, hover, pressed, dragging, scrolling
    /// Fist: the pointer is lifted and stays put while the hand moves.
    case lifted
}

public struct OverlayState: Sendable, Equatable {
    public var mode: OverlayMode
    public var position: CGPoint

    public init(mode: OverlayMode = .hidden, position: CGPoint = .zero) {
        self.mode = mode
        self.position = position
    }
}

/// Renders gesture intents at display rate (spec §3): the pointer follows a predicted, smoothed hand position;
/// scroll and Dock deltas are spread across frames; clicks and presses land where the pointer was at their
/// anchor time. Owns every "smoothing in time". Not thread-safe: own it from the output thread.
public final class OutputLoop {
    private let sink: any EventSink
    private let environment: any PointerEnvironment
    public var mapper: PointerMapper
    private let followTau: Double
    private let scroll: ScrollInjector
    private let dock: DockSwipeInjector
    private var scrollSmoother = RateSmoother()
    private var dockSmoother = RateSmoother()
    private var dockID: GestureID?
    private var scrollActive = false

    private var predictor = MotionPredictor()
    private var deadband = Deadband()
    private var followed: SIMD2<Float>?
    private var pointer: CGPoint
    private var history: [(t: Double, position: CGPoint)] = []
    /// History frozen when a press began (pointer lift): the click or drag that follows — up to a hold time plus
    /// latency later — still finds where the pointer was at its anchor time.
    private var pressHistory: [(t: Double, position: CGPoint)]?
    /// When the scroll ended while motion was still pending: it glides out for `glideOut`, then ends.
    private var scrollEndedAt: Double?
    private var scrollEnding: Bool { scrollEndedAt != nil }
    private static let glideOut = 0.05
    /// Edge glide in screen heights per second, and when it was last renewed (arrival time): a glide the
    /// camera stops confirming ends after `glideStale`.
    private var glide: SIMD2<Float> = .zero
    private var glideRenewed: Double = -.infinity
    private static let glideStale = 0.15
    private var resting = false
    private var lastStep: Double?
    private var leftDown = false
    private var engaged = false
    public private(set) var overlay = OverlayState()

    private static let historyWindow = 0.3

    public init(sink: any EventSink, environment: any PointerEnvironment, spaces: any SpaceSwitchStrategy,
                mapper: PointerMapper = PointerMapper(), followTau: Double = 0.025) {
        self.sink = sink
        self.environment = environment
        self.mapper = mapper
        self.followTau = followTau
        scroll = ScrollInjector(sink: sink)
        dock = DockSwipeInjector(sink: sink, spaces: spaces)
        pointer = environment.cursorLocation()
    }

    /// Something still needs display frames: pointer tracking, pending deltas, momentum, Dock re-sends, a held button.
    public var needsFrames: Bool {
        followed != nil || glide != .zero || !scrollSmoother.isEmpty || !dockSmoother.isEmpty || scrollEnding || scroll.isMomentumActive
            || dock.isActive || dock.needsTicks || leftDown
    }

    /// Where the pointer was at time `t` (the latest frame at or before it).
    public func position(at t: Double) -> CGPoint? {
        Self.lookup(t, in: history)
    }

    private static func lookup(_ t: Double, in frames: [(t: Double, position: CGPoint)]) -> CGPoint? {
        frames.last { $0.t <= t + 1e-9 }?.position ?? frames.first?.position
    }

    /// - Parameter arrival: when these events reached the output loop; the pointer predictor is timed by arrival,
    ///   so pipeline latency doesn't push every prediction to its cap.
    public func receive(_ events: [GestureEvent], at t: Double, arrival: Double? = nil) {
        for event in events {
            switch event {
            case let .pointerTrack(raw, time):
                resting = false
                if followed == nil {
                    predictor.reset()
                    deadband.reset()
                    pressHistory = nil
                    pointer = environment.cursorLocation() // the real mouse may have moved it meanwhile
                }
                let position = deadband.filter(raw) // tremor doesn't move the pointer
                if followed == nil { followed = position }
                predictor.update(position, at: arrival ?? time)
            case .pointerLift:
                if followed != nil { pressHistory = history }
                followed = nil
                glide = .zero
                predictor.reset()
                deadband.reset()
            case .pointerRest:
                resting = true
                followed = nil
                glide = .zero
                pressHistory = nil
                predictor.reset()
                deadband.reset()
            case let .pointerGlide(velocity, _):
                glide = velocity
                glideRenewed = arrival ?? t
            case let .button(button, action, anchorTime):
                let target = action == .up ? pointer : (Self.lookup(anchorTime, in: pressHistory ?? history) ?? pointer)
                press(button, action, at: target)
                if action != .up { pressHistory = nil }
            case let .continuous(id, phase, delta) where id == .scroll:
                handleScroll(phase, delta: delta, at: t)
            case let .continuous(id, phase, delta) where id == .dockSwipeHorizontal || id == .dockSwipeVertical:
                handleDock(id, phase, delta: delta, at: t)
            case .engagement(let state):
                if case .engaged = state { engaged = true } else { engaged = false }
            case .continuous, .discrete:
                break
            }
        }
    }

    /// One display frame.
    public func step(at now: Double) {
        let dt = lastStep.map { min(max(now - $0, 0), 0.1) } ?? 1.0 / 120
        lastStep = now

        var px = SIMD2<Double>.zero
        if let current = followed, let target = predictor.sample(at: now) {
            let next = current + (target - current) * Float(1 - exp(-dt / followTau))
            followed = next
            let handDelta = next - current
            let speed = Double((handDelta * handDelta).sum().squareRoot()) / max(dt, 1e-4)
            px = mapper.pixels(handDelta: handDelta, speed: speed, screenHeight: environment.screenHeight())
        }
        if glide != .zero, now - glideRenewed > Self.glideStale { glide = .zero }
        if glide != .zero, followed != nil || leftDown {
            px += SIMD2<Double>(Double(glide.x), Double(glide.y)) * environment.screenHeight() * dt
        }
        if abs(px.x) + abs(px.y) > 0.01 {
            let next = PointerMapper.clamp(CGPoint(x: pointer.x + px.x, y: pointer.y + px.y), to: environment.displayFrames())
            if next != pointer {
                pointer = next
                sink.post(.mouse(leftDown ? .leftDragged : .moved, x: pointer.x, y: pointer.y, clickCount: 1))
            }
        }
        history.append((now, pointer))
        history.removeAll { now - $0.t > Self.historyWindow }

        if scrollActive || scrollEnding || !scrollSmoother.isEmpty {
            let d = scrollSmoother.take(dt: dt)
            if d != .zero { scroll.handle(phase: .changed, delta: SIMD2<Float>(Float(d.x), Float(d.y)), at: now) }
            if let ended = scrollEndedAt, scrollSmoother.isEmpty || now - ended >= Self.glideOut {
                let rest = scrollSmoother.flush() // the last few percent; a long tail would starve momentum
                if rest != .zero { scroll.handle(phase: .changed, delta: SIMD2<Float>(Float(rest.x), Float(rest.y)), at: now) }
                scrollEndedAt = nil
                scroll.handle(phase: .ended, delta: .zero, at: now) // momentum starts from the glided-out motion
            }
        }
        scroll.tick(at: now)
        if let id = dockID {
            let d = dockSmoother.take(dt: dt)
            if d != .zero { dock.handle(id, phase: .changed, delta: SIMD2<Float>(Float(d.x), Float(d.y)), at: now) }
        }
        dock.tick(at: now)
        updateOverlay()
    }

    /// Interrupt everything (pause, typing, quit, stall): no scroll or Dock left open, no button left down.
    public func cancelAll(at t: Double) {
        if leftDown {
            sink.post(.mouse(.leftUp, x: pointer.x, y: pointer.y, clickCount: 1))
            leftDown = false
        }
        if scrollActive || scrollEnding { handleScroll(.cancelled, delta: .zero, at: t) }
        scroll.cancelMomentum()
        if let id = dockID { handleDock(id, .cancelled, delta: .zero, at: t) }
        dock.cancelActive(at: t)
        followed = nil
        glide = .zero
        resting = false
        predictor.reset()
        deadband.reset()
        updateOverlay()
    }

    /// Real input arrived: a coasting scroll stops and an open Dock swipe snaps back.
    public func cancelMomentum(at t: Double) {
        scroll.cancelMomentum()
        if let id = dockID { handleDock(id, .cancelled, delta: .zero, at: t) }
        dock.cancelActive(at: t)
    }

    private func press(_ button: MouseButton, _ action: ButtonAction, at position: CGPoint) {
        if position != pointer {
            pointer = position
            sink.post(.mouse(leftDown ? .leftDragged : .moved, x: position.x, y: position.y, clickCount: 1))
        }
        let (down, up): (MouseKind, MouseKind) = button == .left ? (.leftDown, .leftUp) : (.rightDown, .rightUp)
        switch action {
        case .click(let count):
            sink.post(.mouse(down, x: position.x, y: position.y, clickCount: count))
            sink.post(.mouse(up, x: position.x, y: position.y, clickCount: count))
        case .down:
            sink.post(.mouse(down, x: position.x, y: position.y, clickCount: 1))
            if button == .left { leftDown = true }
        case .up:
            sink.post(.mouse(up, x: pointer.x, y: pointer.y, clickCount: 1))
            if button == .left { leftDown = false }
        }
    }

    private func handleScroll(_ phase: Phase, delta: SIMD2<Float>, at t: Double) {
        switch phase {
        case .began:
            if scrollEnding { // the previous scroll is still gliding out: finish it first
                let rest = scrollSmoother.flush()
                if rest != .zero { scroll.handle(phase: .changed, delta: SIMD2<Float>(Float(rest.x), Float(rest.y)), at: t) }
                scroll.handle(phase: .ended, delta: .zero, at: t)
                scrollEndedAt = nil
            }
            scrollSmoother.clear()
            scrollActive = true
            glide = .zero
            scroll.handle(phase: .began, delta: .zero, at: t)
            scrollSmoother.add(SIMD2<Double>(Double(delta.x), Double(delta.y)))
        case .changed:
            scrollSmoother.add(SIMD2<Double>(Double(delta.x), Double(delta.y)))
        case .ended:
            scrollActive = false
            scrollEndedAt = t // keep gliding out what's pending; `step` ends the scroll
        case .cancelled:
            scrollSmoother.clear()
            scrollActive = false
            scrollEndedAt = nil
            scroll.handle(phase: .cancelled, delta: .zero, at: t)
        }
    }

    private func handleDock(_ id: GestureID, _ phase: Phase, delta: SIMD2<Float>, at t: Double) {
        switch phase {
        case .began:
            dockSmoother.clear()
            dockID = id
            dock.handle(id, phase: .began, delta: .zero, at: t)
            dockSmoother.add(SIMD2<Double>(Double(delta.x), Double(delta.y)))
        case .changed:
            dockSmoother.add(SIMD2<Double>(Double(delta.x), Double(delta.y)))
        case .ended:
            let rest = dockSmoother.flush()
            if rest != .zero { dock.handle(id, phase: .changed, delta: SIMD2<Float>(Float(rest.x), Float(rest.y)), at: t) }
            dock.handle(id, phase: .ended, delta: .zero, at: t)
            dockID = nil
        case .cancelled:
            dockSmoother.clear()
            dock.handle(id, phase: .cancelled, delta: .zero, at: t)
            dockID = nil
        }
    }

    private func updateOverlay() {
        let mode: OverlayMode = if leftDown { .dragging }
            else if scrollActive || scrollEnding { .scrolling }
            else if followed != nil { .hover }
            else if resting && engaged { .lifted }
            else if pressHistory != nil && engaged { .pressed } // a real press, not just a lost or idle hand
            else { .hidden }
        overlay = OverlayState(mode: mode, position: pointer)
    }
}

/// Hands gesture intents and control commands from other threads to the output thread, in order.
public final class OutputInbox: Sendable {
    private enum Item {
        case events([GestureEvent], Double)
        case cancelAll(Double)
        case cancelMomentum(Double)
    }

    private let queue = Mutex<[Item]>([])

    public init() {}

    public func post(_ events: [GestureEvent], at t: Double) {
        guard !events.isEmpty else { return }
        queue.withLock { $0.append(.events(events, t)) }
    }

    public func postCancelAll(at t: Double) {
        queue.withLock { $0.append(.cancelAll(t)) }
    }

    public func postCancelMomentum(at t: Double) {
        queue.withLock { $0.append(.cancelMomentum(t)) }
    }

    public func drain(into loop: OutputLoop, at now: Double) {
        let items = queue.withLock { q in defer { q.removeAll() }; return q }
        for item in items {
            switch item {
            case let .events(events, t): loop.receive(events, at: t, arrival: now)
            case let .cancelAll(t): loop.cancelAll(at: t)
            case let .cancelMomentum(t): loop.cancelMomentum(at: t)
            }
        }
    }
}
