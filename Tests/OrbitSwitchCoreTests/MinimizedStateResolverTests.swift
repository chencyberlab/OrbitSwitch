import CoreGraphics
import XCTest
@testable import OrbitSwitchCore

final class MinimizedStateResolverTests: XCTestCase {
    private func window(
        id: CGWindowID,
        pid: pid_t = 91245,
        title: String,
        onScreen: Bool
    ) -> WindowMetadata {
        WindowMetadata(
            id: id,
            ownerPID: pid,
            appName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            title: title,
            frame: CGRect(x: 0, y: 0, width: 1280, height: 800),
            layer: 0,
            alpha: 1,
            isOnScreen: onScreen
        )
    }

    /// The regression this type exists for, taken from a real Chrome session.
    /// Chrome appends its profile or Incognito marker to the Accessibility title
    /// but not to the Core Graphics one, so the previous title comparison never
    /// matched and every minimized Chrome window was discarded as unknown —
    /// which dropped it from both the switcher and Dock Peek.
    func testAWindowWhoseTwoTitlesDifferIsStillIdentifiedAsMinimized() {
        var windows = [
            window(id: 29794, title: "Sign in to your account", onScreen: true),
            window(id: 29779, title: "Home | Salesforce", onScreen: false),
            window(id: 28364, title: "Inbox - Chen Li - Outlook", onScreen: false)
        ]
        MinimizedStateResolver.apply(
            to: &windows,
            minimizedByWindowID: [29779: true, 28364: true, 29794: false]
        )
        XCTAssertNil(windows[0].isMinimized, "an on-screen window is never asked about")
        XCTAssertEqual(windows[1].isMinimized, true)
        XCTAssertEqual(windows[2].isMinimized, true)

        // What the title comparison alone would have produced: nothing matches,
        // so both minimized windows resolve to unknown and get filtered out.
        var titleOnly = windows.map { metadata -> WindowMetadata in
            var copy = metadata
            copy.isMinimized = nil
            return copy
        }
        MinimizedStateResolver.apply(
            to: &titleOnly,
            minimizedByWindowID: [:],
            unidentifiedByPID: [91245: [
                .init(title: "Home | Salesforce - Google Chrome (Incognito)", isMinimized: true),
                .init(title: "Inbox - Chen Li - Outlook - Google Chrome – Chen", isMinimized: true)
            ]]
        )
        XCTAssertNil(titleOnly[1].isMinimized)
        XCTAssertNil(titleOnly[2].isMinimized)
    }

    /// Chrome owns far more Core Graphics windows than real ones. Accessibility
    /// says nothing about the helper surfaces, and they must stay unknown so the
    /// filter keeps dropping them.
    func testHelperSurfacesAccessibilityNeverReportsStayUnknown() {
        var windows = (0..<6).map { window(id: CGWindowID(29520 + $0), title: "", onScreen: false) }
            + [window(id: 29779, title: "Home | Salesforce", onScreen: false)]
        MinimizedStateResolver.apply(to: &windows, minimizedByWindowID: [29779: true])
        XCTAssertEqual(windows.filter { $0.isMinimized == nil }.count, 6)
        XCTAssertEqual(windows.last?.isMinimized, true)
    }

    /// A window Accessibility reports as not minimized is off screen for some
    /// other reason — usually another Desktop — and that is a real answer, not
    /// an absent one.
    func testAnOffScreenWindowThatIsNotMinimizedIsIdentifiedRatherThanLeftUnknown() {
        var windows = [window(id: 42, title: "Other Desktop", onScreen: false)]
        MinimizedStateResolver.apply(to: &windows, minimizedByWindowID: [42: false])
        XCTAssertEqual(windows[0].isMinimized, false)
    }

    /// The fallback still has to work for applications whose window ID cannot be
    /// read, and each state describes one window, so it is consumed once rather
    /// than matching every window sharing its title.
    func testTheTitleFallbackStillResolvesAndIsConsumedOnce() {
        var windows = [
            window(id: 1, title: "Untitled", onScreen: false),
            window(id: 2, title: "Untitled", onScreen: false)
        ]
        MinimizedStateResolver.apply(
            to: &windows,
            minimizedByWindowID: [:],
            unidentifiedByPID: [91245: [.init(title: "Untitled", isMinimized: true)]]
        )
        XCTAssertEqual(windows[0].isMinimized, true)
        XCTAssertNil(windows[1].isMinimized)
    }

    /// The window ID is exact and the title is a guess, so a conflict is decided
    /// by the ID.
    func testTheWindowIDWinsOverAContradictingTitleMatch() {
        var windows = [window(id: 7, title: "Shared Title", onScreen: false)]
        MinimizedStateResolver.apply(
            to: &windows,
            minimizedByWindowID: [7: false],
            unidentifiedByPID: [91245: [.init(title: "Shared Title", isMinimized: true)]]
        )
        XCTAssertEqual(windows[0].isMinimized, false)
    }

    /// End to end on the switcher's own defaults, which is where this bug lived
    /// long before Dock Peek existed: Include minimized is on out of the box,
    /// yet a minimized Chrome window never appeared in the switcher because the
    /// title comparison upstream of the filter had already discarded it.
    func testTheSwitcherDefaultsShowAMinimizedWindowOnceItIsIdentified() {
        let settings = AppSettings()
        XCTAssertTrue(settings.includeMinimized, "the default this test is about")

        var windows = [
            window(id: 29794, title: "Sign in to your account", onScreen: true),
            window(id: 29779, title: "Home | Salesforce", onScreen: false),
            window(id: 29520, title: "", onScreen: false)
        ]
        MinimizedStateResolver.apply(to: &windows, minimizedByWindowID: [29779: true])

        let listed = WindowFilter.filtered(windows, settings: settings, ownPID: 1)
        XCTAssertEqual(listed.map(\.id), [29794, 29779], "the minimized window belongs in the switcher; the helper surface does not")
    }

    /// And the same list under Dock Peek's filter, which additionally lifts the
    /// Current Space limit.
    func testDockPeekShowsTheSameMinimizedWindow() {
        var windows = [
            window(id: 29794, title: "Sign in to your account", onScreen: true),
            window(id: 29779, title: "Home | Salesforce", onScreen: false),
            window(id: 29520, title: "", onScreen: false)
        ]
        MinimizedStateResolver.apply(to: &windows, minimizedByWindowID: [29779: true])

        let listed = WindowFilter.filtered(windows, settings: AppSettings().dockPeekDiscovery, ownPID: 1)
        XCTAssertEqual(listed.map(\.id), [29794, 29779])
    }
}
