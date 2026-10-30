import Synchronization

public protocol EventSink: Sendable {
    func post(_ event: SyntheticEvent)
    /// Whether `.dockSwipe` events can be delivered (they need private macOS API).
    var supportsDockSwipe: Bool { get }
}

extension EventSink {
    public var supportsDockSwipe: Bool { false }
}

/// Captures events instead of posting them. Used by tests.
public final class RecordingEventSink: EventSink {
    private let storage = Mutex<[SyntheticEvent]>([])
    public let supportsDockSwipe: Bool

    public init(supportsDockSwipe: Bool = false) {
        self.supportsDockSwipe = supportsDockSwipe
    }

    public var events: [SyntheticEvent] { storage.withLock { $0 } }

    public func post(_ event: SyntheticEvent) {
        storage.withLock { $0.append(event) }
    }
}
