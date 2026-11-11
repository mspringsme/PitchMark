//
//  SignGridUITests.swift
//  PitchMarkUITests
//
//  Batter & Runner Grids (approved 2026-11-08, several grids 2026-11-09):
//  make a card, type into its cells, add a second grid and style it, save,
//  and it's listed with its grid count, cell count and size.
//  Runs the list and editor on their own (`-UITestSignGrids`), in memory.
//

import XCTest

@MainActor
final class SignGridUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestSignGrids"]
        app.launch()
    }

    func testMakeAGridAndSeeItListed() {
        let new = app.buttons["signGrid.new"]
        XCTAssertTrue(new.waitForExistence(timeout: 8))
        new.tap()

        let name = app.textFields["signGrid.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Steal Signs")

        // 4 x 4 to 3 rows x 5 columns.
        app.buttons["signGrid.rows.minus"].tap()
        app.buttons["signGrid.columns.plus"].tap()
        XCTAssertEqual(app.staticTexts["signGrid.rows.value"].label, "3")
        XCTAssertEqual(app.staticTexts["signGrid.columns.value"].label, "5")
        XCTAssertFalse(app.buttons["signGrid.cell.3.0"].exists, "row 4 removed")
        XCTAssertTrue(app.buttons["signGrid.cell.2.4"].exists, "column 5 added")

        // The top row and first column come numbered; the corner is blank.
        XCTAssertEqual(app.buttons["signGrid.cell.0.0"].value as? String, "")
        XCTAssertEqual(app.buttons["signGrid.cell.0.4"].value as? String, "04")
        XCTAssertEqual(app.buttons["signGrid.cell.2.0"].value as? String, "2")

        // Type a cell, Return moves to the next.
        app.buttons["signGrid.cell.1.1"].tap()
        let cellText = app.textFields["signGrid.cellText"]
        XCTAssertTrue(cellText.waitForExistence(timeout: 5))

        // The grid's own color sits between the row and column styles.
        let color = app.descendants(matching: .any)["signGrid.fillColor"]
        XCTAssertTrue(color.exists)
        let rowN = app.buttons["signGrid.style.row.n"].frame, columnB = app.buttons["signGrid.style.column.b"].frame
        XCTAssertGreaterThan(color.frame.midX, rowN.maxX)
        XCTAssertLessThan(color.frame.midX, columnB.minX)
        XCTAssertEqual(color.frame.midY, rowN.midY, accuracy: 6)

        cellText.typeText("Steal\n")
        cellText.typeText("Bunt")
        XCTAssertEqual(app.buttons["signGrid.cell.1.1"].value as? String, "Steal")
        XCTAssertEqual(app.buttons["signGrid.cell.1.2"].value as? String, "Bunt")

        // A second grid, edited on its own.
        app.buttons["signGrid.keyboardDone"].tap()
        let moreGrids = app.buttons["signGrid.grids.plus"]
        // Typing scrolled the Layout row up under the top bar, where
        // XCUITest still calls it hittable: scroll back by position.
        for _ in 0..<3 where moreGrids.frame.minY < 160 { app.swipeDown() }
        moreGrids.tap()
        XCTAssertEqual(app.staticTexts["signGrid.grids.value"].label, "2")
        let next = app.buttons["signGrid.nextGrid"]
        XCTAssertTrue(next.waitForExistence(timeout: 3))
        next.tap()
        XCTAssertEqual(app.staticTexts["signGrid.currentGrid"].label, "Grid 2")
        XCTAssertEqual(app.buttons["signGrid.cell.0.1"].value as? String, "11", "grid 2 numbers from 11")
        XCTAssertEqual(app.buttons["signGrid.cell.1.1"].value as? String, "", "and its body starts empty")
        app.buttons["signGrid.cell.1.2"].tap()
        cellText.typeText("Squeeze")

        // Row 2 bold and filled; then this cell filled only.
        app.buttons["signGrid.style.row.b"].tap()
        app.buttons["signGrid.style.row.f"].tap()
        XCTAssertEqual(app.buttons["signGrid.style.row.b"].value as? String, "On")
        XCTAssertEqual(app.buttons["signGrid.style.row.f"].value as? String, "On")
        XCTAssertEqual(app.buttons["signGrid.style.cell.b"].value as? String, "On", "the cell follows its row")
        app.buttons["signGrid.style.cell.n"].tap()
        app.buttons["signGrid.style.cell.f"].tap()
        XCTAssertEqual(app.buttons["signGrid.style.cell.b"].value as? String, "Off")
        XCTAssertEqual(app.buttons["signGrid.style.cell.f"].value as? String, "On")
        XCTAssertEqual(app.buttons["signGrid.style.row.b"].value as? String, "On", "the row keeps its style")

        // The whole card shows both grids; tapping one edits it.
        let wire = app.buttons["signGrid.wire.0"]
        if !wire.isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["signGrid.wire.1"].exists)
        wire.tap()
        XCTAssertEqual(app.staticTexts["signGrid.currentGrid"].label, "Grid 1")

        app.buttons["signGrid.save"].tap()

        let row = app.buttons["signGrid.row.Steal Signs"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "saved grid listed")
        XCTAssertTrue(app.staticTexts["2 grids · 3 x 5 cells · 3 1/2 x 2 3/4 in"].exists)

        // Reopening shows what was saved.
        row.tap()
        XCTAssertTrue(app.buttons["signGrid.cell.1.2"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["signGrid.cell.1.2"].value as? String, "Bunt")
        app.buttons["signGrid.nextGrid"].tap()
        XCTAssertEqual(app.buttons["signGrid.cell.1.2"].value as? String, "Squeeze")
        app.buttons["signGrid.cell.1.2"].tap()
        XCTAssertEqual(app.buttons["signGrid.style.cell.f"].value as? String, "On")
        XCTAssertEqual(app.buttons["signGrid.style.cell.b"].value as? String, "Off")
        app.buttons["signGrid.cell.1.0"].tap()
        XCTAssertEqual(app.buttons["signGrid.style.cell.b"].value as? String, "On")
    }

    func testASavedCardsCallingCardListsItsCalls() {
        app.buttons["signGrid.new"].tap()
        let name = app.textFields["signGrid.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Calls")
        app.buttons["signGrid.cell.1.1"].tap()
        let cellText = app.textFields["signGrid.cellText"]
        cellText.typeText("STEAL\n")
        cellText.typeText("STEAL")
        app.buttons["signGrid.save"].tap()

        let open = app.buttons["signGrid.callingCard.Calls"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let steal = app.descendants(matching: .any)["callingCard.call.STEAL"]
        XCTAssertTrue(steal.waitForExistence(timeout: 5))
        XCTAssertTrue(steal.label.contains("STEAL"))
        XCTAssertTrue(steal.label.contains("011 021"), "both cells, column + row: \(steal.label)")
        // Share asks which size.
        app.buttons["callingCard.share"].tap()
        XCTAssertTrue(app.buttons["Full Page (8 1/2 x 11 in)"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Pocket (4 1/4 x 5 1/2 in)"].exists)
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertFalse(app.buttons["Pocket (4 1/4 x 5 1/2 in)"].waitForExistence(timeout: 1))
        app.buttons["callingCard.done"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
    }

    func testAddToQuickFillThenFindItInQuickFill() {
        app.buttons["signGrid.new"].tap()
        let cell = app.buttons["signGrid.cell.1.1"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        let cellText = app.textFields["signGrid.cellText"]
        XCTAssertTrue(cellText.waitForExistence(timeout: 5))
        cellText.typeText("Wheel")

        // The bar sits on the keyboard and doesn't cover the cell's B F N.
        let add = app.buttons["signGrid.addToQuickFill"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(add.frame.minY, app.buttons["signGrid.style.cell.n"].frame.maxY)
        XCTAssertTrue(app.buttons["signGrid.style.cell.n"].isHittable)
        add.tap()
        XCTAssertEqual(add.label, "In Quick Fill")
        XCTAssertFalse(add.isEnabled)

        app.buttons["signGrid.keyboardDone"].tap()
        XCTAssertFalse(add.exists, "only while typing")
        app.buttons["signGrid.cell.2.2"].tap()
        // Picking a cell brings the keyboard back, over Quick Fill.
        let hide = app.buttons["signGrid.keyboardDone"]
        if hide.waitForExistence(timeout: 2) { hide.tap() }
        let quickFill = app.buttons["signGrid.quickFill"]
        if !quickFill.isHittable { app.swipeUp() }
        quickFill.tap()
        let mine = app.buttons["signGrid.quickFill.Wheel"]
        XCTAssertTrue(mine.waitForExistence(timeout: 5), "in My Calls")
        mine.tap()
        XCTAssertEqual(app.buttons["signGrid.cell.2.2"].value as? String, "Wheel")
    }

    func testRandomizeFillsEveryCallCellWithThePickedCalls() {
        app.buttons["signGrid.new"].tap()
        XCTAssertTrue(app.buttons["signGrid.cell.0.0"].waitForExistence(timeout: 5))
        let randomize = app.buttons["signGrid.randomize"]
        for _ in 0..<4 where !randomize.isHittable { app.swipeUp() }
        randomize.tap()

        let fill = app.buttons["signGrid.randomize.fill"]
        XCTAssertTrue(fill.waitForExistence(timeout: 5))
        XCTAssertFalse(fill.isEnabled, "nothing picked yet")
        app.buttons["signGrid.randomize.pick.TAKE"].tap()
        app.buttons["signGrid.randomize.pick.SWING"].tap()
        XCTAssertEqual(app.buttons["signGrid.randomize.pick.TAKE"].value as? String, "On")
        XCTAssertEqual(fill.label, "Fill 9 Empty Cells")
        fill.tap()
        XCTAssertFalse(fill.waitForExistence(timeout: 2) && fill.isHittable, "the sheet closes")

        for _ in 0..<4 where !app.buttons["signGrid.cell.0.0"].isHittable { app.swipeDown() }
        for r in 1..<4 {
            for c in 1..<4 {
                let value = app.buttons["signGrid.cell.\(r).\(c)"].value as? String ?? ""
                XCTAssertTrue(["TAKE", "SWING"].contains(value), "\(r).\(c) holds \(value)")
            }
        }
        XCTAssertEqual(app.buttons["signGrid.cell.0.1"].value as? String, "01", "numbers kept")
        XCTAssertEqual(app.buttons["signGrid.cell.1.0"].value as? String, "1")
    }

    func testQuickFillPutsTheLabelInTheSelectedCell() {
        app.buttons["signGrid.new"].tap()
        let cell = app.buttons["signGrid.cell.1.2"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()

        let quickFill = app.buttons["signGrid.quickFill"]
        if !quickFill.isHittable { app.swipeUp() }
        quickFill.tap()
        let hitAndRun = app.buttons["signGrid.quickFill.H&R"]
        XCTAssertTrue(hitAndRun.waitForExistence(timeout: 5))
        hitAndRun.tap()

        XCTAssertFalse(hitAndRun.waitForExistence(timeout: 2) && hitAndRun.isHittable, "the list closes")
        XCTAssertEqual(app.buttons["signGrid.cell.1.2"].value as? String, "H&R")
        XCTAssertEqual(app.textFields["signGrid.cellText"].value as? String, "H&R", "the same cell stays selected")
    }
}
