import XCTest
@testable import OrbitSwitchCore

final class DockPeekLayoutTests: XCTestCase {
    /// A 1920x1080 display with the 25pt menu bar always accounted for. Each
    /// helper adds the reservation of a Dock on one particular edge.
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let bottomDockVisible = CGRect(x: 0, y: 70, width: 1920, height: 985)
    private let leftDockVisible = CGRect(x: 80, y: 0, width: 1840, height: 1055)
    private let rightDockVisible = CGRect(x: 0, y: 0, width: 1840, height: 1055)

    /// An icon sitting in a bottom Dock, `x` being its left edge.
    private func bottomDockItem(x: Double) -> CGRect {
        CGRect(x: x, y: 4, width: 60, height: 60)
    }

    private func placement(
        count: Int,
        anchor: CGRect,
        visibleFrame: CGRect,
        tileWidth: Double = 220
    ) -> DockPeekPlacement {
        DockPeekLayout.placement(
            count: count,
            anchor: anchor,
            screenFrame: screen,
            visibleFrame: visibleFrame,
            preferredTileWidth: tileWidth
        )
    }

    // MARK: - Clamping

    func testHoverDelayAndTileWidthAreClampedToTheirSettingsRanges() {
        XCTAssertEqual(DockPeekLayout.clampedHoverDelay(0), DockPeekLayout.hoverDelayRange.lowerBound)
        XCTAssertEqual(DockPeekLayout.clampedHoverDelay(99), DockPeekLayout.hoverDelayRange.upperBound)
        XCTAssertEqual(DockPeekLayout.clampedHoverDelay(0.3), 0.3)
        XCTAssertEqual(DockPeekLayout.clampedTileWidth(-5), DockPeekLayout.tileWidthRange.lowerBound)
        XCTAssertEqual(DockPeekLayout.clampedTileWidth(9000), DockPeekLayout.tileWidthRange.upperBound)
        XCTAssertEqual(DockPeekLayout.clampedTileWidth(220), 220)
    }

    // MARK: - Edge detection

    /// The Dock's edge is read off the icon itself rather than off the screen's
    /// visible frame, which is what makes an auto-hidden Dock work: it reserves
    /// no screen area, so the insets say nothing.
    func testEdgeComesFromTheIconPositionNotTheScreenInsets() {
        XCTAssertEqual(DockPeekLayout.edge(anchor: bottomDockItem(x: 900), screenFrame: screen), .bottom)
        XCTAssertEqual(
            DockPeekLayout.edge(anchor: CGRect(x: 10, y: 500, width: 60, height: 60), screenFrame: screen),
            .left
        )
        XCTAssertEqual(
            DockPeekLayout.edge(anchor: CGRect(x: 1850, y: 500, width: 60, height: 60), screenFrame: screen),
            .right
        )
    }

    func testAnIconAtTheCornerOfABottomDockStillReadsAsBottom() {
        XCTAssertEqual(DockPeekLayout.edge(anchor: bottomDockItem(x: 8), screenFrame: screen), .bottom)
        XCTAssertEqual(DockPeekLayout.edge(anchor: bottomDockItem(x: 1852), screenFrame: screen), .bottom)
    }

    // MARK: - Fitting the cards

    func testAShortWindowListStaysOnOneRowAtThePreferredWidth() {
        let result = placement(count: 3, anchor: bottomDockItem(x: 900), visibleFrame: bottomDockVisible)
        XCTAssertEqual(result.metrics.totalRows, 1)
        XCTAssertEqual(result.metrics.columns, 3)
        XCTAssertEqual(result.metrics.tileWidth, 220)
        XCTAssertEqual(result.metrics.capacity, 3)
    }

    /// Narrowing is always preferred to wrapping: a smaller card still shows the
    /// window, while a second row costs the pointer a longer trip.
    func testALongWindowListNarrowsBeforeItWraps() {
        let result = placement(count: 10, anchor: bottomDockItem(x: 900), visibleFrame: bottomDockVisible)
        XCTAssertEqual(result.metrics.totalRows, 1)
        XCTAssertEqual(result.metrics.columns, 10)
        XCTAssertLessThan(result.metrics.tileWidth, 220)
        XCTAssertGreaterThanOrEqual(result.metrics.tileWidth, 120)
        XCTAssertEqual(result.metrics.capacity, 10)
        XCTAssertFalse(result.metrics.isScrollable)
    }

