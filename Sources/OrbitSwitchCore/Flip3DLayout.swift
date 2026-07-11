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
    public static func wrappedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (index % count + count) % count
    }

    public static func placements(count: Int, selection: Int, spacing: Double, angle: Double, maximumVisible: Int = 12) -> [Flip3DPlacement] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let forward = wrappedIndex(index - selection, count: count)
            let depth = min(forward, maximumVisible)
            let hidden = forward > maximumVisible
            let verticalStep = max(46, spacing * 0.70)
            return Flip3DPlacement(
                relativeIndex: forward,
                x: Double(depth) * -spacing * 0.92,
                y: Double(depth) * verticalStep,
                z: Double(depth) * -105,
                scale: max(0.64, 1 - Double(depth) * 0.032),
                opacity: hidden ? 0 : max(0.28, 1 - Double(depth) * 0.082),
                angleDegrees: depth == 0 ? 0 : angle
            )
        }
    }
}
