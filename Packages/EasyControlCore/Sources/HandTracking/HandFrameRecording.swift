import Foundation

/// JSON Lines encoding of hand frames: one frame per line. Landmarks only, never images.
public enum HandFrameRecording {
    public static func encode(_ frames: [HandFrame]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = Data()
        for frame in frames {
            data.append(try encoder.encode(frame))
            data.append(0x0A)
        }
        return data
    }

    public static func decode(_ data: Data) throws -> [HandFrame] {
        let decoder = JSONDecoder()
        return try data.split(separator: 0x0A).map { try decoder.decode(HandFrame.self, from: Data($0)) }
    }
}
