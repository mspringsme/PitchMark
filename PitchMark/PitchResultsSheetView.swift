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
    @Binding var showOverlay: Bool

    var body: some View {
        ZStack {
            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Strike Swinging", isOn: $isStrikeSwinging)
                        .onChange(of: isStrikeSwinging) { _, newValue in
                            if newValue { isStrikeLooking = false }
                        }
                    Toggle("Strike Looking", isOn: $isStrikeLooking)
                        .onChange(of: isStrikeLooking) { _, newValue in
                            if newValue { isStrikeSwinging = false }
                        }
                    Toggle("Wild Pitch", isOn: $isWildPitch)
                        .onChange(of: isWildPitch) { _, newValue in
                            if newValue { isPassedBall = false }
                        }
                    Toggle("Passed Ball", isOn: $isPassedBall)
                        .onChange(of: isPassedBall) { _, newValue in
                            if newValue { isWildPitch = false }
                        }
                }
                .padding(.horizontal)
                Spacer()
                Image("FieldImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .onTapGesture {
                        withAnimation(.easeOut) { showOverlay = true }
                    }
            }
        }
    }
}

struct PitchResultSheetView: View {
    @Binding var isPresented: Bool
    @Binding var isStrikeSwinging: Bool
    @Binding var isStrikeLooking: Bool
    @Binding var isWildPitch: Bool
    @Binding var isPassedBall: Bool
    @Binding var selectedOutcome: String?
    @Binding var selectedDescriptor: String?
    @Binding var isError: Bool
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
    let selectedOpponentJersey: String?
    let selectedOpponentBatterId: String?
    let saveAction: (PitchEvent) -> Void
    let template: PitchTemplate?

    private func resetSelections() {
        isStrikeSwinging = false
        isStrikeLooking = false
        isWildPitch = false
        isPassedBall = false
        selectedOutcome = nil
        selectedDescriptor = nil
        isError = false
    }

    private func isOutcomeDisabled(_ label: String) -> Bool {
        if selectedOutcome == "HBP" {
                return label != "HBP"
            }
        if selectedOutcome == "ꓘ" && label == "Foul" {
            return true
        }
        // Determine if any of the top toggles are selected
        let anyTopToggle = isStrikeSwinging || isStrikeLooking || isWildPitch || isPassedBall
        // Determine if either strike toggle is selected
        let anyStrikeToggle = isStrikeSwinging || isStrikeLooking
        // Determine if either K or backwards K is selected
        let isKSelected = selectedOutcome == "K" || selectedOutcome == "ꓘ"

        // Descriptor group (mutually exclusive within the group, but can co-exist with base outcome)
        let descriptorGroup: Set<String> = ["Pop", "Line", "Fly", "Grounder", "Bunt"]
        // Base outcome group that should be mutually exclusive among themselves
        let baseOutcomeGroup: Set<String> = ["1B", "2B", "3B", "HR"]

        // Special rule: If HR is selected
        if selectedOutcome == "HR" {
            // Among descriptors, only allow Line or Fly; disable others.
            let allowedDescriptors: Set<String> = ["Line", "Fly"]
            if descriptorGroup.contains(label) {
                return !allowedDescriptors.contains(label)
            }
            // Disable the following non-descriptor outcomes when HR is selected
            let disallowedWhenHR: Set<String> = [
                "BB", "Bunt", "E", "Foul", "K", "ꓘ", "HBP", "Safe", "Out"
            ]
            if disallowedWhenHR.contains(label) {
                return true
            }
        }
        

        // 1) If K or backwards K is selected, deactivate all other buttons except 1B, E, Foul.
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
        if anyStrikeToggle && label == "BB" {
            return true
        }

        // 4) Do not disable descriptor or base groups due to each other — co-selection is allowed.
        if descriptorGroup.contains(label) || baseOutcomeGroup.contains(label) {
            return false
        }

        return false
    }

    private func handleSave() {
        guard let label = pendingResultLabel,
              let pitchCall = pitchCall else {
            isPresented = false
            return
        }

        let event = PitchEvent(
            id: UUID().uuidString,
            timestamp: Date(),
            pitch: pitchCall.pitch,
            location: label,
            codes: pitchCall.codes,
            isStrike: pitchCall.isStrike,
            mode: currentMode,
            calledPitch: pitchCall,
            batterSide: batterSide,
            templateId: selectedTemplateId,
            strikeSwinging: isStrikeSwinging,
            wildPitch: isWildPitch,
            passedBall: isPassedBall
        )

        saveAction(event)
        isPresented = false
        resetSelections()
    }

