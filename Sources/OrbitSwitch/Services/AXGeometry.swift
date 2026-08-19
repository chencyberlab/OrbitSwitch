import AppKit
import ApplicationServices

/// Accessibility reports geometry in a top-left origin space anchored on the
/// primary display; AppKit uses a bottom-left origin. Both directions of that
/// flip live here so the Dock item locator and the window controller cannot
/// drift apart on it.
enum AXGeometry {
    /// The pivot both conversions turn on. `NSScreen.screens.first` is the
    /// screen containing the origin, which is what Accessibility anchors to.
    static var primaryMaxY: CGFloat? { NSScreen.screens.first?.frame.maxY }

    /// An element's frame in Accessibility coordinates.
    static func axFrame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, CFGetTypeID(positionValue) == AXValueGetTypeID(),
              let sizeValue, CFGetTypeID(sizeValue) == AXValueGetTypeID(),
              AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// An element's frame in AppKit screen coordinates.
    static func cocoaFrame(of element: AXUIElement) -> CGRect? {
        guard let primaryMaxY, let frame = axFrame(of: element) else { return nil }
        return cocoaRect(fromAX: frame, primaryMaxY: primaryMaxY)
    }

    static func cocoaRect(fromAX rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryMaxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    static func axPoint(fromCocoa point: CGPoint, primaryMaxY: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryMaxY - point.y)
    }
}
