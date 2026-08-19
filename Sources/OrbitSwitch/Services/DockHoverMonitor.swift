import AppKit
import OrbitSwitchCore

/// Turns raw global pointer movement into "opened a Dock icon's peek" and
/// "closed it" callbacks.
///
/// Everything that decides *when* those happen lives in `DockHoverMachine`,
/// which is a pure value type in the core and unit tested. This class is the
/// adapter around it: it watches the mouse, throttles the expensive part, runs
/// the timers the machine asks for, and turns the machine's effects into calls.
///
/// Cost control is why the watching is here at all. This sees every mouse move
/// on the system, so two filters run before any Accessibility work: a pointer
/// outside the band of screen the Dock can occupy is rejected on arithmetic
/// alone, and what survives that is rate limited.
@MainActor
final class DockHoverMonitor {
    var onEnter: ((DockItem) -> Void)?
    var onExit: (() -> Void)?
    /// The peek panel's current frame, if one is on screen. Leaving is checked
    /// against this geometrically as well as through the panel's tracking
    /// areas, so a missed enter/exit event can never strand a panel the pointer
    /// is sitting on.
    var panelFrame: (() -> CGRect?)?

    var hoverDelay: TimeInterval {
        get { machine.hoverDelay }
        set { machine.hoverDelay = DockPeekLayout.clampedHoverDelay(newValue) }
    }

    /// Ceiling on Accessibility round trips, independent of mouse event rate.
    private static let minimumQueryInterval = 0.04
    /// How far from a screen edge the pointer must be to be worth a query when
    /// the Dock is hidden and therefore reserves no screen area at all.
    private static let autoHideBand = 100.0

    private var machine = DockHoverMachine()
    private let locator = DockItemLocator()
    private var monitors: [Any] = []
    private var dwellTimer: Timer?
    private var exitTimer: Timer?
    /// The last item seen under the pointer, so an open effect can name it.
    private var itemsByPID: [pid_t: DockItem] = [:]
    private var lastQueryTime: TimeInterval = 0

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        let moved = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        // A click anywhere outside the panel — including on the Dock icon
        // itself — means the user is doing something else. The panel leaves at
        // once rather than after the grace period.
        let pressed = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply(self?.machine.pointerPressedOutside() ?? []) }
        }
        monitors = [moved, pressed].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        reset()
    }

    func setPointerInsidePanel(_ inside: Bool) {
        apply(machine.pointerInsidePanelChanged(inside))
    }

    /// Display rearrangement moves every Dock item and can restart the Dock.
    func screenParametersChanged() {
        locator.invalidate()
        reset()
    }

    /// Drops hover state without asking for a close, for a caller that is
    /// already closing the panel itself.
    func reset() {
        apply(machine.forget())
        itemsByPID.removeAll()
        lastQueryTime = 0
    }

    // MARK: - Effects

    private func apply(_ effects: [DockHoverEffect]) {
        for effect in effects {
            switch effect {
            case .openPanel(let pid):
                guard let item = itemsByPID[pid] else { continue }
                onEnter?(item)
            case .closePanel:
                onExit?()
            case .cancelDwell:
                dwellTimer?.invalidate()
                dwellTimer = nil
            case .cancelExit:
                exitTimer?.invalidate()
                exitTimer = nil
            case .armDwell(let delay):
                dwellTimer?.invalidate()
                dwellTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.dwellTimer = nil
                        self.apply(self.machine.dwellElapsed())
                    }
                }
            case .armExit(let delay):
                guard exitTimer == nil else { continue }
                exitTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.exitTimer = nil
                        // The pointer resting on the panel keeps it open whether
                        // or not the panel's tracking areas said so.
                        if self.panelFrame?()?.contains(NSEvent.mouseLocation) == true {
                            self.apply(self.machine.pointerInsidePanelChanged(true))
                            return
                        }
                        self.apply(self.machine.exitElapsed())
                    }
                }
            }
        }
    }

    // MARK: - Watching

    private func pointerMoved() {
        let point = NSEvent.mouseLocation
        guard isWithinDockBand(point) else {
            apply(machine.pointerLeftItems())
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastQueryTime >= Self.minimumQueryInterval else { return }
        lastQueryTime = now
        guard let item = locator.item(at: point) else {
            apply(machine.pointerLeftItems())
            return
        }
        itemsByPID[item.processID] = item
        apply(machine.pointerEnteredItem(item.processID))
    }

    /// Cheap rejection: the Dock only ever occupies the bottom, left, or right
    /// edge, and the room it reserves is exactly the difference between the
    /// screen's frame and its visible frame. An auto-hidden Dock reserves
    /// nothing, so when no edge reports an inset the whole edge region is
    /// probed instead.
    private func isWithinDockBand(_ point: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return false }
        let frame = screen.frame
        let visible = screen.visibleFrame
        let bottom = max(0, visible.minY - frame.minY)
        let left = max(0, visible.minX - frame.minX)
        let right = max(0, frame.maxX - visible.maxX)
        guard bottom > 0 || left > 0 || right > 0 else {
            return point.y - frame.minY <= Self.autoHideBand
                || point.x - frame.minX <= Self.autoHideBand
                || frame.maxX - point.x <= Self.autoHideBand
        }
        let slack = 4.0
        if bottom > 0 && point.y - frame.minY <= bottom + slack { return true }
        if left > 0 && point.x - frame.minX <= left + slack { return true }
        if right > 0 && frame.maxX - point.x <= right + slack { return true }
        return false
    }
}
