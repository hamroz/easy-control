import GestureEngine

/// Routes gesture events to system actions according to the bindings.
/// Not thread-safe: own it from the pipeline's serial queue.
public final class ActionDispatcher {
    private let sink: any EventSink
    private let spaces: any SpaceSwitchStrategy
    private let scroll: ScrollInjector
    public var bindings: Bindings

    public init(sink: any EventSink, bindings: Bindings = .defaults, spaces: any SpaceSwitchStrategy, scroll: ScrollInjector) {
        self.sink = sink
        self.bindings = bindings
        self.spaces = spaces
        self.scroll = scroll
    }

    public var isMomentumActive: Bool { scroll.isMomentumActive }

    public func handle(_ events: [GestureEvent], at t: Double) {
        for event in events {
            switch event {
            case .discrete(let id):
                perform(bindings[id])
            case .continuous(let id, let phase, let delta):
                if bindings[id] == .scroll { scroll.handle(phase: phase, delta: delta, at: t) }
            case .cursor, .engagement:
                break
            }
        }
    }

    public func tick(at t: Double) {
        scroll.tick(at: t)
    }

    private func perform(_ action: Action) {
        switch action {
        case .switchSpace(let direction): spaces.switchSpace(direction)
        case .missionControl: sink.press(KeyCode.upArrow, flags: KeyFlags.controlArrow)
        case .appExpose: sink.press(KeyCode.downArrow, flags: KeyFlags.controlArrow)
        case .scroll, .none: break
        }
    }
}
