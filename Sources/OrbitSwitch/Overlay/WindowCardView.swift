import AppKit
import OrbitSwitchCore

/// Chrome proportions for a window card. The orbit stack shows one large card
/// at a time, the sidebar strip shows several small ones; both use the same
/// card so labels, controls, and preview behavior stay identical between the
/// two overlay styles.
struct CardMetrics {
    var cornerRadius: CGFloat
    var contentInset: CGFloat
    var footerHeight: CGFloat
    var iconSize: CGFloat
    var appFontSize: CGFloat
    var titleFontSize: CGFloat
    var fallbackFontSize: CGFloat
    var controlDiameter: CGFloat
    var controlSpacing: CGFloat
    var controlInset: CGFloat
    var shadowRadius: CGFloat
    var shadowOffsetY: CGFloat

    static let regular = CardMetrics(
        cornerRadius: 18,
        contentInset: 14,
        footerHeight: 68,
        iconSize: 36,
        appFontSize: 14,
        titleFontSize: 13,
        fallbackFontSize: 16,
        controlDiameter: 26,
        controlSpacing: 9,
        controlInset: 24,
        shadowRadius: 30,
        shadowOffsetY: -12
    )

    /// Drops the label row to a plain inset when nothing would be drawn in it,
    /// so turning the labels off gives the preview that space instead of
    /// leaving a blank band under it. Matters most in the sidebar, where the
    /// row is a third of a tile.
    func resolved(for settings: AppSettings) -> CardMetrics {
        var resolved = self
        switch (settings.showAppName || settings.showWindowTitle, settings.showAppIcon) {
        case (true, _): break
        case (false, true): resolved.footerHeight = iconSize + contentInset
        case (false, false): resolved.footerHeight = contentInset
        }
        return resolved
    }

    static let compact = CardMetrics(
        cornerRadius: 13,
        contentInset: 9,
        footerHeight: 46,
        iconSize: 24,
        appFontSize: 12,
        titleFontSize: 11,
        fallbackFontSize: 12,
        controlDiameter: 19,
        controlSpacing: 6,
        controlInset: 14,
        shadowRadius: 18,
        shadowOffsetY: -6
    )
}

final class WindowCardView: NSView {
    let representedID: CGWindowID
    var onAccessibilityActivate: (() -> Void)?
    var onAccessibilityControlAction: ((WindowControlAction) -> Void)?

    private let imageView = NSImageView()
    private let iconView = NSImageView()
    private let appLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let fallbackLabel = NSTextField(labelWithString: L10n.previewUnavailable)
    /// Purely visual: clicks are hit-tested manually by the surface view through
    /// the card's 3D transform, because AppKit event routing ignores layer
    /// transforms.
    private var controls: [(action: WindowControlAction, view: NSImageView)] = []
    private let controlsEnabled: Bool
    private let metrics: CardMetrics
    private var isSelected = false
    private var controlsHovered = false
    private var controlsAreVisible = false

    init(window: SwitchableWindow, settings: AppSettings, metrics: CardMetrics = .regular) {
        representedID = window.id
        controlsEnabled = settings.showWindowControls
        self.metrics = metrics
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = metrics.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.98).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.55
        layer?.shadowRadius = metrics.shadowRadius
        layer?.shadowOffset = CGSize(width: 0, height: metrics.shadowOffsetY)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = max(6, metrics.cornerRadius - 6)
        imageView.layer?.masksToBounds = true
        if let preview = window.preview {
            updatePreview(preview)
        }

        fallbackLabel.alignment = .center
        fallbackLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        fallbackLabel.font = .systemFont(ofSize: metrics.fallbackFontSize, weight: .medium)
        fallbackLabel.lineBreakMode = .byTruncatingTail
        appLabel.stringValue = window.metadata.appName
        appLabel.font = .systemFont(ofSize: metrics.appFontSize, weight: .semibold)
        appLabel.textColor = .white
        appLabel.lineBreakMode = .byTruncatingTail
        titleLabel.stringValue = window.metadata.title.isEmpty ? "Untitled Window" : window.metadata.title
        titleLabel.font = .systemFont(ofSize: metrics.titleFontSize)
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

