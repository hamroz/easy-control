import SwiftUI

struct MenuContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.statusText)
        Divider()
        Button(model.userPaused ? "Resume" : "Pause") { model.togglePause() }
            .keyboardShortcut("p")
        Button("Permissions…") {
            openWindow(id: WindowID.permissions)
            NSApp.activate()
        }
        Divider()
        Button("Quit EasyControl") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
