//
//  SignGrid.swift
//  PitchMark
//
//  Batter & Runner Grids: a sign card the coach lays out from scratch -
//  the card's real print size, how many grids are pieced together on it,
//  their rows and columns, the text in every cell, and which rows, columns
//  and cells print bold or filled. The model, its
//  Firestore form, the card layout and the PDF all live here so the editor,
//  Home, the store and fulfillment draw the same card.
//
import SwiftUI
import UIKit
import Combine
import FirebaseFirestore

struct SignGridPosition: Hashable, Codable {
    let row: Int
    let column: Int
}

/// How a cell prints: bold, filled with the card's color, both, or
/// neither ("normal").
struct SignGridStyle: Hashable, Codable {
    var bold = false
    var fill = false

    static let normal = SignGridStyle()
    var isNormal: Bool { !bold && !fill }

    func union(_ other: SignGridStyle) -> SignGridStyle {
        SignGridStyle(bold: bold || other.bold, fill: fill || other.fill)
    }
}

/// One grid on the card. Every grid on a card has the card's rows and
/// columns; the card does the indexing.
struct SignGridPanel: Hashable, Codable {
    /// Row-major. Flat on purpose: Firestore can't store an array of arrays.
    fileprivate(set) var cells: [String]
    fileprivate(set) var rowStyles: [Int: SignGridStyle] = [:]
    fileprivate(set) var columnStyles: [Int: SignGridStyle] = [:]
    /// A cell's own style, keyed by its row-major index. It overrides the
    /// cell's row and column (user's call, 2026-11-09).
    fileprivate(set) var cellStyles: [Int: SignGridStyle] = [:]
    /// "RRGGBB", this grid's fill color (user's call, 2026-11-10). Nil on
    /// grids saved before then - they use the card's `fillColorHex`.
    fileprivate(set) var fillColorHex: String? = nil

    fileprivate init(cellCount: Int) {
        cells = Array(repeating: "", count: cellCount)
    }
}

/// A Batter & Runner card: one or more grids pieced together at the card's
/// print size.
struct SignGrid: Identifiable, Codable, Hashable {
    static let countRange: ClosedRange<Int> = 1...12
    static let gridCountRange: ClosedRange<Int> = 1...9
    static let maxCellLength = 24
    static let defaultSize = GridKeyPrintSize(widthInches: 3.5, heightInches: 2.75)
    static let defaultFillHex = "2F6DB5"

    let id: String
    var name: String
    private(set) var rows: Int
    private(set) var columns: Int
    private(set) var grids: [SignGridPanel]
    var widthInches: Double
    var heightInches: Double
    /// "RRGGBB": the fill of any grid without its own color (every grid
    /// on a card saved before 2026-11-10), and of new grids.
    var fillColorHex: String = SignGrid.defaultFillHex
    var archivedAt: Date? = nil

    init(id: String = UUID().uuidString, name: String = "", rows: Int = 4, columns: Int = 4,
         gridCount: Int = 1, size: GridKeyPrintSize = SignGrid.defaultSize, numbered: Bool = true) {
        self.id = id
        self.name = name
        self.rows = Self.clampCount(rows)
        self.columns = Self.clampCount(columns)
        let count = min(max(gridCount, Self.gridCountRange.lowerBound), Self.gridCountRange.upperBound)
        self.grids = Array(repeating: SignGridPanel(cellCount: self.rows * self.columns), count: count)
        self.widthInches = size.widthInches
        self.heightInches = size.heightInches
        if numbered { grids.indices.forEach { numberHeaders(in: $0) } }
    }

    static func clampCount(_ value: Int) -> Int {
        min(max(value, countRange.lowerBound), countRange.upperBound)
    }

    var isArchived: Bool { archivedAt != nil }
    var gridCount: Int { grids.count }

    var chosenSize: GridKeyPrintSize {
        GridKeyPrintSize(widthInches: widthInches, heightInches: heightInches)
    }

    /// The size this card prints at, or nil when the chosen size is outside
    /// the card limits. Never falls back to another size.
    var printSize: GridKeyPrintSize? {
        GridKeyProduct.printSize(productId: GridKeyProduct.signGridProductId, custom: chosenSize)
    }