        let inset = metrics.contentInset
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -metrics.footerHeight),
            fallbackLabel.leadingAnchor.constraint(greaterThanOrEqualTo: imageView.leadingAnchor, constant: 4),
            fallbackLabel.trailingAnchor.constraint(lessThanOrEqualTo: imageView.trailingAnchor, constant: -4),
            fallbackLabel.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            fallbackLabel.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset + 2),
            iconView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -(metrics.footerHeight - metrics.iconSize) / 2),
            iconView.widthAnchor.constraint(equalToConstant: metrics.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: metrics.iconSize),
            appLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: inset - 4),
            appLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(inset + 2)),
            appLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -(metrics.footerHeight / 2 + 1)),
            titleLabel.leadingAnchor.constraint(equalTo: appLabel.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: appLabel.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: appLabel.bottomAnchor, constant: 1)
        ])
        if controlsEnabled { installControls() }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(window.metadata.appName), \(titleLabel.stringValue)")
        setAccessibilityHelp("Select this window. Press again to activate it.")
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
            view.symbolConfiguration = controlConfiguration(highlighted: false)
            view.alphaValue = 0
            // The transformed card owns pointer hit testing. VoiceOver actions
            // are exposed as custom actions on the card instead of inert image
            // elements that look like buttons but cannot be pressed.
            view.setAccessibilityElement(false)
            addSubview(view)
            return (action, view)
        }
        for (index, control) in controls.enumerated() {
            NSLayoutConstraint.activate([
                control.view.topAnchor.constraint(equalTo: topAnchor, constant: metrics.controlInset),
                control.view.leadingAnchor.constraint(
                    equalTo: leadingAnchor,
                    constant: metrics.controlInset + CGFloat(index) * (metrics.controlDiameter + metrics.controlSpacing)
                ),
                control.view.widthAnchor.constraint(equalToConstant: metrics.controlDiameter),
                control.view.heightAnchor.constraint(equalToConstant: metrics.controlDiameter)
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
            control.view.symbolConfiguration = controlConfiguration(highlighted: control.action == action)
        }
    }

    func setControlsHovered(_ hovered: Bool) {
        controlsHovered = hovered
        updateControlVisibility()
    }

    /// Mono palette: white symbol on a gray circle, brighter circle on hover.
    private func controlConfiguration(highlighted: Bool) -> NSImage.SymbolConfiguration {
        let circle = NSColor(calibratedWhite: highlighted ? 0.44 : 0.24, alpha: highlighted ? 0.98 : 0.92)
        return NSImage.SymbolConfiguration(pointSize: metrics.controlDiameter - 4, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [
                NSColor.white.withAlphaComponent(0.92),
                circle
            ]))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func updatePreview(_ preview: CGImage?) {
        guard let preview else {
            imageView.image = nil
            fallbackLabel.isHidden = false
            return
        }
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
        setAccessibilitySelected(selected)
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        layer?.borderWidth = increaseContrast ? 1.5 : 1
        layer?.borderColor = NSColor.white.withAlphaComponent(
            selected ? (increaseContrast ? 0.75 : 0.22) : (increaseContrast ? 0.45 : 0.12)
        ).cgColor
        layer?.shadowOpacity = selected ? 0.70 : 0.40
        layer?.shadowRadius = selected ? metrics.shadowRadius * 1.13 : metrics.shadowRadius * 0.8
        if !selected {
            controlsHovered = false
            setControlHighlight(nil)
        }
        updateControlVisibility()
        updateAccessibilityActions()
    }

    func setAccessibleVisibility(_ visible: Bool) {
        setAccessibilityHidden(!visible)
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onAccessibilityActivate else { return false }
        onAccessibilityActivate()
        return true
    }

    private func updateAccessibilityActions() {
        guard controlsEnabled, isSelected else {
            setAccessibilityCustomActions([])
            return
        }
        let labels: [(WindowControlAction, String)] = [
            (.close, "Close window"),
            (.minimize, "Minimize window"),
            (.zoom, "Zoom window")
        ]
        setAccessibilityCustomActions(labels.map { action, label in
            NSAccessibilityCustomAction(name: label) { [weak self] in
                guard let self, let handler = self.onAccessibilityControlAction else { return false }
                handler(action)
                return true
            }
        })
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
