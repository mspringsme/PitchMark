import XCTest

/// Approved 2026-11-20 (T2): sheets are easy to close. On the real Home
/// (Skip for Now, demo mode, nothing written):
/// - a plain sheet (Account, 42% tall) and a small one (More, 24% tall)
///   each show a ✕ with at least a 44 pt tap area, inside the screen, and
///   the ✕ closes them;
/// - a sheet with its own navigation bar (the Call Sheet) gets no extra ✕ -
///   its own Done stays the button.
final class SheetCloseUITests: XCTestCase {

    private func openDemoHome(_ app: XCUIApplication) {
        app.launch()
        let skip = app.buttons["Skip for Now"]
        if skip.waitForExistence(timeout: 10) { skip.tap() }
        let homeTab = app.buttons["Home"]
        if homeTab.waitForExistence(timeout: 10) { homeTab.tap() }
    }

    private func assertCloseButton(_ close: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(close.waitForExistence(timeout: 5), "no ✕", file: file, line: line)
        // A sheet springs into place: measure once it has stopped moving.
        var last = CGRect.null
        for _ in 0..<30 {
            let now = close.frame
            if now == last { break }
            last = now
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        XCTAssertGreaterThanOrEqual(close.frame.width, 44, "✕ narrower than 44 pt", file: file, line: line)
        XCTAssertGreaterThanOrEqual(close.frame.height, 44, "✕ shorter than 44 pt", file: file, line: line)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(close.frame), "✕ off screen", file: file, line: line)
        XCTAssertTrue(close.isHittable, "✕ can't be tapped", file: file, line: line)
    }

    func testPlainAndSmallSheetsCloseWithTheX() {
        continueAfterFailure = false
        let app = XCUIApplication()
        openDemoHome(app)

        let account = app.buttons["home.action.account"]
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        account.tap()
        // "Account" is also Home's button behind the sheet; Credits is the sheet's own.
        let credits = app.staticTexts["Credits"]
        XCTAssertTrue(credits.waitForExistence(timeout: 5))
        let close = app.buttons["sheet.close"]
        assertCloseButton(close, in: app)
        XCTAssertLessThan(close.frame.minY, credits.frame.minY, "the ✕ sits above the sheet's content")
        close.tap()
        XCTAssertTrue(credits.waitForNonExistence(timeout: 5), "the ✕ closed the Account sheet")

        account.tap()
        let more = app.buttons["account.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let deleteRow = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Delete'")).firstMatch
        XCTAssertTrue(deleteRow.waitForExistence(timeout: 5), "the More sheet opened")
        let smallClose = app.buttons["sheet.close"]
        assertCloseButton(smallClose, in: app)
        smallClose.tap()
        XCTAssertTrue(deleteRow.waitForNonExistence(timeout: 5), "the ✕ closed the small More sheet")
    }

    func testASheetWithItsOwnNavigationBarGetsNoExtraX() {
        continueAfterFailure = false
        let app = XCUIApplication()
        openDemoHome(app)
        let supplies = app.buttons["home.action.supplies"]
        XCTAssertTrue(supplies.waitForExistence(timeout: 10))
        supplies.tap()
        let pitching = app.staticTexts["home.section.pitching"]
        XCTAssertTrue(pitching.waitForExistence(timeout: 5))
        pitching.tap()
        let key = app.buttons["Demo Grid Key"]
        XCTAssertTrue(key.waitForExistence(timeout: 8))
        key.tap()
        let call = app.buttons["pitchKey.call"]
        XCTAssertTrue(call.waitForExistence(timeout: 5))
        call.tap()

        let done = app.buttons["callSheet.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["sheet.close"].exists, "a second close button on a sheet with a nav bar")
        XCTAssertGreaterThanOrEqual(done.frame.minY, app.windows.firstMatch.frame.minY + 20, "Done isn't jammed against the top")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
    }
}
