// ec-probe: drives the real Actions layer from the command line for live QA.
import Actions
import CoreGraphics
import Foundation
import GestureEngine
import QuartzCore

let sink = CGEventSink()
let args = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print("""
    usage: ec-probe space left|right
           ec-probe mission-control | app-expose
           ec-probe scroll-demo [down|up]
           ec-probe dock-swipe left|right|up|down   (simulated three-finger hand drag)
           ec-probe monitor <seconds>
           ec-probe monitor-selftest
    """)
    exit(2)
}

func dockWindowCount() -> Int {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return info.filter { ($0[kCGWindowOwnerName as String] as? String) == "Dock" }.count
}

switch args.first {
case "space":
    guard let d = args.dropFirst().first.flatMap(Direction.init(rawValue:)) else { usage() }
    ControlArrowStrategy(sink: sink).switchSpace(d)
    Thread.sleep(forTimeInterval: 0.3) // events posted right before exit can be dropped
    print("posted Ctrl+\(d.rawValue) with Fn+NumPad flags")

case "mission-control", "app-expose":
    let before = dockWindowCount()
    let dispatcher = ActionDispatcher(sink: sink, spaces: ControlArrowStrategy(sink: sink), scroll: ScrollInjector(sink: sink))
    dispatcher.handle([.discrete(args[0] == "mission-control" ? .swipeUp : .swipeDown)], at: CACurrentMediaTime())
    Thread.sleep(forTimeInterval: 1.0)
    print("posted; on-screen Dock windows before \(before), after \(dockWindowCount())")

case "scroll-demo":
    let sign: Float = args.dropFirst().first == "up" ? -1 : 1
    let scroll = ScrollInjector(sink: sink)
    var t = CACurrentMediaTime()
    scroll.handle(phase: .began, delta: .zero, at: t)
    for _ in 0..<15 { // 400 px over 0.5 s at 30 fps
        Thread.sleep(forTimeInterval: 1.0 / 30)
        t = CACurrentMediaTime()
        scroll.handle(phase: .changed, delta: [0, sign * 400 / 1800 / 15], at: t)
    }
    scroll.handle(phase: .ended, delta: .zero, at: t)
    var ticks = 0
    while scroll.isMomentumActive {
        Thread.sleep(forTimeInterval: 1.0 / 60)
        scroll.tick(at: CACurrentMediaTime())
        ticks += 1
    }
    print("scrolled 400 px with \(ticks) momentum ticks")

case "dock-swipe":
    guard let d = args.dropFirst().first.flatMap(Direction.init(rawValue:)) else { usage() }
    print("private Dock swipe available: \(sink.supportsDockSwipe)")
    let injector = DockSwipeInjector(sink: sink, spaces: ControlArrowStrategy(sink: sink))
    let id: GestureID = d == .left || d == .right ? .dockSwipeHorizontal : .dockSwipeVertical
    // Hand travel of 0.3 frame heights over 0.4 s: right/up are positive x / negative y in our coordinates.
    let step: SIMD2<Float> = switch d {
    case .right: [0.025, 0]
    case .left: [-0.025, 0]
    case .up: [0, -0.025]
    case .down: [0, 0.025]
    }
    var t = CACurrentMediaTime()
    injector.handle(id, phase: .began, delta: step, at: t)
    for _ in 0..<11 {
        Thread.sleep(forTimeInterval: 1.0 / 30)
        t = CACurrentMediaTime()
        injector.handle(id, phase: .changed, delta: step, at: t)
    }
    injector.handle(id, phase: .ended, delta: .zero, at: t)
    while injector.needsTicks {
        Thread.sleep(forTimeInterval: 0.05)
        injector.tick(at: CACurrentMediaTime())
    }
    Thread.sleep(forTimeInterval: 0.5)
    print("posted a \(d.rawValue) hand drag")

case "monitor":
    let seconds = Double(args.dropFirst().first ?? "5") ?? 5
    let monitor = InputActivityMonitor()
    guard monitor.start() else { print("event tap failed: grant Accessibility"); exit(1) }
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        Thread.sleep(forTimeInterval: 0.5)
        let ago = monitor.lastUserInput.map { String(format: "%.2fs ago", CACurrentMediaTime() - $0) } ?? "none"
        print("last real input: \(ago)")
    }

case "monitor-selftest":
    let monitor = InputActivityMonitor()
    guard monitor.start() else { print("event tap failed: grant Accessibility"); exit(1) }
    Thread.sleep(forTimeInterval: 0.3)
    let baseline = monitor.lastUserInput
    sink.post(.scroll(dx: 0, dy: 0, phase: .none, momentum: .none)) // marked: must be ignored
    Thread.sleep(forTimeInterval: 0.3)
    let afterMarked = monitor.lastUserInput
    let unmarked = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0)!
    unmarked.post(tap: .cghidEventTap) // unmarked: must be seen
    Thread.sleep(forTimeInterval: 0.3)
    let afterUnmarked = monitor.lastUserInput
    let ignoredOwn = afterMarked == baseline
    let sawOther = afterUnmarked != nil && afterUnmarked != afterMarked
    print("ignored own event: \(ignoredOwn), saw unmarked event: \(sawOther)")
    exit(ignoredOwn && sawOther ? 0 : 1)

default:
    usage()
}
