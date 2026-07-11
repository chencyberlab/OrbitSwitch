import OrbitSwitchCore
import SwiftUI

struct ShortcutSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: SettingsStore
    @State private var pending: (ShortcutAction, ShortcutDefinition)?
    @State private var message: String?
    @State private var showWarning = false

    var body: some View {
        Form {
            Section("Shortcuts") {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent(action.title) {
                        ShortcutRecorderView(shortcut: settings.value.shortcuts[action]) { shortcut in
                            apply(shortcut, action: action)
                        }
                        .frame(width: 145)
                    }
                }
            }
            Section {
                Text("Press Delete while recording to clear a shortcut. Changes apply immediately.")
                    .foregroundStyle(.secondary)
                if let message { Text(message).foregroundStyle(.red) }
                LabeledContent("Registration", value: appState.shortcutStatus)
                Button("Restore Defaults") {
                    if case .rejected(let error) = appState.restoreDefaultShortcuts() { message = error }
                    else { message = nil }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Potential Shortcut Conflict", isPresented: $showWarning) {
            Button("Cancel", role: .cancel) { pending = nil }
            Button("Try Anyway") {
                guard let pending else { return }
                switch appState.applyShortcut(pending.1, for: pending.0, allowingWarning: true) {
                case .accepted: message = nil
                case .rejected(let error): message = error
                case .warning(let warning): message = warning
                }
                self.pending = nil
            }
        } message: { Text(message ?? "This shortcut may be reserved by macOS.") }
    }

    private func apply(_ shortcut: ShortcutDefinition?, action: ShortcutAction) {
        switch appState.applyShortcut(shortcut, for: action) {
        case .accepted: message = nil
        case .warning(let warning):
            guard let shortcut else { return }
            pending = (action, shortcut)
            message = warning
            showWarning = true
        case .rejected(let error): message = error
        }
    }
}
