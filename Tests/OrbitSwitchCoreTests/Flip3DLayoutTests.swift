import XCTest
@testable import OrbitSwitchCore

final class Flip3DLayoutTests: XCTestCase {
    private let perspective = 0.00115

    /// On-screen position/scale after the m34 projection divides by w.
    private func projected(_ placement: Flip3DPlacement) -> (x: Double, y: Double, scale: Double) {
        let w = 1 - perspective * placement.z
        return (placement.x / w, placement.y / w, placement.scale / w)
    }

    func testSelectionWrapsInBothDirections() {
        XCTAssertEqual(Flip3DLayout.wrappedIndex(-1, count: 4), 3)
        XCTAssertEqual(Flip3DLayout.wrappedIndex(4, count: 4), 0)
        XCTAssertEqual(Flip3DLayout.wrappedIndex(20, count: 0), 0)
    }

    func testEmptyAndSingleWindowGeometry() {
        XCTAssertTrue(Flip3DLayout.placements(count: 0, selection: 0, spacing: 60, angle: 12).isEmpty)
        let one = Flip3DLayout.placements(count: 1, selection: 0, spacing: 60, angle: 12)
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one[0].relativeIndex, 0)
        XCTAssertEqual(one[0].opacity, 1)
    }

    func testSelectedCardIsFrontmostAndCentered() {
        let placements = Flip3DLayout.placements(count: 5, selection: 2, spacing: 60, angle: 12)
        XCTAssertEqual(placements[2].x, 0)
        XCTAssertEqual(placements[2].y, 0)
        XCTAssertEqual(placements[2].z, 0)
        XCTAssertEqual(placements[2].scale, 1)
        XCTAssertLessThan(placements[3].z, placements[2].z)
    }

    func testWholeStackSharesTheSameYaw() {
        let placements = Flip3DLayout.placements(count: 4, selection: 1, spacing: 60, angle: 12)
        for placement in placements {
            XCTAssertEqual(placement.angleDegrees, -12)
        }
    }

    func testStaircaseStepsUpLeftAndRecedes() {
        let placements = Flip3DLayout.placements(count: 8, selection: 0, spacing: 66, angle: 13)
            .sorted { $0.relativeIndex < $1.relativeIndex }
        for (front, back) in zip(placements, placements.dropFirst()) {
            let frontProjected = projected(front)
            let backProjected = projected(back)
            XCTAssertLessThan(backProjected.x, frontProjected.x, "each card must move left on screen")
            XCTAssertGreaterThan(backProjected.y, frontProjected.y, "each card must move up on screen")
            XCTAssertLessThan(back.z, front.z, "each card must recede in Z")
            XCTAssertLessThan(backProjected.scale, frontProjected.scale, "each card must shrink on screen")
            XCTAssertLessThanOrEqual(back.opacity, front.opacity)
        }
    }

    func testTopAndLeftEdgesStayVisibleForEveryDepth() {
        // Nominal full-size card used by the overlay (820 x 560, anchored at center).
        let halfWidth = 410.0
        let halfHeight = 280.0
        let placements = Flip3DLayout.placements(count: 13, selection: 0, spacing: 66, angle: 13)
            .sorted { $0.relativeIndex < $1.relativeIndex }
        for (front, back) in zip(placements, placements.dropFirst()) {
            let frontProjected = projected(front)
            let backProjected = projected(back)
            let frontLeft = frontProjected.x - halfWidth * frontProjected.scale
            let backLeft = backProjected.x - halfWidth * backProjected.scale
            let frontTop = frontProjected.y + halfHeight * frontProjected.scale
            let backTop = backProjected.y + halfHeight * backProjected.scale
            XCTAssertLessThan(backLeft, frontLeft, "left edge of the deeper card must peek out")
            XCTAssertGreaterThan(backTop, frontTop, "top edge of the deeper card must peek out")
        }
    }

    func testStaircaseStaysWithinTravelBudget() {
        let horizontal = 460.0
        let vertical = 300.0
        let placements = Flip3DLayout.placements(
            count: 40,
            selection: 5,
            spacing: 110,
            angle: 13,
            horizontalTravel: horizontal,
            verticalTravel: vertical
        )
        for placement in placements {
            let onScreen = projected(placement)
            XCTAssertGreaterThanOrEqual(onScreen.x, -horizontal * 1.0001)
            XCTAssertLessThanOrEqual(onScreen.y, vertical * 1.0001)
        }
    }

    func testZeroPerspectiveEmitsPlainOffsets() {
        let placements = Flip3DLayout.placements(count: 3, selection: 0, spacing: 24, angle: 0, perspective: 0)
            .sorted { $0.relativeIndex < $1.relativeIndex }
        XCTAssertLessThan(placements[1].x, 0)
        XCTAssertGreaterThan(placements[1].y, 0)
        XCTAssertLessThanOrEqual(placements[1].scale, 1)
    }

    func testSelectionChangesCardAssignmentsWithoutChangingStackSlots() {
        let baseline = Flip3DLayout.placements(count: 8, selection: 0, spacing: 60, angle: 12)
            .sorted { $0.relativeIndex < $1.relativeIndex }
        for selection in 1..<8 {
            let slots = Flip3DLayout.placements(count: 8, selection: selection, spacing: 60, angle: 12)
                .sorted { $0.relativeIndex < $1.relativeIndex }
            XCTAssertEqual(slots, baseline)
        }
    }
}
