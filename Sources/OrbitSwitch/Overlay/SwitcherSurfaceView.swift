import AppKit
import OrbitSwitchCore

/// Everything an overlay style shares: the scrim, the empty state, the position
/// capsule, keyboard and scroll navigation, and transform-aware hit testing.
/// Subclasses own only where the cards go — `Flip3DView` arranges them as a
/// perspective staircase, `SidebarView` as a strip docked to one screen edge.
///
/// Cards are positioned by CALayer transforms in both styles, so their frames
/// all sit on a common base — one shared rect in the sidebar, a shared center
/// in the orbit stack — and pointer events must be mapped through each layer's
/// transform rather than through AppKit's view hierarchy.
class SwitcherSurfaceView: NSView {
    /// Height of the position capsule. Subclasses place the capsule themselves
    /// and need to know how tall it will be, so this is the single source.
    static let indicatorHeight: CGFloat = 28

    var onMove: ((Int) -> Void)?
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
    var onControlAction: ((WindowControlAction, CGWindowID) -> Void)?

    let background = NSView()
    /// Holds every card, so the stack always composites above the scrim.
    let cardHost = NSView()
    let backgroundGradient = CAGradientLayer()
    let positionIndicator = NSVisualEffectView()
    private let emptyLabel = NSTextField(labelWithString: L10n.noWindows)
    private let positionLabel = NSTextField(labelWithString: "")
    private(set) var cards: [WindowCardView] = []
    private(set) var windows: [SwitchableWindow] = []
    private(set) var selection = 0
    private(set) var settings = AppSettings()
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
        background.layer = backgroundGradient
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)
        // The cards are children of their own view rather than siblings of the
        // scrim. Sibling order — subview index, sublayer index, zPosition — did
        // not reliably keep the scrim behind cards carrying 3D transforms, and
        // a scrim painting over the stack dims the cards, their labels, and the
        // position capsule along with the desktop. Containment cannot fail that
        // way, and it keeps the perspective a card style installs on this host
        // off the scrim, which must stay flat against the screen.
        cardHost.wantsLayer = true
        cardHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardHost)
        updateBackgroundDimming(settings.backgroundBlur)
        emptyLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        // The scrim is dark in every theme, so this cannot use a semantic label
        // color: in Light appearance that resolves to near-black on near-black.
        emptyLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        positionIndicator.material = .hudWindow
        positionIndicator.blendingMode = .withinWindow
        positionIndicator.wantsLayer = true
        positionIndicator.layer?.cornerRadius = Self.indicatorHeight / 2
        positionIndicator.layer?.cornerCurve = .continuous
        positionIndicator.layer?.shadowColor = NSColor.black.cgColor
        positionIndicator.layer?.shadowOpacity = 0.28
        positionIndicator.layer?.shadowRadius = 10
        positionIndicator.layer?.shadowOffset = CGSize(width: 0, height: -3)
        positionIndicator.translatesAutoresizingMaskIntoConstraints = false
        positionIndicator.isHidden = true
        addSubview(positionIndicator)
        updateIndicatorAccessibility()

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
            cardHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardHost.topAnchor.constraint(equalTo: topAnchor),
            cardHost.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            positionIndicator.heightAnchor.constraint(equalToConstant: Self.indicatorHeight),
            positionLabel.leadingAnchor.constraint(equalTo: positionIndicator.leadingAnchor, constant: 14),
            positionLabel.trailingAnchor.constraint(equalTo: positionIndicator.trailingAnchor, constant: -14),
            positionLabel.centerYAnchor.constraint(equalTo: positionIndicator.centerYAnchor)
        ])
        NSLayoutConstraint.activate(indicatorPositionConstraints())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Style hooks

    /// Card chrome proportions for this style.
    var cardMetrics: CardMetrics { .regular }

    /// Those proportions with the label row sized for what the settings
    /// actually show. Layout code must use this, not `cardMetrics`.
    var resolvedCardMetrics: CardMetrics { cardMetrics.resolved(for: settings) }

    /// Where the position capsule sits. Called once, from the initializer.
    func indicatorPositionConstraints() -> [NSLayoutConstraint] {
        [
            positionIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            positionIndicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -26)
        ]
    }

    /// Resets every card to the style's base geometry, from which layer
    /// transforms place it. Called whenever the surface size changes.
    func configureBaseCardGeometry() {}

    /// Applies the style's transforms to each card for the current selection.
    func layoutCards(animated: Bool) {}

    /// Card indices ordered front to back, for pointer hit testing and for the
    /// order the cards are stacked in.
    var hitTestOrder: [Int] { Array(cards.indices) }

    /// A click that missed every card. The orbit stack normally ignores it;
    /// with no cards there is nothing else to click, so the empty overlay must
    /// still offer a pointer path out. Sidebar overrides this to dismiss for
    /// every background click.
    func handleBackgroundClick() {
        if windows.isEmpty { onCancel?() }
    }

    func updateBackgroundDimming(_ percentage: Double) {
        let amount = min(0.85, max(0, percentage / 100))
        backgroundGradient.locations = [0, 0.55, 1]
        backgroundGradient.startPoint = CGPoint(x: 0, y: 1)
        backgroundGradient.endPoint = CGPoint(x: 1, y: 0)
        backgroundGradient.colors = [
            NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.08, alpha: min(0.9, amount * 1.12)).cgColor,
            NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.13, alpha: amount * 0.72).cgColor,
            NSColor.black.withAlphaComponent(amount).cgColor
        ]
    }

    // MARK: - Presentation

    func configure(windows: [SwitchableWindow], selection: Int, settings: AppSettings) {
        cards.forEach { $0.removeFromSuperview() }
        self.windows = windows
        self.settings = settings
        updateBackgroundDimming(settings.backgroundBlur)
        self.selection = Flip3DLayout.wrappedIndex(selection, count: windows.count)
        updatePositionIndicator()
        lastLayoutSize = .zero
        let metrics = resolvedCardMetrics
        cards = windows.map { window in
            let card = WindowCardView(window: window, settings: settings, metrics: metrics)
            card.onAccessibilityActivate = { [weak self] in
                self?.activateCardForAccessibility(id: window.id)
            }
            card.onAccessibilityControlAction = { [weak self] action in
                self?.onControlAction?(action, window.id)
            }
            cardHost.addSubview(card)
            return card
        }
        emptyLabel.isHidden = !windows.isEmpty
        if bounds.width > 0, bounds.height > 0 {
            configureBaseCardGeometry()
            lastLayoutSize = bounds.size
            backgroundGradient.frame = bounds
            applyCardLayout(animated: false)
        }
        needsLayout = true
    }

    func updatePreview(id: CGWindowID, image: CGImage) {
        cards.first(where: { $0.representedID == id })?.updatePreview(image)
        if let index = windows.firstIndex(where: { $0.id == id }) { windows[index].preview = image }
    }

    func clearPreviews() {
        for index in windows.indices { windows[index].preview = nil }
        cards.forEach { $0.updatePreview(nil) }
    }

    /// Removes one confirmed-closed window without rebuilding every surviving
    /// card. Recreating the whole view hierarchy from the delayed AX close
    /// verification can leave the new layers without a committed frame until
    /// the next input event; keeping the existing layers also preserves their
    /// previews and makes the remaining layout update immediate.
    func removeWindow(id: CGWindowID, selection: Int) {
        guard let index = windows.firstIndex(where: { $0.id == id }),
              cards.indices.contains(index) else { return }
        cards.remove(at: index).removeFromSuperview()
        windows.remove(at: index)
        self.selection = Flip3DLayout.wrappedIndex(selection, count: windows.count)
        updatePositionIndicator()
        emptyLabel.isHidden = !windows.isEmpty

        if bounds.width > 0, bounds.height > 0 {
            configureBaseCardGeometry()
            lastLayoutSize = bounds.size
            backgroundGradient.frame = background.bounds
            applyCardLayout(animated: true)
            layoutSubtreeIfNeeded()
            displayIfNeeded()
            CATransaction.flush()
        }
        needsLayout = true
    }

    func updateSelection(_ selection: Int) {
        self.selection = Flip3DLayout.wrappedIndex(selection, count: windows.count)
        updatePositionIndicator()
        applyCardLayout(animated: true)
    }

    private func activateCardForAccessibility(id: CGWindowID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        if index == selection {
            onConfirm?()
        } else {
            onMove?(index - selection)
        }
    }

    func prepareForPresentation() {
        layoutSubtreeIfNeeded()
        configureBaseCardGeometry()
        lastLayoutSize = bounds.size
        backgroundGradient.frame = background.bounds
        applyCardLayout(animated: false)
        displayIfNeeded()
        CATransaction.flush()
    }

    /// Arrival and dismissal share one path: the whole surface scales slightly
    /// while the panel fades, so it reads as a material arriving and leaving
    /// rather than an opaque pop. Under Reduce Motion the scale step is dropped
    /// and only the controller's cross-fade remains.
    func animateMaterializeIn(reduceMotion: Bool) {
        guard let layer, !reduceMotion else { return }
        let spring = SpringAnimation.make(keyPath: "transform", response: 0.38)
        spring.fromValue = NSValue(caTransform3D: CATransform3DMakeScale(0.94, 0.94, 1))
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        layer.add(spring, forKey: "orbit.materialize")
    }

    func animateMaterializeOut(reduceMotion: Bool) {
        guard let layer, !reduceMotion else { return }
        let target = CATransform3DMakeScale(0.96, 0.96, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = target
        CATransaction.commit()
        let shrink = CABasicAnimation(keyPath: "transform")
        shrink.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        shrink.toValue = NSValue(caTransform3D: target)
        shrink.duration = 0.14
        shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.add(shrink, forKey: "orbit.materialize")
    }

    /// Places the cards and then puts the view hierarchy in the same order, so
    /// what is painted on top is what the style says is in front.
    private func applyCardLayout(animated: Bool) {
        layoutCards(animated: animated)
        restackCards()
        updateAccessibilityFrames()
    }

    /// Cards are placed with layer transforms, which AppKit's default
    /// accessibility geometry does not follow. Publish each transformed
    /// bounding box in screen coordinates so VoiceOver highlights the tile it
    /// is actually reading instead of the shared untransformed base frame.
    private func updateAccessibilityFrames() {
        guard let window, let rootLayer = cardHost.layer else { return }
        for card in cards {
            guard let cardLayer = card.layer else { continue }
            let hostRect = cardLayer.convert(cardLayer.bounds, to: rootLayer)
            guard hostRect.origin.x.isFinite, hostRect.origin.y.isFinite,
                  hostRect.width.isFinite, hostRect.height.isFinite else { continue }
            let windowRect = cardHost.convert(hostRect, to: nil)
            card.setAccessibilityFrame(window.convertToScreen(windowRect))
        }
    }

    /// Card layers are siblings under one layer-backed view, and AppKit — not
    /// this code — owns their compositing order there, so `layer.zPosition` is
    /// not a dependable stacking control. When it is disregarded the cards sit
    /// in the order they were added, which puts everything ahead of the
    /// selection in the window list on top of the selected card. Keeping the
    /// depth order in `subviews` is what makes the front card actually front.
    private func restackCards() {
        guard !cards.isEmpty else { return }
        let backToFront = hitTestOrder.reversed().compactMap {
            cards.indices.contains($0) ? cards[$0] : nil
        }
        guard backToFront.count == cards.count, backToFront != cardHost.subviews else { return }
        cardHost.subviews = backToFront
    }

    /// AppKit syncs a view's frame onto its backing layer during the display
    /// cycle, and that sync clears the layer's `transform`. Every path that
    /// places cards sets their frames first, so the placements applied right
    /// after are wiped before the first frame is drawn and the whole stack
    /// collapses onto the shared base geometry. Re-applying here — after
    /// layout, once the frames are committed — is what makes the arrangement
    /// survive the pass that created the layers.
    override func viewWillDraw() {
        super.viewWillDraw()
        applyCardLayout(animated: false)
    }

    override func layout() {
        super.layout()
        backgroundGradient.frame = background.bounds
        if lastLayoutSize != bounds.size {
            configureBaseCardGeometry()
            lastLayoutSize = bounds.size
        }
        applyCardLayout(animated: false)
    }

    // MARK: - Input

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
        guard let hit = cardHit(at: point) else {
            handleBackgroundClick()
            return
        }
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

    /// Maps the click through each card layer's transform, front to back, to
    /// find what was really hit. AppKit's own hit testing cannot: the cards all
    /// sit on one base geometry and only their layer transforms tell them
    /// apart.
    private func cardHit(at point: NSPoint) -> (index: Int, localPoint: NSPoint)? {
        guard let rootLayer = cardHost.layer else { return nil }
        for index in hitTestOrder {
            guard cards.indices.contains(index), let cardLayer = cards[index].layer else { continue }
            guard (cardLayer.presentation()?.opacity ?? cardLayer.opacity) > 0.1 else { continue }
            let localPoint = cardLayer.convert(point, from: rootLayer)
            guard localPoint.x.isFinite, localPoint.y.isFinite,
                  cardLayer.bounds.contains(localPoint) else { continue }
            return (index, localPoint)
        }
        return nil
    }

    // MARK: - Shared card animation

    func apply(transform: CATransform3D, opacity: Float, to layer: CALayer, animated: Bool, reduceMotion: Bool) {
        let previousTransform = layer.presentation()?.transform ?? layer.transform
        let previousOpacity = layer.presentation()?.opacity ?? layer.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = transform
        layer.opacity = opacity
        CATransaction.commit()
        guard animated else { return }

        // Reduced motion means a gentler equivalent, not less feedback:
        // cross-fade instead of moving cards through space.
        guard !reduceMotion else {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = previousOpacity
            fade.toValue = opacity
            fade.duration = 0.12
            layer.add(fade, forKey: "orbit.opacity")
            return
        }

        // A critically damped spring re-targeted from the live presentation
        // value: held-down keys interrupt mid-flight and the motion retargets
        // gracefully instead of restarting a fixed-duration ease curve.
        let spring = SpringAnimation.make(keyPath: "transform", response: settings.animationDuration)
        spring.fromValue = NSValue(caTransform3D: previousTransform)
        spring.toValue = NSValue(caTransform3D: transform)
        layer.add(spring, forKey: "orbit.transform")

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = previousOpacity
        opacityAnimation.toValue = opacity
        opacityAnimation.duration = min(settings.animationDuration, 0.18)
        layer.add(opacityAnimation, forKey: "orbit.opacity")
    }

    // MARK: - Position capsule

    private func updatePositionIndicator() {
        guard windows.count > 1 else {
            positionIndicator.isHidden = true
            return
        }
        positionLabel.stringValue = "\(selection + 1)  /  \(windows.count)"
        positionLabel.setAccessibilityLabel("Window \(selection + 1) of \(windows.count)")
        positionIndicator.isHidden = false
    }

    /// Honors Reduce Transparency (solid surface instead of vibrancy) and
    /// Increase Contrast (stronger border) on the floating position indicator.
    private func updateIndicatorAccessibility() {
        let workspace = NSWorkspace.shared
        if workspace.accessibilityDisplayShouldReduceTransparency {
            positionIndicator.state = .inactive
            positionIndicator.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.95).cgColor
        } else {
            positionIndicator.state = .active
            positionIndicator.layer?.backgroundColor = nil
        }
        let increaseContrast = workspace.accessibilityDisplayShouldIncreaseContrast
        positionIndicator.layer?.borderWidth = increaseContrast ? 1 : 0.5
        positionIndicator.layer?.borderColor = NSColor.white.withAlphaComponent(increaseContrast ? 0.5 : 0.14).cgColor
    }
}
