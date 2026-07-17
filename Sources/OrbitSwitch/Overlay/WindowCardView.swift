import AppKit
import OrbitSwitchCore

final class WindowCardView: NSView {
    let representedID: CGWindowID
    private let imageView = NSImageView()
    private let iconView = NSImageView()
    private let appLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let fallbackLabel = NSTextField(labelWithString: L10n.previewUnavailable)
    /// Purely visual: clicks are hit-tested manually by Flip3DView through the
    /// card's 3D transform, because AppKit event routing ignores layer transforms.
    private var controls: [(action: WindowControlAction, view: NSImageView)] = []
    private let controlsEnabled: Bool
    private var isSelected = false
    private var controlsHovered = false
    private var controlsAreVisible = false
    private static let controlDiameter: CGFloat = 26
    private static let controlSpacing: CGFloat = 9

    init(window: SwitchableWindow, settings: AppSettings) {
        representedID = window.id
        controlsEnabled = settings.showWindowControls
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.98).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.55
        layer?.shadowRadius = 30
        layer?.shadowOffset = CGSize(width: 0, height: -12)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 12
        imageView.layer?.masksToBounds = true
        if let preview = window.preview {
            updatePreview(preview)
        }

        fallbackLabel.alignment = .center
        fallbackLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        fallbackLabel.font = .systemFont(ofSize: 16, weight: .medium)
        appLabel.stringValue = window.metadata.appName
        appLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        appLabel.textColor = .white
        appLabel.lineBreakMode = .byTruncatingTail
        titleLabel.stringValue = window.metadata.title.isEmpty ? "Untitled Window" : window.metadata.title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.68)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        iconView.image = window.appIcon
        iconView.imageScaling = .scaleProportionallyUpOrDown

        [imageView, fallbackLabel, iconView, appLabel, titleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        iconView.isHidden = !settings.showAppIcon
        appLabel.isHidden = !settings.showAppName
        titleLabel.isHidden = !settings.showWindowTitle

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -68),
            fallbackLabel.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            fallbackLabel.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -15),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),
            appLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            appLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            appLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -35),
            titleLabel.leadingAnchor.constraint(equalTo: appLabel.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: appLabel.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: appLabel.bottomAnchor, constant: 1)
        ])
        if controlsEnabled { installControls() }
        setAccessibilityElement(true)
        setAccessibilityLabel("\(window.metadata.appName), \(titleLabel.stringValue)")
    }

    private func installControls() {
        // .circle.fill variants: the circle is part of the glyph, so every
        // button gets an identical outline at the same point size.
        let symbols: [(WindowControlAction, String, String)] = [
            (.close, "xmark.circle.fill", "Close window"),
            (.minimize, "minus.circle.fill", "Minimize window"),
            (.zoom, "arrow.up.left.and.arrow.down.right.circle.fill", "Zoom window")
        ]
        controls = symbols.map { action, symbolName, label in
            let view = NSImageView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.imageScaling = .scaleProportionallyUpOrDown
            view.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
            view.symbolConfiguration = Self.controlConfiguration(highlighted: false)
            view.alphaValue = 0
            view.setAccessibilityLabel(label)
            addSubview(view)
            return (action, view)
        }
        for (index, control) in controls.enumerated() {
            NSLayoutConstraint.activate([
                control.view.topAnchor.constraint(equalTo: topAnchor, constant: 24),
                control.view.leadingAnchor.constraint(
                    equalTo: leadingAnchor,
                    constant: 24 + CGFloat(index) * (Self.controlDiameter + Self.controlSpacing)
                ),
                control.view.widthAnchor.constraint(equalToConstant: Self.controlDiameter),
                control.view.heightAnchor.constraint(equalToConstant: Self.controlDiameter)
            ])
        }
    }

    /// Hit-tests the control buttons against a point in this card's own
    /// coordinate space (already mapped through the layer's 3D transform).
    func controlAction(at point: NSPoint) -> WindowControlAction? {
        guard controlsAreVisible else { return nil }
        return controls.first { $0.view.frame.insetBy(dx: -6, dy: -6).contains(point) }?.action
    }

    func setControlHighlight(_ action: WindowControlAction?) {
        for control in controls {
            control.view.symbolConfiguration = Self.controlConfiguration(highlighted: control.action == action)
        }
    }

    func setControlsHovered(_ hovered: Bool) {
        controlsHovered = hovered
        updateControlVisibility()
    }

    /// Mono palette: white symbol on a gray circle, brighter circle on hover.
    private static func controlConfiguration(highlighted: Bool) -> NSImage.SymbolConfiguration {
        let circle = NSColor(calibratedWhite: highlighted ? 0.44 : 0.24, alpha: highlighted ? 0.98 : 0.92)
        return NSImage.SymbolConfiguration(pointSize: controlDiameter - 4, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [
                NSColor.white.withAlphaComponent(0.92),
                circle
            ]))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func updatePreview(_ preview: CGImage?) {
        guard let preview else { return }
        // Previews arrive asynchronously, one by one. A short cross-fade makes
        // each arrival read as continuous motion instead of a hard cut, and a
        // fade stays within what Reduced Motion allows.
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.16
        imageView.layer?.add(transition, forKey: "orbit.previewFade")
        imageView.image = NSImage(cgImage: preview, size: .zero)
        fallbackLabel.isHidden = true
    }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        layer?.borderWidth = increaseContrast ? 1.5 : 1
        layer?.borderColor = NSColor.white.withAlphaComponent(
            selected ? (increaseContrast ? 0.75 : 0.22) : (increaseContrast ? 0.45 : 0.12)
        ).cgColor
        layer?.shadowOpacity = selected ? 0.70 : 0.40
        layer?.shadowRadius = selected ? 34 : 24
        if !selected {
            controlsHovered = false
            setControlHighlight(nil)
        }
        updateControlVisibility()
    }

    private func updateControlVisibility() {
        let shouldShow = controlsEnabled && isSelected && controlsHovered
        guard shouldShow != controlsAreVisible else { return }
        controlsAreVisible = shouldShow
        if !shouldShow { setControlHighlight(nil) }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            controls.forEach { $0.view.animator().alphaValue = shouldShow ? 1 : 0 }
        }
    }
}
