import Testing
@testable import Actions

private func dy(_ e: SyntheticEvent) -> Int32 {
    if case .scroll(_, let dy, _, _) = e { return dy }
    return 0
}

private func momentum(_ e: SyntheticEvent) -> MomentumPhase? {
    if case .scroll(_, _, _, let m) = e { return m }
    return nil
}

@Test func phasesMapToScrollEvents() {
    let sink = RecordingEventSink()
    let natural = ScrollInjector(sink: sink)
    natural.handle(phase: .began, delta: .zero, at: 0)
    natural.handle(phase: .changed, delta: [0, 0.01], at: 1.0 / 30)
    natural.handle(phase: .ended, delta: .zero, at: 2.0 / 30)
    #expect(sink.events == [
        .scroll(dx: 0, dy: 0, phase: .began, momentum: .none),
        .scroll(dx: 0, dy: 18, phase: .changed, momentum: .none),
        .scroll(dx: 0, dy: 0, phase: .ended, momentum: .none),
    ])

    let sink2 = RecordingEventSink()
    let classic = ScrollInjector(sink: sink2, natural: false)
    classic.handle(phase: .began, delta: .zero, at: 0)
    classic.handle(phase: .changed, delta: [0, 0.01], at: 1.0 / 30)
    #expect(sink2.events.last == .scroll(dx: 0, dy: -18, phase: .changed, momentum: .none))
}

@Test func fastReleaseStartsMomentumThatDecays() {
    let sink = RecordingEventSink()
    let s = ScrollInjector(sink: sink)
    s.handle(phase: .began, delta: .zero, at: 0)
    for i in 1...10 { s.handle(phase: .changed, delta: [0, 0.02], at: Double(i) / 60) }
    s.handle(phase: .ended, delta: .zero, at: 11.0 / 60)
    let before = sink.events.count
    var ticks = 0
    while s.isMomentumActive && ticks < 200 {
        ticks += 1
        s.tick(at: 11.0 / 60 + Double(ticks) / 60)
    }
    let m = Array(sink.events[before...])
    #expect(ticks <= 120)
    #expect(momentum(m.first!) == .began)
    #expect(momentum(m.last!) == .ended)
    let mags = m.dropLast().map { abs(dy($0)) }
    #expect(mags.first! > 0)
    #expect(zip(mags, mags.dropFirst()).allSatisfy { $0 >= $1 })
}

@Test func slowReleaseHasNoMomentum() {
    let sink = RecordingEventSink()
    let s = ScrollInjector(sink: sink)
    s.handle(phase: .began, delta: .zero, at: 0)
    for i in 1...5 { s.handle(phase: .changed, delta: [0, 0.01], at: Double(i) / 30) }
    // Hand stops for 0.3 s before the pose is released.
    s.handle(phase: .ended, delta: .zero, at: 5.0 / 30 + 0.3)
    s.tick(at: 1)
    #expect(!s.isMomentumActive)
    #expect(!sink.events.contains { momentum($0) != MomentumPhase.none })
}

@Test func newScrollCancelsMomentum() {
    let sink = RecordingEventSink()
    let s = ScrollInjector(sink: sink)
    s.handle(phase: .began, delta: .zero, at: 0)
    for i in 1...10 { s.handle(phase: .changed, delta: [0, 0.02], at: Double(i) / 60) }
    s.handle(phase: .ended, delta: .zero, at: 11.0 / 60)
    s.tick(at: 12.0 / 60)
    s.tick(at: 13.0 / 60)
    s.handle(phase: .began, delta: .zero, at: 14.0 / 60)
    let tail = Array(sink.events.suffix(2))
    #expect(momentum(tail[0]) == .ended)
    #expect(tail[1] == .scroll(dx: 0, dy: 0, phase: .began, momentum: .none))
    #expect(!s.isMomentumActive)
}
