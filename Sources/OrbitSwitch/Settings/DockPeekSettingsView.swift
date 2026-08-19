import OrbitSwitchCore
import SwiftUI

struct DockPeekSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Dock Peek") {
                Toggle(isOn: settings.binding(\.dockPeekEnabled)) {
                    Text("Preview windows on Dock hover")
                    Text("Resting the pointer on a running app's icon in the Dock shows every window that app has in a compact preview panel. Click one to bring it forward.")
                }
                if !appState.permissionStatus.accessibility {
                    Label("Accessibility permission required", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Dock Peek asks the Dock which icon the pointer is over, which macOS allows only with Accessibility permission. It starts as soon as access is allowed.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Request Access") { appState.requestAccessibility() }
                        Button("Open System Settings") { PermissionService.openAccessibilitySettings() }
                    }
                }
            }
            Section("Size and Timing") {
                LabeledContent("Hover delay") {
                    HStack {
                        Slider(
                            value: settings.binding(\.dockPeekHoverDelay),
                            in: DockPeekLayout.hoverDelayRange
                        )
                        .frame(width: 250)
                        Text("\(settings.value.dockPeekHoverDelay, specifier: "%.2f") s")
                            .monospacedDigit()
                            .frame(width: 72, alignment: .trailing)
                    }
                }
                LabeledContent("Preview size") {
                    HStack {
                        Slider(
                            value: settings.binding(\.dockPeekTileWidth),
                            in: DockPeekLayout.tileWidthRange,
                            step: 1
                        )
                        .frame(width: 250)
                        Text("\(Int(settings.value.dockPeekTileWidth.rounded())) pt")
                            .monospacedDigit()
                            .frame(width: 72, alignment: .trailing)
                    }
                }
                Text("Previews shrink from this size when an app has more windows than fit across the display, then wrap into a grid of up to three visible rows. Longer lists scroll.")
                    .foregroundStyle(.secondary)
            }
            .disabled(!settings.value.dockPeekEnabled)
            Section("Labels") {
                Toggle("Show app icon", isOn: settings.binding(\.dockPeekShowAppIcon))
                Toggle("Show app name", isOn: settings.binding(\.dockPeekShowAppName))
                Toggle("Show window title", isOn: settings.binding(\.dockPeekShowWindowTitle))
                Toggle(isOn: settings.binding(\.dockPeekShowControls)) {
                    Text("Show window controls")
                    Text("Close, minimize, and zoom buttons appear on whichever preview the pointer is over.")
                }
                Text("These apply to Dock Peek only; the switcher keeps its own labels under Appearance. Turning every label off gives the space back to the preview image.")
                    .foregroundStyle(.secondary)
            }
            .disabled(!settings.value.dockPeekEnabled)
            Text("Dock Peek shows every window of the hovered app, including windows on other Desktops — Current Space only does not apply here. The minimum window size and excluded bundle identifiers under Windows still do, so filtered-out windows stay filtered out. Previews use Screen Recording permission when it is granted and fall back to titles and icons when it is not.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}
