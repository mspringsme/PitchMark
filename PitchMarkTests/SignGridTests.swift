import XCTest
import SwiftUI
import PDFKit
@testable import PitchMark

/// Batter & Runner Grids (approved 2026-11-08, several grids per card
/// 2026-11-09): grid count, cell count, bold and fill in any combination,
/// the saved form, the card layout, the printed size and contents, and the
/// order that carries them to fulfillment.
@MainActor
final class SignGridTests: XCTestCase {

    /// Every cell says where it is: "G2R0C1" is grid 2, row 0, column 1
    /// (one-grid cards leave the grid off: "R0C1").
    private func filled(rows: Int, columns: Int, grids: Int = 1,
                        size: GridKeyPrintSize = SignGrid.defaultSize) -> SignGrid {
        var grid = SignGrid(id: "G1", name: "Signs", rows: rows, columns: columns, gridCount: grids, size: size)
        for index in 0..<grids {
            for row in 0..<rows {
                for column in 0..<columns {
                    grid.setText(label(index, row, column, grids: grids), row: row, column: column, in: index)
                }
            }
        }
        return grid
    }

    private func label(_ grid: Int, _ row: Int, _ column: Int, grids: Int) -> String {
        grids == 1 ? "R\(row)C\(column)" : "G\(grid + 1)R\(row)C\(column)"
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SignGridTests-\(UUID()).pdf")
    }

    // MARK: 1. Grid count

    func testMoreGridsKeepsEveryGridsText() {
        var grid = filled(rows: 2, columns: 2, grids: 2)
        grid.setRowStyle(SignGridStyle(fill: true), row: 0, in: 1)
        grid.setGridCount(5)
        XCTAssertEqual(grid.gridCount, 5)
        XCTAssertEqual(grid.text(row: 1, column: 1, in: 0), "G1R1C1")
        XCTAssertEqual(grid.text(row: 0, column: 1, in: 1), "G2R0C1")
        XCTAssertTrue(grid.rowStyle(0, in: 1).fill)
        XCTAssertTrue((2..<5).allSatisfy { grid.isBlank(grid: $0) }, "new grids hold only their numbers")
        XCTAssertEqual(grid.grids[4].cells.count, 4, "new grids have the card's rows and columns")
    }

    func testFewerGridsRemovesTheLastOnesAndSaysWhenThatLosesSomething() {
        var grid = filled(rows: 2, columns: 2, grids: 2)
        grid.setGridCount(4)
        XCTAssertFalse(grid.removesContent(settingGridCount: 2), "grids 3 and 4 are blank")
        XCTAssertTrue(grid.removesContent(settingGridCount: 1), "grid 2 has text")
        grid.setCellStyle(SignGridStyle(bold: true), row: 0, column: 0, in: 3)
        XCTAssertTrue(grid.removesContent(settingGridCount: 3), "a style alone counts")
        grid.setGridCount(1)
        XCTAssertEqual(grid.gridCount, 1)
        XCTAssertEqual(grid.text(row: 0, column: 0), "G1R0C0")
        XCTAssertEqual(grid.text(row: 0, column: 0, in: 1), "", "removed grids read as empty")
    }

    func testGridCountIsOneThroughNine() {
        XCTAssertEqual(SignGrid(gridCount: 0).gridCount, 1)
        XCTAssertEqual(SignGrid(gridCount: 40).gridCount, 9)
        var grid = SignGrid()
        grid.setGridCount(10)
        XCTAssertEqual(grid.gridCount, 9)
        grid.setGridCount(-1)
        XCTAssertEqual(grid.gridCount, 1)
    }

    // MARK: 2. Rows and columns change every grid

    func testResizeKeepsEachCellsTextInItsRowAndColumnOnEveryGrid() {
        var grid = filled(rows: 3, columns: 4, grids: 3)
        grid.resize(rows: 5, columns: 6)
        XCTAssertEqual(grid.rows, 5)
        XCTAssertEqual(grid.columns, 6)
        for index in 0..<3 {
            XCTAssertEqual(grid.grids[index].cells.count, 30)
            for row in 0..<3 {
                for column in 0..<4 {
                    XCTAssertEqual(grid.text(row: row, column: column, in: index), label(index, row, column, grids: 3))
                }
            }
            XCTAssertEqual(grid.text(row: 4, column: 5, in: index), "")
            XCTAssertEqual(grid.text(row: 0, column: 4, in: index), "\(index)4", "a new column is numbered")
        }

        grid.resize(rows: 2, columns: 2)
        XCTAssertEqual(grid.grids[2].cells, ["G3R0C0", "G3R0C1", "G3R1C0", "G3R1C1"])
        // Growing back doesn't bring cut text back.
        grid.resize(rows: 3, columns: 4)
        XCTAssertEqual(grid.text(row: 2, column: 3, in: 1), "")
        XCTAssertEqual(grid.text(row: 1, column: 1, in: 1), "G2R1C1")
    }

    func testResizeKeepsStylesInPlaceAndDropsThemOutsideTheNewSize() {
        var grid = filled(rows: 4, columns: 4, grids: 2)
        let bold = SignGridStyle(bold: true), fill = SignGridStyle(fill: true)
        grid.setRowStyle(bold, row: 3, in: 1)
        grid.setColumnStyle(fill, column: 3, in: 1)
        grid.setRowStyle(bold, row: 1, in: 1)
        grid.setColumnStyle(fill, column: 0, in: 1)
        grid.setCellStyle(fill, row: 0, column: 1, in: 1)
        grid.setCellStyle(bold, row: 3, column: 0, in: 1)
        grid.resize(rows: 3, columns: 5)
        XCTAssertEqual(grid.rowStyle(1, in: 1), bold)
        XCTAssertEqual(grid.rowStyle(3, in: 1), .normal, "row 4 is gone")
        XCTAssertEqual(grid.columnStyle(3, in: 1), fill, "column 4 still exists")
        XCTAssertEqual(grid.columnStyle(0, in: 1), fill)
        XCTAssertEqual(grid.cellOwnStyle(row: 0, column: 1, in: 1), fill, "a cell style follows its cell")
        XCTAssertEqual(grid.style(row: 0, column: 0, in: 0), .normal, "grid 1 untouched")
        grid.resize(rows: 4, columns: 4)
        XCTAssertNil(grid.cellOwnStyle(row: 3, column: 0, in: 1), "dropped styles stay gone")
        XCTAssertEqual(grid.rowStyle(3, in: 1), .normal)
    }

