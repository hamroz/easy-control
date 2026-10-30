import Testing
import HandTracking
import TestSupport
@testable import GestureEngine

private func drag(_ r: inout DockSwipeRecognizer, from a: SIMD2<Float>, to b: SIMD2<Float>, over seconds: Double,
                  start: Double = 0, pose: PoseClass = .three) -> [GestureEvent] {
    let n = Int((seconds * 30).rounded())
    return (0...n).compactMap { i in
        r.update(pose: pose, palmCenter: a + (b - a) * (Float(i) / Float(n)), aspect: 1, at: start + Double(i) / 30)
    }
}

private func total(_ events: [GestureEvent]) -> SIMD2<Float> {
    events.reduce(.zero) { sum, e in
        if case .continuous(_, let phase, let d) = e, phase == .began || phase == .changed { return sum + d }
        return sum
    }
}

@Test func horizontalDragEmitsAxisLockedDeltas() {
    var r = DockSwipeRecognizer(config: .default)
    var events = drag(&r, from: [0.5, 0.5], to: [0.7, 0.52], over: 0.3)
    for i in 0..<4 {
        if let e = r.update(pose: .openPalm, palmCenter: [0.7, 0.52], aspect: 1, at: 0.4 + Double(i) / 30) { events.append(e) }
    }
    guard case .continuous(.dockSwipeHorizontal, .began, _)? = events.first else {
        Issue.record("expected a horizontal began, got \(events.first.map { "\($0)" } ?? "nothing")")
        return
    }
    #expect(events.last == .continuous(.dockSwipeHorizontal, phase: .ended, delta: .zero))
    let sum = total(events)
    #expect(abs(sum.x - 0.2) < 0.01 && sum.y == 0)
}

@Test func verticalDrag() {
    var r = DockSwipeRecognizer(config: .default)
    let events = drag(&r, from: [0.5, 0.6], to: [0.5, 0.4], over: 0.3)
    guard case .continuous(.dockSwipeVertical, .began, _)? = events.first else {
        Issue.record("expected a vertical began")
        return
    }
    let sum = total(events)
    #expect(abs(sum.y + 0.2) < 0.01 && sum.x == 0)
}

@Test func jitterBelowLockEmitsNothing() {
    var r = DockSwipeRecognizer(config: .default)
    var events: [GestureEvent] = []
    for i in 0..<30 {
        let j: Float = i % 2 == 0 ? 0.01 : -0.01
        if let e = r.update(pose: .three, palmCenter: [0.5 + j, 0.5], aspect: 1, at: Double(i) / 30) { events.append(e) }
    }
    #expect(events.isEmpty)
}

@Test func handLostCancelsDockSwipe() {
    var r = DockSwipeRecognizer(config: .default)
    _ = drag(&r, from: [0.5, 0.5], to: [0.6, 0.5], over: 0.2)
    #expect(r.update(pose: .none, palmCenter: nil, aspect: 1, at: 0.25) == nil)
    #expect(r.update(pose: .none, palmCenter: nil, aspect: 1, at: 0.5) == .continuous(.dockSwipeHorizontal, phase: .cancelled, delta: .zero))
}

@Test func singleDroppedFrameKeepsDrag() {
    var r = DockSwipeRecognizer(config: .default)
    var events = drag(&r, from: [0.5, 0.5], to: [0.6, 0.5], over: 0.2)
    if let e = r.update(pose: .none, palmCenter: nil, aspect: 1, at: 0.233) { events.append(e) } // blurred frame
    events += drag(&r, from: [0.62, 0.5], to: [0.7, 0.5], over: 0.1, start: 0.266)
    #expect(events.filter { if case .continuous(_, .began, _) = $0 { return true }; return false }.count == 1)
    #expect(!events.contains { if case .continuous(_, let p, _) = $0 { return p == .ended || p == .cancelled }; return false })
    #expect(abs(total(events).x - 0.2) < 0.01) // movement during the gap is not lost
}

