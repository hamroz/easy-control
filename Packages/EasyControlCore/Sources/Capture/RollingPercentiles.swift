/// Percentiles over the most recent `capacity` samples.
public struct RollingPercentiles: Sendable {
    private var values: [Double] = []
    private var next = 0
    private let capacity: Int

    public init(capacity: Int = 300) {
        self.capacity = capacity
    }

    public mutating func add(_ v: Double) {
        if values.count < capacity {
            values.append(v)
        } else {
            values[next] = v
        }
        next = (next + 1) % capacity
    }

    /// `p` in 0...1; nil when empty.
    public func percentile(_ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count) * p).rounded(.up)) - 1))
        return sorted[index]
    }
}
