/// CGEventFlags raw values, kept here so actions can be described and tested without CoreGraphics.
public enum KeyFlags {
    public static let control: UInt64 = 0x0004_0000
    public static let numericPad: UInt64 = 0x0020_0000
    public static let secondaryFn: UInt64 = 0x0080_0000
    /// What a physical arrow key reports. macOS only matches the Ctrl+Arrow Space/Mission Control hotkeys
    /// when synthetic arrows carry these too (verified in docs/spikes/m0-results.md).
    public static let controlArrow = control | secondaryFn | numericPad
}

public enum KeyCode {
    public static let leftArrow: UInt16 = 123
    public static let rightArrow: UInt16 = 124
    public static let downArrow: UInt16 = 125
    public static let upArrow: UInt16 = 126
}

public enum Direction: String, Codable, Sendable {
    case left, right, up, down
}

extension EventSink {
    func press(_ code: UInt16, flags: UInt64) {
        post(.key(code: code, flags: flags, down: true))
        post(.key(code: code, flags: flags, down: false))
    }
}

public protocol SpaceSwitchStrategy: Sendable {
    func switchSpace(_ direction: Direction)
}

/// Uses the system "Move left/right a space" shortcuts (Ctrl+←/→).
public struct ControlArrowStrategy: SpaceSwitchStrategy {
    private let sink: any EventSink
    private let flags: UInt64

    public init(sink: any EventSink, flags: UInt64 = KeyFlags.controlArrow) {
        self.sink = sink
        self.flags = flags
    }

    public func switchSpace(_ direction: Direction) {
        switch direction {
        case .left: sink.press(KeyCode.leftArrow, flags: flags)
        case .right: sink.press(KeyCode.rightArrow, flags: flags)
        case .up, .down: break
        }
    }
}
