import Combine
import OrbitSwitchCore
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @Published var value: AppSettings {
        didSet {
            persistence.save(value)
            onChange?(value)
        }
    }

    var onChange: ((AppSettings) -> Void)?
    private let persistence: SettingsPersistence

    init(persistence: SettingsPersistence = SettingsPersistence()) {
        self.persistence = persistence
        value = persistence.load()
    }

    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.value[keyPath: keyPath] },
            set: { self.value[keyPath: keyPath] = $0 }
        )
    }

    func restoreShortcutDefaults() {
        value.shortcuts = AppSettings.defaultShortcuts
    }
}
