public enum ScrollPhase: Sendable {
    case began, changed, ended, none
}

public enum MomentumPhase: Sendable {
    case none, began, `continue`, ended
}

/// Input we inject into macOS, independent of CoreGraphics so it can be recorded in tests.
public enum SyntheticEvent: Equatable, Sendable {
    /// Pixel deltas; positive `dy` scrolls the view up (content moves down), as a scroll wheel does.
    case scroll(dx: Int32, dy: Int32, phase: ScrollPhase, momentum: MomentumPhase)
    case key(code: UInt16, flags: UInt64, down: Bool)
}