    /// "2 grids · 4 x 4 cells · 3 1/2 x 2 3/4 in" (no grid count for one).
    var summary: String {
        let cells = "\(rows) x \(columns) cells · \(chosenSize.label)"
        return gridCount == 1 ? cells : "\(gridCount) grids · \(cells)"
    }

    /// How the grids sit on the card, picked from its size.
    var arrangement: SignGridArrangement {
        SignGridArrangement.bestFit(count: gridCount, cardSize: chosenSize.points, rows: rows, columns: columns)
    }

    // MARK: Grids

    /// More grids are added blank; fewer removes the last ones.
    mutating func setGridCount(_ count: Int) {
        let count = min(max(count, Self.gridCountRange.lowerBound), Self.gridCountRange.upperBound)
        if count < grids.count {
            grids.removeLast(grids.count - count)
        } else {
            let first = grids.count
            grids += Array(repeating: SignGridPanel(cellCount: rows * columns), count: count - grids.count)
            (first..<count).forEach { numberHeaders(in: $0) }
        }
    }

    /// True when going to `count` grids would remove a grid with something
    /// in it - the editor asks first. A grid with only its numbers is blank.
    func removesContent(settingGridCount count: Int) -> Bool {
        grids.indices.filter { $0 >= max(count, Self.gridCountRange.lowerBound) }
            .contains { !isBlank(grid: $0) }
    }

    /// Nothing typed but the numbers, nothing styled.
    func isBlank(grid: Int) -> Bool {
        guard hasGrid(grid) else { return true }
        let panel = grids[grid]
        let untouched = panel.cells.indices.allSatisfy { index in
            let text = panel.cells[index]
            return text.isEmpty || text == Self.headerLabel(row: index / columns, column: index % columns, grid: grid)
        }
        return untouched && panel.rowStyles.isEmpty && panel.columnStyles.isEmpty && panel.cellStyles.isEmpty
    }

    /// Where Return goes from `cell`: the next body cell, left to right,
    /// skipping the numbered top row and first column (2026-11-10 - typing
    /// into a number broke that row's codes on the calling card). From a
    /// number cell it steps into the body beside or below it. A card
    /// with one row or column has no body cells, so it steps through all.
    func cellAfter(_ cell: SignGridPosition) -> SignGridPosition {
        guard rows > 1, columns > 1 else {
            let next = (cell.row * columns + cell.column + 1) % (rows * columns)
            return SignGridPosition(row: next / columns, column: next % columns)
        }
        // From a number cell, into the body beside or below it.
        if cell.row == 0 || cell.column == 0 {
            return SignGridPosition(row: min(max(cell.row, 1), rows - 1), column: min(max(cell.column, 1), columns - 1))
        }
        if cell.column + 1 < columns { return SignGridPosition(row: cell.row, column: cell.column + 1) }
        return SignGridPosition(row: cell.row + 1 < rows ? cell.row + 1 : 1, column: 1)
    }

    // MARK: Numbers

    /// What a new cell starts with (user's pattern, 2026-11-10): the top
    /// row is the grid's digit + the column ("01 02 03" on grid 1, "11 12"
    /// on grid 2), the first column counts rows, the corner is blank.
    /// Columns past 9 aren't numbered (user's call). Editable like any text.
    static func headerLabel(row: Int, column: Int, grid: Int) -> String {
        switch (row, column) {
        case (0, 0): return ""
        case (0, 1...9): return "\(grid)\(column)"
        case (1..., 0): return "\(row)"
        default: return ""
        }
    }

    /// Numbers a grid's header cells. Only for cells that are new - never
    /// over something already there.
    /// `oldRows`/`oldColumns` are the size before a resize (0 for a new
    /// grid): only rows and columns past them are numbered.
    private mutating func numberHeaders(in grid: Int, keepingRows oldRows: Int = 0, columns oldColumns: Int = 0) {
        for column in oldColumns..<max(columns, oldColumns) {
            grids[grid].cells[column] = Self.headerLabel(row: 0, column: column, grid: grid)
        }
        for row in max(1, oldRows)..<max(rows, max(1, oldRows)) {
            grids[grid].cells[row * columns] = Self.headerLabel(row: row, column: 0, grid: grid)
        }
    }

