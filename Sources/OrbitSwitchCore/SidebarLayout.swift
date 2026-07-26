import Foundation

/// The direction a strip runs. A strip docked to the left or right edge is a
/// vertical column; one docked to the top or bottom is a horizontal row. The
/// selection model, viewport, and fading are identical either way — only the
/// axis the tiles are laid along changes.
public enum SidebarAxis: String, Codable, Equatable, Sendable {
    case vertical, horizontal
}

/// Resolved tile geometry for one sidebar presentation. `capacity` is how many
/// tiles the strip actually shows, which can be lower than the user's preferred
/// count when the display is small along the strip's axis.
public struct SidebarMetrics: Equatable, Sendable {
    public let tileWidth: Double
    public let tileHeight: Double
    public let spacing: Double
    public let capacity: Int
    public let axis: SidebarAxis

    public init(tileWidth: Double, tileHeight: Double, spacing: Double, capacity: Int, axis: SidebarAxis = .vertical) {
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.spacing = spacing
        self.capacity = capacity
        self.axis = axis
    }

    /// The tile's size along the strip's own axis: its height in a column, its
    /// width in a row.
    public var tileExtent: Double {
        axis == .vertical ? tileHeight : tileWidth
    }

    /// Length of the whole strip along its axis, used to center it on screen.
    public var stripExtent: Double {
        Double(capacity) * tileExtent + Double(max(capacity - 1, 0)) * spacing
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
    /// Position within the visible strip, `0` at the leading end — the top of a
    /// column, the left of a row. Off-viewport tiles report the slot just past
    /// the end they left through, so they animate out along the strip instead
    /// of teleporting.
    public let slot: Int
    /// Distance from the strip's center along its axis, in view coordinates:
    /// upward on a vertical strip, rightward on a horizontal one. Slot 0 is
    /// therefore the most positive offset in a column and the most negative in
    /// a row.
    public let offset: Double
    public let scale: Double
    public let opacity: Double
    public let isVisible: Bool

    public init(slot: Int, offset: Double, scale: Double, opacity: Double, isVisible: Bool) {
        self.slot = slot
        self.offset = offset
        self.scale = scale
        self.opacity = opacity
        self.isVisible = isVisible
    }
}

/// Geometry for the Stage Manager-style edge strip: a fixed number of tiles in
/// a line along one screen edge, with the selection sliding a viewport across
/// the full window list. Selection itself always wraps, so Tab keeps looping
/// through every window even though only `capacity` tiles are on screen at once.
public enum SidebarLayout {
    public static let visibleCountRange = 3...12
    public static let tileWidthRange = 180.0...340.0
    /// On-screen shrink applied to every tile that is not selected.
    private static let unselectedScale = 0.94
    private static let unselectedOpacity = 0.68
    /// A boundary tile with more windows past it is dimmed further, so the
    /// strip reads as a list that continues rather than one that ends.
    private static let boundaryScale = 0.88
    private static let boundaryOpacity = 0.38

    public static func clampedVisibleCount(_ count: Int) -> Int {
        min(visibleCountRange.upperBound, max(visibleCountRange.lowerBound, count))
    }

    public static func clampedTileWidth(_ width: Double) -> Double {
        min(tileWidthRange.upperBound, max(tileWidthRange.lowerBound, width))
    }

