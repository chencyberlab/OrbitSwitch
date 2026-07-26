import XCTest
@testable import OrbitSwitchCore

final class SidebarLayoutTests: XCTestCase {
    private func metrics(capacity: Int, tileWidth: Double = 260, availableHeight: Double = 900) -> SidebarMetrics {
        SidebarLayout.metrics(
            count: 50,
            preferredCapacity: capacity,
            preferredTileWidth: tileWidth,
            availableWidth: 1200,
            availableHeight: availableHeight
        )
    }

    private func rowMetrics(capacity: Int, tileWidth: Double = 260, availableWidth: Double = 2400) -> SidebarMetrics {
        SidebarLayout.metrics(
            count: 50,
            preferredCapacity: capacity,
            preferredTileWidth: tileWidth,
            axis: .horizontal,
            availableWidth: availableWidth,
            availableHeight: 900
        )
    }

    // MARK: - Viewport

    func testViewportKeepsSelectionCenteredInTheMiddleOfTheList() {
        let viewport = SidebarLayout.viewport(count: 20, selection: 10, capacity: 7)
        XCTAssertEqual(viewport.firstIndex, 7)
        XCTAssertEqual(viewport.capacity, 7)
        XCTAssertEqual(viewport.hiddenBefore, 7)
        XCTAssertEqual(viewport.hiddenAfter, 6)
    }

    func testViewportPinsToBothEndsInsteadOfScrollingPastThem() {
        let first = SidebarLayout.viewport(count: 20, selection: 0, capacity: 7)
        XCTAssertEqual(first.firstIndex, 0)
        XCTAssertEqual(first.hiddenBefore, 0)
        XCTAssertEqual(first.hiddenAfter, 13)

        let last = SidebarLayout.viewport(count: 20, selection: 19, capacity: 7)
        XCTAssertEqual(last.firstIndex, 13)
        XCTAssertEqual(last.hiddenBefore, 13)
        XCTAssertEqual(last.hiddenAfter, 0)
    }

    func testEverySelectionIsVisibleInItsOwnViewport() {
        for count in [1, 2, 7, 8, 30] {
            for selection in 0..<count {
                let viewport = SidebarLayout.viewport(count: count, selection: selection, capacity: 7)
                XCTAssertGreaterThanOrEqual(selection, viewport.firstIndex, "count \(count), selection \(selection)")
                XCTAssertLessThan(selection, viewport.firstIndex + viewport.capacity, "count \(count), selection \(selection)")
            }
        }
    }

    func testViewportShowsEverythingWhenTheListFitsAndNeverExceedsTheList() {
        let viewport = SidebarLayout.viewport(count: 4, selection: 3, capacity: 7)
        XCTAssertEqual(viewport.firstIndex, 0)
        XCTAssertEqual(viewport.capacity, 4)
        XCTAssertEqual(viewport.hiddenBefore, 0)
        XCTAssertEqual(viewport.hiddenAfter, 0)
    }

    func testViewportHandlesEmptyAndWrappedSelections() {
        let empty = SidebarLayout.viewport(count: 0, selection: 0, capacity: 7)
        XCTAssertEqual(empty.capacity, 0)
        // A selection past the end wraps the same way the stack's does.
        XCTAssertEqual(
            SidebarLayout.viewport(count: 20, selection: 20, capacity: 7),
            SidebarLayout.viewport(count: 20, selection: 0, capacity: 7)
        )
        XCTAssertEqual(
            SidebarLayout.viewport(count: 20, selection: -1, capacity: 7),
            SidebarLayout.viewport(count: 20, selection: 19, capacity: 7)
        )
    }

    // MARK: - Metrics

    func testMetricsUseThePreferredSizeWhenTheDisplayHasRoom() {
        let metrics = metrics(capacity: 5, tileWidth: 260, availableHeight: 1400)
        XCTAssertEqual(metrics.capacity, 5)
        XCTAssertEqual(metrics.tileWidth, 260)
        XCTAssertLessThanOrEqual(metrics.stripExtent, 1400)
    }

    func testMetricsNarrowTilesBeforeDroppingAnyFromTheStrip() {
        let roomy = metrics(capacity: 8, availableHeight: 1800)
        let tight = metrics(capacity: 8, availableHeight: 1250)
        XCTAssertEqual(tight.capacity, roomy.capacity, "a shorter display must not silently hide windows")
        XCTAssertLessThan(tight.tileWidth, roomy.tileWidth)
        XCTAssertLessThanOrEqual(tight.stripExtent, 1250.001)
    }

