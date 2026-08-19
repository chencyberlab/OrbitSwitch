import AppKit
import ApplicationServices

/// One running application's Dock icon.
struct DockItem: Equatable {
    let processID: pid_t
    let bundleIdentifier: String?
    let appName: String
    /// The icon's frame in AppKit screen coordinates. Everything about where
    /// the peek panel goes is derived from this rather than from the screen's
    /// `visibleFrame`, because an auto-hidden Dock leaves no inset behind.
    let frame: CGRect
}

/// Answers "whose Dock icon is the pointer over" by querying the Dock's own
/// Accessibility tree. This is the single new use of Accessibility that Dock
/// Peek introduces; every attribute it reads is a documented public one.
///
/// The Dock's application element is cached because resolving it costs a
/// process lookup, but the cache is dropped the moment a query fails — the Dock
/// is restarted often enough (display changes, `killall Dock`, logout/login)
/// that a stale element would otherwise disable the feature until relaunch.
@MainActor
final class DockItemLocator {
    private var cachedDock: (pid: pid_t, element: AXUIElement)?

    func invalidate() {
        cachedDock = nil
    }

    /// The application Dock item under `screenPoint`, or nil for empty Dock
    /// space, the separator, Trash, stacks, and minimized-window items.
    func item(at screenPoint: CGPoint) -> DockItem? {
        guard AXIsProcessTrusted(),
              let dock = dockElement(),
              let primaryMaxY = AXGeometry.primaryMaxY else { return nil }
        let point = AXGeometry.axPoint(fromCocoa: screenPoint, primaryMaxY: primaryMaxY)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(dock, Float(point.x), Float(point.y), &hit) == .success,
              let hit else {
            // A failed hit test is the usual first sign that the Dock this
            // element belonged to no longer exists.
            invalidate()
            return nil
        }
        guard let element = applicationDockItem(from: hit),
              let frame = AXGeometry.cocoaFrame(of: element),
              let application = runningApplication(for: element) else { return nil }
        return DockItem(
            processID: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            appName: application.localizedName ?? "",
            frame: frame
        )
    }

    /// The hit element is usually the dock item itself, but badges and other
    /// Dock chrome can add nested children. Walk a small bounded ancestor chain
    /// rather than assuming exactly one level.
    private func applicationDockItem(from element: AXUIElement) -> AXUIElement? {
        var candidate = element
        for _ in 0..<4 {
            if isApplicationDockItem(candidate) { return candidate }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(candidate, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            candidate = parent as! AXUIElement
        }
        return nil
    }

    /// The subrole is what separates an application icon from Trash, a stack,
    /// a folder, or one of the minimized-window items on the Dock's far side.
    private func isApplicationDockItem(_ element: AXUIElement) -> Bool {
        string(kAXSubroleAttribute, of: element) == "AXApplicationDockItem"
    }

    /// Identifies the app by the bundle URL the Dock item carries. Matching on
    /// `AXTitle` alone breaks for every app whose Dock title is localized or
    /// differs from its process name; the URL is exact. Title is kept only as a
    /// fallback for items that report no URL.
    private func runningApplication(for element: AXUIElement) -> NSRunningApplication? {
        let running = NSWorkspace.shared.runningApplications
        var urlValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &urlValue) == .success,
           let url = urlValue as? NSURL as URL? {
            let target = url.standardizedFileURL
            if let match = running.first(where: { $0.bundleURL?.standardizedFileURL == target }) {
                return match
            }
        }
        guard let title = string(kAXTitleAttribute, of: element), !title.isEmpty else { return nil }
        // A title fallback is safe only when unique. Two applications can have
        // the same localized display name; picking the first would show and
        // potentially control the wrong process's windows.
        let matches = running.filter { $0.activationPolicy == .regular && $0.localizedName == title }
        return matches.count == 1 ? matches[0] : nil
    }

    private func dockElement() -> AXUIElement? {
        guard let dockPID = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.dock"
        })?.processIdentifier else {
            invalidate()
            return nil
        }
        if let cachedDock, cachedDock.pid == dockPID { return cachedDock.element }
        let element = AXUIElementCreateApplication(dockPID)
        // The same guard WindowDiscoveryService uses: an unresponsive target
        // must never block the main thread on a pointer move.
        AXUIElementSetMessagingTimeout(element, 0.2)
        cachedDock = (dockPID, element)
        return element
    }

    private func string(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
