import Testing
@testable import GestureEngine

private func obs(_ pose: PoseClass, id: Int = 1, size: Float = 0.12) -> HandObservation {
    HandObservation(id: id, pose: pose, palmSize: size, palmCenter: [0.5, 0.5])
}

/// Feeds `hands` at 30 fps from `start` for `seconds`; returns the controller state afterwards and the end time.
@discardableResult
private func feed(_ c: inout EngagementController, _ hands: [HandObservation], from start: Double, for seconds: Double) -> Double {
    let n = Int((seconds * 30).rounded())
    for i in 0..<n { _ = c.update(hands: hands, at: start + Double(i) / 30) }
    return start + Double(n) / 30
}

@Test func engagesAfterWakeHold() {
    var c = EngagementController(config: .default)
    var t = feed(&c, [obs(.openPalm)], from: 0, for: 0.3)
    #expect(c.state == .idle)
    t = feed(&c, [obs(.openPalm)], from: t, for: 0.2)
    #expect(c.state == .engaged(hand: 1, mode: .command))
}

@Test func smallDistantHandDoesNotEngage() {
    var c = EngagementController(config: .default)
    feed(&c, [obs(.openPalm, size: 0.04)], from: 0, for: 2)
    #expect(c.state == .idle)
}

@Test func interruptedHoldRestarts() {
    var c = EngagementController(config: .default)
    var t = feed(&c, [obs(.openPalm)], from: 0, for: 0.3)
    t = feed(&c, [obs(.fist)], from: t, for: 1.0 / 30)
    feed(&c, [obs(.openPalm)], from: t, for: 0.3)
    #expect(c.state == .idle)
}

@Test func disengagesWhenHandLost() {
    var c = EngagementController(config: .default)
    var t = feed(&c, [obs(.openPalm)], from: 0, for: 0.5)
    #expect(c.state != .idle)
    t = feed(&c, [], from: t, for: 1.0)
    #expect(c.state != .idle)
    feed(&c, [], from: t, for: 0.2)
    #expect(c.state == .idle)
}

@Test func disengagesAfterIdleTimeout() {
    var c = EngagementController(config: .default)
    let t = feed(&c, [obs(.openPalm)], from: 0, for: 0.5)
    feed(&c, [obs(.openPalm)], from: t, for: 3.1)
    #expect(c.state == .idle)

    var d = EngagementController(config: .default)
    var u = feed(&d, [obs(.openPalm)], from: 0, for: 0.5)
    u = feed(&d, [obs(.openPalm)], from: u, for: 2.0)
    d.noteActivity(at: u)
    feed(&d, [obs(.openPalm)], from: u, for: 1.1)
    #expect(d.state == .engaged(hand: 1, mode: .command))
}

@Test func noReengageWithoutRelease() {
    var c = EngagementController(config: .default)
    let t = feed(&c, [obs(.openPalm)], from: 0, for: 0.5)
    feed(&c, [obs(.openPalm)], from: t, for: 5)
    #expect(c.state == .idle)
}

@Test func largestPalmWins() {
    var c = EngagementController(config: .default)
    feed(&c, [obs(.openPalm, id: 1, size: 0.08), obs(.openPalm, id: 2, size: 0.12)], from: 0, for: 0.5)
    #expect(c.state == .engaged(hand: 2, mode: .command))
}

@Test func pausedIgnoresHands() {
    var c = EngagementController(config: .default)
    #expect(c.setPaused(true, at: 0) == .paused)
    feed(&c, [obs(.openPalm)], from: 0, for: 1)
    #expect(c.state == .paused)
    #expect(c.setPaused(false, at: 1) == .idle)
}
