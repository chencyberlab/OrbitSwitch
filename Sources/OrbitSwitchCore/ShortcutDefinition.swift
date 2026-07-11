import Foundation

public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let command = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let control = Self(rawValue: 1 << 2)
    public static let shift = Self(rawValue: 1 << 3)
    public static let function = Self(rawValue: 1 << 4)
}

public struct ShortcutDefinition: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: ShortcutModifiers

    public init(keyCode: UInt16, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var isSuitableForGlobalRegistration: Bool { !modifiers.isEmpty }
}

public enum ShortcutAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case showNext
    case previous
    case dismiss
    case appOnly
    case currentApp

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .showNext: "Show switcher / next window"
        case .previous: "Previous window"
        case .dismiss: "Dismiss switcher"
        case .appOnly: "App-only mode"
        case .currentApp: "Current-app windows"
        }
    }
}

public enum ShortcutConflict: Equatable, Sendable {
    case duplicate(ShortcutAction)
    case commonSystemShortcut(String)
}

public enum ShortcutConflictDetector {
    public static func conflict(
        for shortcut: ShortcutDefinition,
        action: ShortcutAction,
        configured: [ShortcutAction: ShortcutDefinition]
    ) -> ShortcutConflict? {
        if let duplicate = configured.first(where: { $0.key != action && $0.value == shortcut })?.key {
            return .duplicate(duplicate)
        }

        let known: [(ShortcutDefinition, String)] = [
            (.init(keyCode: 48, modifiers: [.command]), "Command-Tab"),
            (.init(keyCode: 48, modifiers: [.command, .shift]), "Command-Shift-Tab"),
            (.init(keyCode: 49, modifiers: [.command]), "Command-Space"),
            (.init(keyCode: 50, modifiers: [.command]), "Command-Backtick"),
            (.init(keyCode: 126, modifiers: [.control]), "Control-Up Arrow"),
            (.init(keyCode: 125, modifiers: [.control]), "Control-Down Arrow"),
            (.init(keyCode: 123, modifiers: [.control]), "Control-Left Arrow"),
            (.init(keyCode: 124, modifiers: [.control]), "Control-Right Arrow")
        ]
        return known.first(where: { $0.0 == shortcut }).map { .commonSystemShortcut($0.1) }
    }
}

public enum ShortcutHoldBehavior {
    public static func confirmationModifiers(for action: ShortcutAction, shortcut: ShortcutDefinition) -> ShortcutModifiers {
        var modifiers = shortcut.modifiers
        if action == .previous { modifiers.remove(.shift) }
        return modifiers
    }
}
