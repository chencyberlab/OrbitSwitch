import XCTest
@testable import OrbitSwitchCore

final class Flip3DLayoutTests: XCTestCase {
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

    func testSelectedCardIsFrontmost() {
        let placements = Flip3DLayout.placements(count: 5, selection: 2, spacing: 60, angle: 12)
        XCTAssertEqual(placements[2].z, 0)
        XCTAssertEqual(placements[2].scale, 1)
        XCTAssertLessThan(placements[3].z, placements[2].z)
        XCTAssertLessThan(placements[3].x, placements[2].x)
        XCTAssertGreaterThan(placements[3].y, placements[2].y)
        XCTAssertEqual(placements[3].x, -55.2, accuracy: 0.001)
        XCTAssertEqual(placements[3].y, 46, accuracy: 0.001)
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
