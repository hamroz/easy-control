import CoreGraphics
import HandTracking

/// A labelled hand box from a dataset annotation: normalized image coordinates, top-left origin, unmirrored.
public struct LabeledBox: Sendable {
    public var label: String
    public var rect: CGRect

    public init(label: String, rect: CGRect) {
        self.label = label
        self.rect = rect
    }
}

/// Pairs detected hands with annotated boxes, so each box's label goes to the right hand.
public enum HandBoxMatcher {
    /// A hand matches a box containing its palm centre; when several fit, the nearest box centre wins.
    /// Each hand and each box is used at most once.
    public static func match(hands: [Hand], boxes: [LabeledBox]) -> [(box: Int, hand: Int)] {
        var candidates: [(dist: CGFloat, box: Int, hand: Int)] = []
        for (h, hand) in hands.enumerated() {
            let c = hand.palmCenter
            let point = CGPoint(x: CGFloat(1 - c.x), y: CGFloat(c.y)) // undo the mirroring
            for (b, box) in boxes.enumerated() where box.rect.contains(point) {
                candidates.append((hypot(point.x - box.rect.midX, point.y - box.rect.midY), b, h))
            }
        }
        var usedBoxes = Set<Int>(), usedHands = Set<Int>()
        var result: [(box: Int, hand: Int)] = []
        for c in candidates.sorted(by: { $0.dist < $1.dist })
        where !usedBoxes.contains(c.box) && !usedHands.contains(c.hand) {
            usedBoxes.insert(c.box)
            usedHands.insert(c.hand)
            result.append((c.box, c.hand))
        }
        return result.sorted { $0.box < $1.box }
    }
}
