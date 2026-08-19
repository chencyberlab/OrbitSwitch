import AppKit
import ApplicationServices
import OrbitSwitchCore

/// Owns the hover-a-Dock-icon flow end to end: listens for hovers, gathers that
/// application's windows, puts the panel on screen, and services clicks on it.
///
/// It shares the discovery actor and the activator with `SwitcherOverlayController`
/// rather than owning its own, so there is one bounded thumbnail cache and one
/// purge path for the whole app. The two are never on screen together — the
/// switcher suppresses peek while it is up.
@MainActor
final class DockPeekController {
    private let discovery: WindowDiscovering
    private let activator: WindowActivating
    private let monitor = DockHoverMonitor()

    private var panel: DockPeekPanel?
    private var view: DockPeekView?
    private var settings = AppSettings()
    private var hoveredItem: DockItem?
    private var preparation: Task<Void, Never>?
    private var closeVerificationTasks: [CGWindowID: Task<Void, Never>] = [:]
    private var terminationObserver: NSObjectProtocol?
    private var isSuppressed = false

    var isVisible: Bool { panel != nil }

    init(discovery: WindowDiscovering, activator: WindowActivating) {
        self.discovery = discovery
        self.activator = activator
        monitor.onEnter = { [weak self] item in self?.show(item) }
        monitor.onExit = { [weak self] in self?.hide() }
        monitor.panelFrame = { [weak self] in self?.panel?.frame }
    }

    deinit {
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
    }

    /// Starts or stops the hover monitor to match the current settings and
    /// permission state. Safe to call repeatedly; it is the single place that
    /// decides whether the feature is live.
    func apply(settings: AppSettings) {
        self.settings = settings
        monitor.hoverDelay = DockPeekLayout.clampedHoverDelay(settings.dockPeekHoverDelay)
        // Reading the Dock's window list is an Accessibility operation, so
        // without that permission there is nothing to hover-test against.
        guard settings.dockPeekEnabled, AXIsProcessTrusted() else {
            stop()
            return
        }
        installTerminationObserver()
        monitor.start()
    }

    func stop() {
        monitor.stop()
        dismiss()
    }

    /// The switcher is on screen. Two window pickers at once would be noise, and
    /// the shared discovery actor should serve one of them at a time.
    func setSuppressed(_ suppressed: Bool) {
        guard suppressed != isSuppressed else { return }
        isSuppressed = suppressed
        if suppressed { dismiss() }
    }

    func screenParametersChanged() {
        monitor.screenParametersChanged()
        hide()
    }

    /// Drops every thumbnail currently on screen. The shared cache behind them
    /// is purged by `SwitcherOverlayController.purgeCachedPreviews`, which owns
    /// the discovery actor's lifecycle.
    func purgeVisiblePreviews() {
        preparation?.cancel()
        preparation = nil
        view?.clearPreviews()
    }

    /// Closes the panel and forgets the hover, so the same icon can open a
    /// fresh peek. Used for anything that invalidates the peek from outside.
    func dismiss() {
        monitor.reset()
        hide()
    }

    // MARK: - Presentation

    private func show(_ item: DockItem) {
        guard !isSuppressed, settings.dockPeekEnabled else { return }
        hoveredItem = item
        preparation?.cancel()
        cancelCloseVerification()

        let peekSettings = settings.dockPeekDiscovery

        let canCapture = PermissionService.status.screenRecording
        preparation = Task { [weak self] in
            guard let self else { return }
            let discovered = await self.discovery.discover(settings: peekSettings)
            guard !Task.isCancelled, self.hoveredItem?.processID == item.processID else { return }
            let windows = discovered.filter { $0.metadata.ownerPID == item.processID }
            guard !windows.isEmpty else {
                // Nothing to show. The monitor keeps this icon as the current
                // hover, so we do not re-query it on every pointer move.
                self.hide()
                return
            }
            let presented = self.present(windows: windows, item: item)
            guard canCapture, !Task.isCancelled, !presented.isEmpty else { return }
            await self.discovery.capturePreviews(for: presented, settings: peekSettings) { [weak self] id, image in
                guard let self, !Task.isCancelled, self.hoveredItem?.processID == item.processID else { return }
                self.view?.updatePreview(id: id, image: image)
            }
        }
    }

