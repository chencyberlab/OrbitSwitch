import CoreGraphics
import XCTest
@testable import OrbitSwitchCore

final class WindowFilteringTests: XCTestCase {
    private func window(
        id: CGWindowID = 1,
        pid: pid_t = 20,
        app: String = "Example",
        bundleID: String? = "com.example.app",
        title: String = "Document",
        width: CGFloat = 800,
        height: CGFloat = 600,
        layer: Int = 0,
        onScreen: Bool = true,
        minimized: Bool? = nil,
        regularApp: Bool = true,
        hiddenApp: Bool = false
    ) -> WindowMetadata {
        WindowMetadata(
            id: id, ownerPID: pid, appName: app, bundleIdentifier: bundleID, title: title,
            frame: CGRect(x: 0, y: 0, width: width, height: height), layer: layer, alpha: 1,
            isOnScreen: onScreen, isMinimized: minimized,
            isRegularApplication: regularApp, isApplicationHidden: hiddenApp
        )
    }

    func testFiltersOwnTinyAndNonzeroLayerWindows() {
        let values = [
            window(id: 1, pid: 10),
            window(id: 2, width: 40),
            window(id: 3, layer: 3),
            window(id: 4)
        ]
        XCTAssertEqual(WindowFilter.filtered(values, settings: AppSettings(), ownPID: 10).map(\.id), [4])
    }

    func testUntitledAndExcludedAppsAreConfigurable() {
        var settings = AppSettings()
        settings.includeUntitled = false
        settings.excludedBundleIdentifiers = ["com.example.excluded"]
        let values = [window(id: 1, title: ""), window(id: 2, bundleID: "com.example.excluded"), window(id: 3)]
        XCTAssertEqual(WindowFilter.filtered(values, settings: settings, ownPID: 10).map(\.id), [3])
    }

    func testGroupingKeepsFrontmostWindowPerApplication() {
        var settings = AppSettings()
        settings.groupByApplication = true
        let values = [window(id: 1), window(id: 2), window(id: 3, bundleID: "com.other")]
        XCTAssertEqual(WindowFilter.filtered(values, settings: settings, ownPID: 10).map(\.id), [1, 3])
    }

    func testMinimizedWindowsFollowPreference() {
        let minimized = window(onScreen: false, minimized: true)
        var settings = AppSettings()
        XCTAssertTrue(WindowFilter.isEligible(minimized, settings: settings, ownPID: 10))
        settings.includeMinimized = false
        XCTAssertFalse(WindowFilter.isEligible(minimized, settings: settings, ownPID: 10))
    }

    func testOffSpaceWindowRequiresCurrentSpaceSettingToBeDisabled() {
        let offSpace = window(onScreen: false, minimized: false)
        var settings = AppSettings()
        XCTAssertFalse(WindowFilter.isEligible(offSpace, settings: settings, ownPID: 10))
        settings.currentSpaceOnly = false
        XCTAssertTrue(WindowFilter.isEligible(offSpace, settings: settings, ownPID: 10))
    }

    func testUnknownOffscreenAndMenuBarAppsAreExcluded() {
        let unknownOffscreen = window(id: 1, onScreen: false, minimized: nil)
        let menuBarUtility = window(id: 2, regularApp: false)
        let values = [unknownOffscreen, menuBarUtility, window(id: 3)]
        XCTAssertEqual(WindowFilter.filtered(values, settings: AppSettings(), ownPID: 10).map(\.id), [3])
    }

    func testHiddenAppsRespectPreference() {
        let hidden = window(hiddenApp: true)
        var settings = AppSettings()
        XCTAssertFalse(WindowFilter.isEligible(hidden, settings: settings, ownPID: 10))
        settings.includeHiddenApps = true
        XCTAssertTrue(WindowFilter.isEligible(hidden, settings: settings, ownPID: 10))
    }
}
