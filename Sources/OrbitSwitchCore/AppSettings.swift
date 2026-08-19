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

/// The overlay presentation the switcher uses. Both styles share one window
/// list, one selection model, and one set of shortcuts; only the arrangement
/// on screen differs.
public enum OverlayStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The perspective staircase: cards recede toward a vanishing point.
    case orbit
    /// A vertical strip of tiles docked to one edge of the active display.
    case sidebar
    public var id: String { rawValue }

    public var title: String {
        switch self { case .orbit: "Orbit" case .sidebar: "Sidebar" }
    }
}

/// Which screen edge the sidebar strip docks to. The side edges give a vertical
/// column, the top and bottom a horizontal row; everything else about the style
/// is the same.
public enum SidebarEdge: String, Codable, CaseIterable, Identifiable, Sendable {
    case left, right, top, bottom
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }

    public var axis: SidebarAxis {
        switch self {
        case .left, .right: .vertical
        case .top, .bottom: .horizontal
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let perspectiveStrengthRange = 0.0...0.002
    public static let cardSpacingRange = 24.0...110.0
    public static let animationDurationRange = 0.1...0.65
    public static let backgroundDimmingRange = 0.0...85.0
    public static let minimumWindowWidthRange = 80.0...500.0
    public static let minimumWindowHeightRange = 60.0...400.0

    public var schemaVersion = 2
    public var launchAtLogin = false
    public var showMenuBarIcon = true
    public var showDockIcon = false
    public var shortcutsPaused = false
    public var shortcuts: [ShortcutAction: ShortcutDefinition] = Self.defaultShortcuts

    public var overlayStyle = OverlayStyle.orbit
    public var sidebarEdge = SidebarEdge.left
    public var sidebarVisibleCount = 7
    public var sidebarTileWidth = 260.0

    public var perspectiveStrength = 0.00115
    public var stackAngle = 0.0
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

    /// Hovering a Dock icon shows that application's windows as a row of cards.
    /// Off by default: it needs Accessibility permission and a global mouse
    /// monitor, neither of which should start without the user asking.
    public var dockPeekEnabled = false
    public var dockPeekHoverDelay = 0.25
    public var dockPeekTileWidth = 220.0
    public var dockPeekShowControls = true
    /// Peek carries its own label switches rather than borrowing the switcher's.
    /// A peek card wants different labels: the application name is redundant on
    /// a panel you opened by pointing at that application's icon, while the
    /// window title is the whole reason you are looking.
    public var dockPeekShowAppIcon = true
    public var dockPeekShowAppName = false
    public var dockPeekShowWindowTitle = true

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
        func decode<Value: Decodable>(
            _ type: Value.Type,
            forKey key: CodingKeys,
            default defaultValue: Value
        ) -> Value {
            (try? container.decode(type, forKey: key)) ?? defaultValue
        }
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        launchAtLogin = decode(Bool.self, forKey: .launchAtLogin, default: defaults.launchAtLogin)
        showMenuBarIcon = decode(Bool.self, forKey: .showMenuBarIcon, default: defaults.showMenuBarIcon)
        showDockIcon = decode(Bool.self, forKey: .showDockIcon, default: defaults.showDockIcon)
        shortcutsPaused = decode(Bool.self, forKey: .shortcutsPaused, default: defaults.shortcutsPaused)
        shortcuts = decode([ShortcutAction: ShortcutDefinition].self, forKey: .shortcuts, default: defaults.shortcuts)
        overlayStyle = decode(OverlayStyle.self, forKey: .overlayStyle, default: defaults.overlayStyle)
        sidebarEdge = decode(SidebarEdge.self, forKey: .sidebarEdge, default: defaults.sidebarEdge)
        sidebarVisibleCount = decode(Int.self, forKey: .sidebarVisibleCount, default: defaults.sidebarVisibleCount)
        sidebarTileWidth = decode(Double.self, forKey: .sidebarTileWidth, default: defaults.sidebarTileWidth)
        perspectiveStrength = decode(Double.self, forKey: .perspectiveStrength, default: defaults.perspectiveStrength)
        stackAngle = decode(Double.self, forKey: .stackAngle, default: defaults.stackAngle)
        cardSpacing = decode(Double.self, forKey: .cardSpacing, default: defaults.cardSpacing)
        animationDuration = decode(Double.self, forKey: .animationDuration, default: defaults.animationDuration)
        thumbnailQuality = decode(ThumbnailQuality.self, forKey: .thumbnailQuality, default: defaults.thumbnailQuality)
        backgroundBlur = decode(Double.self, forKey: .backgroundBlur, default: defaults.backgroundBlur)
        showAppIcon = decode(Bool.self, forKey: .showAppIcon, default: defaults.showAppIcon)
        showAppName = decode(Bool.self, forKey: .showAppName, default: defaults.showAppName)
        showWindowTitle = decode(Bool.self, forKey: .showWindowTitle, default: defaults.showWindowTitle)
        showWindowControls = decode(Bool.self, forKey: .showWindowControls, default: defaults.showWindowControls)
        theme = decode(AppTheme.self, forKey: .theme, default: defaults.theme)
        currentSpaceOnly = decode(Bool.self, forKey: .currentSpaceOnly, default: defaults.currentSpaceOnly)
        includeMinimized = decode(Bool.self, forKey: .includeMinimized, default: defaults.includeMinimized)
        includeHiddenApps = decode(Bool.self, forKey: .includeHiddenApps, default: defaults.includeHiddenApps)
        excludedBundleIdentifiers = decode(
            [String].self,
            forKey: .excludedBundleIdentifiers,
            default: defaults.excludedBundleIdentifiers
        )
        minimumWindowWidth = decode(Double.self, forKey: .minimumWindowWidth, default: defaults.minimumWindowWidth)
        minimumWindowHeight = decode(Double.self, forKey: .minimumWindowHeight, default: defaults.minimumWindowHeight)
        groupByApplication = decode(Bool.self, forKey: .groupByApplication, default: defaults.groupByApplication)
        includeUntitled = decode(Bool.self, forKey: .includeUntitled, default: defaults.includeUntitled)
        ignoreUtilityPanels = decode(Bool.self, forKey: .ignoreUtilityPanels, default: defaults.ignoreUtilityPanels)
        dockPeekEnabled = decode(Bool.self, forKey: .dockPeekEnabled, default: defaults.dockPeekEnabled)
        dockPeekHoverDelay = decode(Double.self, forKey: .dockPeekHoverDelay, default: defaults.dockPeekHoverDelay)
        dockPeekTileWidth = decode(Double.self, forKey: .dockPeekTileWidth, default: defaults.dockPeekTileWidth)
        dockPeekShowControls = decode(Bool.self, forKey: .dockPeekShowControls, default: defaults.dockPeekShowControls)
        dockPeekShowAppIcon = decode(Bool.self, forKey: .dockPeekShowAppIcon, default: defaults.dockPeekShowAppIcon)
        dockPeekShowAppName = decode(Bool.self, forKey: .dockPeekShowAppName, default: defaults.dockPeekShowAppName)
        dockPeekShowWindowTitle = decode(
            Bool.self,
            forKey: .dockPeekShowWindowTitle,
            default: defaults.dockPeekShowWindowTitle
        )
        displayMode = decode(DisplayMode.self, forKey: .displayMode, default: defaults.displayMode)
        rememberDisplayPreference = decode(
            Bool.self,
            forKey: .rememberDisplayPreference,
            default: defaults.rememberDisplayPreference
        )
        onboardingComplete = decode(Bool.self, forKey: .onboardingComplete, default: defaults.onboardingComplete)
    }

    public static let defaultShortcuts: [ShortcutAction: ShortcutDefinition] = [
        .showNext: .init(keyCode: 48, modifiers: [.option]),
        .previous: .init(keyCode: 48, modifiers: [.option, .shift]),
        .dismiss: .init(keyCode: 53, modifiers: []),
        .appOnly: .init(keyCode: 3, modifiers: [.option]),
        .currentApp: .init(keyCode: 50, modifiers: [.option])
    ]
}

