import Foundation
import Synchronization

/// Appends hand frames to a JSON Lines file as they arrive (landmarks only).
public final class HandFrameRecorder: Sendable {
    public let url: URL
    private let handle: Mutex<FileHandle?>

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = Mutex(try FileHandle(forWritingTo: url))
    }

    public func append(_ frame: HandFrame) throws {
        let line = try HandFrameRecording.encode([frame])
        try handle.withLock { try $0?.write(contentsOf: line) }
    }

    public func close() throws {
        try handle.withLock {
            try $0?.close()
            $0 = nil
        }
    }
}
