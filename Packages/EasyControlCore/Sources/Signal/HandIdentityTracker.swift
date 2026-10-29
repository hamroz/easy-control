import HandTracking

public typealias HandID = Int

public struct TrackedHand: Sendable {
    public var id: HandID
    /// Joint positions smoothed by per-joint One Euro filters; confidences are the raw ones.
    public var hand: Hand
    public var raw: Hand
    public var firstSeen: Double
}

/// Gives each hand a stable identity across frames and smooths its joints.
public final class HandIdentityTracker {
    private struct Track {
        var id: HandID
        var chirality: Chirality
        var center: SIMD2<Float>
        var lastSeen: Double
        var firstSeen: Double
        var filters: [OneEuroFilter]
    }

    private let maxMatchDistance: Float
    private let filterParams: (Float, Float, Float)
    private let dropAfter: Double = 0.25
    private var tracks: [Track] = []
    private var nextID: HandID = 1

    public init(maxMatchDistance: Float = 0.15, filterParams: (Float, Float, Float) = (1.7, 0.3, 1.0)) {
        self.maxMatchDistance = maxMatchDistance
        self.filterParams = filterParams
    }

    public static func palmCenter(_ hand: Hand) -> SIMD2<Float> {
        let joints: [JointName] = [.wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP]
        return joints.reduce(SIMD2<Float>.zero) { $0 + hand[$1].position } / Float(joints.count)
    }

    public func update(_ frame: HandFrame) -> [TrackedHand] {
        let t = frame.timestamp
        tracks.removeAll { t - $0.lastSeen > dropAfter || t < $0.lastSeen }

        let centers = frame.hands.map(Self.palmCenter)
        var pairs: [(dist: Float, hand: Int, track: Int)] = []
        for (h, hand) in frame.hands.enumerated() {
            for (k, track) in tracks.enumerated() where Self.compatible(hand.chirality, track.chirality) {
                let d = centers[h] - track.center
                let dist = (d * d).sum().squareRoot()
                if dist <= maxMatchDistance { pairs.append((dist, h, k)) }
            }
        }
        var handToTrack: [Int: Int] = [:]
        var usedTracks = Set<Int>()
        for pair in pairs.sorted(by: { $0.dist < $1.dist })
        where handToTrack[pair.hand] == nil && !usedTracks.contains(pair.track) {
            handToTrack[pair.hand] = pair.track
            usedTracks.insert(pair.track)
        }

        var result: [TrackedHand] = []
        for (h, hand) in frame.hands.enumerated() {
            let k: Int
            if let matched = handToTrack[h] {
                k = matched
            } else {
                let (minCutoff, beta, dCutoff) = filterParams
                let filters = Array(repeating: OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff),
                                    count: JointName.allCases.count)
                tracks.append(Track(id: nextID, chirality: hand.chirality, center: centers[h],
                                    lastSeen: t, firstSeen: t, filters: filters))
                nextID += 1
                k = tracks.count - 1
            }
            var smoothed = hand
            for j in 0..<hand.joints.count {
                smoothed.joints[j].position = tracks[k].filters[j].filter(hand.joints[j].position, at: t)
            }
            tracks[k].center = centers[h]
            tracks[k].lastSeen = t
            if tracks[k].chirality == .unknown { tracks[k].chirality = hand.chirality }
            result.append(TrackedHand(id: tracks[k].id, hand: smoothed, raw: hand, firstSeen: tracks[k].firstSeen))
        }
        return result
    }

    private static func compatible(_ a: Chirality, _ b: Chirality) -> Bool {
        a == b || a == .unknown || b == .unknown
    }
}
