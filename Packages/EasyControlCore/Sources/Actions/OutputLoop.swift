import CoreGraphics
import Foundation
import GestureEngine
import Signal
import Synchronization

public enum OverlayMode: Sendable, Equatable {
    case hidden, hover, pressed, dragging, scrolling
}

public struct OverlayState: Sendable, Equatable {
    public var mode: OverlayMode = .hidden
    public var position: CGPoint = .zero
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
        followed != nil || !scrollSmoother.isEmpty || !dockSmoother.isEmpty || scroll.isMomentumActive
            || dock.isActive || dock.needsTicks || leftDown
    }

    /// Where the pointer was at time `t` (the latest frame at or before it).
    public func position(at t: Double) -> CGPoint? {
        history.last { $0.t <= t + 1e-9 }?.position ?? history.first?.position
    }

    public func receive(_ events: [GestureEvent], at t: Double) {
        for event in events {
            switch event {
            case let .pointerTrack(raw, time):
                if followed == nil {
                    predictor.reset()
                    deadband.reset()
                    pointer = environment.cursorLocation() // the real mouse may have moved it meanwhile
                }
                let position = deadband.filter(raw) // tremor doesn't move the pointer
                if followed == nil { followed = position }
                predictor.update(position, at: time)
            case .pointerLift:
                followed = nil
                predictor.reset()
                deadband.reset()
            case let .button(button, action, anchorTime):
                press(button, action, at: position(at: anchorTime) ?? pointer)
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

        if let current = followed, let target = predictor.sample(at: now) {
            let next = current + (target - current) * Float(1 - exp(-dt / followTau))
            followed = next
            let handDelta = next - current
            let speed = Double((handDelta * handDelta).sum().squareRoot()) / max(dt, 1e-4)
            let px = mapper.pixels(handDelta: handDelta, speed: speed, screenHeight: environment.screenHeight())
            if abs(px.x) + abs(px.y) > 0.01 {
                pointer = PointerMapper.clamp(CGPoint(x: pointer.x + px.x, y: pointer.y + px.y),
                                              to: environment.displayFrames())
                sink.post(.mouse(leftDown ? .leftDragged : .moved, x: pointer.x, y: pointer.y, clickCount: 1))
            }
        }
        history.append((now, pointer))
        history.removeAll { now - $0.t > Self.historyWindow }

        if scrollActive || !scrollSmoother.isEmpty {
            let d = scrollSmoother.take(dt: dt)
            if d != .zero { scroll.handle(phase: .changed, delta: SIMD2<Float>(Float(d.x), Float(d.y)), at: now) }
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
        if scrollActive { handleScroll(.cancelled, delta: .zero, at: t) }
        scroll.cancelMomentum()
        if let id = dockID { handleDock(id, .cancelled, delta: .zero, at: t) }
        dock.cancelActive(at: t)
        followed = nil
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
            scrollSmoother.clear()
            scrollActive = true
            scroll.handle(phase: .began, delta: .zero, at: t)
            scrollSmoother.add(SIMD2<Double>(Double(delta.x), Double(delta.y)))
        case .changed:
            scrollSmoother.add(SIMD2<Double>(Double(delta.x), Double(delta.y)))
        case .ended:
            let rest = scrollSmoother.flush()
            if rest != .zero { scroll.handle(phase: .changed, delta: SIMD2<Float>(Float(rest.x), Float(rest.y)), at: t) }
            scrollActive = false
            scroll.handle(phase: .ended, delta: .zero, at: t)
        case .cancelled:
            scrollSmoother.clear()
            scrollActive = false
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
            else if scrollActive { .scrolling }
            else if followed != nil { .hover }
            else if engaged && dockID == nil { .pressed }
            else { .hidden }
        overlay = OverlayState(mode: mode, position: pointer)
    }
}

/// Hands gesture intents from the capture queue to the output thread.
public final class OutputInbox: Sendable {
    private let queue = Mutex<[(events: [GestureEvent], t: Double)]>([])

    public init() {}

    public func post(_ events: [GestureEvent], at t: Double) {
        guard !events.isEmpty else { return }
        queue.withLock { $0.append((events, t)) }
    }

    public func drain(into loop: OutputLoop) {
        let batches = queue.withLock { q in defer { q.removeAll() }; return q }
        for batch in batches { loop.receive(batch.events, at: batch.t) }
    }
}
