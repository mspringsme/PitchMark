//
//  HalfInningUITests.swift
//  PitchMarkUITests
//
//  Approved 2026-11-21 (item 4): switching the pitching side mid-half-
//  inning saves the batting team's count and outs, gives the new team a
//  fresh board, and coming back asks Keep or Reset. Demo game with an
//  opponent (`-UITestTwoSides`).
//

import XCTest

@MainActor
final class HalfInningUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo", "-UITestTwoSides"]
        app.launch()
    }

    private func dot(_ kind: String, _ index: Int) -> XCUIElement { app.buttons["count.\(kind).\(index)"] }

    private func waitForValue(_ element: XCUIElement, _ value: String, file: StaticString = #filePath, line: UInt = #line) {
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: 5), .completed, "\(element) should be \(value)", file: file, line: line)
    }

    private func setCount() {
        let countBox = app.buttons["Edit Count, Inning, Runners and Score"]
        XCTAssertTrue(countBox.waitForExistence(timeout: 15))
        countBox.tap()
        XCTAssertTrue(dot("O", 0).waitForExistence(timeout: 5))
        dot("B", 0).tap()   // 1 ball
        dot("O", 0).tap()   // 1 out
        waitForValue(dot("B", 0), "on")
        waitForValue(dot("O", 0), "on")
    }

    private func pitchingSide(_ label: String) -> XCUIElement {
        let button = app.buttons[label].firstMatch
        for _ in 0..<3 where !button.isHittable { app.swipeDown() }
        return button
    }

    func testComingBackMidHalfInningAsksKeepOrReset() {
        setCount()

        // The Hawks were batting (we were pitching). Their pitcher now.
        pitchingSide("Opponent pitching").tap()
        waitForValue(dot("B", 0), "off")
        waitForValue(dot("O", 0), "off")
        XCTAssertFalse(app.descendants(matching: .any)["halfInning.card"].exists, "our team never batted - no question")

        // Back to our pitcher: the Hawks bat again, mid-half-inning.
        pitchingSide("Our team pitching").tap()
        let card = app.descendants(matching: .any)["halfInning.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "asks Keep or Reset")
        XCTAssertTrue(app.staticTexts["halfInning.summary"].label.contains("bases empty · 1-0 · 1 out"))
        app.buttons["halfInning.keep"].tap()
        waitForValue(dot("B", 0), "on")
        waitForValue(dot("O", 0), "on")

        // Away and back again, and Reset this time.
        pitchingSide("Opponent pitching").tap()
        pitchingSide("Our team pitching").tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.buttons["halfInning.reset"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        waitForValue(dot("B", 0), "off")
        waitForValue(dot("O", 0), "off")
    }
}
