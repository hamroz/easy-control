// ec-extract: runs the runtime hand detector + feature extractor over a labelled image manifest, so the
// classifier is trained on exactly the features it will see live.
//
// Usage: ec-extract --manifest data/hagrid/manifest.jsonl --images data/hagrid/images --out data/hagrid/features.jsonl [--jobs N]
import Capture
import CoreGraphics
import Foundation
import HandTracking
import ImageIO
import Signal
import Synchronization

struct ManifestRecord: Decodable {
    struct Box: Decodable { var label: String; var bbox: [Double] }
    var image_id: String
    var source: String
    var split: String
    var user_id: String
    var boxes: [Box]
}

struct Sample: Encodable {
    var image_id: String
    var split: String
    var user_id: String
    var source: String
    var label: String
    var vector: [Float]
    var reliable: Bool
    var known: Bool
    var chirality: String
    var palmSize: Float
}

func argument(_ name: String) -> String? {
    let args = CommandLine.arguments
    return args.firstIndex(of: name).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
}

guard let manifestPath = argument("--manifest"), let imagesPath = argument("--images"), let outPath = argument("--out") else {
    print("usage: ec-extract --manifest <jsonl> --images <dir> --out <jsonl> [--jobs N]")
    exit(2)
}
let jobs = argument("--jobs").flatMap(Int.init) ?? ProcessInfo.processInfo.activeProcessorCount

let records = try String(contentsOfFile: manifestPath, encoding: .utf8)
    .split(separator: "\n").map { try JSONDecoder().decode(ManifestRecord.self, from: Data($0.utf8)) }
FileManager.default.createFile(atPath: outPath, contents: nil)
let output = try FileHandle(forWritingTo: URL(fileURLWithPath: outPath))

struct Counts { var images = 0, missing = 0, hands = 0, boxes = 0, matched = 0, lines = Data() }
let counts = Mutex(Counts())
let encoder = JSONEncoder()

DispatchQueue.concurrentPerform(iterations: jobs) { worker in
    let detector = VisionHandDetector(maxHands: 2)
    for index in stride(from: worker, to: records.count, by: jobs) {
        let rec = records[index]
        let url = URL(fileURLWithPath: imagesPath).appending(path: "\(rec.source)/\(rec.image_id).jpg")
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let frame = try? detector.detect(cgImage: image, timestamp: 0) else {
            counts.withLock { $0.missing += 1 }
            continue
        }
        let boxes = rec.boxes.map { LabeledBox(label: $0.label, rect: CGRect(x: $0.bbox[0], y: $0.bbox[1], width: $0.bbox[2], height: $0.bbox[3])) }
        let matches = HandBoxMatcher.match(hands: frame.hands, boxes: boxes)
        var lines = Data()
        for m in matches {
            let hand = frame.hands[m.hand]
            let f = HandFeatureExtractor.extract(hand)
            let sample = Sample(image_id: rec.image_id, split: rec.split, user_id: rec.user_id, source: rec.source,
                                label: boxes[m.box].label, vector: f.vector, reliable: f.isReliable,
                                known: !f.fingerKnown.contains(false), chirality: hand.chirality.rawValue, palmSize: f.palmSize)
            if let json = try? encoder.encode(sample) { lines.append(json); lines.append(0x0A) }
        }
        counts.withLock { c in
            c.images += 1
            c.hands += frame.hands.count
            c.boxes += boxes.count
            c.matched += matches.count
            c.lines.append(lines)
            if c.lines.count > 1 << 20 {
                try? output.write(contentsOf: c.lines)
                c.lines.removeAll(keepingCapacity: true)
            }
            if c.images % 2000 == 0 { print("  \(c.images)/\(records.count) images") }
        }
    }
}

let final = counts.withLock { $0 }
try output.write(contentsOf: final.lines)
try output.close()
let rate = final.boxes > 0 ? Double(final.matched) / Double(final.boxes) * 100 : 0
print("images \(final.images) (missing \(final.missing)), hands \(final.hands), boxes \(final.boxes), matched \(final.matched) (\(String(format: "%.1f", rate))%)")
