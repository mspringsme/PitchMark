//
//  PitchResultsSheetView.swift
//  PitchMark
//
//  Created by Mark Springer on 11/2/25.
//
import SwiftUI
import UIKit

private enum OverlaySelection {
    case field, hr, foul
}

private struct ColorKey: Hashable {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8
}

private func colorKey(from color: UIColor) -> ColorKey {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return ColorKey(r: UInt8((r * 255.0).rounded()),
                    g: UInt8((g * 255.0).rounded()),
                    b: UInt8((b * 255.0).rounded()),
                    a: UInt8((a * 255.0).rounded()))
}

private extension UIImage {
    func pixelColor(at point: CGPoint) -> UIColor? {
        guard let cgImage = self.cgImage else { return nil }
        guard Int(point.x) >= 0, Int(point.y) >= 0, Int(point.x) < cgImage.width, Int(point.y) < cgImage.height else { return nil }
        guard let dataProvider = cgImage.dataProvider, let data = dataProvider.data else { return nil }
        let ptr = CFDataGetBytePtr(data)
        let bytesPerPixel = 4
        let bytesPerRow = cgImage.bytesPerRow
        let offset = Int(point.y) * bytesPerRow + Int(point.x) * bytesPerPixel
        let r = ptr![offset]
        let g = ptr![offset + 1]
        let b = ptr![offset + 2]
        let a = ptr![offset + 3]
        return UIColor(red: CGFloat(r) / 255.0,
                       green: CGFloat(g) / 255.0,
                       blue: CGFloat(b) / 255.0,
                       alpha: CGFloat(a) / 255.0)
    }
}

private struct OutcomeButton: View {
    let label: String
    @Binding var selectedOutcome: String?
    @Binding var selectedDescriptor: String?
    let isDisabled: Bool
    let usesDescriptorSelection: Bool

    var body: some View {
        let isSelected: Bool = {
            usesDescriptorSelection
                ? selectedDescriptor == label
                : selectedOutcome == label
        }()

        Button(action: {
            if usesDescriptorSelection {
                selectedDescriptor = (selectedDescriptor == label) ? nil : label
            } else {
                selectedOutcome = (selectedOutcome == label) ? nil : label
            }
        }) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 36) // 👈 Shorter height
                .background(isSelected ? Color(red: 0.75, green: 0.85, blue: 1.0) : Color.gray.opacity(0.1))
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2) // 👈 Add shadow
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
        .contentShape(Rectangle())
    }
}

private struct ToggleSection: View {
    @Binding var isStrikeSwinging: Bool
    @Binding var isStrikeLooking: Bool
    @Binding var isWildPitch: Bool
    @Binding var isPassedBall: Bool
    @Binding var isBall: Bool
    @Binding var isHitBatter: Bool
    @Binding var selectedOutcome: String?

    private func toggleButton(
        _ title: String,
        isOn: Bool,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(isOn ? Color(red: 0.75, green: 0.85, blue: 1.0) : Color.gray.opacity(0.1))
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Strike:")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)

                toggleButton("Swinging", isOn: isStrikeSwinging) {
                    let next = !isStrikeSwinging
                    isStrikeSwinging = next
                    if next { isStrikeLooking = false }
                }
                .frame(width: 98)

                toggleButton("Looking", isOn: isStrikeLooking) {
                    let next = !isStrikeLooking
                    isStrikeLooking = next
                    if next { isStrikeSwinging = false }
                }
                .frame(width: 98)

                toggleButton("Ball", isOn: isBall) {
                    isBall.toggle()
                }
                .frame(width: 86)

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                toggleButton("Wild Pitch", isOn: isWildPitch) {
                    let next = !isWildPitch
                    isWildPitch = next
                    if next { isPassedBall = false }
                }

                toggleButton("Passed Ball", isOn: isPassedBall) {
                    let next = !isPassedBall
                    isPassedBall = next
                    if next { isWildPitch = false }
                }

                toggleButton("Hit Batter", isOn: isHitBatter) {
                    let next = !isHitBatter
                    isHitBatter = next
                    if next {
                        selectedOutcome = "1B"
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal)
    }
}

private struct HoldActionButton: View {
    let title: String
    let systemImage: String
    let foregroundColor: Color
    let tint: Color
    let isEnabled: Bool
    let action: () -> Void

