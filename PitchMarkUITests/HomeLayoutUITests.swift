import XCTest

/// The real Home, reached through Skip for Now (demo mode, nothing
/// written): the logo centered at the top. The armband keys - Pitching
/// and Batting Bases & Fielding - live in Team Supplies, above the store's
/// products, not on Home (approved 2026-11-18; was "Armband Keys" on Home,
/// 2026-11-10).
final class HomeLayoutUITests: XCTestCase {

    func testLogoIsCenteredAndTheArmbandKeysAreInTeamSupplies() {
        continueAfterFailure = false
        let app = XCUIApplication()
        openDemoHome(app)

        let logo = app.descendants(matching: .any)["home.logo"]
        XCTAssertTrue(logo.waitForExistence(timeout: 10))
        let screen = app.windows.firstMatch.frame
        XCTAssertEqual(logo.frame.midX, screen.midX, accuracy: 2, "centered")
        XCTAssertGreaterThanOrEqual(logo.frame.height, 110, "larger than before (64)")
        XCTAssertFalse(app.staticTexts["Code Grid Keys"].exists)
        XCTAssertFalse(app.staticTexts["Batter & Runner Grids"].exists)

        let pitching = app.staticTexts["home.section.pitching"]
        let batting = app.staticTexts["home.section.batting"]
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertFalse(app.staticTexts["home.armbandKeys"].exists, "no Armband Keys on Home")
        XCTAssertFalse(pitching.exists, "Pitching keys aren't on Home")
        XCTAssertFalse(batting.exists, "Batting keys aren't on Home")

        openTeamSupplies(app)
        let header = app.staticTexts["supplies.armbandKeys"]
        let product = app.staticTexts["Pitching Key"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertTrue(product.waitForExistence(timeout: 5))
        XCTAssertEqual(header.label, "Your Armband Keys")
        XCTAssertEqual(pitching.label, "Pitching")
        XCTAssertEqual(batting.label, "Batting Bases & Fielding")
        XCTAssertLessThan(header.frame.maxY, pitching.frame.minY, "Your Armband Keys heads the two")
        XCTAssertLessThan(pitching.frame.maxY, batting.frame.minY)
        XCTAssertLessThan(batting.frame.maxY, product.frame.minY, "the keys come before the store")
    }

    /// A key's Call in Team Supplies opens the Call Sheet on that key
    /// (approved 2026-11-18).
    func testCallOnAKeyInTeamSuppliesOpensTheCallSheet() {
        continueAfterFailure = false
        let app = XCUIApplication()
        openDemoHome(app)
        openTeamSupplies(app)

        let pitching = app.staticTexts["home.section.pitching"]
        XCTAssertTrue(pitching.waitForExistence(timeout: 5))
        pitching.tap()
        let key = app.buttons["Demo Grid Key"]
        XCTAssertTrue(key.waitForExistence(timeout: 8), "the demo key is listed")
        key.tap()
        let call = app.buttons["pitchKey.call"]
        XCTAssertTrue(call.waitForExistence(timeout: 5))
        call.tap()

        XCTAssertTrue(app.staticTexts["Call Sheet"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Demo Grid Key"].exists, "on the key that was tapped")
    }

    private func openTeamSupplies(_ app: XCUIApplication) {
        let supplies = app.buttons["home.action.supplies"]
        XCTAssertTrue(supplies.waitForExistence(timeout: 10))
        supplies.tap()
    }

    func testTheStoreSellsWaterproofCallingCards() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let skip = app.buttons["Skip for Now"]
        if skip.waitForExistence(timeout: 10) { skip.tap() }
        let homeTab = app.buttons["Home"]
        if homeTab.waitForExistence(timeout: 10) { homeTab.tap() }
        let supplies = app.buttons["home.action.supplies"]
        XCTAssertTrue(supplies.waitForExistence(timeout: 10))
        supplies.tap()

        let product = app.staticTexts["Waterproof Calling Cards"]
        for _ in 0..<6 where !product.isHittable { app.swipeUp() }
        XCTAssertTrue(product.isHittable, "listed in the store")
        product.tap()
        XCTAssertTrue(app.staticTexts["store.callingCard.title"].waitForExistence(timeout: 5))
        let order = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "$8.00")).firstMatch
        for _ in 0..<3 where !order.exists { app.swipeUp() }
        XCTAssertTrue(order.exists, "priced at $8")
    }

    private func openDemoHome(_ app: XCUIApplication) {
        app.launch()
        let skip = app.buttons["Skip for Now"]
        if skip.waitForExistence(timeout: 10) { skip.tap() }
        let homeTab = app.buttons["Home"]
        if homeTab.waitForExistence(timeout: 10) { homeTab.tap() }
    }

    /// A pitching key's size is picked in its editor (approved 2026-11-10),
    /// opened from Team Supplies (2026-11-18).
    func testTheKeyEditorPicksTheKeysPrintSize() {
        continueAfterFailure = false
        let app = XCUIApplication()
        openDemoHome(app)
        openTeamSupplies(app)
        let newKey = app.buttons["New code grid key"]
        XCTAssertTrue(newKey.waitForExistence(timeout: 5))
        newKey.tap()

        let width = app.buttons["gridKey.printWidth"]
        let height = app.buttons["gridKey.printHeight"]
        XCTAssertTrue(width.waitForExistence(timeout: 8))
        XCTAssertTrue(width.label.contains("5 in"), "a new key starts at 5 x 3: \(width.label)")
        XCTAssertTrue(height.label.contains("3 in"), height.label)
        width.tap()
        app.buttons["4 1/4 in"].tap()
        height.tap()
        app.buttons["2 1/2 in"].tap()
        XCTAssertTrue(width.label.contains("4 1/4 in"), width.label)
        XCTAssertTrue(height.label.contains("2 1/2 in"), height.label)
    }

    /// The store sells one pitching key item, at the key's size - no set
    /// sizes and no size pickers (approved 2026-11-10).
    func testTheStoreHasOnePitchingKeyWithNoSizePickers() {
        continueAfterFailure = false
        let app = XCUIApplication()
        openDemoHome(app)
        let supplies = app.buttons["home.action.supplies"]
        XCTAssertTrue(supplies.waitForExistence(timeout: 10))
        supplies.tap()

        let item = app.staticTexts["Pitching Key"]
        XCTAssertTrue(item.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["5 x 3 in."].exists)
        XCTAssertFalse(app.staticTexts["3.5 x 2.75 in."].exists)
        XCTAssertFalse(app.staticTexts["Custom"].exists)
        item.tap()
        let order = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "$14.00")).firstMatch
        XCTAssertTrue(order.waitForExistence(timeout: 5), "priced at $14")
        XCTAssertFalse(app.staticTexts["Custom Size (inches)"].exists, "no size pickers in the store")
        XCTAssertFalse(app.buttons["Width"].exists)
    }
}

