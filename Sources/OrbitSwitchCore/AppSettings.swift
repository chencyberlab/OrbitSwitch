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
    public var showWindowControls = true
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

    /// Tolerant decoding: only schemaVersion is required, so persisted settings
    /// survive new fields being added. Payloads without schemaVersion still fall
    /// through to the LegacySettings migration path in SettingsPersistence.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? defaults.showMenuBarIcon
        showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? defaults.showDockIcon
        shortcutsPaused = try container.decodeIfPresent(Bool.self, forKey: .shortcutsPaused) ?? defaults.shortcutsPaused
        shortcuts = try container.decodeIfPresent([ShortcutAction: ShortcutDefinition].self, forKey: .shortcuts) ?? defaults.shortcuts
        perspectiveStrength = try container.decodeIfPresent(Double.self, forKey: .perspectiveStrength) ?? defaults.perspectiveStrength
        stackAngle = try container.decodeIfPresent(Double.self, forKey: .stackAngle) ?? defaults.stackAngle
        cardSpacing = try container.decodeIfPresent(Double.self, forKey: .cardSpacing) ?? defaults.cardSpacing
        animationDuration = try container.decodeIfPresent(Double.self, forKey: .animationDuration) ?? defaults.animationDuration
        thumbnailQuality = try container.decodeIfPresent(ThumbnailQuality.self, forKey: .thumbnailQuality) ?? defaults.thumbnailQuality
        backgroundBlur = try container.decodeIfPresent(Double.self, forKey: .backgroundBlur) ?? defaults.backgroundBlur
        showAppIcon = try container.decodeIfPresent(Bool.self, forKey: .showAppIcon) ?? defaults.showAppIcon
        showAppName = try container.decodeIfPresent(Bool.self, forKey: .showAppName) ?? defaults.showAppName
        showWindowTitle = try container.decodeIfPresent(Bool.self, forKey: .showWindowTitle) ?? defaults.showWindowTitle
        showWindowControls = try container.decodeIfPresent(Bool.self, forKey: .showWindowControls) ?? defaults.showWindowControls
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? defaults.theme
        currentSpaceOnly = try container.decodeIfPresent(Bool.self, forKey: .currentSpaceOnly) ?? defaults.currentSpaceOnly
        includeMinimized = try container.decodeIfPresent(Bool.self, forKey: .includeMinimized) ?? defaults.includeMinimized
        includeHiddenApps = try container.decodeIfPresent(Bool.self, forKey: .includeHiddenApps) ?? defaults.includeHiddenApps
        excludedBundleIdentifiers = try container.decodeIfPresent([String].self, forKey: .excludedBundleIdentifiers) ?? defaults.excludedBundleIdentifiers
        minimumWindowWidth = try container.decodeIfPresent(Double.self, forKey: .minimumWindowWidth) ?? defaults.minimumWindowWidth
        minimumWindowHeight = try container.decodeIfPresent(Double.self, forKey: .minimumWindowHeight) ?? defaults.minimumWindowHeight
        groupByApplication = try container.decodeIfPresent(Bool.self, forKey: .groupByApplication) ?? defaults.groupByApplication
        includeUntitled = try container.decodeIfPresent(Bool.self, forKey: .includeUntitled) ?? defaults.includeUntitled
        ignoreUtilityPanels = try container.decodeIfPresent(Bool.self, forKey: .ignoreUtilityPanels) ?? defaults.ignoreUtilityPanels
        displayMode = try container.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? defaults.displayMode
        rememberDisplayPreference = try container.decodeIfPresent(Bool.self, forKey: .rememberDisplayPreference) ?? defaults.rememberDisplayPreference
        onboardingComplete = try container.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? defaults.onboardingComplete
    }

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
