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

@Test func handLostEntersStandby() {
    var c = EngagementController(config: .default)
    var t = feed(&c, [obs(.openPalm)], from: 0, for: 0.5)
    t = feed(&c, [], from: t, for: 1.0)
    #expect(c.state == .engaged(hand: 1, mode: .command))
    feed(&c, [], from: t, for: 0.2)
    #expect(c.state == .standby)
}

@Test func idleTimeoutEntersStandby() {
    var c = EngagementController(config: .default)
    let t = feed(&c, [obs(.openPalm)], from: 0, for: 0.5)
    feed(&c, [obs(.openPalm)], from: t, for: 3.1)
    #expect(c.state == .standby)

    var d = EngagementController(config: .default)
    var u = feed(&d, [obs(.openPalm)], from: 0, for: 0.5)
    u = feed(&d, [obs(.openPalm)], from: u, for: 2.0)
    d.noteActivity(at: u)
    feed(&d, [obs(.openPalm)], from: u, for: 1.1)
    #expect(d.state == .engaged(hand: 1, mode: .command))
}

@Test func handLostEntersStandbyAndReturnResumes() {
    var c = EngagementController(config: .default)
    var t = feed(&c, [obs(.openPalm)], from: 0, for: 0.5)
    t = feed(&c, [], from: t, for: 2)
    #expect(c.state == .standby)
    t = feed(&c, [obs(.none, id: 2)], from: t, for: 2.0 / 30) // returning hand, pose not yet stable
    #expect(c.state == .standby)
    _ = c.update(hands: [obs(.openPalm, id: 2)], at: t)        // first gesture frame: no hold needed
    #expect(c.state == .engaged(hand: 2, mode: .command))
}

@Test func switchingToScrollPoseResumesFromStandby() {
    var c = EngagementController(config: .default)
    var t = feed(&c, [obs(.openPalm)], from: 0, for: 0.5)
    t = feed(&c, [obs(.openPalm)], from: t, for: 3.2) // idle → standby, palm still raised
    #expect(c.state == .standby)
    _ = c.update(hands: [obs(.two)], at: t)
    #expect(c.state == .engaged(hand: 1, mode: .command))
}

@Test func stillPalmDoesNotFlap() {
    var c = EngagementController(config: .default)
    var changes: [EngagementState] = []
    for i in 0..<(30 * 20) {
        if let s = c.update(hands: [obs(.openPalm)], at: Double(i) / 30) { changes.append(s) }
    }
    #expect(changes == [.engaged(hand: 1, mode: .command), .standby, .idle])
}

@Test func standbyExpiresToIdle() {
    var c = EngagementController(config: .default)
    let t = feed(&c, [obs(.openPalm)], from: 0, for: 0.5)
    feed(&c, [], from: t, for: 16.2)
    #expect(c.state == .idle)
}

@Test func relaxedHandDoesNotResume() {
    var c = EngagementController(config: .default)
    var t = feed(&c, [obs(.openPalm)], from: 0, for: 0.5)
    t = feed(&c, [], from: t, for: 1.2)
    feed(&c, [obs(.none, id: 3)], from: t, for: 2)
    feed(&c, [obs(.fist, id: 3)], from: t + 2, for: 2)
    #expect(c.state == .standby)
}

@Test func twoOrThreeFingersEngageDirectly() {
    for pose in [PoseClass.two, .three] {
        var c = EngagementController(config: .default)
        let t = feed(&c, [obs(pose)], from: 0, for: 0.25)
        #expect(c.state == .idle)
        feed(&c, [obs(pose)], from: t, for: 0.1)
        #expect(c.state == .engaged(hand: 1, mode: .command), "\(pose)")
    }
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
