import Testing
import GestureEngine
@testable import Actions

private func dock(_ e: SyntheticEvent) -> (DockMotion, DockPhase, Double, Double)? {
    if case let .dockSwipe(m, p, progress, velocity) = e { return (m, p, progress, velocity) }
    return nil
}

private func injector(supported: Bool = true) -> (DockSwipeInjector, RecordingEventSink) {
    let sink = RecordingEventSink(supportsDockSwipe: supported)
    return (DockSwipeInjector(sink: sink, spaces: ControlArrowStrategy(sink: sink)), sink)
}

@Test func progressAccumulatesWithNaturalSign() {
    let (d, sink) = injector()
    d.handle(.dockSwipeHorizontal, phase: .began, delta: [0.05, 0], at: 0)
    d.handle(.dockSwipeHorizontal, phase: .changed, delta: [0.05, 0], at: 0.033)
    let events = sink.events.compactMap(dock)
    #expect(events.map(\.1) == [.began, .changed, .changed])
    #expect(events.allSatisfy { $0.0 == .horizontal })
    #expect(abs(events.last!.2 - 0.4) < 1e-6) // hand moved right 0.1 frame heights = 0.4 of a Space
}

@Test func verticalUpIsPositive() {
    let (d, sink) = injector()
    d.handle(.dockSwipeVertical, phase: .began, delta: [0, -0.05], at: 0)
    let last = sink.events.compactMap(dock).last!
    #expect(last.0 == .vertical && last.2 > 0)
}

@Test func endCarriesVelocity() {
    let (d, sink) = injector()
    d.handle(.dockSwipeHorizontal, phase: .began, delta: [0.05, 0], at: 0)
    d.handle(.dockSwipeHorizontal, phase: .changed, delta: [0.05, 0], at: 0.033)
    d.handle(.dockSwipeHorizontal, phase: .ended, delta: .zero, at: 0.066)
    let end = sink.events.compactMap(dock).last!
    #expect(end.1 == .ended && abs(end.2 - 0.4) < 1e-6 && abs(end.3 - 20) < 1e-6)
}

@Test func reversalBecomesCancelled() {
    let (d, sink) = injector()
    d.handle(.dockSwipeHorizontal, phase: .began, delta: [0.1, 0], at: 0)
    d.handle(.dockSwipeHorizontal, phase: .changed, delta: [-0.02, 0], at: 0.033)
    d.handle(.dockSwipeHorizontal, phase: .ended, delta: .zero, at: 0.066)
    #expect(sink.events.compactMap(dock).last!.1 == .cancelled)
}

@Test func endIsResent() {
    let (d, sink) = injector()
    d.handle(.dockSwipeHorizontal, phase: .began, delta: [0.1, 0], at: 0)
    d.handle(.dockSwipeHorizontal, phase: .ended, delta: .zero, at: 1)
    #expect(d.needsTicks)
    let ends = { sink.events.compactMap(dock).filter { $0.1 == .ended }.count }
    #expect(ends() == 1)
    d.tick(at: 1.25)
    #expect(ends() == 2)
    d.tick(at: 1.6)
    #expect(ends() == 3)
    d.tick(at: 2)
    #expect(ends() == 3 && !d.needsTicks)
}

@Test func fallbackSwitchesSpaceWhenUnsupported() {
    let (d, sink) = injector(supported: false)
    d.handle(.dockSwipeHorizontal, phase: .began, delta: [0.08, 0], at: 0)
    d.handle(.dockSwipeHorizontal, phase: .changed, delta: [0.08, 0], at: 0.033)
    d.handle(.dockSwipeHorizontal, phase: .ended, delta: .zero, at: 0.066)
    #expect(sink.events.compactMap(dock).isEmpty)
    // Hand moved right ⇒ natural direction ⇒ the Space on the left.
    #expect(sink.events == [.key(code: KeyCode.leftArrow, flags: KeyFlags.controlArrow, down: true),
                            .key(code: KeyCode.leftArrow, flags: KeyFlags.controlArrow, down: false)])
}

@Test func smallFallbackDragDoesNothing() {
    let (d, sink) = injector(supported: false)
    d.handle(.dockSwipeVertical, phase: .began, delta: [0, -0.04], at: 0)
    d.handle(.dockSwipeVertical, phase: .ended, delta: .zero, at: 0.1)
    #expect(sink.events.isEmpty)
}

@Test func pauseCancelsOpenDockSwipe() {
    let sink = RecordingEventSink(supportsDockSwipe: true)
    let dispatcher = ActionDispatcher(sink: sink, spaces: ControlArrowStrategy(sink: sink), scroll: ScrollInjector(sink: sink))
    dispatcher.handle([.continuous(.dockSwipeHorizontal, phase: .began, delta: [0.05, 0])], at: 0)
    dispatcher.cancelMomentum()
    #expect(sink.events.compactMap(dock).last?.1 == .cancelled)
}
