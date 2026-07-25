import AppKit
import OrbitSwitchCore

/// The sidebar style: a vertical strip of compact tiles docked to the left or
/// right edge of the display the overlay opened on, in the spirit of Stage
/// Manager. Only `sidebarVisibleCount` tiles are on screen at once; moving past
/// either end slides the strip, and the selection itself keeps wrapping, so Tab
/// loops through every window regardless of how many tiles fit.
final class SidebarView: SwitcherSurfaceView {
    /// Distance from the screen edge (or the Dock, when it is on this edge).
    private static let horizontalMargin: CGFloat = 22
    private static let verticalMargin: CGFloat = 20
    /// Room kept below the strip for the position capsule.
    private static let indicatorHeight: CGFloat = 28
    private static let indicatorGap: CGFloat = 14
    private static let indicatorReserve = indicatorHeight + indicatorGap + 2
    /// How far the selected tile leans out of the strip, toward the screen.
    private static let selectedNudge: CGFloat = 10

    private(set) var placements: [SidebarPlacement] = []
    private(set) var metrics = SidebarMetrics(tileWidth: 0, tileHeight: 0, spacing: 12, capacity: 1)
    private var columnCenter = CGPoint.zero
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
        backgroundGradient.locations = [0, 0.45, 1]
        backgroundGradient.startPoint = CGPoint(x: edge == .left ? 0 : 1, y: 0.5)
        backgroundGradient.endPoint = CGPoint(x: edge == .left ? 1 : 0, y: 0.5)
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
        let reserve = windows.count > 1 ? Self.indicatorReserve : 0
        let contentBottom = insets.bottom + Self.verticalMargin + reserve
        let contentTop = bounds.height - insets.top - Self.verticalMargin
        let availableHeight = max(120, contentTop - contentBottom)
        let availableWidth = max(120, bounds.width - insets.left - insets.right - Self.horizontalMargin * 2)

        metrics = SidebarLayout.metrics(
            count: cards.count,
            preferredCapacity: settings.sidebarVisibleCount,
            preferredTileWidth: settings.sidebarTileWidth,
            availableWidth: Double(availableWidth),
            availableHeight: Double(availableHeight),
            footerHeight: Double(resolvedCardMetrics.footerHeight)
        )

        let tileWidth = CGFloat(metrics.tileWidth)
        let tileHeight = CGFloat(metrics.tileHeight)
        let centerX = edge == .left
            ? insets.left + Self.horizontalMargin + tileWidth / 2
            : bounds.width - insets.right - Self.horizontalMargin - tileWidth / 2
        columnCenter = CGPoint(x: centerX, y: (contentBottom + contentTop) / 2)

        // The capsule follows the strip rather than the screen edge, so a short
        // list keeps it tucked under the last tile instead of stranding it.
        let columnBottom = columnCenter.y - CGFloat(metrics.columnHeight) / 2
        indicatorCenterX?.constant = centerX
        indicatorBottom?.constant = -max(
            insets.bottom + Self.verticalMargin,
            columnBottom - Self.indicatorGap - Self.indicatorHeight
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for card in cards {
            card.layer?.transform = CATransform3DIdentity
            card.frame = NSRect(
                x: columnCenter.x - tileWidth / 2,
                y: columnCenter.y - tileHeight / 2,
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

        let nudge = edge == .left ? Self.selectedNudge : -Self.selectedNudge
        for (index, card) in cards.enumerated() {
            guard let layer = card.layer else { continue }
            let placement = placements[index]
            let isSelected = index == selection
            let scale = reduceMotion ? (isSelected ? 1 : 0.98) : placement.scale
            var transform = CATransform3DIdentity
            transform = CATransform3DTranslate(transform, isSelected ? nudge : 0, placement.y, 0)
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
