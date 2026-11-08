//
//  WildPitchUITests.swift
//  PitchMarkUITests
//
//  Phase 3 rule 10 end to end: with a runner on 3rd, a ball that is also a
//  wild pitch opens the runners-only diamond; moving the runner home and
//  saving scores the run for the batting (Away) side and empties 3rd.
//

import XCTest

@MainActor
final class WildPitchUITests: XCTestCase {
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

    private func tapWhenHittable(_ element: XCUIElement, in scroll: XCUIElement? = nil, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), "\(element) missing", file: file, line: line)
        var attempts = 0
        while !element.isHittable && attempts < 6 {
            (scroll ?? app.scrollViews.firstMatch).swipeUp(velocity: .slow)
            attempts += 1
        }
        XCTAssertTrue(element.isHittable, "\(element) never became tappable", file: file, line: line)
        element.tap()
    }

    func testWildPitchScoresRunnerFromThird() {
        // A runner on 3rd, from the Runners panel.
        let countBox = app.buttons["Edit Count, Inning, Runners and Score"]
        XCTAssertTrue(countBox.waitForExistence(timeout: 15))
        countBox.tap()
        let third = app.buttons["runners.bag.3"]
        tapWhenHittable(third)
        tapWhenHittable(app.buttons["Unknown runner"])
        waitForValue(third, "R")
        app.scrollViews.firstMatch.swipeDown(velocity: .fast)

        // Call a pitch, then tap where it ended up: the result sheet opens.
        tapWhenHittable(app.buttons["4 Seam"])
        tapWhenHittable(app.buttons["Ball Up"])
        sleep(1)
        tapWhenHittable(app.buttons["Ball Up"].firstMatch)
        XCTAssertTrue(app.buttons["Save Result"].waitForExistence(timeout: 8), "result sheet")

        // Ball + Wild Pitch: the runners-only diamond.
        let sheet = app.scrollViews.element(boundBy: app.scrollViews.count - 1)
        tapWhenHittable(app.buttons["Ball"].firstMatch, in: sheet)
        tapWhenHittable(app.buttons["Wild Pitch"].firstMatch, in: sheet)
        let token = app.buttons["Runner R"]
        tapWhenHittable(token, in: sheet)
        tapWhenHittable(app.buttons["Score"].firstMatch, in: sheet)

        let save = app.buttons["Save Result"]
        sheet.swipeDown(velocity: .fast)
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled, "Save enabled with Ball + a legal WP move")
        save.tap()

        // A review sheet may confirm the save.
        let confirm = app.buttons["Save"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }

        waitForValue(app.otherElements["score.away"], "1", timeout: 8)
        waitForValue(app.otherElements["score.home"], "0")
        if !third.isHittable { app.scrollViews.firstMatch.swipeUp(velocity: .slow) }
        waitForValue(third, "empty")
    }
}
