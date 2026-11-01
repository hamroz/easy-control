// ec-replay: false-trigger benchmark. Replays landmark recordings (from the debug window's recorder)
// through the gesture engine and reports how many actions it would have fired per hour.
//
// Usage: ec-replay [--model App/Resources/PoseClassifier.mlpackage] <recording.jsonl>...
import Foundation
import GestureEngine
import HandTracking
import Signal

var args = Array(CommandLine.arguments.dropFirst())
var classifier: any PoseClassifying = RuleBasedPoseClassifier()
if let i = args.firstIndex(of: "--model"), args.indices.contains(i + 1) {
    let compiled = try await CoreMLPoseClassifier.compile(URL(fileURLWithPath: args[i + 1]))
    classifier = try CoreMLPoseClassifier(compiledModelURL: compiled)
    args.removeSubrange(i...(i + 1))
}
// --pinch-stats: distribution of the thumb–index ratio per recording (aggregates only), for calibration.
if args.contains("--pinch-stats") {
    args.removeAll { $0 == "--pinch-stats" }
    print("recording | frames | ratio p5 | p50 | p95 | share < close(\(TouchConfig.default.closeRatio)) | share < open(\(TouchConfig.default.openRatio)) | index reach of closed frames p5/p50/p95")
    for path in args {
        let frames = try HandFrameRecording.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        let kept = zip(frames, RecordingSplitter.assign(timestamps: frames.map(\.timestamp))).filter { $0.1 != nil }.map(\.0)
        var ratios: [Float] = []
        var reach: [Float] = [] // |index tip − wrist| / palm size, for frames that read as pinched
        for frame in kept {
            guard let hand = frame.hands.max(by: { HandNormalizer.palmSize($0) < HandNormalizer.palmSize($1) }),
                  hand[.thumbTip].confidence >= 0.3, hand[.indexTip].confidence >= 0.3 else { continue }
            let d = HandNormalizer.isotropic(hand, .thumbTip) - HandNormalizer.isotropic(hand, .indexTip)
            let r = (d * d).sum().squareRoot() / max(HandNormalizer.palmSize(hand), 1e-6)
            ratios.append(r)
            if r < TouchConfig.default.closeRatio {
                let e = HandNormalizer.isotropic(hand, .indexTip) - HandNormalizer.isotropic(hand, .wrist)
                reach.append((e * e).sum().squareRoot() / max(HandNormalizer.palmSize(hand), 1e-6))
            }
        }
        guard !ratios.isEmpty else { continue }
        let sorted = ratios.sorted()
        func q(_ p: Double) -> Float { sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
        let below = { (x: Float) in Double(ratios.filter { $0 < x }.count) / Double(ratios.count) * 100 }
        let rs = reach.sorted()
        func rq(_ p: Double) -> Float { rs.isEmpty ? .nan : rs[min(rs.count - 1, Int(Double(rs.count) * p))] }
        print("\((path as NSString).lastPathComponent) | \(ratios.count) | \(String(format: "%.3f | %.3f | %.3f | %.1f%% | %.1f%% | %.2f / %.2f / %.2f", q(0.05), q(0.5), q(0.95), below(TouchConfig.default.closeRatio), below(TouchConfig.default.openRatio), rq(0.05), rq(0.5), rq(0.95)))")
    }
    exit(0)
}

let poseMode = args.contains("--poses")
args.removeAll { $0 == "--poses" }
// --segment test: replay only the held-out part of each recording (the part never used for training).
var segment: String?
if let i = args.firstIndex(of: "--segment"), args.indices.contains(i + 1) {
    segment = args[i + 1]
    args.removeSubrange(i...(i + 1))
}
func load(_ path: String, segment: String?) throws -> [HandFrame] {
    let frames = try HandFrameRecording.decode(Data(contentsOf: URL(fileURLWithPath: path)))
    guard let segment else { return frames }
    let splits = RecordingSplitter.assign(timestamps: frames.map(\.timestamp))
    return zip(frames, splits).filter { $0.1 == segment }.map(\.0)
}
guard !args.isEmpty else {
    print("usage: ec-replay [--model <mlpackage>] [--poses] [--segment train|val|test] <recording.jsonl>...")
    exit(2)
}

if poseMode {
    // How the engine reads each recording: share of hand frames per stable pose (largest hand).
    for path in args {
        let frames = try load(path, segment: segment)
        let histogram = ReplayBenchmark.poseHistogram(frames, engine: GestureEngine(classifier: classifier))
        let total = max(histogram.values.reduce(0, +), 1)
        let parts = histogram.sorted { $0.value > $1.value }.prefix(4)
            .map { "\($0.key.rawValue) \(Int((Double($0.value) / Double(total) * 100).rounded()))%" }
        // Raw best guess and its confidence, before the 0.85 threshold and 3-frame stabilizer.
        let engine = GestureEngine(classifier: classifier)
        var raw: [PoseClass: Int] = [:], confident = 0, counted = 0
        for frame in frames {
            _ = engine.process(frame, lastUserInput: nil)
            guard let hand = engine.snapshot.hands.max(by: { $0.features.palmSize < $1.features.palmSize }),
                  let top = hand.probabilities.max(by: { $0.value < $1.value }) else { continue }
            raw[top.key, default: 0] += 1
            counted += 1
            if top.value >= 0.85 { confident += 1 }
        }
        let rawParts = raw.sorted { $0.value > $1.value }.prefix(3)
            .map { "\($0.key.rawValue) \(Int((Double($0.value) / Double(max(counted, 1)) * 100).rounded()))%" }
        print("\((path as NSString).lastPathComponent): stable [\(parts.joined(separator: ", "))]  raw [\(rawParts.joined(separator: ", "))]  ≥0.85: \(Int(Double(confident) / Double(max(counted, 1)) * 100))%")
    }
    exit(0)
}

print("classifier: \(classifier.name)\(segment.map { ", segment: \($0)" } ?? "")  (replay applies no typing suppression, so counts are conservative)")
print("recording | minutes | engagements | discrete | scrolls+dock | clicks | drags | actions/hour")
var totalDuration = 0.0, totalActions = 0
for path in args {
    let frames = try load(path, segment: segment)
    let s = ReplayBenchmark.run(frames, engine: GestureEngine(classifier: classifier))
    totalDuration += s.duration
    totalActions += s.discreteEvents + s.scrollsBegan + s.clicks + s.drags
    print("\((path as NSString).lastPathComponent) | \(String(format: "%.1f", s.duration / 60)) | \(s.engagements) | \(s.discreteEvents) | \(s.scrollsBegan) | \(s.clicks) | \(s.drags) | \(String(format: "%.1f", s.actionsPerHour))")
}
let perHour = totalDuration > 0 ? Double(totalActions) / totalDuration * 3600 : 0
print(String(format: "TOTAL %.1f min, %d actions, %.2f actions/hour (target < 1 on normal use)", totalDuration / 60, totalActions, perHour))
