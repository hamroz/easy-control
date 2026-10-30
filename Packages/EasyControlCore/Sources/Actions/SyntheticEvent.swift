public enum ScrollPhase: Sendable {
    case began, changed, ended, none
}

public enum MomentumPhase: Sendable {
    case none, began, `continue`, ended
}

public enum DockMotion: Int, Sendable {
    case horizontal = 1, vertical = 2
}

public enum DockPhase: UInt32, Sendable {
    case began = 1, changed = 2, ended = 4, cancelled = 8
}

/// Input we inject into macOS, independent of CoreGraphics so it can be recorded in tests.
public enum SyntheticEvent: Equatable, Sendable {
    /// Pixel deltas; positive `dy` scrolls the view up (content moves down), as a scroll wheel does.
    case scroll(dx: Int32, dy: Int32, phase: ScrollPhase, momentum: MomentumPhase)
    case key(code: UInt16, flags: UInt64, down: Bool)
    /// The Dock's three-finger swipe. `progress` 1.0 ≈ one Space (horizontal) or a full Mission Control
    /// transition (vertical); positive = natural direction. `velocity` is sent with ended/cancelled.
    case dockSwipe(motion: DockMotion, phase: DockPhase, progress: Double, velocity: Double)
}
