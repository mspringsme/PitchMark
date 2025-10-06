//
//  Utilities.swift
//  PitchMark
//
//  Created by Mark Springer on 9/30/25.
//

import SwiftUI

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
    .init(row: 2, col: 1, label: "↓ "),
    .init(row: 2, col: 2, label: "↓ & In")
]

let allPitches = ["2 Seam", "4 Seam", "Change", "Curve", "Screw", "Smile", "Drop", "Rise", "Pipe"]
let pitchOrder: [String] = [
    "2 Seam", "4 Seam", "Change", "Curve", "Drop", "Pipe", "Rise", "Screw", "Smile" 
]
func pitchButton(
    x: CGFloat,
    y: CGFloat,
    location: PitchLocation,
    labelManager: PitchLabelManager,
    lastTappedPosition: CGPoint?,
    setLastTapped: @escaping (CGPoint?) -> Void,
    setCalledPitch: @escaping (PitchCall?) -> Void,
    buttonSize: CGFloat,
    selectedPitches: Set<String>,
    pitchCodeAssignments: [PitchCodeAssignment],
    calledPitch: PitchCall?,
    selectedPitch: String,
    gameIsActive: Bool
) -> some View {
    let tappedPoint = CGPoint(x: x, y: y)
    let isSelected = lastTappedPosition == tappedPoint
    let adjustedLabel = labelManager.adjustedLabel(from: location.label)
    let fullLabel = "\(location.isStrike ? "Strike" : "Ball") \(adjustedLabel)"

    let assignedCode = pitchCodeAssignments.first {
        $0.pitch == selectedPitch && $0.location == fullLabel
    }

    let isDisabled = gameIsActive && assignedCode == nil

    let assignedPitches = pitchCodeAssignments
        .filter { $0.location == fullLabel }
        .map(\.pitch)

    let segmentColors = assignedPitches
        .compactMap { pitchColors[$0] }

    return Group {
        if isDisabled {
            disabledView(isStrike: location.isStrike)
                .frame(width: buttonSize, height: buttonSize)
                .position(x: x, y: y)
                .zIndex(1)
        }

        Menu {
            menuContent(
                for: fullLabel,
                tappedPoint: tappedPoint,
                location: location,
                setLastTapped: setLastTapped,
                setCalledPitch: setCalledPitch,
                selectedPitches: selectedPitches,
                pitchCodeAssignments: pitchCodeAssignments,
                lastTappedPosition: lastTappedPosition,
                calledPitch: calledPitch
            )
        } label: {
            StrikeZoneButtonLabel(
                isStrike: location.isStrike,
                isSelected: isSelected,
                fullLabel: fullLabel,
                segmentColors: segmentColors,
                buttonSize: buttonSize
            )
        }
        .position(x: x, y: y)
        .zIndex(1)
    }
}

func allLocationsFromGrid() -> [String] {
    strikeGrid.map(\.label) + [
        "Up & Out", "Up", "Up & In",
        "Out", "In",
        "↓ & Out", "↓ ", "↓ & In"
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
    case "↓ ":            return "↓ "
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

    var body: some View {
        ZStack {
            shapeView(isStrike: isStrike, isSelected: isSelected)

            if !segmentColors.isEmpty {
                PieChartView(segments: segmentColors)
                    .frame(width: buttonSize, height: buttonSize)
                    .opacity(1.0)
            }

            Text(fullLabel)
                .font(.system(size: buttonSize * 0.24, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .padding(4)
        }
        .frame(width: buttonSize, height: buttonSize)
        .contentShape(Rectangle())
    }
}

struct PieChartView: View {
    let segments: [Color]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(segments.indices, id: \.self) { index in
                    let startAngle = Angle(degrees: Double(index) / Double(segments.count) * 360)
                    let endAngle = Angle(degrees: Double(index + 1) / Double(segments.count) * 360)

                    Path { path in
                        let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                        path.move(to: center)
                        path.addArc(center: center,
                                    radius: geo.size.width / 2,
                                    startAngle: startAngle,
                                    endAngle: endAngle,
                                    clockwise: false)
                    }
                    .fill(segments[index])
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
            "↓ & Out", "↓ ", "↓ & In"
        ]
        ballFull = ballRaw.map { factory.fullLabel(prefix: "Ball", rawLabel: $0) }
    }
}



struct PitchCall {
    let pitch: String
    let location: String
    let isStrike: Bool
    let codes: [String]  // ✅ Use array instead of single code

    var type: String {
        isStrike ? "Strike" : "Ball"
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
            "↓ & In", "↓ ", "↓ & Out"
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


enum BatterSide: String, CaseIterable, Identifiable {
    case left, right
    
    var id: String { rawValue }
    
    var displayName: String {
        "\(self == .left ? "Left" : "Right")-Handed Batter"
    }
    
    var opposite: BatterSide {
        self == .left ? .right : .left
    }
}



extension PitchCall {
    var displayTitle: String { "\(type) \(location)" } // location will now already be "Up & In" style
    var shortLabel: String { "\(pitch) — \(displayTitle)" }
}
