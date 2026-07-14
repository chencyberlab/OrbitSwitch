import AppKit
import ApplicationServices

/// Private-but-stable API (used by AltTab, yabai, Amethyst) that maps an
/// AXUIElement window to its CGWindowID. Title matching alone is unreliable:
/// Chrome, for example, appends " - Google Chrome – <profile>" to its AX
/// window titles but not to its CGWindowList titles.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum WindowActivationError: LocalizedError {
    case applicationUnavailable
    case accessibilityUnavailable
    case windowUnavailable
    case actionUnavailable

    var errorDescription: String? {
        switch self {
        case .applicationUnavailable: "The application is no longer running."
        case .accessibilityUnavailable: "Accessibility permission is required to focus this exact window."
        case .windowUnavailable: "The window is no longer available."
        case .actionUnavailable: "The window does not support this action."
        }
    }
}

enum WindowControlAction {
    case close, minimize, zoom
}

protocol WindowActivating {
    func activate(_ window: SwitchableWindow) throws
    func perform(_ action: WindowControlAction, on window: SwitchableWindow) throws
}

final class AccessibilityWindowController: WindowActivating {
    func activate(_ window: SwitchableWindow) throws {
        guard let app = NSRunningApplication(processIdentifier: window.metadata.ownerPID) else {
            throw WindowActivationError.applicationUnavailable
        }
        app.activate(options: [])
        let target = try resolveWindowElement(for: window)
        AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        guard AXUIElementPerformAction(target, kAXRaiseAction as CFString) == .success else {
            throw WindowActivationError.windowUnavailable
        }
    }

    func perform(_ action: WindowControlAction, on window: SwitchableWindow) throws {
        let target = try resolveWindowElement(for: window)
        switch action {
        case .close:
            try press(buttonAttribute: kAXCloseButtonAttribute, of: target)
        case .minimize:
            guard AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success else {
                throw WindowActivationError.actionUnavailable
            }
        case .zoom:
            try maximize(target)
        }
    }

    /// Fills the window's screen (visible frame) via AXPosition/AXSize, the
    /// approach DockDoor uses. Pressing AXZoomButton is app-defined and can
    /// even shrink the window; setting the frame is predictable everywhere.
    /// Falls back to the zoom button for windows that refuse frame changes.
    private func maximize(_ windowElement: AXUIElement) throws {
        let screens = NSScreen.screens
        guard let primaryMaxY = screens.first?.frame.maxY else {
            throw WindowActivationError.actionUnavailable
        }
        let screen = axFrame(of: windowElement).flatMap { frame -> NSScreen? in
            let cocoaFrame = CGRect(
                x: frame.origin.x,
                y: primaryMaxY - frame.origin.y - frame.height,
                width: frame.width,
                height: frame.height
            )
            return screens.first { $0.frame.intersects(cocoaFrame) }
        } ?? NSScreen.main ?? screens[0]

        let visible = screen.visibleFrame
        var position = CGPoint(x: visible.minX, y: primaryMaxY - visible.maxY)
        var size = CGSize(width: visible.width, height: visible.height)
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw WindowActivationError.actionUnavailable
        }
        let positionSet = AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, positionValue) == .success
        let sizeSet = AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, sizeValue) == .success
        if !positionSet || !sizeSet {
            try press(buttonAttribute: kAXZoomButtonAttribute, of: windowElement)
        }
    }

    /// Window frame in AX coordinates (top-left origin, primary-screen based).
    private func axFrame(of windowElement: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, CFGetTypeID(positionValue) == AXValueGetTypeID(),
              let sizeValue, CFGetTypeID(sizeValue) == AXValueGetTypeID(),
              AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func resolveWindowElement(for window: SwitchableWindow) throws -> AXUIElement {
        guard NSRunningApplication(processIdentifier: window.metadata.ownerPID) != nil else {
            throw WindowActivationError.applicationUnavailable
        }
        guard AXIsProcessTrusted() else { throw WindowActivationError.accessibilityUnavailable }

        let application = AXUIElementCreateApplication(window.metadata.ownerPID)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { throw WindowActivationError.windowUnavailable }

        if let match = windows.first(where: { element in
            var windowID: CGWindowID = 0
            return _AXUIElementGetWindow(element, &windowID) == .success && windowID == window.id
        }) {
            return match
        }

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
        return target
    }

    private func press(buttonAttribute: String, of windowElement: AXUIElement) throws {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, buttonAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw WindowActivationError.actionUnavailable
        }
        let button = value as! AXUIElement
        guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
            throw WindowActivationError.actionUnavailable
        }
    }
}
