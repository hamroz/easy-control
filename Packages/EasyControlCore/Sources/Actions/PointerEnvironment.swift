import CoreGraphics

/// Where the cursor is and what displays exist (global coordinates, origin top-left of the main display).
public protocol PointerEnvironment: Sendable {
    func cursorLocation() -> CGPoint
    func displayFrames() -> [CGRect]
    /// Height in points of the display the cursor is on: hand travel maps to it.
    func screenHeight() -> Double
}

public struct SystemPointerEnvironment: PointerEnvironment {
    public init() {}

    public func cursorLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    public func displayFrames() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map(CGDisplayBounds)
    }

    public func screenHeight() -> Double {
        let cursor = cursorLocation()
        let frames = displayFrames()
        let current = frames.first { $0.contains(cursor) } ?? frames.first
        return Double(current?.height ?? 1000)
    }
}
