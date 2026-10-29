import Foundation
import Testing
import GestureEngine
@testable import Actions

private let arrowFlags = KeyFlags.control | KeyFlags.secondaryFn | KeyFlags.numericPad

private func makeDispatcher(_ bindings: Bindings = .defaults) -> (ActionDispatcher, RecordingEventSink) {
    let sink = RecordingEventSink()
    let dispatcher = ActionDispatcher(sink: sink, bindings: bindings,
                                      spaces: ControlArrowStrategy(sink: sink), scroll: ScrollInjector(sink: sink))
    return (dispatcher, sink)
}

@Test func swipeRightPostsCtrlRightWithConfiguredFlags() {
    let (d, sink) = makeDispatcher()
    d.handle([.discrete(.swipeRight)], at: 0)
    #expect(sink.events == [.key(code: 124, flags: arrowFlags, down: true), .key(code: 124, flags: arrowFlags, down: false)])
}

@Test func swipeUpPostsMissionControl() {
    let (d, sink) = makeDispatcher()
    d.handle([.discrete(.swipeUp)], at: 0)
    #expect(sink.events == [.key(code: 126, flags: arrowFlags, down: true), .key(code: 126, flags: arrowFlags, down: false)])
}

@Test func scrollEventsRouteToInjector() {
    let (d, sink) = makeDispatcher()
    d.handle([
        .continuous(.scroll, phase: .began, delta: .zero),
        .continuous(.scroll, phase: .changed, delta: [0, 0.01]),
        .continuous(.scroll, phase: .ended, delta: .zero),
    ], at: 0)
    #expect(sink.events.count == 3)
    #expect(sink.events.allSatisfy { if case .scroll = $0 { return true }; return false })
}

@Test func unboundGestureDoesNothing() {
    var bindings = Bindings.defaults
    bindings[.swipeLeft] = Action.none
    let (d, sink) = makeDispatcher(bindings)
    d.handle([.discrete(.swipeLeft), .engagement(.idle)], at: 0)
    #expect(sink.events.isEmpty)
}

@Test func bindingsRoundTripCodable() throws {
    var bindings = Bindings.defaults
    bindings[.swipeDown] = .switchSpace(.right)
    let decoded = try JSONDecoder().decode(Bindings.self, from: JSONEncoder().encode(bindings))
    #expect(decoded == bindings)
    #expect(decoded[.swipeDown] == .switchSpace(.right))
}
