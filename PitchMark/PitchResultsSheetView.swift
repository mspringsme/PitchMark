//
//  PitchResultsSheetView.swift
//  PitchMark
//
//  Created by Mark Springer on 11/2/25.
//
import SwiftUI
import UIKit

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
                Image("field2")
                    .resizable()
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

    private enum OverlaySelection {
        case field, hr, foul
    }
    @State private var overlayTapPoint: CGPoint? = nil
    @State private var overlaySelection: OverlaySelection? = nil
    
    @State private var fieldCGImage: CGImage? = nil
    @State private var fieldRegionsCGImage: CGImage? = nil

    private func describeTap(point: CGPoint, in imageRect: CGRect) -> String {
        // Calibrate to the artwork: home plate sits a bit above the bottom edge.
        let homeYOffsetFraction: CGFloat = 0.12 // adjust if needed after testing

        // Home plate origin (bottom-center, lifted by a fraction of height)
        let home = CGPoint(x: imageRect.midX, y: imageRect.maxY - imageRect.height * homeYOffsetFraction)

        // Vector from home toward the tap. Use screen-up as positive Y by flipping dy.
        let dx = point.x - home.x
        let dyUp = home.y - point.y // upfield is positive
        let distance = sqrt(dx*dx + dyUp*dyUp)

        // Normalize distance by approximate fence depth (home to top of imageRect)
        let maxDepth = max(1, home.y - imageRect.minY) // avoid divide-by-zero
        let normR = distance / maxDepth

        // Angle with 0 = straight up (center field), positive to right field
        var angle = atan2(dx, dyUp) // -pi..pi
        if angle > .pi { angle -= 2 * .pi }
        if angle < -.pi { angle += 2 * .pi }

        // Depth bands tuned to the art
        let depth: String = {
            switch normR {
            case ..<0.28: return "Infield"
            case 0.28..<0.55: return "Shallow outfield"
            case 0.55..<0.88: return "Deep outfield"
            default: return "Track"
            }
        }()

        // Special infield areas: mound and infield quadrants
        if normR < 0.12 { return "Pitcher’s mound area" }
        if normR < 0.28 {
            if angle < -.pi * 0.5 { return "Infield near 3B" }
            else if angle < 0 { return "Infield between SS and 3B" }
            else if angle < .pi * 0.5 { return "Infield between 1B and 2B" }
            else { return "Infield near 1B" }
        }

        // Side bands
        let side: String = {
            switch angle {
            case (-.pi)...(-.pi * 0.6): return "Left field"
            case (-.pi * 0.6)..<(-.pi * 0.25): return "Left-center"
            case (-.pi * 0.25)...(.pi * 0.25): return "Center field"
            case (.pi * 0.25)..<(.pi * 0.6): return "Right-center"
            default: return "Right field"
            }
        }()

        return "\(depth) \(side)".trimmingCharacters(in: .whitespaces)
    }
    
    private func alphaAtNormalizedPoint(_ p: CGPoint, in cgImage: CGImage) -> CGFloat? {
        // p is normalized [0,1] in both axes relative to the image (top-left origin)
        guard p.x >= 0, p.x <= 1, p.y >= 0, p.y <= 1 else { return nil }
        let width = cgImage.width
        let height = cgImage.height

        let x = Int(round(p.x * CGFloat(width - 1)))
        let y = Int(round((1 - p.y) * CGFloat(height - 1))) // flipped Y for CG bitmap

        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .none
        ctx.translateBy(x: -CGFloat(x), y: -CGFloat(y))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        return CGFloat(pixel[3]) / 255.0
    }

    private func rgbaAtNormalizedPoint(_ p: CGPoint, in cgImage: CGImage) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard p.x >= 0, p.x <= 1, p.y >= 0, p.y <= 1 else { return nil }
        let width = cgImage.width
        let height = cgImage.height

        let x = Int(round(p.x * CGFloat(width - 1)))
        let y = Int(round((1 - p.y) * CGFloat(height - 1)))

        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .none
        ctx.translateBy(x: -CGFloat(x), y: -CGFloat(y))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }

    private func regionNameAtNormalizedPoint(_ p: CGPoint, in cgImage: CGImage) -> String? {
        guard let px = rgbaAtNormalizedPoint(p, in: cgImage) else { return nil }

        func packRGB(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> UInt32 {
            return (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
        }

        // Exact RGB map (alpha ignored). Update if your mask uses different exact RGB values.
        let map: [UInt32: String] = [
            packRGB(0xFF, 0x00, 0x01): "In play — To pitcher",            // FF0001
            packRGB(0x00, 0x00, 0x00): "In play — In front of pitcher",            // 000000
            packRGB(0x00, 0x2F, 0xFE): "In play — In front of 3rd",                // 002FFE
            packRGB(0x00, 0xFE, 0x84): "In play — In front of first",              // 00FE84
            packRGB(0x00, 0xCB, 0x92): "In play — Third",                          // 00CB92
            packRGB(0x86, 0x01, 0x98): "In play — Shortstop",                      // 860198
            packRGB(0xFF, 0x00, 0xE1): "In play — Up the middle",                  // FF00E1
            packRGB(0x88, 0x76, 0x00): "In play — 2nd",                            // 887600
            packRGB(0x77, 0x4C, 0x01): "In play — 1st",                            // 774C01
            packRGB(0x00, 0xA5, 0xFE): "In play — Short right field",              // 00A5FE
            packRGB(0xFF, 0x8C, 0x01): "In play — Right field",                    // FF8C01
            packRGB(0xFF, 0xD8, 0x9D): "In play — Deep right field",               // FFD89D
            packRGB(0x8C, 0x01, 0xFE): "In play — Short center field",             // 8C01FE
            packRGB(0xFF, 0xAA, 0x01): "In play — Center field",                   // FFAA01
            packRGB(0xFF, 0xAE, 0xB5): "In play — Deep center field",              // FFAEB5
            packRGB(0xC8, 0x01, 0xFE): "In play — Short left field",               // C801FE
            packRGB(0xFF, 0xD4, 0x01): "In play — Left field",                     // FFD401
            packRGB(0xA1, 0xBE, 0xFF): "In play — Deep left field"                  // A1BEFF
        ]

        let key = packRGB(px.r, px.g, px.b)
        if let name = map[key] { return name }

        // Optional tiny tolerance for anti-aliasing; set tol=0 for strict matching
        let tol: UInt8 = 2
        func close(_ a: UInt8, _ b: UInt8) -> Bool { return a > b &- tol && a < b &+ tol }
        for (k, name) in map {
            let kr = UInt8((k >> 16) & 0xFF)
            let kg = UInt8((k >> 8) & 0xFF)
            let kb = UInt8(k & 0xFF)
            if close(px.r, kr) && close(px.g, kg) && close(px.b, kb) {
                return name
            }
        }

        return nil
    }

    let pendingResultLabel: String?
    let pitchCall: PitchCall?
    let batterSide: BatterSide
    let selectedTemplateId: String?
    let currentMode: PitchMode
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

    var body: some View {
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
                            .frame(height: 36) // 👈 Shorter height
                            .background(isError ? Color(red: 0.75, green: 0.85, blue: 1.0) : Color.gray.opacity(0.1))
                            .cornerRadius(6)
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2) // 👈 Add shadow
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
            .padding(.horizontal)

            Button("Save Pitch Event") {
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
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height) * 0.8
                let imageOrigin = CGPoint(x: (proxy.size.width - side) / 2, y: (proxy.size.height - side) / 2)
                let imageRect = CGRect(origin: imageOrigin, size: CGSize(width: side, height: side))

                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()

                    // Centered field image
                    Image("field2")
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(width: side, height: side)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .shadow(radius: 10)
                        .onAppear {
                            if fieldCGImage == nil {
                                fieldCGImage = UIImage(named: "field2")?.cgImage
                                print("[DEBUG] field2 loaded:", fieldCGImage != nil)
                            }
                            if fieldRegionsCGImage == nil {
                                fieldRegionsCGImage = UIImage(named: "field2_map")?.cgImage
                                print("[DEBUG] field2_map loaded:", fieldRegionsCGImage != nil)
                            }
                        }
                        
                    // Tap marker and label
                    if let point = overlayTapPoint {
                        // Marker
                        Circle()
                            .fill(Color.red)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .position(x: point.x, y: point.y)

                        // Label near marker
                        let labelText: String = {
                            switch overlaySelection {
                            case .hr: return "Home Run area"
                            case .foul: return "Foul area"
                            case .field:
                                let nx = max(0, min(1, (point.x - imageRect.minX) / imageRect.width))
                                let ny = max(0, min(1, (point.y - imageRect.minY) / imageRect.height))
                                if let mask = fieldRegionsCGImage, let name = regionNameAtNormalizedPoint(CGPoint(x: nx, y: ny), in: mask) {
                                    return name
                                } else if fieldRegionsCGImage == nil {
                                    return "(map not loaded) " + describeTap(point: point, in: imageRect)
                                } else {
                                    return describeTap(point: point, in: imageRect)
                                }
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
                        Button {
                            withAnimation(.easeOut) { showFieldOverlay = false }
                        } label: {
                            Text("Save")
                                .font(.headline)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding(.bottom, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            let loc = value.location
                            overlayTapPoint = loc
                            
                            let nx = max(0, min(1, (loc.x - imageRect.minX) / imageRect.width))
                            let ny = max(0, min(1, (loc.y - imageRect.minY) / imageRect.height))
                            print(String(format: "[DEBUG] Tap loc: (%.1f, %.1f), norm: (%.3f, %.3f)", loc.x, loc.y, nx, ny))
                            if let mask = fieldRegionsCGImage {
                                if let px = rgbaAtNormalizedPoint(CGPoint(x: nx, y: ny), in: mask) {
                                    print(String(format: "[DEBUG] Mask RGBA: #%02X%02X%02X alpha=%d", px.r, px.g, px.b, px.a))
                                    if let matched = regionNameAtNormalizedPoint(CGPoint(x: nx, y: ny), in: mask) {
                                        print("[DEBUG] Matched region:", matched)
                                    } else {
                                        print("[DEBUG] No region match for this color")
                                    }
                                } else {
                                    print("[DEBUG] Failed to sample mask at normalized point")
                                }
                            } else {
                                print("[DEBUG] Mask not loaded")
                            }
                            if let cg = fieldCGImage, let a = alphaAtNormalizedPoint(CGPoint(x: nx, y: ny), in: cg) {
                                print(String(format: "[DEBUG] Field alpha at tap: %.3f", a))
                            }
                            
                            if loc.y < imageRect.minY {
                                // Above the top of the image: HR only if horizontally within the image width; otherwise Foul
                                if loc.x >= imageRect.minX && loc.x <= imageRect.maxX {
                                    overlaySelection = .hr
                                    selectedOutcome = "HR"
                                    selectedDescriptor = nil
                                    isError = false
                                } else {
                                    overlaySelection = .foul
                                    selectedOutcome = "Foul"
                                    selectedDescriptor = nil
                                    isError = false
                                }
                            } else if loc.x < imageRect.minX || loc.x > imageRect.maxX || loc.y > imageRect.maxY {
                                // Sides or below the image => Foul
                                overlaySelection = .foul
                                selectedOutcome = "Foul"
                                selectedDescriptor = nil
                                isError = false
                            } else {
                                // Inside the image: use alpha-based hit testing to determine if it's on-field or transparent
                                if let cg = fieldCGImage, let alpha = alphaAtNormalizedPoint(CGPoint(x: nx, y: ny), in: cg) {
                                    if alpha > 0.1 {
                                        // Opaque pixel: treat as on-field; record point and let user choose outcome below
                                        overlaySelection = .field
                                        // Keep overlayTapPoint at the visual location
                                    } else {
                                        // Transparent region within the image: decide HR vs Foul based on position relative to top arch
                                        // Approximate the outfield arc as a semicircle that fits the image square
                                        let cx = imageRect.midX
                                        let r = imageRect.width / 2.0
                                        let cy = imageRect.minY + r
                                        let dx = loc.x - cx
                                        let dy = loc.y - cy
                                        let dist2 = dx*dx + dy*dy
                                        let r2 = r * r

                                        // If the point is in the top half (above circle center) and outside the circle => above the arch => HR
                                        if loc.y <= cy && dist2 > r2 {
                                            overlaySelection = .hr
                                            selectedOutcome = "HR"
                                            selectedDescriptor = nil
                                            isError = false
                                        } else {
                                            overlaySelection = .foul
                                            selectedOutcome = "Foul"
                                            selectedDescriptor = nil
                                            isError = false
                                        }
                                    }
                                } else {
                                    // Fallback if image not available: assume on-field
                                    overlaySelection = .field
                                }
                            }
                        }
                )
            }
            .ignoresSafeArea()
        }
        .presentationDetents([.large])
        .onChange(of: isPresented) { _, newValue in
            if newValue == false {
                resetSelections()
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
        saveAction: { _ in },
        template: PitchTemplate(
            id: UUID(),
            name: "Sample Template",
            pitches: ["Fastball", "Curveball"],
            codeAssignments: []
        )
    )
}

