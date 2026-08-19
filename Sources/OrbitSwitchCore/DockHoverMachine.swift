import Foundation

/// What the Dock hover state machine asks its host to do.
public enum DockHoverEffect: Equatable, Sendable {
    case openPanel(pid_t)
    case closePanel
    case armDwell(TimeInterval)
    case cancelDwell
    case armExit(TimeInterval)
    case cancelExit
}

/// Decides when a Dock peek opens and closes.
///
/// This is a plain value type rather than logic inside the AppKit monitor
/// because the interesting part is not watching the mouse, it is the bookkeeping
/// around it — and that bookkeeping has been wrong twice. Once the panel could
/// be left on screen with no pending exit, because a click cleared the hover
/// without telling anyone to close; once an exit could be missed entirely. Both
/// were invisible to tests while they lived inside an event monitor.
///
/// The rule the machine enforces: **the panel is open exactly when `shown` is
/// non-nil**, and every transition that clears `shown` while a panel is open
/// emits `.closePanel`. Nothing else is allowed to strand it.
public struct DockHoverMachine: Equatable, Sendable {
    /// Time the pointer must rest on an icon before a panel opens.
    public var hoverDelay: TimeInterval
    /// Moving between icons with a panel already up uses this instead, so
    /// sliding along the Dock tracks the pointer.
    public let switchDelay: TimeInterval
    /// Leaving is forgiving: a diagonal move from the icon toward the panel
    /// crosses bare Dock for a frame or two and must not close it.
    public let exitGrace: TimeInterval

    /// The application whose panel is on screen, if any.
    public private(set) var shown: pid_t?
    /// The application being waited on before its panel opens.
    public private(set) var pending: pid_t?
    public private(set) var pointerInsidePanel = false

    public var isShowingPanel: Bool { shown != nil }

    public init(hoverDelay: TimeInterval = 0.25, switchDelay: TimeInterval = 0.08, exitGrace: TimeInterval = 0.22) {
        self.hoverDelay = hoverDelay
        self.switchDelay = switchDelay
        self.exitGrace = exitGrace
    }

    /// The pointer is over `pid`'s Dock icon.
    public mutating func pointerEnteredItem(_ pid: pid_t) -> [DockHoverEffect] {
        // Dock item signals come from the global event monitor, so receiving one
        // is also proof that the pointer is no longer inside our panel. Repair
        // the flag here in case AppKit missed the panel's mouse-exit event.
        pointerInsidePanel = false
        guard pid != shown else {
            // Back on the icon whose panel is already up.
            pending = nil
            return [.cancelExit, .cancelDwell]
        }
        guard pid != pending else { return [.cancelExit] }
        pending = pid
        return [.cancelExit, .cancelDwell, .armDwell(shown == nil ? hoverDelay : switchDelay)]
    }

    /// The pointer is over the Dock band but not over any application icon, or
    /// has left the band entirely. Like `pointerEnteredItem`, this is fed by the
    /// global monitor and therefore proves the pointer is outside our panel.
    public mutating func pointerLeftItems() -> [DockHoverEffect] {
        pointerInsidePanel = false
        pending = nil
        return [.cancelDwell] + exitEffects()
    }

    public mutating func dwellElapsed() -> [DockHoverEffect] {
        guard let pending else { return [] }
        shown = pending
        self.pending = nil
        return [.openPanel(pending)]
    }

    public mutating func exitElapsed() -> [DockHoverEffect] {
        // The pointer came back onto the panel while the grace period ran.
        guard !pointerInsidePanel, shown != nil else { return [] }
        shown = nil
        return [.closePanel]
    }

    /// The pointer crossed the panel's own boundary. These events reach the app
    /// rather than a global monitor, so the panel has to report them.
    public mutating func pointerInsidePanelChanged(_ inside: Bool) -> [DockHoverEffect] {
        pointerInsidePanel = inside
        return inside ? [.cancelExit] : exitEffects()
    }

    /// A mouse button went down somewhere outside the panel — on the Dock icon
    /// itself, on another window, on the desktop. The user is doing something
    /// else, so the panel leaves at once rather than after the grace period.
    ///
    /// This is the transition that used to clear the hover silently and strand
    /// the panel on screen with nothing left able to close it.
    public mutating func pointerPressedOutside() -> [DockHoverEffect] {
        let wasShowing = shown != nil
        clear()
        return [.cancelDwell, .cancelExit] + (wasShowing ? [.closePanel] : [])
    }

    /// Drops all hover state without asking for a close, for a host that is
    /// already tearing the panel down itself.
    public mutating func forget() -> [DockHoverEffect] {
        clear()
        return [.cancelDwell, .cancelExit]
    }

    private mutating func clear() {
        shown = nil
        pending = nil
        pointerInsidePanel = false
    }

    /// Nothing to leave unless a panel is up and the pointer is off it.
    private func exitEffects() -> [DockHoverEffect] {
        shown != nil && !pointerInsidePanel ? [.armExit(exitGrace)] : []
    }
}
