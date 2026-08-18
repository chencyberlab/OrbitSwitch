import AppKit
import OrbitSwitchCore

/// The orbit style: one large card front and center with the rest receding in a
/// perspective staircase toward a vanishing point.
final class Flip3DView: SwitcherSurfaceView {
    private var placements: [Flip3DPlacement] = []

    override var hitTestOrder: [Int] {
        cards.indices.sorted {
            (placements.indices.contains($0) ? placements[$0].relativeIndex : $0)
                < (placements.indices.contains($1) ? placements[$1].relativeIndex : $1)
        }
    }

    override func layoutCards(animated: Bool) {
        guard !cards.isEmpty else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let perspective = reduceMotion ? 0 : settings.perspectiveStrength
        let placements = Flip3DLayout.placements(
            count: cards.count,
            selection: selection,
            spacing: reduceMotion ? 24 : settings.cardSpacing,
            angle: reduceMotion ? 0 : settings.stackAngle,
            perspective: perspective,
            horizontalTravel: max(180, bounds.width * 0.33),
            verticalTravel: max(120, bounds.height * 0.24)
        )
        self.placements = placements
        applyStackProjection(perspective: perspective)
        for (index, card) in cards.enumerated() {
            guard let layer = card.layer else { continue }
            let placement = placements[index]
            // The projection lives on the superlayer, so this is the card's
            // placement only. Rotating and scaling about the card's own centre
            // keeps its centre on the focal axis, which is what makes the
            // shared depth divisor come out as `w` there.
            let pivot = CGPoint(x: card.bounds.midX, y: card.bounds.midY)
            var transform = CATransform3DMakeTranslation(placement.x, placement.y, placement.z)
            transform = CATransform3DTranslate(transform, pivot.x, pivot.y, 0)
            transform = CATransform3DRotate(transform, placement.angleDegrees * .pi / 180, 0, 1, 0)
            transform = CATransform3DScale(transform, placement.scale, placement.scale, 1)
            transform = CATransform3DTranslate(transform, -pivot.x, -pivot.y, 0)
            apply(
                transform: transform,
                opacity: Float(placement.opacity),
                to: layer,
                animated: animated,
                reduceMotion: reduceMotion
            )
            layer.zPosition = CGFloat(cards.count - placement.relativeIndex)
            card.setSelected(index == selection)
            card.setAccessibleVisibility(placement.opacity > 0)
        }
    }

    /// Where the stack converges: every card's base rect is centred here, and
    /// it is the vanishing point the shared projection uses.
    private var stackFocus: CGPoint {
        CGPoint(x: bounds.width * 0.59, y: bounds.height * 0.45)
    }

    /// One projection for the whole stack rather than an `m34` on every card.
    /// A card carrying its own perspective is projected about its own layer
    /// origin — its bottom-left corner, since AppKit anchors a view's layer
    /// there — so every card gets a different vanishing point and the depth
    /// divisor stops matching the `w` that `Flip3DLayout` pre-multiplies into
    /// x/y/scale. The staircase then fails to converge: cards further back
    /// render *larger* than the selected one, and the selected card is squashed
    /// to a fraction of its width. Projecting every card from the focal point
    /// makes the divisor exactly `w` at each card's centre, which is what the
    /// layout math assumes. It sits on the card host, so the scrim and the
    /// position capsule — which must stay flat against the screen — are outside
    /// it entirely.
    private func applyStackProjection(perspective: Double) {
        guard let layer = cardHost.layer else { return }
        let focus = stackFocus
        var projection = CATransform3DIdentity
        projection.m34 = -perspective
        var transform = CATransform3DMakeTranslation(-focus.x, -focus.y, 0)
        transform = CATransform3DConcat(transform, projection)
        transform = CATransform3DConcat(transform, CATransform3DMakeTranslation(focus.x, focus.y, 0))
        layer.sublayerTransform = transform
    }

    /// Every card shares a center but takes its own window's proportions, so
    /// the preview reaches the card's edges. One card shape for every window
    /// cannot: `.scaleProportionallyUpOrDown` fits the preview inside it, and
    /// anything that is not as wide as the card ends up flanked by a slab of
    /// bare card background — 197pt of it on each side for a 1000x1200 window.
    override func configureBaseCardGeometry() {
        let metrics = resolvedCardMetrics
        let chrome = CGSize(
            width: metrics.contentInset * 2,
            height: metrics.contentInset + metrics.footerHeight
        )
        let picture = CGSize(
            width: max(1, min(820, bounds.width * 0.60) - chrome.width),
            height: max(1, min(560, bounds.height * 0.70) - chrome.height)
        )
        let center = stackFocus
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (card, window) in zip(cards, windows) {
            let preview = Self.pictureSize(for: window.metadata.frame, fitting: picture)
            let size = CGSize(
                width: (preview.width + chrome.width).rounded(),
                height: (preview.height + chrome.height).rounded()
            )
            card.layer?.transform = CATransform3DIdentity
            card.frame = NSRect(
                x: (center.x - size.width / 2).rounded(),
                y: (center.y - size.height / 2).rounded(),
                width: size.width,
                height: size.height
            )
        }
        CATransaction.commit()
    }

    /// The largest box with the window's own proportions that fits the picture
    /// area. Fitting to one axis leaves the other at its full extent, which is
    /// what keeps every card in the staircase peeking past the one in front of
    /// it: a card as wide as the box still clears it on the left, a card as
    /// tall as the box still clears it on top.
    private static func pictureSize(for windowFrame: CGRect, fitting box: CGSize) -> CGSize {
        guard windowFrame.width > 0, windowFrame.height > 0 else { return box }
        // Past this the footer has no room left for the icon beside the labels,
        // so a sliver of a window letterboxes inside a legible card instead.
        let minimumWidth = min(box.width, 240)
        let aspect = windowFrame.width / windowFrame.height
        let width = min(box.width, box.height * aspect)
        guard width >= minimumWidth else { return CGSize(width: minimumWidth, height: box.height) }
        return CGSize(width: width, height: min(box.height, width / aspect))
    }
}