    // MARK: Cells

    private func index(_ row: Int, _ column: Int) -> Int? {
        guard (0..<rows).contains(row), (0..<columns).contains(column) else { return nil }
        return row * columns + column
    }

    private func hasGrid(_ grid: Int) -> Bool { grids.indices.contains(grid) }

    func text(row: Int, column: Int, in grid: Int = 0) -> String {
        guard hasGrid(grid), let index = index(row, column) else { return "" }
        return grids[grid].cells[index]
    }

    mutating func setText(_ text: String, row: Int, column: Int, in grid: Int = 0) {
        guard hasGrid(grid), let index = index(row, column) else { return }
        grids[grid].cells[index] = String(text.prefix(Self.maxCellLength))
    }

    /// Changes every grid's cell count. Text and styles stay in their row
    /// and column; anything outside the new size is dropped.
    mutating func resize(rows newRows: Int, columns newColumns: Int) {
        let newRows = Self.clampCount(newRows)
        let newColumns = Self.clampCount(newColumns)
        grids = grids.map { old in
            var panel = SignGridPanel(cellCount: newRows * newColumns)
            for row in 0..<min(rows, newRows) {
                for column in 0..<min(columns, newColumns) {
                    let from = row * columns + column, to = row * newColumns + column
                    panel.cells[to] = old.cells[from]
                    panel.cellStyles[to] = old.cellStyles[from]
                }
            }
            panel.rowStyles = old.rowStyles.filter { $0.key < newRows }
            panel.columnStyles = old.columnStyles.filter { $0.key < newColumns }
            panel.fillColorHex = old.fillColorHex
            return panel
        }
        let (oldRows, oldColumns) = (rows, columns)
        rows = newRows
        columns = newColumns
        grids.indices.forEach { numberHeaders(in: $0, keepingRows: oldRows, columns: oldColumns) }
    }

    // MARK: Styles

    /// How a cell prints: its own style if it has one, otherwise its row's
    /// and its column's together.
    func style(row: Int, column: Int, in grid: Int = 0) -> SignGridStyle {
        guard hasGrid(grid), let index = index(row, column) else { return .normal }
        let panel = grids[grid]
        if let own = panel.cellStyles[index] { return own }
        return (panel.rowStyles[row] ?? .normal).union(panel.columnStyles[column] ?? .normal)
    }

    func rowStyle(_ row: Int, in grid: Int = 0) -> SignGridStyle {
        hasGrid(grid) ? grids[grid].rowStyles[row] ?? .normal : .normal
    }

    func columnStyle(_ column: Int, in grid: Int = 0) -> SignGridStyle {
        hasGrid(grid) ? grids[grid].columnStyles[column] ?? .normal : .normal
    }

    /// The cell's own style, nil when it follows its row and column.
    func cellOwnStyle(row: Int, column: Int, in grid: Int = 0) -> SignGridStyle? {
        guard hasGrid(grid), let index = index(row, column) else { return nil }
        return grids[grid].cellStyles[index]
    }

    /// Styles a row. The row's cells drop their own styles and follow it -
    /// the latest change wins.
    mutating func setRowStyle(_ style: SignGridStyle, row: Int, in grid: Int = 0) {
        guard hasGrid(grid), (0..<rows).contains(row) else { return }
        grids[grid].rowStyles[row] = style.isNormal ? nil : style
        for column in 0..<columns { grids[grid].cellStyles[row * columns + column] = nil }
    }

    /// Styles a column; its cells drop their own styles, like a row.
    mutating func setColumnStyle(_ style: SignGridStyle, column: Int, in grid: Int = 0) {
        guard hasGrid(grid), (0..<columns).contains(column) else { return }
        grids[grid].columnStyles[column] = style.isNormal ? nil : style
        for row in 0..<rows { grids[grid].cellStyles[row * columns + column] = nil }
    }