    @State private var holdProgress: CGFloat = 0
    private let holdDuration: Double = 0.65

    var body: some View {
        let shape = Capsule()

        Label(title, systemImage: systemImage)
            .foregroundColor(isEnabled ? foregroundColor : .gray)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                shape
                    .fill(isEnabled ? tint : Color(.systemGray5))
            )
            .contentShape(shape)
        .fixedSize()
        .overlay {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    shape
                        .fill(Color.clear)

                    shape
                        .fill((isEnabled ? foregroundColor : .gray).opacity(0.18))
                        .frame(width: geo.size.width * holdProgress)
                }
            }
            .clipShape(shape)
            .allowsHitTesting(false)
        }
        .overlay {
            shape
                .stroke((isEnabled ? foregroundColor : .gray).opacity(holdProgress > 0 ? 0.7 : 0.25), lineWidth: holdProgress > 0 ? 2 : 1)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.15), value: isEnabled)
        .opacity(isEnabled ? 1 : 0.75)
        .onLongPressGesture(
            minimumDuration: holdDuration,
            maximumDistance: 24,
            pressing: { pressing in
                guard isEnabled else {
                    holdProgress = 0
                    return
                }
                withAnimation(pressing ? .linear(duration: holdDuration) : .easeOut(duration: 0.15)) {
                    holdProgress = pressing ? 1 : 0
                }
            },
            perform: {
                guard isEnabled else { return }
                holdProgress = 0
                action()
            }
        )
    }
}

struct PitchResultSheetView: View {
    @Binding var isPresented: Bool
    @Binding var isStrikeSwinging: Bool
    @Binding var isStrikeLooking: Bool
    @Binding var isWildPitch: Bool
    @Binding var isPassedBall: Bool
    @Binding var isBall: Bool
    @Binding var selectedOutcome: String?
    @Binding var selectedDescriptor: String?
    @Binding var isError: Bool
    @State private var isHitBatter = false

    @State private var battedBallRegionName: String? = nil
    @State private var battedBallSelection: OverlaySelection? = nil
    @State private var battedBallTapNormalized: CGPoint? = nil

    @State private var showFieldOverlay: Bool = false

    @State private var colorMapImage: UIImage? = UIImage(named: "colorMap")

    // Map specific RGBA keys from the colorMap to semantic results. Update these to match your asset.
    private let colorMapping: [ColorKey: (selection: OverlaySelection, label: String, outcome: String?)] = [
        ColorKey(r: 0xE6, g: 0x19, b: 0x4B, a: 0xFF): (.hr, "Left Field HR", "HR"),
        ColorKey(r: 0x91, g: 0x1E, b: 0xB4, a: 0xFF): (.foul, "Foul Left", nil),
        ColorKey(r: 0xDC, g: 0xBE, b: 0xFF, a: 0xFF): (.field, "Deep Center", nil),
        
        
        ColorKey(r: 0xBF, g: 0xEF, b: 0x45, a: 0xFF): (.field, "Deep Left", nil),
        ColorKey(r: 0x4e, g: 0x51, b: 0x2e, a: 0xFF): (.field, "Deep Right", nil),
        ColorKey(r: 0x42, g: 0xd4, b: 0xf4, a: 0xFF): (.field, "Shallow Left", nil),
        ColorKey(r: 0xf7, g: 0x81, b: 0xbf, a: 0xFF): (.field, "Shallow Center", nil),
        ColorKey(r: 0x00, g: 0x00, b: 0x75, a: 0xFF): (.field, "Shallow Right", nil),
        ColorKey(r: 0x80, g: 0x80, b: 0x00, a: 0xFF): (.field, "3B area", nil),
        ColorKey(r: 0xff, g: 0xd8, b: 0xb1, a: 0xFF): (.field, "SS area", nil),
        ColorKey(r: 0xff, g: 0xe1, b: 0x19, a: 0xFF): (.field, "2B area", nil),
        ColorKey(r: 0xaa, g: 0x6e, b: 0x28, a: 0xFF): (.field, "1B area", nil),
        ColorKey(r: 0xfa, g: 0xbe, b: 0x28, a: 0xFF): (.field, "Front of 3B", nil),
        ColorKey(r: 0x00, g: 0x80, b: 0x80, a: 0xFF): (.field, "Front of catcher", nil),
        ColorKey(r: 0xe6, g: 0xbe, b: 0xff, a: 0xFF): (.field, "Front of 1B", nil),
        ColorKey(r: 0x80, g: 0x00, b: 0x00, a: 0xFF): (.field, "Pitcher", nil),
        ColorKey(r: 0xf0, g: 0x32, b: 0xe6, a: 0xFF): (.foul, "Foul Right", nil),
        ColorKey(r: 0xf5, g: 0x82, b: 0x31, a: 0xFF): (.foul, "Foul Left field", nil),
        ColorKey(r: 0xd2, g: 0xf5, b: 0x3c, a: 0xFF): (.foul, "Foul Right field", nil),
        ColorKey(r: 0x46, g: 0xf0, b: 0xf0, a: 0xFF): (.foul, "Foul behind", nil),
        ColorKey(r: 0x3c, g: 0xb4, b: 0x4B, a: 0xFF): (.hr, "Center Field HR", "HR"),
        ColorKey(r: 0x00, g: 0x82, b: 0xc8, a: 0xFF): (.hr, "Right Field HR", "HR")
    ]

