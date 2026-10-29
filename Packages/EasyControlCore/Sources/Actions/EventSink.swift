import Synchronization

public protocol EventSink: Sendable {
    func post(_ event: SyntheticEvent)
}

/// Captures events instead of posting them. Used by tests.
public final class RecordingEventSink: EventSink {
    private let storage = Mutex<[SyntheticEvent]>([])

    public init() {}

    public var events: [SyntheticEvent] { storage.withLock { $0 } }

    public func post(_ event: SyntheticEvent) {
        storage.withLock { $0.append(event) }
    }
}
