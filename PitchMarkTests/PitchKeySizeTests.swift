import XCTest
import PDFKit
@testable import PitchMark

/// A pitching key's own print size (approved 2026-11-10): chosen in its
/// editor, saved with it, and what the store previews, sells and prints -
/// no set sizes to pick.
@MainActor
final class PitchKeySizeTests: XCTestCase {

    private func key(_ size: GridKeyPrintSize? = nil) -> PitchTemplate {
        let names = ["Fastball", "Curve", "Change"]
        var t = PitchTemplate(id: UUID(), name: "Key", pitches: names, codeAssignments: [])
        t.pitchGridHeaders = names.map { PitchHeader(pitch: $0, abbreviation: nil) }
        t.pitchGridValues = [[""] + names.map { String($0.prefix(2)) } + ["+"]]
            + (0..<3).map { row in ["AB"] + (0..<3).map { "\(($0 + row) % 9 + 1)" } + [""] }
        t.strikeTopRow = ["A", "B", "C"]
        t.strikeRows = [["", "", ""], ["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]
        t.ballsTopRow = ["D", "E", "F"]
        t.ballsRows = t.strikeRows
        if let size { t.setPrintSize(size) }
        return t
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PitchKeySize-\(UUID()).pdf")
    }

    func testANewOrOlderKeyIsFiveByThreeAndOnlyValidSizesCanBeChosen() {
        var t = key()
        XCTAssertNil(t.printWidthInches, "nothing saved yet")
        XCTAssertEqual(t.chosenPrintSize, GridKeyPrintSize(widthInches: 5, heightInches: 3))
        XCTAssertEqual(t.printSize, GridKeyPrintSize(widthInches: 5, heightInches: 3))

        t.setPrintSize(.init(widthInches: 4.25, heightInches: 2.5))
        XCTAssertEqual(t.printSize, GridKeyPrintSize(widthInches: 4.25, heightInches: 2.5))
        for bad in [GridKeyPrintSize(widthInches: 7.25, heightInches: 3), .init(widthInches: 2.75, heightInches: 3),
                    .init(widthInches: 4, heightInches: 5.25), .init(widthInches: 4, heightInches: 1.75),
                    .init(widthInches: 4.1, heightInches: 3)] {
            t.setPrintSize(bad)
            XCTAssertEqual(t.chosenPrintSize, GridKeyPrintSize(widthInches: 4.25, heightInches: 2.5), "\(bad) was accepted")
        }
        // Every choice the editor offers is one a key can print at.
        for w in GridKeyProduct.customWidthOptions {
            for h in GridKeyProduct.customHeightOptions {
                XCTAssertNotNil(key(.init(widthInches: w, heightInches: h)).printSize, "\(w) x \(h)")
            }
        }
    }

    func testTheSizeSavesAndLoads() throws {
        let t = key(.init(widthInches: 6.5, heightInches: 4.75))
        let fields = t.printSizeFirestoreFields
        XCTAssertEqual(fields["printWidthInches"] as? Double, 6.5)
        XCTAssertEqual(fields["printHeightInches"] as? Double, 4.75)
        XCTAssertEqual(PitchTemplate.savedPrintSize(fields), GridKeyPrintSize(widthInches: 6.5, heightInches: 4.75))
        XCTAssertNil(PitchTemplate.savedPrintSize([:]), "an older key has none - the default applies")
        XCTAssertNil(PitchTemplate.savedPrintSize(["printWidthInches": 9, "printHeightInches": 3]), "a bad saved size is ignored")
        XCTAssertNil(PitchTemplate.savedPrintSize(["printWidthInches": 4]))
        XCTAssertEqual(key().printSizeFirestoreFields["printWidthInches"] as? Double, 5, "a new key saves the default")

        // The copy sent with an order keeps it, and an order from before
        // keys had sizes still decodes (at the default).
        let json = RetailCheckoutRequest.snapshotJson(t)
        XCTAssertEqual(try JSONDecoder().decode(PitchTemplate.self, from: Data(json.utf8)).printSize,
                       GridKeyPrintSize(widthInches: 6.5, heightInches: 4.75))
        let old = RetailCheckoutRequest.snapshotJson(key())
        XCTAssertFalse(old.contains("printWidthInches"))
        XCTAssertEqual(try JSONDecoder().decode(PitchTemplate.self, from: Data(old.utf8)).chosenPrintSize,
                       PitchTemplate.defaultPrintSize)
    }

    func testTheOrderSendsTheKeysOwnSize() throws {
        let t = key(.init(widthInches: 4.75, heightInches: 3.25))
        let request = try XCTUnwrap(RetailCheckoutRequest.gridKey(t, storeTemplateName: "Pitching Key"))
        let payload = request.payload(idempotencyKey: "k")
        XCTAssertEqual(payload["retailProductId"] as? String, "grid_custom")
        XCTAssertEqual(payload["itemKind"] as? String, "gridKey")
        XCTAssertEqual(payload["printWidthInches"] as? Double, 4.75)
        XCTAssertEqual(payload["printHeightInches"] as? Double, 3.25)
        XCTAssertEqual(payload["templateId"] as? String, t.id.uuidString)

        var resized = t
        resized.setPrintSize(.init(widthInches: 5, heightInches: 3.25))
        XCTAssertNotEqual(request.fingerprint,
                          try XCTUnwrap(RetailCheckoutRequest.gridKey(resized, storeTemplateName: "Pitching Key")).fingerprint,
                          "a resized key ordered again gets a new checkout")

        var unprintable = t
        unprintable.printWidthInches = 9
        XCTAssertNil(RetailCheckoutRequest.gridKey(unprintable, storeTemplateName: "Pitching Key"), "never a fallback size")
    }

    func testPreviewFreePDFAndFulfillmentAreAllTheKeysSize() throws {
        let size = GridKeyPrintSize(widthInches: 6.25, heightInches: 2.75)
        let t = key(size)
        // Store preview: the key's shape.
        let image = try XCTUnwrap(GridKeyPrint.image(for: t, size: try XCTUnwrap(t.printSize), pixelScale: 2))
        XCTAssertEqual(image.size.width / image.size.height, 6.25 / 2.75, accuracy: 0.01)

        // Free PDF.
        let free = tempURL()
        defer { try? FileManager.default.removeItem(at: free) }
        XCTAssertTrue(GridKeyPrint.writePDF(for: t, size: try XCTUnwrap(t.printSize), to: free))
        let freeBox = try XCTUnwrap(PDFDocument(url: free)?.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(freeBox.width / 72, 6.25, accuracy: 0.001)
        XCTAssertEqual(freeBox.height / 72, 2.75, accuracy: 0.001)

        // Fulfillment: the size saved on the order, read back the way the
        // fulfillment screen reads it.
        let payload = try XCTUnwrap(RetailCheckoutRequest.gridKey(t, storeTemplateName: "Pitching Key")).payload(idempotencyKey: "k")
        let order: [String: Any] = ["retailProductId": payload["retailProductId"]!,
                                    "printWidthInches": payload["printWidthInches"]!,
                                    "printHeightInches": payload["printHeightInches"]!]
        let ordered = try XCTUnwrap(GridKeyProduct.printSize(productId: "grid_custom", custom: GridKeyProduct.orderPrintSize(order)))
        XCTAssertEqual(ordered, size)
        let printed = tempURL()
        defer { try? FileManager.default.removeItem(at: printed) }
        let snapshot = try JSONDecoder().decode(PitchTemplate.self, from: Data((payload["templateSnapshotJson"] as! String).utf8))
        XCTAssertTrue(GridKeyPrint.writePDF(for: snapshot, size: ordered, to: printed))
        let box = try XCTUnwrap(PDFDocument(url: printed)?.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(box.size, freeBox.size, "prints at the size it previewed")
    }
}