    func testMetricsReduceCapacityOnlyOnceTilesCannotShrinkFurther() {
        let metrics = SidebarLayout.metrics(
            count: 30,
            preferredCapacity: 12,
            preferredTileWidth: 260,
            availableWidth: 1200,
            availableHeight: 420
        )
        XCTAssertLessThan(metrics.capacity, 12)
        XCTAssertGreaterThanOrEqual(metrics.capacity, 1)
        XCTAssertLessThanOrEqual(metrics.stripExtent, 420.001)
    }

    /// Dropping tiles frees room along the strip, and the survivors should use
    /// it rather than staying at the minimum width that forced the drop.
    func testMetricsWidenTilesAgainAfterCapacityIsReduced() {
        let metrics = SidebarLayout.metrics(
            count: 30,
            preferredCapacity: 12,
            preferredTileWidth: 340,
            availableWidth: 1200,
            availableHeight: 700
        )
        XCTAssertLessThan(metrics.capacity, 12)
        XCTAssertGreaterThan(metrics.tileWidth, 150, "the strip should not stay pinned to the minimum tile width")
        XCTAssertLessThanOrEqual(metrics.stripExtent, 700.001)
    }

    func testMetricsNeverShowMoreTilesThanWindowsOrExceedTheConfiguredRange() {
        XCTAssertEqual(metrics(capacity: 7, availableHeight: 1400).capacity, 7)
        let twoWindows = SidebarLayout.metrics(
            count: 2,
            preferredCapacity: 7,
            preferredTileWidth: 260,
            availableWidth: 1200,
            availableHeight: 1400
        )
        XCTAssertEqual(twoWindows.capacity, 2)
        // Out-of-range preferences are clamped rather than trusted.
        XCTAssertEqual(metrics(capacity: 40, availableHeight: 4000).capacity, SidebarLayout.visibleCountRange.upperBound)
        XCTAssertEqual(metrics(capacity: 0, availableHeight: 4000).capacity, SidebarLayout.visibleCountRange.lowerBound)
        XCTAssertEqual(metrics(capacity: 5, tileWidth: 900, availableHeight: 4000).tileWidth, SidebarLayout.tileWidthRange.upperBound)
    }

    func testMetricsStayFiniteAndPositiveOnAVeryShortDisplay() {
        let metrics = SidebarLayout.metrics(
            count: 12,
            preferredCapacity: 12,
            preferredTileWidth: 340,
            availableWidth: 300,
            availableHeight: 140
        )
        XCTAssertGreaterThan(metrics.tileWidth, 0)
        XCTAssertGreaterThan(metrics.tileHeight, 0)
        XCTAssertGreaterThanOrEqual(metrics.capacity, 1)
        XCTAssertTrue(metrics.tileWidth.isFinite && metrics.tileHeight.isFinite)
    }

    // MARK: - Metrics along a horizontal strip

    func testRowMetricsFillTheWidthTheWayAColumnFillsTheHeight() {
        let row = rowMetrics(capacity: 6, availableWidth: 2400)
        XCTAssertEqual(row.axis, .horizontal)
        XCTAssertEqual(row.capacity, 6)
        XCTAssertEqual(row.tileWidth, 260)
        // A row is measured across its tile widths, not their heights.
        XCTAssertEqual(row.tileExtent, row.tileWidth)
        XCTAssertLessThanOrEqual(row.stripExtent, 2400)
    }

    func testRowNarrowsTilesBeforeDroppingAnyOnANarrowDisplay() {
        // A laptop display cannot fit seven 260pt tiles across, but it can fit
        // seven narrower ones, and hiding windows is the worse trade.
        let laptop = rowMetrics(capacity: 7, availableWidth: 1450)
        XCTAssertEqual(laptop.capacity, 7)
        XCTAssertLessThan(laptop.tileWidth, 260)
        XCTAssertGreaterThanOrEqual(laptop.tileWidth, 150)
        XCTAssertLessThanOrEqual(laptop.stripExtent, 1450.001)
    }

    func testRowDropsTilesOnlyOnceTheyWouldBeUnreadablyNarrow() {
        let narrow = rowMetrics(capacity: 12, availableWidth: 1000)
        XCTAssertLessThan(narrow.capacity, 12)
        XCTAssertGreaterThanOrEqual(narrow.capacity, 1)
        XCTAssertGreaterThanOrEqual(narrow.tileWidth, 150)
        XCTAssertLessThanOrEqual(narrow.stripExtent, 1000.001)
    }

