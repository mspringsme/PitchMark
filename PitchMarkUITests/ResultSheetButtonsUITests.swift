//
//  ResultSheetButtonsUITests.swift
//  PitchMarkUITests
//
//  Rules 53-54 (approved 2026-11-05), on the demo game: Save Result
//  floats over the result sheet, and the catcher's pop-up says Skip.
//

import XCTest

@MainActor
final class ResultSheetButtonsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo"]
        app.launch()
    }

    private func openResultSheet(pitch: String) {
        let chip = app.buttons[pitch]
        XCTAssertTrue(chip.waitForExistence(timeout: 15), pitch)
        chip.tap()
        app.buttons["Ball Up"].tap()
        sleep(1)
        app.buttons["Ball Up"].firstMatch.tap()
    }

    /// Rule 53 (revised 2026-11-05): the Safe/Out + Save Result row sticks
    /// to the top once scrolled to - scrolled down at the field, Out and
    /// Save are both still on screen, tappable, and above the field.
    func testSaveRowSticksAboveTheField() {
        openResultSheet(pitch: "4 Seam")
        let save = app.buttons["result.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        let field = app.otherElements["result.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let sheet = app.scrollViews.firstMatch
        for _ in 0..<3 { sheet.swipeUp(velocity: .slow) }
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.40, dy: 0.62)).tap()

        let out = app.buttons["Out"].firstMatch
        XCTAssertTrue(save.isHittable, "Save Result on screen down at the field")
        XCTAssertTrue(out.isHittable, "Out pinned with it")
        XCTAssertLessThan(save.frame.maxY, field.frame.midY, "the row sits above the field, not on it")

        out.tap()
        XCTAssertTrue(save.isEnabled, "an Out can be saved")
        save.tap()
        let confirm = app.buttons["Save"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: save)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "the sheet closed after saving")
    }

    /// Rule 54: the catcher's pop-up has Skip, not No.
    func testCatcherPopUpSaysSkip() {
        openResultSheet(pitch: "Catcher")
        let skip = app.buttons["Skip"]
        if !skip.waitForExistence(timeout: 8) {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/private/tmp/claude-501/-Users-markspringer-Documents-PitchMark/3d87f09b-ca3a-4a54-8fa7-483216f34c2c/scratchpad/catcher.png"))
        }
        XCTAssertTrue(skip.exists, "Skip button")
        XCTAssertFalse(app.buttons["No"].exists, "no No button")
    }
}

/// Rule 64 (approved 2026-11-05): the review's Save opens where Save Result
/// was tapped - unscrolled and pinned at the top - and saves.
@MainActor
final class ReviewSaveSpotUITests: XCTestCase {
    func testReviewSaveOpensOnSaveResultsSpot() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UITestDemo"]
        app.launch()
        let chip = app.buttons["4 Seam"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        chip.tap()
        app.buttons["Ball Up"].tap()
        sleep(1)
        app.buttons["Ball Up"].firstMatch.tap()
        let save = app.buttons["result.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        app.buttons["Out"].firstMatch.tap()
        sleep(1)

        func check(_ label: String, tolerance: CGFloat) {
            let spot = save.frame
            save.tap()
            let confirm = app.buttons["Save"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 3), label)
            sleep(1)
            XCTAssertEqual(confirm.frame.midX, spot.midX, accuracy: 10, "\(label): same left-right spot")
            XCTAssertEqual(confirm.frame.midY, spot.midY, accuracy: tolerance, "\(label): same height")
        }

        check("unscrolled", tolerance: 10)
        app.buttons["Back"].tap()
        sleep(1)
        let sheet = app.scrollViews.firstMatch
        for _ in 0..<3 { sheet.swipeUp(velocity: .slow) }
        sleep(1)
        // Pinned at the very top, the review sheet starts a little lower.
        check("pinned", tolerance: 15)
        app.buttons["Save"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: save)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "saved and closed")
    }
}
