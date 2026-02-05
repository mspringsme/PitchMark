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
    let showConfirmSheet: Binding<Bool>
    let isEncryptedMode: Bool
    let template: PitchTemplate?
    let canInitiateCall: Bool

    @State private var showMenuSheet = false

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
                            showMenuSheet = true
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
                        .sheet(isPresented: $showMenuSheet) {
                            VStack(spacing: 12) {
                                HStack {
                                    Spacer(minLength: 0)
                                    HStack(spacing: 6) {
                                        Text(location.isStrike ? "Strike:  " : "Ball:  ")
                                            .font(.title)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.secondary)
                                        Text(labelManager.adjustedLabel(from: location.label))
                                            .font(.title)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.secondary)
                                    }
                                    .fixedSize()
                                    Spacer(minLength: 0)
                                }
                                .multilineTextAlignment(.center)

                                HStack {
                                    Spacer(minLength: 0)
                                    PitchMenuContent(
                                        adjustedLabel: adjustedLabel,
                                        tappedPoint: tappedPoint,
                                        location: location,
                                        setLastTapped: setLastTapped,
                                        setCalledPitch: setCalledPitch,
                                        selectedPitches: selectedPitches,
                                        pitchCodeAssignments: pitchCodeAssignments,
                                        lastTappedPosition: lastTappedPosition,
                                        calledPitch: calledPitch,
                                        setSelectedPitch: setSelectedPitch,
                                        isEncryptedMode: isEncryptedMode,
                                        generateEncryptedCodes: { selectedPitch, gridKind, columnIndex, rowIndex in
                                            if let template = template {
                                                return EncryptedCodeGenerator.generateCalls(
                                                    template: template,
                                                    selectedPitch: selectedPitch,
                                                    gridKind: gridKind,
                                                    columnIndex: columnIndex,
                                                    rowIndex: rowIndex
                                                )
                                            }
                                            return []
                                        },
                                        onSelection: {
                                            showMenuSheet = false
                                        }
                                    )
                                    .fixedSize(horizontal: true, vertical: false)
                                    Spacer(minLength: 0)
                                }
                                .padding(.bottom, 8)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .presentationDetents([.fraction(0.6), .medium])
                            .presentationDragIndicator(.visible)
                        }

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
    showConfirmSheet: Binding<Bool>,
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
        showConfirmSheet: showConfirmSheet,
        isEncryptedMode: isEncryptedMode,
        template: template,
        canInitiateCall: canInitiateCall
    )
}