    /// Gives one cell its own style, overriding its row and column (normal
    /// included).
    mutating func setCellStyle(_ style: SignGridStyle, row: Int, column: Int, in grid: Int = 0) {
        guard hasGrid(grid), let index = index(row, column) else { return }
        grids[grid].cellStyles[index] = style
    }

    // MARK: Fill color

    /// A grid's fill, "RRGGBB": its own color, or the card's.
    func fillColorHex(in grid: Int) -> String {
        (hasGrid(grid) ? grids[grid].fillColorHex : nil) ?? fillColorHex
    }

    func fillColor(in grid: Int) -> Color { Color(SignGridColor.uiColor(hex: fillColorHex(in: grid))) }

    /// Black text on a light fill, white on a dark one.
    func textOnFill(in grid: Int) -> Color { SignGridColor.isLight(hex: fillColorHex(in: grid)) ? .black : .white }

    mutating func setFillColor(_ color: Color, in grid: Int) {
        setFillColorHex(SignGridColor.hex(UIColor(color)), in: grid)
    }

    mutating func setFillColorHex(_ hex: String, in grid: Int) {
        guard hasGrid(grid), SignGridColor.isValid(hex: hex) else { return }
        grids[grid].fillColorHex = hex.uppercased()
    }

    // MARK: Firestore

    /// `users/{uid}/signGrids/{id}`. Grids are an array of maps and styles
    /// arrays of maps - Firestore crashes on an array of arrays.
    var firestoreData: [String: Any] {
        func styleMap(_ style: SignGridStyle) -> [String: Any] { ["bold": style.bold, "fill": style.fill] }
        return [
            "name": name,
            "rows": rows,
            "columns": columns,
            "grids": grids.map { panel -> [String: Any] in
                var entry: [String: Any] = [
                    "cells": panel.cells,
                    "rowStyles": panel.rowStyles.sorted { $0.key < $1.key }
                        .map { styleMap($0.value).merging(["index": $0.key]) { $1 } },
                    "columnStyles": panel.columnStyles.sorted { $0.key < $1.key }
                        .map { styleMap($0.value).merging(["index": $0.key]) { $1 } },
                    "cellStyles": panel.cellStyles.sorted { $0.key < $1.key }
                        .map { styleMap($0.value).merging(["row": $0.key / columns, "column": $0.key % columns]) { $1 } }
                ]
                if let hex = panel.fillColorHex { entry["fillColor"] = hex }
                return entry
            },
            "fillColor": fillColorHex,
            "widthInches": widthInches,
            "heightInches": heightInches,
            "archivedAt": archivedAt.map { Timestamp(date: $0) } ?? NSNull()
        ]
    }

