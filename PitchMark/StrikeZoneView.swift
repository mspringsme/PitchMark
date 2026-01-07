//
//  StrikeZoneView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/30/25.
//
import SwiftUI

struct StrikeZoneView: View {
    let width: CGFloat
    @Binding var isGame: Bool
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
    let isEncryptedMode: Bool
    let template: PitchTemplate?
    
    var body: some View {
        ZStack {
            Color.clear // 👈 forces fixed size
                    .frame(width: width, height: 390)
            GeometryReader { geo in
                let zoneWidth = geo.size.width * (isGame ? 0.47 : 0.431)
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
                            showConfirmSheet: showConfirmSheet,
                            isEncryptedMode: isEncryptedMode,
                            template: template
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
                        ("↓", originX + zoneWidth / 2, originY + zoneHeight + buttonSize * 0.75),
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
                            showConfirmSheet: showConfirmSheet,
                            isEncryptedMode: isEncryptedMode,
                            template: template
                        )
                    }
                }
            }
            .frame(width: width, height: 390)
        }
        .frame(width: width, height: 390) // ✅ Constrain the ZStack, not just the GeometryReader
//        .background(Color.white)
//        .cornerRadius(12)
    }
        
}

@ViewBuilder
func shapeView(isStrike: Bool, isSelected: Bool, overrideFill: Color? = nil, outlineOnly: Bool = false) -> some View {
    let isOverride = overrideFill != nil
    let baseColor = overrideFill ?? (isStrike ? Color.green : Color.red)
    let fillColor = isOverride ? baseColor : baseColor.opacity(isSelected ? 0.6 : 1.0)

    // Rotation state for animated gradient
    @State var rotation: Angle = .zero

    if outlineOnly {
        Circle()
            .stroke(baseColor, lineWidth: isSelected ? 5 : 4)
            .overlay(
                ZStack {
                    // Subtle static stroke to add definition
                    Circle()
                        .stroke(Color.black.opacity(0.6), lineWidth: isSelected ? 2 : 1.5)

                    // Glowing animated stroke when selected
                    if isSelected {
                        Circle()
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [.cyan, .magenta, .yellow, .lime, .orange]),
                                    center: .center,
                                    angle: rotation
                                ),
                                lineWidth: 6
                            )
                            .blur(radius: 2)
                            .onAppear {
                                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                                    rotation = .degrees(360)
                                }
                            }
                    }
                }
            )
            .scaleEffect(isSelected ? 1.3 : 1.0)
            .animation(.easeOut(duration: 2.0), value: isSelected)
    } else {
        Circle()
            .fill(fillColor)
            .overlay(
                ZStack {
                    // Static stroke
                    Circle()
                        .stroke(Color.black, lineWidth: isSelected ? 2 : 0)

                    // Glowing animated stroke
                    if isSelected {
                        Circle()
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [.cyan, .magenta, .yellow, .lime, .orange]),
                                    center: .center,
                                    angle: rotation
                                ),
                                lineWidth: 6
                            )
                            .blur(radius: 2)
                            .onAppear {
                                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                                    rotation = .degrees(360)
                                }
                            }
                    }
                }
            )
            .scaleEffect(isSelected ? 1.3    : 1.0)
            .animation(.easeOut(duration: 2.0), value: isSelected)
    }
}

@ViewBuilder
func disabledView(isStrike: Bool) -> some View {
    if isStrike {
        Circle().fill(Color.gray.opacity(0.3))
    } else {
        RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.3))
    }
    
}

extension Color {
    static let magenta = Color(red: 1.0, green: 0.0, blue: 1.0)
    static let lime = Color(red: 0.0, green: 1.0, blue: 0.0)
}

struct GlowingShapeView: View {
    let isStrike: Bool
    let isSelected: Bool
    let overrideFill: Color?
    let outlineOnly: Bool

    @State private var angle: Double = 0

    init(isStrike: Bool, isSelected: Bool, overrideFill: Color? = nil, outlineOnly: Bool = false) {
        self.isStrike = isStrike
        self.isSelected = isSelected
        self.overrideFill = overrideFill
        self.outlineOnly = outlineOnly
    }

    var body: some View {
        let isOverride = overrideFill != nil
        let baseColor = overrideFill ?? (isStrike ? Color.green : Color.red)
        let fillColor = isOverride ? baseColor : baseColor.opacity(isSelected ? 0.6 : 1.0)

        Group {
            if outlineOnly {
                Circle()
                    .stroke(baseColor, lineWidth: isSelected ? 5 : 4)
                    .modifier(RotatingGlowModifier(isSelected: isSelected, angle: angle))
            } else {
                Circle()
                    .fill(fillColor)
                    .modifier(RotatingGlowModifier(isSelected: isSelected, angle: angle))
            }
        }
        .scaleEffect(isSelected ? 1.3 : 1.0)
        .animation(.easeOut(duration: 2.0), value: isSelected)
        .onAppear {
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                angle = 360
            }
        }
    }
}
struct RotatingGlowModifier: AnimatableModifier {
    var isSelected: Bool
    var angle: Double

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content
            .overlay(
                ZStack {
                    Circle()
                        .stroke(Color.clear, lineWidth: isSelected ? 2 : 0)

                    if isSelected {
                        Circle()
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [.cyan, .magenta, .yellow, .lime, .orange]),
                                    center: .center,
                                    angle: .degrees(angle)
                                ),
                                lineWidth: 3
                            )
                            .blur(radius: 2)
                    }
                }
            )
    }
}
