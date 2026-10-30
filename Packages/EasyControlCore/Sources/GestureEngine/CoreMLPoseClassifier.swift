import CoreML
import Foundation
import os
import Signal

public enum PoseModelError: Error, CustomStringConvertible {
    case incompatible(String)

    public var description: String {
        switch self {
        case .incompatible(let reason): "pose model doesn't match the app: \(reason)"
        }
    }
}

/// The learned pose classifier (trained in `tools/training`). Same runtime gate as the rules: unreliable
/// hands and hands with unknown fingers are `.none` before the model runs.
public final class CoreMLPoseClassifier: PoseClassifying, @unchecked Sendable {
    public let name = "coreml"
    private let model: MLModel
    private let log = Logger(subsystem: "dev.hamroz.easycontrol", category: "classifier")
    private var reportedFailure = false

    /// Validates the model's interface up front, so a mismatched model is rejected at load time (and the app
    /// falls back to the rules) instead of silently classifying every frame as `.none`.
    /// - Parameter compiledModelURL: a compiled `.mlmodelc` (Xcode compiles the `.mlpackage` into the app bundle).
    public init(compiledModelURL: URL, expectedInputLength: Int = HandFeatures.vectorLength) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly // a few-KB MLP: dispatching to the GPU/ANE costs more than it saves
        model = try MLModel(contentsOf: compiledModelURL, configuration: configuration)

        let description = model.modelDescription
        guard let shape = description.inputDescriptionsByName["features"]?.multiArrayConstraint?.shape,
              shape.last?.intValue == expectedInputLength else {
            throw PoseModelError.incompatible("input 'features' must have \(expectedInputLength) values")
        }
        guard description.outputDescriptionsByName["classLabel_probs"] != nil else {
            throw PoseModelError.incompatible("missing output 'classLabel_probs'")
        }
        let labels = description.classLabels as? [String] ?? []
        guard !labels.isEmpty, labels.allSatisfy({ PoseClass(rawValue: $0) != nil }) else {
            throw PoseModelError.incompatible("class labels \(labels) don't match PoseClass")
        }
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
        let raw: [String: NSNumber]
        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: ["features": MLFeatureValue(multiArray: input)])
            let output = try model.prediction(from: provider)
            guard let probs = output.featureValue(for: "classLabel_probs")?.dictionaryValue as? [String: NSNumber] else {
                throw PoseModelError.incompatible("no probabilities in output")
            }
            raw = probs
        } catch {
            if !reportedFailure {
                reportedFailure = true
                log.error("pose prediction failed: \(String(describing: error), privacy: .public)")
            }
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