    init(id: String, firestoreData data: [String: Any]) {
        func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
        func double(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
        func style(_ entry: [String: Any]) -> SignGridStyle {
            SignGridStyle(bold: entry["bold"] as? Bool ?? false, fill: entry["fill"] as? Bool ?? false)
        }

        let saved = (data["grids"] as? [[String: Any]] ?? []).prefix(Self.gridCountRange.upperBound)
        self.init(
            id: id,
            name: data["name"] as? String ?? "",
            rows: int(data["rows"]) ?? 4,
            columns: int(data["columns"]) ?? 4,
            gridCount: max(saved.count, 1),
            size: GridKeyPrintSize(
                widthInches: double(data["widthInches"]) ?? Self.defaultSize.widthInches,
                heightInches: double(data["heightInches"]) ?? Self.defaultSize.heightInches
            ),
            numbered: false
        )
        if let hex = data["fillColor"] as? String, SignGridColor.isValid(hex: hex) {
            fillColorHex = hex.uppercased()
        }

        func load(grid: Int, cells: [String], rowStyles: [(Int, SignGridStyle)],
                  columnStyles: [(Int, SignGridStyle)], cellStyles: [(Int, Int, SignGridStyle)]) {
            for (index, text) in cells.prefix(rows * columns).enumerated() {
                setText(text, row: index / columns, column: index % columns, in: grid)
            }
            for (row, value) in rowStyles where !value.isNormal { setRowStyle(value, row: row, in: grid) }
            for (column, value) in columnStyles where !value.isNormal { setColumnStyle(value, column: column, in: grid) }
            for (row, column, value) in cellStyles { setCellStyle(value, row: row, column: column, in: grid) }
        }

        if saved.isEmpty {
            // Saved before cards held several grids: one grid, bold only.
            let bold = SignGridStyle(bold: true)
            load(grid: 0,
                 cells: data["cells"] as? [String] ?? [],
                 rowStyles: (data["boldRows"] as? [Any] ?? []).compactMap(int).map { ($0, bold) },
                 columnStyles: (data["boldColumns"] as? [Any] ?? []).compactMap(int).map { ($0, bold) },
                 cellStyles: (data["boldCells"] as? [[String: Any]] ?? []).compactMap { entry in
                     guard let row = int(entry["row"]), let column = int(entry["column"]) else { return nil }
                     return (row, column, bold)
                 })
        } else {
            for (grid, entry) in saved.enumerated() {
                func indexed(_ key: String) -> [(Int, SignGridStyle)] {
                    (entry[key] as? [[String: Any]] ?? []).compactMap { item in
                        int(item["index"]).map { ($0, style(item)) }
                    }
                }
                load(grid: grid,
                     cells: entry["cells"] as? [String] ?? [],
                     rowStyles: indexed("rowStyles"),
                     columnStyles: indexed("columnStyles"),
                     cellStyles: (entry["cellStyles"] as? [[String: Any]] ?? []).compactMap { item in
                         guard let row = int(item["row"]), let column = int(item["column"]) else { return nil }
                         return (row, column, style(item))
                     })
                if let hex = entry["fillColor"] as? String { setFillColorHex(hex, in: grid) }
            }
        }
        if let stamp = data["archivedAt"] as? Timestamp {
            archivedAt = stamp.dateValue()
        } else if let date = data["archivedAt"] as? Date {
            archivedAt = date
        }
    }
}

/// Common calls a cell can be filled with in one tap (user's list,
/// 2026-11-09). The label is what goes in the cell.
enum SignGridQuickFill {
    struct Item: Hashable {
        let meaning: String
        let label: String
    }

    struct Section: Hashable {
        let title: String
        let items: [Item]
    }

    static let sections: [Section] = [
        Section(title: "At Bat", items: [
            Item(meaning: "Take a pitch", label: "TAKE"),
            Item(meaning: "Swing away (green light)", label: "SWING"),
            Item(meaning: "Hit and run", label: "H&R"),
            Item(meaning: "Sacrifice bunt", label: "Sac B"),
            Item(meaning: "Fake bunt, swing away", label: "Fk Bt Sw"),
            Item(meaning: "Drag bunt", label: "DRAG"),
            Item(meaning: "Push bunt toward first", label: "P Bt 1"),
            Item(meaning: "Push bunt toward third", label: "P Bt 3"),
            Item(meaning: "Protect with two strikes", label: "PROT"),
            Item(meaning: "Hitter's choice, no call", label: "FREE")
        ]),
        Section(title: "On Base", items: [
            Item(meaning: "Steal", label: "STEAL"),
            Item(meaning: "Delayed steal", label: "DLY STL"),
            Item(meaning: "Fake bunt, steal", label: "FB STL"),
            Item(meaning: "Double steal", label: "DBL STL"),
            Item(meaning: "Halfway", label: "HALF")
        ]),
        Section(title: "Outfield Positioning", items: [
            Item(meaning: "Outfielders back", label: "OF BAC"),
            Item(meaning: "Outfielders in", label: "OF IN"),
            Item(meaning: "Outfielders normal depth", label: "OF NOR"),
            Item(meaning: "Shade left", label: "SHD L"),
            Item(meaning: "Shade right", label: "SHD R"),
            Item(meaning: "Throw home", label: "HOME")
        ]),
        Section(title: "Infield Positioning", items: [
            Item(meaning: "Infield in", label: "IF IN"),
            Item(meaning: "Infield back", label: "IF BAC"),
            Item(meaning: "Corners in", label: "COR IN"),
            Item(meaning: "Infield normal depth", label: "IF NOR")
        ]),
        Section(title: "Bunt Coverage and Plays", items: [
            Item(meaning: "Bunt coverage 1", label: "BC1"),
            Item(meaning: "Bunt coverage 2", label: "BC2"),
            Item(meaning: "Bunt coverage 3", label: "BC3"),
            Item(meaning: "Corners crash", label: "CRASH")
        ]),
        Section(title: "Modifiers", items: [
            Item(meaning: "Cancel (off)", label: "OFF")
        ])
    ]
}

enum SignGridColor {
    static func isValid(hex: String) -> Bool {
        hex.count == 6 && UInt32(hex, radix: 16) != nil
    }

