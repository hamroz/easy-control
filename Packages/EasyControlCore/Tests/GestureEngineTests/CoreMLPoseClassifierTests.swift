import Foundation
import Testing
import HandTracking
import Signal
import TestSupport
@testable import GestureEngine

private let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
private let packageURL = here.appending(path: "../../../../App/Resources/PoseClassifier.mlpackage").standardized
private let fixtureURL = here.appending(path: "Fixtures/pose-fixture.jsonl")

private struct FixtureRow: Decodable { var label: String; var vector: [Float] }

private func loadClassifier() async throws -> CoreMLPoseClassifier {
    try CoreMLPoseClassifier(compiledModelURL: try await CoreMLPoseClassifier.compile(packageURL))
}

@Test func fixtureAccuracy() async throws {
    let classifier = try await loadClassifier()
    let rows = try String(contentsOf: fixtureURL, encoding: .utf8).split(separator: "\n")
        .map { try JSONDecoder().decode(FixtureRow.self, from: Data($0.utf8)) }
    #expect(rows.count >= 250)
    let correct = rows.filter { row in
        let probs = classifier.classify(vector: row.vector)
        return probs.max { $0.value < $1.value }?.key.rawValue == row.label
    }.count
    #expect(Double(correct) / Double(rows.count) >= 0.95)
}

@Test func probabilitiesSumToOne() async throws {
    let classifier = try await loadClassifier()
    let probs = classifier.classify(HandFeatureExtractor.extract(SyntheticHand.make(.openPalm)))
    #expect(abs(probs.values.reduce(0, +) - 1) < 1e-3)
    #expect(probs.count >= 9) // a real model output, not the [.none: 1] failure fallback
    #expect(probs[.pinch] == nil || probs[.pinch] == 0)
}

@Test func unreliableHandsAreNone() async throws {
    let classifier = try await loadClassifier()
    var hand = SyntheticHand.make(.two)
    hand[.wrist].confidence = 0.05
    #expect(classifier.classify(HandFeatureExtractor.extract(hand)) == [.none: 1])
}

@Test func gateFollowsModelMetadata() async throws {
    let classifier = try await loadClassifier()
    var hand = SyntheticHand.make(.two)
    hand[.indexTip].confidence = 0.05 // reliable hand, one unknown finger
    let forcedNone = classifier.classify(HandFeatureExtractor.extract(hand)) == [.none: 1]
    #expect(forcedNone == classifier.requiresKnownFingers)
}

@Test func modelWithWrongInputLengthIsRejected() async throws {
    let compiled = try await CoreMLPoseClassifier.compile(packageURL)
    #expect(throws: (any Error).self) {
        _ = try CoreMLPoseClassifier(compiledModelURL: compiled, expectedInputLength: HandFeatures.vectorLength + 1)
    }
}

@Test func loadingMissingModelThrows() {
    #expect(throws: (any Error).self) {
        _ = try CoreMLPoseClassifier(compiledModelURL: URL(fileURLWithPath: "/nonexistent/PoseClassifier.mlmodelc"))
    }
}

@Test func classifiersReportTheirNames() {
    #expect(RuleBasedPoseClassifier().name == "rules")
}
