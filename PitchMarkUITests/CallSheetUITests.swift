//
//  CallSheetUITests.swift
//  PitchMarkUITests
//
//  Approved 2026-11-14: the game screen's Key menu opens the Call Sheet on
//  Batting & Fielding, its Pitching tab says codes there aren't recorded
//  while a game is open, and Done closes it.
//

import XCTest

@MainActor
final class CallSheetUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo"]
        app.launch()
    }

    func testTheKeyMenuOpensTheCallSheetFromAGame() {
        XCTAssertTrue(app.descendants(matching: .any)["atBat.1"].waitForExistence(timeout: 20), "demo game open")

        let keyMenu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Key'")).firstMatch
        XCTAssertTrue(keyMenu.waitForExistence(timeout: 5), "the Key menu")
        keyMenu.tap()

        let open = app.buttons["Open Call Sheet"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()

        let tabs = app.segmentedControls["callSheet.tab"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 5), "the Call Sheet")
        XCTAssertTrue(tabs.buttons["Batting & Fielding"].isSelected, "opens on Batting & Fielding in a game")

        tabs.buttons["Pitching"].tap()
        // By its words as well as its identifier: on a cold first launch
        // the Label's identifier wasn't always visible to the test.
        let note = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'callSheet.gameOpenNote' OR label CONTAINS[c] 'aren\\'t recorded'"))
            .firstMatch
        let noKeys = app.staticTexts["No pitching keys"]
        XCTAssertTrue(note.waitForExistence(timeout: 8) || noKeys.exists,
                      "with a key, the Pitching tab says nothing is recorded")

        app.buttons["callSheet.done"].tap()
        XCTAssertTrue(tabs.waitForNonExistence(timeout: 5), "Done closes it")
    }
}
