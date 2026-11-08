//
//  ResultFieldUITests.swift
//  PitchMarkUITests
//
//  One field on the pitch result sheet (rules 24-27, approved 2026-11-04):
//  the hit-location field is never swapped out, the batter and runners are
//  drawn on it, and with Out selected the bases can't make the batter safe.
//

import XCTest

@MainActor
final class ResultFieldUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo"]
        app.launch()
    }

    private func tapWhenHittable(_ element: XCUIElement, in scroll: XCUIElement? = nil,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), "\(element) missing", file: file, line: line)
        var attempts = 0
        while !element.isHittable && attempts < 6 {
            (scroll ?? app.scrollViews.firstMatch).swipeUp(velocity: .slow)
            attempts += 1
        }
        XCTAssertTrue(element.isHittable, "\(element) never became tappable", file: file, line: line)
        element.tap()
    }

    private func isSelected(_ element: XCUIElement) -> Bool {
        (element.value as? String) == "selected"
    }

    private var field: XCUIElement { app.otherElements["result.field"] }
    private var out: XCUIElement { app.buttons["Out"].firstMatch }

    /// Optionally a runner on 1st, then a called pitch's result sheet.
    private func openSheet(runnerOnFirst: Bool) -> XCUIElement {
        if runnerOnFirst {
            let countBox = app.buttons["Edit Count, Inning, Runners and Score"]
            XCTAssertTrue(countBox.waitForExistence(timeout: 15))
            countBox.tap()
            tapWhenHittable(app.buttons["runners.bag.1"])
            tapWhenHittable(app.buttons["Unknown runner"])
            sleep(1)
            app.scrollViews.firstMatch.swipeDown(velocity: .fast)
        }
        tapWhenHittable(app.buttons["4 Seam"])
        tapWhenHittable(app.buttons["Ball Up"])
        sleep(1)
        tapWhenHittable(app.buttons["Ball Up"].firstMatch)
        XCTAssertTrue(app.buttons["Save Result"].waitForExistence(timeout: 8), "result sheet")
        return app.scrollViews.element(boundBy: app.scrollViews.count - 1)
    }

    private func tapField(_ sheet: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), "field")
        var attempts = 0
        while !field.isHittable && attempts < 6 {
            sheet.swipeUp(velocity: .slow)
            attempts += 1
        }
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.40, dy: 0.62)).tap()
    }

    /// Rule 24
    func testOutStaysSelectedThroughGrounderAndAFieldTap() {
        let sheet = openSheet(runnerOnFirst: false)
        tapWhenHittable(out, in: sheet)
        tapWhenHittable(app.buttons["Grounder"].firstMatch, in: sheet)
        XCTAssertTrue(isSelected(out), "Out after Grounder")
        XCTAssertTrue(isSelected(app.buttons["Grounder"].firstMatch))
        tapField(sheet)
        XCTAssertTrue(app.otherElements["result.hitMarker"].waitForExistence(timeout: 3), "location marked")
        XCTAssertTrue(isSelected(out), "Out after a tap on the field")
    }

    /// Rule 25
    func testOutWithARunnerKeepsTheField() {
        let sheet = openSheet(runnerOnFirst: true)
        tapWhenHittable(out, in: sheet)
        XCTAssertTrue(field.waitForExistence(timeout: 3), "the hit-location field is still there")
        XCTAssertTrue(app.buttons["Runner R"].waitForExistence(timeout: 3), "the runner is drawn on it")
        tapField(sheet)
        XCTAssertTrue(app.otherElements["result.hitMarker"].waitForExistence(timeout: 3), "a location can still be tapped")
        XCTAssertTrue(isSelected(out))
    }

    /// Rule 26
    func testBasesDontMakeAnOutBatterSafe() {
        let sheet = openSheet(runnerOnFirst: false)
        tapWhenHittable(out, in: sheet)
        tapField(sheet)
        XCTAssertTrue(app.otherElements["result.hitMarker"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["1st"].exists, "no live bag to place the batter on")
        XCTAssertFalse(app.buttons["Score"].exists)
        XCTAssertTrue(isSelected(out))
    }

    /// Rule 27
    func testHitMarkerStaysWhenTheBatterIsPlaced() {
        let sheet = openSheet(runnerOnFirst: false)
        tapField(sheet)
        let marker = app.otherElements["result.hitMarker"]
        XCTAssertTrue(marker.waitForExistence(timeout: 3), "location marked")
        tapWhenHittable(app.buttons["1st"].firstMatch, in: sheet)
        XCTAssertTrue(isSelected(app.buttons["Safe"].firstMatch), "batter safe at 1st")
        XCTAssertTrue(marker.exists, "the marker is still on the field")
        XCTAssertTrue(field.exists)
    }

    private var runnerOut: XCUIElement { app.buttons["bases.runnerOut"] }

    /// Rule 28
    func testTapOnARunnerBeforeAResultIsTheHitLocation() {
        let sheet = openSheet(runnerOnFirst: true)
        let runner = app.buttons["Runner R"]
        tapWhenHittable(runner, in: sheet)
        XCTAssertTrue(app.otherElements["result.hitMarker"].waitForExistence(timeout: 3), "the tap marked the location")
        XCTAssertFalse(runnerOut.exists, "the runner wasn't picked up")
    }

    /// Rule 29
    func testRefreshPutsAPickedUpRunnerDown() {
        let sheet = openSheet(runnerOnFirst: true)
        tapWhenHittable(out, in: sheet)
        tapWhenHittable(app.buttons["Runner R"], in: sheet)
        XCTAssertTrue(runnerOut.waitForExistence(timeout: 3), "runner picked up")
        tapWhenHittable(app.buttons["Refresh"].firstMatch, in: sheet)
        XCTAssertFalse(runnerOut.waitForExistence(timeout: 2), "Refresh put them down")
    }

    /// Rule 30
    func testNewHitLocationPutsAPickedUpRunnerDown() {
        let sheet = openSheet(runnerOnFirst: true)
        tapWhenHittable(out, in: sheet)
        tapWhenHittable(app.buttons["Runner R"], in: sheet)
        XCTAssertTrue(runnerOut.waitForExistence(timeout: 3), "runner picked up")
        tapField(sheet)
        XCTAssertTrue(app.otherElements["result.hitMarker"].waitForExistence(timeout: 3))
        XCTAssertFalse(runnerOut.waitForExistence(timeout: 2), "a new location put them down")
    }

    private var batter: XCUIElement { app.otherElements["bases.batter"] }

    private func waitForValue(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 5,
                              file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed,
                       "\(element.identifier) value was \(String(describing: element.value)), expected \(expected)",
                       file: file, line: line)
    }

    /// Rule 31
    func testBatterShowsAtBatBesideTheRunners() {
        _ = openSheet(runnerOnFirst: true)
        XCTAssertTrue(batter.waitForExistence(timeout: 5), "batter on the field")
        waitForValue(batter, "at bat")
        XCTAssertTrue(app.buttons["Runner R"].exists, "the runner is a separate token")
        XCTAssertNotEqual(batter.frame.midX, app.buttons["Runner R"].frame.midX)
    }

    /// Rule 32
    func testBatterMovesToTheBaseTheyReached() {
        let sheet = openSheet(runnerOnFirst: true)
        tapField(sheet)
        tapWhenHittable(app.buttons["1st"].firstMatch, in: sheet)
        waitForValue(batter, "1st")
    }

    /// Rule 33
    func testOutBatterReadsOutAndTheRunnerStays() {
        let sheet = openSheet(runnerOnFirst: true)
        tapWhenHittable(out, in: sheet)
        waitForValue(batter, "out")
        XCTAssertTrue(app.buttons["Runner R"].exists, "runner still shown")
    }

    /// Rule 34
    func testPromptNamesTheBatter() {
        let sheet = openSheet(runnerOnFirst: true)
        tapField(sheet)
        let prompt = app.staticTexts["bases.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        XCTAssertTrue(prompt.label.contains("#"), "prompt was \(prompt.label)")
        tapWhenHittable(out, in: sheet)
        let outPrompt = app.staticTexts["bases.prompt"]
        XCTAssertTrue(outPrompt.waitForExistence(timeout: 5))
        XCTAssertTrue(outPrompt.label.hasPrefix("#"), "prompt was \(outPrompt.label)")
        XCTAssertTrue(outPrompt.label.contains("out"))
    }
}
