import Foundation

public enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    public var id: String { rawValue }
}

public enum DisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case active, pointer, all
    public var id: String { rawValue }
}

public enum ThumbnailQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case low, medium, high
    public var id: String { rawValue }
    public var maximumWidth: Int {
        switch self { case .low: 480; case .medium: 720; case .high: 960 }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var schemaVersion = 2
    public var launchAtLogin = false
    public var showMenuBarIcon = true
    public var showDockIcon = false
    public var shortcutsPaused = false
    public var shortcuts: [ShortcutAction: ShortcutDefinition] = Self.defaultShortcuts

    public var perspectiveStrength = 0.00115
    public var stackAngle = 13.0
    public var cardSpacing = 66.0
    public var animationDuration = 0.28
    public var thumbnailQuality = ThumbnailQuality.medium
    public var backgroundBlur = 58.0
    public var showAppIcon = true
    public var showAppName = true
    public var showWindowTitle = true
    public var theme = AppTheme.system

    public var currentSpaceOnly = true
    public var includeMinimized = true
    public var includeHiddenApps = false
    public var excludedBundleIdentifiers: [String] = []
    public var minimumWindowWidth = 180.0
    public var minimumWindowHeight = 120.0
    public var groupByApplication = false
    public var includeUntitled = true
    public var ignoreUtilityPanels = true

    public var displayMode = DisplayMode.pointer
    public var rememberDisplayPreference = true
    public var onboardingComplete = false

    public init() {}

    public static let defaultShortcuts: [ShortcutAction: ShortcutDefinition] = [
        .showNext: .init(keyCode: 48, modifiers: [.option]),
        .previous: .init(keyCode: 48, modifiers: [.option, .shift]),
        .dismiss: .init(keyCode: 53, modifiers: []),
        .appOnly: .init(keyCode: 3, modifiers: [.option]),
        .currentApp: .init(keyCode: 50, modifiers: [.option])
    ]
}

public final class SettingsPersistence {
    private let defaults: UserDefaults
    private let key = "appSettings.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: key) else { return AppSettings() }
        if var settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            var shouldSave = false
            if settings.schemaVersion < 2 {
                settings.schemaVersion = 2
                settings.includeMinimized = true
                settings.backgroundBlur = min(85, max(0, settings.backgroundBlur * 2.4))
                shouldSave = true
            }
            if normalizePersistedInvariants(&settings) { shouldSave = true }
            if shouldSave { save(settings) }
            if !settings.rememberDisplayPreference { settings.displayMode = .pointer }
            return settings
        }
        if let legacy = try? JSONDecoder().decode(LegacySettings.self, from: data) {
            var migrated = AppSettings()
            if let shortcuts = legacy.shortcuts {
                for (name, shortcut) in shortcuts {
                    if let action = ShortcutAction(rawValue: name) { migrated.shortcuts[action] = shortcut }
                }
            }
            if let showDockIcon = legacy.showDockIcon { migrated.showDockIcon = showDockIcon }
            if let showMenuBarIcon = legacy.showMenuBarIcon { migrated.showMenuBarIcon = showMenuBarIcon }
            _ = normalizePersistedInvariants(&migrated)
            save(migrated)
            return migrated
        }
        return AppSettings()
    }

    public func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }

    private func normalizePersistedInvariants(_ settings: inout AppSettings) -> Bool {
        var changed = false
        if !settings.showMenuBarIcon && !settings.showDockIcon {
            settings.showMenuBarIcon = true
            changed = true
        }
        for action in ShortcutAction.allCases where action != .dismiss {
            guard let shortcut = settings.shortcuts[action], !shortcut.isSuitableForGlobalRegistration else { continue }
            settings.shortcuts[action] = nil
            changed = true
        }
        return changed
    }

    private struct LegacySettings: Codable {
        var shortcuts: [String: ShortcutDefinition]?
        var showDockIcon: Bool?
        var showMenuBarIcon: Bool?
    }
}
