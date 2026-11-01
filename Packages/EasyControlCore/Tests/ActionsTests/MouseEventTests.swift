import CoreGraphics
import Testing
@testable import Actions

@Test func mouseEventsCarryPositionAndClickCount() {
    let down = CGEventSink.makeEvent(.mouse(.leftDown, x: 120, y: 340, clickCount: 2))!
    #expect(down.type == .leftMouseDown)
    #expect(down.location == CGPoint(x: 120, y: 340))
    #expect(down.getIntegerValueField(.mouseEventClickState) == 2)
    #expect(CGEventSink.makeEvent(.mouse(.rightUp, x: 1, y: 2, clickCount: 1))!.type == .rightMouseUp)
    #expect(CGEventSink.makeEvent(.mouse(.leftDragged, x: 1, y: 2, clickCount: 1))!.type == .leftMouseDragged)
    #expect(CGEventSink.makeEvent(.mouse(.moved, x: 1, y: 2, clickCount: 0))!.type == .mouseMoved)
}

@Test func recordingSinkRecordsMouse() {
    let sink = RecordingEventSink()
    sink.post(.mouse(.moved, x: 3, y: 4, clickCount: 0))
    #expect(sink.events == [.mouse(.moved, x: 3, y: 4, clickCount: 0)])
}
