import Testing
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
    #expect(abs(total - 0.05) < 1e-4) // from where the pinch closed (0.51): earlier motion already moved the pointer
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
