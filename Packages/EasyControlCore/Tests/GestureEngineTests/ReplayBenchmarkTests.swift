import Testing
import HandTracking
import TestSupport
@testable import GestureEngine

@Test func statsCountActions() {
    var s = FrameScript()
    s.hold(.openPalm, at: [0.5, 0.5], for: 0.5)
    s.hold(.three, at: [0.5, 0.5], for: 0.2)
    s.move(.three, from: [0.5, 0.5], to: [0.7, 0.5], over: 0.3)
    s.hold(.openPalm, at: [0.7, 0.5], for: 0.5)
    s.hold(.pinch, at: [0.7, 0.5], for: 0.1)
    s.move(.pinch, from: [0.7, 0.5], to: [0.7, 0.7], over: 0.3)
    s.hold(.openPalm, at: [0.7, 0.7], for: 0.3)
    let stats = ReplayBenchmark.run(s.frames, engine: GestureEngine())
    #expect(stats.engagements == 1)
    #expect(stats.discreteEvents == 0)
    #expect(stats.scrollsBegan == 2) // the Dock drag and the pinch scroll
    #expect(abs(stats.duration - (s.frames.last!.timestamp - s.frames.first!.timestamp)) < 1e-9)
    #expect(abs(stats.actionsPerHour - 2 / stats.duration * 3600) < 1e-6)
}

@Test func idleRecordingHasNoActions() {
    var s = FrameScript()
    s.hold(.fist, at: [0.5, 0.5], for: 10)
    let stats = ReplayBenchmark.run(s.frames, engine: GestureEngine())
    #expect(stats.engagements == 0 && stats.discreteEvents == 0 && stats.scrollsBegan == 0)
    #expect(stats.actionsPerHour == 0)
}

@Test func poseHistogramCountsStablePosesPerFrame() {
    var s = FrameScript()
    s.hold(.fist, at: [0.5, 0.5], for: 1)
    s.empty(for: 0.5)
    let histogram = ReplayBenchmark.poseHistogram(s.frames, engine: GestureEngine())
    #expect(histogram[.fist, default: 0] >= 27) // 30 frames minus the stabilizer's 2-frame warm-up
    #expect(histogram.values.reduce(0, +) == 30) // only frames with a hand count
}
