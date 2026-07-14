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
        let persistedData = try XCTUnwrap(defaults.data(forKey: "appSettings.v1"))
        XCTAssertNoThrow(try JSONDecoder().decode(AppSettings.self, from: persistedData))
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

    func testDisplayPreferenceResetsWhenRememberingIsDisabled() throws {
        let suite = "OrbitSwitchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        var settings = AppSettings()
        settings.displayMode = .all
        settings.rememberDisplayPreference = false
        persistence.save(settings)
        XCTAssertEqual(persistence.load().displayMode, .pointer)
    }

    func testPersistenceKeepsAtLeastOneApplicationEntryVisible() throws {
        let suite = "OrbitSwitchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        var settings = AppSettings()
        settings.showMenuBarIcon = false
        settings.showDockIcon = false
        persistence.save(settings)
        let loaded = persistence.load()
        XCTAssertTrue(loaded.showMenuBarIcon)
        XCTAssertFalse(loaded.showDockIcon)
    }

    func testDecodingToleratesMissingNewFieldsWithoutResettingSettings() throws {
        var settings = AppSettings()
        settings.stackAngle = 21
        settings.backgroundBlur = 40
        var payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        )
        payload.removeValue(forKey: "showWindowControls")
        let data = try JSONSerialization.data(withJSONObject: payload)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertTrue(decoded.showWindowControls)
        XCTAssertEqual(decoded.stackAngle, 21)
        XCTAssertEqual(decoded.backgroundBlur, 40)
    }

    func testDecodingRequiresSchemaVersionSoLegacyPayloadsStillMigrate() {
        let legacy = Data(#"{"shortcuts":{"showNext":{"keyCode":13,"modifiers":4}},"showDockIcon":true}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AppSettings.self, from: legacy))
    }

    func testPersistenceRemovesUnsafeModifierlessGlobalShortcuts() throws {
        let suite = "OrbitSwitchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        var settings = AppSettings()
        settings.shortcuts[.showNext] = ShortcutDefinition(keyCode: 0, modifiers: [])
        persistence.save(settings)

        XCTAssertNil(persistence.load().shortcuts[.showNext])
        let persistedData = try XCTUnwrap(defaults.data(forKey: "appSettings.v1"))
        let persisted = try JSONDecoder().decode(AppSettings.self, from: persistedData)
        XCTAssertNil(persisted.shortcuts[.showNext])
    }
}
