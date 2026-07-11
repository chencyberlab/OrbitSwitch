import OrbitSwitchCore
import SwiftUI

struct DisplaySettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Picker("Show overlay on", selection: settings.binding(\.displayMode)) {
                Text("Active display").tag(DisplayMode.active)
                Text("Display containing pointer").tag(DisplayMode.pointer)
                Text("All displays").tag(DisplayMode.all)
            }
            .pickerStyle(.radioGroup)
            Toggle("Remember display preference", isOn: settings.binding(\.rememberDisplayPreference))
            Text("All Displays mirrors the current stack on each connected display. Display changes are picked up the next time the switcher opens.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}
