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

    func testDefaultsKeepTheOrbitStyleForExistingUsers() {
        let settings = AppSettings()
        XCTAssertEqual(settings.overlayStyle, .orbit)
        XCTAssertEqual(settings.sidebarEdge, .left)
        XCTAssertEqual(settings.sidebarVisibleCount, 7)
    }

    /// The view picks its layout axis from the edge alone, so this mapping is
    /// what makes a top or bottom strip a row rather than a column.
    func testEachScreenEdgeMapsToTheAxisItsStripRunsAlong() {
        XCTAssertEqual(SidebarEdge.left.axis, .vertical)
        XCTAssertEqual(SidebarEdge.right.axis, .vertical)
        XCTAssertEqual(SidebarEdge.top.axis, .horizontal)
        XCTAssertEqual(SidebarEdge.bottom.axis, .horizontal)
        XCTAssertEqual(SidebarEdge.allCases.count, 4)
    }

    func testEveryScreenEdgeSurvivesAPersistenceRoundTrip() throws {
        for edge in SidebarEdge.allCases {
            let suite = "OrbitSwitchTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let persistence = SettingsPersistence(defaults: defaults)
            var settings = AppSettings()
            settings.overlayStyle = .sidebar
            settings.sidebarEdge = edge
            persistence.save(settings)
            XCTAssertEqual(persistence.load().sidebarEdge, edge)
        }
    }

    func testPersistenceClampsOutOfRangeSidebarValues() throws {
        let suite = "OrbitSwitchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        var settings = AppSettings()
        settings.sidebarVisibleCount = 99
        settings.sidebarTileWidth = 4000
        persistence.save(settings)

        let loaded = persistence.load()
        XCTAssertEqual(loaded.sidebarVisibleCount, SidebarLayout.visibleCountRange.upperBound)
        XCTAssertEqual(loaded.sidebarTileWidth, SidebarLayout.tileWidthRange.upperBound)
    }

    func testDecodingSettingsWrittenBeforeTheSidebarStyleExisted() throws {
        var settings = AppSettings()
        settings.stackAngle = 21
        var payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        )
        ["overlayStyle", "sidebarEdge", "sidebarVisibleCount", "sidebarTileWidth"].forEach {
            payload.removeValue(forKey: $0)
        }
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(decoded.overlayStyle, .orbit)
        XCTAssertEqual(decoded.sidebarEdge, .left)
        XCTAssertEqual(decoded.sidebarVisibleCount, 7)
        XCTAssertEqual(decoded.sidebarTileWidth, 260)
        XCTAssertEqual(decoded.stackAngle, 21)
    }

    func testPersistenceRoundTrip() throws {
        let suite = "OrbitSwitchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        var settings = AppSettings()
        settings.stackAngle = -21
        settings.includeMinimized = true
        persistence.save(settings)
        XCTAssertEqual(persistence.load(), settings)
    }

    func testPersistenceClampsPositiveStackAngles() throws {
        let suite = "OrbitSwitchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        var settings = AppSettings()
        settings.stackAngle = 21
        persistence.save(settings)

        XCTAssertEqual(persistence.load().stackAngle, 0)
        XCTAssertEqual(persistence.load().stackAngle, Flip3DLayout.stackAngleRange.upperBound)
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

    func testDecodingToleratesUnknownOrMalformedIndividualFields() throws {
        var settings = AppSettings()
        settings.stackAngle = -21
        settings.showAppName = false
        var payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        )
        payload["theme"] = "future-theme"
        payload["dockPeekTileWidth"] = "very wide"
        payload["includeHiddenApps"] = ["not", "a", "boolean"]

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )

        XCTAssertEqual(decoded.theme, AppSettings().theme)
        XCTAssertEqual(decoded.dockPeekTileWidth, AppSettings().dockPeekTileWidth)
        XCTAssertEqual(decoded.includeHiddenApps, AppSettings().includeHiddenApps)
        XCTAssertEqual(decoded.stackAngle, -21, "valid neighboring settings must survive")
        XCTAssertFalse(decoded.showAppName, "valid neighboring settings must survive")
    }

    func testDockPeekIsOffByDefault() {
        let settings = AppSettings()
        XCTAssertFalse(settings.dockPeekEnabled)
        XCTAssertEqual(settings.dockPeekHoverDelay, 0.25)
        XCTAssertEqual(settings.dockPeekTileWidth, 220)
        XCTAssertTrue(settings.dockPeekShowControls)
        XCTAssertTrue(settings.dockPeekShowAppIcon)
        XCTAssertTrue(settings.dockPeekShowWindowTitle)
        // Redundant on a panel opened by pointing at that app's own icon.
        XCTAssertFalse(settings.dockPeekShowAppName)
    }

    func testPersistenceClampsOutOfRangeDockPeekValues() throws {
        let suite = "OrbitSwitchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        var settings = AppSettings()
        settings.dockPeekHoverDelay = 30
        settings.dockPeekTileWidth = 4000
        persistence.save(settings)

        let loaded = persistence.load()
        XCTAssertEqual(loaded.dockPeekHoverDelay, DockPeekLayout.hoverDelayRange.upperBound)
        XCTAssertEqual(loaded.dockPeekTileWidth, DockPeekLayout.tileWidthRange.upperBound)
    }

    func testPersistenceClampsEveryNumericSettingUsedByRenderingAndFiltering() throws {
        let suite = "OrbitSwitchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        var settings = AppSettings()
        settings.perspectiveStrength = 99
        settings.cardSpacing = -99
        settings.animationDuration = 99
        settings.backgroundBlur = -99
        settings.minimumWindowWidth = 99_000
        settings.minimumWindowHeight = -99
        persistence.save(settings)

        let loaded = persistence.load()
        XCTAssertEqual(loaded.perspectiveStrength, AppSettings.perspectiveStrengthRange.upperBound)
        XCTAssertEqual(loaded.cardSpacing, AppSettings.cardSpacingRange.lowerBound)
        XCTAssertEqual(loaded.animationDuration, AppSettings.animationDurationRange.upperBound)
        XCTAssertEqual(loaded.backgroundBlur, AppSettings.backgroundDimmingRange.lowerBound)
        XCTAssertEqual(loaded.minimumWindowWidth, AppSettings.minimumWindowWidthRange.upperBound)
        XCTAssertEqual(loaded.minimumWindowHeight, AppSettings.minimumWindowHeightRange.lowerBound)
    }

    func testPersistenceNormalizesExcludedBundleIdentifiers() throws {
        let suite = "OrbitSwitchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        var settings = AppSettings()
        settings.excludedBundleIdentifiers = ["  com.example.one ", "", "com.example.two", "com.example.one"]
        persistence.save(settings)

        XCTAssertEqual(persistence.load().excludedBundleIdentifiers, ["com.example.one", "com.example.two"])
    }

    /// Settings saved before Dock Peek existed must load unchanged, with the
    /// feature off rather than silently switched on.
    func testDecodingSettingsWrittenBeforeDockPeekExisted() throws {
        var settings = AppSettings()
        settings.stackAngle = -21
        var payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        )
        [
            "dockPeekEnabled", "dockPeekHoverDelay", "dockPeekTileWidth", "dockPeekShowControls",
            "dockPeekShowAppIcon", "dockPeekShowAppName", "dockPeekShowWindowTitle"
        ].forEach {
            payload.removeValue(forKey: $0)
        }
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertFalse(decoded.dockPeekEnabled)
        XCTAssertEqual(decoded.dockPeekHoverDelay, 0.25)
        XCTAssertEqual(decoded.dockPeekTileWidth, 220)
        XCTAssertTrue(decoded.dockPeekShowControls)
        XCTAssertTrue(decoded.dockPeekShowAppIcon)
        XCTAssertFalse(decoded.dockPeekShowAppName)
        XCTAssertTrue(decoded.dockPeekShowWindowTitle)
        XCTAssertEqual(decoded.stackAngle, -21)
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

    func testPersistenceRemovesShortcutsWithUnknownModifierBits() throws {
        let suite = "OrbitSwitchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = SettingsPersistence(defaults: defaults)
        var settings = AppSettings()
        let unknown = ShortcutModifiers(rawValue: 1 << 12)
        settings.shortcuts[.showNext] = ShortcutDefinition(keyCode: 0, modifiers: unknown)
        settings.shortcuts[.dismiss] = ShortcutDefinition(keyCode: 53, modifiers: unknown)
        persistence.save(settings)

        let loaded = persistence.load()
        XCTAssertNil(loaded.shortcuts[.showNext])
        XCTAssertNil(loaded.shortcuts[.dismiss])
    }
}
