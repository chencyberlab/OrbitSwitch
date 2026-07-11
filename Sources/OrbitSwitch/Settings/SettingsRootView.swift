import SwiftUI

struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettingsView().tabItem { Label("General", systemImage: "gear") }
            ShortcutSettingsView().tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AppearanceSettingsView().tabItem { Label("Appearance", systemImage: "paintbrush") }
            FilteringSettingsView().tabItem { Label("Windows", systemImage: "macwindow.on.rectangle") }
            DisplaySettingsView().tabItem { Label("Displays", systemImage: "display.2") }
            PermissionsSettingsView().tabItem { Label("Permissions", systemImage: "hand.raised") }
        }
        .frame(width: 720, height: 540)
        .padding()
    }
}
