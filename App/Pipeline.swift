import Actions
import Capture
import CoreVideo
import Foundation
import GestureEngine
import HandTracking
import QuartzCore
import os

struct PipelineSnapshot: Sendable {
    var engine: EngineSnapshot
    var fps: Double
    var latencyP50: Double?
    var latencyP95: Double?
    var captureState: CaptureState
    var latestFrame: HandFrame?
}

/// Camera → Vision → gesture engine on the capture queue; intents go to the output loop through `inbox`
/// (rendered at display rate by `OutputDriver`). Every mutable property below is only touched on `camera.queue`.
final class Pipeline: @unchecked Sendable {
    let camera = CameraCapture()
    let inbox = OutputInbox()
    private let detector = VisionHandDetector()
    private let engine = GestureEngine(classifier: Pipeline.loadClassifier())
    private let monitor = InputActivityMonitor()

    /// Set before `start()`; called on the capture queue whenever the output loop has work (argument: engaged).
    var onOutput: (@Sendable (Bool) -> Void)?

    /// Set before `start()`; called on the capture queue at most 10 times per second.
    var onSnapshot: (@Sendable (PipelineSnapshot) -> Void)?
    /// Set before `start()`; called on the capture queue for every processed frame (landmark recorder).
    var onFrame: (@Sendable (HandFrame) -> Void)?

    private var dispatchEnabled = false
    private var paused = false
    private var stall = FrameStallDetector()
    private var watchdog: DispatchSourceTimer?
    /// Last real-input time already acted on, so new input stops any coasting scroll exactly once.
    private var handledUserInput: Double?
    private var latency = RollingPercentiles()
    private var frameTimes: [Double] = []
    private var lastHandSeen: Double = 0
    private var lowPower = false
    private var lastPublish: Double = 0
    private var captureState: CaptureState = .stopped
    private var latestFrame: HandFrame?

    private static let activeFPS = 30.0
    private static let idleFPS = 10.0
    private static let idleAfter = 5.0

    init() {
        camera.onFrame = { [weak self] buffer, pts in self?.process(buffer, pts) }
        camera.onStateChange = { [weak self] state in
            guard let self else { return }
            camera.queue.async { self.captureState = state; self.publish(force: true) }
        }
    }

    /// The bundled Core ML model; the rule-based classifier if it's missing or fails to load.
    private static func loadClassifier() -> any PoseClassifying {
        let log = Logger(subsystem: "dev.hamroz.easycontrol", category: "classifier")
        guard let url = Bundle.main.url(forResource: "PoseClassifier", withExtension: "mlmodelc") else {
            log.error("PoseClassifier.mlmodelc not in bundle; using rules")
            return RuleBasedPoseClassifier()
        }
        do {
            let classifier = try CoreMLPoseClassifier(compiledModelURL: url)
            log.notice("loaded Core ML pose classifier")
            return classifier
        } catch {
            log.error("Core ML model failed to load (\(error.localizedDescription, privacy: .public)); using rules")
            return RuleBasedPoseClassifier()
        }
    }

    func start() throws {
        try camera.start()
        camera.queue.async { [self] in startWatchdog() }
    }

    /// Pausing stops the camera entirely, so the camera light goes off.
    func setPaused(_ paused: Bool) {
        camera.queue.async { [self] in
            self.paused = paused
            let now = CACurrentMediaTime()
            post(engine.setPaused(paused, at: now), at: now)
            if paused {
                inbox.postCancelAll(at: now) // the output loop keeps running until the Dock's end re-sends are out
                notifyOutput()
                stall = FrameStallDetector()
                camera.stop()
            } else {
                try? camera.start()
            }
            publish(force: true)
        }
    }

    /// Queues the end of any open scroll, drag or Dock swipe before the app quits; the caller flushes the
    /// output loop synchronously afterwards.
    func prepareToQuit() {
        camera.queue.sync {
            let now = CACurrentMediaTime()
            post(engine.setPaused(true, at: now), at: now)
            inbox.postCancelAll(at: now)
        }
    }

    /// Without Accessibility, gestures are still recognized (and shown) but nothing is injected.
    func setDispatchEnabled(_ enabled: Bool) {
        camera.queue.async { [self] in
            dispatchEnabled = enabled
            if enabled { monitor.start() } // also recreates the tap after a re-grant
        }
    }

    /// Injection is only allowed while the typing guard is live; otherwise try to bring it back.
    private var canDispatch: Bool {
        guard dispatchEnabled else { return false }
        return monitor.isRunning || monitor.start()
    }

    private func process(_ buffer: CVPixelBuffer, _ pts: Double) {
        let now = CACurrentMediaTime()
        // Presentation times are host-clock seconds; fall back to arrival time if a camera reports otherwise.
        let t = abs(now - pts) < 1 ? pts : now
        guard let frame = try? detector.detect(buffer, timestamp: t) else { return }
        latestFrame = frame
        stall.frameArrived(at: now)
        onFrame?(frame)

        stopMomentumOnUserInput()
        post(engine.process(frame, lastUserInput: monitor.lastUserInput), at: t)
        notifyOutput()

        let done = CACurrentMediaTime()
        latency.add((done - t) * 1000)
        frameTimes.append(done)
        frameTimes.removeAll { done - $0 > 1 }
        adjustFrameRate(handsVisible: !frame.hands.isEmpty, at: t)
        publish(force: false)
    }

    private func adjustFrameRate(handsVisible: Bool, at t: Double) {
        if handsVisible {
            lastHandSeen = t
            if lowPower {
                camera.setFrameRate(Self.activeFPS)
                lowPower = false
            }
        } else if !lowPower, t - lastHandSeen > Self.idleAfter {
            camera.setFrameRate(Self.idleFPS)
            lowPower = true
        }
    }

    /// Real keyboard/mouse input stops a coasting scroll, like touching a trackpad does.
    private func stopMomentumOnUserInput() {
        guard let input = monitor.lastUserInput, input != handledUserInput else { return }
        handledUserInput = input
        inbox.postCancelMomentum(at: CACurrentMediaTime())
    }

    private func post(_ events: [GestureEvent], at t: Double) {
        guard canDispatch else { return }
        inbox.post(events, at: t)
    }

    private func notifyOutput() {
        if case .engaged = engine.snapshot.state { onOutput?(true) } else { onOutput?(false) }
    }

    /// If frames stop arriving without a pause (camera interrupted, disconnected, permission revoked),
    /// feed the engine empty frames so open gestures end and engagement times out.
    private func startWatchdog() {
        guard watchdog == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: camera.queue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            guard let self, !paused else { return }
            let now = CACurrentMediaTime()
            guard stall.isStalled(at: now) else { return }
            post(engine.process(HandFrame(timestamp: now, hands: []), lastUserInput: monitor.lastUserInput), at: now)
            inbox.postCancelMomentum(at: now)
            notifyOutput()
            publish(force: true)
        }
        timer.resume()
        watchdog = timer
    }

    private func publish(force: Bool) {
        let now = CACurrentMediaTime()
        guard force || now - lastPublish >= 0.1 else { return }
        lastPublish = now
        onSnapshot?(PipelineSnapshot(
            engine: engine.snapshot,
            fps: Double(frameTimes.count),
            latencyP50: latency.percentile(0.5),
            latencyP95: latency.percentile(0.95),
            captureState: captureState,
            latestFrame: latestFrame
        ))
    }
}
