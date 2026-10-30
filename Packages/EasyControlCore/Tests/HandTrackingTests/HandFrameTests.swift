import Foundation
import Testing
import HandTracking
import TestSupport

@Test func jointOrderMatchesVision() {
    #expect(JointName.allCases.count == 21)
    #expect(JointName.indexTip.rawValue == 8)
    #expect(JointName.fingers[1] == [.indexMCP, .indexPIP, .indexDIP, .indexTip])
}

@Test func recordingRoundTrip() throws {
    var script = FrameScript(fps: 30)
    script.hold(.openPalm, at: [0.5, 0.5], for: 0.1)
    let frames = script.frames
    #expect(frames.count == 3)
    let data = try HandFrameRecording.encode(frames)
    let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
    #expect(lines.count == 3)
    #expect(try HandFrameRecording.decode(data) == frames)
}

@Test func syntheticOpenPalmFingertipsAboveMCPs() {
    let palm = SyntheticHand.make(.openPalm)
    for finger in JointName.fingers {
        #expect(palm[finger[3]].position.y < palm[finger[0]].position.y)
    }
    let fist = SyntheticHand.make(.fist)
    for finger in JointName.fingers.dropFirst() {
        #expect(fist[finger[3]].position.y > fist[finger[1]].position.y)
    }
}

@Test func frameScriptTiming() {
    var script = FrameScript(fps: 30)
    script.hold(.openPalm, at: [0.5, 0.5], for: 1.0)
    #expect(script.frames.count == 30)
    for (i, frame) in script.frames.enumerated() {
        #expect(abs(frame.timestamp - Double(i) / 30) < 1e-9)
    }
    script.gap(0.5)
    script.hold(.fist, at: [0.5, 0.5], for: 1.0 / 30)
    #expect(abs(script.frames.last!.timestamp - (1.0 + 0.5)) < 1e-9)
}

@Test func recorderFileDecodes() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    var script = FrameScript(fps: 30)
    script.hold(.two, at: [0.4, 0.6], for: 10.0 / 30)
    let recorder = try HandFrameRecorder(url: url)
    for frame in script.frames { try recorder.append(frame) }
    try recorder.close()
    let decoded = try HandFrameRecording.decode(Data(contentsOf: url))
    #expect(decoded.count == 10)
    #expect(decoded == script.frames)
}

@Test func olderRecordingsWithoutAspectDecode() throws {
    var hand = SyntheticHand.make(.fist)
    hand.aspectRatio = 4.0 / 3.0
    var json = String(decoding: try JSONEncoder().encode(hand), as: UTF8.self)
    json = json.replacingOccurrences(of: #","aspectRatio":1.3333334"#, with: "").replacingOccurrences(of: #""aspectRatio":1.3333334,"#, with: "")
    #expect(!json.contains("aspectRatio"))
    #expect(try JSONDecoder().decode(Hand.self, from: Data(json.utf8)).aspectRatio == 1)
}

@Test func flippingChiralitySwapsLeftAndRight() {
    #expect(SyntheticHand.make(.two, chirality: .right).withFlippedChirality().chirality == .left)
    #expect(SyntheticHand.make(.two, chirality: .left).withFlippedChirality().chirality == .right)
    let unknown = SyntheticHand.make(.two, chirality: .unknown)
    #expect(unknown.withFlippedChirality() == unknown)
}

@Test func recordingSplitIsTemporal() {
    let timestamps = (0..<300).map { Double($0) / 30 } // 10 s recording
    let splits = RecordingSplitter.assign(timestamps: timestamps, trim: 1, trainFraction: 0.6, valFraction: 0.15)
    #expect(splits.prefix(30).allSatisfy { $0 == nil })           // first second dropped
    #expect(splits.suffix(30).allSatisfy { $0 == nil })           // last second dropped
    let kept = splits.compactMap { $0 }
    #expect(kept.first == "train" && kept.last == "test")
    // Strictly ordered in time: train, then val, then test.
    let order = ["train": 0, "val": 1, "test": 2]
    #expect(zip(kept, kept.dropFirst()).allSatisfy { order[$0]! <= order[$1]! })
    let share = { (s: String) in Double(kept.filter { $0 == s }.count) / Double(kept.count) }
    #expect(abs(share("train") - 0.6) < 0.02 && abs(share("val") - 0.15) < 0.02)
}

@Test func recordingLabelComesFromFileName() {
    #expect(RecordingSplitter.label(forFileName: "thumbsUp-2026-10-30T01-04-14Z.jsonl") == "thumbsUp")
    #expect(RecordingSplitter.label(forFileName: "normal-use-2026-10-30T00-43-24Z.jsonl") == "normal-use")
}
