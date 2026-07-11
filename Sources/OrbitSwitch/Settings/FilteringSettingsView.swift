import SwiftUI

struct FilteringSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Toggle("Current Space only", isOn: settings.binding(\.currentSpaceOnly))
            Toggle("Include minimized windows", isOn: settings.binding(\.includeMinimized))
            Text("Minimized-window discovery requires Accessibility permission. Unknown off-screen windows are excluded.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Include hidden apps", isOn: settings.binding(\.includeHiddenApps))
            Toggle("Group windows by application", isOn: settings.binding(\.groupByApplication))
            Toggle("Include untitled windows", isOn: settings.binding(\.includeUntitled))
            Toggle("Ignore transient utility panels", isOn: settings.binding(\.ignoreUtilityPanels))
            LabeledContent("Minimum window width") {
                HStack {
                    Slider(value: settings.binding(\.minimumWindowWidth), in: 80...500).frame(width: 250)
                    Text("\(settings.value.minimumWindowWidth, specifier: "%.0f") pt").monospacedDigit()
                }
            }
            LabeledContent("Minimum window height") {
                HStack {
                    Slider(value: settings.binding(\.minimumWindowHeight), in: 60...400).frame(width: 250)
                    Text("\(settings.value.minimumWindowHeight, specifier: "%.0f") pt").monospacedDigit()
                }
            }
            TextField("Excluded bundle identifiers (comma separated)", text: excludedAppsBinding)
                .textFieldStyle(.roundedBorder)
            Text("Example: com.example.privateapp. OrbitSwitch stores this list only on this Mac.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    private var excludedAppsBinding: Binding<String> {
        Binding(
            get: { settings.value.excludedBundleIdentifiers.joined(separator: ", ") },
            set: { value in
                settings.value.excludedBundleIdentifiers = value.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}
