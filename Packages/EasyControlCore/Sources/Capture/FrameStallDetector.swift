/// Notices when the camera stops delivering frames without a pause (interruption, disconnect, revoked
/// permission), so the pipeline can end gestures instead of leaving them open.
public struct FrameStallDetector: Sendable {
    private let timeout: Double
    private var lastFrame: Double?

    public init(timeout: Double = 0.5) {
        self.timeout = timeout
    }

    public mutating func frameArrived(at t: Double) {
        lastFrame = t
    }

    /// False until the first frame has arrived.
    public func isStalled(at now: Double) -> Bool {
        guard let lastFrame else { return false }
        return now - lastFrame > timeout
    }
}