public extension AppSettings {
    /// Discovery for a mode already scoped to one application must never apply
    /// the global "group by application" preference. Doing so would collapse
    /// that application's complete window list to its first window.
    var currentApplicationDiscovery: AppSettings {
        var settings = self
        settings.groupByApplication = false
        return settings
    }

    /// The window filter Dock Peek discovers with, derived from the user's own
    /// settings.
    ///
    /// Three of them are deliberately overridden, because hovering an
    /// application's Dock icon asks a different question than the switcher does.
    /// The switcher asks "what can I switch to right now"; a Dock peek asks
    /// "what does this application have open", and the answer has to include the
    /// window minimized into the Dock, the one parked on another Desktop, and
    /// the one belonging to a hidden application — those are exactly the windows
    /// that are hardest to get back to by any other means, so leaving them out
    /// would gut the feature.
    ///
    /// Everything else is left alone. Minimum window size and the excluded
    /// bundle list are the user saying "this is not a window I want to see", and
    /// that answer does not change with how they went looking.
    var dockPeekDiscovery: AppSettings {
        var settings = currentApplicationDiscovery
        settings.currentSpaceOnly = false
        settings.includeMinimized = true
        settings.includeHiddenApps = true
        return settings
    }
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
        let defaults = AppSettings()
        func normalized(
            _ value: Double,
            range: ClosedRange<Double>,
            fallback: Double
        ) -> Double {
            guard value.isFinite else { return fallback }
            return min(range.upperBound, max(range.lowerBound, value))
        }
        func replace(_ keyPath: WritableKeyPath<AppSettings, Double>, range: ClosedRange<Double>) {
            let value = normalized(
                settings[keyPath: keyPath],
                range: range,
                fallback: defaults[keyPath: keyPath]
            )
            guard value != settings[keyPath: keyPath] else { return }
            settings[keyPath: keyPath] = value
            changed = true
        }
        if !settings.showMenuBarIcon && !settings.showDockIcon {
            settings.showMenuBarIcon = true
            changed = true
        }
        for action in ShortcutAction.allCases {
            guard let shortcut = settings.shortcuts[action] else { continue }
            let isValid = action == .dismiss
                ? shortcut.hasOnlySupportedModifiers
                : shortcut.isSuitableForGlobalRegistration
            if !isValid {
                settings.shortcuts[action] = nil
                changed = true
            }
        }
        let visibleCount = SidebarLayout.clampedVisibleCount(settings.sidebarVisibleCount)
        if visibleCount != settings.sidebarVisibleCount {
            settings.sidebarVisibleCount = visibleCount
            changed = true
        }
        let tileWidth = SidebarLayout.clampedTileWidth(settings.sidebarTileWidth)
        if tileWidth != settings.sidebarTileWidth {
            settings.sidebarTileWidth = tileWidth
            changed = true
        }
        let stackAngle = Flip3DLayout.clampedStackAngle(settings.stackAngle)
        if stackAngle != settings.stackAngle {
            settings.stackAngle = stackAngle
            changed = true
        }
        let hoverDelay = DockPeekLayout.clampedHoverDelay(settings.dockPeekHoverDelay)
        if hoverDelay != settings.dockPeekHoverDelay {
            settings.dockPeekHoverDelay = hoverDelay
            changed = true
        }
        let peekTileWidth = DockPeekLayout.clampedTileWidth(settings.dockPeekTileWidth)
        if peekTileWidth != settings.dockPeekTileWidth {
            settings.dockPeekTileWidth = peekTileWidth
            changed = true
        }
        replace(\.perspectiveStrength, range: AppSettings.perspectiveStrengthRange)
        replace(\.cardSpacing, range: AppSettings.cardSpacingRange)
        replace(\.animationDuration, range: AppSettings.animationDurationRange)
        replace(\.backgroundBlur, range: AppSettings.backgroundDimmingRange)
        replace(\.minimumWindowWidth, range: AppSettings.minimumWindowWidthRange)
        replace(\.minimumWindowHeight, range: AppSettings.minimumWindowHeightRange)

        var seenBundleIdentifiers = Set<String>()
        let normalizedBundleIdentifiers = settings.excludedBundleIdentifiers.compactMap { raw -> String? in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seenBundleIdentifiers.insert(value).inserted else { return nil }
            return value
        }
        if normalizedBundleIdentifiers != settings.excludedBundleIdentifiers {
            settings.excludedBundleIdentifiers = normalizedBundleIdentifiers
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
