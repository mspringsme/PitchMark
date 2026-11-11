import XCTest

/// Home's row of three - Team Supplies, Join a Game, Account - and the
/// signed-in line under it (approved 2026-11-10). `-UITestHomeActions`
/// shows them alone; the harness reports which button opened what.
final class HomeActionsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestHomeActions"]
        app.launch()
    }

    func testThreeButtonsInOneRowEachOpeningItsOwnThing() {
        let supplies = app.buttons["home.action.supplies"]
        let join = app.buttons["home.action.join"]
        let account = app.buttons["home.action.account"]
        XCTAssertTrue(supplies.waitForExistence(timeout: 8))
        XCTAssertEqual(supplies.label, "Team Supplies")
        XCTAssertEqual(join.label, "Join a Game")
        XCTAssertEqual(account.label, "Account")

        // One row, left to right, the same size.
        XCTAssertEqual(supplies.frame.midY, join.frame.midY, accuracy: 1)
        XCTAssertEqual(join.frame.midY, account.frame.midY, accuracy: 1)
        XCTAssertLessThan(supplies.frame.maxX, join.frame.minX)
        XCTAssertLessThan(join.frame.maxX, account.frame.minX)
        XCTAssertEqual(supplies.frame.width, account.frame.width, accuracy: 1)
        XCTAssertGreaterThan(supplies.frame.height, 70, "tall enough for the ball art over the title")

        let opened = app.staticTexts["harness.opened"]
        join.tap()
        XCTAssertEqual(opened.label, "join")
        account.tap()
        XCTAssertEqual(opened.label, "account")
        supplies.tap()
        XCTAssertTrue(app.staticTexts["harness.store"].waitForExistence(timeout: 3), "Team Supplies opens the store")
    }

    func testTheButtonsSitAtTheBottomJustAboveTheSignedInLine() {
        let join = app.buttons["home.action.join"]
        let line = app.staticTexts["home.signedIn"]
        XCTAssertTrue(join.waitForExistence(timeout: 8))
        let screen = app.windows.firstMatch.frame

        func check(_ when: String) {
            XCTAssertLessThanOrEqual(join.frame.maxY, line.frame.minY, "\(when): the row is above the line")
            XCTAssertLessThan(line.frame.minY - join.frame.maxY, 30, "\(when): directly above it")
            XCTAssertGreaterThan(join.frame.minY, screen.height * 0.7, "\(when): at the bottom of the screen")
        }
        check("at the top")
        let before = join.frame
        app.scrollViews["harness.scroll"].swipeUp()
        app.scrollViews["harness.scroll"].swipeUp()
        check("after scrolling")
        XCTAssertEqual(join.frame.minY, before.minY, accuracy: 1, "the row doesn't scroll away")
        XCTAssertFalse(app.staticTexts["harness.opened"].isHittable, "the page really did scroll")
    }

    func testTheBottomLineShowsWhoIsSignedInAndIsNotAButton() {
        let line = app.staticTexts["home.signedIn"]
        XCTAssertTrue(line.waitForExistence(timeout: 8))
        XCTAssertEqual(line.label, "Signed in as coach@example.com")
        XCTAssertFalse(app.buttons["home.signedIn"].exists, "just text now")

        let toggle = app.buttons["harness.toggleSignIn"]
        toggle.tap()
        XCTAssertEqual(line.label, "Not signed in")
        toggle.tap()
        XCTAssertEqual(line.label, "Signed in as assistant@example.com", "a new sign-in shows the new account")
    }
}
