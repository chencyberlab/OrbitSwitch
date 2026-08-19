import CoreGraphics
import Foundation

/// Which screen edge the Dock is docked to. There is no `top` case: macOS
/// reserves the top edge for the menu bar, so a Dock item's anchor can only
/// ever sit against the bottom, left, or right.
public enum DockEdge: String, Codable, Equatable, Sendable {
    case bottom, left, right

    /// The axis the peek row grows along is always horizontal; this reports
    /// which way the panel is pushed off the Dock to reach free screen.
    public var title: String {
        switch self { case .bottom: "Bottom" case .left: "Left" case .right: "Right" }
    }
}

/// Resolved tile geometry for one peek panel. `capacity` is how many cards the
/// panel actually shows, which is lower than the window count only when even a
/// full grid of minimum-width tiles cannot hold them all.
public struct DockPeekMetrics: Equatable, Sendable {
    public let tileWidth: Double
    public let tileHeight: Double
    public let spacing: Double
    public let padding: Double
    public let columns: Int
    /// Rows the panel is tall enough to show at once.
    public let visibleRows: Int
    /// Rows the whole window list actually needs. Greater than `visibleRows`
    /// means the panel scrolls; no window is ever left out of the grid.
    public let totalRows: Int

    public init(tileWidth: Double, tileHeight: Double, spacing: Double, padding: Double, columns: Int, visibleRows: Int, totalRows: Int) {
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.spacing = spacing
        self.padding = padding
        self.columns = columns
        self.visibleRows = visibleRows
        self.totalRows = max(totalRows, visibleRows)
    }

    /// Cards on screen at one time.
    public var capacity: Int { columns * visibleRows }

    public var isScrollable: Bool { totalRows > visibleRows }

    /// Free strip along the bottom, present only when the panel scrolls and
    /// therefore has a window count to show.
    public var indicatorReserve: Double { isScrollable ? DockPeekLayout.indicatorReserve : 0 }

    /// Adding the reserve to both the panel and the document raises the whole
    /// grid by it, which is what leaves the strip free at the bottom — and it
    /// cancels out of the scroll range, which is their difference.
    private func height(rows: Int) -> Double {
        2 * padding + Double(rows) * tileHeight + Double(max(rows - 1, 0)) * spacing + indicatorReserve
    }

    /// The panel's own size.
    public var contentSize: CGSize {
        CGSize(
            width: 2 * padding + Double(columns) * tileWidth + Double(max(columns - 1, 0)) * spacing,
            height: height(rows: visibleRows)
        )
    }

    /// The size of the full grid, which the panel scrolls over.
    public var documentSize: CGSize {
        CGSize(width: contentSize.width, height: height(rows: totalRows))
    }

    /// How far the grid can travel under the panel.
    public var maximumScrollOffset: Double {
        max(0, documentSize.height - contentSize.height)
    }

    /// The live scroll range after cards have been removed from a panel whose
    /// frame and document geometry intentionally remain fixed. This prevents
    /// scrolling into empty rows without resizing the whole panel during the
    /// close click.
    public func maximumScrollOffset(forWindowCount count: Int) -> Double {
        let safeColumns = max(columns, 1)
        let windowCount = max(count, 1)
        let requiredRows = (windowCount - 1) / safeColumns + 1
        let remainingRange = Double(max(0, requiredRows - visibleRows)) * (tileHeight + spacing)
        return min(maximumScrollOffset, remainingRange)
    }

    /// Origin of the card at `index` within the full grid, filling left to right
    /// and top row first — reading order. Relative to the grid's bottom-left
    /// corner, which is the panel's own when nothing scrolls.
    public func cardOrigin(at index: Int) -> CGPoint {
        let column = columns > 0 ? index % columns : 0
        let row = columns > 0 ? index / columns : 0
        return CGPoint(
            x: padding + Double(column) * (tileWidth + spacing),
            y: documentSize.height - padding - Double(row + 1) * tileHeight - Double(row) * spacing
        )
    }
}

/// Everything needed to put one peek panel on screen.
public struct DockPeekPlacement: Equatable, Sendable {
    public let frame: CGRect
    public let edge: DockEdge
    public let metrics: DockPeekMetrics

    public init(frame: CGRect, edge: DockEdge, metrics: DockPeekMetrics) {
        self.frame = frame
        self.edge = edge
        self.metrics = metrics
    }
}

