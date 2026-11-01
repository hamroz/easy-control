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
    #expect(abs(s.x - 0.13) < 1e-3 && s.y == 0)
}

@Test func predictorCapsAtHorizon() {
    var p = MotionPredictor()
    p.update([0, 0], at: 0)
    p.update([0.1, 0], at: 1.0 / 30)
    let s = p.sample(at: 1.0 / 30 + 0.5)!
    #expect(abs(s.x - (0.1 + 3 * 0.033)) < 1e-3) // velocity 3/s, at most 33 ms ahead
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
