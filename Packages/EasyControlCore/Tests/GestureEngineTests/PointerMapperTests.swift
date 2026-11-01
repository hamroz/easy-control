import CoreGraphics
import Testing
@testable import GestureEngine

@Test func gainCurve() {
    let m = PointerMapper()
    #expect(m.gain(speed: 0.1) == 0.6)
    #expect(abs(m.gain(speed: 1.2) - 2.5) < 1e-9)
    #expect(m.gain(speed: 3) == 2.5)
    #expect(abs(m.gain(speed: 0.675) - 1.55) < 1e-9)
}

@Test func pixelsScaleWithScreenHeight() {
    let m = PointerMapper(speedMultiplier: 2)
    let p = m.pixels(handDelta: [0.01, -0.02], speed: 0.1, screenHeight: 1000)
    #expect(abs(p.x - 12) < 1e-6 && abs(p.y + 24) < 1e-6) // 0.6 gain × 2 multiplier × 1000 px
}

@Test func clampAcrossDisplays() {
    let displays = [CGRect(x: 0, y: 0, width: 1728, height: 1117), CGRect(x: -1920, y: -200, width: 1920, height: 1080)]
    #expect(PointerMapper.clamp(CGPoint(x: -2500, y: 500), to: displays) == CGPoint(x: -1920, y: 500))
    #expect(PointerMapper.clamp(CGPoint(x: 100, y: 100), to: displays) == CGPoint(x: 100, y: 100))
    // Below the shorter second display and left of the main one: snapped to the nearest display edge.
    let snapped = PointerMapper.clamp(CGPoint(x: -10, y: 1100), to: displays)
    #expect(snapped == CGPoint(x: 0, y: 1100))
}
