import XCTest
import SwiftUI
import PDFKit
@testable import PitchMark

/// Printed grid keys: which size each product prints at, that the card
/// fits that size, that the PDF page is that size, and that the size rides
/// the order from checkout to the fulfillment queue.
@MainActor
final class GridKeyPrintTests: XCTestCase {

    // MARK: - Fixtures

    private func template(pitches count: Int, mode: PitchCodeMode) -> PitchTemplate {
        let names = (0..<count).map { "Pitch\($0)" }
        var grid: [[String]] = [[""] + names.map { String($0.prefix(2)) } + ["+"]]
        for row in 0..<3 {
            grid.append(["AB"] + (0..<count).map { "\(($0 + row) % 9 + 1)" } + [""])
        }
        var t = PitchTemplate(id: UUID(), name: "Test Key", pitches: names, codeAssignments: [])
        t.pitchGridHeaders = names.map { PitchHeader(pitch: $0, abbreviation: nil) }
        t.pitchGridValues = grid
        t.strikeTopRow = ["A", "B", "C"]
        t.strikeRows = [["", "", ""], ["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]
        t.ballsTopRow = ["D", "E", "F"]
        t.ballsRows = t.strikeRows
        t.pitchFirstColors = ["red", "blue"]
        t.locationFirstColors = ["green", "black", "yellow"]
        t.codeMode = mode
        t.strikeLocationCells = [["A", "B", "C"], ["D", "E", "F"], ["G", "H", "J"]]
        t.ballsLocationCells = t.strikeLocationCells
        return t
    }

    private let cardSizes: [GridKeyPrintSize] = [
        .init(widthInches: 3, heightInches: 2),
        .init(widthInches: 3.5, heightInches: 2.75),
        .init(widthInches: 5, heightInches: 3),
        .init(widthInches: 7, heightInches: 5),
        .init(widthInches: 4.25, heightInches: 2.5)
    ]

    /// Lowest pixel row (0 = top) holding anything darker than light gray.
    private func lowestInkRow(in image: UIImage) -> Int {
        guard let cg = image.cgImage else { return -1 }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in 0..<width where pixels[(y * width + x) * 4] < 200 {
                return y
            }
        }
        return -1
    }

    // MARK: - Which size each product prints at

    func testStandardProductsPrintAtTheirOwnSize() {
        XCTAssertEqual(GridKeyProduct.printSize(productId: "grid_5x3", custom: nil),
                       GridKeyPrintSize(widthInches: 5, heightInches: 3))
        XCTAssertEqual(GridKeyProduct.printSize(productId: "grid_3_5x2_75", custom: nil),
                       GridKeyPrintSize(widthInches: 3.5, heightInches: 2.75))
        // A custom size passed alongside a standard product is ignored.
        XCTAssertEqual(GridKeyProduct.printSize(productId: "grid_5x3",
                                                custom: .init(widthInches: 4, heightInches: 4)),
                       GridKeyPrintSize(widthInches: 5, heightInches: 3))
    }

    func testCustomProductPrintsAtTheChosenSize() {
        let chosen = GridKeyPrintSize(widthInches: 4.25, heightInches: 2.5)
        XCTAssertEqual(GridKeyProduct.printSize(productId: "grid_custom", custom: chosen), chosen)
        XCTAssertEqual(GridKeyProduct.printSize(productId: "grid_custom", custom: .init(widthInches: 3, heightInches: 2)),
                       GridKeyPrintSize(widthInches: 3, heightInches: 2))
        XCTAssertEqual(GridKeyProduct.printSize(productId: "grid_custom", custom: .init(widthInches: 7, heightInches: 5)),
                       GridKeyPrintSize(widthInches: 7, heightInches: 5))
    }

    /// The bug this guards: custom orders used to fall back to 5 x 3.
    func testInvalidOrMissingCustomSizeGivesNoSizeNeverAFallback() {
        let invalid: [GridKeyPrintSize?] = [
            nil,
            .init(widthInches: 2.75, heightInches: 3),   // too narrow
            .init(widthInches: 7.25, heightInches: 3),   // too wide
            .init(widthInches: 4, heightInches: 1.75),   // too short
            .init(widthInches: 4, heightInches: 5.25),   // too tall
            .init(widthInches: 4.1, heightInches: 3),    // off the quarter inch
            .init(widthInches: 4, heightInches: 2.6)
        ]
        for size in invalid {
            XCTAssertNil(GridKeyProduct.printSize(productId: "grid_custom", custom: size), "\(String(describing: size))")
        }
    }

    func testEveryPickerOptionIsAValidCustomSize() {
        for width in GridKeyProduct.customWidthOptions {
            for height in GridKeyProduct.customHeightOptions {
                XCTAssertTrue(GridKeyProduct.isValidCustom(.init(widthInches: width, heightInches: height)),
                              "\(width) x \(height)")
            }
        }
        XCTAssertEqual(GridKeyProduct.customWidthOptions.first, 3)
        XCTAssertEqual(GridKeyProduct.customWidthOptions.last, 7)
        XCTAssertEqual(GridKeyProduct.customHeightOptions.first, 2)
        XCTAssertEqual(GridKeyProduct.customHeightOptions.last, 5)
    }

    func testSizeLabels() {
        XCTAssertEqual(GridKeyPrintSize(widthInches: 5, heightInches: 3).label, "5 x 3 in")
        XCTAssertEqual(GridKeyPrintSize(widthInches: 4.25, heightInches: 2.5).label, "4 1/4 x 2 1/2 in")
        XCTAssertEqual(GridKeyPrintSize(widthInches: 3.5, heightInches: 2.75).label, "3 1/2 x 2 3/4 in")
    }

    // MARK: - The card fits, and the page is the size

    func testCardFitsEveryCardSizeAndPitchCount() {
        for mode in [PitchCodeMode.advanced, .normal] {
            for pitches in [3, 6, 9, 12] {
                let t = template(pitches: pitches, mode: mode)
                for size in cardSizes {
                    let target = size.points
                    let scale = GridKeyPrint.fitScale(for: t, on: target)
                    let rendered = GridKeyPrint.renderedSize(GridKeyPrint.view(for: t, scale: scale))
                    let context = "\(mode) \(pitches) pitches on \(size.label): \(rendered) in \(target)"
                    XCTAssertLessThanOrEqual(rendered.width, target.width + 0.01, context)
                    XCTAssertLessThanOrEqual(rendered.height, target.height + 0.01, context)
                    // Fit is to the limiting side, not shrunk to nothing.
                    XCTAssertGreaterThan(max(rendered.width / target.width, rendered.height / target.height), 0.95, context)
                }
            }
        }
    }

    func testPDFPageIsExactlyTheOrderedSize() throws {
        let t = template(pitches: 6, mode: .advanced)
        for size in cardSizes {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("GridKeyPrintTests-\(UUID()).pdf")
            defer { try? FileManager.default.removeItem(at: url) }
            XCTAssertTrue(GridKeyPrint.writePDF(for: t, size: size, to: url))
            let document = try XCTUnwrap(PDFDocument(url: url))
            XCTAssertEqual(document.pageCount, 1)
            let box = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
            XCTAssertEqual(box.width / 72, size.widthInches, accuracy: 0.001, size.label)
            XCTAssertEqual(box.height / 72, size.heightInches, accuracy: 0.001, size.label)
        }
    }

    // MARK: - The size rides the order

    func testOrderPrintSizeReadsTheSavedSize() {
        XCTAssertEqual(GridKeyProduct.orderPrintSize(["printWidthInches": 4.25, "printHeightInches": 2.5]),
                       GridKeyPrintSize(widthInches: 4.25, heightInches: 2.5))
        // Firestore hands whole numbers back as integers.
        XCTAssertEqual(GridKeyProduct.orderPrintSize(["printWidthInches": 5, "printHeightInches": 3]),
                       GridKeyPrintSize(widthInches: 5, heightInches: 3))
        XCTAssertNil(GridKeyProduct.orderPrintSize([:]))
        XCTAssertNil(GridKeyProduct.orderPrintSize(["printWidthInches": 4.25]))
        XCTAssertNil(GridKeyProduct.orderPrintSize(["printWidthInches": 0, "printHeightInches": 3]))
        XCTAssertNil(GridKeyProduct.orderPrintSize(["printWidthInches": NSNull(), "printHeightInches": NSNull()]))
    }

    func testCustomOrderWithoutASizeCannotBePrinted() {
        XCTAssertNotNil(GridKeyProduct.printSizeProblem(productId: "grid_custom", orderedSize: nil))
        XCTAssertNil(GridKeyProduct.printSizeProblem(productId: "grid_custom",
                                                     orderedSize: .init(widthInches: 4.25, heightInches: 2.5)))
        XCTAssertNil(GridKeyProduct.printSizeProblem(productId: "grid_5x3", orderedSize: nil))
        XCTAssertNil(GridKeyProduct.printSizeProblem(productId: "sheet_8_5x11", orderedSize: nil))
    }

    private func checkoutRequest(size: GridKeyPrintSize?) -> RetailCheckoutRequest {
        RetailCheckoutRequest(
            retailProductId: "grid_custom", itemKind: "gridKey", templateId: "T1",
            templateName: "Test Key", storeTemplateName: "Custom", templateSnapshotJson: "{}",
            printSize: size
        )
    }

    func testCheckoutPayloadCarriesTheSize() {
        let payload = checkoutRequest(size: .init(widthInches: 4.25, heightInches: 2.5)).payload(idempotencyKey: "pm_key")
        XCTAssertEqual(payload["printWidthInches"] as? Double, 4.25)
        XCTAssertEqual(payload["printHeightInches"] as? Double, 2.5)
        XCTAssertEqual(payload["retailProductId"] as? String, "grid_custom")
        XCTAssertEqual(payload["idempotencyKey"] as? String, "pm_key")

        let sheet = checkoutRequest(size: nil).payload(idempotencyKey: "pm_key")
        XCTAssertNil(sheet["printWidthInches"])
        XCTAssertNil(sheet["printHeightInches"])
    }

    func testChangingTheSizeIsANewCheckout() {
        let first = checkoutRequest(size: .init(widthInches: 4.25, heightInches: 2.5))
        let same = checkoutRequest(size: .init(widthInches: 4.25, heightInches: 2.5))
        let resized = checkoutRequest(size: .init(widthInches: 4.5, heightInches: 2.5))
        XCTAssertEqual(first.fingerprint, same.fingerprint)
        XCTAssertNotEqual(first.fingerprint, resized.fingerprint)
    }

    // MARK: - 8.5 x 11 sheet

    func testLetterSheetStaysOffTheBottomMargin() throws {
        let page = CGSize(width: 612, height: 792)
        let bottomMarginTop = 792 - 24   // the sheet's 24pt page padding
        for pitches in [3, 6, 8, 12, 16] {
            let t = template(pitches: pitches, mode: .advanced)
            for (title, locations) in [("Strikes", strikePrintableLocations), ("Balls", ballPrintableLocations)] {
                let image = try XCTUnwrap(
                    PrintableLocationSheetView(template: t, title: title, locations: locations)
                        .renderAsPNG(size: page, scale: 1.0)
                )
                let lowest = lowestInkRow(in: image)
                XCTAssertGreaterThan(lowest, 0, "\(title), \(pitches) pitches: nothing drawn")
                // One pixel of grace for the half-point cell stroke.
                XCTAssertLessThanOrEqual(lowest, bottomMarginTop, "\(title), \(pitches) pitches")
            }
        }
    }
}
