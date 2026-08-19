import AppKit

/// The floating panel a Dock peek appears in. Built like `SwitcherOverlayWindow`
/// with one deliberate difference: it can never become key. The pointer is the
/// only way in, so taking key status would pull focus out of whatever the user
/// was typing in for no gain.
final class DockPeekPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(content: DockPeekView) {
        super.init(
            contentRect: content.bounds,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Above the Dock's own window level, so the panel is never clipped by
        // the Dock it is anchored to.
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        // The backdrop fills the panel with an opaque rounded shape, so the
        // system shadow follows that shape without any path of our own.
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = content
        isReleasedWhenClosed = false
        animationBehavior = .none
        isMovableByWindowBackground = false
        // Tracking areas only generate moved events for a window that accepts
        // them, and this one never becomes key.
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
    }
}
