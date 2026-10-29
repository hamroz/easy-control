import Foundation
import HandTracking

/// Builds timed sequences of `HandFrame`s for replay-style tests.
public struct FrameScript: Sendable {
    public let fps: Double
    public private(set) var frames: [HandFrame] = []
    private var frameIndex = 0
    private var offset: Double

    public init(fps: Double = 30, start: Double = 0) {
        self.fps = fps
        self.offset = start
    }

    /// Timestamp the next appended frame will get.
    public var now: Double { offset + Double(frameIndex) / fps }

    private func frameCount(_ seconds: Double) -> Int { Int((seconds * fps).rounded()) }

    public mutating func append(_ hands: [Hand], for seconds: Double) {
        for _ in 0..<max(frameCount(seconds), 1) { appendFrame(hands) }
    }

    public mutating func appendFrame(_ hands: [Hand]) {
        frames.append(HandFrame(timestamp: now, hands: hands))
        frameIndex += 1
    }

    public mutating func hold(
        _ pose: SyntheticPose, at center: SIMD2<Float>, for seconds: Double, palmSize: Float = 0.12
    ) {
        append([SyntheticHand.make(pose, center: center, palmSize: palmSize)], for: seconds)
    }

    public mutating func move(
        _ pose: SyntheticPose, from: SIMD2<Float>, to: SIMD2<Float>, over seconds: Double, palmSize: Float = 0.12
    ) {
        let n = max(frameCount(seconds), 1)
        for i in 1...n {
            let t = Float(i) / Float(n)
            appendFrame([SyntheticHand.make(pose, center: from + (to - from) * t, palmSize: palmSize)])
        }
    }

    public mutating func empty(for seconds: Double) {
        append([], for: seconds)
    }

    /// Skips time without producing frames (dropped frames, sleep).
    public mutating func gap(_ seconds: Double) {
        offset += seconds
    }
}
