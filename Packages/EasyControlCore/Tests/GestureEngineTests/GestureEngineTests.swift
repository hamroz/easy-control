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

private func buttons(_ events: [GestureEvent]) -> [GestureEvent] {
    events.filter { if case .button = $0 { return true }; return false }
}

private func scrollEvents(_ events: [GestureEvent]) -> [GestureEvent] {
    events.filter { if case .continuous(.scroll, _, _) = $0 { return true }; return false }
}

private func engagedScript() -> FrameScript {
    var s = FrameScript()
    s.hold(.openPalm, at: [0.5, 0.5], for: 0.5)
    return s
}

@Test func pinchTapAfterEngageClicks() {
    var s = engagedScript()
    s.hold(.pinch, at: [0.5, 0.5], for: 0.13)
    s.hold(.openPalm, at: [0.5, 0.5], for: 0.3)
    let events = run(s.frames)
    #expect(events.contains(where: isEngaged))
    let clicks = buttons(events)
    #expect(clicks.count == 1)
    guard case .button(.left, .click(count: 1), _)? = clicks.first else {
        Issue.record("expected a left click, got \(clicks)")
        return
    }
}

@Test func pinchWhileNotEngagedDoesNothing() {
    var s = FrameScript()
    s.hold(.pinch, at: [0.5, 0.5], for: 1)
    s.hold(.openPalm, at: [0.5, 0.5], for: 0.2) // releasing, but never engaged
    #expect(buttons(run(s.frames)).isEmpty)
}

@Test func hoverMovesPointer() {
    var s = engagedScript()
    s.move(.openPalm, from: [0.5, 0.5], to: [0.6, 0.5], over: 0.3)
    let xs = run(s.frames).compactMap { e -> Float? in if case .pointerTrack(let p, _) = e { return p.x }; return nil }
    #expect(xs.count > 5)
    #expect(xs.last! > xs.first! + 0.05)
}

@Test func pinchScrollAfterEngage() {
    var s = engagedScript()
    s.hold(.pinch, at: [0.5, 0.5], for: 0.1)
    s.move(.pinch, from: [0.5, 0.5], to: [0.5, 0.65], over: 0.3)
    s.hold(.openPalm, at: [0.5, 0.65], for: 0.3)
    let scrolls = scrollEvents(run(s.frames))
    guard case .continuous(.scroll, .began, _)? = scrolls.first else {
        Issue.record("expected a pinch scroll, got \(scrolls)")
        return
    }
    #expect(scrolls.last == .continuous(.scroll, phase: .ended, delta: .zero))
}

@Test func handLostMidScrollCancelsBeforeStandby() {
    var s = engagedScript()
    s.hold(.pinch, at: [0.5, 0.5], for: 0.1)
    s.move(.pinch, from: [0.5, 0.5], to: [0.5, 0.6], over: 0.3)
    s.empty(for: 1.1)
    let events = run(s.frames)
    let cancelled = events.firstIndex(of: .continuous(.scroll, phase: .cancelled, delta: .zero))
    let standby = events.firstIndex(of: .engagement(.standby))
    #expect(cancelled != nil && standby != nil)
    #expect(cancelled! < standby!)
}

@Test func typingDuringDragReleasesButton() {
    var s = engagedScript()
    s.hold(.pinch, at: [0.5, 0.5], for: 0.6)                       // held still: drag starts
    s.move(.pinch, from: [0.5, 0.5], to: [0.55, 0.5], over: 0.2)
    let typedAt = s.now
    s.move(.pinch, from: [0.55, 0.5], to: [0.6, 0.5], over: 0.2)
    let events = run(s.frames) { $0.timestamp >= typedAt ? typedAt : nil }
    let actions = buttons(events).compactMap { e -> ButtonAction? in if case .button(.left, let a, _) = e { return a }; return nil }
    #expect(actions == [.down, .up])
}

@Test func secondHandPinchIsIgnored() {
    var s = engagedScript()
    for i in 0..<12 {
        let other = SyntheticHand.make(.pinch, center: [0.15, 0.2], pinchOpenness: i % 6 < 3 ? 0 : 1)
        s.appendFrame([SyntheticHand.make(.openPalm, center: [0.5, 0.5]), other])
    }
    #expect(buttons(run(s.frames)).isEmpty)
}

@Test func lowConfidenceFramesProduceNothing() {
    var s = engagedScript()
    for i in 1...8 {
        var hand = SyntheticHand.make(.pinch, center: [0.5 - 0.04 * Float(i), 0.5])
        hand[.wrist].confidence = 0.1
        s.appendFrame([hand])
    }
    let events = run(s.frames)
    #expect(buttons(events).isEmpty)
    #expect(scrollEvents(events).isEmpty)
}

@Test func recordingReplayMatchesGolden() throws {
    var s = engagedScript()
    s.move(.openPalm, from: [0.5, 0.5], to: [0.4, 0.5], over: 0.2)
    s.hold(.pinch, at: [0.4, 0.5], for: 0.13)
    s.hold(.openPalm, at: [0.4, 0.5], for: 0.2)
    s.hold(.pinch, at: [0.4, 0.5], for: 0.1)
    s.move(.pinch, from: [0.4, 0.5], to: [0.4, 0.7], over: 0.3)
    let replayed = try HandFrameRecording.decode(HandFrameRecording.encode(s.frames))
    let direct = run(s.frames)
    #expect(!buttons(direct).isEmpty && !scrollEvents(direct).isEmpty)
    #expect(run(replayed) == direct)
}

@Test func shortDropoutKeepsEngagement() {
    var s = engagedScript()
    s.empty(for: 0.3)
    s.move(.openPalm, from: [0.5, 0.5], to: [0.6, 0.5], over: 0.2)
    let events = run(s.frames)
    #expect(!events.contains(.engagement(.idle)) && !events.contains(.engagement(.standby)))
    let lift = events.firstIndex(of: .pointerLift)!
    #expect(events[lift...].contains { if case .pointerTrack = $0 { return true }; return false })
}

@Test func handDropAfterEngageDoesNothing() {
    var s = engagedScript()
    s.move(.openPalm, from: [0.5, 0.5], to: [0.5, 0.95], over: 0.25)
    s.empty(for: 1.2)
    let events = run(s.frames)
    #expect(buttons(events).isEmpty && scrollEvents(events).isEmpty)
}
