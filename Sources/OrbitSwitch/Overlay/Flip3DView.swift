import AppKit
import OrbitSwitchCore

final class Flip3DView: NSView {
    var onMove: ((Int) -> Void)?
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
    var onControlAction: ((WindowControlAction, CGWindowID) -> Void)?

    private let background = NSView()
    private let backgroundGradient = CAGradientLayer()
    private let emptyLabel = NSTextField(labelWithString: L10n.noWindows)
    private let positionIndicator = NSVisualEffectView()
    private let positionLabel = NSTextField(labelWithString: "")
    private var cards: [WindowCardView] = []
    private var windows: [SwitchableWindow] = []
    private var placements: [Flip3DPlacement] = []
    private var selection = 0
    private var settings = AppSettings()
    private var lastLayoutSize = CGSize.zero
    private var accumulatedScroll: CGFloat = 0
    private var lastScrollStepTime: TimeInterval = 0
    private var hoverTrackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        background.wantsLayer = true
        updateBackgroundDimming(settings.backgroundBlur)
        backgroundGradient.locations = [0, 0.55, 1]
        backgroundGradient.startPoint = CGPoint(x: 0, y: 1)
        backgroundGradient.endPoint = CGPoint(x: 1, y: 0)
        background.layer = backgroundGradient
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)
        emptyLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        positionIndicator.material = .hudWindow
        positionIndicator.blendingMode = .withinWindow
        positionIndicator.state = .active
        positionIndicator.wantsLayer = true
        positionIndicator.layer?.cornerRadius = 14
        positionIndicator.layer?.cornerCurve = .continuous
        positionIndicator.layer?.borderWidth = 0.5
        positionIndicator.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        positionIndicator.layer?.shadowColor = NSColor.black.cgColor
        positionIndicator.layer?.shadowOpacity = 0.28
        positionIndicator.layer?.shadowRadius = 10
        positionIndicator.layer?.shadowOffset = CGSize(width: 0, height: -3)
        positionIndicator.translatesAutoresizingMaskIntoConstraints = false
        positionIndicator.isHidden = true
        addSubview(positionIndicator)

        positionLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        positionLabel.textColor = NSColor.white.withAlphaComponent(0.82)
        positionLabel.alignment = .center
        positionLabel.translatesAutoresizingMaskIntoConstraints = false
        positionIndicator.addSubview(positionLabel)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            positionIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            positionIndicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -26),
            positionIndicator.heightAnchor.constraint(equalToConstant: 28),
            positionLabel.leadingAnchor.constraint(equalTo: positionIndicator.leadingAnchor, constant: 14),
            positionLabel.trailingAnchor.constraint(equalTo: positionIndicator.trailingAnchor, constant: -14),
            positionLabel.centerYAnchor.constraint(equalTo: positionIndicator.centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(windows: [SwitchableWindow], selection: Int, settings: AppSettings) {
        cards.forEach { $0.removeFromSuperview() }
        self.windows = windows
        self.settings = settings
        updateBackgroundDimming(settings.backgroundBlur)
        self.selection = Flip3DLayout.wrappedIndex(selection, count: windows.count)
        updatePositionIndicator()
        lastLayoutSize = .zero
        cards = windows.map { window in
            let card = WindowCardView(window: window, settings: settings)
            addSubview(card, positioned: .above, relativeTo: background)
            return card
        }
        emptyLabel.isHidden = !windows.isEmpty
        if bounds.width > 0, bounds.height > 0 {
            configureBaseCardGeometry()
            lastLayoutSize = bounds.size
            backgroundGradient.frame = bounds
            layoutCards(animated: false)
        }
        needsLayout = true
    }

    func updatePreview(id: CGWindowID, image: CGImage) {
        cards.first(where: { $0.representedID == id })?.updatePreview(image)
        if let index = windows.firstIndex(where: { $0.id == id }) { windows[index].preview = image }
    }

    func updateSelection(_ selection: Int) {
        self.selection = Flip3DLayout.wrappedIndex(selection, count: windows.count)
        updatePositionIndicator()
        layoutCards(animated: true)
    }

    func prepareForPresentation() {
        layoutSubtreeIfNeeded()
        configureBaseCardGeometry()
        lastLayoutSize = bounds.size
        backgroundGradient.frame = background.bounds
        layoutCards(animated: false)
        displayIfNeeded()
        CATransaction.flush()
    }

    override func layout() {
        super.layout()
        backgroundGradient.frame = background.bounds
        if lastLayoutSize != bounds.size {
            configureBaseCardGeometry()
            lastLayoutSize = bounds.size
        }
        layoutCards(animated: false)
    }

    override func keyDown(with event: NSEvent) {
        let pressedShortcut = ShortcutDefinition(
            keyCode: event.keyCode,
            modifiers: ShortcutModifiers(eventFlags: event.modifierFlags)
        )
        if settings.shortcuts[.dismiss] == pressedShortcut {
            onCancel?()
            return
        }
        switch event.keyCode {
        case 53: onCancel?()
        case 36, 76: onConfirm?()
        case 123, 126: onMove?(-1)
        case 124, 125, 48: onMove?(event.modifierFlags.contains(.shift) ? -1 : 1)
        default: super.keyDown(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let amount = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
        guard abs(amount) > 0.01, event.momentumPhase.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime

        if event.hasPreciseScrollingDeltas {
            if event.phase == .began { accumulatedScroll = 0 }
            accumulatedScroll += amount
            guard abs(accumulatedScroll) >= 34, now - lastScrollStepTime >= 0.11 else {
                if event.phase == .ended || event.phase == .cancelled { accumulatedScroll = 0 }
                return
            }
            onMove?(accumulatedScroll > 0 ? -1 : 1)
            accumulatedScroll = 0
            lastScrollStepTime = now
        } else {
            guard now - lastScrollStepTime >= 0.14 else { return }
            onMove?(amount > 0 ? -1 : 1)
            lastScrollStepTime = now
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard cards.indices.contains(selection) else { return }
        let point = convert(event.locationInWindow, from: nil)
        let selectedCard = cards[selection]
        guard let hit = cardHit(at: point), hit.index == selection else {
            selectedCard.setControlsHovered(false)
            selectedCard.setControlHighlight(nil)
            return
        }
        selectedCard.setControlsHovered(true)
        selectedCard.setControlHighlight(selectedCard.controlAction(at: hit.localPoint))
    }

    override func mouseExited(with event: NSEvent) {
        guard cards.indices.contains(selection) else { return }
        cards[selection].setControlsHovered(false)
        cards[selection].setControlHighlight(nil)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = cardHit(at: point) else { return }
        if hit.index == selection {
            if let action = cards[hit.index].controlAction(at: hit.localPoint) {
                onControlAction?(action, cards[hit.index].representedID)
            } else {
                onConfirm?()
            }
        } else {
            onMove?(hit.index - selection)
        }
    }

    /// Cards are positioned by CALayer 3D transforms, which AppKit hit-testing
    /// ignores (all card frames overlap at the base rect). Map the click through
    /// each card layer's transform, front to back, to find what was really hit.
    private func cardHit(at point: NSPoint) -> (index: Int, localPoint: NSPoint)? {
        guard let rootLayer = layer else { return nil }
        let frontToBack = cards.indices.sorted {
            (placements.indices.contains($0) ? placements[$0].relativeIndex : $0)
                < (placements.indices.contains($1) ? placements[$1].relativeIndex : $1)
        }
        for index in frontToBack {
            guard let cardLayer = cards[index].layer else { continue }
            guard (cardLayer.presentation()?.opacity ?? cardLayer.opacity) > 0.1 else { continue }
            let localPoint = cardLayer.convert(point, from: rootLayer)
            guard localPoint.x.isFinite, localPoint.y.isFinite,
                  cardLayer.bounds.contains(localPoint) else { continue }
            return (index, localPoint)
        }
        return nil
    }

    private func layoutCards(animated: Bool) {
        guard !cards.isEmpty else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let placements = Flip3DLayout.placements(
            count: cards.count,
            selection: selection,
            spacing: reduceMotion ? 24 : settings.cardSpacing,
            angle: reduceMotion ? 0 : settings.stackAngle,
            perspective: reduceMotion ? 0 : settings.perspectiveStrength,
            horizontalTravel: max(180, bounds.width * 0.33),
            verticalTravel: max(120, bounds.height * 0.24)
        )
        self.placements = placements
        for (index, card) in cards.enumerated() {
            guard let layer = card.layer else { continue }
            let placement = placements[index]
            var transform = CATransform3DIdentity
            if !reduceMotion { transform.m34 = -settings.perspectiveStrength }
            transform = CATransform3DTranslate(transform, placement.x, placement.y, placement.z)
            transform = CATransform3DRotate(transform, placement.angleDegrees * .pi / 180, 0, 1, 0)
            transform = CATransform3DScale(transform, placement.scale, placement.scale, 1)
            apply(
                transform: transform,
                opacity: Float(placement.opacity),
                to: layer,
                animated: animated,
                reduceMotion: reduceMotion
            )
            layer.zPosition = CGFloat(cards.count - placement.relativeIndex)
            card.setSelected(index == selection)
        }
    }

    private func configureBaseCardGeometry() {
        let cardWidth = min(820, bounds.width * 0.60)
        let cardHeight = min(560, bounds.height * 0.70)
        let center = CGPoint(x: bounds.width * 0.59, y: bounds.height * 0.45)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for card in cards {
            card.layer?.transform = CATransform3DIdentity
            card.frame = NSRect(
                x: center.x - cardWidth / 2,
                y: center.y - cardHeight / 2,
                width: cardWidth,
                height: cardHeight
            )
        }
        CATransaction.commit()
    }

    private func updatePositionIndicator() {
        guard windows.count > 1 else {
            positionIndicator.isHidden = true
            return
        }
        positionLabel.stringValue = "\(selection + 1)  /  \(windows.count)"
        positionLabel.setAccessibilityLabel("Window \(selection + 1) of \(windows.count)")
        positionIndicator.isHidden = false
    }

    private func updateBackgroundDimming(_ percentage: Double) {
        let amount = min(0.85, max(0, percentage / 100))
        backgroundGradient.colors = [
            NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.08, alpha: min(0.9, amount * 1.12)).cgColor,
            NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.13, alpha: amount * 0.72).cgColor,
            NSColor.black.withAlphaComponent(amount).cgColor
        ]
    }

    private func apply(transform: CATransform3D, opacity: Float, to layer: CALayer, animated: Bool, reduceMotion: Bool) {
        let previousTransform = layer.presentation()?.transform ?? layer.transform
        let previousOpacity = layer.presentation()?.opacity ?? layer.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = transform
        layer.opacity = opacity
        CATransaction.commit()
        guard animated else { return }

        let duration = reduceMotion ? 0.12 : settings.animationDuration
        let transformAnimation = CABasicAnimation(keyPath: "transform")
        transformAnimation.fromValue = NSValue(caTransform3D: previousTransform)
        transformAnimation.toValue = NSValue(caTransform3D: transform)
        transformAnimation.duration = duration
        transformAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(transformAnimation, forKey: "orbit.transform")

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = previousOpacity
        opacityAnimation.toValue = opacity
        opacityAnimation.duration = min(duration, 0.18)
        layer.add(opacityAnimation, forKey: "orbit.opacity")
    }
}