    func testCountsAreLimitedToOneThroughTwelve() {
        XCTAssertEqual(SignGrid(rows: 0, columns: 40).rows, 1)
        XCTAssertEqual(SignGrid(rows: 0, columns: 40).columns, 12)
        var grid = SignGrid(rows: 4, columns: 4, gridCount: 2)
        grid.resize(rows: 13, columns: -2)
        XCTAssertEqual(grid.rows, 12)
        XCTAssertEqual(grid.columns, 1)
        XCTAssertEqual(grid.grids.map(\.cells.count), [12, 12])
    }

    // MARK: 3. Bold, fill and normal

    private let styles: [SignGridStyle] = [.normal, .init(bold: true), .init(fill: true), .init(bold: true, fill: true)]

    func testRowAndColumnStylesCombineInEveryWay() {
        for rowStyle in styles {
            for columnStyle in styles {
                var grid = filled(rows: 3, columns: 3)
                grid.setRowStyle(rowStyle, row: 1)
                grid.setColumnStyle(columnStyle, column: 2)
                let label = "row \(rowStyle) column \(columnStyle)"
                XCTAssertEqual(grid.style(row: 1, column: 2),
                               SignGridStyle(bold: rowStyle.bold || columnStyle.bold,
                                             fill: rowStyle.fill || columnStyle.fill), label)
                // The rest of row 1 follows the row; the rest of column 2 the column.
                XCTAssertEqual(grid.style(row: 1, column: 0), rowStyle, label)
                XCTAssertEqual(grid.style(row: 0, column: 2), columnStyle, label)
                XCTAssertEqual(grid.style(row: 0, column: 0), .normal, label)
            }
        }
    }

    func testACellsOwnStyleOverridesItsRowAndColumn() {
        for rowStyle in styles {
            for columnStyle in styles {
                for cellStyle in styles {
                    var grid = filled(rows: 3, columns: 3)
                    grid.setRowStyle(rowStyle, row: 1)
                    grid.setColumnStyle(columnStyle, column: 2)
                    grid.setCellStyle(cellStyle, row: 1, column: 2)
                    let label = "row \(rowStyle) column \(columnStyle) cell \(cellStyle)"
                    XCTAssertEqual(grid.style(row: 1, column: 2), cellStyle, label)
                    XCTAssertEqual(grid.style(row: 1, column: 1), rowStyle, "neighbours keep the row - \(label)")
                }
            }
        }
        // N on one cell of a bold, filled row makes just that cell plain.
        var grid = filled(rows: 3, columns: 3)
        grid.setRowStyle(SignGridStyle(bold: true, fill: true), row: 0)
        grid.setCellStyle(.normal, row: 0, column: 1)
        XCTAssertEqual(grid.style(row: 0, column: 1), .normal)
        XCTAssertEqual(grid.style(row: 0, column: 0), SignGridStyle(bold: true, fill: true))
    }

    func testStylingARowOrColumnAgainResetsItsCells() {
        var grid = filled(rows: 3, columns: 3)
        grid.setCellStyle(.normal, row: 0, column: 0)
        grid.setCellStyle(SignGridStyle(fill: true), row: 0, column: 1)
        grid.setCellStyle(SignGridStyle(fill: true), row: 1, column: 0)
        grid.setRowStyle(SignGridStyle(bold: true), row: 0)
        XCTAssertEqual(grid.style(row: 0, column: 0), SignGridStyle(bold: true), "latest change wins")
        XCTAssertEqual(grid.style(row: 0, column: 1), SignGridStyle(bold: true))
        XCTAssertEqual(grid.style(row: 1, column: 0), SignGridStyle(fill: true), "other rows keep their cells")
        grid.setColumnStyle(.normal, column: 0)
        XCTAssertEqual(grid.style(row: 1, column: 0), .normal)
        XCTAssertEqual(grid.style(row: 0, column: 0), SignGridStyle(bold: true), "row 1 is still bold")
        grid.setRowStyle(.normal, row: 0)
        XCTAssertEqual(grid.style(row: 0, column: 0), .normal)
    }

    func testStylesBelongToTheirGridAndOutOfRangeWritesAreIgnored() {
        var grid = filled(rows: 2, columns: 2, grids: 2)
        grid.setRowStyle(SignGridStyle(fill: true), row: 0, in: 1)
        XCTAssertEqual(grid.style(row: 0, column: 0, in: 0), .normal)
        XCTAssertTrue(grid.style(row: 0, column: 0, in: 1).fill)

        let before = grid
        grid.setText("nope", row: 2, column: 0)
        grid.setText("nope", row: 0, column: 0, in: 5)
        grid.setRowStyle(SignGridStyle(bold: true), row: 5)
        grid.setColumnStyle(SignGridStyle(bold: true), column: 2)
        grid.setCellStyle(SignGridStyle(bold: true), row: 0, column: 9)
        grid.setCellStyle(SignGridStyle(bold: true), row: 0, column: 0, in: 2)
        XCTAssertEqual(grid, before)
        grid.setText(String(repeating: "x", count: 40), row: 0, column: 0)
        XCTAssertEqual(grid.text(row: 0, column: 0).count, SignGrid.maxCellLength)
    }

