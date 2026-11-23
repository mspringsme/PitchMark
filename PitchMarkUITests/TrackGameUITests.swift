//
//  TrackGameUITests.swift
//  PitchMarkUITests
//
//  Approved 2026-11-20 (T5), on the demo game: Track Game uses the Call
//  Pitches screen - pick a chip, tap where the pitch went, and the result
//  sheet opens straight away with no code panel; saving records the pitch
//  as a Track Game pitch. Unknown is a chip there.
//

import XCTest

@MainActor
final class TrackGameUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo"]
        app.launch()
    }

    private func switchToTrackGame() {
        let keyMenu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Key'")).firstMatch
        XCTAssertTrue(keyMenu.waitForExistence(timeout: 15), "the Key menu")
        keyMenu.tap()
        let track = app.buttons["Track Game"]
        XCTAssertTrue(track.waitForExistence(timeout: 5), "Track Game in the Key menu")
        track.tap()
    }

    func testOneTapOpensTheResultSheetWithNoCode() {
        switchToTrackGame()

        XCTAssertTrue(app.buttons["Unknown"].waitForExistence(timeout: 5), "Track Game offers Unknown")
        XCTAssertFalse(app.buttons["Catcher"].exists, "no Catcher chip in Track Game")

        let chip = app.buttons["4 Seam"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.pickChip()
        app.buttons["Ball Up"].firstMatch.tap()
        // Track Game asks for an estimate first (2026-11-21).
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 8), "the estimate panel")
        skip.tap()

        let save = app.buttons["result.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 8), "the result sheet opened after one tap")
        XCTAssertFalse(app.descendants(matching: .any)["tracker.codePanel"].exists, "no code panel in Track Game")

        let ball = app.buttons["Ball"].firstMatch
        XCTAssertTrue(ball.waitForExistence(timeout: 5))
        ball.tap()
        XCTAssertTrue(save.isEnabled)
        save.tap()
        let confirm = app.buttons["Save"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }

        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "the result sheet closed")
        // The batter's pitch cards are in the lineup gear sheet.
        let gear = app.buttons["Lineup and Batter Detail"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()
        let pitchCards = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Pitch cards'")).firstMatch
        XCTAssertTrue(pitchCards.waitForExistence(timeout: 5), "the batter's Pitch cards row")
        pitchCards.tap()
        // The gear sheet's card: a tracked pitch has where it went and no
        // called spot - a called pitch would also show "(Coach): ...".
        let result = app.staticTexts["(Result): Ball Up"]
        XCTAssertTrue(result.waitForExistence(timeout: 8), "the pitch was saved where it went")
        let called = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '(Coach)'")).firstMatch
        XCTAssertFalse(called.exists, "recorded as a Track Game pitch, not a called one")
    }

    func testCallPitchesStillShowsTheCodePanel() {
        let chip = app.buttons["4 Seam"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        chip.pickChip()
        app.buttons["Ball Up"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["tracker.codePanel"].waitForExistence(timeout: 8),
                      "Call Pitches still shows the code to signal")
    }
}