    let pendingResultLabel: String?
    let pitchCall: PitchCall?
    let batterSide: BatterSide
    let selectedTemplateId: String?
    let currentMode: PitchMode
    let selectedGameId: String?
    let selectedOpponentJersey: String?
    let selectedOpponentBatterId: String?
    let selectedPracticeId: String?
    let selectedPitcherId: String?
    let saveAction: (PitchEvent) -> Void
    let template: PitchTemplate?
    let pitcherName: String?

    private func resetSelections() {
        isStrikeSwinging = false
        isStrikeLooking = false
        isWildPitch = false
        isPassedBall = false
        isBall = false
        isHitBatter = false
        selectedOutcome = nil
        selectedDescriptor = nil
        isError = false
        battedBallRegionName = nil
        battedBallSelection = nil
        battedBallTapNormalized = nil
    }

    private func isOutcomeDisabled(_ label: String) -> Bool {
        if selectedOutcome == "ꓘ" && label == "Foul" {
            return true
        }
        // Determine if any of the top toggles are selected
        let anyTopToggle = isStrikeSwinging || isStrikeLooking || isWildPitch || isPassedBall || isBall
        // Determine if either strike toggle is selected
        let anyStrikeToggle = isStrikeSwinging || isStrikeLooking
        // Determine if either K or backwards K is selected
        let isKSelected = selectedOutcome == "K" || selectedOutcome == "ꓘ"

        // Descriptor group (mutually exclusive within the group, but can co-exist with base outcome)
        let descriptorGroup: Set<String> = ["Pop", "Line", "Fly", "Grounder", "Bunt"]
        // Base outcome group that should be mutually exclusive among themselves
        let baseOutcomeGroup: Set<String> = ["1B", "2B", "3B", "HR"]

        // Special rule: If HR is selected, only Line and Fly remain available.
        // Keep HR itself enabled so the user can deselect it.
        if selectedOutcome == "HR" {
            let allowedWhenHR: Set<String> = ["HR", "Line", "Fly"]
            return !allowedWhenHR.contains(label)
        }
        

        // 1) Require strike toggles to enable K buttons
        if label == "K" {
            return !isStrikeSwinging
        }
        if label == "ꓘ" {
            return !isStrikeLooking
        }

        // 2) If K or backwards K is selected, deactivate all other buttons except 1B, E, Foul.
        //    K/ꓘ must remain active to allow deselection.
        if isKSelected {
            if label == "K" || label == "ꓘ" { return false }
            if label == "1B" || label == "E" || label == "Foul" { return false }
            return true
        }

        // 2) If any top toggle is on, disable descriptor group only (per earlier rule)
        if anyTopToggle && descriptorGroup.contains(label) {
            return true
        }

        // 3) If either strike toggle is on, also deactivate BB
        if anyStrikeToggle && (label == "BB" || label == "Walk") {
            return true
        }

        // 4) Do not disable descriptor or base groups due to each other — co-selection is allowed.
        if descriptorGroup.contains(label) || baseOutcomeGroup.contains(label) {
            return false
        }

        return false
    }

