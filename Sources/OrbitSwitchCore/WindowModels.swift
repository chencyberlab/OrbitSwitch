import CoreGraphics
import Foundation

public struct WindowMetadata: Identifiable, Equatable, Sendable {
    public let id: CGWindowID
    public let ownerPID: pid_t
    public let appName: String
    public let bundleIdentifier: String?
    public let title: String
    public let frame: CGRect
    public let layer: Int
    public let alpha: Double
    public let isOnScreen: Bool
    public var isMinimized: Bool?
    public let isRegularApplication: Bool
    public let isApplicationHidden: Bool

    public init(id: CGWindowID, ownerPID: pid_t, appName: String, bundleIdentifier: String?, title: String, frame: CGRect, layer: Int, alpha: Double, isOnScreen: Bool, isMinimized: Bool? = nil, isRegularApplication: Bool = true, isApplicationHidden: Bool = false) {
        self.id = id
        self.ownerPID = ownerPID
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.frame = frame
        self.layer = layer
        self.alpha = alpha
        self.isOnScreen = isOnScreen
        self.isMinimized = isMinimized
        self.isRegularApplication = isRegularApplication
        self.isApplicationHidden = isApplicationHidden
    }
}

public enum WindowFilter {
    public static func isEligible(_ window: WindowMetadata, settings: AppSettings, ownPID: pid_t) -> Bool {
        guard window.ownerPID != ownPID,
              window.alpha > 0.01,
              window.isRegularApplication,
              window.frame.width >= settings.minimumWindowWidth,
              window.frame.height >= settings.minimumWindowHeight,
              window.appName != "Dock",
              window.appName != "Window Server" else { return false }
        if settings.ignoreUtilityPanels && window.layer != 0 { return false }
        if !settings.ignoreUtilityPanels && (window.layer < 0 || window.layer > 10) { return false }
        if !settings.includeHiddenApps && window.isApplicationHidden { return false }
        if !window.isOnScreen {
            switch window.isMinimized {
            case true where !settings.includeMinimized: return false
            case false where settings.currentSpaceOnly && !window.isApplicationHidden: return false
            case nil: return false
            default: break
            }
        }
        if !settings.includeUntitled && window.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if let bundleID = window.bundleIdentifier, settings.excludedBundleIdentifiers.contains(bundleID) { return false }
        return true
    }

    public static func filtered(_ windows: [WindowMetadata], settings: AppSettings, ownPID: pid_t) -> [WindowMetadata] {
        var seenApps = Set<String>()
        return windows.filter { window in
            guard isEligible(window, settings: settings, ownPID: ownPID) else { return false }
            guard settings.groupByApplication else { return true }
            let key = window.bundleIdentifier ?? "pid:\(window.ownerPID)"
            return seenApps.insert(key).inserted
        }
    }
}
