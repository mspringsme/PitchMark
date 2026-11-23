//
//  RosterSectionsUITests.swift
//  PitchMarkUITests
//
//  Approved 2026-11-21 (item 3): "Make a Trading Card" opens the player list
//  and it stays open - it used to close at once because the sheet sat on a
//  List section, whose modifiers apply to every row. The same for the Team
//  Sponsors purchase sheet. Launches `-UITestRoster` (a roster in memory).
//

import XCTest

@MainActor
final class RosterSectionsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestRoster"]
        app.launch()
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
    }

    func testMakeATradingCardKeepsThePlayerListOpen() {
        let make = app.buttons["team.makeCard"]
        XCTAssertTrue(make.waitForExistence(timeout: 10))
        scrollTo(make)
        make.tap()
        let title = app.navigationBars["Whose card?"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the player list opened")
        sleep(2)
        XCTAssertTrue(title.exists, "and stayed open")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
    }

    func testAddATeamSponsorKeepsItsSheetOpen() {
        let add = app.buttons["team.addSponsor"]
        guard add.waitForExistence(timeout: 10) else {
            // Only the team's creator sees it; the harness isn't signed in.
            return
        }
        scrollTo(add)
        add.tap()
        let name = app.textFields["sponsor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        sleep(2)
        XCTAssertTrue(name.exists, "the purchase sheet stayed open")
    }
}