    private func handleSave() {
        guard let event = buildCurrentEvent() else {
            isPresented = false
            return
        }
        event.debugLog()
        saveAction(event)
        isPresented = false
        resetSelections()
    }

    private func handlePitchOnlySave() {
        guard let event = buildCurrentEvent() else {
            isPresented = false
            return
        }
        event.debugLog(prefix: "📤 Saving Pitch-Only PitchEvent")
        saveAction(event)
        isPresented = false
        resetSelections()
    }

    private func buildCurrentEvent() -> PitchEvent? {
        guard let label = pendingResultLabel,
              let pitchCall = pitchCall else {
            return nil
        }

        return PitchEvent(
            id: nil,
            timestamp: Date(),
            pitch: pitchCall.pitch,
            location: label,
            codes: pitchCall.codes,
            isStrike: pitchCall.isStrike,
            isBall: isBall,
            mode: currentMode,
            calledPitch: pitchCall,
            batterSide: batterSide,
            templateId: selectedTemplateId,
            strikeSwinging: isStrikeSwinging,
            wildPitch: isWildPitch,
            passedBall: isPassedBall,
            strikeLooking: isStrikeLooking,
            outcome: isHitBatter ? "HBP" : selectedOutcome,
            descriptor: selectedDescriptor,
            errorOnPlay: isError,
            battedBallRegion: battedBallRegionName,
            battedBallType: {
                switch battedBallSelection {
                case .hr?: return "HR"
                case .foul?: return "Foul"
                case .field?: return "Field"
                case nil: return nil
                }
            }(),
            battedBallTapX: battedBallTapNormalized.map { Double($0.x) },
            battedBallTapY: battedBallTapNormalized.map { Double($0.y) },
            gameId: selectedGameId,
            opponentJersey: selectedOpponentJersey,
            opponentBatterId: selectedOpponentBatterId,
            practiceId: selectedPracticeId,
            pitcherId: selectedPitcherId
        )
    }

    private struct OutcomeChangeHandlers: ViewModifier {
        @Binding var isPresented: Bool
        @Binding var isStrikeSwinging: Bool
        @Binding var isStrikeLooking: Bool
        @Binding var isWildPitch: Bool
        @Binding var isPassedBall: Bool
        @Binding var isBall: Bool
        @Binding var isHitBatter: Bool
        @Binding var selectedOutcome: String?
        @Binding var selectedDescriptor: String?
        @Binding var isError: Bool
        let deselectIfDisabled: () -> Void

        func body(content: Content) -> some View {
            content
                .onChange(of: isPresented) { _, newValue in
                    if newValue == false {
                        deselectIfDisabled()
                    }
                }
                .onChange(of: isStrikeSwinging) { _, _ in deselectIfDisabled() }
                .onChange(of: isStrikeLooking) { _, _ in deselectIfDisabled() }
                .onChange(of: isWildPitch) { _, _ in deselectIfDisabled() }
                .onChange(of: isPassedBall) { _, _ in deselectIfDisabled() }
                .onChange(of: isBall) { _, _ in deselectIfDisabled() }
                .onChange(of: isHitBatter) { _, _ in deselectIfDisabled() }
                .onChange(of: selectedOutcome) { _, _ in deselectIfDisabled() }
                .onChange(of: selectedDescriptor) { _, _ in deselectIfDisabled() }
                .onChange(of: isError) { _, _ in deselectIfDisabled() }
                .onChange(of: selectedOutcome) { _, newValue in
                    if isHitBatter && newValue != "1B" {
                        isHitBatter = false
                    }
                    if newValue == "ꓘ" && selectedDescriptor == "Foul" {
                        selectedDescriptor = nil
                    }
                    deselectIfDisabled()
                }
        }
    }

