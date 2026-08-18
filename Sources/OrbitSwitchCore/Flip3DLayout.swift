import Foundation

public struct Flip3DPlacement: Equatable, Sendable {
    public let relativeIndex: Int
    public let x: Double
    public let y: Double
    public let z: Double
    public let scale: Double
    public let opacity: Double
    public let angleDegrees: Double
}

public enum Flip3DLayout {
    /// Allowed stack angle, in degrees. Only non-positive values are offered:
    /// positive angles yaw the cards the wrong way and break the view, so the
    /// setting range ends at zero.
    public static let stackAngleRange = -28.0...0.0

    public static func clampedStackAngle(_ angle: Double) -> Double {
        min(stackAngleRange.upperBound, max(stackAngleRange.lowerBound, angle))
    }

    /// Ratio between consecutive staircase steps. Values < 1 make the stack
    /// converge toward a vanishing point instead of marching off screen, and
    /// bound the total run at firstStep / (1 - stepDecay).
    private static let stepDecay = 0.86
    /// Z distance between consecutive cards, in points.
    private static let depthStep = 118.0
    /// Per-step on-screen shrink factor. Must shrink slower than stepDecay so
    /// every card's top and left edges stay visible past the card in front.
    private static let scaleDecay = 0.97
    private static let minimumScale = 0.66

    public static func wrappedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index % count + count) % count
    }

    /// Vista Flip 3D staircase: the selected card sits front and center while
    /// successive cards step up and to the left, receding in Z. A positive
    /// angle yaws every card Vista-style: right edge toward the viewer, left
    /// edge receding; negative flips the tilt, zero renders the stack flat.
    ///
    /// x/y/scale are raw layer-transform values pre-multiplied by the m34
    /// projection divisor `w = 1 + perspective * |z|`, so the *projected*
    /// staircase keeps uniform, converging steps. That divisor has to come from
    /// one projection shared by the whole stack, anchored at the point the
    /// cards are centred on — `Flip3DView` puts it on the card host. Giving
    /// each card its own m34 projects it about its own layer origin instead,
    /// and the cancellation these values rely on does not happen.
    ///
    /// Every card the stack shows is opaque. Fading them by depth turned each
    /// card into a gray film over the ones behind it, so overlapping cards
    /// washed into one another instead of showing their own window; depth is
    /// carried by the staircase, the shrink, and the shadow instead.
    public static func placements(
        count: Int,
        selection: Int,
        spacing: Double,
        angle: Double,
        perspective: Double = 0.00115,
        horizontalTravel: Double = 460,
        verticalTravel: Double = 300,
        maximumVisible: Int = 12
    ) -> [Flip3DPlacement] {
        guard count > 0 else { return [] }
        let steps = Double(min(max(count - 1, 1), maximumVisible))
        let travelFactor = (1 - pow(stepDecay, steps)) / (1 - stepDecay)
        let stepX = min(spacing * 1.6, horizontalTravel / travelFactor)
        let stepY = min(spacing * 1.15, verticalTravel / travelFactor)
        return (0..<count).map { index in
            let forward = wrappedIndex(index - selection, count: count)
            let depth = Double(min(forward, maximumVisible))
            let hidden = forward > maximumVisible
            let run = (1 - pow(stepDecay, depth)) / (1 - stepDecay)
            let z = -depthStep * depth
            let w = 1 + perspective * depthStep * depth
            return Flip3DPlacement(
                relativeIndex: forward,
                x: -stepX * run * w,
                y: stepY * run * w,
                z: z,
                scale: max(minimumScale, pow(scaleDecay, depth)) * w,
                opacity: hidden ? 0 : 1,
                angleDegrees: -angle
            )
        }
    }
}
