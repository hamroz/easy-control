import ApplicationServices
import Foundation
import Testing
@testable import Actions

// Event taps need the Accessibility permission; CI runners don't have it.
@Suite(.enabled(if: AXIsProcessTrusted()), .serialized)
struct InputActivityMonitorTests {
    @Test func concurrentStartsCreateOneTap() {
        let monitor = InputActivityMonitor()
        DispatchQueue.concurrentPerform(iterations: 8) { _ in monitor.start() }
        #expect(monitor.tapsCreated == 1)
        #expect(monitor.isRunning)
        monitor.stop()
    }

    @Test func startRecreatesInvalidatedTap() {
        let monitor = InputActivityMonitor()
        #expect(monitor.start())
        monitor.invalidateTapForTesting() // what revoking Accessibility does to a live tap
        #expect(!monitor.isRunning)
        #expect(monitor.start())
        #expect(monitor.isRunning)
        #expect(monitor.tapsCreated == 2)
        monitor.stop()
    }
}