    static func components(hex: String) -> (CGFloat, CGFloat, CGFloat) {
        let value = UInt32(isValid(hex: hex) ? hex : SignGrid.defaultFillHex, radix: 16) ?? 0
        return (CGFloat((value >> 16) & 0xFF) / 255, CGFloat((value >> 8) & 0xFF) / 255, CGFloat(value & 0xFF) / 255)
    }

    static func uiColor(hex: String) -> UIColor {
        let (r, g, b) = components(hex: hex)
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    static func hex(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return SignGrid.defaultFillHex }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    static func isLight(hex: String) -> Bool {
        let (r, g, b) = components(hex: hex)
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.6
    }
}

// MARK: - Layout

/// How many grids across and down. Picked so each cell comes out close to
/// the shape of the sample wristband card's (a little wider than tall),
/// with as few empty slots as possible.
struct SignGridArrangement: Equatable {
    let across: Int
    let down: Int

    static func bestFit(count: Int, cardSize: CGSize, rows: Int, columns: Int) -> SignGridArrangement {
        let count = max(count, 1)
        let targetCellAspect: CGFloat = 1.25
        var best = SignGridArrangement(across: 1, down: count)
        var bestScore = CGFloat.infinity
        for across in 1...count {
            let down = Int((Double(count) / Double(across)).rounded(.up))
            // Skip shapes with a whole empty row or column of grids.
            guard across * (down - 1) < count else { continue }
            let arrangement = SignGridArrangement(across: across, down: down)
            let layout = SignGridCardLayout(size: cardSize, arrangement: arrangement, count: count)
            let cell = CGSize(width: layout.gridSize.width / CGFloat(max(columns, 1)),
                              height: layout.gridSize.height / CGFloat(max(rows, 1)))
            guard cell.width > 0, cell.height > 0 else { continue }
            let empty = CGFloat(across * down - count)
            let score = abs(log(cell.width / cell.height / targetCellAspect)) + empty * 0.2
            if score < bestScore - 0.0001 {
                bestScore = score
                best = arrangement
            }
        }
        return best
    }
}

/// Where each grid sits on a card of `size` points. Everything is a
/// fraction of the card, so the wireframe and the 72-pt-per-inch PDF place
/// them the same way.
struct SignGridCardLayout {
    let size: CGSize
    let arrangement: SignGridArrangement
    let count: Int

    init(size: CGSize, arrangement: SignGridArrangement, count: Int) {
        self.size = size
        self.arrangement = arrangement
        self.count = count
    }

    init(grid: SignGrid, size: CGSize) {
        self.init(size: size, arrangement: grid.arrangement, count: grid.gridCount)
    }

    private var shortSide: CGFloat { min(size.width, size.height) }
    var inset: CGFloat { (shortSide * 0.04).rounded(.down) }
    var gap: CGFloat { max(1, shortSide * 0.025) }
    var lineWidth: CGFloat { max(0.5, shortSide * 0.005) }

    var contentRect: CGRect {
        CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
    }

    var gridSize: CGSize {
        let across = CGFloat(arrangement.across), down = CGFloat(arrangement.down)
        return CGSize(width: max(0, (contentRect.width - gap * (across - 1)) / across),
                      height: max(0, (contentRect.height - gap * (down - 1)) / down))
    }

