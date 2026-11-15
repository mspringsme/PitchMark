//
//  MomentsUITests.swift
//  PitchMarkUITests
//
//  Approved 2026-11-15: the Moments library opens on All, with Mixtape,
//  Compare and the filter chips. (The demo account has no clips, so the
//  pick modes and clip screens are checked on a device.)
//

import XCTest

@MainActor
final class MomentsUITests: XCTestCase {
    func testTheLibraryHasMixtapeCompareAndFilters() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestDemo"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["atBat.1"].waitForExistence(timeout: 20), "demo game open")
        app.tabBars.buttons["Moments"].tap()

        XCTAssertTrue(app.buttons["moments.mixtape"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["moments.compare"].exists)
        XCTAssertFalse(app.buttons["Done"].exists, "no Done button on the tab")
        for chip in ["all", "favorites", "videos", "photos"] {
            XCTAssertTrue(app.buttons["moments.filter.\(chip)"].exists, chip)
        }
        XCTAssertTrue(app.staticTexts["No Moments yet. Record one above."].exists, "opens on All")
        XCTAssertFalse(app.buttons["moments.compare"].isEnabled, "Compare needs two clips")
    }
}
