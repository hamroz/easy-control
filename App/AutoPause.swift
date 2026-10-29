import AppKit

/// Pauses tracking (and the camera) while the screen is locked, the displays sleep, or the Mac sleeps.
@MainActor
final class AutoPause {
    private var reasons = Set<String>()
    private let onChange: @MainActor (Bool) -> Void
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    init(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        watch(distributed, "com.apple.screenIsLocked", reason: "locked", active: true)
        watch(distributed, "com.apple.screenIsUnlocked", reason: "locked", active: false)
        watch(workspace, NSWorkspace.screensDidSleepNotification.rawValue, reason: "displaySleep", active: true)
        watch(workspace, NSWorkspace.screensDidWakeNotification.rawValue, reason: "displaySleep", active: false)
        watch(workspace, NSWorkspace.willSleepNotification.rawValue, reason: "sleep", active: true)
        watch(workspace, NSWorkspace.didWakeNotification.rawValue, reason: "sleep", active: false)
    }

    var isPaused: Bool { !reasons.isEmpty }

    private func watch(_ center: NotificationCenter, _ name: String, reason: String, active: Bool) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.set(reason, active: active) }
        }
        tokens.append((center, token))
    }

    private func set(_ reason: String, active: Bool) {
        let before = isPaused
        if active { reasons.insert(reason) } else { reasons.remove(reason) }
        if isPaused != before { onChange(isPaused) }
    }
}
