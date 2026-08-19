import AppKit
import OrbitSwitchCore

/// The contents of a Dock peek panel: a row — or, for a long window list, a
/// bounded scrolling grid — of `WindowCardView`s on a vibrant rounded backdrop.
///
/// Deliberately not a `SwitcherSurfaceView` subclass. That class exists to
/// arrange cards by layer transform on top of a full-screen scrim, and carries
/// a position capsule, an empty state, and transform-aware hit testing to match.
/// Peek cards sit at ordinary frames, so hit testing is `frame.contains` and
/// hover is a plain tracking area — none of that machinery would earn its keep.
///
/// Scrolling is done by moving the card frames rather than by an `NSScrollView`.
/// The panel is never the key window and its cards are hit-tested and hover-
/// tracked by hand; interposing a scroll view's clip and event handling would
/// complicate both to save an offset subtraction.
final class DockPeekView: NSView {
    var onActivate: ((CGWindowID) -> Void)?
    var onControlAction: ((WindowControlAction, CGWindowID) -> Void)?
    /// Reports the pointer crossing the panel's own boundary, which the global
    /// Dock monitor cannot see because these events belong to this app.
    var onPointerInsideChanged: ((Bool) -> Void)?

    private let backdrop = NSVisualEffectView()
    /// Clips the grid to the panel, so scrolled-away rows are not drawn outside it.
    private let cardHost = NSView()
    private let countIndicator = NSVisualEffectView()
    private let countLabel = NSTextField(labelWithString: "")
    private(set) var cards: [WindowCardView] = []
    private(set) var windows: [SwitchableWindow] = []
    private var metrics = DockPeekMetrics(
        tileWidth: 220, tileHeight: 174, spacing: 10, padding: 12, columns: 1, visibleRows: 1, totalRows: 1
    )
    private var scrollOffset: CGFloat = 0
    private var hoveredIndex: Int?
    private var cardTrackingAreas: [NSTrackingArea] = []
    private var panelTrackingArea: NSTrackingArea?

