import GestureEngine

/// Routes gesture events to system actions according to the bindings.
/// Not thread-safe: own it from the pipeline's serial queue.
public final class ActionDispatcher {
    private let sink: any EventSink
    private let spaces: any SpaceSwitchStrategy
    private let scroll: ScrollInjector
    private let dock: DockSwipeInjector
    private var lastTime: Double = 0
    public var bindings: Bindings

    public init(sink: any EventSink, bindings: Bindings = .defaults, spaces: any SpaceSwitchStrategy, scroll: ScrollInjector,
                dock: DockSwipeInjector? = nil) {
        self.sink = sink
        self.bindings = bindings
        self.spaces = spaces
        self.scroll = scroll
        self.dock = dock ?? DockSwipeInjector(sink: sink, spaces: spaces)
    }

    public var isMomentumActive: Bool { scroll.isMomentumActive }
    /// Whether `tick(at:)` has work: scroll momentum or Dock end events to re-send.
    public var needsTicks: Bool { scroll.isMomentumActive || dock.needsTicks }

    public func handle(_ events: [GestureEvent], at t: Double) {
        lastTime = t
        for event in events {
            switch event {
            case .discrete(let id):
                perform(bindings[id])
            case .continuous(let id, let phase, let delta):
                switch bindings[id] {
                case .scroll: scroll.handle(phase: phase, delta: delta, at: t)
                case .dockSwipe: dock.handle(id, phase: phase, delta: delta, at: t)
                default: break
                }
            case .cursor, .engagement:
                break
            }
        }
    }

    public func tick(at t: Double) {
        lastTime = t
        scroll.tick(at: t)
        dock.tick(at: t)
    }

    /// Call when real keyboard/mouse input arrives or tracking pauses: coasting scroll must not continue,
    /// and an open Dock swipe snaps back.
    public func cancelMomentum() {
        scroll.cancelMomentum()
        dock.cancelActive(at: lastTime)
    }

    private func perform(_ action: Action) {
        switch action {
        case .switchSpace(let direction): spaces.switchSpace(direction)
        case .missionControl: sink.press(KeyCode.upArrow, flags: KeyFlags.controlArrow)
        case .appExpose: sink.press(KeyCode.downArrow, flags: KeyFlags.controlArrow)
        case .scroll, .dockSwipe, .none: break
        }
    }
}