    /// The height bounds a row crosswise, so a short display makes the tiles
    /// narrower even when there is width to spare.
    func testRowTilesShrinkToFitAShortDisplayEvenWithWidthToSpare() {
        let short = SidebarLayout.metrics(
            count: 20,
            preferredCapacity: 5,
            preferredTileWidth: 340,
            axis: .horizontal,
            availableWidth: 3000,
            availableHeight: 190
        )
        XCTAssertEqual(short.capacity, 5)
        XCTAssertLessThan(short.tileWidth, 340)
        XCTAssertLessThanOrEqual(short.tileHeight, 190.001)
        XCTAssertTrue(short.tileWidth.isFinite && short.tileWidth > 0)
    }

    func testRowStaysFiniteAndPositiveOnATinyDisplay() {
        let tiny = SidebarLayout.metrics(
            count: 12,
            preferredCapacity: 12,
            preferredTileWidth: 340,
            axis: .horizontal,
            availableWidth: 200,
            availableHeight: 40
        )
        XCTAssertGreaterThan(tiny.tileWidth, 0)
        XCTAssertGreaterThan(tiny.tileHeight, 0)
        XCTAssertGreaterThanOrEqual(tiny.capacity, 1)
        XCTAssertTrue(tiny.tileWidth.isFinite && tiny.tileHeight.isFinite)
    }

    // MARK: - Placements

    func testColumnIsEvenlySpacedTopToBottomAndCenteredOnZero() {
        let metrics = metrics(capacity: 5, availableHeight: 1400)
        let placements = SidebarLayout.placements(count: 5, selection: 2, metrics: metrics)
        XCTAssertEqual(placements.count, 5)
        XCTAssertEqual(placements[2].offset, 0, accuracy: 0.0001, "an odd column centers its middle tile")
        for (upper, lower) in zip(placements, placements.dropFirst()) {
            XCTAssertEqual(upper.offset - lower.offset, metrics.tileHeight + metrics.spacing, accuracy: 0.0001)
        }
        XCTAssertEqual(placements.first!.offset, -placements.last!.offset, accuracy: 0.0001)
    }

    /// Same spacing rule as the column, but slot 0 is the leftmost tile, so the
    /// offsets run the other way.
    func testRowIsEvenlySpacedLeftToRightAndCenteredOnZero() {
        let metrics = rowMetrics(capacity: 5)
        let placements = SidebarLayout.placements(count: 5, selection: 2, metrics: metrics)
        XCTAssertEqual(placements[2].offset, 0, accuracy: 0.0001)
        XCTAssertLessThan(placements[0].offset, placements[4].offset, "slot 0 is the leftmost tile")
        for (left, right) in zip(placements, placements.dropFirst()) {
            XCTAssertEqual(right.offset - left.offset, metrics.tileWidth + metrics.spacing, accuracy: 0.0001)
        }
        XCTAssertEqual(placements.first!.offset, -placements.last!.offset, accuracy: 0.0001)
    }

    /// Everything but the direction of travel is shared between the two axes.
    func testRowAndColumnAgreeOnEverythingExceptDirection() {
        let column = SidebarLayout.placements(count: 20, selection: 10, metrics: metrics(capacity: 5, availableHeight: 1400))
        let row = SidebarLayout.placements(count: 20, selection: 10, metrics: rowMetrics(capacity: 5))
        for (columnPlacement, rowPlacement) in zip(column, row) {
            XCTAssertEqual(columnPlacement.slot, rowPlacement.slot)
            XCTAssertEqual(columnPlacement.scale, rowPlacement.scale)
            XCTAssertEqual(columnPlacement.opacity, rowPlacement.opacity)
            XCTAssertEqual(columnPlacement.isVisible, rowPlacement.isVisible)
        }
    }

    func testSelectedTileIsFullSizeAndOpaqueWhileOthersRecede() {
        let placements = SidebarLayout.placements(count: 5, selection: 1, metrics: metrics(capacity: 5, availableHeight: 1400))
        XCTAssertEqual(placements[1].scale, 1)
        XCTAssertEqual(placements[1].opacity, 1)
        for index in [0, 2, 3, 4] {
            XCTAssertLessThan(placements[index].scale, 1)
            XCTAssertLessThan(placements[index].opacity, 1)
            XCTAssertGreaterThan(placements[index].opacity, 0)
        }
    }

