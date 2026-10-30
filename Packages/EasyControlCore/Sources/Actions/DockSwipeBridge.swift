import CoreGraphics
import Foundation

/// The only place EasyControl touches private macOS API: the Dock Swipe IOHIDEvent the Dock uses for
/// three-finger trackpad swipes, attached to a CGEvent through SkyLight. Symbols are resolved with `dlsym`;
/// if any is missing (a future macOS), `isAvailable` is false and callers fall back to keystrokes.
///
/// Event format from Grabby's research notes (MIT, https://github.com/govindup63/grabby,
/// specs/001-mouse-action-button/research.md), verified here in docs/spikes/m0-results.md §5.
final class DockSwipeBridge: @unchecked Sendable {
    static let shared = DockSwipeBridge()

    private typealias HIDEvent = UnsafeMutableRawPointer
    private typealias Create = @convention(c) (CFAllocator?, UInt32, UInt64, UInt32) -> HIDEvent?
    private typealias SetInt = @convention(c) (HIDEvent, UInt32, Int) -> Void
    private typealias SetFloat = @convention(c) (HIDEvent, UInt32, Double) -> Void
    private typealias SetFlags = @convention(c) (HIDEvent, UInt32) -> Void
    private typealias Append = @convention(c) (HIDEvent, HIDEvent, UInt32) -> Void
    private typealias Attach = @convention(c) (CGEvent, HIDEvent) -> Void

    private static let dockSwipeType: UInt32 = 23
    private static let velocityType: UInt32 = 9
    private static let motionField = (dockSwipeType << 16) | 1
    private static let progressField = (dockSwipeType << 16) | 2
    private static let flavorField = (dockSwipeType << 16) | 5
    private static let dockPrimaryFlavor = 3
    private static let gestureEventType: UInt32 = 30

    private let create: Create?
    private let setInt: SetInt?
    private let setFloat: SetFloat?
    private let setFlags: SetFlags?
    private let append: Append?
    private let attach: Attach?

    private init() {
        let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        let skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
        func resolve<T>(_ lib: UnsafeMutableRawPointer?, _ names: [String], as _: T.Type) -> T? {
            for name in names { if let p = dlsym(lib, name) { return unsafeBitCast(p, to: T.self) } }
            return nil
        }
        create = resolve(iokit, ["IOHIDEventCreate"], as: Create.self)
        setInt = resolve(iokit, ["IOHIDEventSetIntegerValue"], as: SetInt.self)
        setFloat = resolve(iokit, ["IOHIDEventSetFloatValue"], as: SetFloat.self)
        setFlags = resolve(iokit, ["IOHIDEventSetEventFlags", "_IOHIDEventSetOptions"], as: SetFlags.self)
        append = resolve(iokit, ["IOHIDEventAppendEvent"], as: Append.self)
        attach = resolve(skylight, ["SLEventSetIOHIDEvent"], as: Attach.self)
    }

    var isAvailable: Bool {
        create != nil && setInt != nil && setFloat != nil && setFlags != nil && append != nil && attach != nil
    }

    func post(motion: DockMotion, phase: DockPhase, progress: Double, velocity: Double, marker: Int64) {
        guard let create, let setInt, let setFloat, let setFlags, let append, let attach,
              let event = create(nil, Self.dockSwipeType, 0, 0) else { return }
        // IOHIDEventCreate returns a +1 reference; the CGEvent doesn't take ownership, so release it ourselves.
        defer { Self.release(event) }
        setFlags(event, phase.rawValue << 24)
        setInt(event, Self.motionField, motion.rawValue)
        setInt(event, Self.flavorField, Self.dockPrimaryFlavor)
        setFloat(event, Self.progressField, progress)
        if phase == .ended || phase == .cancelled, let v = create(nil, Self.velocityType, 0, 0) {
            setFloat(v, Self.velocityType << 16, velocity)
            setFloat(v, (Self.velocityType << 16) | 1, velocity)
            append(event, v, 0) // the parent retains its child
            Self.release(v)
        }
        guard let cg = CGEvent(source: nil), let type = CGEventType(rawValue: Self.gestureEventType) else { return }
        cg.type = type
        attach(cg, event)
        cg.setIntegerValueField(.eventSourceUserData, value: marker)
        cg.post(tap: .cgSessionEventTap)
    }

    private static func release(_ event: HIDEvent) {
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(event)).release()
    }
}
