//
//  LineupScanReaderTests.swift
//  PitchMarkTests
//
//  Scan Opponent Lineup: the real on-device reader (Vision) on a lineup
//  drawn like a team-app screenshot - order, name, jersey, position.
//

import XCTest
import UIKit
@testable import PitchMark

final class LineupScanReaderTests: XCTestCase {

    private func screenshot(_ lines: [(String, String, String, String)]) -> UIImage {
        let size = CGSize(width: 1170, height: 300 + lines.count * 110)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let header: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 56), .foregroundColor: UIColor.black]
            let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 52), .foregroundColor: UIColor.black]
            ("Lineup" as NSString).draw(at: CGPoint(x: 60, y: 80), withAttributes: header)
            for (i, line) in lines.enumerated() {
                let y = CGFloat(220 + i * 110)
                (line.0 as NSString).draw(at: CGPoint(x: 60, y: y), withAttributes: body)
                (line.1 as NSString).draw(at: CGPoint(x: 160, y: y), withAttributes: body)
                (line.2 as NSString).draw(at: CGPoint(x: 760, y: y), withAttributes: body)
                (line.3 as NSString).draw(at: CGPoint(x: 950, y: y), withAttributes: body)
            }
        }
    }

    func testReadsADrawnLineupScreenshot() async {
        let image = screenshot([
            ("1", "Jake Smith", "#12", "SS"),
            ("2", "Ann Lee", "#4", "CF"),
            ("3", "Cy Young", "#9", "P"),
            ("4", "Bo Diaz", "#22", "1B"),
        ])
        let rows = await LineupScanReader.rows(from: [image])
        XCTAssertEqual(rows.map(\.order), [1, 2, 3, 4])
        XCTAssertEqual(rows.map(\.jersey), ["12", "4", "9", "22"])
        XCTAssertEqual(rows.map(\.name), ["Jake Smith", "Ann Lee", "Cy Young", "Bo Diaz"])
    }

    /// The user's real GameChanger box score (2026-11-06): the twelve
    /// Cheetahs in order with their jerseys, cut-short names flagged,
    /// and nothing else kept.
    func testRealGameChangerBoxScore() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LineupBoxScoreGameChanger", withExtension: "png"))
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path))
        let rows = await LineupScanReader.rows(from: [image])
        let kept = rows.filter(\.likelyBatter)
        XCTAssertEqual(kept.map(\.jersey), ["12", "7", "3", "13", "23", "62", "8", "11", "44", "16", "1", "4"])
        XCTAssertEqual(kept.map(\.name), [
            "T Hanew", "E Steph...s", "A McCalla", "E Claahsen", "L Laxton", "E Hoffm",
            "A Barratt", "C Suda", "F Homolka", "A Siuty", "A Adriea", "G Trela",
        ])
        XCTAssertEqual(kept.filter(\.needsCheck).map(\.jersey), ["12", "7", "62", "1"], "only the cut-short names")
    }
}