@Test func otherPosesDoNotDrag() {
    var r = DockSwipeRecognizer(config: .default)
    #expect(drag(&r, from: [0.5, 0.5], to: [0.8, 0.5], over: 0.3, pose: .two).isEmpty)
}

@Test func threeFingerDragAfterEngage() {
    var s = FrameScript()
    s.hold(.openPalm, at: [0.5, 0.5], for: 0.6)
    s.hold(.three, at: [0.5, 0.5], for: 0.2)
    s.move(.three, from: [0.5, 0.5], to: [0.7, 0.5], over: 0.3)
    s.hold(.openPalm, at: [0.7, 0.5], for: 0.2)
    let engine = GestureEngine()
    let events = s.frames.flatMap { engine.process($0, lastUserInput: nil) }
    #expect(events.contains { if case .continuous(.dockSwipeHorizontal, .began, _) = $0 { return true }; return false })
    #expect(events.contains(.continuous(.dockSwipeHorizontal, phase: .ended, delta: .zero)))
    #expect(!events.contains { if case .discrete = $0 { return true }; return false })
}

@Test func typingCancelsDockSwipe() {
    var s = FrameScript()
    s.hold(.openPalm, at: [0.5, 0.5], for: 0.6)
    s.hold(.three, at: [0.5, 0.5], for: 0.2)
    s.move(.three, from: [0.5, 0.5], to: [0.6, 0.5], over: 0.2)
    let typedAt = s.now
    s.move(.three, from: [0.6, 0.5], to: [0.7, 0.5], over: 0.2)
    let engine = GestureEngine()
    let events = s.frames.flatMap { engine.process($0, lastUserInput: $0.timestamp >= typedAt ? typedAt : nil) }
    let dock = events.filter { if case .continuous(.dockSwipeHorizontal, _, _) = $0 { return true }; return false }
    #expect(dock.last == .continuous(.dockSwipeHorizontal, phase: .cancelled, delta: .zero))
}

@Test func flickerToTwoMidScrollDoesNotStartDockSwipe() {
    var s = FrameScript()
    s.hold(.openPalm, at: [0.5, 0.4], for: 0.6)
    s.hold(.two, at: [0.5, 0.4], for: 0.2)
    s.move(.two, from: [0.5, 0.4], to: [0.5, 0.5], over: 0.2)
    s.move(.three, from: [0.5, 0.5], to: [0.5, 0.55], over: 0.17) // brief misread mid-scroll (~2–3 stable frames)
    s.move(.two, from: [0.5, 0.55], to: [0.5, 0.65], over: 0.2)
    let engine = GestureEngine()
    let events = s.frames.flatMap { engine.process($0, lastUserInput: nil) }
    #expect(!events.contains { if case .continuous(.dockSwipeVertical, _, _) = $0 { return true }; return false })
    #expect(!events.contains { if case .continuous(.dockSwipeHorizontal, _, _) = $0 { return true }; return false })
    #expect(events.filter { $0 == .continuous(.scroll, phase: .began, delta: .zero) }.count == 1)
}

@Test func releasingDockSwipeIntoPalmDoesNotSwipe() {
    var s = FrameScript()
    s.hold(.openPalm, at: [0.4, 0.5], for: 0.6)
    s.hold(.three, at: [0.4, 0.5], for: 0.2)
    s.move(.three, from: [0.3, 0.5], to: [0.45, 0.5], over: 0.15)
    s.move(.openPalm, from: [0.45, 0.5], to: [0.85, 0.5], over: 0.3) // still flicking as the pose changes
    s.hold(.openPalm, at: [0.85, 0.5], for: 0.3)
    let engine = GestureEngine()
    let events = s.frames.flatMap { engine.process($0, lastUserInput: nil) }
    #expect(!events.contains { if case .discrete = $0 { return true }; return false })
}
