//
//  SeasonBookTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-19 (Season Book):
//  - the PDF page size matches the product
//  - page suggestions put favorites first and leave out hidden photos
//  - the app's page limits and price match the server's
//    (functions/src/seasonBook.ts, functions/test/seasonBook.test.js)
//  Not yet built, so not tested: the stats page (it will use
//  HittingStatLine, like every stats screen).
//

import XCTest
import UIKit
@testable import PitchMark

final class SeasonBookTests: XCTestCase {

    // MARK: Product

    func testPriceMatchesTheServer() {
        // The same values functions/test/seasonBook.test.js checks.
        XCTAssertEqual(SeasonBookProduct.priceCents(pageCount: 30), 4900)
        XCTAssertEqual(SeasonBookProduct.priceCents(pageCount: 32), 5000)
        XCTAssertEqual(SeasonBookProduct.priceCents(pageCount: 40), 5400)
        XCTAssertEqual(SeasonBookProduct.priceCents(pageCount: 200), 4900 + 85 * 100)
        for bad in [0, 28, 29, 31, 201, 202, -30] {
            XCTAssertNil(SeasonBookProduct.priceCents(pageCount: bad), "priced \(bad) pages")
        }
    }

    func testPrintedPageCountIsEvenAndAtLeastTheMinimum() {
        XCTAssertEqual(SeasonBookProduct.printedPageCount(contentPages: 1), 30)
        XCTAssertEqual(SeasonBookProduct.printedPageCount(contentPages: 30), 30)
        XCTAssertEqual(SeasonBookProduct.printedPageCount(contentPages: 31), 32)
        XCTAssertEqual(SeasonBookProduct.printedPageCount(contentPages: 199), 200)
        XCTAssertEqual(SeasonBookProduct.printedPageCount(contentPages: 200), 200)
        XCTAssertNil(SeasonBookProduct.printedPageCount(contentPages: 201))
    }

    func testABookIsATitlePagePlusOnePagePerPhoto() {
        let book = SeasonBook(name: "Spring", pages: (0..<40).map { SeasonBookPage(slideId: "p-m-\($0)") })
        XCTAssertEqual(book.contentPageCount, 41)
        XCTAssertEqual(book.printedPageCount, 42)
        XCTAssertEqual(book.priceCents, 4900 + 6 * 100)
    }

    // MARK: PDF

    func testEveryPDFPageIsTheProductSize() throws {
        let side = (20 / 2.54 + 0.25) * 72
        XCTAssertEqual(SeasonBookProduct.pageSize.width, side, accuracy: 0.01)
        XCTAssertEqual(SeasonBookProduct.pageSize.height, side, accuracy: 0.01)

        let book = SeasonBook(name: "2026 Season", pages: [
            SeasonBookPage(slideId: "p-a-0", caption: "First hit"),
            SeasonBookPage(slideId: "p-a-1"),
            SeasonBookPage(slideId: "f-b", caption: "Dugout")
        ])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("season-book-test.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let written = try SeasonBookPrint.writePDF(book, to: url) { _ in Self.photo() }
        XCTAssertEqual(written, 30)

        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(document.numberOfPages, 30, "padded with blank pages to the minimum")
        for number in 1...document.numberOfPages {
            let box = try XCTUnwrap(document.page(at: number)).getBoxRect(.mediaBox)
            XCTAssertEqual(box.width, side, accuracy: 0.01, "page \(number) width")
            XCTAssertEqual(box.height, side, accuracy: 0.01, "page \(number) height")
        }
    }

    func testAPhotoMissingFromThePhoneStopsTheOrder() {
        let book = SeasonBook(name: "x", pages: [SeasonBookPage(slideId: "p-a-0"), SeasonBookPage(slideId: "p-gone-0")])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("season-book-missing.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try SeasonBookPrint.writePDF(book, to: url) { page in
            page.slideId == "p-gone-0" ? nil : Self.photo()
        })
    }

    // MARK: Suggestion

    func testSuggestionPutsFavoritesFirstAndLeavesOutHiddenPhotos() {
        var newest = Moment(createdAt: Date(timeIntervalSince1970: 200), photoCount: 2)
        newest.id = "m1"
        var favorite = Moment(createdAt: Date(timeIntervalSince1970: 100), isFavorite: true)
        favorite.id = "m2"
        let prefs = HomeSlideshowPrefs(hidden: ["p-m1-0"], favoritePhotos: ["p-m1-1"])

        let pages = SeasonBookSuggestion.pages(
            moments: [newest, favorite],
            prefs: prefs,
            photoExists: { _, _ in true },
            videoExists: { _ in true }
        )
        XCTAssertEqual(pages.map(\.slideId), ["p-m1-1", "f-m2", "f-m1"])
        XCTAssertFalse(pages.contains { $0.slideId == "p-m1-0" }, "a hidden photo was suggested")
        XCTAssertEqual(Set(pages.map(\.slideId)).count, pages.count, "a still was suggested twice")
    }

    func testSuggestionSkipsPhotosNotOnThisPhoneAndRespectsTheLimit() {
        var moment = Moment(photoCount: 5)
        moment.id = "m"
        let pages = SeasonBookSuggestion.pages(
            moments: [moment],
            prefs: HomeSlideshowPrefs(),
            photoExists: { _, index in index != 2 },
            videoExists: { _ in false },
            limit: 3
        )
        XCTAssertEqual(pages.map(\.slideId), ["p-m-0", "p-m-1", "p-m-3"])
    }

    // MARK: Saved layout

    func testTheLayoutSurvivesASaveAndLoad() {
        let book = SeasonBook(id: "b1", name: "Fall Ball", pages: [
            SeasonBookPage(slideId: "p-m-0", caption: "Opening day"),
            SeasonBookPage(slideId: "f-m2")
        ])
        var data = book.firestoreData
        XCTAssertNotNil(data["pages"] as? [[String: Any]], "pages must be an array of maps")
        let loaded = SeasonBook(id: "b1", data: data)
        XCTAssertEqual(loaded?.name, "Fall Ball")
        XCTAssertEqual(loaded?.pages, book.pages)

        data["pages"] = [["slide": "not-a-slide"], ["slide": "p-m-1", "caption": "ok"]]
        XCTAssertEqual(SeasonBook(id: "b1", data: data)?.pages.map(\.slideId), ["p-m-1"])
    }

    private static func photo() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
    }
}
