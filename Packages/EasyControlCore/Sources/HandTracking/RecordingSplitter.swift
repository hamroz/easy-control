/// Turns the user's labelled landmark recordings into training data: each file's first and last `trim`
/// seconds (getting into and out of the pose) are dropped, then time is split so the held-out part comes
/// strictly after the training part.
public enum RecordingSplitter {
    /// "train", "val", "test" or nil (dropped) for each timestamp, in that order in time.
    public static func assign(timestamps: [Double], trim: Double = 1, trainFraction: Double = 0.6,
                              valFraction: Double = 0.15) -> [String?] {
        guard let first = timestamps.first, let last = timestamps.last, last - first > 2 * trim else {
            return timestamps.map { _ in nil }
        }
        let start = first + trim, end = last - trim
        let trainEnd = start + (end - start) * trainFraction
        let valEnd = trainEnd + (end - start) * valFraction
        return timestamps.map { t in
            guard t >= start, t <= end else { return nil }
            return t < trainEnd ? "train" : t < valEnd ? "val" : "test"
        }
    }

    /// The recorder names files "<label>-<ISO8601 date>.jsonl".
    public static func label(forFileName name: String) -> String {
        name.components(separatedBy: "-20").first ?? name
    }
}
