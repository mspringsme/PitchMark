//
//  NoKeyEstimateUITests.swift
//  PitchMarkUITests
//
//  Approved 2026-11-21, on the demo game:
//  item 7/8 - the Key sheet offers No Key; with it every pitch type is a
//  chip and a zone tap shows no code.
//  item 9 - Catcher's estimate is a short panel under the main zone and
//  chips (no separate screen); the main chips and zone pick the estimate;
//  Done goes on to the result.
//

import XCTest

@MainActor
final class NoKeyEstimateUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo"]
        app.launch()
    }

    func testNoKeyShowsEveryPitchTypeAndNoCode() {
        let keyMenu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Key'")).firstMatch
        XCTAssertTrue(keyMenu.waitForExistence(timeout: 15))
        keyMenu.tap()
        let keyItem = app.buttons["Key"]
        XCTAssertTrue(keyItem.waitForExistence(timeout: 5))
        keyItem.tap()
        let noKey = app.buttons["No Key"]
        XCTAssertTrue(noKey.waitForExistence(timeout: 5), "No Key in the key sheet")
        noKey.tap()
        if app.buttons["Close"].waitForExistence(timeout: 2) { app.buttons["Close"].tap() }

        for pitch in ["Screw", "Pipe", "Drop"] {
            XCTAssertTrue(app.buttons[pitch].waitForExistence(timeout: 5), "\(pitch) is a chip with No Key")
        }
        app.buttons["Screw"].pickChip()
        let spot = app.buttons["Strike Up"].firstMatch
        XCTAssertTrue(spot.isHittable, "no spot greyed out")
        spot.tap()
        // 2026-11-21 (#58): the called pitch shows with "Tap Location" and no
        // code - hiding the card left only a blurred, empty sheet.
        let panel = app.descendants(matching: .any)["tracker.codePanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 8), "the called pitch card")
        XCTAssertTrue(panel.staticTexts["Tap Location"].exists, "it says what to do next")
        XCTAssertTrue(panel.staticTexts["Screw"].exists, "the called pitch")
        XCTAssertFalse(panel.staticTexts["Code"].exists, "no code with No Key")
        XCTAssertTrue(panel.staticTexts["No key – tap where the pitch went"].exists, "not an error message")

        // The next tap is where it went: the result opens.
        app.buttons["Ball Up"].firstMatch.tap()
        XCTAssertTrue(app.buttons["result.save"].waitForExistence(timeout: 8), "on to the result")
    }

    func testCatcherEstimateIsAPanelUnderTheZone() {
        let catcher = app.buttons["Catcher"]
        XCTAssertTrue(catcher.waitForExistence(timeout: 15))
        catcher.tap()
        app.buttons["Ball Up"].firstMatch.tap()

        let panel = app.descendants(matching: .any)["estimate.panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 8), "the estimate panel")
        let zoneSpot = app.buttons["Strike Up"].firstMatch
        XCTAssertTrue(zoneSpot.isHittable, "the main zone stays usable above the panel")
        XCTAssertLessThan(zoneSpot.frame.maxY, panel.frame.minY, "the panel sits below the zone")

        app.buttons["4 Seam"].tap()
        zoneSpot.tap()
        let summary = app.staticTexts["estimate.summary"]
        let picked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Estimate: 4 Seam · Strike Up'"), object: summary)
        XCTAssertEqual(XCTWaiter().wait(for: [picked], timeout: 5), .completed, "the main chips and zone pick the estimate")

        for title in ["Reset", "Skip", "Done"] {
            XCTAssertTrue(app.buttons[title].exists, title)
        }
        let reset = app.buttons["Reset"].frame, skip = app.buttons["Skip"].frame, done = app.buttons["Done"].frame
        XCTAssertEqual(reset.width, skip.width, accuracy: 2, "evenly spaced")
        XCTAssertEqual(skip.width, done.width, accuracy: 2, "evenly spaced")
        XCTAssertGreaterThanOrEqual(reset.height, 44)

        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["result.save"].waitForExistence(timeout: 8), "on to the result")
    }

    /// 2026-11-21: the panel's Reset starts the pitch over - the panel
    /// closes and the zone takes a new pitch.
    func testEstimateResetClosesThePanel() {
        let catcher = app.buttons["Catcher"]
        XCTAssertTrue(catcher.waitForExistence(timeout: 15))
        catcher.pickChip()
        app.buttons["Ball Up"].firstMatch.tap()
        let panel = app.descendants(matching: .any)["estimate.panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        panel.buttons["Reset"].tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "the panel closed")
        XCTAssertFalse(app.buttons["result.save"].exists, "no result in progress")

        // A new pitch starts normally.
        app.buttons["Ball Up"].firstMatch.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 8), "the next pitch asks again")
    }
}