    /// Grids fill left to right, then top to bottom.
    func gridRect(_ index: Int) -> CGRect {
        let column = index % arrangement.across, row = index / arrangement.across
        return CGRect(x: contentRect.minX + CGFloat(column) * (gridSize.width + gap),
                      y: contentRect.minY + CGFloat(row) * (gridSize.height + gap),
                      width: gridSize.width, height: gridSize.height)
    }
}

/// Where each cell sits inside one grid's rectangle.
struct SignGridLayout {
    let rect: CGRect
    let rows: Int
    let columns: Int

    var cellSize: CGSize {
        CGSize(width: rect.width / CGFloat(max(columns, 1)),
               height: rect.height / CGFloat(max(rows, 1)))
    }

    func frame(row: Int, column: Int) -> CGRect {
        CGRect(x: rect.minX + CGFloat(column) * cellSize.width,
               y: rect.minY + CGFloat(row) * cellSize.height,
               width: cellSize.width,
               height: cellSize.height)
    }

    /// One size for every cell; long text shrinks inside its own cell.
    var fontSize: CGFloat {
        max(1, min(cellSize.height * 0.5, cellSize.width * 0.38))
    }
}

/// One grid, filling `size`. The editor draws it big; the card draws each
/// of its grids with it.
struct SignGridPanelView: View {
    let grid: SignGrid
    let index: Int
    let size: CGSize
    let lineWidth: CGFloat
    var selected: SignGridPosition? = nil

