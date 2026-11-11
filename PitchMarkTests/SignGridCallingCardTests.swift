import XCTest
import PDFKit
import SwiftUI
@testable import PitchMark

/// The coach's calling card (approved 2026-11-10): each number is the
/// cell's column header + row header, every place a call appears is
/// listed, calls run A to Z, and it prints on a letter page (alone, and as
/// page 2 of a store order).
@MainActor
final class SignGridCallingCardTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CallingCardTests-\(UUID()).pdf")
    }

    private func codes(_ card: SignGridCallingCard, _ label: String) -> [String]? {
        card.calls.first { $0.label == label }?.codes
    }

    // 1. Column header + row header, every place, none missed.

    func testANumberIsTheColumnHeaderThenTheRowHeader() {
        var grid = SignGrid(name: "Signs", rows: 4, columns: 4, gridCount: 2)
        grid.setText("STEAL", row: 1, column: 1, in: 0)   // 01 + 1
        grid.setText("STEAL", row: 2, column: 3, in: 0)   // 03 + 2
        grid.setText("STEAL", row: 3, column: 2, in: 1)   // 12 + 3
        grid.setText("H&R", row: 2, column: 3, in: 1)     // 13 + 2
        let card = SignGridCallingCard(grid: grid)
        XCTAssertEqual(card.title, "Signs")
        XCTAssertEqual(codes(card, "STEAL"), ["011", "032", "123"])
        XCTAssertEqual(codes(card, "H&R"), ["132"])
        XCTAssertEqual(card.calls.count, 2)
    }

    func testEveryCellOfEveryGridIsListedOnce() {
        let labels = ["TAKE", "SWING", "H&R", "STEAL"]
        var grid = SignGrid(rows: 6, columns: 6, gridCount: 3)
        var expected: [String: Set<String>] = [:]
        var n = 0
        for g in 0..<3 {
            for r in 1..<6 {
                for c in 1..<6 {
                    let label = labels[n % labels.count]
                    n += 1
                    grid.setText(label, row: r, column: c, in: g)
                    expected[label, default: []].insert("\(g)\(c)\(r)")
                }
            }
        }
        let card = SignGridCallingCard(grid: grid)
        XCTAssertEqual(card.calls.reduce(0) { $0 + $1.codes.count }, 3 * 5 * 5, "one number per cell")
        for call in card.calls {
            XCTAssertEqual(Set(call.codes), expected[call.label], call.label)
            XCTAssertEqual(call.codes.count, Set(call.codes).count, "\(call.label) repeats a number")
        }
        XCTAssertEqual(card.unnumberedCount, 0)
    }

    // 2. Headers and blanks are never calls; no header number, no code.

    func testHeadersAndBlankCellsAreNeverCallsAndUnnumberedCellsAreLeftOut() {
        var grid = SignGrid(rows: 4, columns: 4)
        grid.setText("CORNER", row: 0, column: 0)
        grid.setText("   ", row: 1, column: 1)
        grid.setText("BUNT", row: 1, column: 2)
        grid.setText("", row: 2, column: 0)               // row 2 loses its number
        grid.setText("STEAL", row: 2, column: 1)
        grid.setText("", row: 0, column: 3)               // column 3 loses its number
        grid.setText("HOME", row: 3, column: 3)
        let card = SignGridCallingCard(grid: grid)
        XCTAssertEqual(card.calls.map(\.label), ["BUNT"], "headers, blanks and unnumbered cells aren't listed")
        XCTAssertEqual(codes(card, "BUNT"), ["021"])
        XCTAssertFalse(card.calls.contains { $0.label == "01" || $0.label == "1" }, "header numbers are not calls")
        XCTAssertEqual(card.unnumberedCount, 2)
        XCTAssertTrue(SignGridCallingCard(grid: SignGrid()).isEmpty, "a new card has no calls")
    }

    // 3. Edited headers change the numbers.

    func testEditedHeadersChangeTheNumbers() {
        var grid = SignGrid(rows: 3, columns: 3)
        grid.setText("STEAL", row: 2, column: 1)
        XCTAssertEqual(codes(SignGridCallingCard(grid: grid), "STEAL"), ["012"])
        grid.setText("7", row: 0, column: 1)
        grid.setText("4", row: 2, column: 0)
        XCTAssertEqual(codes(SignGridCallingCard(grid: grid), "STEAL"), ["74"])
    }

    // 4. A to Z (user's call), numbers ascending.

    func testCallsRunAToZAndNumbersAscend() {
        var grid = SignGrid(rows: 12, columns: 12, gridCount: 2)
        grid.setText("steal", row: 1, column: 1)
        grid.setText("H&R", row: 1, column: 2)
        grid.setText("bunt 2", row: 1, column: 3)
        grid.setText("Bunt", row: 1, column: 4)
        grid.setText("Bunt", row: 11, column: 9, in: 1)   // 19 + 11
        grid.setText("Bunt", row: 2, column: 4)           // 04 + 2
        let card = SignGridCallingCard(grid: grid)
        XCTAssertEqual(card.calls.map(\.label), ["Bunt", "bunt 2", "H&R", "steal"])
        XCTAssertEqual(codes(card, "Bunt"), ["041", "042", "1911"])
    }

    // Return skips the numbered row and column (approved 2026-11-10).

    func testReturnWalksTheBodyCellsAndSkipsTheNumbers() {
        let grid = SignGrid(rows: 3, columns: 4)
        var cell = SignGridPosition(row: 1, column: 1)
        var visited: [SignGridPosition] = []
        for _ in 0..<7 {
            cell = grid.cellAfter(cell)
            visited.append(cell)
        }
        XCTAssertEqual(visited.map { "\($0.row).\($0.column)" },
                       ["1.2", "1.3", "2.1", "2.2", "2.3", "1.1", "1.2"],
                       "across, wrap to column 1 of the next row, then back to row 1")
        XCTAssertFalse(visited.contains { $0.row == 0 || $0.column == 0 }, "never a number cell")
        XCTAssertEqual(grid.cellAfter(.init(row: 0, column: 0)), .init(row: 1, column: 1), "corner into the body")
        XCTAssertEqual(grid.cellAfter(.init(row: 0, column: 2)), .init(row: 1, column: 2), "a column number to the cell below")
        XCTAssertEqual(grid.cellAfter(.init(row: 2, column: 0)), .init(row: 2, column: 1), "a row number to the cell beside")

        // No body cells: every cell in turn, as before.
        let oneRow = SignGrid(rows: 1, columns: 3)
        XCTAssertEqual(oneRow.cellAfter(.init(row: 0, column: 0)), .init(row: 0, column: 1))
        XCTAssertEqual(oneRow.cellAfter(.init(row: 0, column: 2)), .init(row: 0, column: 0))
        let oneColumn = SignGrid(rows: 3, columns: 1)
        XCTAssertEqual(oneColumn.cellAfter(.init(row: 0, column: 0)), .init(row: 1, column: 0))
        XCTAssertEqual(oneColumn.cellAfter(.init(row: 2, column: 0)), .init(row: 0, column: 0))
    }

    // 5. The PDF: one letter page with every call and number; and page 2
    // of a store order.

    func testTheCallingCardPrintsEveryCallAndNumberOnALetterPage() throws {
        var grid = SignGrid(name: "Signs", rows: 5, columns: 5, gridCount: 3)
        for (g, label) in ["TAKE", "SWING", "Fk Bt Sw"].enumerated() {
            grid.setText(label, row: 2, column: 3, in: g)
            grid.setText(label, row: 4, column: 1, in: (g + 1) % 3)
        }
        let card = SignGridCallingCard(grid: grid)
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(SignGridCallingCardPrint.writePDF(for: grid, to: url))
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(document.pageCount, 1)
        let box = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(box.size, CGSize(width: 612, height: 792), "8 1/2 x 11 in")
        let text = try XCTUnwrap(document.string)
        for call in card.calls {
            XCTAssertTrue(text.contains(call.label), "\(call.label) missing")
            for code in call.codes { XCTAssertTrue(text.contains(code), "\(call.label) \(code) missing") }
        }
    }

    func testABigCardStillFitsOnePage() throws {
        // Every numbered cell different: 9 grids x 11 rows x 9 columns (past 9 isn't numbered).
        var grid = SignGrid(name: "Everything", rows: 12, columns: 10, gridCount: 9)
        for g in 0..<9 { for r in 1..<12 { for c in 1..<10 { grid.setText("C\(g)-\(r)-\(c)", row: r, column: c, in: g) } } }
        XCTAssertEqual(SignGridCallingCard(grid: grid).calls.count, 891)
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(SignGridCallingCardPrint.writePDF(for: grid, to: url))
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(document.pageCount, 1)
        let page = try XCTUnwrap(document.page(at: 0))
        let last = try XCTUnwrap(page.selection(for: NSRange(location: 0, length: page.numberOfCharacters))?.string)
        XCTAssertTrue(last.contains("C8-11-9"), "the last call made it onto the page")
        // Everything drawn sits inside the page.
        let bounds = page.bounds(for: .mediaBox)
        for i in stride(from: 0, to: page.numberOfCharacters, by: 97) {
            let r = page.characterBounds(at: i)
            guard r.width > 0 else { continue }
            XCTAssertTrue(bounds.contains(r), "character \(i) at \(r) is off the page")
        }
    }

    // MARK: Pocket size and the waterproof cards (approved 2026-11-10)

    private func sampleGrid() -> SignGrid {
        var grid = SignGrid(name: "Signs", rows: 5, columns: 5, gridCount: 3)
        for (g, label) in ["TAKE", "SWING", "Fk Bt Sw", "STEAL"].enumerated() {
            grid.setText(label, row: 2, column: 3, in: g % 3)
            grid.setText(label, row: 4, column: (g % 4) + 1, in: (g + 1) % 3)
        }
        return grid
    }

    func testThePocketCardIsAQuarterSheetWithEveryCallAndNumber() throws {
        let grid = sampleGrid()
        let card = SignGridCallingCard(grid: grid)
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(SignGridCallingCardPrint.writePDF(for: grid, format: .pocket, to: url))
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(document.pageCount, 1)
        let box = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(box.width / 72, 4.25, accuracy: 0.001)
        XCTAssertEqual(box.height / 72, 5.5, accuracy: 0.001)
        let text = try XCTUnwrap(document.string)
        for call in card.calls {
            XCTAssertTrue(text.contains(call.label), "\(call.label) missing")
            for code in call.codes { XCTAssertTrue(text.contains(code), "\(call.label) \(code) missing") }
        }
        // The full page is still a full page.
        let full = tempURL()
        defer { try? FileManager.default.removeItem(at: full) }
        XCTAssertTrue(SignGridCallingCardPrint.writePDF(for: grid, format: .fullPage, to: full))
        XCTAssertEqual(PDFDocument(url: full)?.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 612, height: 792))
    }

    func testABigCardStillFitsThePocketCard() throws {
        var grid = SignGrid(name: "Everything", rows: 12, columns: 10, gridCount: 9)
        for g in 0..<9 { for r in 1..<12 { for c in 1..<10 { grid.setText("C\(g)-\(r)-\(c)", row: r, column: c, in: g) } } }
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(SignGridCallingCardPrint.writePDF(for: grid, format: .pocket, to: url))
        let page = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
        XCTAssertTrue(page.string?.contains("C8-11-9") == true, "the last call made it onto the card")
        let bounds = page.bounds(for: .mediaBox)
        for i in stride(from: 0, to: page.numberOfCharacters, by: 97) {
            let r = page.characterBounds(at: i)
            guard r.width > 0 else { continue }
            XCTAssertTrue(bounds.contains(r), "character \(i) at \(r) is off the card")
        }
    }

    private func bigGrid() -> SignGrid {
        var big = SignGrid(name: "Big", rows: 7, columns: 7, gridCount: 2)
        let labels = SignGridQuickFill.sections.flatMap { $0.items.map(\.label) }.prefix(19)
        var generator = SystemRandomNumberGenerator()
        big.randomFill(with: Array(labels), using: &generator)
        return big
    }

    /// The store's pocket preview lays out like the print, and the shrunk
    /// card fits inside the pocket card's margins.
    func testThePreviewShrinksLikeThePrint() throws {
        let format = SignGridCallingCardPrint.Format.pocket
        let inner = SignGridCallingCardPrint.innerSize(format)
        for (name, grid) in [("small", sampleGrid()), ("big", bigGrid())] {
            let card = SignGridCallingCard(grid: grid)
            let layout = SignGridCallingCardPrint.layout(for: card, format: format)
            let natural = SignGridCallingCardPrint.contentSize(of: card, columns: layout.columns, width: layout.width)
            XCTAssertLessThanOrEqual(natural.height * layout.fit, inner.height + 0.5, "\(name) runs past the bottom margin")
            XCTAssertEqual(layout.width * layout.fit, inner.width, accuracy: 0.5, "\(name) is the card's full width")
            XCTAssertEqual(SignGridCallingCardPrint.fitScale(for: card, format: format), layout.fit, "\(name): one answer")

            // The worked-out height is the height it really draws at.
            let renderer = ImageRenderer(content: SignGridCallingCardView(card: card, columns: layout.columns, width: layout.width)
                .frame(width: layout.width, alignment: .topLeading))
            renderer.proposedSize = ProposedViewSize(width: layout.width, height: nil)
            var drawn = CGSize.zero
            renderer.render { size, _ in drawn = size }
            XCTAssertEqual(drawn.height, natural.height, accuracy: 3, "\(name): worked-out height is off")

            // The printed page puts every character inside the same margins.
            let url = tempURL()
            defer { try? FileManager.default.removeItem(at: url) }
            XCTAssertTrue(SignGridCallingCardPrint.writePDF(for: grid, format: format, to: url))
            let page = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
            // A PDF character box carries a little line spacing above the
            // letters, so allow a few points into the 18 pt margin.
            let margins = CGRect(origin: .zero, size: format.size).insetBy(dx: format.margin - 4, dy: format.margin - 4)
            for i in 0..<page.numberOfCharacters {
                let r = page.characterBounds(at: i)
                guard r.width > 0 else { continue }
                XCTAssertTrue(margins.contains(r), "\(name): character \(i) at \(r) is outside the margins")
            }
        }
        XCTAssertLessThan(SignGridCallingCardPrint.layout(for: SignGridCallingCard(grid: bigGrid()), format: format).fit, 1,
                          "a card this big has to shrink")
        XCTAssertEqual(SignGridCallingCardPrint.layout(for: SignGridCallingCard(grid: sampleGrid()), format: .fullPage),
                       .init(columns: 4, width: SignGridCallingCardPrint.innerSize(.fullPage).width, fit: 1),
                       "a small card prints full size, at the page's own columns")
    }

    /// A big card fills the card's width - no blank side - and every box
    /// on it is the same height (approved 2026-11-10).
    func testABigPocketCardFillsTheWidthWithEvenBoxes() throws {
        let grid = bigGrid()
        let card = SignGridCallingCard(grid: grid)
        let format = SignGridCallingCardPrint.Format.pocket
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(SignGridCallingCardPrint.writePDF(for: grid, format: format, to: url))
        let document = try XCTUnwrap(PDFDocument(url: url))
        let page = try XCTUnwrap(document.page(at: 0))
        let text = try XCTUnwrap(page.string)
        for call in card.calls {
            for code in call.codes { XCTAssertTrue(text.contains(code), "\(call.label) \(code) lost") }
        }

        // Text reaches across the card, not just its left half.
        var right: CGFloat = 0
        for i in 0..<page.numberOfCharacters { right = max(right, page.characterBounds(at: i).maxX) }
        let innerRight = format.size.width - format.margin
        XCTAssertGreaterThan(right, innerRight - 0.15 * SignGridCallingCardPrint.innerSize(format).width,
                             "text stops at \(right) of \(innerRight)")

        // Every row is the same distance apart: same-height boxes. Each
        // row is found by its first box's first number (numbers are unique).
        var bandTops: [CGFloat] = []
        let layout = SignGridCallingCardPrint.layout(for: card, format: format)
        for (index, call) in card.calls.enumerated() where index % layout.columns == 0 {
            let code = try XCTUnwrap(call.codes.first)
            let found = try XCTUnwrap(document.findString(code, withOptions: []).first, "\(code) not found")
            bandTops.append((found.bounds(for: page).midY * 2).rounded() / 2)
        }
        let steps = zip(bandTops, bandTops.dropFirst()).map { $0 - $1 }
        XCTAssertGreaterThan(steps.count, 1)
        for step in steps { XCTAssertEqual(step, steps[0], accuracy: 1, "rows aren't even: \(bandTops)") }
    }

    func testEveryBoxHasTheSameNumbersPerLineAndLineCount() {
        let card = SignGridCallingCard(grid: bigGrid())
        let perLine = 3
        let lines = SignGridCallingCardView.lineCount(for: card, perLine: perLine)
        for call in card.calls {
            let boxLines = SignGridCallingCardView.codeLines(call.codes, perLine: perLine, lines: lines)
            XCTAssertEqual(boxLines.count, lines, "\(call.label) box is a different height")
            let filled = boxLines.filter { $0.trimmingCharacters(in: .whitespaces).isEmpty == false }
            XCTAssertTrue(filled.allSatisfy { $0.split(separator: " ").count <= perLine })
            XCTAssertEqual(filled.dropLast().allSatisfy { $0.split(separator: " ").count == perLine }, true,
                           "\(call.label): only the last line may be short")
            XCTAssertEqual(filled.flatMap { $0.split(separator: " ").map(String.init) }, call.codes, "\(call.label) lost a number")
        }
        XCTAssertEqual(SignGridCallingCardView.codeLines([], perLine: 3, lines: 2), [" ", " "])
        XCTAssertGreaterThanOrEqual(SignGridCallingCardView.codesPerLine(boxWidth: 100, codeSize: 16, padding: 5), 2)
        XCTAssertEqual(SignGridCallingCardView.codesPerLine(boxWidth: 10, codeSize: 16, padding: 5), 1, "never zero")
    }

    func testTheWaterproofOrderIsEightDollarsAndCarriesTheDesign() throws {
        XCTAssertEqual(SignGridCallingCardPrint.waterproofPrice, 8)
        let grid = sampleGrid()
        let request = RetailCheckoutRequest.waterproofCallingCards(grid, storeTemplateName: "Waterproof Calling Cards")
        let payload = request.payload(idempotencyKey: "k")
        XCTAssertEqual(payload["retailProductId"] as? String, "calling_card_waterproof")
        XCTAssertEqual(payload["itemKind"] as? String, "signGrid")
        XCTAssertNil(payload["printWidthInches"], "always pocket cards - no size to send")
        let json = try XCTUnwrap(payload["templateSnapshotJson"] as? String)
        XCTAssertEqual(try JSONDecoder().decode(SignGrid.self, from: Data(json.utf8)), grid)

        let same = RetailCheckoutRequest.waterproofCallingCards(grid, storeTemplateName: "Waterproof Calling Cards")
        XCTAssertEqual(request.fingerprint, same.fingerprint)
        var edited = grid
        edited.setText("BUNT", row: 1, column: 1)
        XCTAssertNotEqual(request.fingerprint,
                          RetailCheckoutRequest.waterproofCallingCards(edited, storeTemplateName: "Waterproof Calling Cards").fingerprint,
                          "an edited card ordered again gets a new checkout")
        XCTAssertNotEqual(request.fingerprint,
                          try XCTUnwrap(RetailCheckoutRequest.signGrid(grid, storeTemplateName: "Waterproof Calling Cards")).fingerprint,
                          "not the same checkout as the grid cards")
    }

    func testTheWaterproofSheetHasTheCardFourTimesEachInItsOwnQuarter() throws {
        let grid = sampleGrid()
        let card = SignGridCallingCard(grid: grid)
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(SignGridCallingCardPrint.writeWaterproofOrderPDF(snapshotJson: RetailCheckoutRequest.snapshotJson(grid), to: url))
        XCTAssertFalse(SignGridCallingCardPrint.writeWaterproofOrderPDF(snapshotJson: "not json", to: tempURL()))
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(document.pageCount, 1)
        let page = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).size, CGSize(width: 612, height: 792), "one 8 1/2 x 11 sheet")

        let margin = SignGridCallingCardPrint.Format.pocket.margin
        // PDF space is bottom-up; the quarters are top-down.
        let quarters = SignGridCallingCardPrint.sheetQuarters.map {
            CGRect(x: $0.minX, y: 792 - $0.maxY, width: $0.width, height: $0.height)
        }
        XCTAssertEqual(quarters.count, 4)
        for (index, quarter) in quarters.enumerated() {
            let text = try XCTUnwrap(page.selection(for: quarter)?.string, "quarter \(index) is empty")
            for call in card.calls {
                XCTAssertTrue(text.contains(call.label), "quarter \(index) is missing \(call.label)")
                for code in call.codes { XCTAssertTrue(text.contains(code), "quarter \(index) is missing \(code)") }
            }
        }
        // Every character sits inside one quarter's margins - nothing runs
        // across a cut.
        var perQuarter = [Int](repeating: 0, count: 4)
        for i in 0..<page.numberOfCharacters {
            let r = page.characterBounds(at: i)
            guard r.width > 0, r.height > 0 else { continue }
            let home = quarters.firstIndex { $0.insetBy(dx: margin - 1, dy: margin - 1).contains(r) }
            XCTAssertNotNil(home, "character \(i) at \(r) crosses a cut or a margin")
            if let home { perQuarter[home] += 1 }
        }
        XCTAssertEqual(Set(perQuarter).count, 1, "the same card in each quarter: \(perQuarter)")
        XCTAssertGreaterThan(perQuarter[0], 0)
    }

    func testAStoreOrderPrintsTheCardThenItsCallingCard() throws {
        var grid = SignGrid(name: "Signs", rows: 4, columns: 4, gridCount: 2, size: .init(widthInches: 5, heightInches: 3))
        grid.setText("SQUEEZE", row: 3, column: 2, in: 1)
        let json = RetailCheckoutRequest.snapshotJson(grid)
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(SignGridPrint.writeOrderPDF(snapshotJson: json, orderedSize: .init(widthInches: 5, heightInches: 3), to: url))
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(document.pageCount, 2)
        let cardBox = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(cardBox.size, CGSize(width: 360, height: 216), "the card stays its own size")
        let callingPage = try XCTUnwrap(document.page(at: 1))
        XCTAssertEqual(callingPage.bounds(for: .mediaBox).size, CGSize(width: 612, height: 792))
        let text = try XCTUnwrap(callingPage.string)
        XCTAssertTrue(text.contains("SQUEEZE") && text.contains("123"), "page 2 is the calling card")

        // The free PDF of the card is still just the card.
        let free = tempURL()
        defer { try? FileManager.default.removeItem(at: free) }
        XCTAssertTrue(SignGridPrint.writePDF(for: grid, size: .init(widthInches: 5, heightInches: 3), to: free))
        XCTAssertEqual(PDFDocument(url: free)?.pageCount, 1)
    }
}
