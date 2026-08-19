import AppKit
import OrbitSwitchCore
import ServiceManagement
import SwiftUI

enum ShortcutUpdateResult {
    case accepted
    case warning(String)
    case rejected(String)
}

@MainActor
final class AppState: ObservableObject {
    let settings: SettingsStore
    @Published private(set) var shortcutStatus = "Shortcuts active"
    @Published private(set) var permissionStatus = PermissionService.status
    @Published private(set) var launchAtLoginStatus = AppState.currentLaunchAtLoginStatus()
    @Published private(set) var launchAtLoginError: String?

    /// One discovery actor and one activator for the whole app. Sharing them
    /// means the switcher and Dock Peek draw from a single bounded thumbnail
    /// cache with a single purge path, rather than two of each.
    private let overlay: SwitcherOverlayController
    private let dockPeek: DockPeekController
    private var shortcutManager: GlobalShortcutManager?
    private var started = false
    private var appliedSettings: AppSettings
    private var onboardingWindow: NSWindow?
    private var heldConfirmationModifiers: ShortcutModifiers = []
    private var modifierReleaseTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isReconcilingSettings = false

    init() {
        let discovery = WindowDiscoveryService()
        let activator = AccessibilityWindowController()
        overlay = SwitcherOverlayController(discovery: discovery, activator: activator)
        dockPeek = DockPeekController(discovery: discovery, activator: activator)
        let store = SettingsStore()
        settings = store
        appliedSettings = store.value
        store.onChange = { [weak self] value in self?.settingsDidChange(value) }
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.start()
        }
    }

    func start() {
        guard !started else { return }
        started = true
        do {
            shortcutManager = try GlobalShortcutManager()
            try registerShortcuts(from: settings.value)
        } catch {
            shortcutManager?.unregisterAll()
            shortcutStatus = error.localizedDescription
            Log.shortcuts.error("Shortcut setup failed: \(error.localizedDescription, privacy: .public)")
        }
        applyAppearance(settings.value)
        overlay.onStateChange = { [weak self] state in
            self?.dockPeek.setSuppressed(state != .idle)
        }
        dockPeek.apply(settings: settings.value)
        reconcileLaunchAtLoginAtStart()
        installWorkspaceObservers()
        refreshPermissions()
        refreshLaunchAtLoginStatus()
        if !settings.value.onboardingComplete { showOnboarding() }
    }

    func openSwitcher() {
        stopWaitingForModifierRelease()
        overlay.showOrAdvance(settings: settings.value)
    }

    func dismissSwitcher() {
        stopWaitingForModifierRelease()
        overlay.dismiss()
    }

    func toggleShortcutPause() {
        let previous = settings.value
        var candidate = previous
        candidate.shortcutsPaused.toggle()
        do {
            try registerShortcuts(from: candidate)
        } catch {
            let message = restoreShortcuts(after: error, previous: previous)
            shortcutStatus = message
            return
        }
        // Registration is the side effect that can fail, so persist only after
        // it succeeds. Pre-advancing appliedSettings prevents onChange from
        // registering the same complete set a second time.
        appliedSettings = candidate
        settings.value = candidate
    }

    func refreshPermissions() {
        let status = PermissionService.status
        guard status != permissionStatus else { return }
        let screenRecordingWasRevoked = permissionStatus.screenRecording && !status.screenRecording
        let accessibilityChanged = permissionStatus.accessibility != status.accessibility
        permissionStatus = status
        if screenRecordingWasRevoked {
            overlay.purgeCachedPreviews()
            dockPeek.purgeVisiblePreviews()
        }
        // Dock Peek cannot read the Dock without Accessibility, so granting or
        // revoking it starts or stops the hover monitor.
        if accessibilityChanged { dockPeek.apply(settings: settings.value) }
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = Self.currentLaunchAtLoginStatus()
        let actualValue = Self.isLaunchAtLoginRegistered()
        if settings.value.launchAtLogin == actualValue {
            launchAtLoginError = nil
            return
        }
        // Login Items can also be changed in System Settings. When OrbitSwitch
        // becomes active again, make the preference reflect that external
        // decision instead of leaving a stale toggle beside the live status.
        var corrected = settings.value
        corrected.launchAtLogin = actualValue
        appliedSettings = corrected
        isReconcilingSettings = true
        settings.value = corrected
        isReconcilingSettings = false
    }

    func showOnboarding() {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            return
        }
        let root = OnboardingView { [weak self] in self?.completeOnboarding() }
            .environmentObject(self)
            .environmentObject(settings)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "Welcome to OrbitSwitch"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func completeOnboarding() {
        settings.value.onboardingComplete = true
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    func applyShortcut(_ shortcut: ShortcutDefinition?, for action: ShortcutAction, allowingWarning: Bool = false) -> ShortcutUpdateResult {
        if let shortcut, action != .dismiss, !shortcut.isSuitableForGlobalRegistration {
            return .rejected("Global shortcuts require at least one modifier key.")
        }
        if let shortcut, let conflict = ShortcutConflictDetector.conflict(for: shortcut, action: action, configured: settings.value.shortcuts) {
            switch conflict {
            case .duplicate(let other):
                return .rejected("This shortcut is already assigned to \(other.title).")
            case .commonSystemShortcut(let name) where !allowingWarning:
                return .warning("\(name) is commonly controlled by macOS. OrbitSwitch will try it, but the system shortcut may win.")
            case .commonSystemShortcut: break
            }
        }

        let previous = settings.value
        var candidate = previous
        candidate.shortcuts[action] = shortcut
        do {
            try registerShortcuts(from: candidate)
            settings.value = candidate
            shortcutStatus = candidate.shortcutsPaused ? "Shortcuts paused" : "Shortcuts active"
            return .accepted
        } catch {
            return .rejected(restoreShortcuts(after: error, previous: previous))
        }
    }

    func restoreDefaultShortcuts() -> ShortcutUpdateResult {
        var candidate = settings.value
        candidate.shortcuts = AppSettings.defaultShortcuts
        do {
            try registerShortcuts(from: candidate)
            settings.value = candidate
            return .accepted
        } catch {
            return .rejected(restoreShortcuts(after: error, previous: settings.value))
        }
    }

    func requestAccessibility() {
        PermissionService.requestAccessibility()
        refreshPermissions()
    }

    func requestScreenRecording() {
        PermissionService.requestScreenRecording()
        refreshPermissions()
    }

    private func settingsDidChange(_ value: AppSettings) {
        guard !isReconcilingSettings else {
            appliedSettings = value
            return
        }
        var accepted = value
        if value.shortcutsPaused != appliedSettings.shortcutsPaused {
            do { try registerShortcuts(from: value) }
            catch {
                let previous = appliedSettings
                accepted.shortcutsPaused = previous.shortcutsPaused
                shortcutStatus = restoreShortcuts(after: error, previous: previous)
            }
        }
        if value.showDockIcon != appliedSettings.showDockIcon || value.theme != appliedSettings.theme {
            applyAppearance(value)
        }
        if value.launchAtLogin != appliedSettings.launchAtLogin {
            do {
                try applyLaunchAtLogin(value.launchAtLogin)
                launchAtLoginError = nil
            } catch {
                accepted.launchAtLogin = appliedSettings.launchAtLogin
                launchAtLoginError = error.localizedDescription
                Log.app.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
            }
            refreshLaunchAtLoginStatus()
        }
        appliedSettings = accepted
        // Cheap and idempotent: it re-reads every field the peek uses and
        // starts or stops the monitor only when that decision actually changes.
        dockPeek.apply(settings: accepted)
        guard accepted != value else { return }
        isReconcilingSettings = true
        settings.value = accepted
        isReconcilingSettings = false
    }

    private func restoreShortcuts(after candidateError: Error, previous: AppSettings) -> String {
        let candidateMessage = candidateError.localizedDescription
        do {
            try registerShortcuts(from: previous)
            return candidateMessage
        } catch {
            let message = "\(candidateMessage) The previous shortcuts could not be restored: \(error.localizedDescription)"
            Log.shortcuts.error("\(message, privacy: .public)")
            return message
        }
    }

    private func registerShortcuts(from settings: AppSettings) throws {
        guard let shortcutManager else { return }
        shortcutManager.unregisterAll()
        guard !settings.shortcutsPaused else {
            shortcutStatus = "Shortcuts paused"
            return
        }
        do {
            for action in ShortcutAction.allCases where action != .dismiss {
                guard let shortcut = settings.shortcuts[action] else { continue }
                try shortcutManager.register(
                    shortcut,
                    pressed: { [weak self] in self?.handle(action) },
                    released: {}
                )
            }
        } catch {
            shortcutManager.unregisterAll()
            throw error
        }
        shortcutStatus = "Shortcuts active"
    }

    private func handle(_ action: ShortcutAction) {
        if action != .dismiss { beginWaitingForModifierRelease(action: action) }
        switch action {
        case .showNext: overlay.showOrAdvance(settings: settings.value)
        case .previous: overlay.movePrevious(settings: settings.value)
        case .dismiss: dismissSwitcher()
        case .appOnly: overlay.showOrAdvance(settings: settings.value, mode: .onePerApplication)
        case .currentApp: overlay.showOrAdvance(settings: settings.value, mode: .currentApplication)
        }
    }

    private func beginWaitingForModifierRelease(action: ShortcutAction) {
        guard let shortcut = settings.value.shortcuts[action] else { return }
        let modifiers = ShortcutHoldBehavior.confirmationModifiers(for: action, shortcut: shortcut)
        guard !modifiers.isEmpty else { return }
        heldConfirmationModifiers = modifiers
        guard modifierReleaseTimer == nil else { return }
        modifierReleaseTimer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollHeldModifiers() }
        }
    }

    private func pollHeldModifiers() {
        let current = ShortcutModifiers(eventFlags: CGEventSource.flagsState(.combinedSessionState))
        guard !current.isSuperset(of: heldConfirmationModifiers) else { return }
        stopWaitingForModifierRelease()
        overlay.confirm()
    }

    private func stopWaitingForModifierRelease() {
        modifierReleaseTimer?.invalidate()
        modifierReleaseTimer = nil
        heldConfirmationModifiers = []
    }

    private func installWorkspaceObservers() {
        guard workspaceObservers.isEmpty else { return }
        let dismissOnNotification: (Notification.Name, NotificationCenter, Bool) -> NSObjectProtocol = { name, center, purgePreviews in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.dismissSwitcher()
                    self?.dockPeek.dismiss()
                    if purgePreviews {
                        self?.overlay.purgeCachedPreviews()
                        self?.dockPeek.purgeVisiblePreviews()
                    }
                }
            }
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.screensDidSleepNotification
        ].map { dismissOnNotification($0, workspaceCenter, true) }
        // Panels are sized to the screens present when the switcher opened, so
        // unplugging or rearranging a display mid-session would leave one on a
        // screen that no longer exists. Screen parameters post to the default
        // center, not the workspace one. The same event moves every Dock item,
        // so the peek locator's cached Dock element has to go with it.
        workspaceObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.dismissSwitcher()
                    self?.dockPeek.screenParametersChanged()
                }
            }
        )
        // Granting a permission happens in System Settings, so the state that
        // Settings and the menu show is only stale until the user comes back.
        workspaceObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshPermissions()
                    self?.refreshLaunchAtLoginStatus()
                }
            }
        )
    }

    private func applyAppearance(_ settings: AppSettings) {
        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
        NSApp.appearance = switch settings.theme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            switch service.status {
            case .enabled, .requiresApproval: return
            default: try service.register()
            }
        } else {
            switch service.status {
            case .notRegistered, .notFound: return
            default: try service.unregister()
            }
        }
    }

    /// Preferences can outlive an ad-hoc build or be changed independently in
    /// System Settings. On launch, honor the persisted request if possible and
    /// otherwise persist the service's real state so the toggle never starts
    /// out contradicting the status row beside it.
    private func reconcileLaunchAtLoginAtStart() {
        do {
            try applyLaunchAtLogin(settings.value.launchAtLogin)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            Log.app.error("Launch at login reconciliation failed: \(error.localizedDescription, privacy: .public)")
            let actualValue = Self.isLaunchAtLoginRegistered()
            guard settings.value.launchAtLogin != actualValue else { return }
            var corrected = settings.value
            corrected.launchAtLogin = actualValue
            appliedSettings = corrected
            isReconcilingSettings = true
            settings.value = corrected
            isReconcilingSettings = false
        }
    }

    private static func isLaunchAtLoginRegistered() -> Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval: true
        default: false
        }
    }

    private static func currentLaunchAtLoginStatus() -> String {
        switch SMAppService.mainApp.status {
        case .enabled: "Enabled"
        case .requiresApproval: "Requires approval"
        case .notFound: "Unavailable in this build"
        default: "Disabled"
        }
    }
}
