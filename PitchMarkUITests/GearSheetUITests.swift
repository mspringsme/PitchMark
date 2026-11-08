//
//  GearSheetUITests.swift
//  PitchMarkUITests
//
//  Rules 48-49 (approved 2026-11-05): the lineup gear sheet has its own
//  selection. Looking at a player there never changes who is batting.
//

import XCTest

@MainActor
final class GearSheetUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo"]
        app.launch()
    }

    private func waitForValue(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 5,
                              file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed,
                       "\(element.identifier) value was \(String(describing: element.value)), expected \(expected)",
                       file: file, line: line)
    }

    /// The demo lineup is #1 only: add #2, keep #1 batting.
    private func lineupOfTwoWithOneBatting() {
        let one = app.descendants(matching: .any)["atBat.1"]
        XCTAssertTrue(one.waitForExistence(timeout: 15), "batter #1 in the at-bat scroll")
        if one.value as? String != "selected" { one.tap() }
        waitForValue(one, "selected")

        let add = app.buttons.matching(identifier: "plus").matching(NSPredicate(format: "label == %@", "Add")).allElementsBoundByIndex
            .first { abs($0.frame.midX - one.frame.midX) < 40 }
        XCTAssertNotNil(add, "the at-bat scroll's Add button")
        add?.tap()
        let jerseyOnly = app.buttons["Jersey Number Only (this game)"]
        XCTAssertTrue(jerseyOnly.waitForExistence(timeout: 5))
        jerseyOnly.tap()
        let field = app.textFields["##"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("2")
        app.buttons["Save"].firstMatch.tap()
        let keep = app.buttons["Keep Current Batter"]
        if keep.waitForExistence(timeout: 3) { keep.tap() }
        XCTAssertTrue(app.descendants(matching: .any)["atBat.2"].waitForExistence(timeout: 5), "#2 added")
        waitForValue(one, "selected")
    }

    /// Rule 49: the sheet opens on the game's batter.
    func testGearSheetOpensOnTheGameBatter() {
        lineupOfTwoWithOneBatting()
        app.buttons["Lineup and Batter Detail"].tap()
        waitForValue(app.buttons["lineup.batter.1"], "selected")
        waitForValue(app.buttons["lineup.batter.2"], "")
    }

    /// Rule 48: tapping another player in the sheet highlights them there,
    /// and the game's batter is still #1 once the sheet is closed.
    func testTappingAPlayerInTheSheetDoesntChangeTheBatter() {
        lineupOfTwoWithOneBatting()
        app.buttons["Lineup and Batter Detail"].tap()
        let two = app.buttons["lineup.batter.2"]
        XCTAssertTrue(two.waitForExistence(timeout: 5))
        two.tap()
        waitForValue(two, "selected")
        waitForValue(app.buttons["lineup.batter.1"], "")

        app.swipeDown(velocity: .fast)
        let one = app.descendants(matching: .any)["atBat.1"]
        XCTAssertTrue(one.waitForExistence(timeout: 5))
        waitForValue(one, "selected")
        waitForValue(app.descendants(matching: .any)["atBat.2"], "")
    }
}
