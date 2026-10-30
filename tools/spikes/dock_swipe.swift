// SPIKE — THROWAWAY. Can we drive the Dock's Spaces swipe with a synthetic Dock Swipe IOHIDEvent on macOS 27?
// Recipe from Grabby's research notes (MIT, github.com/govindup63/grabby, specs/001-mouse-action-button/research.md).
import CoreGraphics
import Foundation

typealias HIDEventRef = UnsafeMutableRawPointer
typealias CreateFn = @convention(c) (CFAllocator?, UInt32, UInt64, UInt32) -> HIDEventRef?
typealias SetIntFn = @convention(c) (HIDEventRef, UInt32, Int) -> Void
typealias SetFloatFn = @convention(c) (HIDEventRef, UInt32, Double) -> Void
typealias SetOptionsFn = @convention(c) (HIDEventRef, UInt32) -> Void
typealias AppendFn = @convention(c) (HIDEventRef, HIDEventRef, UInt32) -> Void
typealias SLSetFn = @convention(c) (CGEvent, HIDEventRef) -> Void
typealias MainConnFn = @convention(c) () -> Int32
typealias ActiveSpaceFn = @convention(c) (Int32) -> UInt64

let h = dlopen(nil, RTLD_NOW)
let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
func sym<T>(_ lib: UnsafeMutableRawPointer?, _ name: String, _: T.Type) -> T? {
    guard let p = dlsym(lib, name) else { print("missing \(name)"); return nil }
    return unsafeBitCast(p, to: T.self)
}
guard let create = sym(iokit, "IOHIDEventCreate", CreateFn.self),
      let setInt = sym(iokit, "IOHIDEventSetIntegerValue", SetIntFn.self),
      let setFloat = sym(iokit, "IOHIDEventSetFloatValue", SetFloatFn.self),
      let setOptions = sym(iokit, "IOHIDEventSetEventFlags", SetOptionsFn.self) ?? sym(iokit, "_IOHIDEventSetOptions", SetOptionsFn.self),
      let append = sym(iokit, "IOHIDEventAppendEvent", AppendFn.self),
      let slSet = sym(sky, "SLEventSetIOHIDEvent", SLSetFn.self),
      let mainConn = sym(h, "CGSMainConnectionID", MainConnFn.self),
      let activeSpace = sym(h, "CGSGetActiveSpace", ActiveSpaceFn.self) else { exit(1) }

let dockSwipe: UInt32 = 23, velocity: UInt32 = 9
let fMotion = (dockSwipe << 16) | 1, fProgress = (dockSwipe << 16) | 2, fFlavor = (dockSwipe << 16) | 5
func post(phase: UInt32, progress: Double, flavor: Int, lastDelta: Double) {
    guard let ev = create(nil, dockSwipe, 0, 0) else { return }
    setOptions(ev, phase << 24)
    setInt(ev, fMotion, 1) // horizontal
    setInt(ev, fFlavor, flavor)
    setFloat(ev, fProgress, progress)
    if phase == 4, let v = create(nil, velocity, 0, 0) {
        setFloat(v, (velocity << 16) | 0, lastDelta * 100)
        setFloat(v, (velocity << 16) | 1, lastDelta * 100)
        append(ev, v, 0)
    }
    guard let cg = CGEvent(source: nil) else { return }
    cg.type = CGEventType(rawValue: 30)!
    slSet(cg, ev)
    cg.setIntegerValueField(.eventSourceUserData, value: 0x4543_0001)
    cg.post(tap: .cgSessionEventTap)
}
func swipe(sign: Double, flavor: Int) {
    post(phase: 1, progress: 0, flavor: flavor, lastDelta: 0)
    var p = 0.0
    for _ in 0..<30 { p += sign * 0.04; Thread.sleep(forTimeInterval: 1.0 / 60); post(phase: 2, progress: p, flavor: flavor, lastDelta: sign * 0.04) }
    post(phase: 4, progress: p, flavor: flavor, lastDelta: sign * 0.04)
    Thread.sleep(forTimeInterval: 1.0)
}
let start = activeSpace(mainConn())
print("start space \(start)")
for flavor in [3, 1] {
    for sign in [1.0, -1.0] {
        let before = activeSpace(mainConn())
        swipe(sign: sign, flavor: flavor)
        let after = activeSpace(mainConn())
        print("flavor \(flavor) sign \(sign > 0 ? "+" : "-"): \(before) -> \(after) \(before != after ? "SWITCHED" : "")")
    }
}
print("final \(activeSpace(mainConn())) (start \(start))")
