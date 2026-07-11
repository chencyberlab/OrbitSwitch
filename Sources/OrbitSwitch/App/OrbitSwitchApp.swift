import SwiftUI

@main
struct OrbitSwitchApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra(
            L10n.appName,
            systemImage: "square.stack.3d.up",
            isInserted: appState.settings.binding(\.showMenuBarIcon)
        ) {
            MenuBarContent()
                .environmentObject(appState)
                .environmentObject(appState.settings)
        }

        Settings {
            SettingsRootView()
                .environmentObject(appState)
                .environmentObject(appState.settings)
        }
    }
}
