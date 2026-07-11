import AppKit
import OrbitSwitchCore
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    let shortcut: ShortcutDefinition?
    let onChange: (ShortcutDefinition?) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onChange = onChange
        button.shortcut = shortcut
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.onChange = onChange
        if !nsView.isRecording { nsView.shortcut = shortcut }
    }
}

final class RecorderButton: NSButton {
    var onChange: ((ShortcutDefinition?) -> Void)?
    var shortcut: ShortcutDefinition? { didSet { updateTitle() } }
    fileprivate(set) var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        setAccessibilityLabel("Record keyboard shortcut")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func beginRecording() {
        isRecording = true
        title = "Type shortcut…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        if event.keyCode == 51 || event.keyCode == 117 {
            finish(with: nil)
            return
        }
        let modifiers = ShortcutModifiers(eventFlags: event.modifierFlags)
        finish(with: ShortcutDefinition(keyCode: event.keyCode, modifiers: modifiers))
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateTitle()
        return super.resignFirstResponder()
    }

    private func finish(with shortcut: ShortcutDefinition?) {
        isRecording = false
        self.shortcut = shortcut
        onChange?(shortcut)
        window?.makeFirstResponder(nil)
    }

    private func updateTitle() {
        guard !isRecording else { return }
        title = ShortcutFormatting.string(for: shortcut)
    }
}
