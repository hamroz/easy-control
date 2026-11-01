import CoreGraphics
import Testing
import GestureEngine
@testable import Actions

final class FakeEnvironment: PointerEnvironment, @unchecked Sendable {
    var cursor = CGPoint(x: 500, y: 500)
    func cursorLocation() -> CGPoint { cursor }
    func displayFrames() -> [CGRect] { [CGRect(x: 0, y: 0, width: 1728, height: 1117)] }
    func screenHeight() -> Double { 1117 }
}

private func makeLoop() -> (OutputLoop, RecordingEventSink) {
    let sink = RecordingEventSink(supportsDockSwipe: true)
    return (OutputLoop(sink: sink, environment: FakeEnvironment(), spaces: ControlArrowStrategy(sink: sink)), sink)
}

private func positions(_ events: [SyntheticEvent], _ kind: MouseKind = .moved) -> [CGPoint] {
    events.compactMap { if case let .mouse(k, x, y, _) = $0, k == kind { return CGPoint(x: x, y: y) }; return nil }
}

/// Camera samples at 30 Hz, display steps at 120 Hz in between.
private func drive(_ loop: OutputLoop, samples: [SIMD2<Float>], start: Double = 10) -> Int {
    var steps = 0
    for (i, p) in samples.enumerated() {
        let t = start + Double(i) / 30
        loop.receive([.pointerTrack(position: p, at: t)], at: t)
        for k in 0..<4 {
            loop.step(at: t + Double(k) / 120 + 0.001)
            steps += 1
        }
    }
    return steps
}

@Test func pointerMovesEveryFrameBetweenCameraSamples() {
    let (loop, sink) = makeLoop()
    let samples = (0..<16).map { SIMD2<Float>(0.4 + 0.01 * Float($0), 0.5) } // 0.3 frame heights/s
    let steps = drive(loop, samples: samples)
    let moves = positions(sink.events)
    #expect(Double(moves.count) >= Double(steps) * 0.8)
    let deltas = zip(moves, moves.dropFirst()).map { $1.x - $0.x }
    let median = deltas.sorted()[deltas.count / 2]
    #expect(deltas.allSatisfy { $0 >= 0 })                 // never jumps back
    #expect(deltas.dropFirst(8).allSatisfy { $0 <= median * 3 }) // no camera-frame-sized steps
    let total = moves.last!.x - 500
    #expect(total > 60 && total < 180)                      // ≈ 0.15 frame heights × gain 0.87 × 1117 px
}

@Test func stillHandWithTremorDoesNotCreep() {
    let (loop, sink) = makeLoop()
    let samples = (0..<30).map { SIMD2<Float>(0.5 + ($0 % 2 == 0 ? 0.002 : -0.002), 0.5) }
    _ = drive(loop, samples: samples)
    let last = positions(sink.events).last ?? CGPoint(x: 500, y: 500)
    #expect(abs(last.x - 500) < 2 && abs(last.y - 500) < 2)
}

@Test func clickLandsAtAnchorPosition() {
    let (loop, sink) = makeLoop()
    let samples = (0..<12).map { SIMD2<Float>(0.4 + 0.01 * Float($0), 0.5) }
    _ = drive(loop, samples: samples)
    let anchorTime = 10 + 6.0 / 30 + 0.001                     // a step time while the hand was moving
    let expected = loop.position(at: anchorTime)!
    loop.receive([.pointerLift, .button(.left, .click(count: 1), anchorTime: anchorTime)], at: 10.5)
    let downs = positions(sink.events, .leftDown), ups = positions(sink.events, .leftUp)
    #expect(downs == [expected] && ups == [expected])
    #expect(expected.x < positions(sink.events).dropLast().last!.x) // the pointer had moved on; the click went back
}

@Test func dragPostsDraggedBetweenDownAndUp() {
    let (loop, sink) = makeLoop()
    _ = drive(loop, samples: [[0.5, 0.5], [0.5, 0.5]])
    loop.receive([.button(.left, .down, anchorTime: 10.03)], at: 10.1)
    _ = drive(loop, samples: (0..<6).map { SIMD2<Float>(0.5 + 0.02 * Float($0), 0.5) }, start: 10.1)
    loop.receive([.button(.left, .up, anchorTime: 10.4)], at: 10.4)
    let kinds = sink.events.compactMap { e -> MouseKind? in if case let .mouse(k, _, _, _) = e { return k }; return nil }
    let down = kinds.firstIndex(of: .leftDown)!, up = kinds.firstIndex(of: .leftUp)!
    #expect(down < up)
    #expect(kinds[down..<up].contains(.leftDragged) && !kinds[down..<up].contains(.moved))
}

@Test func scrollIsSpreadAcrossFrames() {
    let (loop, sink) = makeLoop()
    loop.receive([.continuous(.scroll, phase: .began, delta: .zero), .continuous(.scroll, phase: .changed, delta: [0, 0.01])], at: 10)
    for k in 0..<12 { loop.step(at: 10 + Double(k) / 120) }
    let dys = sink.events.compactMap { e -> Int32? in
        if case let .scroll(_, dy, phase, _) = e, phase == .changed { return dy }
        return nil
    }
    #expect(dys.count >= 4)
    #expect(dys.allSatisfy { $0 < 18 })
    #expect(abs(Int(dys.reduce(0, +)) - 18) <= 2)
}

@Test func dockDeltasSpreadAcrossFrames() {
    let (loop, sink) = makeLoop()
    loop.receive([.continuous(.dockSwipeHorizontal, phase: .began, delta: [0.05, 0])], at: 10)
    for k in 0..<12 { loop.step(at: 10 + Double(k) / 120) }
    let progress = sink.events.compactMap { e -> Double? in
        if case let .dockSwipe(_, phase, p, _) = e, phase == .changed { return p }
        return nil
    }
    #expect(progress.count >= 4)
    #expect(zip(progress, progress.dropFirst()).allSatisfy { $0 < $1 })
    #expect(abs(progress.last! - 0.2) < 0.02)
}

@Test func cancelAllReleasesHeldButton() {
    let (loop, sink) = makeLoop()
    loop.receive([.button(.left, .down, anchorTime: 10)], at: 10)
    loop.cancelAll(at: 10.1)
    #expect(positions(sink.events, .leftUp).count == 1)
}

@Test func needsFramesFalseWhenIdle() {
    let (loop, _) = makeLoop()
    #expect(!loop.needsFrames)
    loop.receive([.pointerTrack(position: [0.5, 0.5], at: 10)], at: 10)
    #expect(loop.needsFrames)
    loop.receive([.pointerLift], at: 10.1)
    loop.step(at: 10.2)
    #expect(!loop.needsFrames)
}
