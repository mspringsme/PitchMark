//
//  Utilities.swift
//  PitchMark
//
//  Created by Mark Springer on 9/30/25.
//

import SwiftUI
import UIKit
import FirebaseFirestore

// Shared helper: returns a stable color for any pitch name, including custom ones.
// Order of precedence: user override -> pitchColors map -> deterministic palette.
func colorForPitch(_ pitch: String) -> Color {
    if let override = pitchColorOverride(for: pitch) { return override }
    if let base = pitchColors[pitch] { return base }
    let palette: [Color] = [.indigo, .teal, .mint, .pink, .purple, .orange, .brown, .cyan]
    let key = pitch.lowercased()
    var hash = 0
    for scalar in key.unicodeScalars { hash = (hash &* 31) &+ Int(scalar.value) }
    let index = abs(hash) % palette.count
    return palette[index]
}

let templatePaletteColorNames: [String] = ["red", "black", "green", "white", "blue"]

func templatePaletteColor(_ name: String) -> Color {
    switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "red":
        return .red
    case "black":
        return .black
    case "green":
        return .green
    case "white":
        return .white
    case "blue":
        return .blue
    default:
        return .gray
    }
}

private let pitchColorOverridesKey = "pitchColorOverrides"

// Convert Color <-> Hex for persistence
private func colorToHex(_ color: Color) -> String? {
    let ui = UIColor(color)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
    let ri = Int((r * 255).rounded())
    let gi = Int((g * 255).rounded())
    let bi = Int((b * 255).rounded())
    return String(format: "#%02X%02X%02X", ri, gi, bi)
}

