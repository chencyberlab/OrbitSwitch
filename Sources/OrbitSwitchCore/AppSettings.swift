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
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? defaults.showMenuBarIcon
        showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? defaults.showDockIcon
        shortcutsPaused = try container.decodeIfPresent(Bool.self, forKey: .shortcutsPaused) ?? defaults.shortcutsPaused
        shortcuts = try container.decodeIfPresent([ShortcutAction: ShortcutDefinition].self, forKey: .shortcuts) ?? defaults.shortcuts
        overlayStyle = try container.decodeIfPresent(OverlayStyle.self, forKey: .overlayStyle) ?? defaults.overlayStyle
        sidebarEdge = try container.decodeIfPresent(SidebarEdge.self, forKey: .sidebarEdge) ?? defaults.sidebarEdge
        sidebarVisibleCount = try container.decodeIfPresent(Int.self, forKey: .sidebarVisibleCount) ?? defaults.sidebarVisibleCount
        sidebarTileWidth = try container.decodeIfPresent(Double.self, forKey: .sidebarTileWidth) ?? defaults.sidebarTileWidth
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
        dockPeekEnabled = try container.decodeIfPresent(Bool.self, forKey: .dockPeekEnabled) ?? defaults.dockPeekEnabled
        dockPeekHoverDelay = try container.decodeIfPresent(Double.self, forKey: .dockPeekHoverDelay) ?? defaults.dockPeekHoverDelay
        dockPeekTileWidth = try container.decodeIfPresent(Double.self, forKey: .dockPeekTileWidth) ?? defaults.dockPeekTileWidth
        dockPeekShowControls = try container.decodeIfPresent(Bool.self, forKey: .dockPeekShowControls) ?? defaults.dockPeekShowControls
        dockPeekShowAppIcon = try container.decodeIfPresent(Bool.self, forKey: .dockPeekShowAppIcon) ?? defaults.dockPeekShowAppIcon
        dockPeekShowAppName = try container.decodeIfPresent(Bool.self, forKey: .dockPeekShowAppName) ?? defaults.dockPeekShowAppName
        dockPeekShowWindowTitle = try container.decodeIfPresent(Bool.self, forKey: .dockPeekShowWindowTitle) ?? defaults.dockPeekShowWindowTitle
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

public extension AppSettings {
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
        var settings = self
        settings.currentSpaceOnly = false
        settings.includeMinimized = true
        settings.includeHiddenApps = true
        // Peek is already scoped to one application, so collapsing to one window
        // per application would leave exactly one card.
        settings.groupByApplication = false
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
        if !settings.showMenuBarIcon && !settings.showDockIcon {
            settings.showMenuBarIcon = true
            changed = true
        }
        for action in ShortcutAction.allCases where action != .dismiss {
            guard let shortcut = settings.shortcuts[action], !shortcut.isSuitableForGlobalRegistration else { continue }
            settings.shortcuts[action] = nil
            changed = true
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
        return changed
    }

    private struct LegacySettings: Codable {
        var shortcuts: [String: ShortcutDefinition]?
        var showDockIcon: Bool?
        var showMenuBarIcon: Bool?
    }
}
