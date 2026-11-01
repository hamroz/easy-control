import Actions
import AppKit
import QuartzCore

/// Runs the output loop once per display refresh on the main run loop (a display link keeps firing during menu
/// tracking; each frame is microseconds of event posting). Pauses itself when there is nothing to render.
@MainActor
final class OutputDriver: NSObject {
    let loop: OutputLoop
    private let inbox: OutputInbox
    private let overlay = CursorOverlay()
    private var link: CADisplayLink?
    private var fallback: Timer?
    /// Set from the pipeline: while engaged the loop keeps running even when idle.
    var engaged = false

    init(inbox: OutputInbox) {
        self.inbox = inbox
        let sink = CGEventSink()
        loop = OutputLoop(sink: sink, environment: SystemPointerEnvironment(), spaces: ControlArrowStrategy(sink: sink))
        super.init()
    }

    /// Make sure frames are flowing (cheap to call often).
    func wake() {
        if let link {
            link.isPaused = false
            return
        }
        if fallback != nil { return }
        if let screenLink = NSScreen.main?.displayLink(target: self, selector: #selector(frame(_:))) {
            screenLink.add(to: .main, forMode: .common)
            link = screenLink
        } else {
            fallback = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
    }

    /// Drain pending intents and render one frame now (also used synchronously at quit).
    func flush(at now: Double = CACurrentMediaTime()) {
        inbox.drain(into: loop)
        loop.step(at: now)
        overlay.show(loop.overlay)
    }

    @objc private func frame(_ link: CADisplayLink) {
        tick()
    }

    private func tick() {
        flush()
        guard !engaged, !loop.needsFrames else { return }
        overlay.show(.init())
        link?.isPaused = true
        fallback?.invalidate()
        fallback = nil
    }
}
