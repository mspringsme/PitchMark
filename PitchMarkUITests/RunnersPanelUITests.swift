//
//  RunnersPanelUITests.swift
//  PitchMarkUITests
//
//  Tap-through tests for the Runners panel (Phase 3), on the local demo
//  game (`-UITestDemo`: no sign-in, nothing written to Firestore). In the
//  demo, Home ("Us") is pitching, so the Away side is batting and gets runs.
//

import XCTest

@MainActor
final class RunnersPanelUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo"]
        app.launch()
        let countBox = app.buttons["Edit Count, Inning, Runners and Score"]
        XCTAssertTrue(countBox.waitForExistence(timeout: 15))
        countBox.tap()
        XCTAssertTrue(bag(1).waitForExistence(timeout: 5))
    }

    // MARK: Helpers

    private func bag(_ base: Int) -> XCUIElement {
        app.buttons["runners.bag.\(base)"]
    }

    private func outDot(_ index: Int) -> XCUIElement {
        app.buttons["count.O.\(index)"]
    }

    /// The panel sits low in a scroll view, partly under the tab bar.
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        var attempts = 0
        while !element.isHittable && attempts < 6 {
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
            attempts += 1
        }
        XCTAssertTrue(element.isHittable, "\(element) never became tappable", file: file, line: line)
    }

    private func tapBag(_ base: Int) {
        reveal(bag(base))
        bag(base).tap()
    }

    /// Empty bag -> picker -> lineup player #1.
    private func placeLineupRunner(on base: Int) {
        tapBag(base)
        let row = app.buttons["#1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "lineup row #1 in the picker")
        row.tap()
        waitForValue(bag(base), "#1")
    }

    /// Empty bag -> picker -> "Unknown runner" (label R).
    private func placeUnknownRunner(on base: Int) {
        tapBag(base)
        let unknown = app.buttons["Unknown runner"]
        XCTAssertTrue(unknown.waitForExistence(timeout: 5))
        unknown.tap()
        waitForValue(bag(base), "R")
    }

    private func action(_ title: String, forRunnerOn base: Int) {
        tapBag(base)
        let chip = app.buttons[title]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "action chip \(title)")
        reveal(app.scrollViews["runners.actions"])
        // The chips scroll sideways; later ones start off-screen.
        var attempts = 0
        while !chip.isHittable && attempts < 4 {
            app.scrollViews["runners.actions"].swipeLeft(velocity: .slow)
            attempts += 1
        }
        XCTAssertTrue(chip.isHittable, "action chip \(title) never became tappable")
        chip.tap()
    }

    private func waitForValue(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 5,
                              file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(element.identifier) value was \(String(describing: element.value)), expected \(expected)",
                       file: file, line: line)
    }

    // MARK: Tests

    /// Rule 1: steal 2nd moves the runner and nothing else.
    func testStealSecond() {
        placeLineupRunner(on: 1)
        action("Steal 2nd", forRunnerOn: 1)
        waitForValue(bag(2), "#1")
        waitForValue(bag(1), "empty")
        waitForValue(outDot(0), "off")
        waitForValue(app.otherElements["score.away"], "0")
    }

    /// Rule 2: a steal into an occupied base is offered but disabled.
    func testStealIntoOccupiedBaseIsDisabled() {
        placeLineupRunner(on: 1)
        placeUnknownRunner(on: 2)
        tapBag(1)
        let steal = app.buttons["Steal 2nd"]
        XCTAssertTrue(steal.waitForExistence(timeout: 5))
        XCTAssertFalse(steal.isEnabled)
    }

    /// Rule 3: steal of home scores for the batting (Away) side.
    func testStealHomeScoresForBattingTeam() {
        placeUnknownRunner(on: 3)
        action("Steal Home", forRunnerOn: 3)
        waitForValue(bag(3), "empty")
        waitForValue(app.otherElements["score.away"], "1")
        waitForValue(app.otherElements["score.home"], "0")
    }

    /// Rules 5 and 7: caught stealing for the third out - outs reset to 0
    /// and every base clears.
    func testCaughtStealingThirdOutClearsTheBases() {
        reveal(outDot(1))
        outDot(1).tap()                       // 2 outs
        waitForValue(outDot(1), "on")
        placeLineupRunner(on: 1)
        placeUnknownRunner(on: 3)
        action("Caught Stealing", forRunnerOn: 1)
        // 3 outs flash, then the reset.
        waitForValue(bag(3), "empty", timeout: 5)
        waitForValue(bag(1), "empty")
        waitForValue(outDot(0), "off")
        waitForValue(outDot(1), "off")
        waitForValue(outDot(2), "off")
    }

    /// Rule 6: picked off - runner gone, one out.
    func testPickedOff() {
        placeUnknownRunner(on: 2)
        action("Picked Off", forRunnerOn: 2)
        waitForValue(bag(2), "empty")
        waitForValue(outDot(0), "on")
        waitForValue(outDot(1), "off")
    }

    /// Rule 9: pinch runner typed in by jersey.
    func testPinchRunner() {
        placeLineupRunner(on: 1)
        action("Pinch Runner", forRunnerOn: 1)
        let field = app.textFields["Jersey #"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("22")
        app.buttons["runnerPicker.add"].tap()
        waitForValue(bag(1), "#22")
        waitForValue(outDot(0), "off")
    }

    /// Rule 17: undo right after a steal puts the runner back.
    func testUndoAfterSteal() {
        placeLineupRunner(on: 1)
        action("Steal 2nd", forRunnerOn: 1)
        waitForValue(bag(2), "#1")

        let undo = app.buttons["Undo Last Pitch"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        app.scrollViews.firstMatch.swipeDown(velocity: .fast)
        XCTAssertTrue(undo.isEnabled, "undo is available after a steal with no pitches")
        undo.tap()
        XCTAssertTrue(app.staticTexts["Undo Last Play?"].waitForExistence(timeout: 5))
        app.buttons["Undo"].tap()

        waitForValue(bag(1), "#1")
        waitForValue(bag(2), "empty")
    }
}
