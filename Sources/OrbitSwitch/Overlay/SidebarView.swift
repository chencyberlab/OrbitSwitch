import AppKit
import OrbitSwitchCore

/// The sidebar style: a strip of compact tiles docked to one edge of the
/// display the overlay opened on, in the spirit of Stage Manager. The left and
/// right edges give a vertical column, the top and bottom a horizontal row.
/// Only `sidebarVisibleCount` tiles are on screen at once; moving past either
/// end slides the strip, and the selection itself keeps wrapping, so Tab loops
/// through every window regardless of how many tiles fit.
final class SidebarView: SwitcherSurfaceView {
    /// Distance from the screen's own edges, or from the Dock and menu bar
    /// where those intrude.
    private static let horizontalMargin: CGFloat = 22
    private static let verticalMargin: CGFloat = 20
    /// Room kept beside the strip for the position capsule.
    private static let indicatorGap: CGFloat = 14
    private static let indicatorReserve = SwitcherSurfaceView.indicatorHeight + indicatorGap + 2
    /// How far the selected tile leans out of the strip, toward the screen.
    private static let selectedNudge: CGFloat = 10

    private(set) var placements: [SidebarPlacement] = []
    private(set) var metrics = SidebarMetrics(tileWidth: 0, tileHeight: 0, spacing: 12, capacity: 1)
    private var stripCenter = CGPoint.zero
    private var indicatorCenterX: NSLayoutConstraint?
    private var indicatorBottom: NSLayoutConstraint?
    private var lastViewportStart: Int?

    override var cardMetrics: CardMetrics { .compact }

    /// Selected first: tiles never overlap, so any order hit-tests correctly,
    /// but checking the selection first keeps its controls responsive at the
    /// edges where the scaled-up tile slightly overhangs its neighbors.
    override var hitTestOrder: [Int] {
        guard cards.indices.contains(selection) else { return Array(cards.indices) }
        return [selection] + cards.indices.filter { $0 != selection }
    }

    private var edge: SidebarEdge { settings.sidebarEdge }

