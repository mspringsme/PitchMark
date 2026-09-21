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
/// - C3: each character inside the tapped column’s header cell in the selected bottom grid (strikes/balls)
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

    /// Ambiguity-safe alphanumeric pool (digits/letters that aren't easily confused with each other,
    /// e.g. no 0/O, 1/I). Shared by the Normal-mode location grid and the Advanced-mode top-row header,
    /// so both are randomized from the same pool.
    static let safeAlnumPool: [Character] = Array("23456789AFHJKLMPQRSTVWXY")

    private static func sanitize(_ value: String) -> String {
        value.uppercased().filter { $0.isNumber || ($0.isLetter && $0.isASCII) }
    }

    /// Resolves the top pitch-selection grid's column for `selectedPitch`, and returns each row's
    /// (C1 options, C2 character) pair. Shared by `generateCalls` and `generateNormalCalls` since
    /// pitch identification (C1+C2) is identical in both modes.
    private static func pitchRowOptions(
        template: PitchTemplate,
        selectedPitch: String
    ) -> [(c1Options: [String], c2: String)]? {
        let headerPitches = template.pitchGridHeaders.map { $0.pitch }
        if headerPitches.count != template.pitches.count || headerPitches != template.pitches {
            debugLog("[GENERATOR WARNING] pitchGridHeaders and pitches differ in count or order.")
            debugLog("Headers: \(headerPitches)")
            debugLog("Pitches: \(template.pitches)")
        }
        let pitchCol: Int
        if let headerIndex = headerPitches.firstIndex(of: selectedPitch) {
            pitchCol = headerIndex + 1
            debugLog("[GENERATOR] Using headers. headerPitches=\(headerPitches) selectedPitchIndex=\(headerIndex) pitchCol=\(pitchCol)")
        } else if let pitchIndex = template.pitches.firstIndex(of: selectedPitch) {
            pitchCol = pitchIndex + 1
            debugLog("[GENERATOR] Using pitches fallback. pitches=\(template.pitches) selectedPitchIndex=\(pitchIndex) pitchCol=\(pitchCol)")
        } else {
            debugLog("EncryptedCodeGenerator: selected pitch not found in headers or pitches — \(selectedPitch)")
            return nil
        }

        guard !template.pitchGridValues.isEmpty else {
            debugLog("EncryptedCodeGenerator: template.pitchGridValues is empty")
            return nil
        }

        let sanitizedPitchGridValues = template.pitchGridValues.map { row in row.map { sanitize($0) } }

        var rowOptions: [(c1Options: [String], c2: String)] = []
        for (rowIdx, row) in sanitizedPitchGridValues.enumerated() {
            guard row.count > max(0, pitchCol) else {
                debugLog("EncryptedCodeGenerator: top grid row \(rowIdx) has insufficient columns")
                continue
            }

            let leading = row[0]
            let c1Options = leading.map { String($0) }
            if c1Options.isEmpty { continue }

            let c2String = row[pitchCol]
            guard let c2Char = c2String.first else { continue }
            let c2 = String(c2Char)
            debugLog("[GENERATOR ROW] idx=\(rowIdx) leading='\(leading)' C1Options=\(c1Options) C2='\(c2)'")

            rowOptions.append((c1Options: c1Options, c2: c2))
        }
        return rowOptions
    }

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
        debugLog("[GENERATOR START] kind=\(gridKind) selectedPitch=\(selectedPitch) col=\(columnIndex) row=\(rowIndex)")

        // Validate bottom grid indices
        guard (0...2).contains(columnIndex), (0...2).contains(rowIndex) else {
            debugLog("EncryptedCodeGenerator: invalid bottom-grid indices col=\(columnIndex) row=\(rowIndex)")
            return []
        }

        guard let rowOptions = pitchRowOptions(template: template, selectedPitch: selectedPitch) else {
            return []
        }

        debugLog("Headers: \(template.pitchGridHeaders)")
        debugLog("Pitches: \(template.pitches)")

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

        // Normalize a leading blank row if present (editor sometimes stores 4 rows with first empty)
        let bottomRows: [[String]] = {
            if bottomRowsRaw.count == 4,
               bottomRowsRaw.first?.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) == true {
                let dropped = Array(bottomRowsRaw.dropFirst())
                debugLog("[GENERATOR] Detected leading blank row in bottom grid; using rows=\(dropped.count)")
                return dropped
            }
            return bottomRowsRaw
        }()
        debugLog("[GENERATOR] bottom headers=\(bottomHeaders) rows count=\(bottomRows.count) firstRow=\(bottomRows.first ?? [])")

        // Sanitize grid content to remove interpuncts and non-alnum chars
        let sanitizedBottomHeaders = bottomHeaders.map { sanitize($0) }
        let sanitizedBottomRows = bottomRows.map { row in row.map { sanitize($0) } }

        guard bottomHeaders.count == 3 else {
            debugLog("EncryptedCodeGenerator: bottom header count != 3 (\(bottomHeaders.count))")
            return []
        }
        guard bottomRows.count >= 3, bottomRows.allSatisfy({ $0.count >= 3 }) else {
            debugLog("EncryptedCodeGenerator: bottom grid rows must be 3x3")
            return []
        }

        // C3 from header’s first character of tapped column
        let header = sanitizedBottomHeaders[columnIndex]
        let c3Options = header.map { String($0) }
        if c3Options.isEmpty {
            debugLog("EncryptedCodeGenerator: tapped column header is empty at col=\(columnIndex)")
            return []
        }
        debugLog("[GENERATOR] tapped header='\(header)' C3Options=\(c3Options)")

        // C4 options from each character in the tapped cell
        let tappedCell = sanitizedBottomRows[rowIndex][columnIndex]
        let c4Options = tappedCell.map { String($0) }
        if c4Options.isEmpty {
            debugLog("EncryptedCodeGenerator: tapped cell is empty at (r=\(rowIndex), c=\(columnIndex))")
            return []
        }
        debugLog("[GENERATOR] tapped cell at (r=\(rowIndex), c=\(columnIndex)) value='\(tappedCell)' C4Options=\(c4Options)")

        var results: [String] = []

        // Combine each row's C1 x C2 with C3 x C4
        for row in rowOptions {
            for c1 in row.c1Options {
                for c3 in c3Options {
                    for c4 in c4Options {
                        let code = c1 + row.c2 + c3 + c4
                        results.append(code)
                    }
                }
            }
        }

        // Print for debugging as requested
        if results.isEmpty {
            debugLog("[GENERATOR RESULT] no codes generated")
        } else {
            debugLog("[GENERATOR RESULT] count=\(results.count) codes=\(results.joined(separator: ", "))")
        }

        return results
    }

    /// Generate C1C2Cloc codes (Normal / 3-character mode) given the template, selected pitch, and tap mapping.
    /// C1+C2 identify the pitch exactly as in `generateCalls`; Cloc is the single character stored at
    /// `[rowIndex][columnIndex]` in `template.strikeLocationCells`/`ballsLocationCells`.
    /// - Parameters:
    ///   - template: The `PitchTemplate` containing encrypted grid data (`codeMode == .normal`).
    ///   - selectedPitch: The coach-selected pitch (must exist in `template.pitches`).
    ///   - gridKind: Which location grid was tapped (strikes/balls).
    ///   - columnIndex: Column in the location grid (0..2).
    ///   - rowIndex: Row in the location grid (0..2), where 0=top, 1=middle, 2=bottom.
    /// - Returns: Array of 3-character codes in the order generated.
    static func generateNormalCalls(
        template: PitchTemplate,
        selectedPitch: String,
        gridKind: EncryptedGridKind,
        columnIndex: Int,
        rowIndex: Int
    ) -> [String] {
        debugLog("[GENERATOR START normal] kind=\(gridKind) selectedPitch=\(selectedPitch) col=\(columnIndex) row=\(rowIndex)")

        guard (0...2).contains(columnIndex), (0...2).contains(rowIndex) else {
            debugLog("EncryptedCodeGenerator: invalid location-grid indices col=\(columnIndex) row=\(rowIndex)")
            return []
        }

        guard let rowOptions = pitchRowOptions(template: template, selectedPitch: selectedPitch) else {
            return []
        }

        let locationCells: [[String]]
        switch gridKind {
        case .strikes:
            locationCells = template.strikeLocationCells
        case .balls:
            locationCells = template.ballsLocationCells
        }

        guard locationCells.count >= 3, locationCells.allSatisfy({ $0.count >= 3 }) else {
            debugLog("EncryptedCodeGenerator: location grid must be 3x3")
            return []
        }

        let cloc = sanitize(locationCells[rowIndex][columnIndex])
        guard !cloc.isEmpty else {
            debugLog("EncryptedCodeGenerator: tapped location cell is empty at (r=\(rowIndex), c=\(columnIndex))")
            return []
        }

        var results: [String] = []
        for row in rowOptions {
            for c1 in row.c1Options {
                results.append(c1 + row.c2 + cloc)
            }
        }

        if results.isEmpty {
            debugLog("[GENERATOR RESULT normal] no codes generated")
        } else {
            debugLog("[GENERATOR RESULT normal] count=\(results.count) codes=\(results.joined(separator: ", "))")
        }

        return results
    }
}
