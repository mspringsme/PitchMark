//
//  ClipBarUITests.swift
//  PitchMarkUITests
//
//  Approved 2026-11-24 (clip brief 2c), test 9: the demo game shows Clip;
//  adding Grandma to Quick Send puts her chip on the bar, picked; a tap
//  unpicks it. The demo starts from an empty list every launch.
//

import XCTest

@MainActor
final class ClipBarUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo"]
        app.launch()
    }

    func testAddSomeoneAndPickThem() {
        XCTAssertTrue(app.buttons["clipBar.clip"].waitForExistence(timeout: 15))
        app.buttons["clipBar.addRecipients"].tap()

        let name = app.textFields["quickSend.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Grandma")
        let address = app.textFields["quickSend.address"]
        address.tap()
        address.typeText("5551234567")
        app.buttons["quickSend.save"].tap()
        app.buttons["Done"].tap()

        let chip = app.buttons["clipBar.chip.Grandma"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertTrue(chip.isSelected, "a new person is picked")
        chip.tap()
        let unpicked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == false"), object: chip)
        XCTAssertEqual(XCTWaiter().wait(for: [unpicked], timeout: 5), .completed)
    }
}