    override func indicatorPositionConstraints() -> [NSLayoutConstraint] {
        let centerX = positionIndicator.centerXAnchor.constraint(equalTo: leadingAnchor, constant: 0)
        let bottom = positionIndicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalMargin)
        indicatorCenterX = centerX
        indicatorBottom = bottom
        return [centerX, bottom]
    }

    /// A scrim that is heaviest at the docked edge and thins out across the
    /// screen, so the strip sits on a gradient of its own instead of flattening
    /// the whole desktop.
    override func updateBackgroundDimming(_ percentage: Double) {
        let amount = min(0.85, max(0, percentage / 100))
        // A gradient layer's unit space runs top-down: (0, 0) is its top-left
        // corner, the opposite of the view coordinates around it.
        let anchor: CGPoint = switch edge {
        case .left: CGPoint(x: 0, y: 0.5)
        case .right: CGPoint(x: 1, y: 0.5)
        case .top: CGPoint(x: 0.5, y: 0)
        case .bottom: CGPoint(x: 0.5, y: 1)
        }
        backgroundGradient.locations = [0, 0.45, 1]
        backgroundGradient.startPoint = anchor
        backgroundGradient.endPoint = CGPoint(x: 1 - anchor.x, y: 1 - anchor.y)
        backgroundGradient.colors = [
            NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.08, alpha: min(0.9, amount * 1.05)).cgColor,
            NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.10, alpha: amount * 0.55).cgColor,
            NSColor.black.withAlphaComponent(amount * 0.18).cgColor
        ]
    }

    /// Most of the screen stays uncovered in this style, so a click out there
    /// reads as dismissal rather than a miss.
    override func handleBackgroundClick() {
        onCancel?()
    }

    override func configureBaseCardGeometry() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let insets = safeAreaInsetsForScreen()
        let left = insets.left + Self.horizontalMargin
        let right = bounds.width - insets.right - Self.horizontalMargin
        let bottom = insets.bottom + Self.verticalMargin
        let top = bounds.height - insets.top - Self.verticalMargin
        // The capsule sits past the end of a column but under (or over) a row,
        // so on either axis it comes out of the height before tiles are sized.
        // A row's selected tile also leans across the strip toward the capsule,
        // which a column's leans clear of, so that lean is reserved too.
        let isRow = edge.axis == .horizontal
        let reserve = windows.count > 1 ? Self.indicatorReserve + (isRow ? Self.selectedNudge : 0) : 0
        let availableWidth = max(120, right - left)
        let availableHeight = max(120, top - bottom - reserve)

        metrics = SidebarLayout.metrics(
            count: cards.count,
            preferredCapacity: settings.sidebarVisibleCount,
            preferredTileWidth: settings.sidebarTileWidth,
            axis: edge.axis,
            availableWidth: Double(availableWidth),
            availableHeight: Double(availableHeight),
            footerHeight: Double(resolvedCardMetrics.footerHeight)
        )

        let tileWidth = CGFloat(metrics.tileWidth)
        let tileHeight = CGFloat(metrics.tileHeight)
        // A column is centered in what is left of the height and pushed against
        // its side edge; a row is centered across the width and pushed against
        // the top or bottom.
        stripCenter = switch edge {
        case .left: CGPoint(x: left + tileWidth / 2, y: (bottom + reserve + top) / 2)
        case .right: CGPoint(x: right - tileWidth / 2, y: (bottom + reserve + top) / 2)
        case .top: CGPoint(x: (left + right) / 2, y: top - tileHeight / 2)
        case .bottom: CGPoint(x: (left + right) / 2, y: bottom + tileHeight / 2)
        }

        // The capsule follows the strip rather than the screen edge, so a short
        // list keeps it tucked against the tiles instead of stranding it.
        let indicatorHeight = SwitcherSurfaceView.indicatorHeight
        let rowClearance = tileHeight / 2 + Self.selectedNudge + Self.indicatorGap
        let capsuleBottom: CGFloat = switch edge {
        case .left, .right:
            max(bottom, stripCenter.y - CGFloat(metrics.stripExtent) / 2 - Self.indicatorGap - indicatorHeight)
        case .top:
            max(bottom, stripCenter.y - rowClearance - indicatorHeight)
        case .bottom:
            min(top - indicatorHeight, stripCenter.y + rowClearance)
        }
        indicatorCenterX?.constant = stripCenter.x
        indicatorBottom?.constant = -capsuleBottom

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for card in cards {
            card.layer?.transform = CATransform3DIdentity
            card.frame = NSRect(
                x: stripCenter.x - tileWidth / 2,
                y: stripCenter.y - tileHeight / 2,
                width: tileWidth,
                height: tileHeight
            )
        }
        CATransaction.commit()
    }

    override func layoutCards(animated: Bool) {
        guard !cards.isEmpty else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let placements = SidebarLayout.placements(count: cards.count, selection: selection, metrics: metrics)
        self.placements = placements

        // Wrapping from one end of the list to the other lands on a viewport
        // that shares no tile with the previous one. Sliding across that gap
        // would fly the whole strip past several screens of tiles, so the jump
        // is cut instead.
        let viewport = SidebarLayout.viewport(count: cards.count, selection: selection, capacity: metrics.capacity)
        let jumped = lastViewportStart.map { abs(viewport.firstIndex - $0) >= metrics.capacity } ?? false
        lastViewportStart = viewport.firstIndex
        let animated = animated && !jumped

        let lean = selectionLean
        let isVertical = metrics.axis == .vertical
        for (index, card) in cards.enumerated() {
            guard let layer = card.layer else { continue }
            let placement = placements[index]
            let isSelected = index == selection
            let scale = reduceMotion ? (isSelected ? 1 : 0.98) : placement.scale
            let along = CGFloat(placement.offset)
            let across = isSelected ? lean : 0
            var transform = CATransform3DIdentity
            transform = CATransform3DTranslate(
                transform,
                isVertical ? across : along,
                isVertical ? along : across,
                0
            )
            transform = CATransform3DScale(transform, scale, scale, 1)
            apply(
                transform: transform,
                opacity: Float(placement.opacity),
                to: layer,
                animated: animated,
                reduceMotion: reduceMotion
            )
            layer.zPosition = isSelected ? CGFloat(cards.count + 1) : CGFloat(cards.count - abs(placement.slot))
            card.setSelected(isSelected)
            card.setAccessibleVisibility(placement.isVisible)
        }
    }

    /// The selected tile leans across the strip, always toward the middle of
    /// the screen and so away from whichever edge the strip is docked to.
    private var selectionLean: CGFloat {
        switch edge {
        case .left, .bottom: Self.selectedNudge
        case .right, .top: -Self.selectedNudge
        }
    }

    /// Keeps the strip clear of the menu bar and of the Dock, including when
    /// the Dock is on the same edge the strip is docked to.
    private func safeAreaInsetsForScreen() -> NSEdgeInsets {
        guard let screen = window?.screen ?? NSScreen.main else {
            return NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        }
        let frame = screen.frame
        let visible = screen.visibleFrame
        return NSEdgeInsets(
            top: max(0, frame.maxY - visible.maxY),
            left: max(0, visible.minX - frame.minX),
            bottom: max(0, visible.minY - frame.minY),
            right: max(0, frame.maxX - visible.maxX)
        )
    }
}
