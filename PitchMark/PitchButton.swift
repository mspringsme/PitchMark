//
//  PitchButton.swift
//  PitchMark
//
//  Created by Mark Springer on 10/13/25.
//
import SwiftUI

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
    template: PitchTemplate?
) -> some View {
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
            Menu {
                PitchMenuContent(
                    adjustedLabel: fullLabel,
                    tappedPoint: tappedPoint,
                    location: location,
                    setLastTapped: setLastTapped,
                    setCalledPitch: setCalledPitch,
                    selectedPitches: selectedPitches,
                    pitchCodeAssignments: isEncryptedMode ? [] : pitchCodeAssignments,
                    lastTappedPosition: lastTappedPosition,
                    calledPitch: calledPitch,
                    setSelectedPitch: setSelectedPitch,
                    isEncryptedMode: isEncryptedMode,
                    generateEncryptedCodes: { selectedPitch, gridKind, columnIndex, rowIndex in
                        print("[PitchButton] Preparing encrypted generation for label=\(fullLabel) isStrike=\(location.isStrike) selectedPitch=\(selectedPitch)")
                        guard let template = template else {
                            print("[PitchButton] No template available for encrypted generation.")
                            return []
                        }
                        print("""
                        [PitchButton] Encrypted generate inputs
                        selectedPitch=\(selectedPitch)
                        kind=\(gridKind) col=\(columnIndex) row=\(rowIndex)
                        strikeTopRow=\(template.strikeTopRow)
                        ballsTopRow=\(template.ballsTopRow)
                        strikeRows count=\(template.strikeRows.count) firstRow=\(template.strikeRows.first ?? [])
                        ballsRows count=\(template.ballsRows.count) firstRow=\(template.ballsRows.first ?? [])
                        """)
                        let codes = EncryptedCodeGenerator.generateCalls(
                            template: template,
                            selectedPitch: selectedPitch,
                            gridKind: gridKind,
                            columnIndex: columnIndex,
                            rowIndex: rowIndex
                        )
                        print("[PitchButton] Summary kind=\(gridKind) col=\(columnIndex) row=\(rowIndex) → count=\(codes.count)")
                        print("[PitchButton] Encrypted generate output codes=\(codes)")

                        return codes
                    }
                )
            } label: {
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
        }
    }
    .position(x: x, y: y)
    .zIndex(1)
}

