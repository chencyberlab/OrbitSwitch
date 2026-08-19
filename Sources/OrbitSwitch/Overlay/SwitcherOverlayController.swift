import AppKit
import OrbitSwitchCore

enum SwitcherMode {
    case allWindows
    case onePerApplication
    case currentApplication
}

@MainActor
final class SwitcherOverlayController {
    enum State: Equatable {
        case idle, preparing, visible(selection: Int), activating, dismissing
    }

    /// Reported on every real state change. Dock Peek uses it to stay out of
    /// the way while the switcher is up; nothing else in the overlay depends on
    /// it, so an unset handler costs nothing.
    var onStateChange: ((State) -> Void)?

    private(set) var state = State.idle {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }
    private let discovery: WindowDiscovering
    private let activator: WindowActivating
    private var panels: [SwitcherOverlayWindow] = []
    private var windows: [SwitchableWindow] = []
    private var settings = AppSettings()
    private var preparation: Task<Void, Never>?
    private var pendingOffset = 0
    private var activateWhenReady = false
    private var presentationRevision = 0
    private var previewFill: Task<Void, Never>?
    private var previewRefresh: Task<Void, Never>?
    private var closeVerificationTasks: [CGWindowID: Task<Void, Never>] = [:]

    init(discovery: WindowDiscovering = WindowDiscoveryService(), activator: WindowActivating = AccessibilityWindowController()) {
        self.discovery = discovery
        self.activator = activator
    }

    func showOrAdvance(settings: AppSettings, mode: SwitcherMode = .allWindows) {
        switch state {
        case .visible(let selection): move(to: selection + 1)
        case .preparing: pendingOffset += 1
        case .idle: prepare(settings: settings, mode: mode)
        case .activating, .dismissing: break
        }
    }

    func movePrevious(settings: AppSettings) {
        if case .visible(let selection) = state { move(to: selection - 1) }
        else if state == .preparing { pendingOffset -= 1 }
        else { prepare(settings: settings, mode: .allWindows, initialOffset: -1) }
    }

    func confirm() {
        if state == .preparing {
            activateWhenReady = true
            return
        }
        guard case .visible(let selection) = state, windows.indices.contains(selection) else {
            dismiss(); return
        }
        state = .activating
        preparation?.cancel()
        let target = windows[selection]
        closePanels()
        do { try activator.activate(target) }
        catch { Log.windows.error("Window activation was incomplete: \(error.localizedDescription, privacy: .public)") }
        clear()
    }

    func dismiss() {
        preparation?.cancel()
        guard state != .idle else { return }
        state = .dismissing
        closePanels()
        clear()
    }

    /// Clears all screen-derived images without requiring an application
    /// restart. Revoking Screen Recording should update an already visible
    /// overlay immediately, and session lock/sleep must form a hard privacy
    /// boundary rather than retaining the previous session's first frame.
    func purgeCachedPreviews() {
        if state == .preparing {
            dismiss()
        } else {
            preparation?.cancel()
        }
        previewFill?.cancel()
        previewFill = nil
        previewRefresh?.cancel()
        previewRefresh = nil
        for index in windows.indices { windows[index].preview = nil }
        panels.compactMap { $0.contentView as? SwitcherSurfaceView }.forEach { $0.clearPreviews() }
        let discovery = discovery
        Task { await discovery.purgePreviews() }
    }

