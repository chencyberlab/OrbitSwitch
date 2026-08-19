import CoreGraphics
import Foundation

/// One Accessibility window whose Core Graphics window ID could not be read.
public struct AccessibilityWindowState: Equatable, Sendable {
    public let title: String
    public let isMinimized: Bool

    public init(title: String, isMinimized: Bool) {
        self.title = title
        self.isMinimized = isMinimized
    }
}

/// Decides which off-screen windows are minimized.
///
/// Core Graphics reports that a window is off screen but never why: minimized,
/// on another Desktop, or an invisible helper surface are indistinguishable in
/// its window list. Accessibility knows, so the two lists have to be lined up —
/// and how that is done is the whole point of this type.
///
/// Matching on titles does not work. Chrome reports one window as
/// `"Home | Salesforce - Google Chrome (Incognito)"` to Accessibility and
/// `"Home | Salesforce"` to Core Graphics; the strings never compare equal, so
/// every minimized Chrome window resolved to "unknown" and was discarded. The
/// window ID is exact and is tried first, with titles kept only for the rare
/// element whose ID cannot be read.
///
/// An unresolved window stays `nil`, which the filter drops. That is deliberate:
/// most off-screen entries really are helper surfaces, and listing one as a
/// window the user can switch to is worse than omitting a real window.
public enum MinimizedStateResolver {
    public static func apply(
        to windows: inout [WindowMetadata],
        minimizedByWindowID: [CGWindowID: Bool],
        unidentifiedByPID: [pid_t: [AccessibilityWindowState]] = [:]
    ) {
        var unidentified = unidentifiedByPID
        for index in windows.indices where !windows[index].isOnScreen {
            if let isMinimized = minimizedByWindowID[windows[index].id] {
                windows[index].isMinimized = isMinimized
                continue
            }
            let candidates = unidentified[windows[index].ownerPID] ?? []
            // Each fallback state describes one window, so it is consumed once
            // rather than matching every window that shares its title.
            guard let match = candidates.firstIndex(where: { $0.title == windows[index].title }) else { continue }
            windows[index].isMinimized = candidates[match].isMinimized
            unidentified[windows[index].ownerPID]?.remove(at: match)
        }
    }
}