/// Geometry for the Dock peek panel: a row of window cards anchored beside the
/// hovered Dock item.
///
/// Every decision here is derived from the Dock item's own frame rather than
/// from the screen's `visibleFrame` insets. That is deliberate — an auto-hidden
/// Dock leaves no inset at all, so inset-derived placement would put the panel
/// on top of the Dock it is supposed to sit beside.
public enum DockPeekLayout {
    public static let hoverDelayRange = 0.05...1.0
    public static let tileWidthRange = 140.0...360.0
    /// A peek is a peek. However many windows an application has, the panel
    /// stays this small a share of the room beside the Dock and this few rows
    /// tall; anything past that scrolls rather than growing the panel or, worse,
    /// being dropped from it.
    public static let maximumWidthFraction = 0.8
    public static let maximumVisibleRows = 3
    /// Strip kept clear along the bottom of a scrolling panel for the window
    /// count, so the indicator sits beside the grid rather than over a card's
    /// title.
    public static let indicatorReserve = 18.0
    /// Distance between the Dock item and the panel, and between the panel and
    /// the edges of the screen it must stay inside.
    public static let gap = 10.0
    public static let screenMargin = 8.0

    public static func clampedHoverDelay(_ delay: Double) -> Double {
        min(hoverDelayRange.upperBound, max(hoverDelayRange.lowerBound, delay))
    }

    public static func clampedTileWidth(_ width: Double) -> Double {
        min(tileWidthRange.upperBound, max(tileWidthRange.lowerBound, width))
    }

    /// The edge whose Dock the anchor belongs to: whichever of the three
    /// candidate edges its center sits closest to.
    public static func edge(anchor: CGRect, screenFrame: CGRect) -> DockEdge {
        let toBottom = anchor.midY - screenFrame.minY
        let toLeft = anchor.midX - screenFrame.minX
        let toRight = screenFrame.maxX - anchor.midX
        if toLeft <= toBottom && toLeft <= toRight { return .left }
        if toRight <= toBottom && toRight <= toLeft { return .right }
        return .bottom
    }

    /// Room left for the panel once the Dock item and the gap beside it are
    /// taken out of the screen's visible area.
    public static func availableSpace(
        edge: DockEdge,
        anchor: CGRect,
        visibleFrame: CGRect,
        gap: Double = gap
    ) -> CGSize {
        let margin = 2 * screenMargin
        switch edge {
        case .bottom:
            return CGSize(
                width: max(0, visibleFrame.width - margin),
                height: max(0, visibleFrame.maxY - (anchor.maxY + gap) - screenMargin)
            )
        case .left:
            return CGSize(
                width: max(0, visibleFrame.maxX - (anchor.maxX + gap) - screenMargin),
                height: max(0, visibleFrame.height - margin)
            )
        case .right:
            return CGSize(
                width: max(0, (anchor.minX - gap) - visibleFrame.minX - screenMargin),
                height: max(0, visibleFrame.height - margin)
            )
        }
    }

