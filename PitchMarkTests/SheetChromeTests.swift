//
//  SheetChromeTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-20 (sheets easier to close):
//  T1 every sheet goes through `appSheet` - a plain `.sheet(` anywhere in
//     PitchMark/ or PitchMarkDisplay/ fails, so a new sheet can't skip the
//     drag handle / top margin / close button. Full-screen covers keep
//     their own top bars (the Moment editors' MomentEditorTopBar) and
//     aren't sheets.
//  Plus: the ✕'s tap area is at least Apple's 44 pt.
//

import XCTest
@testable import PitchMark

final class SheetChromeTests: XCTestCase {

    func testEverySheetGoesThroughAppSheet() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var offenders: [String] = []
        var appSheets = 0
        for folder in ["PitchMark", "PitchMarkDisplay"] {
            let directory = root.appendingPathComponent(folder)
            let files = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" }
            XCTAssertFalse(files.isEmpty, "no source in \(folder) - the test can't see the code")
            for file in files {
                let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                for (index, line) in lines.enumerated() {
                    let code = line.components(separatedBy: "//").first ?? ""
                    appSheets += code.components(separatedBy: ".appSheet(").count - 1
                    if code.contains(".sheet(") {
                        offenders.append("\(file.lastPathComponent):\(index + 1)")
                    }
                }
            }
        }
        XCTAssertEqual(offenders, [], "use .appSheet(...) - plain .sheet( skips the close chrome")
        XCTAssertGreaterThan(appSheets, 100, "found too few sheets - the scan is broken")
    }

    func testTheCloseButtonIsBigEnoughToTap() {
        XCTAssertGreaterThanOrEqual(AppSheetChromeMetrics.closeTapSize, 44)
        XCTAssertGreaterThan(AppSheetChromeMetrics.topMargin, 0)
    }
}
