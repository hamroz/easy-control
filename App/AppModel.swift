import AppKit
import Capture
import Foundation
import GestureEngine
import Observation
import os

@MainActor
@Observable
final class AppModel {
    private(set) var snapshot: PipelineSnapshot?
    private(set) var permissions = PermissionStatus.current()
    private(set) var userPaused = false
    private(set) var autoPaused = false
    private(set) var startError: String?

    let pipeline = Pipeline()
    let recorder = LandmarkRecorder()
    private(set) var isRecording = false
    private(set) var lastRecording: URL?
    private(set) var recordingError: String?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var autoPause: AutoPause?
    @ObservationIgnored private var permissionTimer: Timer?

    init() {
        pipeline.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in self?.snapshot = snapshot }
        }
        pipeline.onFrame = { [recorder] frame in recorder.append(frame) }
        autoPause = AutoPause { [weak self] paused in
            self?.autoPaused = paused
            self?.applyPause()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) {
            [pipeline] _ in pipeline.prepareToQuit()
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        refreshPermissions()
    }

    var isPaused: Bool { userPaused || autoPaused }

    func togglePause() {
        userPaused.toggle()
        applyPause()
    }

    func requestCamera() {
        Task {
            _ = await Permissions.requestCamera()
            refreshPermissions()
        }
    }

    @ObservationIgnored private let log = Logger(subsystem: "dev.hamroz.easycontrol", category: "permissions")

    func refreshPermissions() {
        let current = PermissionStatus.current()
        if current != permissions || !started {
            log.notice("camera=\(current.camera.rawValue, privacy: .public) accessibility=\(current.accessibility, privacy: .public) app=\(Bundle.main.bundlePath, privacy: .public)")
        }
        let accessibilityChanged = current.accessibility != permissions.accessibility || !started
        permissions = current
        if accessibilityChanged { pipeline.setDispatchEnabled(current.accessibility) }
        if current.camera == .authorized, !started { startPipeline() }
    }

    func toggleRecording(label: String) {
        do {
            if isRecording {
                lastRecording = try recorder.stop()
            } else {
                try recorder.start(label: label)
            }
            isRecording = recorder.isRecording
            recordingError = nil
        } catch {
            recordingError = error.localizedDescription
            isRecording = recorder.isRecording
        }
    }

    private func startPipeline() {
        do {
            try pipeline.start()
            started = true
            startError = nil
            applyPause()
        } catch {
            startError = "Camera could not start: \(error.localizedDescription)"
        }
    }

    private func applyPause() {
        guard started else { return }
        pipeline.setPaused(isPaused)
    }

    // MARK: Presentation

    var statusText: String {
        if let startError { return startError }
        if permissions.camera != .authorized { return "Camera access needed" }
        if isPaused { return autoPaused && !userPaused ? "Paused (screen locked or asleep)" : "Paused" }
        if !permissions.accessibility { return "Accessibility access needed to control the Mac" }
        switch snapshot?.captureState {
        case .interrupted?: return "Camera interrupted"
        case .noCamera?: return "No camera available"
        case .failed(let message)?: return "Camera error: \(message)"
        default: break
        }
        switch snapshot?.engine.state ?? .idle {
        case .paused: return "Paused"
        case .idle: return "Watching: open palm (or two/three fingers) to start"
        case .standby: return "Standby: make a gesture to continue"
        case .engaged(_, .command): return "Engaged: gestures active"
        case .engaged(_, .cursor): return "Cursor mode"
        }
    }

    var menuBarSymbol: String {
        if isPaused { return "hand.raised.slash" }
        if !permissions.allGranted || startError != nil { return "exclamationmark.triangle" }
        switch snapshot?.captureState {
        case .interrupted?, .noCamera?, .failed?: return "exclamationmark.triangle"
        default: break
        }
        if case .engaged = snapshot?.engine.state { return "hand.raised.fill" }
        return "hand.raised"
    }
}
