//
//  TeamScheduleUITests.swift
//  PitchMarkUITests
//
//  Approved 2026-11-22 (team schedule, UI, in memory): a Family sees the
//  team's tourney read-only; a coach puts a tourney on a team.
//

import XCTest

@MainActor
final class TeamScheduleUITests: XCTestCase {
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestTourneys", "-UITestTourneysOpen"] + extra
        app.launch()
        return app
    }

    func testAFamilySeesTheTeamTourneyReadOnly() {
        let app = launch(["-UITestTourneysFamily"])
        let row = app.buttons["tourney.row.Summer Slam"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Team: Reds 16U B"), row.label)
        // Join a Team moved to Home's Teams (2026-11-24).
        row.tap()
        XCTAssertTrue(app.staticTexts["Cooperstown Dreams Park"].waitForExistence(timeout: 5), "the page opens")
        XCTAssertFalse(app.textFields["tourney.name"].exists, "nothing to edit")
    }

    func testACoachPutsATourneyOnATeam() {
        let app = launch(["-UITestTourneysTeams"])
        let row = app.buttons["tourney.row.Summer Slam"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let put = app.buttons["tourney.putOnTeam"]
        XCTAssertTrue(put.waitForExistence(timeout: 5))
        put.tap()
        app.buttons["Reds 16U B"].tap()
        let confirm = app.buttons["Put on Team"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Team: Reds 16U B"].waitForExistence(timeout: 5)
                      || app.buttons["tourney.team"].exists || app.otherElements["tourney.team"].exists,
                      "the page says which team")
        XCTAssertFalse(put.exists, "no second team")
    }
}
