import Testing
import HandTracking
import TestSupport
@testable import GestureEngine

private let open = PinchReading(index: false, middle: false, ratio: 0.6)
private func closed(_ ratio: Float = 0.15) -> PinchReading { PinchReading(index: true, middle: false, ratio: ratio) }
private func opening(_ ratio: Float) -> PinchReading { PinchReading(index: false, middle: false, ratio: ratio) }

/// Feeds frames at 30 fps from `start`; returns all events and the next timestamp.
private struct Feed {
    var r = TouchRecognizer(config: .default, gesture: .default)
    var t = 0.0
    var events: [GestureEvent] = []

    mutating func frame(_ anchor: SIMD2<Float>?, _ pinch: PinchReading?) {
        events += r.update(anchor: anchor, pinch: pinch, at: t)
        t += 1.0 / 30
    }

    mutating func frames(_ n: Int, _ anchor: SIMD2<Float>?, _ pinch: PinchReading?) {
        for _ in 0..<n { frame(anchor, pinch) }
    }

    var buttons: [GestureEvent] { events.filter { if case .button = $0 { return true }; return false } }
    var scrolls: [GestureEvent] { events.filter { if case .continuous(.scroll, _, _) = $0 { return true }; return false } }
}

@Test func hoverEmitsPointerTrack() {
    var f = Feed()
    f.frame([0.5, 0.5], open)
    #expect(f.events == [.pointerTrack(position: [0.5, 0.5], at: 0)])
}

@Test func tapClicksAtAnchor() {
    var f = Feed()
    f.frames(3, [0.5, 0.5], open)                                   // t 0 … 0.067
    let fallStart = f.t                                             // 0.1
    f.frame([0.5, 0.5], opening(0.6))
    f.frame([0.503, 0.5], opening(0.45))                            // closing fingers drag the anchor
    f.frame([0.506, 0.5], opening(0.3))
    f.frame([0.509, 0.5], closed())                                 // closes at 0.2
    f.frames(2, [0.509, 0.5], closed())
    f.frame([0.509, 0.5], open)                                     // released after 0.1 s
    guard case let .button(.left, .click(count: 1), anchorTime)? = f.buttons.first else {
        Issue.record("expected one left click, got \(f.buttons)")
        return
    }
    #expect(abs(anchorTime - fallStart) < 1e-6)
    #expect(f.buttons.count == 1)
}

@Test func pressFreezesPointer() {
    var f = Feed()
    f.frame([0.5, 0.5], open)
    f.frames(4, [0.505, 0.5], closed())
    let afterPress = f.events.dropFirst()
    #expect(!afterPress.contains { if case .pointerTrack = $0 { return true }; return false })
}

@Test func doubleTapCountsTwo() {
    var f = Feed()
    f.frame([0.5, 0.5], open)
    f.frames(2, [0.5, 0.5], closed()); f.frame([0.5, 0.5], open)
    f.frames(2, [0.5, 0.5], open)
    f.frames(2, [0.501, 0.5], closed()); f.frame([0.501, 0.5], open)
    let counts = f.buttons.compactMap { e -> Int? in if case .button(.left, .click(let c), _) = e { return c }; return nil }
    #expect(counts == [1, 2])
}

@Test func middleTapRightClicks() {
    var f = Feed()
    f.frame([0.5, 0.5], open)
    f.frames(2, [0.5, 0.5], PinchReading(index: false, middle: true, ratio: 0.5))
    f.frame([0.5, 0.5], open)
    guard case .button(.right, .click(count: 1), _)? = f.buttons.first else {
        Issue.record("expected a right click, got \(f.buttons)")
        return
    }
}

@Test func pinchMoveScrollsThenEnds() {
    var f = Feed()
    f.frame([0.5, 0.5], open)
    for i in 1...6 { f.frame([0.5, 0.5 + 0.01 * Float(i)], closed()) }
    f.frame([0.5, 0.56], open)
    guard case .continuous(.scroll, .began, _)? = f.scrolls.first else {
        Issue.record("expected a scroll, got \(f.events)")
        return
    }
    #expect(f.scrolls.last == .continuous(.scroll, phase: .ended, delta: .zero))
    #expect(f.buttons.isEmpty)
    let total = f.scrolls.reduce(Float(0)) { sum, e in
        if case .continuous(_, let p, let d) = e, p == .began || p == .changed { return sum + d.y }
        return sum
    }
    #expect(abs(total - 0.047) < 1e-4) // from where the pinch closed (0.51), minus the 0.003 scroll dead-band slack
}

@Test func holdThenMoveDrags() {
    var f = Feed()
    f.frame([0.5, 0.5], open)
    f.frames(14, [0.5, 0.5], closed())                            // ≥ 0.4 s still
    for i in 1...3 { f.frame([0.5 + 0.02 * Float(i), 0.5], closed()) }
    f.frame([0.56, 0.5], open)
    let kinds = f.buttons.compactMap { e -> ButtonAction? in if case .button(.left, let a, _) = e { return a }; return nil }
    #expect(kinds == [.down, .up])
    #expect(f.scrolls.isEmpty)
    let downIndex = f.events.firstIndex { if case .button(_, .down, _) = $0 { return true }; return false }!
    #expect(f.events[downIndex...].contains { if case .pointerTrack = $0 { return true }; return false })
}

