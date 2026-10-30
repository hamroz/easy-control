import Testing
import HandTracking
import TestSupport
@testable import Signal

@Test func stableIDsAcrossFrames() {
    let tracker = HandIdentityTracker()
    var ids = Set<HandID>()
    for i in 0..<30 {
        let hand = SyntheticHand.make(.openPalm, center: [0.3 + 0.01 * Float(i), 0.5])
        let tracked = tracker.update(HandFrame(timestamp: Double(i) / 30, hands: [hand]))
        #expect(tracked.count == 1)
        ids.formUnion(tracked.map(\.id))
    }
    #expect(ids.count == 1)
}

@Test func twoHandsKeepDistinctIDs() {
    let tracker = HandIdentityTracker()
    var idsByX: [Bool: Set<HandID>] = [:]
    for i in 0..<30 {
        let left = SyntheticHand.make(.openPalm, center: [0.3, 0.5], chirality: .left)
        let right = SyntheticHand.make(.two, center: [0.7, 0.5], chirality: .right)
        for t in tracker.update(HandFrame(timestamp: Double(i) / 30, hands: [left, right])) {
            idsByX[t.hand[.wrist].position.x > 0.5, default: []].insert(t.id)
        }
    }
    #expect(idsByX[true]?.count == 1)
    #expect(idsByX[false]?.count == 1)
    #expect(idsByX[true] != idsByX[false])
}

@Test func reappearingHandGetsNewID() {
    let tracker = HandIdentityTracker()
    let hand = SyntheticHand.make(.openPalm)
    let first = tracker.update(HandFrame(timestamp: 0, hands: [hand]))[0].id
    _ = tracker.update(HandFrame(timestamp: 0.5, hands: []))
    let second = tracker.update(HandFrame(timestamp: 1.2, hands: [hand]))[0].id
    #expect(first != second)
}

@Test func briefDropoutKeepsID() {
    let tracker = HandIdentityTracker()
    let first = tracker.update(HandFrame(timestamp: 0, hands: [SyntheticHand.make(.openPalm)]))[0].id
    for i in 1...9 { _ = tracker.update(HandFrame(timestamp: Double(i) / 30, hands: [])) }
    let back = tracker.update(HandFrame(timestamp: 0.33, hands: [SyntheticHand.make(.openPalm, center: [0.55, 0.5])]))[0].id
    #expect(back == first)
}

@Test func chiralityFlipKeepsID() {
    let tracker = HandIdentityTracker()
    let first = tracker.update(HandFrame(timestamp: 0, hands: [SyntheticHand.make(.openPalm, chirality: .right)]))[0].id
    var ids = Set<HandID>()
    for i in 1...3 {
        let hand = SyntheticHand.make(.openPalm, chirality: .left)
        ids.formUnion(tracker.update(HandFrame(timestamp: Double(i) / 30, hands: [hand])).map(\.id))
    }
    #expect(ids == [first])
}

@Test func smoothedHandKeepsMajorityChirality() {
    // Vision's left/right guess flickers for single frames; the hand handed to the classifier must not.
    let tracker = HandIdentityTracker()
    var seen: [Chirality] = []
    for i in 0..<20 {
        let flicker = i % 7 == 6
        let hand = SyntheticHand.make(.openPalm, chirality: flicker ? .left : .right)
        seen += tracker.update(HandFrame(timestamp: Double(i) / 30, hands: [hand])).map(\.hand.chirality)
    }
    #expect(seen.allSatisfy { $0 == .right })
}