    /// Fits `preferredCapacity` tiles into the room available along `axis`.
    /// Tiles are narrowed before any are dropped, because a shorter strip hides
    /// windows while a smaller tile only shows them smaller. Capacity is reduced
    /// only once the tile has shrunk to `minimumTileWidth`, and the tile is then
    /// widened again to use the room the dropped tiles freed.
    ///
    /// Tile width drives both axes: `previewAspect` is the preview block's
    /// height as a fraction of that width and `footerHeight` is the fixed label
    /// row beneath it. So a column is bounded lengthwise by the display height
    /// and crosswise by its width, and a row is bounded the other way around.
    public static func metrics(
        count: Int,
        preferredCapacity: Int,
        preferredTileWidth: Double,
        axis: SidebarAxis = .vertical,
        availableWidth: Double,
        availableHeight: Double,
        previewAspect: Double = 0.58,
        footerHeight: Double = 46,
        minimumTileWidth: Double = 150,
        spacing: Double = 12
    ) -> SidebarMetrics {
        let aspect = max(previewAspect, 0.01)
        func height(for width: Double) -> Double { width * aspect + footerHeight }
        /// Room along the strip, and the widest tile the other axis can hold.
        let alongExtent = axis == .vertical ? availableHeight : availableWidth
        let crossCeiling = axis == .vertical ? availableWidth : (availableHeight - footerHeight) / aspect
        let minimumWidth = max(80, min(minimumTileWidth, max(crossCeiling, 80)))
        let ceilingWidth = max(minimumWidth, min(clampedTileWidth(preferredTileWidth), crossCeiling))
        func extent(for width: Double) -> Double { axis == .vertical ? height(for: width) : width }
        func required(_ capacity: Int, _ width: Double) -> Double {
            Double(capacity) * extent(for: width) + Double(max(capacity - 1, 0)) * spacing
        }
        /// Solves `required(capacity, w) == alongExtent` for w.
        func fittedWidth(_ capacity: Int) -> Double {
            let usable = alongExtent - Double(capacity - 1) * spacing
            return axis == .vertical
                ? (usable - Double(capacity) * footerHeight) / (Double(capacity) * aspect)
                : usable / Double(capacity)
        }

        var capacity = max(1, min(clampedVisibleCount(preferredCapacity), max(count, 1)))
        var width = ceilingWidth
        if required(capacity, width) > alongExtent {
            let fitted = fittedWidth(capacity)
            if fitted >= minimumWidth {
                width = min(width, fitted)
            } else {
                let step = extent(for: minimumWidth) + spacing
                capacity = max(1, min(capacity, Int(((alongExtent + spacing) / step).rounded(.down))))
                width = max(minimumWidth, min(ceilingWidth, fittedWidth(capacity)))
            }
        }
        return SidebarMetrics(
            tileWidth: width,
            tileHeight: height(for: width),
            spacing: spacing,
            capacity: capacity,
            axis: axis
        )
    }

    /// Keeps the selection centered in the strip where possible and pinned to
    /// the ends otherwise, so it scrolls like a list instead of rotating under
    /// a fixed cursor.
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
        let tileExtent = metrics.tileExtent
        let step = tileExtent + metrics.spacing
        let stripExtent = Double(capacity) * tileExtent + Double(max(capacity - 1, 0)) * metrics.spacing
        // Slot 0 is the leading tile: the top of a column, the left of a row.
        // Offsets therefore count down from the leading edge on a vertical
        // strip and up from it on a horizontal one.
        let leadOffset = (stripExtent - tileExtent) / 2
        let direction: Double = metrics.axis == .vertical ? -1 : 1
        return (0..<count).map { index in
            let rawSlot = index - viewport.firstIndex
            let isVisible = rawSlot >= 0 && rawSlot < capacity
            let slot = min(max(rawSlot, -1), capacity)
            let isSelected = index == selection
            let isLeadingBoundary = rawSlot == 0 && viewport.hiddenBefore > 0
            let isTrailingBoundary = rawSlot == capacity - 1 && viewport.hiddenAfter > 0
            let isBoundary = (isLeadingBoundary || isTrailingBoundary) && !isSelected
            let scale: Double = if isSelected { 1 } else if isBoundary { boundaryScale } else { unselectedScale }
            let opacity: Double = if !isVisible { 0 } else if isSelected { 1 } else if isBoundary { boundaryOpacity } else { unselectedOpacity }
            return SidebarPlacement(
                slot: slot,
                offset: direction * (Double(slot) * step - leadOffset),
                scale: scale,
                opacity: opacity,
                isVisible: isVisible
            )
        }
    }
}