    /// Fits `count` cards into `available`. A single row is always preferred:
    /// tiles narrow toward `minimumTileWidth` before the row is allowed to wrap,
    /// because a narrower card still shows the window while a second row costs
    /// the pointer a longer trip. Only when a row of minimum-width tiles still
    /// cannot hold them does it wrap into a grid.
    ///
    /// The panel never grows past `maximumWidthFraction` of the room beside the
    /// Dock or past `maximumVisibleRows` rows. An application with dozens of
    /// windows therefore gets a scrolling grid at a readable size rather than a
    /// near-full-screen wall of unreadable thumbnails — and every window is in
    /// that grid, because dropping some of them silently is worse than either.
    public static func metrics(
        count: Int,
        preferredTileWidth: Double,
        available: CGSize,
        previewAspect: Double = 0.58,
        footerHeight: Double = 46,
        minimumTileWidth: Double = 120,
        spacing: Double = 10,
        padding: Double = 12
    ) -> DockPeekMetrics {
        let aspect = max(previewAspect, 0.01)
        func height(for width: Double) -> Double { width * aspect + footerHeight }
        let count = max(1, count)
        let usableWidth = max(minimumTileWidth, available.width * maximumWidthFraction - 2 * padding)
        let usableHeight = max(height(for: minimumTileWidth), available.height - 2 * padding)

        // The widest a tile may be here: the user's preference, never wider than
        // the panel could be and never taller than the room beside the Dock.
        let heightCeiling = max(minimumTileWidth, (usableHeight - footerHeight) / aspect)
        let ceilingWidth = max(
            minimumTileWidth,
            min(clampedTileWidth(preferredTileWidth), usableWidth, heightCeiling)
        )

        func columns(at width: Double) -> Int {
            max(1, Int(((usableWidth + spacing) / (width + spacing)).rounded(.down)))
        }

        if count <= columns(at: ceilingWidth) {
            return DockPeekMetrics(
                tileWidth: ceilingWidth,
                tileHeight: height(for: ceilingWidth),
                spacing: spacing,
                padding: padding,
                columns: count,
                visibleRows: 1,
                totalRows: 1
            )
        }

        // One row, narrowed to fit, as long as the tiles stay legible.
        let fitted = (usableWidth - Double(count - 1) * spacing) / Double(count)
        if fitted >= minimumTileWidth {
            let width = min(ceilingWidth, fitted)
            return DockPeekMetrics(
                tileWidth: width,
                tileHeight: height(for: width),
                spacing: spacing,
                padding: padding,
                columns: count,
                visibleRows: 1,
                totalRows: 1
            )
        }

        // The grid is shaped at the minimum tile size, which is what decides how
        // many columns there is room for; the tile is widened again afterward.
        let minimumWidth = min(ceilingWidth, minimumTileWidth)
        let columnCount = columns(at: minimumWidth)
        let rowsThatFit = max(1, Int(((usableHeight + spacing) / (height(for: minimumWidth) + spacing)).rounded(.down)))
        let rowCeiling = min(maximumVisibleRows, rowsThatFit)
        let neededRows = Int((Double(count) / Double(columnCount)).rounded(.up))

        let columnsUsed: Int
        let visibleRows: Int
        if neededRows <= rowCeiling {
            // The whole list fits. Spread it evenly over the rows it uses:
            // filling the first row to the edge and leaving the last one half
            // empty makes the panel both wider and more ragged than it needs.
            visibleRows = neededRows
            columnsUsed = min(columnCount, Int((Double(count) / Double(neededRows)).rounded(.up)), count)
        } else {
            // More than the panel can show. Every column is used, because width
            // is what buys visible cards, and the surplus rows scroll.
            visibleRows = rowCeiling
            columnsUsed = min(columnCount, count)
        }

        // Wrapping usually leaves the panel narrower than the room it had, so
        // the tile takes that room back. Without this a list that just barely
        // wraps would sit at the minimum tile size beside a wide empty margin.
        let reserve = neededRows > visibleRows ? indicatorReserve : 0
        let widthAcross = (usableWidth - Double(columnsUsed - 1) * spacing) / Double(columnsUsed)
        let heightBudget = usableHeight - reserve - Double(visibleRows - 1) * spacing
        let widthDown = ((heightBudget / Double(visibleRows)) - footerHeight) / aspect
        let width = max(minimumWidth, min(ceilingWidth, widthAcross, widthDown))

        return DockPeekMetrics(
            tileWidth: width,
            tileHeight: height(for: width),
            spacing: spacing,
            padding: padding,
            columns: columnsUsed,
            visibleRows: visibleRows,
            totalRows: neededRows
        )
    }

    /// Centers the panel on the Dock item, pushed off the Dock's edge, then
    /// clamps it inside the visible area so an item at either end of the Dock
    /// still gets a fully on-screen panel.
    public static func frame(
        edge: DockEdge,
        anchor: CGRect,
        visibleFrame: CGRect,
        metrics: DockPeekMetrics,
        gap: Double = gap
    ) -> CGRect {
        let size = metrics.contentSize
        var origin: CGPoint
        switch edge {
        case .bottom:
            origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)
        case .left:
            origin = CGPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
        case .right:
            origin = CGPoint(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2)
        }
        origin.x = clamp(origin.x, lower: visibleFrame.minX + screenMargin, upper: visibleFrame.maxX - screenMargin - size.width)
        origin.y = clamp(origin.y, lower: visibleFrame.minY + screenMargin, upper: visibleFrame.maxY - screenMargin - size.height)
        return CGRect(origin: origin, size: size)
    }

    /// The whole chain in one call: pick the edge, measure the room beside the
    /// Dock, fit the cards into it, and place the panel.
    public static func placement(
        count: Int,
        anchor: CGRect,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        preferredTileWidth: Double,
        footerHeight: Double = 46
    ) -> DockPeekPlacement {
        let edge = edge(anchor: anchor, screenFrame: screenFrame)
        let available = availableSpace(edge: edge, anchor: anchor, visibleFrame: visibleFrame)
        let metrics = metrics(
            count: count,
            preferredTileWidth: preferredTileWidth,
            available: available,
            footerHeight: footerHeight
        )
        return DockPeekPlacement(
            frame: frame(edge: edge, anchor: anchor, visibleFrame: visibleFrame, metrics: metrics),
            edge: edge,
            metrics: metrics
        )
    }

    /// A lower bound above an upper bound means the panel is wider or taller
    /// than the room it has; pinning to the lower bound keeps its leading edge
    /// on screen, which is the half the pointer arrives from.
    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        upper < lower ? lower : min(max(value, lower), upper)
    }
}
