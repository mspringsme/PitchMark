//
//  ChipPicking.swift
//  PitchMarkUITests
//
//  Tapping the picked pitch chip deselects it (2026-11-21), so a test that
//  wants a chip picked taps it only when it isn't already.
//

import XCTest

extension XCUIElement {
    func pickChip(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForExistence(timeout: 15), "\(self) missing", file: file, line: line)
        if !isSelected { tap() }
    }
}
