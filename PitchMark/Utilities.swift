//
//  Utilities.swift
//  PitchMark
//
//  Created by Mark Springer on 9/30/25.
//

import SwiftUI
import UIKit

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

struct StrikeZoneButtonLabel: View {
    let isStrike: Bool
    let isSelected: Bool
    let fullLabel: String
    let segmentColors: [Color]
    let buttonSize: CGFloat
    let isRecordingResult: Bool
    let actualLocationRecorded: String?
    let calledPitchLocation: String?
    let pendingResultLabel: String?
    let outlineOnly: Bool

    var body: some View {
        
        let isResultSelected = pendingResultLabel == fullLabel
        
        let isFaded = isRecordingResult && !isResultSelected
        let isCalledPitch = calledPitchLocation?.trimmingCharacters(in: .whitespacesAndNewlines) == fullLabel
        let overrideFill: Color? = isCalledPitch ? (segmentColors.first ?? .gray) : nil
        
        return ZStack {
            GlowingShapeView(isStrike: isStrike, isSelected: isSelected, overrideFill: overrideFill, outlineOnly: outlineOnly)

            if !outlineOnly && !segmentColors.isEmpty {
                PieChartView(segments: segmentColors)
                    .frame(width: buttonSize, height: buttonSize)
                    .opacity(1)
                    .animation(.easeInOut(duration: 0.2), value: segmentColors)
            }

            Text(fullLabel)
                .font(.system(size: buttonSize * 0.24, weight: .semibold))
                .foregroundColor(outlineOnly ? Color.primary.opacity(0.7) : .white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .padding(4)
        }
        .frame(width: buttonSize, height: buttonSize)
        .contentShape(Rectangle())
        .opacity(isFaded ? 0.4 : 1)
        .compositingGroup()
    }
}

struct PieChartView: View {
    let segments: [Color]

    var body: some View {
        if segments.isEmpty {
            Color.clear
        } else {
            GeometryReader { geo in
                let radius = min(geo.size.width, geo.size.height) / 2
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let sliceCount = segments.count
                let anglePerSlice = 2 * .pi / Double(sliceCount)

                ZStack {
                    ForEach(segments.indices, id: \.self) { index in
                        let startAngle = anglePerSlice * Double(index) - .pi / 2
                        let endAngle = startAngle + anglePerSlice

                        Path { path in
                            path.move(to: center)
                            path.addArc(center: center,
                                        radius: radius,
                                        startAngle: Angle(radians: startAngle),
                                        endAngle: Angle(radians: endAngle),
                                        clockwise: false)
                            path.closeSubpath()
                        }
                        .fill(segments[index])
                    }
                }
            }
        }
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

struct GridLocation: Identifiable {
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

struct PitchCodeAssignment: Hashable {
    let code: String
    let pitch: String
    let location: String
}

struct PitchTemplate: Identifiable, Hashable {
    let id: UUID
    var name: String
    var pitches: [String]
    var codeAssignments: [PitchCodeAssignment]
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
struct PitchImageGridPreview: View {
    let locations = [
        "Middle", "High", "Low",
        "Up & In", "Up & Out",
        "↓ & In", "↓ & Out",
        "In", "Out", "Up" // include "Up" if it's used
    ]
    
    struct Combo: Identifiable {
        let id = UUID()
        let location: String
        let isStrike: Bool
        let side: PitchMark.BatterSide
    }
    
    func allCombinations() -> [Combo] {
        let sides: [PitchMark.BatterSide] = [.right, .left]
        let strikeStates: [Bool] = [true, false]
        
        return sides.flatMap { side in
            strikeStates.flatMap { isStrike in
                locations.map { location in
                    Combo(location: location, isStrike: isStrike, side: side)
                }
            }
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(120), spacing: 16), count: 3), spacing: 24) {
                ForEach(allCombinations()) { combo in
                    let imageName = PitchImageDictionary.imageName(
                        for: combo.location,
                        isStrike: combo.isStrike,
                        batterSide: combo.side
                    )
                    
                    let isMissing = imageName == "Bat"
                    
                    VStack(spacing: 8) {
                        Text(imageName)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .frame(width: 100)
                        Image(imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 100)
                            .border(isMissing ? Color.red : Color.gray.opacity(0.3), width: 2)
                        Text("\(combo.isStrike ? "Strike" : "Ball") \(combo.location)\n[\(combo.side.rawValue)]")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
    }
}

