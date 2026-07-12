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
    /// successive cards step up and to the left, receding in Z.
    ///
    /// x/y/scale are raw layer-transform values pre-multiplied by the m34
    /// projection divisor `w = 1 + perspective * |z|`, so the *projected*
    /// staircase keeps uniform, converging steps. Applying them without an
    /// m34 of -perspective will not land cards where intended.
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
                opacity: hidden ? 0 : max(0.30, 1 - depth * 0.062),
                angleDegrees: -angle
            )
        }
    }
}
