//
//  PitchButton.swift
//  PitchMark
//
//  Created by Mark Springer on 10/13/25.
//
import SwiftUI

private struct PitchButtonView: View {
    let x: CGFloat
    let y: CGFloat
    let location: PitchLocation
    let labelManager: PitchLabelManager
    let lastTappedPosition: CGPoint?
    let setLastTapped: (CGPoint?) -> Void
    let setCalledPitch: (PitchCall?) -> Void
    let buttonSize: CGFloat
    let selectedPitches: Set<String>
    let pitchCodeAssignments: [PitchCodeAssignment]
    let calledPitch: PitchCall?
    let selectedPitch: String
    let gameIsActive: Bool
    let isRecordingResult: Bool
    let setIsRecordingResult: (Bool) -> Void
    let setActualLocation: (String) -> Void
    let actualLocationRecorded: String?
    let calledPitchLocation: String?
    let setSelectedPitch: (String) -> Void
    let resultVisualState: String?
    let setResultVisualState: (String?) -> Void
    let pendingResultLabel: Binding<String?>
    let showResultConfirmation: Binding<Bool>
    let showConfirmSheet: Binding<Bool>
    let onResultLocationPicked: (String) -> Void
    let isEncryptedMode: Bool
    let template: PitchTemplate?
    let canInitiateCall: Bool