private func hexToColor(_ hex: String) -> Color? {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let val = Int(s, radix: 16) else { return nil }
    let r = Double((val >> 16) & 0xFF) / 255.0
    let g = Double((val >> 8) & 0xFF) / 255.0
    let b = Double(val & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
}

func pitchColorOverride(for pitch: String) -> Color? {
    let dict = UserDefaults.standard.dictionary(forKey: pitchColorOverridesKey) as? [String: String]
    if let hex = dict?[pitch], let color = hexToColor(hex) { return color }
    return nil
}

func setPitchColorOverride(pitch: String, color: Color?) {
    var dict = UserDefaults.standard.dictionary(forKey: pitchColorOverridesKey) as? [String: String] ?? [:]
    if let color = color, let hex = colorToHex(color) {
        dict[pitch] = hex
    } else {
        dict.removeValue(forKey: pitch)
    }
    UserDefaults.standard.set(dict, forKey: pitchColorOverridesKey)
}

let pitchColors: [String: Color] = [
    "4 Seam": .blue,            // classic fastball
    "2 Seam": ._2Seam,            // cooler tone than green---
    "Change": .brown,           // earthy, off-speed
    "Curve": .purple,           // sharp break
    "Screw": ._Screw,             // neutral, subtle
    "Smile": ._Smile,           // playful, high visibility
    "Drop": ._Drop,              // light, vertical action---
    "Rise": .mint,              // soft, upward movement---
    "Pipe": .black              // bold, center-cut
]

// ... rest of the file unchanged ...

extension Color {
    static let _2Seam = Color(red: 1.0, green: 143/255, blue: 0)
    static let _Drop = Color(red: 1.0, green: 0.0, blue: 1.0)
    static let _Screw = Color(red: 172/255, green: 172/255, blue: 172/255)
    static let _Smile = Color(red: 0, green: 200/255, blue: 1.0)
    // Add more as needed
}

let strikeGrid: [GridLocation] = [
    .init(row: 0, col: 0, label: "Up & Out"),
    .init(row: 0, col: 1, label: "Up"),
    .init(row: 0, col: 2, label: "Up & In"),
    .init(row: 1, col: 0, label: "Out"),
    .init(row: 1, col: 1, label: "Middle"),
    .init(row: 1, col: 2, label: "In"),
    .init(row: 2, col: 0, label: "↓ & Out"),
    .init(row: 2, col: 1, label: "↓"),
    .init(row: 2, col: 2, label: "↓ & In")
]

let allPitches = ["2 Seam", "4 Seam", "Change", "Curve", "Screw", "Smile", "Drop", "Rise", "Pipe"]

let pitchOrder: [String] = [
    "2 Seam", "4 Seam", "Change", "Curve", "Drop", "Pipe", "Rise", "Screw", "Smile"
]

func allLocationsFromGrid() -> [String] {
    strikeGrid.map(\.label) + [
        "Up & Out", "Up", "Up & In",
        "Out", "In",
        "↓ & Out", "↓", "↓ & In"
    ]
}

func normalizedLocation(from label: String) -> String {
    if label.hasPrefix("Strike ") || label.hasPrefix("Ball ") {
        return label
    }

    let strikeLabels = strikeGrid.map(\.label)
    let prefix = strikeLabels.contains(label) ? "Strike" : "Ball"
    return "\(prefix) \(label)"
}

func normalizedLabel(_ label: String) -> String {
    switch label {
    case "Up & In":       return "Up & In"
    case "↓ & In":     return "↓ & In"
    case "Up & Out":      return "Up & Out"
    case "↓ & Out":    return "↓ & Out"
    case "Up":              return "Up"
    case "↓":            return "↓"
    case "In":              return "In"
    case "Out":             return "Out"
    case "Middle":          return "Middle"
    default:                return label
    }
}

struct LabelFactory {
    let batterSide: BatterSide

    func fullLabel(prefix: String, rawLabel: String) -> String {
        let norm = normalizedLabel(rawLabel)                       // produces "Up & In", etc.
        let adj = PitchLabelManager(batterSide: batterSide).adjustedLabel(from: norm)
        return "\(prefix) \(adj)"                                  // "Strike Up & In" or "Ball ↓  & Out"
    }
}

struct BatterLabelSet {
    let strikeFull: [String]
    let ballFull: [String]

    init(side: BatterSide) {
        let factory = LabelFactory(batterSide: side)
        strikeFull = strikeGrid.map { factory.fullLabel(prefix: "Strike", rawLabel: $0.label) }
        let ballRaw = [
            "Up & Out", "Up", "Up & In",
            "Out", "In",
            "↓ & Out", "↓", "↓ & In"
        ]
        ballFull = ballRaw.map { factory.fullLabel(prefix: "Ball", rawLabel: $0) }
    }
}

struct PitchLocation {
    let label: String
    let isStrike: Bool
}

struct GridLocation: Identifiable, Codable, Hashable {
    let id = UUID()
    let row: Int
    let col: Int
    let label: String
}

struct PitchLabelManager {
    let batterSide: BatterSide

    func adjustedLabel(from rawLabel: String) -> String {
        guard batterSide == .left else { return rawLabel }

        var output = rawLabel

        func replaceWholeWord(_ word: String, with replacement: String) {
            if output == word {
                output = replacement
            }
            output = output.replacingOccurrences(of: " \(word) ", with: " \(replacement) ")
            if output.hasPrefix("\(word) ") {
                output = output.replacingOccurrences(of: "\(word) ", with: "\(replacement) ")
            }
            if output.hasSuffix(" \(word)") {
                output = output.replacingOccurrences(of: " \(word)", with: " \(replacement)")
            }
            output = output.replacingOccurrences(of: " & \(word) ", with: " & \(replacement) ")
            if output.hasPrefix("\(word) &") {
                output = output.replacingOccurrences(of: "\(word) &", with: "\(replacement) &")
            }
            if output.hasSuffix("& \(word)") {
                output = output.replacingOccurrences(of: "& \(word)", with: "& \(replacement)")
            }
            
        }
        
        replaceWholeWord("In", with: "__TEMP_IN__")
        replaceWholeWord("Out", with: "In")
        replaceWholeWord("__TEMP_IN__", with: "Out")

        return output
    }

    func adjustedCallPrefix(for rawLabel: String, isStrike: Bool) -> String {
        let adjusted = adjustedLabel(from: rawLabel)

        let strikeZoneLabels: Set<String> = [
            "Up & In", "Up", "Up & Out",
            "In", "Middle", "Out",
            "↓ & In", "↓", "↓ & Out"
        ]

        return strikeZoneLabels.contains(adjusted) ? "Strike" : "Ball"
    }
}

struct PitchCodeAssignment: Hashable, Codable {
    // Plaintext code retained for backward compatibility
    let code: String
    let pitch: String
    let location: String

    // Optional encrypted representation of the code. When present and the template is encrypted,
    // prefer this over the plaintext `code`.
    var encryptedCode: String? = nil

    // Helper to resolve which code to use based on encryption context.
    // Pass `true` when the surrounding template is encrypted.
    func effectiveCode(usingEncrypted: Bool) -> String {
        if usingEncrypted, let encryptedCode {
            return encryptedCode
        }
        return code
    }
}

/// Returns the display code for an assignment given the active template mode.
/// In classic mode, this is the classic `code`.
/// In fail-safe (“encrypted”) mode, this selects `encryptedCode` if provided; otherwise falls back to `code`.
func decipherDisplayCode(from assignment: PitchCodeAssignment, using template: PitchTemplate) -> String {
    // Select the stored code for the current mode
    let stored = assignment.effectiveCode(usingEncrypted: template.isEncrypted)

    // Optional: apply a transformation for fail-safe mode if you want a distinct presentation.
    // For now, we simply return the selected value without further changes.
    // Example transform (commented):
    // if template.isEncrypted {
    //     return stored.replacingOccurrences(of: "-", with: "•")
    // }

    return stored
}

struct PitchHeader: Codable, Hashable {
    var pitch: String
    var abbreviation: String?
}

struct Pitcher: Identifiable, Codable, Hashable {
    @DocumentID var id: String?

    var name: String
    var templateId: String?

    var ownerUid: String
    var sharedWith: [String]
    var claimedByUid: String?

    var createdAt: Date? = nil
}

extension Pitcher {
    var activeOwnerUid: String {
        claimedByUid ?? ownerUid
    }

    func isActiveOwner(currentUid: String?) -> Bool {
        guard let currentUid else { return false }
        return activeOwnerUid == currentUid
    }
}

struct PitchTemplate: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var pitches: [String]
    var codeAssignments: [PitchCodeAssignment]
    var isEncrypted: Bool = false
    var ownerUid: String? = nil
    var sharedWith: [String] = []
    var sharedWithEmails: [String] = []

    // Encrypted editor data
    var pitchGridHeaders: [PitchHeader] = []          // headers from PitchGridView2 (col > 0)
    var pitchGridValues: [[String]] = []              // 4 x N grid values

    var strikeTopRow: [String] = []                   // length 3
    var strikeRows: [[String]] = []                   // 4 x 3

    var ballsTopRow: [String] = []                    // length 3
    var ballsRows: [[String]] = []                    // 4 x 3

    var pitchFirstColors: [String] = []              // length 2
    var locationFirstColors: [String] = []           // length 3
}

