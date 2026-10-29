import Testing
@testable import GestureEngine

/// A motion sample: time, pose, palm centre (nil = hand lost).
private typealias Sample = (t: Double, pose: PoseClass, center: SIMD2<Float>?)

private func linear(_ pose: PoseClass, from a: SIMD2<Float>, to b: SIMD2<Float>, over seconds: Double, start: Double) -> [Sample] {
    let n = Int((seconds * 30).rounded())
    return (0...n).map { i in
        let f = Float(i) / Float(n)
        return (start + Double(i) / 30, pose, a + (b - a) * f)
    }
}

private func runSwipe(_ samples: [Sample]) -> [GestureEvent] {
    var r = SwipeRecognizer(config: .default)
    return samples.compactMap { r.update(pose: $0.pose, palmCenter: $0.center, at: $0.t) }
}

@Test func scrollLifecycle() {
    var r = ScrollRecognizer(config: .default)
    var events: [GestureEvent] = []
    for s in linear(.two, from: [0.5, 0.4], to: [0.5, 0.6], over: 0.5, start: 0) {
        if let e = r.update(pose: s.pose, palmCenter: s.center, at: s.t) { events.append(e) }
    }
    if let e = r.update(pose: .openPalm, palmCenter: [0.5, 0.6], at: 0.6) { events.append(e) }

    #expect(events.first == .continuous(.scroll, phase: .began, delta: .zero))
    #expect(events.last == .continuous(.scroll, phase: .ended, delta: .zero))
    var total = SIMD2<Float>.zero
    for case let .continuous(_, .changed, d) in events { total += d }
    #expect(abs(total.x) < 0.01 && abs(total.y - 0.2) < 0.01)
}

@Test func scrollDeadZoneSuppressesJitter() {
    var r = ScrollRecognizer(config: .default)
    var events: [GestureEvent] = []
    for i in 0..<30 {
        let jitter: Float = i % 2 == 0 ? 0.001 : -0.001
        if let e = r.update(pose: .two, palmCenter: [0.5, 0.5 + jitter], at: Double(i) / 30) { events.append(e) }
    }
    #expect(events == [.continuous(.scroll, phase: .began, delta: .zero)])
}

@Test func scrollEndsWhenHandLost() {
    var r = ScrollRecognizer(config: .default)
    _ = r.update(pose: .two, palmCenter: [0.5, 0.5], at: 0)
    #expect(r.update(pose: .none, palmCenter: nil, at: 0.033) == .continuous(.scroll, phase: .ended, delta: .zero))
}

@Test func fastLeftSwipeFires() {
    let events = runSwipe(linear(.openPalm, from: [0.7, 0.5], to: [0.45, 0.5], over: 0.2, start: 0))
    #expect(events == [.discrete(.swipeLeft)])
}

@Test func slowDriftDoesNotSwipe() {
    #expect(runSwipe(linear(.openPalm, from: [0.7, 0.5], to: [0.45, 0.5], over: 2, start: 0)).isEmpty)
}

@Test func diagonalDoesNotSwipe() {
    #expect(runSwipe(linear(.openPalm, from: [0.7, 0.3], to: [0.5, 0.5], over: 0.2, start: 0)).isEmpty)
}

@Test func upSwipeIsMissionControlDirection() {
    #expect(runSwipe(linear(.openPalm, from: [0.5, 0.7], to: [0.5, 0.45], over: 0.2, start: 0)) == [.discrete(.swipeUp)])
}

@Test func cooldownPreventsDoubleFire() {
    let first = linear(.openPalm, from: [0.7, 0.5], to: [0.45, 0.5], over: 0.2, start: 0)
    let second = linear(.openPalm, from: [0.45, 0.5], to: [0.2, 0.5], over: 0.2, start: 0.2 + 1.0 / 30)
    #expect(runSwipe(first + second) == [.discrete(.swipeLeft)])
}

@Test func gapDoesNotCreatePhantomSwipe() {
    var samples: [Sample] = (0..<10).map { (Double($0) / 30, .openPalm, [0.7, 0.5]) }
    samples.append((9.0 / 30 + 0.5, .openPalm, [0.3, 0.5]))
    samples.append((9.0 / 30 + 0.5 + 1.0 / 30, .openPalm, [0.3, 0.5]))
    #expect(runSwipe(samples).isEmpty)
}
