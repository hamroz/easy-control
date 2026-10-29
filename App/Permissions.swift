import AppKit
import ApplicationServices
@preconcurrency import AVFoundation

struct PermissionStatus: Equatable {
    var camera: AVAuthorizationStatus
    var accessibility: Bool

    var allGranted: Bool { camera == .authorized && accessibility }

    static func current() -> PermissionStatus {
        PermissionStatus(camera: AVCaptureDevice.authorizationStatus(for: .video), accessibility: AXIsProcessTrusted())
    }
}

enum Permissions {
    static func requestCamera() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    /// Shows the system prompt that offers to open Accessibility settings.
    static func promptAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openCameraSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
    }

    private static func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}
