//
//  CardsSheetUITests.swift
//  PitchMarkUITests
//
//  2026-11-21 (#59): in the full cards sheet the filter button sat under
//  the sheet's floating ✕. They must not overlap.
//

import XCTest

@MainActor
final class CardsSheetUITests: XCTestCase {
    func testFilterButtonClearsTheCloseButton() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITestDemo"]
        app.launch()
        // A saved pitch, so there's a last result to open.
        app.buttons["4 Seam"].pickChip()
        app.buttons["Ball Up"].firstMatch.tap()
        sleep(1)
        app.buttons["Ball Up"].firstMatch.tap()
        let ball = app.buttons["Ball"].firstMatch
        XCTAssertTrue(ball.waitForExistence(timeout: 8))
        ball.tap()
        app.buttons["result.save"].tap()
        if app.buttons["Save"].waitForExistence(timeout: 3) { app.buttons["Save"].tap() }
        let cards = app.buttons["Cards"].firstMatch
        XCTAssertTrue(cards.waitForExistence(timeout: 15))
        cards.tap()
        let open = app.buttons["Filter and Edit Cards"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()

        let close = app.buttons["sheet.close"]
        let filter = app.buttons["Filter pitches"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        // It opens editing the last pitch; Done shows the normal row.
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertLessThan(done.frame.maxX, close.frame.minX + 1, "the edit row clears the ✕ too")
        done.tap()
        XCTAssertTrue(filter.waitForExistence(timeout: 8))
        XCTAssertFalse(filter.frame.intersects(close.frame),
                       "filter \(filter.frame) overlaps ✕ \(close.frame)")
        XCTAssertGreaterThanOrEqual(close.frame.minX - filter.frame.maxX, 4, "a gap between them")
        XCTAssertTrue(filter.isHittable)
    }
}
