//
//  FieldingUITests.swift
//  PitchMarkUITests
//
//  Fielding rule 15 (approved 2026-11-03), on the local demo game: a
//  groundout entered as SS then 1B on the result sheet's Fielded by row
//  reads 6-3 and is saved with the pitch - its card shows "6-3".
//
//  The demo has no roster or positions and reads nothing from Firestore, so
//  the Fielding stats screens themselves can't open here; the credit they
//  show from a saved pitch is covered by FieldingTests.
//

import XCTest

@MainActor
final class FieldingUITests: XCTestCase {
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

    func testGroundoutSixThreeIsSavedWithThePitch() {
        // Call a pitch, then tap where it ended up: the result sheet opens.
        tapWhenHittable(app.buttons["4 Seam"])
        tapWhenHittable(app.buttons["Ball Up"])
        sleep(1)
        tapWhenHittable(app.buttons["Ball Up"].firstMatch)
        XCTAssertTrue(app.buttons["Save Result"].waitForExistence(timeout: 8), "result sheet")
        let sheet = app.scrollViews.element(boundBy: app.scrollViews.count - 1)

        // A ground ball to the left side of the infield, then Out.
        let field = app.otherElements["result.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "field")
        var attempts = 0
        while !field.isHittable && attempts < 6 {
            sheet.swipeUp(velocity: .slow)
            attempts += 1
        }
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.40, dy: 0.62)).tap()
        tapWhenHittable(app.buttons["Out"].firstMatch, in: sheet)

        // Fielded by: SS, then 1B.
        tapWhenHittable(app.buttons["fielding.batter.SS"], in: sheet)
        tapWhenHittable(app.buttons["fielding.batter.1B"], in: sheet)
        waitForValue(app.staticTexts["fielding.batter.sequence"], "6-3")

        let save = app.buttons["Save Result"]
        sheet.swipeDown(velocity: .fast)
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled, "Save enabled for a groundout")
        save.tap()
        // The review step lists what will be saved.
        let confirm = app.buttons["Save"]
        if confirm.waitForExistence(timeout: 3) {
            let reviewLine = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "6-3")).firstMatch
            XCTAssertTrue(reviewLine.exists, "review shows 6-3")
            confirm.tap()
        }
        // The saved pitch's card carries the scorebook notation.
        tapWhenHittable(app.buttons["Cards"].firstMatch)
        let card = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "6-3")).firstMatch
        if !card.waitForExistence(timeout: 8) {
            print("SCREEN_TEXTS: " + app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | "))
        }
        XCTAssertTrue(card.exists, "a card showing 6-3")
    }

    /// Rule 22 (approved 2026-11-04): runner on 1st, batter safe at 1st on
    /// a fielder's choice - the runner is put out on their own, and SS
    /// then 2B on their Fielded by row reads 6-4 and is saved.
    func testSixFourFieldersChoiceIsSavedWithThePitch() {
        let countBox = app.buttons["Edit Count, Inning, Runners and Score"]
        XCTAssertTrue(countBox.waitForExistence(timeout: 15))
        countBox.tap()
        let first = app.buttons["runners.bag.1"]
        tapWhenHittable(first)
        tapWhenHittable(app.buttons["Unknown runner"])
        waitForValue(first, "R")
        app.scrollViews.firstMatch.swipeDown(velocity: .fast)

        tapWhenHittable(app.buttons["4 Seam"])
        tapWhenHittable(app.buttons["Ball Up"])
        sleep(1)
        tapWhenHittable(app.buttons["Ball Up"].firstMatch)
        XCTAssertTrue(app.buttons["Save Result"].waitForExistence(timeout: 8), "result sheet")
        let sheet = app.scrollViews.element(boundBy: app.scrollViews.count - 1)

        let field = app.otherElements["result.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "field")
        var attempts = 0
        while !field.isHittable && attempts < 6 {
            sheet.swipeUp(velocity: .slow)
            attempts += 1
        }
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.40, dy: 0.62)).tap()

        // Bases: batter to 1st, credit FC - the runner from 1st goes out.
        tapWhenHittable(app.buttons["1st"].firstMatch, in: sheet)
        tapWhenHittable(app.buttons["FC"].firstMatch, in: sheet)
        XCTAssertTrue(app.buttons["R, out"].waitForExistence(timeout: 5), "runner from 1st marked out")

        tapWhenHittable(app.buttons["fielding.1.SS"], in: sheet)
        tapWhenHittable(app.buttons["fielding.1.2B"], in: sheet)
        waitForValue(app.staticTexts["fielding.1.sequence"], "6-4")
        XCTAssertFalse(app.buttons["fielding.batter.SS"].exists, "the batter is safe, not asked about")

        let save = app.buttons["Save Result"]
        sheet.swipeDown(velocity: .fast)
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled, "Save enabled for a fielder's choice")
        save.tap()
        let confirm = app.buttons["Save"]
        if confirm.waitForExistence(timeout: 3) {
            let reviewLine = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "6-4")).firstMatch
            XCTAssertTrue(reviewLine.exists, "review shows 6-4")
            confirm.tap()
        }
        tapWhenHittable(app.buttons["Cards"].firstMatch)
        let card = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "6-4")).firstMatch
        if !card.waitForExistence(timeout: 8) {
            print("SCREEN_TEXTS: " + app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | "))
        }
        XCTAssertTrue(card.exists, "a card showing 6-4")
    }
}
