// M0 SPIKE — THROWAWAY. Measures Vision hand-pose latency on sample images with both APIs.
// Build: swiftc -O -parse-as-library tools/spikes/vision_bench.swift -o /tmp/vision_bench; run with image root dir.
import Foundation
import ImageIO
import Vision

func loadImages(_ root: URL) -> [(String, CGImage)] {
    let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
        .compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "jpg" }.sorted { $0.path < $1.path }
    return files.compactMap { url in
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return (url.deletingLastPathComponent().lastPathComponent, img)
    }
}

func pct(_ xs: [Double], _ p: Double) -> Double {
    let s = xs.sorted(); return s[min(s.count - 1, Int(Double(s.count) * p))]
}

func cpuSeconds() -> Double {
    var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
        + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
}

@main struct Bench {
    static func main() async throws {
        let images = loadImages(URL(fileURLWithPath: CommandLine.arguments[1]))
        print("images: \(images.count)")
        let runs = 5

        // Legacy VN API (synchronous).
        var legacy: [Double] = []; var legacyHits = 0; var perClass: [String: (Int, Int)] = [:]
        var chirality: [String: Int] = [:]
        let c0 = cpuSeconds()
        for (cls, img) in images {
            let req = VNDetectHumanHandPoseRequest(); req.maximumHandCount = 2
            try VNImageRequestHandler(cgImage: img).perform([req]) // warm-up
            for r in 0..<runs {
                let t = CFAbsoluteTimeGetCurrent()
                try VNImageRequestHandler(cgImage: img).perform([req])
                legacy.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
                if r == 0 {
                    let obs = req.results ?? []
                    let good = obs.contains { o in ((try? o.recognizedPoints(.all)) ?? [:]).values.filter { $0.confidence > 0.3 }.count >= 15 }
                    if good { legacyHits += 1 }
                    let e = perClass[cls] ?? (0, 0); perClass[cls] = (e.0 + (good ? 1 : 0), e.1 + 1)
                    for o in obs { chirality["\(o.chirality.rawValue)", default: 0] += 1 }
                }
            }
        }
        let legacyCPU = (cpuSeconds() - c0) / Double(images.count * (runs + 1)) * 1000

        // New Swift API (async).
        var modern: [Double] = []; var modernHits = 0
        var request = DetectHumanHandPoseRequest(); request.maximumHandCount = 2
        let c1 = cpuSeconds()
        for (_, img) in images {
            _ = try await request.perform(on: img)
            for r in 0..<runs {
                let t = CFAbsoluteTimeGetCurrent()
                let obs = try await request.perform(on: img)
                modern.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
                if r == 0, obs.contains(where: { $0.allJoints().values.filter { $0.confidence > 0.3 }.count >= 15 }) { modernHits += 1 }
            }
        }
        let modernCPU = (cpuSeconds() - c1) / Double(images.count * (runs + 1)) * 1000

        print(String(format: "VNDetectHumanHandPoseRequest: p50 %.1f ms, p95 %.1f ms, CPU %.1f ms/img, detected %d/%d",
                     pct(legacy, 0.5), pct(legacy, 0.95), legacyCPU, legacyHits, images.count))
        print(String(format: "DetectHumanHandPoseRequest:   p50 %.1f ms, p95 %.1f ms, CPU %.1f ms/img, detected %d/%d",
                     pct(modern, 0.5), pct(modern, 0.95), modernCPU, modernHits, images.count))
        print("per class (legacy):", perClass.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.0)/\($0.value.1)" }.joined(separator: ", "))
        print("chirality raw values seen (legacy, -1 left, 0 unknown, 1 right):", chirality)
    }
}
