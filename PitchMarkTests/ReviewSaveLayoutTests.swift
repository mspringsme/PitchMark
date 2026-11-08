//
//  ReviewSaveLayoutTests.swift
//  PitchMarkTests
//
//  Rules 61-63 (approved 2026-11-05): the review sheet's Save opens where
//  Save Result was, so saving is two taps in one place.
//

import XCTest
@testable import PitchMark

final class ReviewSaveLayoutTests: XCTestCase {
    private let bar = ReviewSaveLayout.barHeight

    /// Rule 61: the row is centred on Save Result's height, Save on its x.
    func testRowAndSaveSitOnTheAnchor() {
        let top = ReviewSaveLayout.barTop(anchorMidY: 327, sheetMinY: 80, sheetHeight: 794, barHeight: bar)
        XCTAssertEqual(top + bar / 2, 327 - 80, accuracy: 0.01)
        let x = ReviewSaveLayout.saveCenterX(anchorMidX: 256, sheetMinX: 0, sheetWidth: 402, saveWidth: 114)
        XCTAssertEqual(x, 256, accuracy: 0.01)
        let shifted = ReviewSaveLayout.saveCenterX(anchorMidX: 266, sheetMinX: 10, sheetWidth: 382, saveWidth: 114)
        XCTAssertEqual(shifted, 256, accuracy: 0.01, "measured from the sheet's own left edge")
    }

    /// Rule 62: never above the sheet's top or too near its bottom; Save
    /// clear of Back and the right edge.
    func testRowAndSaveStayInsideTheSheet() {
        XCTAssertEqual(ReviewSaveLayout.barTop(anchorMidY: 93, sheetMinY: 80, sheetHeight: 794, barHeight: bar), 0,
                       "pinned Save Result above the sheet's top")
        let low = ReviewSaveLayout.barTop(anchorMidY: 860, sheetMinY: 80, sheetHeight: 794, barHeight: bar)
        XCTAssertEqual(low, 794 - bar - ReviewSaveLayout.bottomRoom, accuracy: 0.01)
        let left = ReviewSaveLayout.saveCenterX(anchorMidX: 40, sheetMinX: 0, sheetWidth: 402, saveWidth: 114)
        XCTAssertGreaterThanOrEqual(left - 57, 110, "doesn't cover Back")
        let right = ReviewSaveLayout.saveCenterX(anchorMidX: 400, sheetMinX: 0, sheetWidth: 402, saveWidth: 114)
        XCTAssertLessThanOrEqual(right + 57, 402 - 16, "doesn't run off the edge")
    }

    /// Rule 63: title and count above the row only if they fit; the count
    /// never without the title.
    func testOnlyWhatFitsGoesAbove() {
        XCTAssertTrue(ReviewSaveLayout.above(room: 0, headerHeight: 34, countHeight: 150) == (false, false))
        XCTAssertTrue(ReviewSaveLayout.above(room: 64, headerHeight: 34, countHeight: 150) == (true, false))
        XCTAssertTrue(ReviewSaveLayout.above(room: 63, headerHeight: 34, countHeight: 150) == (false, false))
        XCTAssertTrue(ReviewSaveLayout.above(room: 232, headerHeight: 34, countHeight: 150) == (true, true))
        XCTAssertTrue(ReviewSaveLayout.above(room: 231, headerHeight: 34, countHeight: 150) == (true, false))
        XCTAssertTrue(ReviewSaveLayout.above(room: 200, headerHeight: 190, countHeight: 0) == (false, false),
                      "no count above without the title")
    }
}
