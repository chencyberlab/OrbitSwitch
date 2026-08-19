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
        let hidden = window(onScreen: false, minimized: false, hiddenApp: true)
        var settings = AppSettings()
        XCTAssertFalse(WindowFilter.isEligible(hidden, settings: settings, ownPID: 10))
        settings.includeHiddenApps = true
        XCTAssertTrue(WindowFilter.isEligible(hidden, settings: settings, ownPID: 10))
    }

    func testUtilityPanelFilteringCanBeDisabled() {
        let utilityPanel = window(layer: 3)
        var settings = AppSettings()
        XCTAssertFalse(WindowFilter.isEligible(utilityPanel, settings: settings, ownPID: 10))
        settings.ignoreUtilityPanels = false
        XCTAssertTrue(WindowFilter.isEligible(utilityPanel, settings: settings, ownPID: 10))
    }

    // MARK: - Dock peek

    /// The question a Dock peek answers is "what does this application have
    /// open", so a window minimized into the Dock has to be in the answer — it
    /// is one of the windows hardest to reach any other way.
    func testDockPeekShowsMinimizedWindowsEvenWhenTheSwitcherIsSetNotTo() {
        var settings = AppSettings()
        settings.includeMinimized = false
        let minimized = window(title: "Minimized", onScreen: false, minimized: true)

        XCTAssertFalse(WindowFilter.isEligible(minimized, settings: settings, ownPID: 1))
        XCTAssertTrue(WindowFilter.isEligible(minimized, settings: settings.dockPeekDiscovery, ownPID: 1))
    }

    /// Same for a window on another Desktop and one belonging to a hidden
    /// application, which the switcher's defaults also leave out.
    func testDockPeekShowsOffSpaceAndHiddenApplicationWindows() {
        let settings = AppSettings()
        let otherSpace = window(title: "Other Desktop", onScreen: false, minimized: false)
        let hidden = window(title: "Hidden App", onScreen: false, minimized: false, hiddenApp: true)

        XCTAssertFalse(WindowFilter.isEligible(otherSpace, settings: settings, ownPID: 1))
        XCTAssertFalse(WindowFilter.isEligible(hidden, settings: settings, ownPID: 1))
        XCTAssertTrue(WindowFilter.isEligible(otherSpace, settings: settings.dockPeekDiscovery, ownPID: 1))
        XCTAssertTrue(WindowFilter.isEligible(hidden, settings: settings.dockPeekDiscovery, ownPID: 1))
    }

    /// A minimized window that Accessibility could not positively identify stays
    /// out. An unknown off-screen window is as likely to be a background utility
    /// surface as a real one, and guessing wrong puts junk on the panel.
    func testDockPeekStillExcludesOffScreenWindowsItCannotIdentify() {
        let unknown = window(title: "Unknown", onScreen: false, minimized: nil)
        XCTAssertFalse(WindowFilter.isEligible(unknown, settings: AppSettings().dockPeekDiscovery, ownPID: 1))
    }

    /// The filters that say "this is not a window I want to see" are the user's,
    /// and they hold however the user went looking.
    func testDockPeekKeepsTheUsersOwnSizeAndExclusionFilters() {
        var settings = AppSettings()
        settings.excludedBundleIdentifiers = ["com.example.app"]
        settings.minimumWindowWidth = 400
        let excluded = window(title: "Excluded")
        let tiny = window(bundleID: "com.example.other", title: "Tiny", width: 120)

        XCTAssertFalse(WindowFilter.isEligible(excluded, settings: settings.dockPeekDiscovery, ownPID: 1))
        XCTAssertFalse(WindowFilter.isEligible(tiny, settings: settings.dockPeekDiscovery, ownPID: 1))
    }

    /// Peek is already scoped to one application, so grouping would collapse the
    /// whole panel to a single card.
    func testDockPeekNeverGroupsByApplication() {
        var settings = AppSettings()
        settings.groupByApplication = true
        let windows = [window(id: 1, title: "One"), window(id: 2, title: "Two")]

        XCTAssertEqual(WindowFilter.filtered(windows, settings: settings, ownPID: 1).count, 1)
        XCTAssertEqual(WindowFilter.filtered(windows, settings: settings.dockPeekDiscovery, ownPID: 1).count, 2)
    }
}
