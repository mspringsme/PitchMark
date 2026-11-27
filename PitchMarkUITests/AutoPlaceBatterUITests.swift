//
//  AutoPlaceBatterUITests.swift
//  PitchMarkUITests
//
//  Approved 2026-11-25 (a hit nobody placed), on the demo game:
//  2 runner on 1st; Hit and a tap on the field; Save - the batter is on
//    1st and the runner on 2nd (the user's report: nobody moved)
//  5 after the batter was put on 1st for you, tapping 1st keeps them
//    there; a second tap takes them off as before
//

import XCTest

@MainActor
final class AutoPlaceBatterUITests: XCTestCase {
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

    private func waitForValue(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 5,
                              file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed,
                       "\(element.identifier) value was \(String(describing: element.value)), expected \(expected)",
                       file: file, line: line)
    }

    private var countBox: XCUIElement { app.buttons["Edit Count, Inning, Runners and Score"] }

    private func putRunnerOnFirst() {
        XCTAssertTrue(countBox.waitForExistence(timeout: 15))
        countBox.tap()
        tapWhenHittable(app.buttons["runners.bag.1"])
        tapWhenHittable(app.buttons["Unknown runner"])
        waitForValue(app.buttons["runners.bag.1"], "R")
        app.scrollViews.firstMatch.swipeDown(velocity: .fast)
    }

    private func openSheet() -> XCUIElement {
        app.buttons["4 Seam"].pickChip()
        tapWhenHittable(app.buttons["Ball Up"])
        sleep(1)
        tapWhenHittable(app.buttons["Ball Up"].firstMatch)
        XCTAssertTrue(app.buttons["Save Result"].waitForExistence(timeout: 8), "result sheet")
        return app.scrollViews["result.scroll"]
    }

    private func hitToTheField(_ sheet: XCUIElement) {
        tapWhenHittable(app.buttons["Hit"].firstMatch, in: sheet)
        let field = app.otherElements["result.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "field")
        var attempts = 0
        while !field.isHittable && attempts < 6 {
            sheet.swipeUp(velocity: .slow)
            attempts += 1
        }
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.35)).tap()
    }

    private var batter: XCUIElement { app.otherElements["bases.batter"] }

    /// 2
    func testAHitWithARunnerOnFirstMovesEveryoneUpWithoutTappingABase() {
        putRunnerOnFirst()
        let sheet = openSheet()
        hitToTheField(sheet)
        waitForValue(batter, "1st")

        let save = app.buttons["Save Result"]
        sheet.swipeDown(velocity: .fast)
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled, "Save enabled for the single")
        save.tap()
        let confirm = app.buttons["Save"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }

        XCTAssertTrue(countBox.waitForExistence(timeout: 10))
        countBox.tap()
        waitForValue(app.buttons["runners.bag.2"], "R", timeout: 8)
        XCTAssertNotEqual(app.buttons["runners.bag.1"].value as? String, "empty", "the batter is on 1st")
    }

    /// 5
    func testTappingFirstAfterItWasFilledInKeepsTheBatter() {
        let sheet = openSheet()
        hitToTheField(sheet)
        waitForValue(batter, "1st")
        tapWhenHittable(app.buttons["1st"].firstMatch, in: sheet)
        waitForValue(batter, "1st")
        tapWhenHittable(app.buttons["1st"].firstMatch, in: sheet)
        waitForValue(batter, "at bat")
    }
}
