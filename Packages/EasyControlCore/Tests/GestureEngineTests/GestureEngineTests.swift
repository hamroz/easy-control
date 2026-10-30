import Testing
import HandTracking
import Signal
import TestSupport
@testable import GestureEngine

private func run(_ frames: [HandFrame], lastUserInput: (HandFrame) -> Double? = { _ in nil }) -> [GestureEvent] {
    let engine = GestureEngine()
    return frames.flatMap { engine.process($0, lastUserInput: lastUserInput($0)) }
}

private func isEngaged(_ e: GestureEvent) -> Bool {
    if case .engagement(.engaged) = e { return true }
    return false
}

private func scrollEvents(_ events: [GestureEvent]) -> [GestureEvent] {
    events.filter { if case .continuous(.scroll, _, _) = $0 { return true }; return false }
}

private func engagedScript() -> FrameScript {
    var s = FrameScript()
    s.hold(.openPalm, at: [0.5, 0.5], for: 0.6)
    return s
}

@Test func palmSwipeAfterEngageSwitches() {
    var s = engagedScript()
    s.move(.openPalm, from: [0.5, 0.5], to: [0.25, 0.5], over: 0.2)
    s.hold(.openPalm, at: [0.25, 0.5], for: 0.2)
    let events = run(s.frames)
    #expect(events.contains(where: isEngaged))
    #expect(events.filter { if case .discrete = $0 { return true }; return false } == [.discrete(.swipeLeft)])
}

@Test func noGesturesWhenIdle() {
    var s = FrameScript()
    s.move(.openPalm, from: [0.6, 0.5], to: [0.3, 0.5], over: 0.2)
    #expect(!run(s.frames).contains { if case .discrete = $0 { return true }; return false })
}

@Test func scrollAfterEngage() {
    var s = engagedScript()
    s.hold(.two, at: [0.5, 0.5], for: 0.2)
    s.move(.two, from: [0.5, 0.5], to: [0.5, 0.7], over: 0.5)
    s.hold(.openPalm, at: [0.5, 0.7], for: 0.3)
    let scrolls = scrollEvents(run(s.frames))
    #expect(scrolls.first == .continuous(.scroll, phase: .began, delta: .zero))
    #expect(scrolls.last == .continuous(.scroll, phase: .ended, delta: .zero))
    #expect(scrolls.contains { if case .continuous(_, .changed, _) = $0 { return true }; return false })
}

@Test func handLostMidScrollEndsScroll() {
    var s = engagedScript()
    s.hold(.two, at: [0.5, 0.5], for: 0.2)
    s.move(.two, from: [0.5, 0.5], to: [0.5, 0.6], over: 0.3)
    s.empty(for: 1.1)
    let events = run(s.frames)
    let ended = events.firstIndex(of: .continuous(.scroll, phase: .cancelled, delta: .zero))
    let standby = events.firstIndex(of: .engagement(.standby))
    #expect(ended != nil && standby != nil)
    #expect(ended! < standby!)
}

@Test func secondHandIsIgnored() {
    var s = engagedScript()
    let n = 15
    for i in 0..<n {
        let other = SyntheticHand.make(.two, center: [0.15, 0.15 + 0.01 * Float(i)])
        s.appendFrame([SyntheticHand.make(.openPalm, center: [0.5, 0.5]), other])
    }
    let other = SyntheticHand.make(.two, center: [0.15, 0.3])
    for i in 1...12 {
        let x = 0.5 + 0.25 * Float(min(i, 6)) / 6
        s.appendFrame([SyntheticHand.make(.openPalm, center: [x, 0.5]), other])
    }
    let events = run(s.frames)
    #expect(scrollEvents(events).isEmpty)
    #expect(events.contains(.discrete(.swipeRight)))
}

@Test func typingSuppressesMidScroll() {
    var s = engagedScript()
    s.hold(.two, at: [0.5, 0.5], for: 0.2)
    s.move(.two, from: [0.5, 0.5], to: [0.5, 0.6], over: 0.3)
    let typedAt = s.now
    s.move(.two, from: [0.5, 0.6], to: [0.5, 0.8], over: 0.4)
    let events = run(s.frames) { $0.timestamp >= typedAt ? typedAt : nil }
    let scrolls = scrollEvents(events)
    #expect(scrolls.last == .continuous(.scroll, phase: .cancelled, delta: .zero))
    #expect(scrolls.filter { $0 == .continuous(.scroll, phase: .began, delta: .zero) }.count == 1)
}

@Test func lowConfidenceFramesProduceNothing() {
    var s = engagedScript()
    for i in 1...8 {
        var hand = SyntheticHand.make(.openPalm, center: [0.5 - 0.04 * Float(i), 0.5])
        hand[.wrist].confidence = 0.1
        s.appendFrame([hand])
    }
    let events = run(s.frames)
    #expect(!events.contains { if case .discrete = $0 { return true }; return false })
    #expect(scrollEvents(events).isEmpty)
}

@Test func recordingReplayMatchesGolden() throws {
    var s = engagedScript()
    s.move(.openPalm, from: [0.5, 0.5], to: [0.25, 0.5], over: 0.2)
    s.hold(.two, at: [0.25, 0.5], for: 0.2)
    s.move(.two, from: [0.25, 0.5], to: [0.25, 0.7], over: 0.4)
    let replayed = try HandFrameRecording.decode(HandFrameRecording.encode(s.frames))
    let direct = run(s.frames)
    #expect(!direct.isEmpty)
    #expect(run(replayed) == direct)
}

@Test func shortDropoutKeepsEngagementAndSwipe() {
    var s = engagedScript()
    s.empty(for: 0.3)
    s.hold(.openPalm, at: [0.5, 0.5], for: 0.2)
    s.move(.openPalm, from: [0.5, 0.5], to: [0.25, 0.5], over: 0.2)
    s.hold(.openPalm, at: [0.25, 0.5], for: 0.2)
    let events = run(s.frames)
    #expect(events.contains(.discrete(.swipeLeft)))
    #expect(!events.contains(.engagement(.idle)) && !events.contains(.engagement(.standby)))
}

@Test func handDropAfterEngageDoesNothing() {
    var s = engagedScript()
    s.move(.openPalm, from: [0.5, 0.5], to: [0.5, 0.95], over: 0.25)
    s.empty(for: 1.2)
    #expect(!run(s.frames).contains { if case .discrete = $0 { return true }; return false })
}
