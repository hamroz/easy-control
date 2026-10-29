import Foundation
import HandTracking
import Synchronization

/// Records labelled landmark sessions for training and replay tests. Landmarks only, never images.
final class LandmarkRecorder: Sendable {
    private let current = Mutex<HandFrameRecorder?>(nil)

    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "EasyControl/recordings", directoryHint: .isDirectory)
    }

    var isRecording: Bool { current.withLock { $0 != nil } }

    func start(label: String) throws {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let recorder = try HandFrameRecorder(url: Self.directory.appending(path: "\(label)-\(stamp).jsonl"))
        current.withLock { $0 = recorder }
    }

    /// Returns the file written, if a recording was running.
    @discardableResult
    func stop() throws -> URL? {
        let recorder = current.withLock { r in defer { r = nil }; return r }
        try recorder?.close()
        return recorder?.url
    }

    /// Called from the capture queue for every frame.
    func append(_ frame: HandFrame) {
        current.withLock { try? $0?.append(frame) }
    }
}
