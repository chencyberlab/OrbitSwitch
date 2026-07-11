import SwiftUI

struct PermissionsSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            if isAdHocBuild {
                Section("Development Signature") {
                    Label("Permission grants may reset after rebuilding", systemImage: "signature")
                        .foregroundStyle(.orange)
                    Text("This copy is signed ad hoc. Sign every update with the same Apple Development or Developer ID certificate to keep the macOS TCC identity stable.")
                        .foregroundStyle(.secondary)
                }
            }
            permissionRow(
                title: "Accessibility",
                allowed: appState.permissionStatus.accessibility,
                explanation: "Raises the selected window and restores minimized windows.",
                request: appState.requestAccessibility,
                open: PermissionService.openAccessibilitySettings
            )
            permissionRow(
                title: "Screen Recording",
                allowed: appState.permissionStatus.screenRecording,
                explanation: "Creates local, in-memory previews. Without it, OrbitSwitch shows titles and icons.",
                request: appState.requestScreenRecording,
                open: PermissionService.openScreenRecordingSettings
            )
            Button("Refresh Status") { appState.refreshPermissions() }
            Text("macOS may require OrbitSwitch to be restarted after a permission change. No preview, title, or usage data is transmitted or written to disk.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    private var isAdHocBuild: Bool {
        Bundle.main.object(forInfoDictionaryKey: "OrbitSwitchSigningMode") as? String != "stable-identity"
    }

    @ViewBuilder
    private func permissionRow(title: String, allowed: Bool, explanation: String, request: @escaping () -> Void, open: @escaping () -> Void) -> some View {
        Section(title) {
            Label(allowed ? "Allowed" : "Not allowed", systemImage: allowed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(allowed ? .green : .orange)
            Text(explanation)
            HStack {
                Button("Request Access", action: request).disabled(allowed)
                Button("Open System Settings", action: open)
            }
        }
    }
}
