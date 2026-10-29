/// The 21 hand joints, in the same order Vision and MediaPipe use.
public enum JointName: Int, CaseIterable, Codable, Sendable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip

    /// Joints of each finger, thumb to little, ordered base to tip.
    public static let fingers: [[JointName]] = [
        [.thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        [.indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.littleMCP, .littlePIP, .littleDIP, .littleTip],
    ]
}
