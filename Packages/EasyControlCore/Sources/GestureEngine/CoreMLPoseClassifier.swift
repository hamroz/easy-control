import CoreML
import Foundation
import Signal

/// The learned pose classifier (trained in `tools/training`). Same runtime gate as the rules: unreliable
/// hands and hands with unknown fingers are `.none` before the model runs.
public final class CoreMLPoseClassifier: PoseClassifying, @unchecked Sendable {
    public let name = "coreml"
    private let model: MLModel

    /// - Parameter compiledModelURL: a compiled `.mlmodelc` (Xcode compiles the `.mlpackage` into the app bundle).
    public init(compiledModelURL: URL) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly // a few-KB MLP: dispatching to the GPU/ANE costs more than it saves
        model = try MLModel(contentsOf: compiledModelURL, configuration: configuration)
    }

    /// Compiles an `.mlpackage` (tests and tools; the app ships a precompiled model).
    public static func compile(_ packageURL: URL) async throws -> URL {
        try await MLModel.compileModel(at: packageURL)
    }

    public func classify(_ features: HandFeatures) -> [PoseClass: Float] {
        guard features.isReliable, !features.fingerKnown.contains(false) else { return [.none: 1] }
        return classify(vector: features.vector)
    }

    /// Classifies a raw 52-float `HandFeatures.vector` (no gate).
    public func classify(vector: [Float]) -> [PoseClass: Float] {
        guard let input = try? MLMultiArray(shape: [1, NSNumber(value: vector.count)], dataType: .float32) else { return [.none: 1] }
        for (i, v) in vector.enumerated() { input[i] = NSNumber(value: v) }
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: ["features": MLFeatureValue(multiArray: input)]),
              let output = try? model.prediction(from: provider),
              let raw = output.featureValue(for: "classLabel_probs")?.dictionaryValue as? [String: NSNumber] else {
            return [.none: 1]
        }
        var probs: [PoseClass: Float] = [:]
        for (label, p) in raw {
            if let pose = PoseClass(rawValue: label) { probs[pose] = p.floatValue }
        }
        let total = probs.values.reduce(0, +)
        guard total > 0 else { return [.none: 1] }
        return probs.mapValues { $0 / total }
    }
}
