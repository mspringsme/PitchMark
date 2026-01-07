import Foundation

/// Represents whether the tap landed in the strikes (green) or balls (red) grid.
enum EncryptedGridKind {
    case strikes
    case balls
}

/// A small helper that produces C1–C4 4-character codes from a `PitchTemplate`, a selected pitch,
/// and a geometry-derived tap mapping (grid kind, column index, row index).
///
/// It follows the reference algorithm:
/// - C1: each character from the first two-character cell in the first column of a top-grid row
/// - C2: the character at the selected pitch’s column for that same row
/// - C3: first character of the tapped column’s header in the selected bottom grid (strikes/balls)
/// - C4: each character inside the tapped cell (rowIndex, columnIndex) of the selected bottom grid
///
/// Notes/assumptions:
/// - `PitchTemplate.pitchGridValues` is a 4 x N matrix of strings for top grid values, where
///   column 0 holds the two-character leading cell (source for C1), and columns 1..N-1 correspond to pitches.
/// - `PitchTemplate.pitchGridHeaders` holds the pitch headers (col > 0) aligned with `template.pitches`.
/// - `strikeTopRow`/`ballsTopRow` are length 3 strings for headers of bottom grids; `strikeRows`/`ballsRows` are 3 x 3
///   strings for the bottom-grid content rows.
/// - All characters are treated individually. Multi-character strings are split character-by-character.
///
/// The function returns the generated calls and also prints them for debugging.
struct EncryptedCodeGenerator {

    /// Generate C1C2C3C4 codes given the template, selected pitch, and tap mapping.
    /// - Parameters:
    ///   - template: The `PitchTemplate` containing encrypted grid data.
    ///   - selectedPitch: The coach-selected pitch (must exist in `template.pitches`).
    ///   - gridKind: Which bottom grid was tapped (strikes/balls).
    ///   - columnIndex: Column in the bottom grid (0..2).
    ///   - rowIndex: Row in the bottom grid (0..2), where 0=top, 1=middle, 2=bottom.
    /// - Returns: Array of 4-character codes in the order generated.
    static func generateCalls(
        template: PitchTemplate,
        selectedPitch: String,
        gridKind: EncryptedGridKind,
        columnIndex: Int,
        rowIndex: Int
    ) -> [String] {
        print("[GENERATOR START] kind=\(gridKind) selectedPitch=\(selectedPitch) col=\(columnIndex) row=\(rowIndex)")

        // Validate bottom grid indices
        guard (0...2).contains(columnIndex), (0...2).contains(rowIndex) else {
            print("EncryptedCodeGenerator: invalid bottom-grid indices col=\(columnIndex) row=\(rowIndex)")
            return []
        }

        // Resolve pitch column using headers (which align with pitchGridValues columns 1...N-1)
        let headerPitches = template.pitchGridHeaders.map { $0.pitch }
        // Warn if headers and pitches differ (count or order)
        if headerPitches.count != template.pitches.count || headerPitches != template.pitches {
            print("[GENERATOR WARNING] pitchGridHeaders and pitches differ in count or order.")
            print("Headers: \(headerPitches)")
            print("Pitches: \(template.pitches)")
        }
        let pitchCol: Int
        if let headerIndex = headerPitches.firstIndex(of: selectedPitch) {
            // headerIndex maps directly to the grid column (since col 0 is the leading cell)
            pitchCol = headerIndex + 1
            print("[GENERATOR] Using headers. headerPitches=\(headerPitches) selectedPitchIndex=\(headerIndex) pitchCol=\(pitchCol)")
        } else if let pitchIndex = template.pitches.firstIndex(of: selectedPitch) {
            // Fallback: assumes pitches are in the same order as headers
            pitchCol = pitchIndex + 1
            print("[GENERATOR] Using pitches fallback. pitches=\(template.pitches) selectedPitchIndex=\(pitchIndex) pitchCol=\(pitchCol)")
        } else {
            print("EncryptedCodeGenerator: selected pitch not found in headers or pitches — \(selectedPitch)")
            return []
        }

        // Sanity-check top grid dimensions (expecting 4 rows)
        guard !template.pitchGridValues.isEmpty else {
            print("EncryptedCodeGenerator: template.pitchGridValues is empty")
            return []
        }

        // Bottom grid: headers and rows for strikes/balls
        let bottomHeaders: [String]
        let bottomRowsRaw: [[String]]
        switch gridKind {
        case .strikes:
            bottomHeaders = template.strikeTopRow
            bottomRowsRaw = template.strikeRows
        case .balls:
            bottomHeaders = template.ballsTopRow
            bottomRowsRaw = template.ballsRows
        }
        
        print("Headers: \(template.pitchGridHeaders)")
        print("Pitches: \(template.pitches)")
        for (i, row) in template.pitchGridValues.enumerated() {
            print("Row \(i): \(row)")
        }
        
        // Normalize a leading blank row if present (editor sometimes stores 4 rows with first empty)
        let bottomRows: [[String]] = {
            if bottomRowsRaw.count == 4,
               bottomRowsRaw.first?.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) == true {
                let dropped = Array(bottomRowsRaw.dropFirst())
                print("[GENERATOR] Detected leading blank row in bottom grid; using rows=\(dropped.count)")
                return dropped
            }
            return bottomRowsRaw
        }()
        print("[GENERATOR] bottom headers=\(bottomHeaders) rows count=\(bottomRows.count) firstRow=\(bottomRows.first ?? [])")

