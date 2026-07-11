import XCTest
@testable import OrbitSwitchCore

final class SettingsStoreTests: XCTestCase {
    func testDefaultsUseOptionTabNotCommandTab() {
        let settings = AppSettings()
        XCTAssertEqual(settings.shortcuts[.showNext], .init(keyCode: 48, modifiers: [.option]))
        XCTAssertNotEqual(settings.shortcuts[.showNext], .init(keyCode: 48, modifiers: [.command]))
        XCTAssertTrue(settings.includeMinimized)
        XCTAssertEqual(settings.schemaVersion, 2)
    }

    func testPersistenceRoundTrip() throws {
        let suite = "OrbitSwitchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        var settings = AppSettings()
        settings.stackAngle = 21
        settings.includeMinimized = true
        persistence.save(settings)
        XCTAssertEqual(persistence.load(), settings)
    }

    func testMigratesLegacyShortcutSettings() throws {
        let suite = "OrbitSwitchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = #"{"shortcuts":{"showNext":{"keyCode":13,"modifiers":4}},"showDockIcon":true}"#
        defaults.set(Data(legacy.utf8), forKey: "appSettings.v1")
        let migrated = SettingsPersistence(defaults: defaults).load()
        XCTAssertEqual(migrated.shortcuts[.showNext], .init(keyCode: 13, modifiers: [.control]))
        XCTAssertTrue(migrated.showDockIcon)
        XCTAssertEqual(migrated.schemaVersion, 2)
    }

    func testMigratesVersionOneAppearanceAndMinimizedDefaults() throws {
        let suite = "OrbitSwitchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var versionOne = AppSettings()
        versionOne.schemaVersion = 1
        versionOne.includeMinimized = false
        versionOne.backgroundBlur = 24
        defaults.set(try JSONEncoder().encode(versionOne), forKey: "appSettings.v1")
        let migrated = SettingsPersistence(defaults: defaults).load()
        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertTrue(migrated.includeMinimized)
        XCTAssertEqual(migrated.backgroundBlur, 57.6, accuracy: 0.001)
    }
}
