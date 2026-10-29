import AVFoundation
import SwiftUI

struct PermissionsView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("EasyControl needs two permissions")
                .font(.title2.bold())
            Text("Everything runs on this Mac. Camera frames are never saved or sent anywhere.")
                .foregroundStyle(.secondary)

            row(
                title: "Camera",
                detail: "To see your hand.",
                granted: model.permissions.camera == .authorized
            ) {
                if model.permissions.camera == .notDetermined {
                    Button("Allow Camera") { model.requestCamera() }
                } else {
                    Button("Open Camera Settings") { Permissions.openCameraSettings() }
                }
            }

            row(
                title: "Accessibility",
                detail: "To scroll and switch Spaces for you. Turn on EasyControl in the list.",
                granted: model.permissions.accessibility
            ) {
                Button("Open Accessibility Settings") {
                    Permissions.promptAccessibility()
                    Permissions.openAccessibilitySettings()
                }
            }

            if model.permissions.allGranted {
                Label("All set. Raise an open palm toward the camera to start.", systemImage: "hand.raised.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func row(title: String, detail: String, granted: Bool, @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.title2)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
                if !granted { action() }
            }
        }
    }
}
