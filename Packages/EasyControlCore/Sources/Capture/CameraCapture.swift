@preconcurrency import AVFoundation
import CoreMedia
import Foundation

public enum CaptureState: Sendable, Equatable {
    case stopped, running, interrupted, noCamera
    case failed(String)
}

public enum CaptureError: Error {
    case noCamera
    case cannotAddInput
    case cannotAddOutput
}

/// Front camera frames at 640×480, delivered on a serial queue. Late frames are dropped, never queued.
public final class CameraCapture: NSObject, @unchecked Sendable {
    public let session = AVCaptureSession()
    public let queue = DispatchQueue(label: "EasyControl.capture", qos: .userInteractive)
    /// Called on `queue` with the pixel buffer and its presentation time in host-clock seconds.
    public var onFrame: (@Sendable (CVPixelBuffer, Double) -> Void)?
    public var onStateChange: (@Sendable (CaptureState) -> Void)?

    private var device: AVCaptureDevice?
    private let output = AVCaptureVideoDataOutput()
    private var observers: [NSObjectProtocol] = []

    public override init() {
        super.init()
    }

    public func start() throws {
        if device == nil { try configure() }
        queue.async { [session] in session.startRunning() }
        onStateChange?(.running)
    }

    public func stop() {
        queue.async { [session] in session.stopRunning() }
        onStateChange?(.stopped)
    }

    /// Uses the closest rate the camera's active format supports.
    public func setFrameRate(_ fps: Double) {
        guard let device else { return }
        let ranges = device.activeFormat.videoSupportedFrameRateRanges.map { $0.minFrameRate...$0.maxFrameRate }
        guard let rate = Self.chooseFrameRate(fps, ranges: ranges) else { return }
        do {
            try device.lockForConfiguration()
            let duration = CMTime(value: 1000, timescale: CMTimeScale(rate * 1000))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            // Keep the current rate; the camera is still usable.
        }
    }

    /// A rate inside one of `ranges`: `fps` itself if supported, else the nearest range endpoint.
    /// (Setting a duration outside every supported range raises an Objective-C exception.)
    static func chooseFrameRate(_ fps: Double, ranges: [ClosedRange<Double>]) -> Double? {
        if ranges.contains(where: { $0.contains(fps) }) { return fps }
        return ranges.flatMap { [$0.lowerBound, $0.upperBound] }.min { abs($0 - fps) < abs($1 - fps) }
    }

    private func configure() throws {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video) else {
            onStateChange?(.noCamera)
            throw CaptureError.noCamera
        }
        device = camera
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CaptureError.cannotAddOutput }
        session.addOutput(output)
        setFrameRate(30)
        observe()
    }

    private func observe() {
        let center = NotificationCenter.default
        let report: (CaptureState) -> @Sendable (Notification) -> Void = { [weak self] state in
            { [weak self] _ in self?.onStateChange?(state) }
        }
        observers = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil,
                               using: report(.interrupted)),
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil,
                               using: report(.running)),
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
                let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
                self?.onStateChange?(.failed(error?.localizedDescription ?? "camera error"))
            },
            center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil,
                               using: report(.noCamera)),
        ]
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}

extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(buffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)
    }
}