    var body: some View {
        let tappedPoint = CGPoint(x: x, y: y)
        let isSelected = lastTappedPosition == tappedPoint
        let adjustedLabel = labelManager.adjustedLabel(from: location.label)
        let fullLabel = "\(location.isStrike ? "Strike" : "Ball") \(adjustedLabel)"
        let assignedCode = pitchCodeAssignments.first {
            $0.pitch == selectedPitch && $0.location == fullLabel
        }

        let isDisabled = gameIsActive && assignedCode == nil

        let assignedPitches = Set(
            pitchCodeAssignments
                .filter { $0.location == fullLabel && selectedPitches.contains($0.pitch) }
                .map(\.pitch)
        )
        // In encrypted mode, always render outline-only (no filled segments)
        let shouldOutline = isEncryptedMode ? true : (assignedPitches.isEmpty && !isRecordingResult)

        let segmentColors: [Color] = {
            // In encrypted mode, suppress filled segments entirely to show outline-only
            if isEncryptedMode {
                return []
            }
            if let resultLabel = resultVisualState {
                if fullLabel == resultLabel {
                    return [location.isStrike ? .green : .red]
                } else {
                    return [location.isStrike ? .green : .red]
                }
            } else if isRecordingResult {
                if fullLabel == calledPitchLocation {
                    return [colorForPitch(selectedPitch)]
                } else {
                    return [location.isStrike ? .green : .red]
                }
            } else if lastTappedPosition == tappedPoint {
                return [colorForPitch(selectedPitch)]
            } else {
                return Array(assignedPitches).map { colorForPitch($0) }
            }
        }()

        return Group {
            if isDisabled {
                disabledView(isStrike: location.isStrike)
                    .frame(width: buttonSize, height: buttonSize)
            } else if isRecordingResult {
                Button(action: {
                    print("🔆 fullLabel=", fullLabel)
                    pendingResultLabel.wrappedValue = fullLabel
                    onResultLocationPicked(fullLabel)
                    showConfirmSheet.wrappedValue = true
                }) {
                    StrikeZoneButtonLabel(
                        isStrike: location.isStrike,
                        isSelected: isSelected,
                        fullLabel: fullLabel,
                        segmentColors: segmentColors,
                        buttonSize: buttonSize,
                        isRecordingResult: isRecordingResult,
                        actualLocationRecorded: actualLocationRecorded,
                        calledPitchLocation: calledPitchLocation,
                        pendingResultLabel: pendingResultLabel.wrappedValue,
                        outlineOnly: shouldOutline
                    )
                }
                .buttonStyle(.plain)

            } else {
                Group {
                    if canInitiateCall {
                        Button(action: {
                            guard !selectedPitch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

                            let selected = selectedPitch
                            let assignedCodes = pitchCodeAssignments
                                .filter { $0.pitch == selected && $0.location == fullLabel }
                                .map(\.code)

                            let callCodes: [String] = {
                                guard isEncryptedMode else { return assignedCodes }
                                guard let template else { return [] }
                                let labelForGrid = adjustedLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard let (gridKind, columnIndex, rowIndex) = mapLabelToGridInfo(label: labelForGrid, isStrike: location.isStrike) else {
                                    return []
                                }
                                return EncryptedCodeGenerator.generateCalls(
                                    template: template,
                                    selectedPitch: selected,
                                    gridKind: gridKind,
                                    columnIndex: columnIndex,
                                    rowIndex: rowIndex
                                )
                            }()

                            let newCall = PitchCall(
                                pitch: selected,
                                location: adjustedLabel,
                                isStrike: location.isStrike,
                                codes: callCodes
                            )

                            // Never clear the active call via strike-zone re-tap in composer flow.
                            // Re-tap should keep/update call state, not dismiss the sheet.
                            setLastTapped(tappedPoint)
                            setCalledPitch(newCall)
                        }) {
                            ZStack {
                                StrikeZoneButtonLabel(
                                    isStrike: location.isStrike,
                                    isSelected: isSelected,
                                    fullLabel: fullLabel,
                                    segmentColors: segmentColors,
                                    buttonSize: buttonSize,
                                    isRecordingResult: isRecordingResult,
                                    actualLocationRecorded: actualLocationRecorded,
                                    calledPitchLocation: calledPitchLocation,
                                    pendingResultLabel: pendingResultLabel.wrappedValue,
                                    outlineOnly: shouldOutline
                                )
                            }
                            .padding(10)
                            .compositingGroup()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                    } else {
                        // Joiner: no pitch-selection menu
                        StrikeZoneButtonLabel(
                            isStrike: location.isStrike,
                            isSelected: isSelected,
                            fullLabel: fullLabel,
                            segmentColors: segmentColors,
                            buttonSize: buttonSize,
                            isRecordingResult: isRecordingResult,
                            actualLocationRecorded: actualLocationRecorded,
                            calledPitchLocation: calledPitchLocation,
                            pendingResultLabel: pendingResultLabel.wrappedValue,
                            outlineOnly: shouldOutline
                        )
                        .padding(10)
                        .compositingGroup()
                    }
                }
            }
        }
        .position(x: x, y: y)
        .zIndex(1)
    }

    private func mapLabelToGridInfo(label: String, isStrike: Bool) -> (gridKind: EncryptedGridKind, columnIndex: Int, rowIndex: Int)? {
        let cleaned = label.trimmingCharacters(in: .whitespacesAndNewlines)
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
            for (c, value) in row.enumerated() {
                if value == cleaned {
                    if !isStrike && value.isEmpty { return nil }
                    return (kind, c, r)
                }
            }
        }
        return nil
    }
}

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
    gameIsActive: Bool,
    isRecordingResult: Bool,
    setIsRecordingResult: @escaping (Bool) -> Void,
    setActualLocation: @escaping (String) -> Void,
    actualLocationRecorded: String?,
    calledPitchLocation: String?,
    setSelectedPitch: @escaping (String) -> Void,
    resultVisualState: String?,
    setResultVisualState: @escaping (String?) -> Void,
    pendingResultLabel: Binding<String?>,
    showResultConfirmation: Binding<Bool>,
    showConfirmSheet: Binding<Bool>,
    onResultLocationPicked: @escaping (String) -> Void,
    isEncryptedMode: Bool,
    template: PitchTemplate?,
    canInitiateCall: Bool
) -> some View {
    PitchButtonView(
        x: x,
        y: y,
        location: location,
        labelManager: labelManager,
        lastTappedPosition: lastTappedPosition,
        setLastTapped: setLastTapped,
        setCalledPitch: setCalledPitch,
        buttonSize: buttonSize,
        selectedPitches: selectedPitches,
        pitchCodeAssignments: pitchCodeAssignments,
        calledPitch: calledPitch,
        selectedPitch: selectedPitch,
        gameIsActive: gameIsActive,
        isRecordingResult: isRecordingResult,
        setIsRecordingResult: setIsRecordingResult,
        setActualLocation: setActualLocation,
        actualLocationRecorded: actualLocationRecorded,
        calledPitchLocation: calledPitchLocation,
        setSelectedPitch: setSelectedPitch,
        resultVisualState: resultVisualState,
        setResultVisualState: setResultVisualState,
        pendingResultLabel: pendingResultLabel,
        showResultConfirmation: showResultConfirmation,
        showConfirmSheet: showConfirmSheet,
        onResultLocationPicked: onResultLocationPicked,
        isEncryptedMode: isEncryptedMode,
        template: template,
        canInitiateCall: canInitiateCall
    )
}
