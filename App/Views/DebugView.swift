@preconcurrency import AVFoundation
import Capture
import GestureEngine
import HandTracking
import Signal
import SwiftUI

/// Live camera with the tracked skeleton, engine state, performance numbers and the landmark recorder.
struct DebugView: View {
    let model: AppModel
    @State private var label = "normal-use"

    private static let labels = ["normal-use"] + PoseClass.allCases.map(\.rawValue)

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.black
                CameraPreview(session: model.pipeline.camera.session)
                SkeletonOverlay(snapshot: model.snapshot?.engine)
            }
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stats
                    hands
                    recorder
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 300)
        }
    }

    private var stats: some View {
        let s = model.snapshot
        return VStack(alignment: .leading, spacing: 4) {
            Text("Status").font(.headline)
            Text(model.statusText)
            Text("State: \(describe(s?.engine.state ?? .idle))")
            Text("Classifier: \(s?.engine.classifierName ?? "–")")
            if s?.engine.suppressed == true { Text("Suppressed (keyboard/mouse in use)").foregroundStyle(.orange) }
            Text(String(format: "FPS: %.0f", s?.fps ?? 0))
            Text("Latency p50 / p95: \(ms(s?.latencyP50)) / \(ms(s?.latencyP95))")
            Text("Last event: \(s?.engine.lastEvent.map(describe) ?? "–")")
        }
        .font(.system(.body, design: .monospaced))
    }

    private var hands: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hands").font(.headline)
            if let hands = model.snapshot?.engine.hands, !hands.isEmpty {
                ForEach(hands, id: \.id) { hand in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("#\(hand.id) \(hand.hand.chirality.rawValue): \(hand.pose.rawValue)").bold()
                        Text(hand.probabilities.sorted { $0.value > $1.value }.prefix(3)
                            .map { "\($0.key.rawValue) \(Int($0.value * 100))%" }.joined(separator: "  "))
                        Text(String(format: "palm %.3f  reliable %@", hand.features.palmSize,
                                    hand.features.isReliable ? "yes" : "no"))
                        Text("fingers " + hand.features.fingerExtended.map { $0 ? "▮" : "▯" }.joined())
                    }
                    .font(.system(.caption, design: .monospaced))
                }
            } else {
                Text("No hands").foregroundStyle(.secondary)
            }
        }
    }

    private var recorder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Landmark recorder").font(.headline)
            Text("Saves hand landmarks only (no images) for training and tests.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Label", selection: $label) {
                ForEach(Self.labels, id: \.self) { Text($0) }
            }
            .disabled(model.isRecording)
            Button(model.isRecording ? "Stop recording" : "Start recording") {
                model.toggleRecording(label: label)
            }
            .tint(model.isRecording ? .red : .accentColor)
            if let url = model.lastRecording {
                Button("Show last recording in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(.link)
            }
            if let error = model.recordingError { Text(error).foregroundStyle(.red).font(.caption) }
        }
    }

    private func ms(_ v: Double?) -> String { v.map { String(format: "%.0f ms", $0) } ?? "–" }

    private func describe(_ state: EngagementState) -> String {
        switch state {
        case .paused: "paused"
        case .idle: "idle"
        case .engaged(let hand, let mode): "engaged #\(hand) (\(mode.rawValue))"
        }
    }

    private func describe(_ event: GestureEvent) -> String {
        switch event {
        case .discrete(let id): id.rawValue
        case .continuous(let id, let phase, _): "\(id.rawValue) \(phase.rawValue)"
        case .cursor: "cursor"
        case .engagement(let state): describe(state)
        }
    }
}

/// Mirrored camera preview sharing the pipeline's capture session.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Draws smoothed joints in our mirrored, top-left normalized coordinates.
private struct SkeletonOverlay: View {
    let snapshot: EngineSnapshot?

    var body: some View {
        Canvas { context, size in
            guard let snapshot else { return }
            let engagedID: HandID? = if case .engaged(let id, _) = snapshot.state { id } else { nil }
            for info in snapshot.hands {
                let color: Color = info.id == engagedID ? .green : (info.features.isReliable ? .yellow : .red)
                let point = { (j: JointName) in
                    CGPoint(x: CGFloat(info.hand[j].position.x) * size.width, y: CGFloat(info.hand[j].position.y) * size.height)
                }
                var bones = Path()
                for finger in JointName.fingers {
                    bones.move(to: point(.wrist))
                    finger.forEach { bones.addLine(to: point($0)) }
                }
                bones.move(to: point(.indexMCP))
                [JointName.middleMCP, .ringMCP, .littleMCP].forEach { bones.addLine(to: point($0)) }
                context.stroke(bones, with: .color(color), lineWidth: 3)
                for joint in JointName.allCases where info.hand[joint].confidence > 0.3 {
                    let p = point(joint)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(.white))
                }
                let wrist = point(.wrist)
                context.draw(Text("\(info.pose.rawValue)").font(.headline).foregroundStyle(color),
                             at: CGPoint(x: wrist.x, y: wrist.y + 18))
            }
        }
        .allowsHitTesting(false)
    }
}