    var body: some View {
        let layout = SignGridLayout(rect: CGRect(origin: .zero, size: size), rows: grid.rows, columns: grid.columns)
        ZStack(alignment: .topLeading) {
            Color.white

            ForEach(0..<grid.rows, id: \.self) { row in
                ForEach(0..<grid.columns, id: \.self) { column in
                    let frame = layout.frame(row: row, column: column)
                    let style = grid.style(row: row, column: column, in: index)
                    let padding = min(frame.width, frame.height) * 0.08
                    ZStack {
                        if style.fill { grid.fillColor(in: index) }
                        Text(grid.text(row: row, column: column, in: index))
                            .font(.system(size: layout.fontSize, weight: style.bold ? .bold : .regular))
                            .foregroundStyle(style.fill ? grid.textOnFill(in: index) : Color.black)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.25)
                            .padding(padding)
                    }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                }
            }

            Path { path in
                for row in 0...grid.rows {
                    let y = CGFloat(row) * layout.cellSize.height
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                for column in 0...grid.columns {
                    let x = CGFloat(column) * layout.cellSize.width
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
            }
            .stroke(Color.black, lineWidth: lineWidth)

            if let selected, selected.row < grid.rows, selected.column < grid.columns {
                // Inside the cell's lines, so it never runs past the cell.
                let frame = layout.frame(row: selected.row, column: selected.column)
                    .insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
                Rectangle()
                    .strokeBorder(Color.orange, lineWidth: 2)
                    .frame(width: max(0, frame.width), height: max(0, frame.height))
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .light)
    }
}

/// The printed card: every grid in its place. Also the store preview.
struct SignGridCardView: View {
    let grid: SignGrid
    let size: CGSize

    var body: some View {
        let layout = SignGridCardLayout(grid: grid, size: size)
        ZStack(alignment: .topLeading) {
            Color.white
            ForEach(0..<grid.gridCount, id: \.self) { index in
                let rect = layout.gridRect(index)
                SignGridPanelView(grid: grid, index: index, size: rect.size, lineWidth: layout.lineWidth)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Print

enum SignGridPrint {
    /// One PDF page exactly `size` big. Drawn as vectors, so the text stays
    /// sharp and can be read back out of the file.
    /// With `includingCallingCard`, a second page (US letter) carries the
    /// coach's calling card - store orders ship one (user's call, 2026-11-10).
    @MainActor
    static func writePDF(for grid: SignGrid, size: GridKeyPrintSize, to url: URL,
                         includingCallingCard: Bool = false) -> Bool {
        let points = size.points
        let renderer = ImageRenderer(content: SignGridCardView(grid: grid, size: points))
        renderer.proposedSize = ProposedViewSize(points)
        var mediaBox = CGRect(origin: .zero, size: points)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return false }
        var drew = false
        renderer.render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            drew = true
        }
        if drew, includingCallingCard {
            drew = SignGridCallingCardPrint.drawPage(for: grid, in: context)
        }
        context.closePDF()
        return drew
    }

    /// The fulfillment PDF for an order: the grid saved with the order, at
    /// the size saved with the order, then its calling card.
    @MainActor
    static func writeOrderPDF(snapshotJson: String, orderedSize: GridKeyPrintSize?, to url: URL) -> Bool {
        guard let size = GridKeyProduct.printSize(productId: GridKeyProduct.signGridProductId, custom: orderedSize),
              let data = snapshotJson.data(using: .utf8),
              let grid = try? JSONDecoder().decode(SignGrid.self, from: data) else { return false }
        return writePDF(for: grid, size: size, to: url, includingCallingCard: true)
    }

    static func fileURL(for grid: SignGrid) -> URL {
        let safeName = grid.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("PitchMark_\(safeName.isEmpty ? "Grid" : safeName).pdf")
    }
}

extension RetailCheckoutRequest {
    /// A Batter & Runner Grid order: prints the grid as it is now, at its
    /// own size. Nil when the grid's size can't be printed.
    static func signGrid(_ grid: SignGrid, storeTemplateName: String) -> RetailCheckoutRequest? {
        guard let size = grid.printSize else { return nil }
        return RetailCheckoutRequest(
            retailProductId: GridKeyProduct.signGridProductId,
            itemKind: "signGrid",
            templateId: grid.id,
            templateName: grid.name,
            storeTemplateName: storeTemplateName,
            templateSnapshotJson: snapshotJson(grid),
            printSize: size
        )
    }
}

// MARK: - Store

/// The signed-in coach's grids, live from `users/{uid}/signGrids`. A
/// listener rather than one-off loads, so a save shows at once and a reload
/// can't put back an older copy.
@MainActor
final class SignGridStore: ObservableObject {
    @Published private(set) var grids: [SignGrid] = []
    @Published private(set) var errorMessage: String? = nil

    private let inMemory: Bool
    private var uid: String? = nil
    private var listener: ListenerRegistration? = nil

    /// `inMemory` keeps everything local (UI tests).
    init(inMemory: Bool = false) {
        self.inMemory = inMemory
    }

    deinit {
        listener?.remove()
    }

    var activeGrids: [SignGrid] { grids.filter { !$0.isArchived } }
    var archivedGrids: [SignGrid] { grids.filter(\.isArchived) }

    func start(uid: String?) {
        guard !inMemory, uid != self.uid else { return }
        listener?.remove()
        listener = nil
        self.uid = uid
        grids = []
        guard let uid, !uid.isEmpty else { return }
        listener = collection(uid).addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    debugLog("❌ signGrids listener:", error.localizedDescription)
                    self.errorMessage = "Couldn't load grids. \(error.localizedDescription)"
                    return
                }
                self.errorMessage = nil
                self.grids = (snapshot?.documents ?? [])
                    .map { SignGrid(id: $0.documentID, firestoreData: $0.data()) }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }
    }

    func save(_ grid: SignGrid) {
        if let index = grids.firstIndex(where: { $0.id == grid.id }) {
            grids[index] = grid
        } else {
            grids.append(grid)
        }
        guard !inMemory, let uid else { return }
        var data = grid.firestoreData
        data["updatedAt"] = FieldValue.serverTimestamp()
        collection(uid).document(grid.id).setData(data) { [weak self] error in
            guard let error else { return }
            debugLog("❌ signGrid save:", error.localizedDescription)
            Task { @MainActor in self?.errorMessage = "Couldn't save the grid. \(error.localizedDescription)" }
        }
    }

    func setArchived(_ grid: SignGrid, _ archived: Bool) {
        var updated = grid
        updated.archivedAt = archived ? Date() : nil
        save(updated)
    }

    private func collection(_ uid: String) -> CollectionReference {
        Firestore.firestore().collection("users").document(uid).collection("signGrids")
    }
}
