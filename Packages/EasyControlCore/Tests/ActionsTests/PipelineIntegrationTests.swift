import Testing
import GestureEngine
import HandTracking
import TestSupport
@testable import Actions

/// Engine → dispatcher → recorded events: the layer boundary where stuck synthetic input hides.
private struct Rig {
    let engine = GestureEngine()
    let sink = RecordingEventSink()
    let dispatcher: ActionDispatcher

    init() {
        dispatcher = ActionDispatcher(sink: sink, spaces: ControlArrowStrategy(sink: sink), scroll: ScrollInjector(sink: sink))
    }

    func play(_ frames: [HandFrame], lastUserInput: (HandFrame) -> Double? = { _ in nil }) {
        for f in frames { dispatcher.handle(engine.process(f, lastUserInput: lastUserInput(f)), at: f.timestamp) }
    }

    func tick(from t: Double, count: Int = 120) {
        for i in 1...count { dispatcher.tick(at: t + Double(i) / 60) }
    }

    var momentumEvents: [SyntheticEvent] {
        sink.events.filter { if case .scroll(_, _, _, let m) = $0 { return m != .none }; return false }
    }
}

/// Engage, then a fast two-finger flick that is still moving at the end of the script.
private func flickScript() -> FrameScript {
    var s = FrameScript()
    s.hold(.openPalm, at: [0.5, 0.4], for: 0.6)
    s.hold(.two, at: [0.5, 0.4], for: 0.2)
    s.move(.two, from: [0.5, 0.4], to: [0.5, 0.7], over: 0.3)
    return s
}

@Test func releasedFlickCoastsWithMomentum() {
    let rig = Rig()
    var s = flickScript()
    s.hold(.openPalm, at: [0.5, 0.7], for: 0.2)
    rig.play(s.frames)
    rig.tick(from: s.now)
    #expect(!rig.momentumEvents.isEmpty)
}

@Test func typingMidFlickPostsNoMomentum() {
    let rig = Rig()
    var s = flickScript()
    let typedAt = s.now
    s.move(.two, from: [0.5, 0.7], to: [0.5, 0.75], over: 0.1)
    rig.play(s.frames) { $0.timestamp >= typedAt ? typedAt : nil }
    rig.tick(from: s.now)
    #expect(rig.momentumEvents.isEmpty)
}

@Test func pauseMidFlickPostsNoMomentum() {
    let rig = Rig()
    let s = flickScript()
    rig.play(s.frames)
    rig.dispatcher.handle(rig.engine.setPaused(true, at: s.now), at: s.now)
    rig.tick(from: s.now)
    #expect(rig.momentumEvents.isEmpty)
    #expect(!rig.dispatcher.isMomentumActive)
}

@Test func userInputStopsRunningMomentum() {
    let rig = Rig()
    var s = flickScript()
    s.hold(.openPalm, at: [0.5, 0.7], for: 0.2)
    rig.play(s.frames)
    rig.tick(from: s.now, count: 3)
    #expect(rig.dispatcher.isMomentumActive)
    rig.dispatcher.cancelMomentum()
    #expect(!rig.dispatcher.isMomentumActive)
    let before = rig.sink.events.count
    rig.tick(from: s.now + 0.05)
    #expect(rig.sink.events.count == before)
    if case .scroll(_, _, _, let m) = rig.sink.events.last { #expect(m == .ended) }
}
