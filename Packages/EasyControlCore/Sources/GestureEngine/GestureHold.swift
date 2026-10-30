/// Keeps a running continuous gesture (scroll, three-finger drag) alive through brief tracking noise:
/// a blurred or dropped frame, or a pose misread for a few frames, must not end and restart it.
struct GestureHold {
    /// `track`: keep following the hand (also while a misread pose is being ridden out);
    /// `hold`: hand not tracked this frame, emit nothing; `release` / `cancel`: end the gesture.
    enum Decision { case track, hold, release, cancel }

    private let config: GestureConfig
    private var gapStart: Double?
    private var otherFrames = 0

    init(config: GestureConfig) {
        self.config = config
    }

    mutating func reset() {
        gapStart = nil
        otherFrames = 0
    }

    /// - Parameters:
    ///   - matches: the gesture's own pose is showing.
    ///   - pose: the stable pose.
    ///   - tracked: the hand's position is known this frame.
    mutating func observe(matches: Bool, pose: PoseClass, tracked: Bool, at t: Double) -> Decision {
        guard tracked else {
            otherFrames = 0
            let start = gapStart ?? t
            gapStart = start
            return t - start > config.continuousGrace ? .cancel : .hold // hand gone: interrupted
        }
        if matches {
            reset()
            return .track
        }
        // A confirmed different pose on a well-tracked hand — including `.none`, which is what in-between
        // shapes read as while fingers open or close — counts toward release. (Unreliable frames arrive as
        // untracked above.)
        gapStart = nil
        otherFrames += 1
        return otherFrames >= config.continuousReleaseFrames ? .release : .track
    }
}
