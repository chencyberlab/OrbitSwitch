import XCTest
@testable import OrbitSwitchCore

final class ShortcutConflictTests: XCTestCase {
    func testDetectsDuplicateInternalShortcut() {
        let shortcut = ShortcutDefinition(keyCode: 48, modifiers: [.option])
        let conflict = ShortcutConflictDetector.conflict(
            for: shortcut,
            action: .previous,
            configured: [.showNext: shortcut]
        )
        XCTAssertEqual(conflict, .duplicate(.showNext))
    }

    func testWarnsForCommandTab() {
        let conflict = ShortcutConflictDetector.conflict(
            for: .init(keyCode: 48, modifiers: [.command]),
            action: .showNext,
            configured: [:]
        )
        XCTAssertEqual(conflict, .commonSystemShortcut("Command-Tab"))
    }

    func testShortcutCodableRoundTrip() throws {
        let original = ShortcutDefinition(keyCode: 13, modifiers: [.control, .shift])
        XCTAssertEqual(try JSONDecoder().decode(ShortcutDefinition.self, from: JSONEncoder().encode(original)), original)
    }

    func testHoldBehaviorConfirmsOnOptionRatherThanTabOrDirectionShift() {
        let forward = ShortcutDefinition(keyCode: 48, modifiers: [.option])
        let reverse = ShortcutDefinition(keyCode: 48, modifiers: [.option, .shift])
        XCTAssertEqual(ShortcutHoldBehavior.confirmationModifiers(for: .showNext, shortcut: forward), [.option])
        XCTAssertEqual(ShortcutHoldBehavior.confirmationModifiers(for: .previous, shortcut: reverse), [.option])
    }

    func testGlobalRegistrationRequiresModifier() {
        XCTAssertFalse(ShortcutDefinition(keyCode: 0, modifiers: []).isSuitableForGlobalRegistration)
        XCTAssertTrue(ShortcutDefinition(keyCode: 0, modifiers: [.option]).isSuitableForGlobalRegistration)
    }
}
