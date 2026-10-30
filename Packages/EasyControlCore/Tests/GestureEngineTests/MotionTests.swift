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

/// Holds the last position of `samples` still for `seconds` (a stroke that ends with the hand stopping).
private func thenHold(_ samples: [Sample], for seconds: Double = 0.15) -> [Sample] {
    guard let last = samples.last else { return samples }
    let n = Int((seconds * 30).rounded())
    return samples + (1...n).map { (last.t + Double($0) / 30, last.pose, last.center) }
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
    for i in 0..<4 { // a different pose must persist a few frames to end the scroll
        if let e = r.update(pose: .openPalm, palmCenter: [0.5, 0.6], at: 0.6 + Double(i) / 30) { events.append(e) }
    }

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
    #expect(r.update(pose: .none, palmCenter: nil, at: 0.033) == nil) // a dropped frame is tolerated…
    #expect(r.update(pose: .none, palmCenter: nil, at: 0.3) == .continuous(.scroll, phase: .cancelled, delta: .zero)) // …a lost hand isn't
}

@Test func scrollRidesThroughBriefPoseFlicker() {
    var r = ScrollRecognizer(config: .default)
    var events: [GestureEvent] = []
    let poses: [PoseClass] = [.two, .two, .three, .three, .two, .two] // shorter than continuousReleaseFrames
    for (i, pose) in poses.enumerated() {
        if let e = r.update(pose: pose, palmCenter: [0.5, 0.5 + 0.01 * Float(i)], at: Double(i) / 30) { events.append(e) }
    }
    #expect(!events.contains { if case .continuous(_, .ended, _) = $0 { return true }; return false })
    #expect(events.filter { if case .continuous(_, .began, _) = $0 { return true }; return false }.count == 1)
}

@Test func fastLeftSwipeFires() {
    let events = runSwipe(thenHold(linear(.openPalm, from: [0.7, 0.5], to: [0.45, 0.5], over: 0.2, start: 0)))
    #expect(events == [.discrete(.swipeLeft)])
}

@Test func slowDriftDoesNotSwipe() {
    #expect(runSwipe(linear(.openPalm, from: [0.7, 0.5], to: [0.45, 0.5], over: 2, start: 0)).isEmpty)
}

@Test func diagonalDoesNotSwipe() {
    #expect(runSwipe(linear(.openPalm, from: [0.7, 0.3], to: [0.5, 0.5], over: 0.2, start: 0)).isEmpty)
}

@Test func upSwipeIsMissionControlDirection() {
    #expect(runSwipe(thenHold(linear(.openPalm, from: [0.5, 0.7], to: [0.5, 0.45], over: 0.2, start: 0))) == [.discrete(.swipeUp)])
}

@Test func cooldownPreventsDoubleFire() {
    let first = thenHold(linear(.openPalm, from: [0.7, 0.5], to: [0.45, 0.5], over: 0.2, start: 0), for: 0.1)
    let second = thenHold(linear(.openPalm, from: [0.45, 0.5], to: [0.2, 0.5], over: 0.2, start: first.last!.t + 1.0 / 30))
    #expect(runSwipe(first + second) == [.discrete(.swipeLeft)])
}

@Test func gapDoesNotCreatePhantomSwipe() {
    var samples: [Sample] = (0..<10).map { (Double($0) / 30, .openPalm, [0.7, 0.5]) }
    samples.append((9.0 / 30 + 0.5, .openPalm, [0.3, 0.5]))
    samples.append((9.0 / 30 + 0.5 + 1.0 / 30, .openPalm, [0.3, 0.5]))
    #expect(runSwipe(samples).isEmpty)
}

@Test func handDropDoesNotSwipe() {
    // Engaged user lowers the open hand out of the frame.
    var samples = linear(.openPalm, from: [0.5, 0.5], to: [0.5, 0.97], over: 0.25, start: 0)
    samples.append((samples.last!.t + 1.0 / 30, .none, nil))
    #expect(runSwipe(samples).isEmpty)
}

@Test func strokeEndingAtFrameEdgeDoesNotSwipe() {
    #expect(runSwipe(thenHold(linear(.openPalm, from: [0.5, 0.55], to: [0.5, 0.95], over: 0.25, start: 0))).isEmpty)
}

@Test func strokeThatNeverStopsDoesNotSwipe() {
    // Hand keeps moving (e.g. gesturing while talking) and the pose ends without the stroke settling.
    var samples = linear(.openPalm, from: [0.8, 0.5], to: [0.2, 0.5], over: 0.5, start: 0)
    samples.append((samples.last!.t + 1.0 / 30, .fist, [0.18, 0.5]))
    #expect(runSwipe(samples).isEmpty)
}

@Test func returnStrokeIsLockedOut() {
    let swipe = thenHold(linear(.openPalm, from: [0.7, 0.5], to: [0.45, 0.5], over: 0.2, start: 0), for: 0.5)
    let back = thenHold(linear(.openPalm, from: [0.45, 0.5], to: [0.7, 0.5], over: 0.2, start: swipe.last!.t + 1.0 / 30))
    #expect(runSwipe(swipe + back) == [.discrete(.swipeLeft)])
}

@Test func wideFrameHorizontalSwipeFires() {
    // 16:9 camera: 0.14 of the frame width is 0.25 frame heights of real hand travel.
    var r = SwipeRecognizer(config: .default)
    let samples = thenHold(linear(.openPalm, from: [0.6, 0.5], to: [0.46, 0.5], over: 0.2, start: 0))
    let events = samples.compactMap { r.update(pose: $0.pose, palmCenter: $0.center, aspect: 16.0 / 9.0, at: $0.t) }
    #expect(events == [.discrete(.swipeLeft)])
}

@Test func wideFrameEdgeStillNormalized() {
    var r = SwipeRecognizer(config: .default)
    let samples = thenHold(linear(.openPalm, from: [0.8, 0.5], to: [0.95, 0.5], over: 0.15, start: 0))
    #expect(samples.compactMap { r.update(pose: $0.pose, palmCenter: $0.center, aspect: 16.0 / 9.0, at: $0.t) }.isEmpty)
}

@Test func scrollDeltaIsIsotropic() {
    var r = ScrollRecognizer(config: .default)
    _ = r.update(pose: .two, palmCenter: [0.5, 0.5], aspect: 2, at: 0)
    guard case .continuous(.scroll, .changed, let d)? = r.update(pose: .two, palmCenter: [0.51, 0.5], aspect: 2, at: 1.0 / 30) else {
        Issue.record("expected a scroll change")
        return
    }
    #expect(abs(d.x - 0.02) < 1e-5 && d.y == 0)
}
