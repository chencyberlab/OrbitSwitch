import Combine
import OrbitSwitchCore
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @Published var value: AppSettings {
        didSet {
            // SwiftUI bindings write on every slider tick, including the ones
            // that land on the value already stored. Skipping those keeps the
            // encode-and-persist work proportional to real changes.
            guard value != oldValue else { return }
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
}
