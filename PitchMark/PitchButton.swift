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
    showConfirmSheet: Binding<Bool>
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
    let shouldOutline = assignedPitches.isEmpty && !isRecordingResult

    let segmentColors: [Color] = {
        if let resultLabel = resultVisualState {
            if fullLabel == resultLabel {
                return [location.isStrike ? .green : .red]
            } else {
                return [location.isStrike ? .green : .red]
            }
        } else if isRecordingResult {
            if fullLabel == calledPitchLocation {
                return [pitchColors[selectedPitch] ?? .gray]
            } else {
                return [location.isStrike ? .green : .red]
            }
        } else if lastTappedPosition == tappedPoint {
            return [pitchColors[selectedPitch] ?? .gray]
        } else {
            return Array(assignedPitches).compactMap { pitchColors[$0] }
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
                menuContent(
                    for: fullLabel,
                    tappedPoint: tappedPoint,
                    location: location,
                    setLastTapped: setLastTapped,
                    setCalledPitch: setCalledPitch,
                    selectedPitches: selectedPitches,
                    pitchCodeAssignments: pitchCodeAssignments,
                    lastTappedPosition: lastTappedPosition,
                    calledPitch: calledPitch,
                    setSelectedPitch: setSelectedPitch // ✅ Pass it in
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

