import AppKit
import ApplicationServices

enum WindowActivationError: LocalizedError {
    case applicationUnavailable
    case accessibilityUnavailable
    case windowUnavailable

    var errorDescription: String? {
        switch self {
        case .applicationUnavailable: "The application is no longer running."
        case .accessibilityUnavailable: "Accessibility permission is required to focus this exact window."
        case .windowUnavailable: "The window is no longer available."
        }
    }
}

protocol WindowActivating {
    func activate(_ window: SwitchableWindow) throws
}

final class AccessibilityWindowController: WindowActivating {
    func activate(_ window: SwitchableWindow) throws {
        guard let app = NSRunningApplication(processIdentifier: window.metadata.ownerPID) else {
            throw WindowActivationError.applicationUnavailable
        }
        app.activate(options: [])
        guard AXIsProcessTrusted() else { throw WindowActivationError.accessibilityUnavailable }

        let application = AXUIElementCreateApplication(window.metadata.ownerPID)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { throw WindowActivationError.windowUnavailable }

        let target: AXUIElement? = if window.metadata.title.isEmpty {
            windows.first
        } else {
            windows.first { element in
                var titleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
                return (titleValue as? String ?? "") == window.metadata.title
            }
        }
        guard let target else { throw WindowActivationError.windowUnavailable }
        AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        guard AXUIElementPerformAction(target, kAXRaiseAction as CFString) == .success else {
            throw WindowActivationError.windowUnavailable
        }
    }
}
