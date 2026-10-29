import GestureEngine

public enum Action: Codable, Hashable, Sendable {
    case scroll
    case switchSpace(Direction)
    case missionControl
    case appExpose
    case none
}

/// Which action each gesture triggers.
public struct Bindings: Codable, Equatable, Sendable {
    private var map: [String: Action]

    public init(_ map: [GestureID: Action] = [:]) {
        self.map = Dictionary(uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value) })
    }

    public static let defaults = Bindings([
        .scroll: .scroll,
        .swipeLeft: .switchSpace(.left),
        .swipeRight: .switchSpace(.right),
        .swipeUp: .missionControl,
        .swipeDown: .appExpose,
    ])

    public subscript(_ id: GestureID) -> Action {
        get { map[id.rawValue] ?? .none }
        set { map[id.rawValue] = newValue }
    }
}
