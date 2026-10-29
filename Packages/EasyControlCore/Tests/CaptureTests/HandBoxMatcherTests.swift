import CoreGraphics
import Testing
import HandTracking
import TestSupport
@testable import Capture

// Boxes are in unmirrored image coordinates; hands in our mirrored convention (x' = 1 − x).
private let left = SyntheticHand.make(.openPalm, center: [0.3, 0.5])   // image x ≈ 0.7
private let right = SyntheticHand.make(.two, center: [0.7, 0.5])      // image x ≈ 0.3

@Test func matcherPicksHandInsideBox() {
    let box = LabeledBox(label: "two", rect: CGRect(x: 0.15, y: 0.3, width: 0.3, height: 0.4))
    let matches = HandBoxMatcher.match(hands: [left, right], boxes: [box])
    #expect(matches.count == 1)
    #expect(matches.first?.box == 0 && matches.first?.hand == 1)
}

@Test func matcherIgnoresHandOutsideAllBoxes() {
    let box = LabeledBox(label: "two", rect: CGRect(x: 0.0, y: 0.0, width: 0.1, height: 0.1))
    #expect(HandBoxMatcher.match(hands: [left, right], boxes: [box]).isEmpty)
}

@Test func matcherUsesEachHandOnce() {
    // Two overlapping boxes both containing the same single hand: only one match.
    let a = LabeledBox(label: "two", rect: CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.6))
    let b = LabeledBox(label: "none", rect: CGRect(x: 0.22, y: 0.36, width: 0.16, height: 0.32)) // centre (0.30, 0.52)
    let matches = HandBoxMatcher.match(hands: [right], boxes: [a, b])
    #expect(matches.count == 1)
    #expect(matches.first?.box == 1) // nearest box centre wins
}