    var body: some View {
        AnyView(
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 10) {
                HStack(spacing: 12) {
                    if let label = pendingResultLabel {
                        Text("Location: \(label)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.blue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }

                Divider()

                ToggleSection(
                    isStrikeSwinging: $isStrikeSwinging,
                    isStrikeLooking: $isStrikeLooking,
                    isWildPitch: $isWildPitch,
                    isPassedBall: $isPassedBall,
                    isBall: $isBall,
                    isHitBatter: $isHitBatter,
                    selectedOutcome: $selectedOutcome
                )

                Divider()

                OutcomeButtonsSection(
                    selectedOutcome: $selectedOutcome,
                    selectedDescriptor: $selectedDescriptor,
                    isError: $isError,
                    isOutcomeDisabled: isOutcomeDisabled
                )
                .padding(.horizontal)

                let canSave: Bool = {
                    // Require at least one of: overlay tap, outcome/descriptor/error, or any toggle
                    (battedBallRegionName != nil) ||
                    (selectedOutcome != nil) ||
                    (selectedDescriptor != nil) ||
                    isError ||
                    isStrikeSwinging ||
                    isStrikeLooking ||
                    isWildPitch ||
                    isPassedBall ||
                    isBall
                }()
                
                HStack(alignment: .center, spacing: 12) {
                    HoldActionButton(
                        title: "Pitch Only",
                        systemImage: "square.and.arrow.down",
                        foregroundColor: .blue,
                        tint: .white,
                        isEnabled: true,
                        action: handlePitchOnlySave
                    )

                    Spacer()
                    
                    HoldActionButton(
                        title: "Pitch Event",
                        systemImage: "square.and.arrow.down.on.square.fill",
                        foregroundColor: .green,
                        tint: .white,
                        isEnabled: canSave,
                        action: handleSave
                    )
                }

                Divider()
                    .padding(.top, -6)

                HStack(spacing: 8) {
                    Text("Ball in play location")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        battedBallRegionName = nil
                        battedBallSelection = nil
                        battedBallTapNormalized = nil
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }

                FieldOverlayView(
                    isPresented: .constant(true),
                    colorMapImage: colorMapImage,
                    colorMapping: colorMapping,
                    selectedOutcome: $selectedOutcome,
                    selectedDescriptor: $selectedDescriptor,
                    isError: $isError,
                    battedBallRegionName: $battedBallRegionName,
                    battedBallSelection: $battedBallSelection,
                    battedBallTapNormalized: $battedBallTapNormalized,
                    showsDismissControls: false
                )
                .frame(height: 520)
                .padding(.horizontal, -12)
                .padding(.top, -12)

                }
                .padding(12)
            }
            .modifier(
                OutcomeChangeHandlers(
                    isPresented: $isPresented,
                    isStrikeSwinging: $isStrikeSwinging,
                    isStrikeLooking: $isStrikeLooking,
                    isWildPitch: $isWildPitch,
                    isPassedBall: $isPassedBall,
                    isBall: $isBall,
                    isHitBatter: $isHitBatter,
                    selectedOutcome: $selectedOutcome,
                    selectedDescriptor: $selectedDescriptor,
                    isError: $isError,
                    deselectIfDisabled: { self.deselectIfDisabled() }
                )
            )
        )
    }
    private func deselectIfDisabled() {
        if let outcome = selectedOutcome, isOutcomeDisabled(outcome) {
            selectedOutcome = nil
        }
        if let descriptor = selectedDescriptor, isOutcomeDisabled(descriptor) {
            selectedDescriptor = nil
        }
        if isError && isOutcomeDisabled("E") {
            isError = false
        }
    }
}

private struct OutcomeButtonsSection: View {
    @Binding var selectedOutcome: String?
    @Binding var selectedDescriptor: String?
    @Binding var isError: Bool
    var isOutcomeDisabled: (String) -> Bool
    
