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
            card.setAccessibleVisibility(placement.opacity > 0)
        }
    }

    override func configureBaseCardGeometry() {
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
}
