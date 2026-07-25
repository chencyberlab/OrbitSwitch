import Foundation

/// Resolved tile geometry for one sidebar presentation. `capacity` is how many
/// tiles the strip actually shows, which can be lower than the user's preferred
/// count when the display is short.
public struct SidebarMetrics: Equatable, Sendable {
    public let tileWidth: Double
    public let tileHeight: Double
    public let spacing: Double
    public let capacity: Int

    public init(tileWidth: Double, tileHeight: Double, spacing: Double, capacity: Int) {
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.spacing = spacing
        self.capacity = capacity
    }

    /// Height of the whole column, used to center the strip vertically.
    public var columnHeight: Double {
        Double(capacity) * tileHeight + Double(max(capacity - 1, 0)) * spacing
    }
}

/// The slice of the window list currently on screen.
public struct SidebarViewport: Equatable, Sendable {
    public let firstIndex: Int
    public let capacity: Int
    public let hiddenBefore: Int
    public let hiddenAfter: Int

    public init(firstIndex: Int, capacity: Int, hiddenBefore: Int, hiddenAfter: Int) {
        self.firstIndex = firstIndex
        self.capacity = capacity
        self.hiddenBefore = hiddenBefore
        self.hiddenAfter = hiddenAfter
    }
}

public struct SidebarPlacement: Equatable, Sendable {
    /// Position within the visible column, `0` at the top. Off-viewport tiles
    /// report the slot just past the end they left through, so they animate out
    /// along the strip instead of teleporting.
    public let slot: Int
    /// Vertical offset from the column's center, positive upward.
    public let y: Double
    public let scale: Double
    public let opacity: Double
    public let isVisible: Bool

    public init(slot: Int, y: Double, scale: Double, opacity: Double, isVisible: Bool) {
        self.slot = slot
        self.y = y
        self.scale = scale
        self.opacity = opacity
        self.isVisible = isVisible
    }
}

/// Geometry for the Stage Manager-style edge strip: a fixed number of tiles in
/// a vertical column, with the selection sliding a viewport across the full
/// window list. Selection itself always wraps, so Tab keeps looping through
/// every window even though only `capacity` tiles are on screen at once.
public enum SidebarLayout {
    public static let visibleCountRange = 3...12
    public static let tileWidthRange = 180.0...340.0
    /// On-screen shrink applied to every tile that is not selected.
    private static let unselectedScale = 0.94
    private static let unselectedOpacity = 0.68
    /// A boundary tile with more windows past it is dimmed further, so the
    /// column reads as a list that continues rather than one that ends.
    private static let boundaryScale = 0.88
    private static let boundaryOpacity = 0.38

    public static func clampedVisibleCount(_ count: Int) -> Int {
        min(visibleCountRange.upperBound, max(visibleCountRange.lowerBound, count))
    }

    public static func clampedTileWidth(_ width: Double) -> Double {
        min(tileWidthRange.upperBound, max(tileWidthRange.lowerBound, width))
    }

    /// Fits `preferredCapacity` tiles into `availableHeight`. Tiles are narrowed
    /// before any are dropped, because a shorter strip hides windows while a
    /// smaller tile only shows them smaller. Capacity is reduced only once the
    /// tile has shrunk to `minimumTileWidth`, and the tile is then widened again
    /// to use the room the dropped tiles freed.
    ///
    /// `previewAspect` is the preview block's height as a fraction of the tile
    /// width, and `footerHeight` is the fixed label row beneath it.
    public static func metrics(
        count: Int,
        preferredCapacity: Int,
        preferredTileWidth: Double,
        availableWidth: Double,
        availableHeight: Double,
        previewAspect: Double = 0.58,
        footerHeight: Double = 46,
        minimumTileWidth: Double = 150,
        spacing: Double = 12
    ) -> SidebarMetrics {
        let minimumWidth = max(80, min(minimumTileWidth, max(availableWidth, 80)))
        let ceilingWidth = max(minimumWidth, min(clampedTileWidth(preferredTileWidth), availableWidth))
        func height(for width: Double) -> Double { width * previewAspect + footerHeight }
        func required(_ capacity: Int, _ width: Double) -> Double {
            Double(capacity) * height(for: width) + Double(max(capacity - 1, 0)) * spacing
        }
        /// Solves capacity * (w * aspect + footer) + gaps = availableHeight for w.
        func fittedWidth(_ capacity: Int) -> Double {
            let usable = availableHeight - Double(capacity - 1) * spacing - Double(capacity) * footerHeight
            return usable / (Double(capacity) * max(previewAspect, 0.01))
        }

        var capacity = max(1, min(clampedVisibleCount(preferredCapacity), max(count, 1)))
        var width = ceilingWidth
        if required(capacity, width) > availableHeight {
            let fitted = fittedWidth(capacity)
            if fitted >= minimumWidth {
                width = min(width, fitted)
            } else {
                let step = height(for: minimumWidth) + spacing
                capacity = max(1, min(capacity, Int(((availableHeight + spacing) / step).rounded(.down))))
                width = max(minimumWidth, min(ceilingWidth, fittedWidth(capacity)))
            }
        }
        return SidebarMetrics(tileWidth: width, tileHeight: height(for: width), spacing: spacing, capacity: capacity)
    }

    /// Keeps the selection centered in the column where possible and pinned to
    /// the ends otherwise, so the strip scrolls like a list instead of rotating
    /// under a fixed cursor.
    public static func viewport(count: Int, selection: Int, capacity: Int) -> SidebarViewport {
        guard count > 0 else { return SidebarViewport(firstIndex: 0, capacity: 0, hiddenBefore: 0, hiddenAfter: 0) }
        let capacity = max(1, min(capacity, count))
        let selection = Flip3DLayout.wrappedIndex(selection, count: count)
        let centered = selection - (capacity - 1) / 2
        let first = min(max(centered, 0), count - capacity)
        return SidebarViewport(
            firstIndex: first,
            capacity: capacity,
            hiddenBefore: first,
            hiddenAfter: count - (first + capacity)
        )
    }

    public static func placements(count: Int, selection: Int, metrics: SidebarMetrics) -> [SidebarPlacement] {
        guard count > 0 else { return [] }
        let selection = Flip3DLayout.wrappedIndex(selection, count: count)
        let viewport = viewport(count: count, selection: selection, capacity: metrics.capacity)
        let capacity = viewport.capacity
        let step = metrics.tileHeight + metrics.spacing
        let columnHeight = Double(capacity) * metrics.tileHeight + Double(max(capacity - 1, 0)) * metrics.spacing
        let topSlotY = (columnHeight - metrics.tileHeight) / 2
        return (0..<count).map { index in
            let rawSlot = index - viewport.firstIndex
            let isVisible = rawSlot >= 0 && rawSlot < capacity
            let slot = min(max(rawSlot, -1), capacity)
            let isSelected = index == selection
            let isTopBoundary = rawSlot == 0 && viewport.hiddenBefore > 0
            let isBottomBoundary = rawSlot == capacity - 1 && viewport.hiddenAfter > 0
            let isBoundary = (isTopBoundary || isBottomBoundary) && !isSelected
            let scale: Double = if isSelected { 1 } else if isBoundary { boundaryScale } else { unselectedScale }
            let opacity: Double = if !isVisible { 0 } else if isSelected { 1 } else if isBoundary { boundaryOpacity } else { unselectedOpacity }
            return SidebarPlacement(
                slot: slot,
                y: topSlotY - Double(slot) * step,
                scale: scale,
                opacity: opacity,
                isVisible: isVisible
            )
        }
    }
}
