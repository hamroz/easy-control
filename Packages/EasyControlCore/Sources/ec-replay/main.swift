// ec-replay: false-trigger benchmark. Replays landmark recordings (from the debug window's recorder)
// through the gesture engine and reports how many actions it would have fired per hour.
//
// Usage: ec-replay [--model App/Resources/PoseClassifier.mlpackage] <recording.jsonl>...
import Foundation
import GestureEngine
import HandTracking

var args = Array(CommandLine.arguments.dropFirst())
var classifier: any PoseClassifying = RuleBasedPoseClassifier()
if let i = args.firstIndex(of: "--model"), args.indices.contains(i + 1) {
    let compiled = try await CoreMLPoseClassifier.compile(URL(fileURLWithPath: args[i + 1]))
    classifier = try CoreMLPoseClassifier(compiledModelURL: compiled)
    args.removeSubrange(i...(i + 1))
}
guard !args.isEmpty else {
    print("usage: ec-replay [--model <mlpackage>] <recording.jsonl>...")
    exit(2)
}

print("classifier: \(classifier.name)")
print("recording | minutes | engagements | swipes | scrolls | actions/hour")
var totalDuration = 0.0, totalActions = 0
for path in args {
    let frames = try HandFrameRecording.decode(Data(contentsOf: URL(fileURLWithPath: path)))
    let s = ReplayBenchmark.run(frames, engine: GestureEngine(classifier: classifier))
    totalDuration += s.duration
    totalActions += s.discreteEvents + s.scrollsBegan
    print("\((path as NSString).lastPathComponent) | \(String(format: "%.1f", s.duration / 60)) | \(s.engagements) | \(s.discreteEvents) | \(s.scrollsBegan) | \(String(format: "%.1f", s.actionsPerHour))")
}
let perHour = totalDuration > 0 ? Double(totalActions) / totalDuration * 3600 : 0
print(String(format: "TOTAL %.1f min, %d actions, %.2f actions/hour (target < 1 on normal use)", totalDuration / 60, totalActions, perHour))
