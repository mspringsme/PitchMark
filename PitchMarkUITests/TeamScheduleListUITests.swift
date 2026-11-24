//
//  TeamScheduleListUITests.swift
//  PitchMarkUITests
//
//  Approved 2026-11-24 (UI, in memory): a Scheduler adds a Scrimmage and
//  it's on the Team Schedule (and Canceled shows struck through); a
//  family's team page shows the schedule with no Add Game; the calendar
//  shows a scheduled game and tapping it opens its card.
//

import XCTest

@MainActor
final class TeamScheduleListUITests: XCTestCase {
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestTourneys", "-UITestTourneysOpen"] + extra
        app.launch()
        return app
    }

    private func openTeamPage(_ app: XCUIApplication) {
        let team = app.buttons["tourney.team.Reds 16U B"]
        for _ in 0..<5 where !team.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(team.waitForExistence(timeout: 10), "the team under Your Teams")
        team.tap()
    }

    func testASchedulerAddsAScrimmageThenCancelsIt() {
        let app = launch(["-UITestTourneysTeams"])
        openTeamPage(app)
        let add = app.buttons["teamSchedule.addGame"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "Schedulers can add")
        add.tap()
        app.segmentedControls["teamGame.kind"].buttons["Scrimmage"].tap()
        let opponent = app.textFields["teamGame.opponent"]
        opponent.tap()
        opponent.typeText("Storm")
        app.buttons["teamGame.save"].tap()

        let row = app.buttons["teamSchedule.row.vs Storm"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "on the schedule")
        XCTAssertTrue(row.label.contains("Scrimmage"), row.label)

        row.tap()
        let canceled = app.switches["teamGame.canceled"]
        XCTAssertTrue(canceled.waitForExistence(timeout: 5))
        for _ in 0..<3 where !canceled.isHittable { app.swipeUp(velocity: .slow) }
        canceled.switches.firstMatch.tap()
        app.buttons["teamGame.save"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let canceledRow = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Canceled'"), object: row)
        XCTAssertEqual(XCTWaiter().wait(for: [canceledRow], timeout: 5), .completed, "marked Canceled: \(row.label)")
    }

    func testAFamilysTeamPageShowsTheScheduleOnly() {
        let app = launch(["-UITestTourneysFamily"])
        openTeamPage(app)
        let row = app.buttons["teamSchedule.row.vs Hawks"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the team tourney's games are on the schedule")
        XCTAssertTrue(row.label.contains("Summer Slam"), row.label)
        XCTAssertFalse(app.buttons["teamSchedule.addGame"].exists, "families don't add games")
        row.tap()
        XCTAssertTrue(app.staticTexts["When"].waitForExistence(timeout: 5), "the game's card")
    }

    func testTheCalendarShowsAScheduledGame() {
        let app = launch(["-UITestTourneysCalendar"])
        let scheduledDay = app.buttons.matching(NSPredicate(format: "value CONTAINS 'scheduled'")).firstMatch
        XCTAssertTrue(scheduledDay.waitForExistence(timeout: 10), "a day marked scheduled")
        scheduledDay.tap()
        let entry = app.buttons["calendar.scheduled.vs Hawks"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.staticTexts["When"].waitForExistence(timeout: 5), "its card opens")
    }
}
