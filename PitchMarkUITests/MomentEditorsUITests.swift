//
//  MomentEditorsUITests.swift
//  PitchMarkUITests
//
//  2026-11-16 (user away, asked for calls to be made): every Moment editor
//  shares one frame - Cancel, its name, Save, a scrubber - and Cancel
//  closes it. Zoom's Save/Cancel answer after adding a zoom area (they
//  didn't), and Filters can be scrubbed (it was one still frame). Runs on
//  `-UITestMomentEditors`, a Moment's real details screen on a test video.
//

import XCTest

@MainActor
final class MomentEditorsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestMomentEditors"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Speed"].waitForExistence(timeout: 20), "the Moment's screen")
    }

    private func open(_ name: String) {
        let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        if !button.isHittable { app.swipeUp() }
        button.tap()
    }

    func testEveryEditorHasTheSameFrameAndCancelCloses() {
        for name in ["Speed", "Zoom", "Crop", "Freeze Frame", "Filters", "Overlays", "Markup", "Audio"] {
            open(name)
            let cancel = app.buttons["editor.cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 8), "\(name): Cancel")
            XCTAssertTrue(app.buttons["editor.save"].exists, "\(name): Save")
            XCTAssertTrue(app.staticTexts[name].exists, "\(name): its name in the top bar")
            XCTAssertTrue(app.descendants(matching: .any)["editor.scrubber"].exists, "\(name): scrubber")
            cancel.tap()
            XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "\(name): Cancel closes it")
        }
    }

    func testZoomsSaveAndCancelStillAnswerAfterAddingAZoomArea() {
        open("Zoom")
        let add = app.buttons["Add Zoom Area Here"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()
        // Zoomed in, the enlarged preview used to cover the top bar.
        let zoomAmount = app.sliders.element(boundBy: 2)   // after Start and End
        XCTAssertTrue(zoomAmount.waitForExistence(timeout: 3), "the zoom amount slider")
        zoomAmount.adjust(toNormalizedSliderPosition: 1.0)
        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.isHittable, "nothing covers Save")
        app.buttons["editor.cancel"].tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "Cancel closes the editor with a zoom area added")
    }

    func testFiltersCanBeScrubbed() {
        open("Filters")
        let scrubber = app.descendants(matching: .any)["editor.scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 8))
        let before = scrubber.value as? String
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        let moved = NSPredicate(format: "value != %@", before ?? "")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: moved, object: scrubber)], timeout: 3), .completed,
                       "tapping the scrubber moves the time")
    }
}
