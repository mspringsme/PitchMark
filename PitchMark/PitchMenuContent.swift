import Foundation
import SwiftUI

struct PitchMenuContent: View {
    let adjustedLabel: String
    let tappedPoint: CGPoint
    let location: PitchLocation
    let setLastTapped: (CGPoint?) -> Void
    let setCalledPitch: (PitchCall?) -> Void
    let selectedPitches: Set<String>
    let pitchCodeAssignments: [PitchCodeAssignment]
    let lastTappedPosition: CGPoint?
    let calledPitch: PitchCall?
    let setSelectedPitch: (String) -> Void
    let isEncryptedMode: Bool
    let generateEncryptedCodes: ((String, EncryptedGridKind, Int, Int) -> [String])?
    let onSelection: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            

            Group {
                if selectedPitches.isEmpty {
                    Button("Select pitches first") {}.disabled(true)
                } else {
                    let orderedSelected: [String] = {
                        let base = pitchOrder.filter { selectedPitches.contains($0) }
                        let extras = Array(selectedPitches.subtracting(Set(pitchOrder))).sorted()
                        return base + extras
                    }()

                    ForEach(orderedSelected, id: \.self) { (pitch: String) in
                        let assignedCodes = pitchCodeAssignments
                            .filter { $0.pitch == pitch && $0.location == adjustedLabel }
                            .map(\.code)

                        let codeSuffix = assignedCodes.isEmpty
                            ? "     --"
                            : "   \(assignedCodes.joined(separator: ", "))"

                        let isCurrent = lastTappedPosition == tappedPoint &&
                            calledPitch?.location == adjustedLabel &&
                            calledPitch?.pitch == pitch

                        Button {
                            withAnimation {
                                setSelectedPitch(pitch)

                                var newCallCodes: [String] = []

                                if isEncryptedMode {
                                    let labelForGrid = normalizedLabel(adjustedLabel, isStrike: location.isStrike)
                                    print("[PitchMenuContent] normalized label='\(labelForGrid)' from adjusted='\(adjustedLabel)' isStrike=\(location.isStrike)")
                                    if let (gridKind, columnIndex, rowIndex) = mapLabelToGridInfo(label: labelForGrid, isStrike: location.isStrike) {
                                        print("[PitchMenuContent] mapped → kind=\(gridKind) col=\(columnIndex) row=\(rowIndex)")
                                        // Attempt to generate encrypted codes if a generator is provided
                                        print("Encrypted mode: generating with gridKind=\(gridKind), col=\(columnIndex), row=\(rowIndex)")
                                        if let generator = generateEncryptedCodes {
                                            let generated = generator(pitch, gridKind, columnIndex, rowIndex)
                                            newCallCodes = generated
                                            print("Generated codes: \(generated)")
                                        } else {
                                            print("No generator provided. Skipping encrypted code generation.")
                                            newCallCodes = []
                                        }
                                    } else {
                                        print("[PitchMenuContent] mapping failed for adjusted='\(adjustedLabel)' normalized='\(labelForGrid)' isStrike=\(location.isStrike)")
                                        newCallCodes = []
                                    }
                                } else {
                                    newCallCodes = assignedCodes
                                    print("Assigned codes (non-encrypted): \(assignedCodes)")
                                }

                                let newCall = PitchCall(
                                    pitch: pitch,
                                    location: adjustedLabel,
                                    isStrike: location.isStrike,
                                    codes: newCallCodes
                                )
                                print("New call codes: \(newCall.codes)")

                                if lastTappedPosition == tappedPoint,
                                   let currentCall = calledPitch,
                                   currentCall.location == newCall.location,
                                   currentCall.pitch == newCall.pitch {
                                    setLastTapped(nil)
                                    setCalledPitch(nil)
                                } else {
                                    setLastTapped(tappedPoint)
                                    setCalledPitch(newCall)
                                }
                                onSelection?()
                            }
                        } label: {
                            Text("\(pitch)\(codeSuffix)")
                                .font(.system(size: 17, weight: isCurrent ? .semibold : .regular))
                                .foregroundColor(isCurrent ? .accentColor : .primary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func normalizedLabel(_ label: String, isStrike: Bool) -> String {
        // Trim and standardize whitespace/case for comparison
        let raw = label.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove common prefixes like "Ball " or "Strike " if present
        let lower = raw.lowercased()
        let stripped: String
        if lower.hasPrefix("ball ") {
            stripped = String(raw.dropFirst(5))
        } else if lower.hasPrefix("strike ") {
            stripped = String(raw.dropFirst(7))
        } else {
            stripped = raw
        }

        // Normalize arrow/down synonyms and spacing
        let replaced = stripped
            .replacingOccurrences(of: "Down", with: "↓", options: [.caseInsensitive])
            .replacingOccurrences(of: "down", with: "↓")
            .replacingOccurrences(of: " ", with: " ") // keep spaces consistent
            .replacingOccurrences(of: "&", with: "&") // keep ampersand

        // Map common wordy forms to canonical grid labels
        // Supported canonicals in grids:
        // "Up & Out", "Up", "Up & In",
        // "Out", "Middle", "In",
        // "↓ & Out", "↓", "↓ & In"
        let candidates = [replaced, stripped, raw]

        for cand in candidates {
            let c = cand.trimmingCharacters(in: .whitespacesAndNewlines)
            // Direct matches
            switch c {
            case "Up & Out", "Up", "Up & In", "Out", "Middle", "In", "↓ & Out", "↓", "↓ & In":
                return c
            default:
                break
            }
            // Wordy to canonical
            let lowerC = c.lowercased()
            if lowerC == "up and out" { return "Up & Out" }
            if lowerC == "up and in" { return "Up & In" }
            if lowerC == "down and out" { return "↓ & Out" }
            if lowerC == "down and in" { return "↓ & In" }
            if lowerC == "down" { return "↓" }
            if lowerC == "center" { return "Middle" }
            if lowerC == "middle" { return "Middle" }
            if lowerC == "out" { return "Out" }
            if lowerC == "in" { return "In" }
            if lowerC == "up" { return "Up" }
            if lowerC == "ball out" { return "Out" }
            if lowerC == "ball in" { return "In" }
            if lowerC == "ball up" { return "Up" }
            if lowerC == "ball down" { return "↓" }
            if lowerC == "strike out" { return "Out" }
            if lowerC == "strike in" { return "In" }
            if lowerC == "strike up" { return "Up" }
            if lowerC == "strike down" { return "↓" }
            if lowerC == "ball up & out" || lowerC == "ball up and out" { return "Up & Out" }
            if lowerC == "ball up & in" || lowerC == "ball up and in" { return "Up & In" }
            if lowerC == "ball down & out" || lowerC == "ball down and out" { return "↓ & Out" }
            if lowerC == "ball down & in" || lowerC == "ball down and in" { return "↓ & In" }
            if lowerC == "strike up & out" || lowerC == "strike up and out" { return "Up & Out" }
            if lowerC == "strike up & in" || lowerC == "strike up and in" { return "Up & In" }
            if lowerC == "strike down & out" || lowerC == "strike down and out" { return "↓ & Out" }
            if lowerC == "strike down & in" || lowerC == "strike down and in" { return "↓ & In" }
        }

        // Fallback: return stripped version so mapping may still succeed if already canonical
        return stripped
    }

    private func mapLabelToGridInfo(label: String, isStrike: Bool) -> (gridKind: EncryptedGridKind, columnIndex: Int, rowIndex: Int)? {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let strikeRows = [
            ["Up & Out", "Up", "Up & In"],
            ["Out", "Middle", "In"],
            ["↓ & Out", "↓", "↓ & In"]
        ]
        let ballRows = [
            ["Up & Out", "Up", "Up & In"],
            ["Out", "", "In"],
            ["↓ & Out", "↓", "↓ & In"]
        ]
        let rows = isStrike ? strikeRows : ballRows
        let kind: EncryptedGridKind = isStrike ? .strikes : .balls
        for (r, row) in rows.enumerated() {
            for (c, val) in row.enumerated() {
                if val == label {
                    if !isStrike && val.isEmpty { return nil }
                    return (kind, c, r)
                }
            }
        }
        return nil
    }
}

