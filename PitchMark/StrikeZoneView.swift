//
//  StrikeZoneView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/30/25.
//
import SwiftUI

struct StrikeZoneView: View {
    let batterSide: BatterSide
    let lastTappedPosition: CGPoint?
    let setLastTapped: (CGPoint?) -> Void
    let calledPitch: PitchCall?
    let setCalledPitch: (PitchCall?) -> Void
    let selectedPitches: Set<String>
    let gameIsActive: Bool
    let selectedPitch: String
    let pitchCodeAssignments: [PitchCodeAssignment]
    let isRecordingResult: Bool
    let setIsRecordingResult: (Bool) -> Void
    let setActualLocation: (String) -> Void
    let actualLocationRecorded: String?
    let setSelectedPitch: (String) -> Void
    let resultVisualState: String?
    let setResultVisualState: (String?) -> Void
    let pendingResultLabel: Binding<String?>
    let showResultConfirmation: Binding<Bool>
    let showConfirmSheet: Binding<Bool>
    
    var body: some View {
        GeometryReader { geo in
        let zoneWidth = geo.size.width * 0.4
        let zoneHeight = geo.size.height * 0.6
        let cellWidth = zoneWidth / 3
        let cellHeight = zoneHeight / 3
        let buttonSize = min(cellWidth, cellHeight) * 0.8
        let originX = (geo.size.width - zoneWidth) / 2
        let originY: CGFloat = 60
        let labelManager = PitchLabelManager(batterSide: batterSide)
        
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .stroke(Color.black, lineWidth: 2)
                    .frame(width: zoneWidth, height: zoneHeight)
                    .position(x: originX + zoneWidth / 2, y: originY + zoneHeight / 2)
                
                // Strike zone buttons
                ForEach(strikeGrid) { loc in
                    let x = originX + CGFloat(loc.col) * cellWidth + cellWidth / 2
                    let y = originY + CGFloat(loc.row) * cellHeight + cellHeight / 2
                    
                    pitchButton(
                        x: x,
                        y: y,
                        location: .init(label: loc.label, isStrike: true),
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
                        calledPitchLocation: calledPitch?.location,
                        setSelectedPitch: setSelectedPitch,
                        resultVisualState: resultVisualState,
                        setResultVisualState: setResultVisualState,
                        pendingResultLabel: pendingResultLabel,
                        showConfirmSheet: showConfirmSheet
                    )
                }
                
                // Ball zone buttons
                let ballLocations: [(String, CGFloat, CGFloat)] = [
                    ("Up & Out", originX - buttonSize * 0.6, originY - buttonSize * 0.6),
                    ("Up", originX + zoneWidth / 2, originY - buttonSize * 0.75),
                    ("Up & In", originX + zoneWidth + buttonSize * 0.6, originY - buttonSize * 0.6),
                    ("Out", originX - buttonSize * 0.75, originY + zoneHeight / 2),
                    ("In", originX + zoneWidth + buttonSize * 0.75, originY + zoneHeight / 2),
                    ("↓ & Out", originX - buttonSize * 0.6, originY + zoneHeight + buttonSize * 0.6),
                    ("↓ ", originX + zoneWidth / 2, originY + zoneHeight + buttonSize * 0.75),
                    ("↓ & In", originX + zoneWidth + buttonSize * 0.6, originY + zoneHeight + buttonSize * 0.6)
                ]
                
                ForEach(ballLocations, id: \.0) { label, x, y in
                    pitchButton(
                        x: x,
                        y: y,
                        location: .init(label: label, isStrike: false),
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
                        calledPitchLocation: calledPitch?.location,
                        setSelectedPitch: setSelectedPitch,
                        resultVisualState: resultVisualState,
                        setResultVisualState: setResultVisualState,
                        pendingResultLabel: pendingResultLabel,
                        showConfirmSheet: showConfirmSheet // ✅ This is the new binding
                    )
                }
            }
        }
    }
}

@ViewBuilder
func shapeView(isStrike: Bool, isSelected: Bool, overrideFill: Color? = nil) -> some View {
    let isOverride = overrideFill != nil
    let baseColor = overrideFill ?? (isStrike ? Color.green : Color.red)
    let fillColor = isOverride ? baseColor : baseColor.opacity(isSelected ? 0.6 : 1.0)

    Circle()
        .fill(fillColor)
        .overlay(
            Circle()
                .stroke(Color.black, lineWidth: isSelected ? 3 : 0)
        )
        .shadow(color: isSelected ? Color.blue.opacity(0.8) : .clear, radius: isSelected ? 15 : 0)
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.easeOut(duration: 0.2), value: isSelected)
}

@ViewBuilder
func disabledView(isStrike: Bool) -> some View {
    if isStrike {
        Circle().fill(Color.gray.opacity(0.3))
    } else {
        RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.3))
    }
    
}
