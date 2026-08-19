import AppKit
import ApplicationServices
import OrbitSwitchCore

/// NotificationCenter's block-observer token is not Sendable, while a main-
/// actor object's deinitializer is nonisolated in Swift 6. Keeping the token in
/// an explicitly thread-safe lifetime wrapper lets cleanup happen without
/// reaching into actor-isolated state from `DockPeekController.deinit`.
private final class NotificationObservation: @unchecked Sendable {
    private let center: NotificationCenter
    private let token: NSObjectProtocol

    init(center: NotificationCenter, token: NSObjectProtocol) {
        self.center = center
        self.token = token
    }

    deinit { center.removeObserver(token) }
}

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
    private var previewRefresh: Task<Void, Never>?
    private var visiblePreviewFill: Task<Void, Never>?
    private var pendingPreviewIDs = Set<CGWindowID>()
    private var requestedPreviewIDs = Set<CGWindowID>()
    private var inFlightPreviewIDs = Set<CGWindowID>()
    private var refreshedPreviewIDs = Set<CGWindowID>()
    private var previewGeneration = 0
    private var closeVerificationTasks: [CGWindowID: Task<Void, Never>] = [:]
    private var terminationObservation: NotificationObservation?
    private var isSuppressed = false

    var isVisible: Bool { panel != nil }

    init(discovery: WindowDiscovering, activator: WindowActivating) {
        self.discovery = discovery
        self.activator = activator
        monitor.onEnter = { [weak self] item in self?.show(item) }
        monitor.onExit = { [weak self] in self?.hide() }
        monitor.panelFrame = { [weak self] in self?.panel?.frame }
    }

    /// Starts or stops the hover monitor to match the current settings and
    /// permission state. Safe to call repeatedly; it is the single place that
    /// decides whether the feature is live.
    func apply(settings: AppSettings) {
        self.settings = settings
        monitor.hoverDelay = DockPeekLayout.clampedHoverDelay(settings.dockPeekHoverDelay)
        // Reading the Dock's window list is an Accessibility operation, so
        // without that permission there is nothing to hover-test against.
        guard !isSuppressed, settings.dockPeekEnabled, AXIsProcessTrusted() else {
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
        if suppressed {
            // Do not merely hide the panel. A running monitor could otherwise
            // continue advancing its hover machine behind the switcher and
            // leave it believing a panel was open when suppression ends.
            stop()
        } else {
            apply(settings: settings)
        }
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
        previewRefresh?.cancel()
        previewRefresh = nil
        resetVisiblePreviewWork()
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
        previewRefresh?.cancel()
        previewRefresh = nil
        resetVisiblePreviewWork()
        cancelCloseVerification()

        let peekSettings = settings.dockPeekDiscovery

        preparation = Task { [weak self] in
            guard let self else { return }
            let discovered = await self.discovery.discover(settings: peekSettings, ownerPID: item.processID)
            guard !Task.isCancelled, self.hoveredItem?.processID == item.processID else { return }
            let windows = discovered
            guard !windows.isEmpty else {
                // Nothing to show. The monitor keeps this icon as the current
                // hover, so we do not re-query it on every pointer move.
                self.hide()
                return
            }
            guard self.present(windows: windows, item: item) else {
                self.hide()
                return
            }
        }
    }

    /// Puts every discovered window on the panel: a list too long for the panel
    /// scrolls rather than being cut. Returns false only when no screen exists
    /// to host the panel.
    @discardableResult
    private func present(windows: [SwitchableWindow], item: DockItem) -> Bool {
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
        guard let screen else { return false }

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
        self.view = view
        view.configure(
            windows: windows,
            settings: cardSettings,
            metrics: placement.metrics,
            cardMetrics: cardMetrics
        )

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
        return true
    }

    private func makeView() -> DockPeekView {
        let view = DockPeekView(frame: .zero)
        view.onActivate = { [weak self] id in self?.activate(id) }
        view.onControlAction = { [weak self] action, id in self?.performControl(action, windowID: id) }
        view.onVisibleWindowsChanged = { [weak self] in self?.visibleWindowsChanged() }
        view.onPointerInsideChanged = { [weak self] inside in
            self?.monitor.setPointerInsidePanel(inside)
        }
        return view
    }

    /// Closes the panel without touching the monitor's hover state.
    private func hide() {
        preparation?.cancel()
        preparation = nil
        previewRefresh?.cancel()
        previewRefresh = nil
        resetVisiblePreviewWork()
        hoveredItem = nil
        cancelCloseVerification()
        guard let panel else { return }
        self.panel = nil
        view = nil
        // The outgoing view still exists for the fade. Stop it from delivering
        // stale tracking/click events into a newly opened panel during that
        // short overlap.
        panel.ignoresMouseEvents = true
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
            NSSound.beep()
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
            for attempt in 0..<10 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled, let self, let view = self.view,
                      view.windows.contains(where: { $0.id == windowID }) else { return }
                guard Self.windowStillExists(windowID) else {
                    self.closeVerificationTasks.removeValue(forKey: windowID)
                    view.removeWindow(id: windowID)
                    if view.windows.isEmpty { self.dismiss() }
                    return
                }
                if attempt == 2,
                   let target = view.windows.first(where: { $0.id == windowID }) {
                    // A close that still exists usually has a save sheet or
                    // another decision waiting in the owning app. Reveal it
                    // instead of leaving the user to hunt for the prompt.
                    self.dismiss()
                    do { try self.activator.activate(target) }
                    catch {
                        Log.windows.error(
                            "Could not reveal a Dock Peek window awaiting close confirmation: \(error.localizedDescription, privacy: .public)"
                        )
                    }
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
        // Keep the same all-Spaces scope used to discover the card. A user can
        // zoom a window parked on another Desktop without activating it first;
        // the switcher's raw Current Space setting must not make that refresh
        // silently miss the target.
        let settings = settings.dockPeekDiscovery
        previewRefresh?.cancel()
        previewRefresh = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self,
                  self.view?.windows.contains(where: { $0.id == window.id }) == true else { return }
            await self.discovery.capturePreviews(
                for: [window],
                settings: settings,
                maximumCount: 1
            ) { [weak self] id, image in
                guard !Task.isCancelled,
                      self?.view?.windows.contains(where: { $0.id == id }) == true else { return }
                self?.view?.updatePreview(id: id, image: image)
            }
        }
    }

    // MARK: - Visible preview loading

    /// Captures every card brought into the viewport, not just a fixed prefix
    /// of a long application list. Requests are drained serially so a fast
    /// scroll coalesces into the next batch rather than launching one complete
    /// ScreenCaptureKit enumeration per wheel event.
    private func visibleWindowsChanged() {
        guard PermissionService.status.screenRecording,
              let view, let hoveredItem else { return }
        let visible = view.visibleWindows
        let visibleIDs = Set(visible.map(\.id))
        requestedPreviewIDs.formIntersection(visibleIDs.union(inFlightPreviewIDs))
        for window in visible
        where (window.preview == nil || !refreshedPreviewIDs.contains(window.id))
            && !requestedPreviewIDs.contains(window.id) {
            requestedPreviewIDs.insert(window.id)
            pendingPreviewIDs.insert(window.id)
        }
        guard !pendingPreviewIDs.isEmpty, visiblePreviewFill == nil else { return }
        let generation = previewGeneration
        let processID = hoveredItem.processID
        let discoverySettings = settings.dockPeekDiscovery
        visiblePreviewFill = Task { [weak self] in
            await self?.drainVisiblePreviewRequests(
                generation: generation,
                processID: processID,
                settings: discoverySettings
            )
        }
    }

    private func drainVisiblePreviewRequests(
        generation: Int,
        processID: pid_t,
        settings: AppSettings
    ) async {
        defer {
            if previewGeneration == generation { visiblePreviewFill = nil }
        }
        while !Task.isCancelled, previewGeneration == generation,
              hoveredItem?.processID == processID, let view {
            let visibleIDs = Set(view.visibleWindows.map(\.id))
            let batchIDs = pendingPreviewIDs.intersection(visibleIDs)
            pendingPreviewIDs.subtract(batchIDs)
            let stalePending = pendingPreviewIDs.subtracting(visibleIDs)
            pendingPreviewIDs.subtract(stalePending)
            requestedPreviewIDs.subtract(stalePending)
            guard !batchIDs.isEmpty else {
                if pendingPreviewIDs.isEmpty { return }
                continue
            }
            inFlightPreviewIDs.formUnion(batchIDs)
            let targets = view.windows.filter { batchIDs.contains($0.id) }
            await discovery.capturePreviews(
                for: targets,
                settings: settings,
                maximumCount: targets.count
            ) { [weak self] id, image in
                guard let self, !Task.isCancelled,
                      self.previewGeneration == generation,
                      self.hoveredItem?.processID == processID,
                      self.view?.visibleWindows.contains(where: { $0.id == id }) == true else { return }
                self.view?.updatePreview(id: id, image: image)
            }
            refreshedPreviewIDs.formUnion(batchIDs)
            inFlightPreviewIDs.subtract(batchIDs)
            guard previewGeneration == generation, let currentView = self.view else { return }
            let stillVisible = Set(currentView.visibleWindows.map(\.id))
            requestedPreviewIDs.subtract(batchIDs.subtracting(stillVisible))
            if pendingPreviewIDs.isEmpty { return }
        }
    }

    private func resetVisiblePreviewWork() {
        previewGeneration &+= 1
        visiblePreviewFill?.cancel()
        visiblePreviewFill = nil
        pendingPreviewIDs.removeAll()
        requestedPreviewIDs.removeAll()
        inFlightPreviewIDs.removeAll()
        refreshedPreviewIDs.removeAll()
    }

    private func cancelCloseVerification() {
        closeVerificationTasks.values.forEach { $0.cancel() }
        closeVerificationTasks.removeAll()
    }

    /// A peeked application can quit while its panel is up — including because
    /// the last card was just closed from that panel.
    private func installTerminationObserver() {
        guard terminationObservation == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        let token = center.addObserver(
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
        terminationObservation = NotificationObservation(center: center, token: token)
    }
}
