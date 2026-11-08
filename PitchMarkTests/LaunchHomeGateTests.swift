//
//  LaunchHomeGateTests.swift
//  PitchMarkTests
//
//  Regression tests for the 2026-10-31 bug: tapping a game right after a
//  fresh launch loaded the tracker, then flashed back to Home when the slow
//  primary-session read finished.
//
//  Rules:
//  1. Launch lands on Home after 15+ minutes away, or when the one-shot
//     "force on next launch" flag is set; otherwise it doesn't.
//  2. A launch with no recorded background time doesn't force Home.
//  3. Once the coach opens a game, nothing that finishes later in boot
//     may send them to Home - not the launch decision, not "Home was the
//     last screen".
//  4. Before they open a game, the late boot decision still applies.
//

import XCTest
@testable import PitchMark

@MainActor
final class LaunchHomeGateTests: XCTestCase {
    private let now: TimeInterval = 1_000_000

    /// Rule 1.
    func testLaunchAfterLongIdleForcesHome() {
        XCTAssertTrue(LaunchHomeGate.shouldForceHomeOnLaunch(forceFlag: false, lastBackgroundAt: now - 20 * 60, now: now))
        XCTAssertTrue(LaunchHomeGate.shouldForceHomeOnLaunch(forceFlag: false, lastBackgroundAt: now - 15 * 60, now: now),
                      "exactly 15 minutes counts")
    }

    /// Rule 1.
    func testShortIdleOnlyForcesHomeWithTheFlag() {
        XCTAssertFalse(LaunchHomeGate.shouldForceHomeOnLaunch(forceFlag: false, lastBackgroundAt: now - 5 * 60, now: now))
        XCTAssertTrue(LaunchHomeGate.shouldForceHomeOnLaunch(forceFlag: true, lastBackgroundAt: now - 5 * 60, now: now))
    }

    /// Rule 2.
    func testNoRecordedBackgroundDoesNotForceHome() {
        XCTAssertFalse(LaunchHomeGate.shouldForceHomeOnLaunch(forceFlag: false, lastBackgroundAt: 0, now: now))
        XCTAssertFalse(LaunchHomeGate.isIdleTooLong(lastBackgroundAt: 0, now: now))
    }

    /// Rule 3 - the bug. Launch says Home, the coach opens a game before the
    /// session read returns, and the read's late answer must not undo it.
    func testOpeningAGameBlocksTheLateTripHome() {
        var gate = LaunchHomeGate()
        gate.noteGameOpened()
        XCTAssertFalse(gate.allowsLateHome)
        XCTAssertFalse(gate.shouldGoHomeAfterBoot(forceHomeOnLaunch: true, lastView: nil))
        XCTAssertFalse(gate.shouldGoHomeAfterBoot(forceHomeOnLaunch: false, lastView: "settings"))
    }

    /// Rule 4.
    func testLateBootDecisionAppliesBeforeAnyGameIsOpened() {
        let gate = LaunchHomeGate()
        XCTAssertTrue(gate.shouldGoHomeAfterBoot(forceHomeOnLaunch: true, lastView: nil))
        XCTAssertTrue(gate.shouldGoHomeAfterBoot(forceHomeOnLaunch: false, lastView: "settings"))
        XCTAssertFalse(gate.shouldGoHomeAfterBoot(forceHomeOnLaunch: false, lastView: "tracker"))
    }

    // 2026-11-02: the Game tab's onAppear fires on every return to it, and
    // rerunning launch there bounced the coach to Home after 15 minutes.
    func testLaunchRunsOnTheFirstAppearanceOnly() {
        var gate = LaunchHomeGate()
        XCTAssertTrue(gate.claimFirstAppear())
        XCTAssertFalse(gate.claimFirstAppear(), "returning to the Game tab")
        XCTAssertFalse(gate.claimFirstAppear())
    }
}
