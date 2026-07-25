import AppKit
import Carbon.HIToolbox
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
        if shortcut.modifiers.contains(.function) { value += "fn" }
        if shortcut.modifiers.contains(.control) { value += "⌃" }
        if shortcut.modifiers.contains(.option) { value += "⌥" }
        if shortcut.modifiers.contains(.shift) { value += "⇧" }
        if shortcut.modifiers.contains(.command) { value += "⌘" }
        value += keyName(shortcut.keyCode)
        return value
    }

    /// Keys whose glyph is fixed regardless of layout. Asking the layout for
    /// these returns control characters (Tab is `\t`, Escape is `\u{1B}`), so
    /// they are resolved first.
    private static let fixedNames: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 71: "⌧", 76: "⌤",
        115: "↖", 116: "⇞", 117: "⌦", 119: "↘", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
        100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13",
        107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19"
    ]

    /// US QWERTY, used only when the current input source exposes no Unicode
    /// layout data — several IMEs (Pinyin, Kotoeri) do not.
    private static let usLayoutNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 50: "`"
    ]

    /// A recorded shortcut is a hardware key code, so the label has to be
    /// derived from the active keyboard layout. Hard-coding US QWERTY would
    /// print "Q" for the key an AZERTY user actually pressed.
    static func keyName(_ keyCode: UInt16) -> String {
        if let fixed = fixedNames[keyCode] { return fixed }
        if let character = layoutCharacter(for: keyCode) { return character }
        return usLayoutNames[keyCode] ?? "Key \(keyCode)"
    }

    private static func layoutCharacter(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(rawLayout).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr, length > 0 else { return nil }
            let text = String(utf16CodeUnits: characters, count: length)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            // Control characters and blanks mean this key has no printable
            // glyph on the current layout; the caller falls back.
            guard !text.isEmpty, text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
                return nil
            }
            return text
        }
    }
}