enum BatterSide: String, CaseIterable, Identifiable, Codable {
    case left, right

    var id: String { rawValue }

    var displayName: String {
        "\(self == .left ? "Left" : "Right")-Handed Batter"
    }

    var opposite: BatterSide {
        self == .left ? .right : .left
    }
}

enum PitchImageDictionary {
    static let imageMap: [String: String] = [
        // Right-handed batter
        "Strike Middle|right": "Strike Middle",
        "Strike High|right": "Strike High",
        "Strike Low|right": "Strike Low",
        "Strike Up & In|right": "Strike High Right_Inside_Righty",
        "Strike Up & Out|right": "Strike High Left_Outside_Righty",
        "Strike ↓ & In|right": "Strike Low Right_Inside_Righty",
        "Strike ↓|right": "Strike Low",
        "Strike ↓ & Out|right": "Strike Low Left_Outside_Righty png",
        "Strike In|right": "Strike Right_Inside_Righty",
        "Strike Out|right": "Strike Left_Outside_Righty",
        
        "Ball High|right": "Ball High",
        "Ball Low|right": "Ball Low",
        "Ball ↓|right": "Ball Low",
        "Ball Up & In|right": "Ball High Right_Inside_Righty",
        "Ball Up & Out|right": "Ball High Left_Outside_Righty",
        "Ball ↓ & In|right": "Ball Low Right_Inside_Righty",
        "Ball ↓ & Out|right": "Ball Low Left_Outside_Righty",
        "Ball In|right": "Ball Right_Inside_Righty",
        "Ball Out|right": "Ball Left_Outside_Righty",
        
        // Left-handed batter (flipped)
        "Strike Middle|left": "Strike Middle",
        "Strike High|left": "Strike High",
        "Strike Low|left": "Strike Low",
        "Strike Up & In|left": "Strike High Left_Inside_Lefty",
        "Strike Up & Out|left": "Strike High Right_Outside_Lefty",
        "Strike ↓ & In|left": "Strike Low Left_Inside_Lefty",
        "Strike ↓ & Out|left": "Strike Low Right_Outside_Lefty",
        "Strike In|left": "Strike Left_Inside_Lefty",
        "Strike Out|left": "Strike Right_Outside_Lefty",
        
        "Ball High|left": "Ball High",
        "Ball Low|left": "Ball Low",
        "Ball ↓|left": "Ball Low",
        "Ball Up & In|left": "Ball High Left_Inside_Lefty",
        "Ball Up & Out|left": "Ball High Right_Outside_Lefty",
        "Ball ↓ & In|left": "Ball Low Left_Inside_Lefty",
        "Ball ↓ & Out|left": "Ball Low Right_Outside_Lefty",
        "Ball In|left": "Ball Left_Inside_Lefty",
        "Ball Out|left": "Ball Right_Outside_Lefty",
        
        "Strike Up|right": "Strike High",
        "Strike Up|left": "Strike High",
        "Ball Up|right": "Ball High",
        "Ball Up|left": "Ball High"
        
    ]
    
    
    static func imageName(for location: String, isStrike: Bool, batterSide: BatterSide) -> String {
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "\(trimmedLocation)|\(batterSide.rawValue)"
        print("🔍 Lookup key: \(key)")
        
        if let image = imageMap[key] {
            return image
        } else {
            print("⚠️ Missing image for key: \(key)")
            return "Bat"
        }
    }
}

