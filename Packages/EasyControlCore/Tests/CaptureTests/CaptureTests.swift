import CoreGraphics
import Foundation
import ImageIO
import Testing
import Vision
import HandTracking
@testable import Capture

@Test func convertFlipsBothAxes() {
    let p = VisionHandDetector.convert(CGPoint(x: 0.2, y: 0.9))
    #expect(abs(p.x - 0.8) < 1e-6 && abs(p.y - 0.1) < 1e-6)
}

@Test func allVisionJointsMapped() {
    let mapped = VisionHandDetector.visionJoints.map(VisionHandDetector.jointName(for:))
    #expect(VisionHandDetector.visionJoints.count == 21)
    #expect(Set(mapped).count == 21)
    #expect(VisionHandDetector.jointName(for: .indexTip) == .indexTip)
    #expect(VisionHandDetector.jointName(for: .thumbCMC) == .thumbCMC)
}

@Test func percentiles() {
    var r = RollingPercentiles(capacity: 100)
    #expect(r.percentile(0.5) == nil)
    for v in 1...100 { r.add(Double(v)) }
    #expect(abs(r.percentile(0.5)! - 50) <= 1)
    #expect(abs(r.percentile(0.95)! - 95) <= 1)
    for _ in 0..<100 { r.add(1000) }
    #expect(r.percentile(0.5) == 1000)
}

private let sampleDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("../../../../data/hagrid-sample/palm").standardized

@Test(.enabled(if: FileManager.default.fileExists(atPath: sampleDir.path)))
func detectsHandInSampleImage() throws {
    let file = try FileManager.default.contentsOfDirectory(at: sampleDir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "jpg" }.sorted { $0.path < $1.path }.first!
    let src = CGImageSourceCreateWithURL(file as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    let frame = try VisionHandDetector().detect(cgImage: image, timestamp: 1)
    #expect(frame.timestamp == 1)
    #expect(frame.hands.count >= 1)
    #expect(frame.hands[0].joints.filter { $0.confidence > 0.3 }.count >= 15)
}

@Test func stallDetector() {
    var d = FrameStallDetector(timeout: 0.5)
    #expect(!d.isStalled(at: 10))
    d.frameArrived(at: 0)
    #expect(!d.isStalled(at: 0.4))
    #expect(d.isStalled(at: 0.6))
    d.frameArrived(at: 0.7)
    #expect(!d.isStalled(at: 0.8))
}

@Test func frameRateStaysInsideSupportedRanges() {
    #expect(CameraCapture.chooseFrameRate(10, ranges: [1...30]) == 10)
    #expect(CameraCapture.chooseFrameRate(10, ranges: [5...5, 30...30]) == 5)
    #expect(CameraCapture.chooseFrameRate(10, ranges: [15...30]) == 15)
    #expect(CameraCapture.chooseFrameRate(60, ranges: [1...30]) == 30)
    #expect(CameraCapture.chooseFrameRate(10, ranges: []) == nil)
}
