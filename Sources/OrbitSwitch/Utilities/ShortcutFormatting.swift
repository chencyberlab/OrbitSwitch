import AppKit
import OrbitSwitchCore

extension ShortcutModifiers {
    init(eventFlags: NSEvent.ModifierFlags) {
        var result: ShortcutModifiers = []
        if eventFlags.contains(.command) { result.insert(.command) }
        if eventFlags.contains(.option) { result.insert(.option) }
        if eventFlags.contains(.control) { result.insert(.control) }
        if eventFlags.contains(.shift) { result.insert(.shift) }
        if eventFlags.contains(.function) { result.insert(.function) }
        self = result
    }

    init(eventFlags: CGEventFlags) {
        var result: ShortcutModifiers = []
        if eventFlags.contains(.maskCommand) { result.insert(.command) }
        if eventFlags.contains(.maskAlternate) { result.insert(.option) }
        if eventFlags.contains(.maskControl) { result.insert(.control) }
        if eventFlags.contains(.maskShift) { result.insert(.shift) }
        if eventFlags.contains(.maskSecondaryFn) { result.insert(.function) }
        self = result
    }
}

enum ShortcutFormatting {
    static func string(for shortcut: ShortcutDefinition?) -> String {
        guard let shortcut else { return "None" }
        var value = ""
        if shortcut.modifiers.contains(.control) { value += "⌃" }
        if shortcut.modifiers.contains(.option) { value += "⌥" }
        if shortcut.modifiers.contains(.shift) { value += "⇧" }
        if shortcut.modifiers.contains(.command) { value += "⌘" }
        if shortcut.modifiers.contains(.function) { value += "fn " }
        value += keyName(shortcut.keyCode)
        return value
    }

    static func keyName(_ keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
            47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋", 123: "←", 124: "→",
            125: "↓", 126: "↑"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}