    func testFillColorAndTheTextOnIt() {
        var grid = SignGrid()
        XCTAssertEqual(grid.fillColorHex(in: 0), SignGrid.defaultFillHex)
        XCTAssertEqual(grid.textOnFill(in: 0), .white, "the default blue is dark")
        grid.setFillColor(Color(red: 1, green: 0.8, blue: 0.2), in: 0)
        XCTAssertEqual(grid.fillColorHex(in: 0), "FFCC33")
        XCTAssertEqual(grid.textOnFill(in: 0), .black, "dark text on a light fill")
        grid.setFillColor(Color(red: 0.36, green: 0.23, blue: 0.55), in: 0)
        XCTAssertEqual(grid.textOnFill(in: 0), .white)
    }

    func testEachGridHasItsOwnFillColor() throws {
        var grid = filled(rows: 2, columns: 2, grids: 3)
        grid.setFillColorHex("ffcc33", in: 1)
        grid.setFillColorHex("purple", in: 2)
        XCTAssertEqual(grid.fillColorHex(in: 0), SignGrid.defaultFillHex, "grid 1 keeps the default")
        XCTAssertEqual(grid.fillColorHex(in: 1), "FFCC33")
        XCTAssertEqual(grid.fillColorHex(in: 2), SignGrid.defaultFillHex, "a bad color changes nothing")
        XCTAssertEqual(grid.textOnFill(in: 1), .black)
        XCTAssertEqual(grid.textOnFill(in: 0), .white)
        grid.setFillColorHex("112233", in: 2)

        grid.resize(rows: 3, columns: 3)
        grid.setGridCount(4)
        XCTAssertEqual(grid.fillColorHex(in: 1), "FFCC33", "a resize keeps each grid's color")
        XCTAssertEqual(grid.fillColorHex(in: 3), SignGrid.defaultFillHex, "a new grid starts on the default")

        let back = SignGrid(id: grid.id, firestoreData: grid.firestoreData)
        XCTAssertEqual(back, grid)
        XCTAssertEqual(back.fillColorHex(in: 2), "112233")
        let json = try XCTUnwrap(RetailCheckoutRequest.signGrid(grid, storeTemplateName: "S")?
            .payload(idempotencyKey: "k")["templateSnapshotJson"] as? String)
        let ordered = try JSONDecoder().decode(SignGrid.self, from: Data(json.utf8))
        XCTAssertEqual((0..<4).map { ordered.fillColorHex(in: $0) },
                       [SignGrid.defaultFillHex, "FFCC33", "112233", SignGrid.defaultFillHex])
    }

