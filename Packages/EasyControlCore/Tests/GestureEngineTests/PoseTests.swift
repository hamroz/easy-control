import Testing
import HandTracking
import Signal
import TestSupport
@testable import GestureEngine

private func classify(_ pose: SyntheticPose) -> [PoseClass: Float] {
    RuleBasedPoseClassifier().classify(HandFeatureExtractor.extract(SyntheticHand.make(pose)))
}

@Test func rulesClassifySyntheticPoses() {
    let expected: [(SyntheticPose, PoseClass)] = [
        (.openPalm, .openPalm), (.fist, .fist), (.point, .point), (.two, .two), (.three, .three),
    ]
    for (pose, cls) in expected {
        #expect(classify(pose) == [cls: 1], "\(pose)")
    }
}

@Test func unreliableIsNone() {
    var hand = SyntheticHand.make(.openPalm)
    hand[.wrist].confidence = 0.1
    #expect(RuleBasedPoseClassifier().classify(HandFeatureExtractor.extract(hand)) == [.none: 1])
}

@Test func stabilizerNeedsThreeFrames() {
    var s = PoseStabilizer(config: .default)
    #expect(s.update([.openPalm: 1]) == .none)
    #expect(s.update([.openPalm: 1]) == .none)
    #expect(s.update([.openPalm: 1]) == .openPalm)
}

@Test func stabilizerIgnoresSingleFrameFlicker() {
    var s = PoseStabilizer(config: .default)
    for _ in 0..<3 { _ = s.update([.openPalm: 1]) }
    #expect(s.update([.fist: 1]) == .openPalm)
    #expect(s.update([.openPalm: 1]) == .openPalm)
}

@Test func stabilizerExitsBelowThreshold() {
    var s = PoseStabilizer(config: .default)
    for _ in 0..<3 { _ = s.update([.openPalm: 1]) }
    #expect(s.update([.openPalm: 0.5, .none: 0.5]) == .none)
}

@Test func lowConfidenceFingersAreNone() {
    // A hand that looks like `two`, but the extended fingers' joints are barely detected (e.g. cut off by the frame edge).
    var hand = SyntheticHand.make(.two)
    for joint in [JointName.indexPIP, .indexDIP, .indexTip, .middlePIP, .middleDIP, .middleTip] {
        hand[joint].confidence = 0.05
    }
    #expect(RuleBasedPoseClassifier().classify(HandFeatureExtractor.extract(hand)) == [.none: 1])
}
