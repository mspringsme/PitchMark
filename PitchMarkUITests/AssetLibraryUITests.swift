//
//  AssetLibraryUITests.swift
//  PitchMarkUITests
//
//  Approved 2026-11-15: the Asset Library lists the built-in icons by
//  category and the built-in sounds by group, with chips that filter.
//  (Opening a Moment's Overlays editor needs a clip, which the demo
//  account doesn't have - that's checked on a device.)
//

import XCTest

@MainActor
final class AssetLibraryUITests: XCTestCase {
    func testIconsAndSoundsAreListedByGroup() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestDemo"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["atBat.1"].waitForExistence(timeout: 20), "demo game open")
        app.tabBars.buttons["Moments"].tap()
        app.buttons["Assets"].tap()

        XCTAssertTrue(app.staticTexts["Icons: Highlight"].waitForExistence(timeout: 5), "icon sections")
        XCTAssertTrue(app.staticTexts["Circle"].exists)

        app.buttons["Audio"].tap()
        let stingers = app.buttons["audioLibrary.group.Stingers"]
        XCTAssertTrue(stingers.waitForExistence(timeout: 5), "group chips")
        stingers.tap()
        XCTAssertTrue(app.staticTexts["8-Bit Win"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Wood Crack"].exists, "other groups hidden")
    }
}
