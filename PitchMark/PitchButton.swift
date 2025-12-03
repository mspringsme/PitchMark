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
    
    @ViewBuilder
    func menuContent(
        for adjustedLabel: String,
        tappedPoint: CGPoint,
        location: PitchLocation,
        setLastTapped: @escaping (CGPoint?) -> Void,
        setCalledPitch: @escaping (PitchCall?) -> Void,
        selectedPitches: Set<String>,
        pitchCodeAssignments: [PitchCodeAssignment],
        lastTappedPosition: CGPoint?,
        calledPitch: PitchCall?,
        setSelectedPitch: @escaping (String) -> Void
    ) -> some View {
        if selectedPitches.isEmpty {
            Button("Select pitches first") {}.disabled(true)
        } else {
            let orderedSelected: [String] = {
                let base = pitchOrder.filter { selectedPitches.contains($0) }
                let extras = Array(selectedPitches.subtracting(Set(pitchOrder))).sorted()
                return base + extras
            }()
            ForEach(orderedSelected, id: \.self) { pitch in
                let assignedCodes = pitchCodeAssignments
                    .filter { $0.pitch == pitch && $0.location == adjustedLabel }
                    .map(\.code)
                
                let codeSuffix = assignedCodes.isEmpty
                ? "     --"
                : "   \(assignedCodes.joined(separator: ", "))"
                
                Button("\(pitch)\(codeSuffix)") {
                    withAnimation {
                        setSelectedPitch(pitch)
                        
                        let newCall = PitchCall(
                            pitch: pitch,
                            location: adjustedLabel,
                            isStrike: location.isStrike,
                            codes: assignedCodes
                        )
                        
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
                    }
                }
            }
        }
    }
    
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
