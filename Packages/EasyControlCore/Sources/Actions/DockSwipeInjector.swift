import GestureEngine

/// Turns three-finger drags into the Dock's own swipe: the Spaces strip or Mission Control follows the hand,
/// and on release the Dock commits or snaps back from the velocity, as with a trackpad. Without the private
/// API, a long enough drag falls back to the Space / Mission Control keystrokes on release.
/// Not thread-safe: own it from the pipeline's serial queue.
public final class DockSwipeInjector {
    private let sink: any EventSink
    private let spaces: any SpaceSwitchStrategy
    /// Hand travel (frame heights) that moves one full Space / Mission Control transition.
    private let handTravelPerSpace: Float
    private static let resendDelays = [0.2, 0.5]
    private static let fallbackThreshold = 0.5

    private var motion: DockMotion?
    private var progress = 0.0
    private var lastDelta = 0.0
    private var resends: [(at: Double, event: SyntheticEvent)] = []

    public init(sink: any EventSink, spaces: any SpaceSwitchStrategy, handTravelPerSpace: Float = 0.25) {
        self.sink = sink
        self.spaces = spaces
        self.handTravelPerSpace = handTravelPerSpace
    }

    public var isActive: Bool { motion != nil }
    /// True while end events are waiting to be re-sent (they clear the Dock's occasional stuck transition).
    public var needsTicks: Bool { !resends.isEmpty }

    public func handle(_ id: GestureID, phase: Phase, delta: SIMD2<Float>, at t: Double) {
        let axis: DockMotion = id == .dockSwipeVertical ? .vertical : .horizontal
        // Natural direction: hand right shows the Space on the left; hand up opens Mission Control.
        let step = Double(axis == .horizontal ? delta.x : -delta.y) / Double(handTravelPerSpace)
        switch phase {
        case .began:
            motion = axis
            progress = 0
            post(.began)
            if step != 0 { apply(step) }
        case .changed:
            guard motion != nil else { return }
            apply(step)
        case .ended:
            guard motion != nil else { return }
            let reversed = progress != 0 && lastDelta != 0 && (lastDelta > 0) != (progress > 0)
            finish(reversed ? .cancelled : .ended, at: t)
        case .cancelled:
            guard motion != nil else { return }
            finish(.cancelled, at: t)
        }
    }

    /// Interrupts an open swipe (typing, pause): the Dock snaps back.
    public func cancelActive(at t: Double) {
        if motion != nil { finish(.cancelled, at: t) }
    }

    public func tick(at t: Double) {
        let due = resends.filter { $0.at <= t }
        resends.removeAll { $0.at <= t }
        due.forEach { sink.post($0.event) }
    }

    private func apply(_ step: Double) {
        progress += step
        lastDelta = step
        post(.changed)
    }

    private func post(_ phase: DockPhase, velocity: Double = 0) {
        guard let motion, sink.supportsDockSwipe else { return }
        sink.post(.dockSwipe(motion: motion, phase: phase, progress: progress, velocity: velocity))
    }

    private func finish(_ phase: DockPhase, at t: Double) {
        guard let axis = motion else { return }
        if sink.supportsDockSwipe {
            let event = SyntheticEvent.dockSwipe(motion: axis, phase: phase, progress: progress, velocity: lastDelta * 100)
            sink.post(event)
            resends += Self.resendDelays.map { (t + $0, event) }
        } else if phase == .ended, abs(progress) >= Self.fallbackThreshold {
            switch (axis, progress > 0) {
            case (.horizontal, true): spaces.switchSpace(.left)
            case (.horizontal, false): spaces.switchSpace(.right)
            case (.vertical, true): sink.press(KeyCode.upArrow, flags: KeyFlags.controlArrow)
            case (.vertical, false): sink.press(KeyCode.downArrow, flags: KeyFlags.controlArrow)
            }
        }
        motion = nil
        progress = 0
        lastDelta = 0
    }
}