    func testAWindowListTooLongForOneLegibleRowWrapsIntoAGrid() {
        let result = placement(count: 30, anchor: bottomDockItem(x: 900), visibleFrame: bottomDockVisible)
        XCTAssertGreaterThan(result.metrics.totalRows, 1)
        XCTAssertGreaterThanOrEqual(result.metrics.tileWidth, 120)
        XCTAssertLessThanOrEqual(result.metrics.tileWidth, 220)
    }

    /// Wrapping leaves the panel narrower than the room it had. The tile takes
    /// that room back, or a list that just barely wraps would sit at the minimum
    /// size beside a wide empty margin.
    func testWrappingWidensTheTilesBackIntoTheRoomTheGridFreed() {
        let available = CGSize(width: 1904, height: 950)
        let wrapped = DockPeekLayout.metrics(count: 14, preferredTileWidth: 220, available: available)
        XCTAssertEqual(wrapped.totalRows, 2)
        // Far wider than the 120pt minimum the grid was shaped at.
        XCTAssertGreaterThan(wrapped.tileWidth, 180)
        // And the panel still uses no more than its share of the screen.
        XCTAssertLessThanOrEqual(
            wrapped.contentSize.width,
            available.width * DockPeekLayout.maximumWidthFraction + 0.001
        )
    }

    /// A ragged last row makes the panel wider and uglier than it needs to be,
    /// so a grid that holds the whole list spreads it evenly over its rows.
    func testAWrappedGridBalancesItsRowsInsteadOfFillingTheFirstOne() {
        let metrics = DockPeekLayout.metrics(
            count: 20,
            preferredTileWidth: 220,
            available: CGSize(width: 1904, height: 950)
        )
        XCTAssertEqual(metrics.totalRows, 2)
        XCTAssertEqual(metrics.visibleRows, 2)
        XCTAssertEqual(metrics.columns, 10)
        XCTAssertFalse(metrics.isScrollable)
    }

    /// A peek stays a peek. However many windows an application has, the panel
    /// never spans the display or grows past its row limit.
    func testThePanelNeverGrowsPastItsWidthAndRowLimits() {
        let available = CGSize(width: 1904, height: 950)
        let metrics = DockPeekLayout.metrics(count: 100, preferredTileWidth: 220, available: available)
        XCTAssertEqual(metrics.visibleRows, DockPeekLayout.maximumVisibleRows)
        XCTAssertLessThanOrEqual(
            metrics.contentSize.width,
            available.width * DockPeekLayout.maximumWidthFraction
        )
        XCTAssertLessThanOrEqual(metrics.contentSize.height, available.height)
    }

    /// The whole point of the bound: a window that does not fit on screen must
    /// still be in the grid, reachable by scrolling. Silently dropping windows
    /// from a window picker is the one outcome that is never acceptable.
    func testEveryWindowIsInTheGridNoMatterHowManyThereAre() {
        for available in [CGSize(width: 1904, height: 950), CGSize(width: 1496, height: 860)] {
            for count in [40, 100, 400] {
                let metrics = DockPeekLayout.metrics(
                    count: count,
                    preferredTileWidth: 220,
                    available: available
                )
                XCTAssertGreaterThanOrEqual(
                    metrics.columns * metrics.totalRows, count,
                    "grid holds \(metrics.columns * metrics.totalRows) of \(count) at \(available)"
                )
                XCTAssertTrue(metrics.isScrollable)
                XCTAssertGreaterThan(metrics.maximumScrollOffset, 0)
            }
        }
    }

    func testAListThatFitsNeitherScrollsNorReportsScrollRoom() {
        let metrics = DockPeekLayout.metrics(
            count: 4,
            preferredTileWidth: 220,
            available: CGSize(width: 1904, height: 950)
        )
        XCTAssertFalse(metrics.isScrollable)
        XCTAssertEqual(metrics.maximumScrollOffset, 0)
        XCTAssertEqual(metrics.contentSize, metrics.documentSize)
        // No scrolling means no count to show, so no strip is reserved for it.
        XCTAssertEqual(metrics.indicatorReserve, 0)
    }

    /// Scrolling moves the grid under a fixed panel, so the document is taller
    /// than the panel by exactly the distance the grid can travel.
    func testTheScrollableDocumentIsTallerThanThePanelByItsScrollRange() {
        let metrics = DockPeekLayout.metrics(
            count: 100,
            preferredTileWidth: 220,
            available: CGSize(width: 1904, height: 950)
        )
        XCTAssertEqual(
            metrics.documentSize.height - metrics.contentSize.height,
            metrics.maximumScrollOffset,
            accuracy: 0.001
        )
        XCTAssertEqual(metrics.documentSize.width, metrics.contentSize.width)
        // The last card sits just above the reserved indicator strip, which is
        // what the panel reaches at full scroll.
        let last = metrics.cardOrigin(at: (metrics.totalRows - 1) * metrics.columns)
        XCTAssertEqual(last.y, metrics.padding + metrics.indicatorReserve, accuracy: 0.001)
        XCTAssertEqual(metrics.indicatorReserve, DockPeekLayout.indicatorReserve)
    }

