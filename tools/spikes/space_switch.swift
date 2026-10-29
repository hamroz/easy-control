// M0 SPIKE — THROWAWAY. Finds which synthetic Ctrl+Arrow variant switches Spaces on this macOS.
// Build: swiftc -O tools/spikes/space_switch.swift -o /tmp/space_switch
import CoreGraphics
import Foundation

typealias MainConnFn = @convention(c) () -> Int32
typealias ActiveSpaceFn = @convention(c) (Int32) -> UInt64
let handle = dlopen(nil, RTLD_NOW)
let mainConn = unsafeBitCast(dlsym(handle, "CGSMainConnectionID"), to: MainConnFn.self)
let activeSpace = unsafeBitCast(dlsym(handle, "CGSGetActiveSpace"), to: ActiveSpaceFn.self)
func currentSpace() -> UInt64 { activeSpace(mainConn()) }

let source = CGEventSource(stateID: .hidSystemState)
func press(_ key: CGKeyCode, flags: CGEventFlags) {
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)!
        e.flags = flags
        e.setIntegerValueField(.eventSourceUserData, value: 0x4543_0001)
        e.post(tap: .cghidEventTap)
    }
}

let variants: [(String, CGEventFlags)] = [
    ("ctrl", [.maskControl]),
    ("ctrl+fn+numpad", [.maskControl, .maskSecondaryFn, .maskNumericPad]),
]
let initial = currentSpace()
print("initial space id: \(initial)")
print("variant | direction | before | after | switched")
for (name, flags) in variants {
    for (first, back, label) in [(CGKeyCode(124), CGKeyCode(123), "right"), (CGKeyCode(123), CGKeyCode(124), "left")] {
        let before = currentSpace()
        press(first, flags: flags)
        Thread.sleep(forTimeInterval: 1.2)
        let after = currentSpace()
        let switched = after != before
        print("\(name) | \(label) | \(before) | \(after) | \(switched)")
        if switched {
            press(back, flags: flags)
            Thread.sleep(forTimeInterval: 1.2)
            break
        }
    }
}
// Restore the user's original Space if anything drifted.
for (key, _) in [(CGKeyCode(123), 0), (CGKeyCode(124), 0)] where currentSpace() != initial {
    press(key, flags: [.maskControl, .maskSecondaryFn, .maskNumericPad])
    Thread.sleep(forTimeInterval: 1.2)
}
print("final space id: \(currentSpace()) restored=\(currentSpace() == initial)")