enum HeatmapLocationSource: String, CaseIterable, Identifiable {
    case result = "Result"
    case called = "Called"

    var id: String { rawValue }
}

struct HeatmapCell: Identifiable, Hashable {
    let row: Int
    let col: Int
    let count: Int

    var id: String { "\(row)-\(col)" }
}

struct HeatmapSummary {
    let cells: [HeatmapCell]
    let outerCounts: [Int]
    let maxCount: Int
    let outerMaxCount: Int
    let totalCount: Int
}

private enum HeatmapPoint {
    case inner(row: Int, col: Int)
    case outer(index: Int) // 0...7 matches StrikeZoneView ballLocations order
}

private func heatmapPoint(for rawLocation: String) -> HeatmapPoint? {
    let trimmed = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix: String? = {
        if trimmed.hasPrefix("Strike ") { return "strike" }
        if trimmed.hasPrefix("Ball ") { return "ball" }
        return nil
    }()

    var zone = trimmed
    if trimmed.hasPrefix("Strike ") {
        zone = String(trimmed.dropFirst("Strike ".count))
    } else if trimmed.hasPrefix("Ball ") {
        zone = String(trimmed.dropFirst("Ball ".count))
    }

    let normalized = zone
        .lowercased()
        .replacingOccurrences(of: "—", with: " ")
        .replacingOccurrences(of: "–", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .replacingOccurrences(of: "  ", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    // Ball-prefixed locations map to the outside ring.
    if prefix == "ball" {
        if normalized.contains("up") && normalized.contains("out") { return .outer(index: 0) }
        if normalized == "up" || normalized == "high" { return .outer(index: 1) }
        if normalized.contains("up") && normalized.contains("in") { return .outer(index: 2) }
        if normalized == "out" { return .outer(index: 3) }
        if normalized == "in" { return .outer(index: 4) }
        if (normalized.contains("↓") || normalized.contains("down") || normalized.contains("low")) && normalized.contains("out") { return .outer(index: 5) }
        if normalized == "↓" || normalized == "down" || normalized == "low" { return .outer(index: 6) }
        if (normalized.contains("↓") || normalized.contains("down") || normalized.contains("low")) && normalized.contains("in") { return .outer(index: 7) }
    }

    // Strike-prefixed locations map to inner grid.
    if prefix == "strike" {
        if normalized.contains("up") && normalized.contains("out") { return .inner(row: 0, col: 0) }
        if normalized == "up" || normalized == "high" { return .inner(row: 0, col: 1) }
        if normalized.contains("up") && normalized.contains("in") { return .inner(row: 0, col: 2) }
        if normalized == "out" { return .inner(row: 1, col: 0) }
        if normalized == "middle" { return .inner(row: 1, col: 1) }
        if normalized == "in" { return .inner(row: 1, col: 2) }
        if (normalized.contains("↓") || normalized.contains("down") || normalized.contains("low")) && normalized.contains("out") { return .inner(row: 2, col: 0) }
        if normalized == "↓" || normalized == "down" || normalized == "low" { return .inner(row: 2, col: 1) }
        if (normalized.contains("↓") || normalized.contains("down") || normalized.contains("low")) && normalized.contains("in") { return .inner(row: 2, col: 2) }
    }

    // Fallback for legacy labels without explicit Strike/Ball prefix:
    let row: Int? = {
        if normalized.contains("up") || normalized.contains("high") { return 0 }
        if normalized.contains("↓") || normalized.contains("low") || normalized.contains("down") { return 2 }
        if normalized.contains("middle") { return 1 }
        if normalized.contains("in") || normalized.contains("out") { return 1 }
        return nil
    }()

    let col: Int? = {
        if normalized.contains("out") { return 0 }
        if normalized.contains("middle") { return 1 }
        if normalized.contains("in") { return 2 }
        if normalized.contains("up") || normalized.contains("high") || normalized.contains("↓") || normalized.contains("low") || normalized.contains("down") {
            return 1
        }
        return nil
    }()

    guard let row, let col else { return nil }
    return .inner(row: row, col: col)
}

func buildHeatmapSummary(
    events: [PitchEvent],
    pitchType: String? = nil,
    calledStrikeOnly: Bool = false,
    source: HeatmapLocationSource
) -> HeatmapSummary {
    let filtered = events.filter { event in
        if let pitchType, !pitchType.isEmpty {
            return event.pitch == pitchType
        }
        return true
    }
    .filter { event in
        if calledStrikeOnly {
            return event.calledPitch?.isStrike == true
        }
        return true
    }

    var buckets: [String: Int] = [:]
    var outerCounts = Array(repeating: 0, count: 8)
    var total = 0
    for event in filtered {
        let rawLocation: String = {
            switch source {
            case .result:
                return event.location
            case .called:
                return event.calledPitch?.location ?? ""
            }
        }()
        guard let point = heatmapPoint(for: rawLocation) else { continue }
        switch point {
        case let .inner(row, col):
            let key = "\(row)-\(col)"
            buckets[key, default: 0] += 1
        case let .outer(index):
            guard outerCounts.indices.contains(index) else { break }
            outerCounts[index] += 1
        }
        total += 1
    }

    var cells: [HeatmapCell] = []
    var maxCount = 0
    for row in 0..<3 {
        for col in 0..<3 {
            let count = buckets["\(row)-\(col)"] ?? 0
            maxCount = max(maxCount, count)
            cells.append(HeatmapCell(row: row, col: col, count: count))
        }
    }
    let outerMaxCount = outerCounts.max() ?? 0

    return HeatmapSummary(
        cells: cells,
        outerCounts: outerCounts,
        maxCount: maxCount,
        outerMaxCount: outerMaxCount,
        totalCount: total
    )
}
