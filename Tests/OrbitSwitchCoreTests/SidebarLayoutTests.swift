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
        XCTAssertLessThanOrEqual(metrics.columnHeight, 1400)
    }

    func testMetricsNarrowTilesBeforeDroppingAnyFromTheStrip() {
        let roomy = metrics(capacity: 8, availableHeight: 1800)
        let tight = metrics(capacity: 8, availableHeight: 1250)
        XCTAssertEqual(tight.capacity, roomy.capacity, "a shorter display must not silently hide windows")
        XCTAssertLessThan(tight.tileWidth, roomy.tileWidth)
        XCTAssertLessThanOrEqual(tight.columnHeight, 1250.001)
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
        XCTAssertLessThanOrEqual(metrics.columnHeight, 420.001)
    }

    /// Dropping tiles frees vertical room, and the survivors should use it
    /// rather than staying at the minimum width that forced the drop.
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
        XCTAssertLessThanOrEqual(metrics.columnHeight, 700.001)
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

    // MARK: - Placements

    func testColumnIsEvenlySpacedTopToBottomAndCenteredOnZero() {
        let metrics = metrics(capacity: 5, availableHeight: 1400)
        let placements = SidebarLayout.placements(count: 5, selection: 2, metrics: metrics)
        XCTAssertEqual(placements.count, 5)
        XCTAssertEqual(placements[2].y, 0, accuracy: 0.0001, "an odd column centers its middle tile")
        for (upper, lower) in zip(placements, placements.dropFirst()) {
            XCTAssertEqual(upper.y - lower.y, metrics.tileHeight + metrics.spacing, accuracy: 0.0001)
        }
        XCTAssertEqual(placements.first!.y, -placements.last!.y, accuracy: 0.0001)
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
        XCTAssertGreaterThan(placements[0].y, placements[viewport.firstIndex].y)
        XCTAssertLessThan(placements[19].y, placements[viewport.firstIndex + viewport.capacity - 1].y)
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
        let metrics = metrics(capacity: 7, availableHeight: 1400)
        XCTAssertTrue(SidebarLayout.placements(count: 0, selection: 0, metrics: metrics).isEmpty)
        let one = SidebarLayout.placements(count: 1, selection: 0, metrics: metrics)
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one[0].y, 0, accuracy: 0.0001)
        XCTAssertEqual(one[0].scale, 1)
        XCTAssertEqual(one[0].opacity, 1)
    }

    func testSteppingThroughEveryWindowKeepsTheSelectionOnScreen() {
        let metrics = metrics(capacity: 6, availableHeight: 1400)
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
