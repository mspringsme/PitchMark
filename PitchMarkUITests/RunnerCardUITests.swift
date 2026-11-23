//
//  RunnerCardUITests.swift
//  PitchMarkUITests
//
//  Item 5 (2026-11-21): a steal between pitches shows as its own card.
//

import XCTest

@MainActor
final class RunnerCardUITests: XCTestCase {
    func testAStealShowsAsACard() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITestDemo"]
        app.launch()
        let countBox = app.buttons["Edit Count, Inning, Runners and Score"]
        XCTAssertTrue(countBox.waitForExistence(timeout: 15))
        countBox.tap()
        let first = app.buttons["runners.bag.1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        for _ in 0..<6 where !first.isHittable { app.scrollViews.firstMatch.swipeUp(velocity: .slow) }
        first.tap()
        let unknown = app.buttons["Unknown runner"]
        XCTAssertTrue(unknown.waitForExistence(timeout: 5))
        unknown.tap()
        first.tap()
        let steal = app.buttons["Steal 2nd"]
        XCTAssertTrue(steal.waitForExistence(timeout: 5))
        for _ in 0..<4 where !steal.isHittable { app.scrollViews["runners.actions"].swipeLeft(velocity: .slow) }
        steal.tap()
        // Back to the cards (the count editor took their place).
        let cards = app.buttons["Cards"].firstMatch
        for _ in 0..<6 where !cards.isHittable { app.scrollViews.firstMatch.swipeDown(velocity: .slow) }
        cards.tap()

        let card = app.descendants(matching: .any)["runnerCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the steal has a card")
        XCTAssertTrue(card.label.contains("R steals 2nd"), card.label)
        XCTAssertTrue(card.label.contains("0-0 · 0 outs"), "with the board: \(card.label)")
    }
}
