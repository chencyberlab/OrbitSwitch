import XCTest
@testable import OrbitSwitchCore

final class DockHoverMachineTests: XCTestCase {
    private let chrome: pid_t = 91245
    private let mail: pid_t = 500

    /// Drives a machine to the point where Chrome's panel is on screen.
    private func showing() -> DockHoverMachine {
        var machine = DockHoverMachine()
        _ = machine.pointerEnteredItem(chrome)
        _ = machine.dwellElapsed()
        XCTAssertTrue(machine.isShowingPanel)
        return machine
    }

    // MARK: - Opening

    func testRestingOnAnIconArmsTheDwellAndOpensWhenItElapses() {
        var machine = DockHoverMachine()
        XCTAssertEqual(
            machine.pointerEnteredItem(chrome),
            [.cancelExit, .cancelDwell, .armDwell(machine.hoverDelay)]
        )
        XCTAssertFalse(machine.isShowingPanel, "nothing opens before the dwell elapses")
        XCTAssertEqual(machine.dwellElapsed(), [.openPanel(chrome)])
        XCTAssertTrue(machine.isShowingPanel)
    }

    func testMovingBetweenIconsWithAPanelUpUsesTheShorterSwitchDelay() {
        var machine = showing()
        XCTAssertEqual(
            machine.pointerEnteredItem(mail),
            [.cancelExit, .cancelDwell, .armDwell(machine.switchDelay)]
        )
        XCTAssertEqual(machine.dwellElapsed(), [.openPanel(mail)])
    }

    func testReturningToTheIconWhosePanelIsOpenNeitherReopensNorCloses() {
        var machine = showing()
        _ = machine.pointerLeftItems()
        XCTAssertEqual(machine.pointerEnteredItem(chrome), [.cancelExit, .cancelDwell])
        XCTAssertEqual(machine.dwellElapsed(), [], "no pending item to open")
        XCTAssertTrue(machine.isShowingPanel)
    }

    // MARK: - The stuck-panel regression

    /// Clicking the Dock icon rather than a preview used to clear the hover
    /// silently. The panel stayed on screen with nothing left able to close it:
    /// moving away armed no exit, because the state it guarded on had just been
    /// cleared. Only hovering a different app or clicking the panel itself got
    /// rid of it.
    func testClickingOutsideClosesThePanelInsteadOfStrandingIt() {
        var machine = showing()
        XCTAssertEqual(machine.pointerPressedOutside(), [.cancelDwell, .cancelExit, .closePanel])
        XCTAssertFalse(machine.isShowingPanel)
    }

    /// And the machine must be usable straight afterward — the icon just clicked
    /// should open again on a fresh hover, not be stuck as "already shown".
    func testAFreshHoverWorksImmediatelyAfterAClick() {
        var machine = showing()
        _ = machine.pointerPressedOutside()
        XCTAssertEqual(
            machine.pointerEnteredItem(chrome),
            [.cancelExit, .cancelDwell, .armDwell(machine.hoverDelay)],
            "the full hover delay, because no panel is up any more"
        )
        XCTAssertEqual(machine.dwellElapsed(), [.openPanel(chrome)])
    }

    func testClickingWithNoPanelUpAsksForNoClose() {
        var machine = DockHoverMachine()
        _ = machine.pointerEnteredItem(chrome)
        XCTAssertEqual(machine.pointerPressedOutside(), [.cancelDwell, .cancelExit])
    }

    // MARK: - Closing

    func testLeavingTheIconsArmsTheExitGraceAndClosesWhenItElapses() {
        var machine = showing()
        XCTAssertEqual(machine.pointerLeftItems(), [.cancelDwell, .armExit(machine.exitGrace)])
        XCTAssertTrue(machine.isShowingPanel, "still open during the grace period")
        XCTAssertEqual(machine.exitElapsed(), [.closePanel])
        XCTAssertFalse(machine.isShowingPanel)
    }

    /// The diagonal move from icon to panel crosses bare Dock. Reaching the
    /// panel within the grace period has to keep it open.
    func testReachingThePanelDuringTheGracePeriodKeepsItOpen() {
        var machine = showing()
        _ = machine.pointerLeftItems()
        XCTAssertEqual(machine.pointerInsidePanelChanged(true), [.cancelExit])
        XCTAssertEqual(machine.exitElapsed(), [], "a late timer must not close a panel under the pointer")
        XCTAssertTrue(machine.isShowingPanel)
    }

    func testLeavingThePanelClosesItAfterTheGracePeriod() {
        var machine = showing()
        _ = machine.pointerInsidePanelChanged(true)
        XCTAssertEqual(machine.pointerInsidePanelChanged(false), [.armExit(machine.exitGrace)])
        XCTAssertEqual(machine.exitElapsed(), [.closePanel])
    }

    func testLeavingTheIconsWithNoPanelUpArmsNothing() {
        var machine = DockHoverMachine()
        XCTAssertEqual(machine.pointerLeftItems(), [.cancelDwell])
    }

    // MARK: - The invariant

    /// The rule the whole type exists to enforce: a panel is on screen exactly
    /// while `shown` is set, so every transition that clears it while one is up
    /// must ask for it to close. A transition that clears `shown` silently is
    /// precisely the bug that stranded the panel.
    func testNoTransitionEverClearsAShownPanelWithoutClosingIt() {
        let transitions: [(String, (inout DockHoverMachine) -> [DockHoverEffect])] = [
            ("pointerEnteredItem(same)", { $0.pointerEnteredItem(self.chrome) }),
            ("pointerEnteredItem(other)", { $0.pointerEnteredItem(self.mail) }),
            ("pointerLeftItems", { $0.pointerLeftItems() }),
            ("dwellElapsed", { $0.dwellElapsed() }),
            ("exitElapsed", { $0.exitElapsed() }),
            ("pointerInsidePanelChanged(true)", { $0.pointerInsidePanelChanged(true) }),
            ("pointerInsidePanelChanged(false)", { $0.pointerInsidePanelChanged(false) }),
            ("pointerPressedOutside", { $0.pointerPressedOutside() })
        ]
        for (name, transition) in transitions {
            var machine = showing()
            let effects = transition(&machine)
            if !machine.isShowingPanel {
                XCTAssertTrue(
                    effects.contains(.closePanel),
                    "\(name) cleared the shown panel without asking for it to close"
                )
            }
        }
    }

    /// `forget` is the one deliberate exception, for a host tearing the panel
    /// down itself — so it is the only transition allowed to clear silently.
    func testForgetClearsSilentlyBecauseItsCallerIsAlreadyClosing() {
        var machine = showing()
        XCTAssertEqual(machine.forget(), [.cancelDwell, .cancelExit])
        XCTAssertFalse(machine.isShowingPanel)
    }
}