    private static let cornerRadius: CGFloat = 16
    private static let indicatorHeight: CGFloat = 22
    /// A wheel notch carries no pixel delta, so it is given roughly a third of
    /// a row rather than a single point.
    private static let lineScrollDistance: CGFloat = 16

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = Self.cornerRadius
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.masksToBounds = true
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)

        cardHost.wantsLayer = true
        cardHost.layer?.cornerRadius = Self.cornerRadius
        cardHost.layer?.cornerCurve = .continuous
        // Card shadows are clipped along with the rows, which is the point: a
        // half-scrolled row must not bleed past the panel's rounded edge.
        cardHost.layer?.masksToBounds = true
        cardHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardHost)

        countIndicator.material = .hudWindow
        countIndicator.blendingMode = .withinWindow
        countIndicator.wantsLayer = true
        countIndicator.layer?.cornerRadius = Self.indicatorHeight / 2
        countIndicator.layer?.cornerCurve = .continuous
        countIndicator.translatesAutoresizingMaskIntoConstraints = false
        countIndicator.isHidden = true
        addSubview(countIndicator)

        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        countLabel.textColor = NSColor.white.withAlphaComponent(0.82)
        countLabel.alignment = .center
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countIndicator.addSubview(countLabel)

        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            cardHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardHost.topAnchor.constraint(equalTo: topAnchor),
            cardHost.bottomAnchor.constraint(equalTo: bottomAnchor),
            countIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            countIndicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            countIndicator.heightAnchor.constraint(equalToConstant: Self.indicatorHeight),
            countLabel.leadingAnchor.constraint(equalTo: countIndicator.leadingAnchor, constant: 10),
            countLabel.trailingAnchor.constraint(equalTo: countIndicator.trailingAnchor, constant: -10),
            countLabel.centerYAnchor.constraint(equalTo: countIndicator.centerYAnchor)
        ])
        updateBackdropAccessibility()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Dock window preview")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Presentation

    func configure(windows: [SwitchableWindow], settings: AppSettings, metrics: DockPeekMetrics, cardMetrics: CardMetrics) {
        cards.forEach { $0.removeFromSuperview() }
        self.windows = windows
        self.metrics = metrics
        hoveredIndex = nil
        scrollOffset = 0
        cards = windows.map { window in
            let card = WindowCardView(window: window, settings: settings, metrics: cardMetrics)
            card.onAccessibilityActivate = { [weak self] in self?.onActivate?(window.id) }
            card.onAccessibilityControlAction = { [weak self] action in
                self?.onControlAction?(action, window.id)
            }
            cardHost.addSubview(card)
            return card
        }
        setFrameSize(metrics.contentSize)
        updateCountIndicator()
        layoutCards()
    }

    func updatePreview(id: CGWindowID, image: CGImage) {
        cards.first(where: { $0.representedID == id })?.updatePreview(image)
        if let index = windows.firstIndex(where: { $0.id == id }) { windows[index].preview = image }
    }

    func clearPreviews() {
        for index in windows.indices { windows[index].preview = nil }
        cards.forEach { $0.updatePreview(nil) }
    }

    /// Drops one confirmed-closed window's card in place. The panel keeps its
    /// frame: resizing it under the pointer would move every remaining card out
    /// from under the cursor mid-click.
    func removeWindow(id: CGWindowID) {
        guard let index = windows.firstIndex(where: { $0.id == id }), cards.indices.contains(index) else { return }
        cards.remove(at: index).removeFromSuperview()
        windows.remove(at: index)
        if let hoveredIndex, hoveredIndex >= index { self.hoveredIndex = nil }
        updateCountIndicator()
        layoutCards()
    }

    /// Marks a card minimized without re-capturing it; the thumbnail on screen
    /// is the last good look at that window.
    func markMinimized(id: CGWindowID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].metadata.isMinimized = true
    }

    private func updateCountIndicator() {
        countIndicator.isHidden = !metrics.isScrollable
        guard metrics.isScrollable else { return }
        countLabel.stringValue = "\(windows.count) windows"
        countIndicator.setAccessibilityLabel("\(windows.count) windows, scroll for more")
    }

    /// Grid coordinates are the full document's; the panel shows a window onto
    /// it, so every card is shifted by however far that window has travelled.
    private func layoutCards() {
        let size = CGSize(width: metrics.tileWidth, height: metrics.tileHeight)
        let shift = metrics.documentSize.height - metrics.contentSize.height - scrollOffset
        for (index, card) in cards.enumerated() {
            let origin = metrics.cardOrigin(at: index)
            card.frame = CGRect(
                origin: CGPoint(x: origin.x, y: origin.y - shift),
                size: size
            )
            card.setSelected(index == hoveredIndex)
        }
        updateTrackingAreas()
    }

    // MARK: - Scrolling

    override func scrollWheel(with event: NSEvent) {
        guard metrics.isScrollable else { return }
        let delta = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY
            : event.scrollingDeltaY * Self.lineScrollDistance
        let proposed = scrollOffset - delta
        let clamped = min(max(proposed, 0), metrics.maximumScrollOffset)
        guard clamped != scrollOffset else { return }
        scrollOffset = clamped
        layoutCards()
        // Cards moved under a stationary pointer, so whatever is under it now is
        // what should look hovered.
        if let point = window?.mouseLocationOutsideOfEventStream {
            setHovered(cardIndex(at: convert(point, from: nil)))
        }
    }

    // MARK: - Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        cardTrackingAreas.forEach(removeTrackingArea)
        cardTrackingAreas.removeAll()
        if let panelTrackingArea { removeTrackingArea(panelTrackingArea) }

        // The panel-wide area reports crossings of the panel boundary and
        // supplies moved events for control-button highlighting; a per-card
        // area is what actually drives hover, because enter/exit is delivered
        // to a non-key window where moved events are not guaranteed to be.
        let panelArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: ["panel": true]
        )
        addTrackingArea(panelArea)
        panelTrackingArea = panelArea

        for (index, card) in cards.enumerated() {
            // A scrolled-away card is still geometrically where its frame says,
            // so its tracking area is clipped to the panel or it would report
            // hover for a card nobody can see.
            let visible = card.frame.intersection(bounds)
            guard !visible.isEmpty else { continue }
            let area = NSTrackingArea(
                rect: visible,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: ["index": index]
            )
            addTrackingArea(area)
            cardTrackingAreas.append(area)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard let info = event.trackingArea?.userInfo else { return }
        if info["panel"] != nil {
            onPointerInsideChanged?(true)
            return
        }
        guard let index = info["index"] as? Int else { return }
        setHovered(index)
    }

    override func mouseExited(with event: NSEvent) {
        guard let info = event.trackingArea?.userInfo else { return }
        if info["panel"] != nil {
            setHovered(nil)
            onPointerInsideChanged?(false)
            return
        }
        guard let index = info["index"] as? Int, index == hoveredIndex else { return }
        setHovered(nil)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = cardIndex(at: point) else {
            setHovered(nil)
            return
        }
        if index != hoveredIndex { setHovered(index) }
        let card = cards[index]
        card.setControlHighlight(card.controlAction(at: convert(point, to: card)))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = cardIndex(at: point) else { return }
        let card = cards[index]
        if let action = card.controlAction(at: convert(point, to: card)) {
            onControlAction?(action, card.representedID)
        } else {
            onActivate?(card.representedID)
        }
    }

    private func setHovered(_ index: Int?) {
        guard index != hoveredIndex else { return }
        if let previous = hoveredIndex, cards.indices.contains(previous) {
            cards[previous].setControlsHovered(false)
            cards[previous].setControlHighlight(nil)
            cards[previous].setSelected(false)
        }
        hoveredIndex = index
        guard let index, cards.indices.contains(index) else { return }
        // `WindowCardView` only reveals its controls for a card that is both
        // selected and hovered, so hover here means both.
        cards[index].setSelected(true)
        cards[index].setControlsHovered(true)
    }

    /// Only a card the panel is actually showing can be hit; a scrolled-away one
    /// still has a frame, but nothing of it is on screen.
    private func cardIndex(at point: NSPoint) -> Int? {
        guard bounds.contains(point) else { return nil }
        return cards.firstIndex { $0.frame.contains(point) }
    }

    /// Reduce Transparency swaps the vibrant backdrop for a solid one, matching
    /// how the switcher's position capsule behaves.
    private func updateBackdropAccessibility() {
        let workspace = NSWorkspace.shared
        if workspace.accessibilityDisplayShouldReduceTransparency {
            backdrop.state = .inactive
            backdrop.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.97).cgColor
            countIndicator.state = .inactive
            countIndicator.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.95).cgColor
        } else {
            backdrop.state = .active
            backdrop.layer?.backgroundColor = nil
            countIndicator.state = .active
            countIndicator.layer?.backgroundColor = nil
        }
        let increaseContrast = workspace.accessibilityDisplayShouldIncreaseContrast
        backdrop.layer?.borderWidth = increaseContrast ? 1 : 0.5
        backdrop.layer?.borderColor = NSColor.white.withAlphaComponent(increaseContrast ? 0.5 : 0.14).cgColor
        countIndicator.layer?.borderWidth = increaseContrast ? 1 : 0.5
        countIndicator.layer?.borderColor = NSColor.white.withAlphaComponent(increaseContrast ? 0.5 : 0.14).cgColor
    }
}
