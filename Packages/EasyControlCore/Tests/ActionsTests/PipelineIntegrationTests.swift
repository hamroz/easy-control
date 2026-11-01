import Testing
import GestureEngine
import HandTracking
import TestSupport
@testable import Actions

/// Engine → output loop (display rate) → recorded events: the layer boundary where stuck input hides.
private struct Rig {
    let engine = GestureEngine()
    let sink = RecordingEventSink()
    let loop: OutputLoop

    init() {
        loop = OutputLoop(sink: sink, environment: FakeEnvironment(), spaces: ControlArrowStrategy(sink: sink))
    }

    func play(_ frames: [HandFrame], lastUserInput: (HandFrame) -> Double? = { _ in nil }) {
        for f in frames {
            loop.receive(engine.process(f, lastUserInput: lastUserInput(f)), at: f.timestamp)
            for k in 0..<4 { loop.step(at: f.timestamp + Double(k) / 120) }
        }
    }

    func tick(from t: Double, count: Int = 240) {
        for i in 1...count { loop.step(at: t + Double(i) / 120) }
    }

    var momentumEvents: [SyntheticEvent] {
        sink.events.filter { if case .scroll(_, _, _, let m) = $0 { return m != .none }; return false }
    }
}

/// Engage, then a fast pinch flick that is still moving at the end of the script.
private func flickScript() -> FrameScript {
    var s = FrameScript()
    s.hold(.openPalm, at: [0.5, 0.4], for: 0.6)
    s.hold(.pinch, at: [0.5, 0.4], for: 0.1)
    s.move(.pinch, from: [0.5, 0.4], to: [0.5, 0.7], over: 0.3)
    return s
}

@Test func releasedFlickCoastsWithMomentum() {
    let rig = Rig()
    var s = flickScript()
    s.move(.openPalm, from: [0.5, 0.7], to: [0.5, 0.9], over: 0.2) // flick: the hand keeps moving as the pose opens
    rig.play(s.frames)
    rig.tick(from: s.now)
    #expect(!rig.momentumEvents.isEmpty)
}

@Test func typingMidFlickPostsNoMomentum() {
    let rig = Rig()
    var s = flickScript()
    let typedAt = s.now
    s.move(.pinch, from: [0.5, 0.7], to: [0.5, 0.75], over: 0.1)
    rig.play(s.frames) { $0.timestamp >= typedAt ? typedAt : nil }
    rig.tick(from: s.now)
    #expect(rig.momentumEvents.isEmpty)
}

@Test func pauseMidFlickPostsNoMomentum() {
    let rig = Rig()
    let s = flickScript()
    rig.play(s.frames)
    rig.loop.receive(rig.engine.setPaused(true, at: s.now), at: s.now)
    rig.loop.cancelAll(at: s.now)
    rig.tick(from: s.now)
    #expect(rig.momentumEvents.isEmpty)
    #expect(!rig.loop.needsFrames) // nothing left coasting, open or held
}

@Test func userInputStopsRunningMomentum() {
    let rig = Rig()
    var s = flickScript()
    s.move(.openPalm, from: [0.5, 0.7], to: [0.5, 0.9], over: 0.2)
    rig.play(s.frames)
    rig.tick(from: s.now, count: 3)
    #expect(!rig.momentumEvents.isEmpty) // coasting
    rig.loop.cancelMomentum(at: s.now + 0.03)
    let scrolls = { rig.sink.events.filter { if case .scroll = $0 { return true }; return false } }
    let before = scrolls().count
    rig.tick(from: s.now + 0.05)
    #expect(scrolls().count == before) // the pointer may still move; scrolling must not
    if case .scroll(_, _, _, let m) = scrolls().last { #expect(m == .ended) }
}

@Test func pauseDuringDragReleasesButton() {
    let rig = Rig()
    var s = FrameScript()
    s.hold(.openPalm, at: [0.5, 0.5], for: 0.5)
    s.hold(.pinch, at: [0.5, 0.5], for: 0.6)                     // held still: drag starts
    s.move(.pinch, from: [0.5, 0.5], to: [0.6, 0.5], over: 0.2)
    rig.play(s.frames)
    rig.loop.receive(rig.engine.setPaused(true, at: s.now), at: s.now)
    rig.loop.cancelAll(at: s.now)
    let kinds = rig.sink.events.compactMap { e -> MouseKind? in if case let .mouse(k, _, _, _) = e { return k }; return nil }
    #expect(kinds.filter { $0 == .leftDown }.count == 1)
    #expect(kinds.last == .leftUp)
}
