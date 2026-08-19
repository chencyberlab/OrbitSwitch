import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Welcome to OrbitSwitch").font(.largeTitle.bold())
            Text("OrbitSwitch uses two optional macOS permissions for its complete experience. You can continue without either one and enable it later.")
                .frame(maxWidth: 500, alignment: .leading)
            GroupBox("Accessibility") {
                HStack {
                    Text("Focuses the exact window you select and enables optional Dock Peek.")
                    Spacer()
                    Button("Request") { appState.requestAccessibility() }
                        .disabled(appState.permissionStatus.accessibility)
                    Button("Open Settings") { PermissionService.openAccessibilitySettings() }
                }.padding(6)
            }
            GroupBox("Screen Recording") {
                HStack {
                    Text("Captures temporary in-memory thumbnails.")
                    Spacer()
                    Button("Request") { appState.requestScreenRecording() }
                        .disabled(appState.permissionStatus.screenRecording)
                    Button("Open Settings") { PermissionService.openScreenRecordingSettings() }
                }.padding(6)
            }
            Text("Everything stays on this Mac. OrbitSwitch never saves or transmits window previews or titles.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Continue", action: onContinue)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 590)
        .onAppear { appState.refreshPermissions() }
    }
}