    private struct OutcomeChangeHandlers: ViewModifier {
        @Binding var isPresented: Bool
        @Binding var isStrikeSwinging: Bool
        @Binding var isStrikeLooking: Bool
        @Binding var isWildPitch: Bool
        @Binding var isPassedBall: Bool
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
                .onChange(of: selectedOutcome) { _, _ in deselectIfDisabled() }
                .onChange(of: selectedDescriptor) { _, _ in deselectIfDisabled() }
                .onChange(of: isError) { _, _ in deselectIfDisabled() }
                .onChange(of: selectedOutcome) { _, newValue in
                    if newValue == "HBP" {
                        isWildPitch = true
                        isStrikeSwinging = false
                        isStrikeLooking = false
                        isPassedBall = false
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
            VStack(spacing: 20) {
                
                if let template = template {
                    Text(template.name)
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                
                Text("Save Pitch")
                    .font(.title2)
                    .bold()

                if let label = pendingResultLabel {
                    Text("Location: \(label)")
                        .font(.headline)
                        .foregroundColor(.blue)
                }

                Divider()

                ToggleSection(isStrikeSwinging: $isStrikeSwinging, isStrikeLooking: $isStrikeLooking, isWildPitch: $isWildPitch, isPassedBall: $isPassedBall, showOverlay: $showFieldOverlay)

                Divider()

                OutcomeButtonsSection(
                    selectedOutcome: $selectedOutcome,
                    selectedDescriptor: $selectedDescriptor,
                    isError: $isError,
                    isOutcomeDisabled: isOutcomeDisabled
                )
                .padding(.horizontal)

                Button("Save Pitch Event") {
                    handleSave()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)

                Button("Cancel", role: .cancel) {
                    isPresented = false
                    resetSelections()
                }
                .padding(.bottom)
            }
            .padding()
            .fullScreenCover(isPresented: $showFieldOverlay) {
                FieldOverlayView(
                    isPresented: $showFieldOverlay,
                    colorMapImage: colorMapImage,
                    colorMapping: colorMapping,
                    selectedOutcome: $selectedOutcome,
                    selectedDescriptor: $selectedDescriptor,
                    isError: $isError
                )
                .ignoresSafeArea()
            }
            .presentationDetents([.large])
            .modifier(
                OutcomeChangeHandlers(
                    isPresented: $isPresented,
                    isStrikeSwinging: $isStrikeSwinging,
                    isStrikeLooking: $isStrikeLooking,
                    isWildPitch: $isWildPitch,
                    isPassedBall: $isPassedBall,
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
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                OutcomeButton(label: "ꓘ", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("ꓘ"), usesDescriptorSelection: false)
                OutcomeButton(label: "K", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("K"), usesDescriptorSelection: false)
                Spacer()
                OutcomeButton(label: "HBP", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("HBP"), usesDescriptorSelection: false)
                Spacer()
                OutcomeButton(label: "Safe", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Safe"), usesDescriptorSelection: false)
                OutcomeButton(label: "Out", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Out"), usesDescriptorSelection: false)
            }
            HStack(spacing: 8) {
                OutcomeButton(label: "1B", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("1B"), usesDescriptorSelection: false)
                OutcomeButton(label: "Pop", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Pop"), usesDescriptorSelection: true)
                OutcomeButton(label: "BB", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("BB"), usesDescriptorSelection: false)
            }
            HStack(spacing: 8) {
                OutcomeButton(label: "2B", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("2B"), usesDescriptorSelection: false)
                OutcomeButton(label: "Line", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Line"), usesDescriptorSelection: true)
                OutcomeButton(label: "Bunt", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Bunt"), usesDescriptorSelection: true)
            }
            HStack(spacing: 8) {
                OutcomeButton(label: "3B", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("3B"), usesDescriptorSelection: false)
                OutcomeButton(label: "Fly", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Fly"), usesDescriptorSelection: true)
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
            }
            HStack(spacing: 8) {
                OutcomeButton(label: "HR", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("HR"), usesDescriptorSelection: false)
                OutcomeButton(label: "Grounder", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Grounder"), usesDescriptorSelection: true)
                OutcomeButton(label: "Foul", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Foul"), usesDescriptorSelection: false)
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

    @State private var overlayTapPoint: CGPoint? = nil
    @State private var overlaySelection: OverlaySelection? = nil
    @State private var overlayRegionName: String? = nil

    private func handleTap(at location: CGPoint, in imageRect: CGRect) {
        guard imageRect.contains(location) else { return }
        // Removed the line: overlayTapPoint = location

        let nx = (location.x - imageRect.minX) / imageRect.width
        let ny = (location.y - imageRect.minY) / imageRect.height

        if let img = colorMapImage, let cg = img.cgImage {
            let px = max(0, min(CGFloat(cg.width - 1), nx * CGFloat(cg.width)))
            let py = max(0, min(CGFloat(cg.height - 1), ny * CGFloat(cg.height)))
            if let uiColor = img.pixelColor(at: CGPoint(x: floor(px), y: floor(py))) {
                let key = colorKey(from: uiColor)
                if let mapped = colorMapping[key] {
                    overlayTapPoint = location
                    overlaySelection = mapped.selection
                    overlayRegionName = mapped.label
                    if let out = mapped.outcome {
                        selectedOutcome = out
                        selectedDescriptor = nil
                        isError = false
                    } else {
                        selectedOutcome = nil
                        selectedDescriptor = nil
                        isError = false
                    }
                    return
                } else {
                    // Unmapped color: do nothing and return without showing overlay
                    return
                }
            }
        }

        overlaySelection = .field
        overlayRegionName = "No color map"
        selectedOutcome = nil
        selectedDescriptor = nil
        isError = false
    }

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width
            let availableHeight = proxy.size.height
            let baseCenter = CGPoint(x: availableWidth / 2, y: availableHeight / 2)
            // Prefer the color map's aspect to ensure tap sampling aligns with the displayed image
            let drivingImage: UIImage? = colorMapImage ?? UIImage(named: "FieldImage")
            let aspect: CGFloat = {
                if let img = drivingImage { return img.size.width / max(img.size.height, 1) }
                return 1
            }()
            // Fit by height with slight scale-down to make the image a bit smaller, still allowing horizontal clipping
            let scale: CGFloat = 0.92
            let finalHeight: CGFloat = availableHeight * scale
            let finalWidth: CGFloat = finalHeight * aspect
            let imageRect = CGRect(
                x: baseCenter.x - finalWidth / 2,
                y: baseCenter.y - finalHeight / 2,
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

                Rectangle()
                    .stroke(Color.purple.opacity(0.25), lineWidth: 1)
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)
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
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                handleTap(at: value.location, in: imageRect)
                            }
                    )

                if let point = overlayTapPoint {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .position(x: point.x, y: point.y)

                    let labelText: String = {
                        switch overlaySelection {
                        case .hr: return overlayRegionName ?? ""
                        case .foul: return overlayRegionName ?? ""
                        case .field:
                            return overlayRegionName ?? ""
                        case .none: return ""
                        }
                    }()
                    Text(labelText)
                        .font(.headline)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .position(x: min(max(point.x, 60), proxy.size.width - 60), y: min(point.y + 28, proxy.size.height - 24))
                }

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
            .contentShape(Rectangle())
            .clipped()
        }
    }
}

#Preview {
    PitchResultSheetView(
        isPresented: .constant(true),
        isStrikeSwinging: .constant(false),
        isStrikeLooking: .constant(false),
        isWildPitch: .constant(false),
        isPassedBall: .constant(false),
        selectedOutcome: .constant(nil),
        selectedDescriptor: .constant(nil),
        isError: .constant(false),
        pendingResultLabel: "A2",
        pitchCall: PitchCall(pitch: "Fastball", location: "A2", isStrike: true, codes: ["S", "C"]),
        batterSide: .left,
        selectedTemplateId: nil,
        currentMode: .practice, // Use a valid case for PitchMode
        selectedOpponentJersey: nil,
        selectedOpponentBatterId: nil,
        saveAction: { _ in },
        template: PitchTemplate(
            id: UUID(),
            name: "Sample Template",
            pitches: ["Fastball", "Curveball"],
            codeAssignments: []
        )
    )
}
