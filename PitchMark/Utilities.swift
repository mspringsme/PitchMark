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

    var localPortraitImage: UIImage? {
        guard let id else { return nil }
        return localPitcherPortraitImage(for: id)
    }

    var avatarInitials: String {
        let parts = name
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
        let initials = parts.compactMap { $0.first }.map(String.init).joined()
        return initials.isEmpty ? "P" : initials.uppercased()
    }
}

private func localPitcherPortraitsDirectory() -> URL? {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return nil
    }
    return base.appendingPathComponent("PitchMark/PitcherPortraits", isDirectory: true)
}

func localPitcherPortraitURL(for pitcherId: String) -> URL? {
    guard !pitcherId.isEmpty, let directory = localPitcherPortraitsDirectory() else { return nil }
    return directory.appendingPathComponent("\(pitcherId).png")
}

func localPitcherPortraitImage(for pitcherId: String) -> UIImage? {
    guard let url = localPitcherPortraitURL(for: pitcherId),
          let data = try? Data(contentsOf: url) else {
        return nil
    }
    return UIImage(data: data)
}

func saveLocalPitcherPortrait(_ image: UIImage, pitcherId: String) -> Bool {
    guard let url = localPitcherPortraitURL(for: pitcherId) else { return false }
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let normalizedImage = image.normalizedUpOrientation()
        guard let data = normalizedImage.pngData() else { return false }
        try data.write(to: url, options: [.atomic])
        NotificationCenter.default.post(name: .pitcherPortraitDidChange, object: pitcherId)
        return true
    } catch {
        debugLog("❌ saveLocalPitcherPortrait failed: \(error.localizedDescription)")
        return false
    }
}

func copyLocalPitcherPortrait(from sourcePitcherId: String, to destinationPitcherId: String) {
    guard let sourceURL = localPitcherPortraitURL(for: sourcePitcherId),
          let destinationURL = localPitcherPortraitURL(for: destinationPitcherId) else {
        return
    }
    do {
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        NotificationCenter.default.post(name: .pitcherPortraitDidChange, object: destinationPitcherId)
    } catch {
        debugLog("⚠️ copyLocalPitcherPortrait failed: \(error.localizedDescription)")
    }
}

func removeLocalPitcherPortrait(pitcherId: String) {
    guard let url = localPitcherPortraitURL(for: pitcherId) else { return }
    try? FileManager.default.removeItem(at: url)
    NotificationCenter.default.post(name: .pitcherPortraitDidChange, object: pitcherId)
}

extension UIImage {
    func normalizedUpOrientation() -> UIImage {
        if imageOrientation == .up {
            return self
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func resizedToFit(maxDimension: CGFloat) -> UIImage {
        let largestDimension = max(size.width, size.height)
        guard largestDimension > maxDimension, largestDimension > 0 else {
            return self
        }

        let scaleFactor = maxDimension / largestDimension
        let targetSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

struct PitcherAvatarView: View {
    let pitcher: Pitcher?
    var size: CGFloat = 28
    @State private var refreshToken = UUID()

    private var accentColors: [Color] {
        [.indigo, .teal, .orange, .pink, .mint]
    }

    private var fallbackGradient: LinearGradient {
        let key = pitcher?.name.lowercased() ?? "pitcher"
        var hash = 0
        for scalar in key.unicodeScalars {
            hash = (hash &* 31) &+ Int(scalar.value)
        }
        let seed = abs(hash) % accentColors.count
        let first = accentColors[seed]
        let second = accentColors[(seed + 2) % accentColors.count]
        return LinearGradient(colors: [first, second], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(fallbackGradient)

            if let image = pitcher?.localPortraitImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(pitcher?.avatarInitials ?? "P")
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .onReceive(NotificationCenter.default.publisher(for: .pitcherPortraitDidChange)) { notification in
            guard let pitcherId = pitcher?.id,
                  let changedId = notification.object as? String,
                  changedId == pitcherId else { return }
            refreshToken = UUID()
        }
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
        debugLog("🔍 Lookup key: \(key)")
        
        if let image = imageMap[key] {
            return image
        } else {
            // Older call paths store the bare grid label ("Up & In") while the card assets
            // are keyed by the prefixed form ("Strike Up & In" / "Ball Up & In").
            let prefixedLocation = "\(isStrike ? "Strike" : "Ball") \(trimmedLocation)"
            let prefixedKey = "\(prefixedLocation)|\(batterSide.rawValue)"
            if let image = imageMap[prefixedKey] {
                debugLog("🔍 Fallback lookup key: \(prefixedKey)")
                return image
            }
            debugLog("⚠️ Missing image for key: \(key)")
            return "Bat"
        }
    }
}
