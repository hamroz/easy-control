import Testing
@testable import Signal

@Test func predictorNilBeforeFirstUpdate() {
    #expect(MotionPredictor().sample(at: 0) == nil)
}

@Test func predictorExtrapolatesWithinHorizon() {
    var p = MotionPredictor()
    p.update([0, 0], at: 0)
    p.update([0.1, 0], at: 1.0 / 30)
    let s = p.sample(at: 1.0 / 30 + 0.01)!
    #expect(abs(s.x - 0.115) < 1e-3 && s.y == 0) // half-strength: 0.1 + 3/s × 0.01 s × 0.5
}

@Test func predictorCapsAtHorizon() {
    var p = MotionPredictor()
    p.update([0, 0], at: 0)
    p.update([0.1, 0], at: 1.0 / 30)
    let s = p.sample(at: 1.0 / 30 + 0.5)!
    #expect(abs(s.x - (0.1 + 3 * 0.033 * 0.5)) < 1e-3) // velocity 3/s, at most 33 ms ahead, half strength
}

@Test func predictorHoldsWhenSlow() {
    var p = MotionPredictor()
    p.update([0.5, 0.5], at: 0)
    p.update([0.5005, 0.5], at: 1.0 / 30) // 0.015/s: below the speed floor
    #expect(p.sample(at: 0.06) == [0.5005, 0.5])
}

@Test func predictorResetsAfterGap() {
    var p = MotionPredictor()
    p.update([0, 0], at: 0)
    p.update([0.1, 0], at: 1.0 / 30)
    p.update([0.2, 0], at: 1.0) // long gap: no velocity carried over
    #expect(p.sample(at: 1.02) == [0.2, 0])
}

@Test func deadbandIgnoresTremor() {
    var d = Deadband(radius: 0.004)
    #expect(d.filter([0.502, 0.5]) == [0.502, 0.5])
    #expect(d.filter([0.498, 0.5]) == [0.502, 0.5]) // 0.004 away: still inside
    #expect(d.filter([0.5015, 0.501]) == [0.502, 0.5])
}

@Test func deadbandFollowsRealMotionWithSlack() {
    var d = Deadband(radius: 0.004)
    _ = d.filter([0.5, 0.5])
    let out = d.filter([0.52, 0.5])
    #expect(abs(out.x - 0.516) < 1e-5 && out.y == 0.5) // dragged along, `radius` behind
}
