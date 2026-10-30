import Foundation
import Testing
import HandTracking
import TestSupport
@testable import Signal

private func close(_ a: [SIMD2<Float>], _ b: [SIMD2<Float>], tol: Float = 1e-3) -> Bool {
    zip(a, b).allSatisfy { abs($0.x - $1.x) < tol && abs($0.y - $1.y) < tol }
}

private func rotated(_ hand: Hand, by angle: Float) -> Hand {
    var out = hand
    let pivot = hand[.wrist].position
    let (c, s) = (cos(angle), sin(angle))
    for i in out.joints.indices {
        let p = out.joints[i].position - pivot
        out.joints[i].position = pivot + [c * p.x - s * p.y, s * p.x + c * p.y]
    }
    return out
}

@Test func normalizationIsTranslationAndScaleInvariant() {
    let a = HandFeatureExtractor.extract(SyntheticHand.make(.openPalm, center: [0.3, 0.4], palmSize: 0.1))
    let b = HandFeatureExtractor.extract(SyntheticHand.make(.openPalm, center: [0.7, 0.6], palmSize: 0.2))
    #expect(close(a.normalized, b.normalized))
}

@Test func normalizationIsRotationInvariant() {
    let hand = SyntheticHand.make(.openPalm)
    let a = HandFeatureExtractor.extract(hand)
    let b = HandFeatureExtractor.extract(rotated(hand, by: .pi / 6))
    #expect(close(a.normalized, b.normalized))
}

@Test func leftHandMirrorsToRight() {
    let right = HandFeatureExtractor.extract(SyntheticHand.make(.two, chirality: .right))
    let left = HandFeatureExtractor.extract(SyntheticHand.make(.two, chirality: .left))
    #expect(close(left.normalized, right.normalized))
}

@Test func extensionFlagsPerPose() {
    func flags(_ pose: SyntheticPose) -> [Bool] { HandFeatureExtractor.extract(SyntheticHand.make(pose)).fingerExtended }
    #expect(flags(.openPalm) == [true, true, true, true, true])
    #expect(Array(flags(.fist).dropFirst()) == [false, false, false, false])
    #expect(Array(flags(.two).dropFirst()) == [true, true, false, false])
    #expect(Array(flags(.point).dropFirst()) == [true, false, false, false])
}

@Test func lowConfidenceIsUnreliable() {
    var hand = SyntheticHand.make(.openPalm)
    hand[.wrist].confidence = 0.1
    #expect(HandFeatureExtractor.extract(hand).isReliable == false)
    #expect(HandFeatureExtractor.extract(SyntheticHand.make(.openPalm)).isReliable == true)
}

@Test func vectorLengthMatchesConstant() {
    #expect(HandFeatures.vectorLength == 55)
    #expect(HandFeatureExtractor.extract(SyntheticHand.make(.three)).vector.count == HandFeatures.vectorLength)
}

/// The same physical hand seen in an image of a different shape: normalized x shrinks by the aspect ratio.
private func seen(_ hand: Hand, inAspect aspect: Float) -> Hand {
    var out = hand
    for i in out.joints.indices { out.joints[i].position.x = 0.5 + (out.joints[i].position.x - 0.5) / aspect }
    out.aspectRatio = aspect
    return out
}

@Test func aspectCorrectionRecoversShape() {
    let square = SyntheticHand.make(.openPalm)
    let landscape = seen(square, inAspect: 4.0 / 3.0)  // 640×480 webcam
    let portrait = seen(square, inAspect: 512.0 / 683.0) // HaGRID 512px photo
    let a = HandFeatureExtractor.extract(square), b = HandFeatureExtractor.extract(landscape)
    let c = HandFeatureExtractor.extract(portrait)
    #expect(close(a.normalized, b.normalized))
    #expect(close(a.normalized, c.normalized))
    #expect(abs(a.palmSize - b.palmSize) < 1e-4)
}

@Test func orientationFeaturesIgnoreChirality() {
    var flipped = SyntheticHand.make(.two)
    flipped.chirality = .left // same joints, wrong left/right guess
    let a = HandFeatureExtractor.extract(SyntheticHand.make(.two)), b = HandFeatureExtractor.extract(flipped)
    #expect(zip(a.orientation, b.orientation).allSatisfy { abs($0 - $1) < 1e-5 })
    #expect(!close(a.normalized, b.normalized))
}

@Test func orientationTracksRotation() {
    let upright = HandFeatureExtractor.extract(SyntheticHand.make(.openPalm))
    let upsideDown = HandFeatureExtractor.extract(rotated(SyntheticHand.make(.openPalm), by: .pi))
    #expect(abs(upright.orientation[0] + upsideDown.orientation[0]) < 1e-4)
    #expect(abs(upright.orientation[1] + upsideDown.orientation[1]) < 1e-4)
    #expect(upright.orientation[2] > 0 && upsideDown.orientation[2] < 0) // thumb above / below the wrist
}
