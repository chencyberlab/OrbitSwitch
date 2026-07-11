import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Group {
            Button("Open Switcher") { appState.openSwitcher() }
                .keyboardShortcut("o")
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",")
            Divider()
            Label(
                appState.permissionStatus.accessibility ? "Accessibility: Allowed" : "Accessibility: Required",
                systemImage: appState.permissionStatus.accessibility ? "checkmark.circle" : "exclamationmark.triangle"
            )
            Label(
                appState.permissionStatus.screenRecording ? "Screen Recording: Allowed" : "Screen Recording: Preview fallback",
                systemImage: appState.permissionStatus.screenRecording ? "checkmark.circle" : "rectangle.dashed"
            )
            Button(settings.value.shortcutsPaused ? "Resume Shortcuts" : "Pause Shortcuts") {
                appState.toggleShortcutPause()
            }
            Divider()
            Button("About OrbitSwitch") { NSApp.orderFrontStandardAboutPanel(nil) }
            Button("Quit OrbitSwitch") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .onAppear { appState.start() }
    }
}
