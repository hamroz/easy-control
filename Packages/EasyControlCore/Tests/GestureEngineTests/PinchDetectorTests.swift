import Testing
import HandTracking
import TestSupport
@testable import GestureEngine

private func reading(_ d: inout PinchDetector, _ hand: Hand, at t: Double) -> PinchReading? { d.update(hand, at: t) }

@Test func pinchClosesAndOpensWithHysteresis() {
    var d = PinchDetector(config: .default)
    #expect(reading(&d, SyntheticHand.make(.pinch, pinchOpenness: 1), at: 0)?.index == false)
    #expect(reading(&d, SyntheticHand.make(.pinch, pinchOpenness: 0.1), at: 0.033)?.index == true)
    #expect(reading(&d, SyntheticHand.make(.pinch, pinchOpenness: 0.3), at: 0.066)?.index == true)   // between thresholds: stays closed
    #expect(reading(&d, SyntheticHand.make(.pinch, pinchOpenness: 0.5), at: 0.1)?.index == false)    // past the open threshold
    #expect(reading(&d, SyntheticHand.make(.pinch, pinchOpenness: 0.3), at: 0.133)?.index == false)  // between thresholds: stays open
}

@Test func middlePinchIsSeparate() {
    var d = PinchDetector(config: .default)
    let r = reading(&d, SyntheticHand.make(.pinchMiddle, pinchOpenness: 0), at: 0)
    #expect(r?.middle == true && r?.index == false)
}

@Test func lowTipConfidenceHoldsThenCancels() {
    var d = PinchDetector(config: .default)
    _ = reading(&d, SyntheticHand.make(.pinch, pinchOpenness: 0), at: 0)
    var blurred = SyntheticHand.make(.pinch, pinchOpenness: 0)
    blurred[.thumbTip].confidence = 0.1
    #expect(reading(&d, blurred, at: 0.1)?.index == true) // held
    #expect(reading(&d, blurred, at: 0.3) == nil)          // beyond the hold: unknown
}

@Test func ratioIsScaleInvariant() {
    var a = PinchDetector(config: .default), b = PinchDetector(config: .default)
    let ra = reading(&a, SyntheticHand.make(.pinch, palmSize: 0.08, pinchOpenness: 0.6), at: 0)!.ratio
    let rb = reading(&b, SyntheticHand.make(.pinch, palmSize: 0.2, pinchOpenness: 0.6), at: 0)!.ratio
    #expect(abs(ra - rb) < 1e-3)
}

@Test func fistWithThumbOnIndexIsNotPinch() {
    // A curled index (tip pulled into the palm) with the thumb resting on it: touching, but not a pinch.
    var fist = SyntheticHand.make(.fist)
    let s: Float = 0.12, center = SIMD2<Float>(0.5, 0.5)
    fist[.indexTip].position = center + [-0.2 * s, 0.45 * s]
    fist[.thumbTip].position = fist[.indexTip].position + [0.01 * s, 0]
    var d = PinchDetector(config: .default)
    #expect(d.update(fist, at: 0)?.index == false)
}