    /// Returns the windows put on the panel, which is all of them: a list too
    /// long for the panel scrolls rather than being cut.
    @discardableResult
    private func present(windows: [SwitchableWindow], item: DockItem) -> [SwitchableWindow] {
        // The card is shared with the switcher, so peek's own chrome choices are
        // handed to it as a settings copy rather than duplicating the card.
        var cardSettings = settings
        cardSettings.showWindowControls = settings.dockPeekShowControls
        cardSettings.showAppIcon = settings.dockPeekShowAppIcon
        cardSettings.showAppName = settings.dockPeekShowAppName
        cardSettings.showWindowTitle = settings.dockPeekShowWindowTitle
        let cardMetrics = CardMetrics.compact.resolved(for: cardSettings)
        let screen = NSScreen.screens.first { $0.frame.intersects(item.frame) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return [] }

        let placement = DockPeekLayout.placement(
            count: windows.count,
            anchor: item.frame,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            preferredTileWidth: settings.dockPeekTileWidth,
            footerHeight: Double(cardMetrics.footerHeight)
        )
        let isNewPanel = panel == nil
        let view = view ?? makeView()
        view.configure(
            windows: windows,
            settings: cardSettings,
            metrics: placement.metrics,
            cardMetrics: cardMetrics
        )
        self.view = view

        let panel = panel ?? DockPeekPanel(content: view)
        self.panel = panel
        if isNewPanel {
            panel.alphaValue = 0
            panel.setFrame(placement.frame, display: false)
            panel.orderFrontRegardless()
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0.08 : 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            // Sliding to the neighboring icon keeps the same panel and moves it,
            // which reads as one surface following the pointer rather than two
            // panels flashing in sequence.
            panel.setFrame(placement.frame, display: true)
            panel.orderFrontRegardless()
        }
        return windows
    }

    private func makeView() -> DockPeekView {
        let view = DockPeekView(frame: .zero)
        view.onActivate = { [weak self] id in self?.activate(id) }
        view.onControlAction = { [weak self] action, id in self?.performControl(action, windowID: id) }
        view.onPointerInsideChanged = { [weak self] inside in
            self?.monitor.setPointerInsidePanel(inside)
        }
        return view
    }

    /// Closes the panel without touching the monitor's hover state.
    private func hide() {
        preparation?.cancel()
        preparation = nil
        hoveredItem = nil
        cancelCloseVerification()
        guard let panel else { return }
        self.panel = nil
        view = nil
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0.06 : 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            // AppKit calls this on the main thread but types it as nonisolated.
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }

    // MARK: - Actions

    private func activate(_ windowID: CGWindowID) {
        guard let window = view?.windows.first(where: { $0.id == windowID }) else { return }
        dismiss()
        do { try activator.activate(window) }
        catch { Log.windows.error("Dock peek activation was incomplete: \(error.localizedDescription, privacy: .public)") }
    }

    private func performControl(_ action: WindowControlAction, windowID: CGWindowID) {
        guard let view, let window = view.windows.first(where: { $0.id == windowID }) else { return }
        do { try activator.perform(action, on: window) }
        catch {
            Log.windows.error("Dock peek control action failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        switch action {
        case .close:
            verifyWindowClosed(windowID)
        case .minimize:
            view.markMinimized(id: windowID)
        case .zoom:
            refreshPreviewSoon(for: window)
        }
    }

    /// Same rule the switcher uses: AXPress returning success means the close
    /// request was delivered, not accepted. A document app can hold the window
    /// open behind a save sheet, so the card survives until Core Graphics says
    /// the window ID is really gone.
    private func verifyWindowClosed(_ windowID: CGWindowID) {
        closeVerificationTasks.removeValue(forKey: windowID)?.cancel()
        closeVerificationTasks[windowID] = Task { [weak self] in
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled, let self, let view = self.view,
                      view.windows.contains(where: { $0.id == windowID }) else { return }
                guard Self.windowStillExists(windowID) else {
                    view.removeWindow(id: windowID)
                    if view.windows.isEmpty { self.dismiss() }
                    return
                }
            }
            self?.closeVerificationTasks.removeValue(forKey: windowID)
        }
    }

    private static func windowStillExists(_ windowID: CGWindowID) -> Bool {
        let requestedIDs = [NSNumber(value: windowID)] as CFArray
        guard let descriptions = CGWindowListCreateDescriptionFromArray(requestedIDs) else { return true }
        return CFArrayGetCount(descriptions) > 0
    }

    private func refreshPreviewSoon(for window: SwitchableWindow) {
        guard PermissionService.status.screenRecording else { return }
        let settings = settings
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, self.view != nil else { return }
            await self.discovery.capturePreviews(for: [window], settings: settings) { [weak self] id, image in
                self?.view?.updatePreview(id: id, image: image)
            }
        }
    }

    private func cancelCloseVerification() {
        closeVerificationTasks.values.forEach { $0.cancel() }
        closeVerificationTasks.removeAll()
    }

    /// A peeked application can quit while its panel is up — including because
    /// the last card was just closed from that panel.
    private func installTerminationObserver() {
        guard terminationObserver == nil else { return }
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let terminated = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .processIdentifier
            Task { @MainActor [weak self] in
                guard let self, let terminated, self.hoveredItem?.processID == terminated else { return }
                self.dismiss()
            }
        }
    }
}
