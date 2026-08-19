import AppKit
import ApplicationServices

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
        let originalFrame = AXGeometry.axFrame(of: windowElement)
        let screen = originalFrame.flatMap { frame -> NSScreen? in
            let cocoaFrame = AXGeometry.cocoaRect(fromAX: frame, primaryMaxY: primaryMaxY)
            return screens.filter { $0.frame.intersects(cocoaFrame) }.max { left, right in
                let leftIntersection = left.frame.intersection(cocoaFrame)
                let rightIntersection = right.frame.intersection(cocoaFrame)
                return leftIntersection.width * leftIntersection.height
                    < rightIntersection.width * rightIntersection.height
            }
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
            // Some applications accept only one of the two writes. Restore the
            // original geometry before invoking their own zoom button so the
            // fallback does not start from a half-moved, half-resized window.
            if let originalFrame {
                var originalPosition = originalFrame.origin
                var originalSize = originalFrame.size
                if let originalPositionValue = AXValueCreate(.cgPoint, &originalPosition),
                   let originalSizeValue = AXValueCreate(.cgSize, &originalSize) {
                    AXUIElementSetAttributeValue(
                        windowElement,
                        kAXPositionAttribute as CFString,
                        originalPositionValue
                    )
                    AXUIElementSetAttributeValue(
                        windowElement,
                        kAXSizeAttribute as CFString,
                        originalSizeValue
                    )
                }
            }
            try press(buttonAttribute: kAXZoomButtonAttribute, of: windowElement)
        }
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

        if let match = windows.first(where: { AXWindowBridge.windowID(of: $0) == window.id }) {
            return match
        }

        // A title fallback is safe only when it identifies exactly one AX
        // window. Raising the first untitled or duplicate-titled window would
        // be worse than the existing application-level activation fallback.
        let titleMatches = windows.filter { element in
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
            return (titleValue as? String ?? "") == window.metadata.title
        }
        guard titleMatches.count == 1, let target = titleMatches.first else {
            throw WindowActivationError.windowUnavailable
        }
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