    func testCardsFillLeftToRightAndTopRowFirst() {
        let metrics = DockPeekMetrics(
            tileWidth: 100,
            tileHeight: 80,
            spacing: 10,
            padding: 12,
            columns: 2,
            visibleRows: 2,
            totalRows: 2
        )
        // Unflipped coordinates, so the top row has the greater y.
        XCTAssertEqual(metrics.cardOrigin(at: 0).x, 12)
        XCTAssertEqual(metrics.cardOrigin(at: 1).x, 122)
        XCTAssertEqual(metrics.cardOrigin(at: 0).y, metrics.cardOrigin(at: 1).y)
        XCTAssertGreaterThan(metrics.cardOrigin(at: 0).y, metrics.cardOrigin(at: 2).y)
        XCTAssertEqual(metrics.cardOrigin(at: 2).x, 12)
    }

    // MARK: - Placing the panel

    func testThePanelCentersOnTheIconWhenThereIsRoom() {
        let anchor = bottomDockItem(x: 900)
        let result = placement(count: 3, anchor: anchor, visibleFrame: bottomDockVisible)
        XCTAssertEqual(result.frame.midX, anchor.midX, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(result.frame.minY, anchor.maxY)
    }

    func testAnIconAtEitherEndOfTheDockStillGetsAFullyOnScreenPanel() {
        for x in [8.0, 1852.0] {
            let result = placement(count: 5, anchor: bottomDockItem(x: x), visibleFrame: bottomDockVisible)
            XCTAssertGreaterThanOrEqual(result.frame.minX, screen.minX)
            XCTAssertLessThanOrEqual(result.frame.maxX, screen.maxX)
            XCTAssertGreaterThanOrEqual(result.frame.minY, bottomDockVisible.minY)
            XCTAssertLessThanOrEqual(result.frame.maxY, bottomDockVisible.maxY)
        }
    }

    func testASideDockPushesThePanelInwardRatherThanUpward() {
        let leftAnchor = CGRect(x: 10, y: 500, width: 60, height: 60)
        let left = placement(count: 4, anchor: leftAnchor, visibleFrame: leftDockVisible)
        XCTAssertEqual(left.edge, .left)
        XCTAssertGreaterThanOrEqual(left.frame.minX, leftAnchor.maxX)
        XCTAssertLessThanOrEqual(left.frame.maxX, leftDockVisible.maxX)

        let rightAnchor = CGRect(x: 1850, y: 500, width: 60, height: 60)
        let right = placement(count: 4, anchor: rightAnchor, visibleFrame: rightDockVisible)
        XCTAssertEqual(right.edge, .right)
        XCTAssertLessThanOrEqual(right.frame.maxX, rightAnchor.minX)
        XCTAssertGreaterThanOrEqual(right.frame.minX, rightDockVisible.minX)
    }

    /// An auto-hidden Dock reserves nothing, so the visible frame is the whole
    /// screen below the menu bar. Placement must still clear the revealed Dock,
    /// which it does by working from the icon.
    func testAnAutoHiddenDockStillPlacesThePanelClearOfTheIcon() {
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1055)
        let anchor = bottomDockItem(x: 900)
        let result = placement(count: 4, anchor: anchor, visibleFrame: visible)
        XCTAssertEqual(result.edge, .bottom)
        XCTAssertGreaterThanOrEqual(result.frame.minY, anchor.maxY)
    }

    func testAPanelWiderThanItsScreenKeepsItsLeadingEdgeOnScreen() {
        let narrow = CGRect(x: 0, y: 0, width: 400, height: 400)
        let metrics = DockPeekMetrics(
            tileWidth: 600,
            tileHeight: 200,
            spacing: 10,
            padding: 12,
            columns: 1,
            visibleRows: 1,
            totalRows: 1
        )
        let frame = DockPeekLayout.frame(
            edge: .bottom,
            anchor: CGRect(x: 180, y: 4, width: 40, height: 40),
            visibleFrame: narrow,
            metrics: metrics
        )
        XCTAssertEqual(frame.minX, narrow.minX + DockPeekLayout.screenMargin, accuracy: 0.001)
    }
}
