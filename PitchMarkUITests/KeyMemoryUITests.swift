//
//  KeyMemoryUITests.swift
//  PitchMarkUITests
//
//  Approved 2026-11-22 (item 2, test 5): switching sides asks a pitcher
//  with no choice once, then never again - and each keeps their own choice.
//

import XCTest

@MainActor
final class KeyMemoryUITests: XCTestCase {
    func testSwitchingSidesAsksEachPitcherOnce() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITestDemo", "-UITestTwoSides", "-UITestKeyMemory"]
        app.launch()
        let ours = app.buttons["Our team pitching"].firstMatch
        let theirs = app.buttons["Opponent pitching"].firstMatch
        XCTAssertTrue(theirs.waitForExistence(timeout: 15))

        // The Hawks pitcher's first time in: asked. Keep No Key.
        theirs.tap()
        let keep = app.buttons["Keep No Key"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5), "asked the first time")
        keep.tap()
        XCTAssertTrue(app.buttons["Key: No Key"].waitForExistence(timeout: 5))

        // Ours already had a key when the game opened (the demo starts on
        // it): back on it with no pop-up.
        ours.tap()
        let use = app.buttons["Use Demo Grid Key"]
        XCTAssertTrue(app.buttons["Key: Demo Grid Key"].waitForExistence(timeout: 5), "ours back on their key")
        XCTAssertFalse(use.waitForExistence(timeout: 1.5), "no pop-up for a pitcher with a choice")

        // Twice more each way: never asked, each keeps their own choice.
        for _ in 0..<2 {
            theirs.tap()
            XCTAssertTrue(app.buttons["Key: No Key"].waitForExistence(timeout: 5), "Hawks pitcher kept No Key")
            XCTAssertFalse(keep.waitForExistence(timeout: 1.5), "no pop-up for the Hawks pitcher")
            ours.tap()
            XCTAssertTrue(app.buttons["Key: Demo Grid Key"].waitForExistence(timeout: 5), "ours kept their key")
            XCTAssertFalse(use.waitForExistence(timeout: 1.5), "no pop-up for ours")
        }
    }
}