@Test func handLostWhileDraggingReleasesButton() {
    var f = Feed()
    f.frame([0.5, 0.5], open)
    f.frames(14, [0.5, 0.5], closed())
    f.frames(9, nil, nil)                                         // 0.3 s gone
    let kinds = f.buttons.compactMap { e -> ButtonAction? in if case .button(.left, let a, _) = e { return a }; return nil }
    #expect(kinds == [.down, .up])
}

@Test func handLostWhileScrollingCancels() {
    var f = Feed()
    f.frame([0.5, 0.5], open)
    for i in 1...4 { f.frame([0.5, 0.5 + 0.01 * Float(i)], closed()) }
    f.frames(9, nil, nil)
    #expect(f.scrolls.last == .continuous(.scroll, phase: .cancelled, delta: .zero))
}

@Test func slowPinchHeldIsNotTap() {
    var f = Feed()
    f.frame([0.5, 0.5], open)
    f.frames(10, [0.5, 0.5], closed())                            // 0.33 s: too long to tap, too short to drag
    f.frame([0.5, 0.5], open)
    #expect(f.buttons.isEmpty)
}

@Test func lateDriftAfterHoldTimeIsNeverADeadPress() {
    // The frame that first exceeds the slop arrives after the hold time (e.g. a 15 fps frame gap).
    var r = TouchRecognizer(config: .default, gesture: .default)
    var events = r.update(anchor: [0.5, 0.5], pinch: open, at: 0)
    events += r.update(anchor: [0.5, 0.5], pinch: closed(), at: 0.033)
    events += r.update(anchor: [0.505, 0.5], pinch: closed(), at: 0.3)
    events += r.update(anchor: [0.53, 0.5], pinch: closed(), at: 0.5)   // past 0.4 s and past the slop at once
    events += r.update(anchor: [0.56, 0.5], pinch: closed(), at: 0.533)
    events += r.update(anchor: [0.56, 0.5], pinch: open, at: 0.566)
    let acted = events.contains { e in
        switch e {
        case .button(.left, .down, _), .continuous(.scroll, .began, _): return true
        default: return false
        }
    }
    #expect(acted)
    #expect(!r.isBusy)
}

@Test func singleDroppedFrameInHoverDoesNotLift() {
    var f = Feed()
    f.frame([0.5, 0.5], open)
    f.frame(nil, nil)                                          // one blurred frame
    f.frame([0.51, 0.5], open)
    #expect(!f.events.contains(.pointerLift))
}

@Test func heldScrollDoesNotJiggle() {
    var f = Feed()
    f.frame([0.5, 0.5], open)
    for i in 1...3 { f.frame([0.5, 0.5 + 0.01 * Float(i)], closed()) }   // scrolling
    for i in 0..<10 { f.frame([0.5, 0.53 + (i % 2 == 0 ? 0.003 : -0.003)], closed()) } // holding still, raw noise
    let afterHold = f.scrolls.suffix(10).filter { if case .continuous(_, .changed, _) = $0 { return true }; return false }
    #expect(afterHold.count <= 1)
}

@Test func unreadableMiddleTipReleasesRightPress() {
    var d = PinchDetector(config: .default)
    _ = d.update(SyntheticHand.make(.pinchMiddle, pinchOpenness: 0), at: 0)
    var blurred = SyntheticHand.make(.pinchMiddle, pinchOpenness: 0)
    blurred[.middleTip].confidence = 0.1
    #expect(d.update(blurred, at: 0.033)?.middle == false)
}

@Test func pinchWhileMovingFastDoesNotPress() {
    // Gesturing while talking: thumb meets index mid-motion.
    var r = TouchRecognizer(config: .default, gesture: .default)
    var events: [GestureEvent] = []
    for i in 0..<12 {
        let x = 0.4 + 0.03 * Float(i)                              // 0.9 frame heights/s
        let reading = (6...7).contains(i) ? closed() : open
        events += r.update(anchor: [x, 0.5], pinch: reading, at: Double(i) / 30)
    }
    #expect(!events.contains { if case .button = $0 { return true }; if case .continuous(.scroll, _, _) = $0 { return true }; return false })
}

@Test func pinchWithoutPresentedHandDoesNotPress() {
    var r = TouchRecognizer(config: .default, gesture: .default)
    var events = r.update(anchor: [0.5, 0.5], pinch: open, presented: false, at: 0)
    events += r.update(anchor: [0.5, 0.5], pinch: closed(), presented: false, at: 0.033)
    events += r.update(anchor: [0.5, 0.5], pinch: open, presented: false, at: 0.1)
    #expect(!events.contains { if case .button = $0 { return true }; return false })
}