    func testOffViewportTilesAreHiddenJustPastTheEndTheyLeftThrough() {
        let metrics = metrics(capacity: 5, availableHeight: 1400)
        let placements = SidebarLayout.placements(count: 20, selection: 10, metrics: metrics)
        let viewport = SidebarLayout.viewport(count: 20, selection: 10, capacity: 5)
        for (index, placement) in placements.enumerated() {
            let isVisible = index >= viewport.firstIndex && index < viewport.firstIndex + viewport.capacity
            XCTAssertEqual(placement.isVisible, isVisible, "index \(index)")
            guard !isVisible else { continue }
            XCTAssertEqual(placement.opacity, 0)
            XCTAssertEqual(placement.slot, index < viewport.firstIndex ? -1 : viewport.capacity)
        }
        // The tile above the strip sits higher than the topmost visible one.
        XCTAssertGreaterThan(placements[0].offset, placements[viewport.firstIndex].offset)
        XCTAssertLessThan(placements[19].offset, placements[viewport.firstIndex + viewport.capacity - 1].offset)
    }

    /// The same parking rule mirrored: a row's hidden tiles wait off its left
    /// and right ends rather than above and below.
    func testOffViewportRowTilesParkPastTheLeftAndRightEnds() {
        let metrics = rowMetrics(capacity: 5)
        let placements = SidebarLayout.placements(count: 20, selection: 10, metrics: metrics)
        let viewport = SidebarLayout.viewport(count: 20, selection: 10, capacity: 5)
        XCTAssertLessThan(placements[0].offset, placements[viewport.firstIndex].offset)
        XCTAssertGreaterThan(placements[19].offset, placements[viewport.firstIndex + viewport.capacity - 1].offset)
        XCTAssertEqual(placements[0].opacity, 0)
        XCTAssertEqual(placements[19].opacity, 0)
    }

    func testBoundaryTilesFadeOnlyOnTheSideThatStillHasHiddenWindows() {
        let metrics = metrics(capacity: 5, availableHeight: 1400)
        let atTop = SidebarLayout.placements(count: 20, selection: 0, metrics: metrics)
        XCTAssertEqual(atTop[0].opacity, 1, "the selection is never dimmed")
        XCTAssertLessThan(atTop[4].opacity, atTop[3].opacity, "the bottom tile hints at more windows below")

        let middle = SidebarLayout.placements(count: 20, selection: 10, metrics: metrics)
        let viewport = SidebarLayout.viewport(count: 20, selection: 10, capacity: 5)
        let first = viewport.firstIndex
        let last = first + viewport.capacity - 1
        XCTAssertLessThan(middle[first].opacity, middle[first + 1].opacity)
        XCTAssertLessThan(middle[last].opacity, middle[last - 1].opacity)
        XCTAssertLessThan(middle[first].scale, middle[first + 1].scale)
    }

    func testShortListsHaveNoBoundaryFadeBecauseNothingIsHidden() {
        let placements = SidebarLayout.placements(count: 4, selection: 1, metrics: metrics(capacity: 7, availableHeight: 1400))
        XCTAssertTrue(placements.allSatisfy(\.isVisible))
        for index in [0, 2, 3] {
            XCTAssertEqual(placements[index].opacity, placements[2].opacity, accuracy: 0.0001)
        }
    }

    func testEmptyAndSingleWindowStrips() {
        for metrics in [metrics(capacity: 7, availableHeight: 1400), rowMetrics(capacity: 7)] {
            XCTAssertTrue(SidebarLayout.placements(count: 0, selection: 0, metrics: metrics).isEmpty)
            let one = SidebarLayout.placements(count: 1, selection: 0, metrics: metrics)
            XCTAssertEqual(one.count, 1)
            XCTAssertEqual(one[0].offset, 0, accuracy: 0.0001)
            XCTAssertEqual(one[0].scale, 1)
            XCTAssertEqual(one[0].opacity, 1)
        }
    }

    func testSteppingThroughEveryWindowKeepsTheSelectionOnScreen() {
        for metrics in [metrics(capacity: 6, availableHeight: 1400), rowMetrics(capacity: 6)] {
            // One full loop plus a wrap, the way holding Tab walks the list.
            for step in 0...25 {
                let selection = Flip3DLayout.wrappedIndex(step, count: 25)
                let placements = SidebarLayout.placements(count: 25, selection: selection, metrics: metrics)
                XCTAssertTrue(placements[selection].isVisible, "selection \(selection) fell off the strip")
                XCTAssertEqual(placements[selection].opacity, 1)
                XCTAssertEqual(placements.filter(\.isVisible).count, metrics.capacity)
            }
        }
    }
}