    var body: some View {
        let safeLinkedOutcomes: Set<String> = ["1B", "2B", "3B", "HR"]
        let isSafeActive = selectedOutcome == "Safe" || safeLinkedOutcomes.contains(selectedOutcome ?? "")

        VStack(spacing: 12) {
            HStack(spacing: 8) {
                OutcomeButton(label: "ꓘ", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("ꓘ"), usesDescriptorSelection: false)
                OutcomeButton(label: "K", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("K"), usesDescriptorSelection: false)
                OutcomeButton(label: "Foul", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Foul"), usesDescriptorSelection: false)
                Spacer()
            }
            HStack(spacing: 8) {
                Button {
                    selectedOutcome = (selectedOutcome == "Safe") ? nil : "Safe"
                } label: {
                    Text("Safe")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(isSafeActive ? Color(red: 0.75, green: 0.85, blue: 1.0) : Color.gray.opacity(0.1))
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(isOutcomeDisabled("Safe"))
                OutcomeButton(label: "Out", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Out"), usesDescriptorSelection: false)
                Spacer()
            }
            HStack(spacing: 8) {
                Text("Safe:")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)
                OutcomeButton(label: "1B", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("1B"), usesDescriptorSelection: false)
                OutcomeButton(label: "2B", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("2B"), usesDescriptorSelection: false)
                OutcomeButton(label: "3B", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("3B"), usesDescriptorSelection: false)
            }
            HStack(spacing: 8) {
                OutcomeButton(label: "Grounder", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Grounder"), usesDescriptorSelection: true)
                OutcomeButton(label: "Line", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Line"), usesDescriptorSelection: true)
                OutcomeButton(label: "Pop", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Pop"), usesDescriptorSelection: true)
                OutcomeButton(label: "Fly", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Fly"), usesDescriptorSelection: true)
            }
            HStack(spacing: 8) {
                OutcomeButton(label: "Walk", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Walk"), usesDescriptorSelection: false)
                OutcomeButton(label: "Bunt", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Bunt"), usesDescriptorSelection: true)
                Button {
                    isError.toggle()
                } label: {
                    Text("E")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(isError ? Color(red: 0.75, green: 0.85, blue: 1.0) : Color.gray.opacity(0.1))
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(isOutcomeDisabled("E"))
                OutcomeButton(label: "HR", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("HR"), usesDescriptorSelection: false)
            }
        }
    }
}

private struct FieldOverlayView: View {
    @Binding var isPresented: Bool
    let colorMapImage: UIImage?
    let colorMapping: [ColorKey: (selection: OverlaySelection, label: String, outcome: String?)]
    @Binding var selectedOutcome: String?
    @Binding var selectedDescriptor: String?
    @Binding var isError: Bool

    @Binding var battedBallRegionName: String?
    @Binding var battedBallSelection: OverlaySelection?
    @Binding var battedBallTapNormalized: CGPoint?
    var showsDismissControls: Bool = true

    private func handleTap(at location: CGPoint, in imageRect: CGRect) {
        guard imageRect.contains(location) else { return }

        let nx = (location.x - imageRect.minX) / imageRect.width
        let ny = (location.y - imageRect.minY) / imageRect.height

        if let img = colorMapImage, let cg = img.cgImage {
            let px = max(0, min(CGFloat(cg.width - 1), nx * CGFloat(cg.width)))
            let py = max(0, min(CGFloat(cg.height - 1), ny * CGFloat(cg.height)))
            if let uiColor = img.pixelColor(at: CGPoint(x: floor(px), y: floor(py))) {
                let key = colorKey(from: uiColor)
                if let mapped = colorMapping[key] {
                    battedBallSelection = mapped.selection
                    battedBallRegionName = mapped.label
                    // normalized 0...1 coordinates relative to imageRect
                    let clampedX = max(0, min(1, nx))
                    let clampedY = max(0, min(1, ny))
                    battedBallTapNormalized = CGPoint(x: clampedX, y: clampedY)
                    if let out = mapped.outcome {
                        // Only override selections when the map explicitly dictates an outcome
                        selectedOutcome = out
                        if out == "HR" {
                            let allowedHRDescriptors: Set<String> = ["Line", "Fly"]
                            if !allowedHRDescriptors.contains(selectedDescriptor ?? "") {
                                selectedDescriptor = nil
                            }
                        } else {
                            selectedDescriptor = nil
                        }
                        isError = false
                    }
                    return
                } else {
                    // Unmapped color: do nothing and return without showing overlay
                    return
                }
            }
        }

        battedBallSelection = .field
        battedBallRegionName = colorMapImage == nil ? "No color map" : "Unmapped"
        let clampedX = max(0, min(1, nx))
        let clampedY = max(0, min(1, ny))
        battedBallTapNormalized = CGPoint(x: clampedX, y: clampedY)
        // Removed clearing of selections here as per instructions
    }

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width
            let availableHeight = proxy.size.height
            let baseCenterX = availableWidth / 2
            // Prefer the color map's aspect to ensure tap sampling aligns with the displayed image
            let drivingImage: UIImage? = colorMapImage ?? UIImage(named: "FieldImage")
            let aspect: CGFloat = {
                if let img = drivingImage { return img.size.width / max(img.size.height, 1) }
                return 1
            }()
            // Fill available space (aspect-fill style) and zoom in so the field is much larger.
            let fittedSize: (width: CGFloat, height: CGFloat) = {
                let zoom: CGFloat = 1.28

                let widthFitW = availableWidth * zoom
                let widthFitH = widthFitW / max(aspect, 0.001)

                let heightFitH = availableHeight * zoom
                let heightFitW = heightFitH * aspect

                // Choose the variant that covers the container (aspectFill behavior).
                if widthFitH >= availableHeight {
                    return (widthFitW, widthFitH)
                } else {
                    return (heightFitW, heightFitH)
                }
            }()
            let finalWidth = fittedSize.width
            let finalHeight = fittedSize.height
            let topPadding: CGFloat = -130 + (availableHeight * 0.03)
            let imageRect = CGRect(
                x: baseCenterX - finalWidth / 2,
                y: topPadding,
                width: finalWidth,
                height: finalHeight
            )

            ZStack {
                // Removed dimming background as per instructions
                
                VStack {
                    HStack {
                        if colorMapImage == nil {
                            Text("colorMap image not found")
                                .font(.caption)
                                .padding(6)
                                .background(Color.red.opacity(0.8), in: Capsule())
                                .foregroundColor(.white)
                        } else if colorMapping.isEmpty {
                            Text("colorMapping is empty — taps won't map")
                                .font(.caption)
                                .padding(6)
                                .background(Color.orange.opacity(0.8), in: Capsule())
                                .foregroundColor(.white)
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .padding()
                .allowsHitTesting(false)

                Image("FieldImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)
                    .shadow(radius: 10)
                    .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.clear)
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                handleTap(at: value.location, in: imageRect)
                            }
                    )

                if let normalized = battedBallTapNormalized {
                    let point = CGPoint(
                        x: imageRect.minX + (normalized.x * imageRect.width),
                        y: imageRect.minY + (normalized.y * imageRect.height)
                    )
                    Circle()
                        .fill(Color.red)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .position(x: point.x, y: point.y)

                    if let labelText = battedBallRegionName, !labelText.isEmpty {
                        Text(labelText)
                            .font(.headline)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .position(x: min(max(point.x, 60), proxy.size.width - 60), y: min(point.y + 28, proxy.size.height - 24))
                    }
                }

                if showsDismissControls {
                    VStack {
                        Spacer()
                        Text("Ball in play location")
                        HStack{
                            Spacer()
                            Button {
                                withAnimation(.easeOut) { isPresented = false }
                            } label: {
                                Text("Save")
                                    .font(.headline)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .padding(.bottom, 24)
                            Spacer()
                            Button {
                                withAnimation(.easeOut) { isPresented = false }
                            } label: {
                                Text("Cancel")
                                    .font(.headline)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .padding(.bottom, 24)
                            Spacer()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .clipped()
        }
    }
}
