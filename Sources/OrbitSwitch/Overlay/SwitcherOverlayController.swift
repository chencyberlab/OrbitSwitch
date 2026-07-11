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
        case idle, preparing, visible(selection: Int), activating, dismissing, permissionBlocked
    }

    private(set) var state = State.idle
    private let discovery: WindowDiscovering
    private let activator: WindowActivating
    private var panels: [SwitcherOverlayWindow] = []
    private var windows: [SwitchableWindow] = []
    private var settings = AppSettings()
    private var preparation: Task<Void, Never>?
    private var pendingOffset = 0
    private var activateWhenReady = false
    private var presentationRevision = 0

    init(discovery: WindowDiscovering = WindowDiscoveryService(), activator: WindowActivating = AccessibilityWindowController()) {
        self.discovery = discovery
        self.activator = activator
    }

    func showOrAdvance(settings: AppSettings, mode: SwitcherMode = .allWindows) {
        switch state {
        case .visible(let selection): move(to: selection + 1)
        case .preparing: pendingOffset += 1
        case .idle, .permissionBlocked: prepare(settings: settings, mode: mode)
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

    private func prepare(settings: AppSettings, mode: SwitcherMode, initialOffset: Int = 0) {
        guard state == .idle || state == .permissionBlocked else { return }
        state = .preparing
        self.settings = settings
        pendingOffset = initialOffset
        activateWhenReady = false
        let canCapture = PermissionService.status.screenRecording
        preparation = Task { [weak self] in
            guard let self else { return }
            var adjusted = settings
            if mode == .onePerApplication { adjusted.groupByApplication = true }
            var discovered = await discovery.discover(settings: adjusted)
            guard !Task.isCancelled else { return }
            if mode == .currentApplication, let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier {
                discovered = discovered.filter { $0.metadata.ownerPID == frontPID }
            }
            windows = discovered
            present()
            guard canCapture, !Task.isCancelled, !windows.isEmpty else { return }
            let captureTargets = windows
            await discovery.capturePreviews(for: captureTargets, settings: adjusted) { [weak self] id, image in
                guard let self, !Task.isCancelled, case .visible = self.state else { return }
                if let index = self.windows.firstIndex(where: { $0.id == id }) {
                    self.windows[index].preview = image
                }
                self.panels.compactMap { $0.contentView as? Flip3DView }.forEach {
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
            let view = Flip3DView(frame: screen.frame)
            let initialSelection = Flip3DLayout.wrappedIndex(pendingOffset, count: windows.count)
            view.configure(windows: windows, selection: initialSelection, settings: settings)
            view.onMove = { [weak self] offset in
                guard let self, case .visible(let selection) = self.state else { return }
                self.move(to: selection + offset)
            }
            view.onConfirm = { [weak self] in self?.confirm() }
            view.onCancel = { [weak self] in self?.dismiss() }
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
        pendingOffset = 0
        presentationRevision += 1
        let revision = presentationRevision
        let panelsToReveal = panels
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.presentationRevision == revision, case .visible = self.state else { return }
            panelsToReveal.compactMap { $0.contentView as? Flip3DView }.forEach { $0.prepareForPresentation() }
            CATransaction.flush()
            panelsToReveal.forEach { $0.alphaValue = 1 }
        }
        if activateWhenReady {
            activateWhenReady = false
            confirm()
        }
    }

    private func move(to proposedSelection: Int) {
        guard !windows.isEmpty else { return }
        let selection = Flip3DLayout.wrappedIndex(proposedSelection, count: windows.count)
        state = .visible(selection: selection)
        panels.compactMap { $0.contentView as? Flip3DView }.forEach { $0.updateSelection(selection) }
    }

    private func closePanels() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }

    private func clear() {
        preparation?.cancel()
        presentationRevision += 1
        windows.removeAll()
        preparation = nil
        pendingOffset = 0
        activateWhenReady = false
        state = .idle
    }
}
