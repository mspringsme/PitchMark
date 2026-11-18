//
//  TourneyUITests.swift
//  PitchMarkUITests
//
//  Round Robin / Tourney Info (approved 2026-11-16, 2026-11-17): the Games
//  row's button opens the list; games (teams picked like a new game,
//  arrive-at, order, Start Game hand-off), uniforms +, General Info items,
//  and Scouting. Runs on its own (`-UITestTourneys`), in memory; the
//  harness stands in for Home's new-game card and shows what Start Game
//  would fill in (`harness.startedGame`).
//

import XCTest

@MainActor
final class TourneyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ extra: [String] = []) {
        app.launchArguments = ["-UITestTourneys"] + extra
        app.launch()
    }

    /// Scrolls the page up until `element` exists and is on screen.
    private func scrollTo(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<12 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "couldn't reach \(element)", file: file, line: line)
    }

    func testOpenTourneyInfoMakeOneAndSeeItListed() {
        launch()
        let open = app.buttons["home.tourneyInfo"]
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        open.tap()

        XCTAssertTrue(app.buttons["tourney.row.Summer Slam"].waitForExistence(timeout: 5), "the sample is listed")
        app.buttons["tourney.new"].tap()

        let name = app.textFields["tourney.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Opening Day Classic")

        app.navigationBars.buttons.element(boundBy: 0).tap()   // Back
        XCTAssertTrue(app.buttons["tourney.row.Opening Day Classic"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tourney.row.Summer Slam"].exists)
    }

    func testAddGamesWithTeamsAndArriveTimeThenStartOne() {
        launch(["-UITestTourneysOpen", "-UITestTourneysDetail"])

        // A bracket game, added first, still lists after the scheduled ones.
        let addBracket = app.buttons["tourney.addBracketGame"]
        XCTAssertTrue(addBracket.waitForExistence(timeout: 8))
        addBracket.tap()
        let opponent = app.textFields["tourneyGame.opponent"]
        XCTAssertTrue(opponent.waitForExistence(timeout: 5))
        opponent.tap()
        opponent.typeText("Seed 2")
        app.buttons["tourneyGame.save"].tap()
        XCTAssertTrue(app.buttons["tourney.game.Seed 2"].waitForExistence(timeout: 5))

        // A scheduled game: teams picked the way a new game picks them.
        app.buttons["tourney.addScheduledGame"].tap()
        XCTAssertTrue(app.buttons["Select"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Select"].firstMatch.tap()          // Our team
        app.buttons["Storm"].tap()
        app.buttons["Select"].firstMatch.tap()          // Opponent
        app.buttons["Lightning"].tap()
        XCTAssertEqual(app.textFields["tourneyGame.opponent"].value as? String, "Lightning",
                       "picking the opponent team fills in its name")

        let arrive = app.buttons["optionalDate.Arrive at"]
        XCTAssertTrue(arrive.exists)
        arrive.tap()
        XCTAssertFalse(arrive.exists, "arrive-at is set")
        app.buttons["tourneyGame.save"].tap()

        // Back on the page: the new game shows its arrive time and sits
        // with the scheduled games, above the bracket game.
        let added = app.descendants(matching: .any)["tourney.game.Lightning"].firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        XCTAssertTrue(added.label.contains("Arrive"), added.label)
        let seed2 = app.descendants(matching: .any)["tourney.game.Seed 2"].firstMatch
        XCTAssertLessThan(added.frame.minY, seed2.frame.minY, "scheduled before bracket")

        // Its + hands both teams, the opponent and the time to Home's card.
        app.buttons["tourney.startGame.Lightning"].tap()
        let started = app.staticTexts["harness.startedGame"]
        XCTAssertTrue(started.waitForExistence(timeout: 5))
        XCTAssertEqual(started.label, "New game: Lightning · ours t-Storm · opp t-Lightning")
    }

    func testSaveWaitsWhileANewTeamIsBeingAdded() {
        launch(["-UITestTourneysOpen", "-UITestTourneysDetail"])
        let add = app.buttons["tourney.addScheduledGame"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()
        let save = app.buttons["tourneyGame.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        app.buttons["Select"].firstMatch.tap()
        app.buttons["New Team…"].tap()
        XCTAssertTrue(app.textFields["Team name"].waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "Save waits for the New Team form, as on Home")
        // The New Team form's Cancel - the last one; the first is the sheet's.
        let cancels = app.buttons.matching(NSPredicate(format: "label == 'Cancel'"))
        cancels.element(boundBy: cancels.count - 1).tap()
        XCTAssertTrue(save.isEnabled)
    }

    func testStartGameFromASavedGameHandsOnItsTeams() {
        launch(["-UITestTourneysOpen", "-UITestTourneysDetail"])
        let start = app.buttons["tourney.startGame.Hawks"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        start.tap()
        let started = app.staticTexts["harness.startedGame"]
        XCTAssertTrue(started.waitForExistence(timeout: 5))
        XCTAssertEqual(started.label, "New game: Hawks · ours t-Lightning · opp t-Hawks")
    }

    func testASharedTourneysGameOpensItsCardWithTrackBelow() {
        launch(["-UITestTourneysOpen", "-UITestTourneysRead"])
        let row = app.buttons["tourneyRead.game.Hawks"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["tourney.startGame.Hawks"].exists, "no Track on a shared tourney's rows")
        row.tap()
        XCTAssertTrue(app.staticTexts["Field 7"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Apple Maps"].firstMatch.exists, "directions on the card")
        // Track sits last, under the directions - scroll the card to it.
        let track = app.buttons["tourneyGameCard.track"]
        scrollTo(track)
        track.tap()
        let started = app.staticTexts["harness.startedGame"]
        XCTAssertTrue(started.waitForExistence(timeout: 5))
        XCTAssertEqual(started.label, "New game: Hawks")
    }

    func testUniformPlusAndGeneralInfoItems() {
        launch(["-UITestTourneysOpen", "-UITestTourneysDetail"])
        XCTAssertTrue(app.buttons["tourney.addScheduledGame"].waitForExistence(timeout: 8))

        // The sample has two days; + adds a third.
        let plus = app.buttons["tourney.addUniformDay"]
        scrollTo(plus)
        XCTAssertFalse(app.textFields["tourney.uniform.2"].exists)
        plus.tap()
        XCTAssertTrue(app.textFields["tourney.uniform.2"].waitForExistence(timeout: 5))

        // General Info starts with only the cleats toggle and a blank line.
        let item = app.textFields["tourney.newItem"]
        scrollTo(item)
        XCTAssertTrue(app.switches["tourney.metalCleats"].exists)
        item.tap()
        item.typeText("Folding chairs\n")
        XCTAssertTrue(app.staticTexts["Folding chairs"].waitForExistence(timeout: 5))
        XCTAssertEqual(item.value as? String, "Add an item", "the line is blank again")
    }

    func testScoutingAddsAnEntry() {
        launch(["-UITestTourneysOpen"])
        XCTAssertTrue(app.buttons["tourney.row.Summer Slam"].waitForExistence(timeout: 8))
        app.buttons["Scouting"].tap()
        XCTAssertTrue(app.buttons["prospect.row.Fall Classic"].waitForExistence(timeout: 5))
        app.buttons["tourney.new"].tap()
        let name = app.textFields["prospect.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Spring Fling")
        app.textFields["prospect.distance"].tap()
        app.textFields["prospect.distance"].typeText("2 hr")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let row = app.buttons["prospect.row.Spring Fling"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("2 hr"), row.label)
        XCTAssertFalse(app.buttons["tourney.row.Summer Slam"].exists, "Our Tourneys isn't shown on Scouting")
    }
}
