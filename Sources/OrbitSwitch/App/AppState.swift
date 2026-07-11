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

    private let overlay = SwitcherOverlayController()
    private var shortcutManager: GlobalShortcutManager?
    private var started = false
    private var appliedSettings: AppSettings
    private var onboardingWindow: NSWindow?
    private var heldConfirmationModifiers: ShortcutModifiers = []
    private var modifierReleaseTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    init() {
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
        installWorkspaceObservers()
        refreshPermissions()
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
        settings.value.shortcutsPaused.toggle()
    }

    func refreshPermissions() {
        permissionStatus = PermissionService.status
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
            try? registerShortcuts(from: previous)
            return .rejected(error.localizedDescription)
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
            try? registerShortcuts(from: settings.value)
            return .rejected(error.localizedDescription)
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
        if value.shortcutsPaused != appliedSettings.shortcutsPaused {
            do { try registerShortcuts(from: value) }
            catch { shortcutStatus = error.localizedDescription }
        }
        if value.showDockIcon != appliedSettings.showDockIcon || value.theme != appliedSettings.theme {
            applyAppearance(value)
        }
        if value.launchAtLogin != appliedSettings.launchAtLogin {
            applyLaunchAtLogin(value.launchAtLogin)
        }
        appliedSettings = value
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
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.screensDidSleepNotification
        ]
        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.dismissSwitcher() }
            }
        }
    }

    private func applyAppearance(_ settings: AppSettings) {
        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
        NSApp.appearance = switch settings.theme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.app.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
