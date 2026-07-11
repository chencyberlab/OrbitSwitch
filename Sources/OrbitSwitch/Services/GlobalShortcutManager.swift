import Carbon.HIToolbox
import Foundation
import OrbitSwitchCore

@MainActor
protocol GlobalShortcutManaging: AnyObject {
    func register(
        _ shortcut: ShortcutDefinition,
        pressed: @escaping () -> Void,
        released: @escaping () -> Void
    ) throws
    func unregister(_ shortcut: ShortcutDefinition)
    func unregisterAll()
}

enum GlobalShortcutError: LocalizedError {
    case handlerInstallation(OSStatus)
    case registrationFailed(OSStatus)
    case modifierRequired

    var errorDescription: String? {
        switch self {
        case .handlerInstallation(let status): "Could not install the keyboard shortcut handler (\(status))."
        case .registrationFailed(let status): "macOS or another app refused this shortcut (\(status))."
        case .modifierRequired: "Global shortcuts require at least one modifier key."
        }
    }
}

@MainActor
final class GlobalShortcutManager: GlobalShortcutManaging {
    private struct Registration {
        let shortcut: ShortcutDefinition
        let reference: EventHotKeyRef
        let pressed: () -> Void
        let released: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var identifiers: [ShortcutDefinition: UInt32] = [:]
    private var nextIdentifier: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    init() throws {
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard result == noErr else { return result }
                manager.handle(identifier: hotKeyID.id, kind: GetEventKind(event))
                return noErr
            },
            specs.count,
            &specs,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else { throw GlobalShortcutError.handlerInstallation(status) }
    }

    deinit {
        registrations.values.forEach { UnregisterEventHotKey($0.reference) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func register(_ shortcut: ShortcutDefinition, pressed: @escaping () -> Void, released: @escaping () -> Void) throws {
        guard shortcut.isSuitableForGlobalRegistration else { throw GlobalShortcutError.modifierRequired }
        if identifiers[shortcut] != nil { throw GlobalShortcutError.registrationFailed(OSStatus(eventHotKeyExistsErr)) }
        let identifier = nextIdentifier
        nextIdentifier += 1
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: 0x4F_52_42_54, id: identifier) // ORBT
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.modifiers.carbonFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { throw GlobalShortcutError.registrationFailed(status) }
        registrations[identifier] = Registration(shortcut: shortcut, reference: reference, pressed: pressed, released: released)
        identifiers[shortcut] = identifier
    }

    func unregister(_ shortcut: ShortcutDefinition) {
        guard let identifier = identifiers.removeValue(forKey: shortcut),
              let registration = registrations.removeValue(forKey: identifier) else { return }
        UnregisterEventHotKey(registration.reference)
    }

    func unregisterAll() {
        registrations.values.forEach { UnregisterEventHotKey($0.reference) }
        registrations.removeAll()
        identifiers.removeAll()
    }

    private func handle(identifier: UInt32, kind: UInt32) {
        guard let registration = registrations[identifier] else { return }
        if kind == UInt32(kEventHotKeyPressed) { registration.pressed() }
        if kind == UInt32(kEventHotKeyReleased) { registration.released() }
    }
}

private extension ShortcutModifiers {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.function) { flags |= UInt32(kEventKeyModifierFnMask) }
        return flags
    }
}
