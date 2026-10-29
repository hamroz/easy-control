import SwiftUI

@main
struct EasyControlApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.menuBarSymbol)
        }

        Window("EasyControl Permissions", id: WindowID.permissions) {
            PermissionsView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(PermissionStatus.current().allGranted ? .suppressed : .presented)
    }
}

enum WindowID {
    static let permissions = "permissions"
    static let debug = "debug"
}
