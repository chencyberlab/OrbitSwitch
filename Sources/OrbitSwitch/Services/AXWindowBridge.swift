import ApplicationServices
import CoreGraphics

/// Private-but-stable API (used by AltTab, yabai, Amethyst) that maps an
/// AXUIElement window to its CGWindowID. Apple exposes no public equivalent.
///
/// Matching on titles instead is not merely less precise, it is wrong for real
/// applications: Chrome reports `"Home | Salesforce - Google Chrome (Incognito)"`
/// as a window's Accessibility title and `"Home | Salesforce"` as its Core
/// Graphics title, so the two never compare equal. Everything that has to line
/// an Accessibility window up with a Core Graphics one goes through here, and
/// treats a failure as "unknown" rather than guessing.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AXWindowBridge {
    /// The Core Graphics window ID behind an Accessibility window element, or
    /// nil when the symbol cannot resolve it.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &windowID) == .success,
              windowID != kCGNullWindowID else { return nil }
        return windowID
    }
}
