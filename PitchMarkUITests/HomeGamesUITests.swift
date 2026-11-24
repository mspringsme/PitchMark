//
//  HomeGamesUITests.swift
//  PitchMarkUITests
//
//  Approved 2026-11-24 (UI), on the real Home in demo mode with
//  -UITestHomeSchedule (in memory: one of your teams and an opponent, an
//  upcoming Scrimmage, and a team tourney's game):
//  + offers Game / Tournament / Pitching Practice Session; a Game asks for
//  every field; an upcoming game shows its date and type and opens its card
//  with Start Tracking; a tourney's game lists with the tourney's name;
//  Teams shows My Teams and Opponents, and a team can be moved.
//

import XCTest

@MainActor
final class HomeGamesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestHomeSchedule"]
        app.launch()
        if app.buttons["Skip for Now"].waitForExistence(timeout: 10) { app.buttons["Skip for Now"].tap() }
        if app.buttons["Home"].waitForExistence(timeout: 10) { app.buttons["Home"].tap() }
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp(velocity: .slow) }
    }

    func testPlusOffersThreeKindsAndAGameAsksForEverything() {
        let add = app.buttons["home.games.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let kinds = app.segmentedControls["newGame.kindOfNew"]
        XCTAssertTrue(kinds.waitForExistence(timeout: 5))
        for title in ["Game", "Tournament", "Practice"] {
            XCTAssertTrue(kinds.buttons[title].exists, "+ offers \(title)")
        }
        XCTAssertTrue(app.segmentedControls["newGame.kind"].exists, "Game / Friendly / Scrimmage")
        for id in ["newGame.where", "newGame.field", "newGame.notes"] {
            XCTAssertTrue(app.descendants(matching: .any)[id].exists, "asks for \(id)")
        }
        XCTAssertTrue(app.staticTexts["Arrive by"].exists || app.buttons["Arrive by"].exists, "asks when to arrive")

        kinds.buttons["Tournament"].tap()
        XCTAssertTrue(app.buttons["newGame.createTournament"].waitForExistence(timeout: 5), "Tournament makes one")
    }

    func testUpcomingGamesListWithTheirTypeOrTourney() {
        let add = app.buttons["home.games.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()   // opens the Games section
        app.buttons["Cancel"].firstMatch.tap()

        let scrim = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Scrimmage'")).firstMatch
        XCTAssertTrue(scrim.waitForExistence(timeout: 10), "the Scrimmage, with its type")
        let slam = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Summer Slam'")).firstMatch
        XCTAssertTrue(slam.exists, "the tourney's game, with the tourney's name")
        let classic = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Fall Classic'")).firstMatch
        XCTAssertTrue(classic.exists, "a followed (shared-link) tourney's game is listed too")
        XCTAssertLessThan(scrim.frame.minY, slam.frame.minY, "soonest first")

        reveal(scrim)
        scrim.tap()
        XCTAssertTrue(app.buttons["upcoming.start"].waitForExistence(timeout: 5), "an upcoming game opens its card")
        XCTAssertTrue(app.staticTexts["Away jerseys"].exists, "with its details")
    }

    func testTeamsSplitIntoMyTeamsAndOpponents() {
        let add = app.buttons["home.teams.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        XCTAssertTrue(app.buttons["teams.joinTeam"].waitForExistence(timeout: 5), "Join a Team is with Teams now")

        let mine = app.staticTexts["teams.group.My Teams"]
        let opponents = app.staticTexts["teams.group.Opponents"]
        XCTAssertTrue(mine.waitForExistence(timeout: 10))
        XCTAssertTrue(opponents.exists)
        let hawks = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Hawks'")).firstMatch
        XCTAssertTrue(hawks.exists)
        XCTAssertGreaterThan(hawks.frame.minY, opponents.frame.minY, "Hawks is under Opponents")

        reveal(hawks)
        hawks.press(forDuration: 1.0)
        let move = app.buttons["Move to My Teams"]
        XCTAssertTrue(move.waitForExistence(timeout: 5))
        move.tap()
        XCTAssertTrue(opponents.waitForNonExistence(timeout: 5), "no opponents left")
    }
}