        guard bottomHeaders.count == 3 else {
            print("EncryptedCodeGenerator: bottom header count != 3 (\(bottomHeaders.count))")
            return []
        }
        guard bottomRows.count >= 3, bottomRows.allSatisfy({ $0.count >= 3 }) else {
            print("EncryptedCodeGenerator: bottom grid rows must be 3x3")
            return []
        }

        // C3 from header’s first character of tapped column
        let header = bottomHeaders[columnIndex]
        guard let c3 = header.first else {
            print("EncryptedCodeGenerator: tapped column header is empty at col=\(columnIndex)")
            return []
        }
        print("[GENERATOR] tapped header='\(header)' C3='\(c3)'")

        // C4 options from each character in the tapped cell
        let tappedCell = bottomRows[rowIndex][columnIndex]
        let c4Options = tappedCell.map { String($0) }
        if c4Options.isEmpty {
            print("EncryptedCodeGenerator: tapped cell is empty at (r=\(rowIndex), c=\(columnIndex))")
            return []
        }
        print("[GENERATOR] tapped cell at (r=\(rowIndex), c=\(columnIndex)) value='\(tappedCell)' C4Options=\(c4Options)")

        var results: [String] = []

        // Iterate each top-grid row to form C1, C2
        for (rowIdx, row) in template.pitchGridValues.enumerated() {
            // Row must at least contain the leading cell and the selected pitch column
            guard row.count > max(0, pitchCol) else {
                print("EncryptedCodeGenerator: top grid row \(rowIdx) has insufficient columns")
                continue
            }

            // C1 options come from column 0 (two-character string)
            let leading = row[0]
            let c1Options = leading.map { String($0) }
            if c1Options.isEmpty {
                // Skip rows with no leading characters
                continue
            }

            // C2 is the character in the selected pitch’s column for this row
            let c2String = row[pitchCol]
            guard let c2Char = c2String.first else {
                // If empty, skip this row
                continue
            }
            let c2 = String(c2Char)
            print("[GENERATOR ROW] idx=\(rowIdx) leading='\(leading)' C1Options=\(c1Options) C2='\(c2)'")

            // Combine C1 x C2 x C3 x C4
            for c1 in c1Options {
                for c4 in c4Options {
                    let code = c1 + c2 + String(c3) + c4
                    results.append(code)
                }
            }
        }

        // Print for debugging as requested
        if results.isEmpty {
            print("[GENERATOR RESULT] no codes generated")
        } else {
            print("[GENERATOR RESULT] count=\(results.count) codes=\(results.joined(separator: ", "))")
        }

        return results
    }
}

