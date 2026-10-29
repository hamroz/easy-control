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
    /// How long an unseen hand keeps its identity. Matches the engine's hand-lost timeout, so a brief
    /// detection dropout (motion blur, a stalled frame) doesn't turn the engaged hand into a stranger.
    private let retainFor: Double
    /// Extra match radius per second unseen: a returning hand may have moved.
    private static let matchGrowthPerSecond: Float = 0.5
    private static let maxMatchRadius: Float = 0.4
    /// Vision's left/right guess can flicker, so a mismatch only makes a match less likely.
    private static let chiralityMismatchPenalty: Float = 0.1
    private var tracks: [Track] = []
    private var nextID: HandID = 1

    public init(maxMatchDistance: Float = 0.15, retainFor: Double = 1.0, filterParams: (Float, Float, Float) = (1.7, 0.3, 1.0)) {
        self.maxMatchDistance = maxMatchDistance
        self.retainFor = retainFor
        self.filterParams = filterParams
    }

    /// Identities currently tracked, including hands briefly unseen.
    public var activeIDs: Set<HandID> { Set(tracks.map(\.id)) }

    public static func palmCenter(_ hand: Hand) -> SIMD2<Float> { hand.palmCenter }

    public func update(_ frame: HandFrame) -> [TrackedHand] {
        let t = frame.timestamp
        tracks.removeAll { t - $0.lastSeen > retainFor || t < $0.lastSeen }

        let centers = frame.hands.map(Self.palmCenter)
        var pairs: [(dist: Float, hand: Int, track: Int)] = []
        for (h, hand) in frame.hands.enumerated() {
            for (k, track) in tracks.enumerated() {
                let d = centers[h] - track.center
                let penalty = Self.compatible(hand.chirality, track.chirality) ? 0 : Self.chiralityMismatchPenalty
                let dist = (d * d).sum().squareRoot() + penalty
                let radius = min(maxMatchDistance + Self.matchGrowthPerSecond * Float(t - track.lastSeen), Self.maxMatchRadius)
                if dist <= radius { pairs.append((dist, h, k)) }
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
            if hand.chirality != .unknown { tracks[k].chirality = hand.chirality }
            result.append(TrackedHand(id: tracks[k].id, hand: smoothed, raw: hand, firstSeen: tracks[k].firstSeen))
        }
        return result
    }

    private static func compatible(_ a: Chirality, _ b: Chirality) -> Bool {
        a == b || a == .unknown || b == .unknown
    }
}
