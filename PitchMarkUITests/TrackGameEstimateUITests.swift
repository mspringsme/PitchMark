//
//  TrackGameEstimateUITests.swift
//  PitchMarkUITests
//
//  Approved 2026-11-21, on the demo game:
//  (7) Track Game: zone tap -> estimate panel under the zone -> a pitch and
//      a spot -> Done -> save a 1B; its card shows and the chips clear.
//  (8) Catcher picked, then Track Game: the result still records (the
//      reported bug - a hidden Catcher call hid the zone).
//  (9) A steal, then a pitch: the pitch card sits above the steal.
//  (11) Skip has Reset's tint.
//

import XCTest

@MainActor
final class TrackGameEstimateUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestDemo"]
        app.launch()
        XCTAssertTrue(keyMenu.waitForExistence(timeout: 15))
    }

    private var keyMenu: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Key'")).firstMatch
    }

    private func reveal(_ element: XCUIElement, in scroll: XCUIElement? = nil, up: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), "\(element) missing", file: file, line: line)
        var attempts = 0
        while !element.isHittable && attempts < 6 {
            let s = scroll ?? app.scrollViews.firstMatch
            up ? s.swipeUp(velocity: .slow) : s.swipeDown(velocity: .slow)
            attempts += 1
        }
        XCTAssertTrue(element.isHittable, "\(element) never became tappable", file: file, line: line)
    }

    private func switchToTrackGame() {
        keyMenu.tap()
        let track = app.buttons["Track Game"]
        XCTAssertTrue(track.waitForExistence(timeout: 5))
        track.tap()
    }

    /// Field tap, batter safe at 1st, Save Result, Save.
    private func recordSingle() {
        let field = app.otherElements["result.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "the result sheet's field")
        let sheet = app.scrollViews.element(boundBy: app.scrollViews.count - 1)
        reveal(field, in: sheet)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.40)).tap()
        let first = app.buttons["1st"].firstMatch
        reveal(first, in: sheet)
        first.tap()
        sheet.swipeDown(velocity: .fast)
        let save = app.buttons["Save Result"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        let confirm = app.buttons["Save"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "the result sheet closed")
        if app.buttons["OK"].waitForExistence(timeout: 2) { app.buttons["OK"].tap() }
    }

    private func cardTexts() -> [String] {
        let cards = app.buttons["Cards"].firstMatch
        reveal(cards)
        cards.tap()
        sleep(1)
        return app.staticTexts.allElementsBoundByIndex.map(\.label)
    }

    func testTrackGameAsksForAnEstimateThenRecordsTheHit() {
        switchToTrackGame()
        app.buttons["Strike Middle"].firstMatch.tap()

        let panel = app.descendants(matching: .any)["estimate.panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 8), "the estimate panel, not the result yet")
        let spot = app.buttons["Strike Up"].firstMatch
        XCTAssertTrue(spot.isHittable, "the zone stays usable above the panel")
        XCTAssertLessThan(spot.frame.maxY, panel.frame.minY, "the panel sits below the zone")

        app.buttons["Change"].firstMatch.tap()
        spot.tap()
        let summary = app.staticTexts["estimate.summary"]
        let picked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Estimate: Change · Strike Up'"),
                                               object: summary)
        XCTAssertEqual(XCTWaiter().wait(for: [picked], timeout: 5), .completed)
        app.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts["Pitch result: Strike Middle"].waitForExistence(timeout: 8),
                      "the result is where it went - estimate taps didn't move it")
        recordSingle()

        XCTAssertTrue(cardTexts().contains("1B"), "the hit was saved")
        XCTAssertFalse(app.buttons["Change"].firstMatch.isSelected, "Track Game starts the next pitch with no chip")
    }

    func testACatcherPickCarriedIntoTrackGameStillRecords() {
        app.buttons["Catcher"].tap()
        switchToTrackGame()
        app.buttons["Strike Middle"].firstMatch.tap()
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 8), "the short estimate panel")
        XCTAssertTrue(app.buttons["Strike Up"].firstMatch.isHittable, "the zone is not hidden")
        skip.tap()
        XCTAssertTrue(app.staticTexts["Pitch result: Strike Middle"].waitForExistence(timeout: 8))
        recordSingle()
        XCTAssertTrue(cardTexts().contains("1B"), "recorded")
    }

    func testAPitchAfterAStealSitsAboveIt() {
        let countBox = app.buttons["Edit Count, Inning, Runners and Score"]
        countBox.tap()
        let bag = app.buttons["runners.bag.1"]
        reveal(bag)
        bag.tap()
        app.buttons["Unknown runner"].tap()
        bag.tap()
        let steal = app.buttons["Steal 2nd"]
        XCTAssertTrue(steal.waitForExistence(timeout: 5))
        for _ in 0..<4 where !steal.isHittable { app.scrollViews["runners.actions"].swipeLeft(velocity: .slow) }
        steal.tap()

        switchToTrackGame()
        let zone = app.buttons["Ball Up"].firstMatch
        reveal(zone, up: false)
        zone.tap()
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 8))
        skip.tap()
        let ball = app.buttons["Ball"].firstMatch
        XCTAssertTrue(ball.waitForExistence(timeout: 5))
        ball.tap()
        app.buttons["result.save"].tap()
        if app.buttons["Save"].waitForExistence(timeout: 3) { app.buttons["Save"].tap() }

        _ = cardTexts()
        let runner = app.descendants(matching: .any)["runnerCard"].firstMatch
        let pitch = app.staticTexts["Ball"].firstMatch
        XCTAssertTrue(runner.waitForExistence(timeout: 5))
        XCTAssertTrue(pitch.waitForExistence(timeout: 5))
        XCTAssertLessThan(pitch.frame.minY, runner.frame.minY, "newest first: the pitch above the steal")
    }

    func testSkipHasResetsTint() throws {
        app.buttons["Catcher"].tap()
        app.buttons["Ball Up"].firstMatch.tap()
        let reset = app.buttons["Reset"], skip = app.buttons["Skip"], done = app.buttons["Done"]
        XCTAssertTrue(skip.waitForExistence(timeout: 8))
        let shot = XCUIScreen.main.screenshot().image
        let resetColor = try XCTUnwrap(Self.edgeColor(of: reset.frame, in: shot))
        let skipColor = try XCTUnwrap(Self.edgeColor(of: skip.frame, in: shot))
        let doneColor = try XCTUnwrap(Self.edgeColor(of: done.frame, in: shot))
        XCTAssertLessThan(Self.distance(resetColor, skipColor), 0.06, "Skip looks like Reset")
        XCTAssertGreaterThan(Self.distance(resetColor, doneColor), 0.06, "sanity: Done is the prominent one")
    }

    /// The button's fill, sampled just inside its left edge (away from the
    /// label and icon).
    private static func edgeColor(of frame: CGRect, in image: UIImage) -> (CGFloat, CGFloat, CGFloat)? {
        guard let cg = image.cgImage else { return nil }
        let scale = CGFloat(cg.width) / image.size.width
        let rect = CGRect(x: (frame.minX + 6) * scale, y: (frame.midY - 4) * scale, width: 8 * scale, height: 8 * scale)
        guard let crop = cg.cropping(to: rect.integral) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
    }

    private static func distance(_ a: (CGFloat, CGFloat, CGFloat), _ b: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
        max(abs(a.0 - b.0), abs(a.1 - b.1), abs(a.2 - b.2))
    }

    /// 2026-11-21: Track Game has no key - every pitch type, no Key item,
    /// and Call Pitches gets the key back.
    func testTrackGameHasNoKey() {
        XCTAssertFalse(app.buttons["Screw"].exists, "the demo key has no Screw")
        switchToTrackGame()
        XCTAssertTrue(app.buttons["Screw"].waitForExistence(timeout: 5), "every pitch type in Track Game")
        let menu = app.buttons["Track Game"].firstMatch
        XCTAssertTrue(menu.exists, "the menu reads Track Game")
        menu.tap()
        XCTAssertTrue(app.buttons["Call Pitches"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Key"].exists, "no key picker while tracking")
        app.buttons["Call Pitches"].tap()
        XCTAssertTrue(app.buttons["Key: Demo Grid Key"].waitForExistence(timeout: 5), "the key comes back")
        XCTAssertFalse(app.buttons["Screw"].exists)
    }
}
