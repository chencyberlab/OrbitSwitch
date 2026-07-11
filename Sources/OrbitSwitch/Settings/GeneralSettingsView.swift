import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: settings.binding(\.launchAtLogin))
            Toggle("Show menu bar icon", isOn: settings.binding(\.showMenuBarIcon))
                .disabled(!settings.value.showDockIcon)
            Toggle("Show Dock icon", isOn: settings.binding(\.showDockIcon))
                .disabled(!settings.value.showMenuBarIcon)
            Text("Keep at least one app entry visible so Settings remains accessible.")
                .font(.callout)
                .foregroundStyle(.secondary)
            LabeledContent("Start at login status", value: launchStatus)
            LabeledContent("Updates", value: "Manual in version 1.0")
            Button("Show Onboarding") {
                settings.value.onboardingComplete = false
                appState.showOnboarding()
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var launchStatus: String {
        switch SMAppService.mainApp.status {
        case .enabled: "Enabled"
        case .requiresApproval: "Requires approval"
        case .notFound: "Unavailable in this build"
        default: "Disabled"
        }
    }
}