    private func prepare(settings: AppSettings, mode: SwitcherMode, initialOffset: Int = 0) {
        guard state == .idle else { return }
        state = .preparing
        self.settings = settings
        pendingOffset = initialOffset
        activateWhenReady = false
        let canCapture = PermissionService.status.screenRecording
        var discoverySettings = settings
        let ownerPID: pid_t?
        switch mode {
        case .allWindows:
            ownerPID = nil
        case .onePerApplication:
            discoverySettings.groupByApplication = true
            ownerPID = nil
        case .currentApplication:
            discoverySettings = settings.currentApplicationDiscovery
            // Snapshot the app at invocation time. Reading this after the
            // asynchronous discovery can target whichever app happened to
            // become frontmost while OrbitSwitch was preparing instead.
            ownerPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        preparation = Task { [weak self] in
            guard let self else { return }
            let discovered: [SwitchableWindow]
            if mode == .currentApplication, ownerPID == nil {
                // No frontmost application is a valid transient state. It is
                // not a reason for a current-app shortcut to show every app.
                discovered = []
            } else {
                discovered = await discovery.discover(settings: discoverySettings, ownerPID: ownerPID)
            }
            guard !Task.isCancelled else { return }
            windows = discovered
            present()
            guard canCapture, !Task.isCancelled, !windows.isEmpty else { return }
            let captureTargets = windows
            await discovery.capturePreviews(
                for: captureTargets,
                settings: discoverySettings,
                maximumCount: PreviewCache.defaultLimit
            ) { [weak self] id, image in
                guard let self, !Task.isCancelled, case .visible = self.state else { return }
                if let index = self.windows.firstIndex(where: { $0.id == id }) {
                    self.windows[index].preview = image
                }
                self.panels.compactMap { $0.contentView as? SwitcherSurfaceView }.forEach {
                    $0.updatePreview(id: id, image: image)
                }
            }
        }
    }

    private func present() {
        let availableScreens = NSScreen.screens
        guard let fallbackScreen = NSScreen.main ?? availableScreens.first else {
            clear()
            return
        }
        let targetScreens: [NSScreen]
        switch settings.displayMode {
        case .active: targetScreens = [fallbackScreen]
        case .pointer:
            let point = NSEvent.mouseLocation
            targetScreens = [availableScreens.first(where: { $0.frame.contains(point) }) ?? fallbackScreen]
        case .all: targetScreens = availableScreens
        }
        panels = targetScreens.map { screen in
            let view: SwitcherSurfaceView = switch settings.overlayStyle {
            case .orbit: Flip3DView(frame: screen.frame)
            case .sidebar: SidebarView(frame: screen.frame)
            }
            let initialSelection = Flip3DLayout.wrappedIndex(pendingOffset, count: windows.count)
            view.configure(windows: windows, selection: initialSelection, settings: settings)
            view.onMove = { [weak self] offset in
                guard let self, case .visible(let selection) = self.state else { return }
                self.move(to: selection + offset)
            }
            view.onConfirm = { [weak self] in self?.confirm() }
            view.onCancel = { [weak self] in self?.dismiss() }
            view.onControlAction = { [weak self] action, windowID in
                self?.performControl(action, windowID: windowID)
            }
            let panel = SwitcherOverlayWindow(screen: screen, content: view)
            panel.alphaValue = 0
            view.prepareForPresentation()
            return panel
        }
        panels.dropFirst().forEach { $0.orderFrontRegardless() }
        panels.first?.makeKeyAndOrderFront(nil)
        if let view = panels.first?.contentView { panels.first?.makeFirstResponder(view) }
        let initialSelection = Flip3DLayout.wrappedIndex(pendingOffset, count: windows.count)
        state = .visible(selection: initialSelection)
        announceSelection(initialSelection)
        if initialSelection >= PreviewCache.defaultLimit {
            // Repeated shortcut events can move the initial selection past the
            // bounded opening capture while discovery is still running.
            fillMissingPreview(at: initialSelection)
        }
        pendingOffset = 0
        presentationRevision += 1
        let revision = presentationRevision
        let panelsToReveal = panels
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.presentationRevision == revision, case .visible = self.state else { return }
            panelsToReveal.compactMap { $0.contentView as? SwitcherSurfaceView }.forEach { $0.prepareForPresentation() }
            CATransaction.flush()
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            for panel in panelsToReveal {
                (panel.contentView as? SwitcherSurfaceView)?.animateMaterializeIn(reduceMotion: reduceMotion)
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = reduceMotion ? 0.12 : 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().alphaValue = 1
                }, completionHandler: nil)
            }
        }
        if activateWhenReady {
            activateWhenReady = false
            confirm()
        }
    }

    private func performControl(_ action: WindowControlAction, windowID: CGWindowID) {
        guard case .visible(let selection) = state,
              let index = windows.firstIndex(where: { $0.id == windowID }) else { return }
        do { try activator.perform(action, on: windows[index]) }
        catch {
            Log.windows.error("Window control action failed: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
            return
        }
        switch action {
        case .close:
            verifyWindowClosed(windowID)
        case .minimize:
            if settings.includeMinimized {
                windows[index].metadata.isMinimized = true
            } else {
                removeWindow(at: index, currentSelection: selection)
            }
        case .zoom:
            refreshPreviewSoon(for: windows[index])
        }
    }

    private func removeWindow(at index: Int, currentSelection: Int) {
        let removedID = windows[index].id
        closeVerificationTasks.removeValue(forKey: removedID)?.cancel()
        windows.remove(at: index)
        guard !windows.isEmpty else {
            dismiss()
            return
        }
        let adjusted = index < currentSelection ? currentSelection - 1 : currentSelection
        let selection = Flip3DLayout.wrappedIndex(adjusted, count: windows.count)
        state = .visible(selection: selection)
        panels.compactMap { $0.contentView as? SwitcherSurfaceView }.forEach {
            $0.removeWindow(id: removedID, selection: selection)
        }
        announceSelection(selection)
        fillMissingPreview(at: selection)
    }

    /// AXPress returning success means the close request was delivered, not
    /// that the application accepted it. Document apps can keep the window
    /// alive behind a save-confirmation sheet, so remove the card only after
    /// Core Graphics confirms that the window ID has actually disappeared.
    private func verifyWindowClosed(_ windowID: CGWindowID) {
        closeVerificationTasks.removeValue(forKey: windowID)?.cancel()
        closeVerificationTasks[windowID] = Task { [weak self] in
            for attempt in 0..<10 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled, let self,
                      case .visible(let selection) = self.state,
                      let index = self.windows.firstIndex(where: { $0.id == windowID }) else { return }
                guard Self.windowStillExists(windowID) else {
                    self.removeWindow(at: index, currentSelection: selection)
                    return
                }
                if attempt == 2 {
                    // A normal close has had 600 ms to disappear. If the
                    // window remains, it usually needs attention in an
                    // unsaved-document sheet. The full-screen switcher would
                    // sit above that sheet and block it, so hand control to the
                    // owning app while keeping fast successful closes in-place.
                    let target = self.windows[index]
                    self.dismiss()
                    do { try self.activator.activate(target) }
                    catch {
                        Log.windows.error(
                            "Could not reveal a window awaiting close confirmation: \(error.localizedDescription, privacy: .public)"
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
        // A Window Server query failure is not evidence that the close
        // succeeded; err toward retaining the card and let the next discovery
        // reconcile it.
        guard let descriptions = CGWindowListCreateDescriptionFromArray(requestedIDs) else { return true }
        return CFArrayGetCount(descriptions) > 0
    }

    private func refreshPreviewSoon(for window: SwitchableWindow) {
        guard PermissionService.status.screenRecording else { return }
        previewRefresh?.cancel()
        previewRefresh = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self, case .visible = self.state,
                  self.windows.contains(where: { $0.id == window.id }) else { return }
            await self.discovery.capturePreviews(
                for: [window],
                settings: self.settings,
                maximumCount: 1
            ) { [weak self] id, image in
                guard let self, !Task.isCancelled, case .visible = self.state,
                      self.windows.contains(where: { $0.id == id }) else { return }
                if let index = self.windows.firstIndex(where: { $0.id == id }) {
                    self.windows[index].preview = image
                }
                self.panels.compactMap { $0.contentView as? SwitcherSurfaceView }.forEach {
                    $0.updatePreview(id: id, image: image)
                }
            }
        }
    }

    private func move(to proposedSelection: Int) {
        guard !windows.isEmpty else { return }
        let selection = Flip3DLayout.wrappedIndex(proposedSelection, count: windows.count)
        state = .visible(selection: selection)
        panels.compactMap { $0.contentView as? SwitcherSurfaceView }.forEach { $0.updateSelection(selection) }
        announceSelection(selection)
        fillMissingPreview(at: selection)
    }

    /// The overlay is a non-activating panel, so moving the selection changes
    /// nothing VoiceOver would otherwise notice — and with mirrored panels the
    /// announcement has to come from here, once, rather than from each view.
    /// Only posted when VoiceOver is actually listening.
    private func announceSelection(_ selection: Int) {
        guard NSWorkspace.shared.isVoiceOverEnabled, windows.indices.contains(selection) else { return }
        let window = windows[selection].metadata
        let title = window.title.isEmpty ? "Untitled Window" : window.title
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "\(window.appName), \(title), \(selection + 1) of \(windows.count)",
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    /// The opening capture covers a bounded prefix of the window list, but the
    /// selected window is always on screen in both styles — so past that prefix
    /// it would keep its title/icon fallback forever. Capture the selection on
    /// demand instead, debounced so holding the shortcut down does not queue a
    /// capture for every window it passes through.
    private func fillMissingPreview(at selection: Int) {
        // A task for the previous selection is no longer useful even when this
        // selection already has an image. Cancel before the early exits.
        previewFill?.cancel()
        previewFill = nil
        guard PermissionService.status.screenRecording,
              windows.indices.contains(selection),
              windows[selection].preview == nil else { return }
        let target = windows[selection]
        let settings = settings
        previewFill = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled, let self, case .visible(let currentSelection) = self.state,
                  self.windows.indices.contains(currentSelection),
                  self.windows[currentSelection].id == target.id else { return }
            await self.discovery.capturePreviews(
                for: [target],
                settings: settings,
                maximumCount: 1
            ) { [weak self] id, image in
                guard let self, !Task.isCancelled, case .visible(let currentSelection) = self.state,
                      self.windows.indices.contains(currentSelection),
                      self.windows[currentSelection].id == id else { return }
                if let index = self.windows.firstIndex(where: { $0.id == id }) {
                    self.windows[index].preview = image
                }
                self.panels.compactMap { $0.contentView as? SwitcherSurfaceView }.forEach {
                    $0.updatePreview(id: id, image: image)
                }
            }
        }
    }

    /// Fades and settles each panel back, then orders it out. Callers are not
    /// blocked on the animation, so confirming a window activates it while the
    /// overlay is still leaving — the inverse of the arrival, along the same path.
    private func closePanels() {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let outgoing = panels
        panels.removeAll()
        for panel in outgoing {
            // State returns to idle before the fade is finished. The outgoing
            // panel must not eat a click intended for the newly activated app
            // or overlap a fresh Dock Peek with live hit targets.
            panel.ignoresMouseEvents = true
            (panel.contentView as? SwitcherSurfaceView)?.animateMaterializeOut(reduceMotion: reduceMotion)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = reduceMotion ? 0.1 : 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                // AppKit calls this on the main thread but types it as
                // nonisolated, so state the guarantee rather than hopping
                // through a Task and ordering the panel out a frame later.
                MainActor.assumeIsolated { panel.orderOut(nil) }
            })
        }
    }

    private func clear() {
        preparation?.cancel()
        previewFill?.cancel()
        previewFill = nil
        previewRefresh?.cancel()
        previewRefresh = nil
        closeVerificationTasks.values.forEach { $0.cancel() }
        closeVerificationTasks.removeAll()
        presentationRevision += 1
        windows.removeAll()
        preparation = nil
        pendingOffset = 0
        activateWhenReady = false
        state = .idle
    }
}