    func testACardSavedWithOneColorUsesItOnEveryGrid() throws {
        let old = SignGrid(id: "old", firestoreData: [
            "rows": 2, "columns": 2, "fillColor": "5b3b8c",
            "grids": [["cells": ["", "01", "1", "a"]], ["cells": ["", "11", "1", "b"]]]
        ])
        XCTAssertEqual(old.fillColorHex(in: 0), "5B3B8C")
        XCTAssertEqual(old.fillColorHex(in: 1), "5B3B8C")
        // An order placed before per-grid colors still decodes for fulfillment.
        // Its grids carry no color of their own, so the snapshot has none.
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(old), encoding: .utf8))
        XCTAssertEqual(json.components(separatedBy: "fillColorHex").count - 1, 1, "only the card's color")
        let ordered = try JSONDecoder().decode(SignGrid.self, from: Data(json.utf8))
        XCTAssertEqual(ordered.fillColorHex(in: 1), "5B3B8C")
    }

    // MARK: 3b. Numbered headers

    /// The top row is the grid's digit + the column, the first column
    /// counts rows, the corner is blank (user's pattern, 2026-11-10).
    func testANewCardNumbersEveryGridsTopRowAndFirstColumn() {
        let grid = SignGrid(rows: 4, columns: 4, gridCount: 3)
        func row(_ r: Int, _ g: Int) -> [String] { (0..<4).map { grid.text(row: r, column: $0, in: g) } }
        func column(_ c: Int, _ g: Int) -> [String] { (0..<4).map { grid.text(row: $0, column: c, in: g) } }
        XCTAssertEqual(row(0, 0), ["", "01", "02", "03"])
        XCTAssertEqual(row(0, 1), ["", "11", "12", "13"])
        XCTAssertEqual(row(0, 2), ["", "21", "22", "23"])
        for g in 0..<3 {
            XCTAssertEqual(column(0, g), ["", "1", "2", "3"], "grid \(g + 1)")
            XCTAssertEqual(row(1, g).dropFirst(), ["", "", ""], "the body starts empty")
        }
        let ninth = SignGrid(rows: 12, columns: 12, gridCount: 9)
        XCTAssertEqual(ninth.text(row: 0, column: 9, in: 8), "89")
        XCTAssertEqual(ninth.text(row: 0, column: 10, in: 8), "", "columns past 9 aren't numbered")
        XCTAssertEqual(ninth.text(row: 11, column: 0, in: 8), "11")
    }

    func testNumbersAreEditableAndLoadingNeverRenumbers() {
        var grid = SignGrid(rows: 3, columns: 3, gridCount: 2)
        grid.setText("Steal", row: 0, column: 1, in: 1)
        grid.setText("", row: 2, column: 0, in: 0)
        let back = SignGrid(id: grid.id, firestoreData: grid.firestoreData)
        XCTAssertEqual(back.text(row: 0, column: 1, in: 1), "Steal")
        XCTAssertEqual(back.text(row: 2, column: 0, in: 0), "", "a cleared number stays cleared")
        XCTAssertEqual(back, grid)
    }

    func testOnlyNewCellsAreNumbered() {
        var grid = SignGrid(rows: 3, columns: 3, gridCount: 1)
        grid.setText("A", row: 0, column: 2)
        grid.setText("", row: 1, column: 0)
        grid.setText("B", row: 1, column: 1)

        grid.resize(rows: 5, columns: 5)
        XCTAssertEqual((0..<5).map { grid.text(row: 0, column: $0) }, ["", "01", "A", "03", "04"])
        XCTAssertEqual((0..<5).map { grid.text(row: $0, column: 0) }, ["", "", "2", "3", "4"])
        XCTAssertEqual(grid.text(row: 1, column: 1), "B")
        XCTAssertEqual(grid.text(row: 4, column: 4), "")

        grid.resize(rows: 2, columns: 2)
        grid.resize(rows: 3, columns: 3)
        XCTAssertEqual(grid.text(row: 0, column: 2), "02", "a column removed and added back is new")

        grid.setGridCount(2)
        XCTAssertEqual((0..<3).map { grid.text(row: 0, column: $0, in: 1) }, ["", "11", "12"])
        XCTAssertEqual(grid.text(row: 1, column: 1), "B", "adding a grid touches no other grid")
    }

    func testAGridWithOnlyItsNumbersRemovesWithoutAsking() {
        var grid = SignGrid(rows: 4, columns: 4, gridCount: 3)
        XCTAssertFalse(grid.removesContent(settingGridCount: 1))
        grid.setText("Bunt", row: 2, column: 2, in: 2)
        XCTAssertTrue(grid.removesContent(settingGridCount: 1))
        XCTAssertFalse(grid.removesContent(settingGridCount: 3))
        grid.setText("99", row: 0, column: 1, in: 1)
        XCTAssertTrue(grid.removesContent(settingGridCount: 2), "an edited number counts")
    }

    // MARK: 4. Saved form

    func testFirestoreRoundTripKeepsEverything() {
        var grid = filled(rows: 3, columns: 5, grids: 3, size: .init(widthInches: 4.75, heightInches: 2.25))
        grid.name = "Steal Signs"
        grid.setRowStyle(SignGridStyle(bold: true, fill: true), row: 0, in: 0)
        grid.setColumnStyle(SignGridStyle(fill: true), column: 4, in: 1)
        grid.setCellStyle(SignGridStyle(bold: true), row: 2, column: 1, in: 2)
        grid.setCellStyle(.normal, row: 0, column: 3, in: 0)
        grid.fillColorHex = "5B3B8C"
        grid.setFillColorHex("FFCC33", in: 1)
        grid.archivedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let back = SignGrid(id: grid.id, firestoreData: grid.firestoreData)
        XCTAssertEqual(back, grid)
        XCTAssertEqual(back.style(row: 0, column: 3, in: 0), .normal, "an N override survives")
    }

    func testSavedFormHasNoNestedArrays() {
        var grid = filled(rows: 4, columns: 4, grids: 2)
        grid.setCellStyle(SignGridStyle(bold: true), row: 1, column: 2, in: 1)
        grid.setRowStyle(SignGridStyle(fill: true), row: 3, in: 0)
        func check(_ value: Any, _ path: String) {
            if let array = value as? [Any] {
                XCTAssertFalse(array.contains { $0 is [Any] }, "\(path) holds an array of arrays - Firestore crashes on that")
                for (index, item) in array.enumerated() { check(item, "\(path)[\(index)]") }
            } else if let map = value as? [String: Any] {
                for (key, item) in map { check(item, "\(path).\(key)") }
            }
        }
        check(grid.firestoreData, "grid")
        let grids = grid.firestoreData["grids"] as? [[String: Any]]
        XCTAssertEqual(grids?.count, 2)
        XCTAssertEqual((grids?[1]["cells"] as? [String])?.count, 16)
    }

    func testAGridSavedBeforeSeveralGridsLoadsAsOneGrid() {
        // The 2026-11-08 form: one grid, bold rows/columns/cells, no fill.
        let old = SignGrid(id: "old", firestoreData: [
            "name": "Old", "rows": 2, "columns": 3,
            "cells": ["a", "b", "c", "d", "e", "f"],
            "boldRows": [1], "boldColumns": [2],
            "boldCells": [["row": 0, "column": 0]],
            "widthInches": 4.0, "heightInches": 3.0
        ])
        XCTAssertEqual(old.gridCount, 1)
        XCTAssertEqual(old.text(row: 1, column: 2), "f")
        XCTAssertEqual(old.fillColorHex, SignGrid.defaultFillHex)
        let bold = SignGridStyle(bold: true)
        // Bold exactly where it was: row 2, column 3 and cell (0,0).
        for row in 0..<2 {
            for column in 0..<3 {
                let wasBold = row == 1 || column == 2 || (row == 0 && column == 0)
                XCTAssertEqual(old.style(row: row, column: column), wasBold ? bold : .normal, "\(row),\(column)")
            }
        }
    }

    func testMissingFieldsLoadAsDefaults() {
        let grid = SignGrid(id: "old", firestoreData: ["name": "Old"])
        XCTAssertEqual(grid.name, "Old")
        XCTAssertEqual(grid.rows, 4)
        XCTAssertEqual(grid.columns, 4)
        XCTAssertEqual(grid.gridCount, 1)
        XCTAssertEqual(grid.grids[0].cells, Array(repeating: "", count: 16))
        XCTAssertEqual(grid.chosenSize, SignGrid.defaultSize)
        XCTAssertNil(grid.archivedAt)

        // A short cells array, a bad style index or a bad color can't misplace anything.
        let short = SignGrid(id: "s", firestoreData: [
            "rows": 2, "columns": 2, "fillColor": "purple",
            "grids": [["cells": ["a"], "rowStyles": [["index": 7, "bold": true]]], ["cells": "nope"]]
        ])
        XCTAssertEqual(short.gridCount, 2)
        XCTAssertEqual(short.grids[0].cells, ["a", "", "", ""])
        XCTAssertTrue(short.grids[0].rowStyles.isEmpty)
        XCTAssertTrue(short.isBlank(grid: 1))
        XCTAssertEqual(short.fillColorHex, SignGrid.defaultFillHex)
    }

    // MARK: 5. Card layout

    func testGridsAreArrangedToFitTheCard() {
        func arrangement(_ count: Int, _ width: Double, _ height: Double, rows: Int = 6, columns: Int = 6) -> SignGridArrangement {
            SignGridArrangement.bestFit(count: count,
                                        cardSize: GridKeyPrintSize(widthInches: width, heightInches: height).points,
                                        rows: rows, columns: columns)
        }
        // The sample wristband card: six 6 x 6 grids, 3 across and 2 down.
        XCTAssertEqual(arrangement(6, 7, 4.75), SignGridArrangement(across: 3, down: 2))
        XCTAssertEqual(arrangement(1, 3.5, 2.75), SignGridArrangement(across: 1, down: 1))
        XCTAssertEqual(arrangement(4, 3.5, 2.75, rows: 4, columns: 4), SignGridArrangement(across: 2, down: 2))
        XCTAssertEqual(arrangement(2, 7, 2.75, rows: 4, columns: 4), SignGridArrangement(across: 2, down: 1))
        XCTAssertEqual(arrangement(2, 3, 5, rows: 4, columns: 4), SignGridArrangement(across: 1, down: 2))
        for count in SignGrid.gridCountRange {
            let fit = arrangement(count, 4.25, 2.5)
            XCTAssertGreaterThanOrEqual(fit.across * fit.down, count, "\(count) grids all have a place")
            XCTAssertLessThan(fit.across * (fit.down - 1), count, "\(count): no empty row of grids")
        }
    }

    func testGridsTileTheCardWithoutOverlapAndCellsTileEachGrid() {
        for size in [CGSize(width: 216, height: 144), CGSize(width: 504, height: 360), CGSize(width: 330, height: 198)] {
            for count in SignGrid.gridCountRange {
                for (rows, columns) in [(1, 1), (3, 5), (12, 12)] {
                    let grid = SignGrid(rows: rows, columns: columns, gridCount: count)
                    let layout = SignGridCardLayout(grid: grid, size: size)
                    let card = CGRect(origin: .zero, size: size)
                    let rects = (0..<count).map(layout.gridRect)
                    for (index, rect) in rects.enumerated() {
                        XCTAssertTrue(layout.contentRect.insetBy(dx: -0.001, dy: -0.001).contains(rect),
                                      "grid \(index + 1) of \(count) off the card at \(size)")
                        XCTAssertGreaterThan(rect.width, 0)
                        XCTAssertGreaterThan(rect.height, 0)
                        for other in rects[(index + 1)...] {
                            XCTAssertLessThan(rect.intersection(other).width * rect.intersection(other).height, 0.001,
                                              "grids overlap: \(count) at \(size)")
                        }
                        // Cells fill the grid exactly.
                        let cells = SignGridLayout(rect: rect, rows: rows, columns: columns)
                        let last = cells.frame(row: rows - 1, column: columns - 1)
                        XCTAssertEqual(cells.frame(row: 0, column: 0).minX, rect.minX, accuracy: 0.001)
                        XCTAssertEqual(last.maxX, rect.maxX, accuracy: 0.001)
                        XCTAssertEqual(last.maxY, rect.maxY, accuracy: 0.001)
                    }
                    XCTAssertTrue(card.contains(layout.contentRect))
                    XCTAssertGreaterThan(layout.inset, 0, "a margin keeps the lines off the cut edge")
                    // The grids reach the card's right and bottom margins.
                    XCTAssertEqual(rects.map(\.maxX).max()!, layout.contentRect.maxX, accuracy: 0.001)
                    XCTAssertEqual(rects.map(\.maxY).max()!, layout.contentRect.maxY, accuracy: 0.001)
                }
            }
        }
    }

    func testTheWireframeAndThePrintPlaceGridsTheSameWay() {
        let grid = filled(rows: 5, columns: 6, grids: 6, size: .init(widthInches: 7, heightInches: 4.75))
        let print = SignGridCardLayout(grid: grid, size: grid.chosenSize.points)
        let small = CGSize(width: 260, height: 260 * 4.75 / 7)
        let wire = SignGridCardLayout(grid: grid, size: small)
        let scale = small.width / grid.chosenSize.points.width
        XCTAssertEqual(print.arrangement, wire.arrangement)
        for index in 0..<6 {
            // Same order and place; only the margins are rounded differently.
            XCTAssertEqual(print.gridRect(index).midX * scale, wire.gridRect(index).midX, accuracy: 3)
            XCTAssertEqual(print.gridRect(index).midY * scale, wire.gridRect(index).midY, accuracy: 3)
        }
    }

    func testOnlyAValidCardSizePrintsNeverAFallback() {
        XCTAssertEqual(SignGrid(size: .init(widthInches: 4.25, heightInches: 2.5)).printSize,
                       GridKeyPrintSize(widthInches: 4.25, heightInches: 2.5))
        XCTAssertEqual(SignGrid(size: .init(widthInches: 3, heightInches: 2)).printSize,
                       GridKeyPrintSize(widthInches: 3, heightInches: 2))
        XCTAssertEqual(SignGrid(size: .init(widthInches: 7, heightInches: 5)).printSize,
                       GridKeyPrintSize(widthInches: 7, heightInches: 5))
        for bad in [GridKeyPrintSize(widthInches: 2.75, heightInches: 3),
                    .init(widthInches: 7.25, heightInches: 3),
                    .init(widthInches: 4, heightInches: 1.75),
                    .init(widthInches: 4, heightInches: 5.25),
                    .init(widthInches: 4.1, heightInches: 3)] {
            XCTAssertNil(SignGrid(size: bad).printSize, bad.label)
        }
    }

    // MARK: 6. The printed card

    func testPDFPageIsExactlyTheChosenSize() throws {
        let sizes: [GridKeyPrintSize] = [.init(widthInches: 3, heightInches: 2),
                                         .init(widthInches: 3.5, heightInches: 2.75),
                                         .init(widthInches: 4.25, heightInches: 2.5),
                                         .init(widthInches: 7, heightInches: 5)]
        for size in sizes {
            let url = tempURL()
            defer { try? FileManager.default.removeItem(at: url) }
            XCTAssertTrue(SignGridPrint.writePDF(for: filled(rows: 3, columns: 3, size: size), size: size, to: url))
            let document = try XCTUnwrap(PDFDocument(url: url))
            XCTAssertEqual(document.pageCount, 1)
            let box = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
            XCTAssertEqual(box.width / 72, size.widthInches, accuracy: 0.001, size.label)
            XCTAssertEqual(box.height / 72, size.heightInches, accuracy: 0.001, size.label)
        }
    }

    func testPDFHoldsEveryCellsText() throws {
        let cases: [(Int, Int, Int, GridKeyPrintSize)] = [(3, 3, 1, SignGrid.defaultSize),
                                                          (12, 12, 1, .init(widthInches: 3, heightInches: 2)),
                                                          (1, 12, 1, .init(widthInches: 7, heightInches: 2)),
                                                          (12, 1, 1, .init(widthInches: 3, heightInches: 5)),
                                                          (5, 5, 6, .init(widthInches: 7, heightInches: 4.75)),
                                                          (3, 4, 9, .init(widthInches: 7, heightInches: 5))]
        for (rows, columns, grids, size) in cases {
            let grid = filled(rows: rows, columns: columns, grids: grids, size: size)
            let url = tempURL()
            defer { try? FileManager.default.removeItem(at: url) }
            XCTAssertTrue(SignGridPrint.writePDF(for: grid, size: size, to: url))
            let text = try XCTUnwrap(PDFDocument(url: url)?.string)
            let words = Set(text.components(separatedBy: .whitespacesAndNewlines))
            for index in 0..<grids {
                for row in 0..<rows {
                    for column in 0..<columns {
                        let text = label(index, row, column, grids: grids)
                        XCTAssertTrue(words.contains(text), "\(grids) x \(rows)x\(columns) on \(size.label): \(text) missing")
                    }
                }
            }
        }
    }

    /// The PDF rasterized at 4x, RGBA, rows top-down.
    private func raster(pdf url: URL, size: GridKeyPrintSize) throws -> (pixels: [UInt8], width: Int, scale: CGFloat) {
        let page = try XCTUnwrap(CGPDFDocument(url as CFURL)?.page(at: 1))
        let scale: CGFloat = 4
        let points = size.points
        let width = Int(points.width * scale), height = Int(points.height * scale)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(page)
        return (pixels, width, scale)
    }

    /// Per cell of one grid, read off the PDF itself (PDFKit can't report
    /// real font names - it says Times for everything): how many pixels
    /// are near black (text on white) and how many are near white (text on
    /// a fill). "Black" is anything dark - text, or a dark fill.
    private struct CellInk { var black = 0; var white = 0; var total = 0 }

    private func inkPerCell(pdf url: URL, grid: SignGrid, index: Int = 0,
                            size: GridKeyPrintSize) throws -> [SignGridPosition: CellInk] {
        let (pixels, width, scale) = try raster(pdf: url, size: size)
        let rect = SignGridCardLayout(grid: grid, size: size.points).gridRect(index)
        let layout = SignGridLayout(rect: rect, rows: grid.rows, columns: grid.columns)
        var ink: [SignGridPosition: CellInk] = [:]
        for row in 0..<grid.rows {
            for column in 0..<grid.columns {
                // Inside the lines only.
                let frame = layout.frame(row: row, column: column).insetBy(dx: 3, dy: 3)
                var cell = CellInk()
                for y in Int(frame.minY * scale)..<Int(frame.maxY * scale) {
                    for x in Int(frame.minX * scale)..<Int(frame.maxX * scale) {
                        let i = (y * width + x) * 4
                        let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                        if r + g + b < 270 { cell.black += 1 }
                        if r > 230 && g > 230 && b > 230 { cell.white += 1 }
                        cell.total += 1
                    }
                }
                ink[SignGridPosition(row: row, column: column)] = cell
            }
        }
        return ink
    }

    func testBoldCellsPrintBold() throws {
        let plain = filled(rows: 3, columns: 3, grids: 2)
        var grid = plain
        grid.setRowStyle(SignGridStyle(bold: true), row: 0, in: 1)
        grid.setColumnStyle(SignGridStyle(bold: true), column: 2, in: 1)
        grid.setCellStyle(SignGridStyle(bold: true), row: 1, column: 0, in: 1)
        grid.setCellStyle(.normal, row: 0, column: 2, in: 1)
        let size = GridKeyPrintSize(widthInches: 5, heightInches: 2.5)
        let plainURL = tempURL(), boldURL = tempURL()
        defer {
            try? FileManager.default.removeItem(at: plainURL)
            try? FileManager.default.removeItem(at: boldURL)
        }
        var sizedPlain = plain, sizedGrid = grid
        sizedPlain.widthInches = size.widthInches; sizedPlain.heightInches = size.heightInches
        sizedGrid.widthInches = size.widthInches; sizedGrid.heightInches = size.heightInches
        XCTAssertTrue(SignGridPrint.writePDF(for: sizedPlain, size: size, to: plainURL))
        XCTAssertTrue(SignGridPrint.writePDF(for: sizedGrid, size: size, to: boldURL))
        for index in 0..<2 {
            let before = try inkPerCell(pdf: plainURL, grid: sizedPlain, index: index, size: size)
            let after = try inkPerCell(pdf: boldURL, grid: sizedGrid, index: index, size: size)
            for row in 0..<3 {
                for column in 0..<3 {
                    let position = SignGridPosition(row: row, column: column)
                    let plainInk = Double(before[position]!.black), ink = Double(after[position]!.black)
                    let name = "grid \(index + 1) R\(row)C\(column)"
                    XCTAssertGreaterThan(plainInk, 30, "\(name) drew no text")
                    if sizedGrid.style(row: row, column: column, in: index).bold {
                        XCTAssertGreaterThan(ink, plainInk * 1.15, "\(name) should print bold")
                    } else {
                        XCTAssertEqual(ink, plainInk, accuracy: plainInk * 0.03, "\(name) should print regular")
                    }
                }
            }
        }
    }

    func testFilledCellsPrintTheFillColorWithLightText() throws {
        let size = GridKeyPrintSize(widthInches: 4, heightInches: 3)
        var grid = filled(rows: 3, columns: 3, size: size)
        grid.fillColorHex = "202060"
        grid.setRowStyle(SignGridStyle(fill: true), row: 0)
        grid.setCellStyle(SignGridStyle(bold: true, fill: true), row: 2, column: 2)
        grid.setCellStyle(.normal, row: 0, column: 1)
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(SignGridPrint.writePDF(for: grid, size: size, to: url))
        let ink = try inkPerCell(pdf: url, grid: grid, size: size)
        for row in 0..<3 {
            for column in 0..<3 {
                let cell = ink[SignGridPosition(row: row, column: column)]!
                let name = "R\(row)C\(column)"
                if grid.style(row: row, column: column).fill {
                    XCTAssertGreaterThan(Double(cell.black) / Double(cell.total), 0.5, "\(name) should be filled")
                    XCTAssertGreaterThan(cell.white, 30, "\(name) needs light text on the fill")
                } else {
                    XCTAssertGreaterThan(Double(cell.white) / Double(cell.total), 0.5, "\(name) should be white")
                }
            }
        }
        // The fill really is the card's color.
        let (pixels, width, scale) = try raster(pdf: url, size: size)
        let frame = SignGridLayout(rect: SignGridCardLayout(grid: grid, size: size.points).gridRect(0),
                                   rows: 3, columns: 3).frame(row: 0, column: 0)
        let i = (Int((frame.minY + 2) * scale) * width + Int((frame.minX + 2) * scale)) * 4
        XCTAssertEqual(Double(pixels[i]), 0x20, accuracy: 12)
        XCTAssertEqual(Double(pixels[i + 2]), 0x60, accuracy: 12)
    }

    // MARK: 9. Checkout

    func testCheckoutCarriesTheGridsSizeAndAWorkingCopy() throws {
        var grid = filled(rows: 2, columns: 3, grids: 3, size: .init(widthInches: 4.25, heightInches: 2.5))
        grid.setColumnStyle(SignGridStyle(bold: true, fill: true), column: 1, in: 2)
        grid.fillColorHex = "5B3B8C"
        let request = try XCTUnwrap(RetailCheckoutRequest.signGrid(grid, storeTemplateName: "Batter & Runner Grid"))
        let payload = request.payload(idempotencyKey: "pm_key")
        XCTAssertEqual(payload["retailProductId"] as? String, "sign_grid_custom")
        XCTAssertEqual(payload["itemKind"] as? String, "signGrid")
        XCTAssertEqual(payload["templateId"] as? String, "G1")
        XCTAssertEqual(payload["printWidthInches"] as? Double, 4.25)
        XCTAssertEqual(payload["printHeightInches"] as? Double, 2.5)
        let json = try XCTUnwrap(payload["templateSnapshotJson"] as? String)
        XCTAssertEqual(try JSONDecoder().decode(SignGrid.self, from: Data(json.utf8)), grid)

        XCTAssertNil(RetailCheckoutRequest.signGrid(SignGrid(size: .init(widthInches: 9, heightInches: 3)),
                                                    storeTemplateName: "x"))
    }

    func testChangingSizeOrContentsIsANewCheckout() throws {
        let grid = filled(rows: 2, columns: 2)
        let first = try XCTUnwrap(RetailCheckoutRequest.signGrid(grid, storeTemplateName: "S"))
        let same = try XCTUnwrap(RetailCheckoutRequest.signGrid(grid, storeTemplateName: "S"))
        XCTAssertEqual(first.fingerprint, same.fingerprint)

        var resized = grid
        resized.widthInches = 4
        XCTAssertNotEqual(first.fingerprint, try XCTUnwrap(RetailCheckoutRequest.signGrid(resized, storeTemplateName: "S")).fingerprint)

        var edited = grid
        edited.setText("Bunt", row: 0, column: 0)
        XCTAssertNotEqual(first.fingerprint, try XCTUnwrap(RetailCheckoutRequest.signGrid(edited, storeTemplateName: "S")).fingerprint)

        var bolded = grid
        bolded.setRowStyle(SignGridStyle(bold: true), row: 1)
        XCTAssertNotEqual(first.fingerprint, try XCTUnwrap(RetailCheckoutRequest.signGrid(bolded, storeTemplateName: "S")).fingerprint)

        var filledIn = grid
        filledIn.setCellStyle(SignGridStyle(fill: true), row: 0, column: 1)
        XCTAssertNotEqual(first.fingerprint, try XCTUnwrap(RetailCheckoutRequest.signGrid(filledIn, storeTemplateName: "S")).fingerprint)

        var recolored = grid
        recolored.setFillColorHex("112233", in: 0)
        XCTAssertNotEqual(first.fingerprint, try XCTUnwrap(RetailCheckoutRequest.signGrid(recolored, storeTemplateName: "S")).fingerprint)

        var moreGrids = grid
        moreGrids.setGridCount(2)
        XCTAssertNotEqual(first.fingerprint, try XCTUnwrap(RetailCheckoutRequest.signGrid(moreGrids, storeTemplateName: "S")).fingerprint)

        // Styles live in dictionaries; the same design must always encode the same way.
        var styled = filled(rows: 4, columns: 4, grids: 3)
        for index in 0..<3 {
            for n in 0..<4 {
                styled.setCellStyle(SignGridStyle(bold: n % 2 == 0, fill: true), row: n, column: 3 - n, in: index)
                styled.setColumnStyle(SignGridStyle(bold: true), column: n, in: index)
            }
        }
        let fingerprints = Set((0..<20).map { _ in RetailCheckoutRequest.signGrid(styled, storeTemplateName: "S")!.fingerprint })
        XCTAssertEqual(fingerprints.count, 1)
    }

    /// The same fix for grid keys: an edited key ordered again in the same
    /// session used to get the first checkout - and print the old key.
    func testAnEditedGridKeyIsANewCheckout() {
        var key = PitchTemplate(id: UUID(), name: "Key", pitches: ["Fastball"], codeAssignments: [])
        func request(_ template: PitchTemplate) -> RetailCheckoutRequest {
            RetailCheckoutRequest(retailProductId: "grid_5x3", itemKind: "gridKey", templateId: template.id.uuidString,
                                  templateName: template.name, storeTemplateName: "5 x 3 in.",
                                  templateSnapshotJson: RetailCheckoutRequest.snapshotJson(template),
                                  printSize: GridKeyProduct.printSize(productId: "grid_5x3", custom: nil))
        }
        let before = request(key)
        XCTAssertEqual(before.fingerprint, request(key).fingerprint)
        key.strikeTopRow = ["A", "B", "C"]
        XCTAssertNotEqual(before.fingerprint, request(key).fingerprint)
    }

    // MARK: 10. Fulfillment

    func testFulfillmentPrintsTheOrderedGridAtTheOrderedSize() throws {
        let size = GridKeyPrintSize(widthInches: 5.5, heightInches: 3.25)
        let grid = filled(rows: 2, columns: 2, grids: 4, size: size)
        let payload = try XCTUnwrap(RetailCheckoutRequest.signGrid(grid, storeTemplateName: "S")).payload(idempotencyKey: "k")
        // What the webhook saves on retailOrders.
        let order: [String: Any] = [
            "retailProductId": payload["retailProductId"]!,
            "printWidthInches": payload["printWidthInches"]!,
            "printHeightInches": payload["printHeightInches"]!,
            "orderedTemplateSnapshotJson": payload["templateSnapshotJson"]!
        ]
        let orderedSize = GridKeyProduct.orderPrintSize(order)
        XCTAssertNil(GridKeyProduct.printSizeProblem(productId: "sign_grid_custom", orderedSize: orderedSize))

        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(SignGridPrint.writeOrderPDF(snapshotJson: order["orderedTemplateSnapshotJson"] as! String,
                                                  orderedSize: orderedSize, to: url))
        let document = try XCTUnwrap(PDFDocument(url: url))
        let box = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(box.width / 72, 5.5, accuracy: 0.001)
        XCTAssertEqual(box.height / 72, 3.25, accuracy: 0.001)
        for index in 1...4 {
            XCTAssertTrue(document.string?.contains("G\(index)R1C1") == true, "grid \(index) missing")
        }
    }

    func testAGridOrderWithoutASizeIsFlaggedAndNotPrinted() {
        XCTAssertNotNil(GridKeyProduct.printSizeProblem(productId: "sign_grid_custom", orderedSize: nil))
        XCTAssertTrue(GridKeyProduct.printsOnCard("sign_grid_custom"))
        XCTAssertTrue(GridKeyProduct.isCustom("sign_grid_custom"))
        let json = RetailCheckoutRequest.snapshotJson(filled(rows: 2, columns: 2))
        XCTAssertFalse(SignGridPrint.writeOrderPDF(snapshotJson: json, orderedSize: nil, to: tempURL()))
        XCTAssertFalse(SignGridPrint.writeOrderPDF(snapshotJson: "not json",
                                                   orderedSize: .init(widthInches: 4, heightInches: 3), to: tempURL()))
    }

    // MARK: 11. Quick Fill

    func testQuickFillIsTheUsersListAndEveryLabelFitsACell() {
        XCTAssertEqual(SignGridQuickFill.sections.map(\.title),
                       ["At Bat", "On Base", "Outfield Positioning", "Infield Positioning",
                        "Bunt Coverage and Plays", "Modifiers"])
        XCTAssertEqual(SignGridQuickFill.sections.map(\.items.count), [10, 5, 6, 4, 4, 1])
        let items = SignGridQuickFill.sections.flatMap(\.items)
        XCTAssertEqual(items.map(\.label), [
            "TAKE", "SWING", "H&R", "Sac B", "Fk Bt Sw", "DRAG", "P Bt 1", "P Bt 3", "PROT", "FREE",
            "STEAL", "DLY STL", "FB STL", "DBL STL", "HALF",
            "OF BAC", "OF IN", "OF NOR", "SHD L", "SHD R", "HOME",
            "IF IN", "IF BAC", "COR IN", "IF NOR",
            "BC1", "BC2", "BC3", "CRASH",
            "OFF"
        ])
        XCTAssertEqual(Set(items.map(\.label)).count, items.count, "a label is used twice")
        XCTAssertEqual(Set(items.map(\.meaning)).count, items.count, "a meaning is listed twice")
        var grid = SignGrid()
        for item in items {
            XCTAssertLessThanOrEqual(item.label.count, SignGrid.maxCellLength, item.label)
            grid.setText(item.label, row: 0, column: 0)
            XCTAssertEqual(grid.text(row: 0, column: 0), item.label, "\(item.label) is cut short")
        }
    }
}
