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

private enum ResultSymbolPickerTarget {
    case swinging
    case looking
    case ball
    case foul
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color(red: 0.75, green: 0.85, blue: 1.0) : Color.gray.opacity(0.1))
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
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
    @Binding var isError: Bool
    @Binding var selectedOutcome: String?
    @Binding var selectedDescriptor: String?
    let isSwingingDisabled: Bool
    let isLookingDisabled: Bool
    let isBallDisabled: Bool
    let isWildPitchDisabled: Bool
    let isPassedBallDisabled: Bool
    let isHitBatterDisabled: Bool
    let isOutcomeDisabled: (String) -> Bool
    let onRequestSymbolPicker: (ResultSymbolPickerTarget) -> Void
    let onFoulActivated: () -> Void

    private func toggleButton(
        _ title: String,
        leadingSystemImage: String? = nil,
        isOn: Bool,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let leadingSystemImage {
                    Image(systemName: leadingSystemImage)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
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
                toggleButton("Swinging", leadingSystemImage: "s.circle", isOn: isStrikeSwinging, disabled: isSwingingDisabled) {
                    let next = !isStrikeSwinging
                    isStrikeSwinging = next
                    if next {
                        isStrikeLooking = false
                        onRequestSymbolPicker(.swinging)
                    }
                }

                toggleButton("Looking", leadingSystemImage: "s.circle", isOn: isStrikeLooking, disabled: isLookingDisabled) {
                    let next = !isStrikeLooking
                    isStrikeLooking = next
                    if next {
                        isStrikeSwinging = false
                        onRequestSymbolPicker(.looking)
                    }
                }

                Button {
                    let next = (selectedOutcome == "Foul") ? nil : "Foul"
                    selectedOutcome = next
                    if next == "Foul" {
                        onFoulActivated()
                    }
                } label: {
                    Text("Foul")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedOutcome == "Foul" ? Color(red: 0.75, green: 0.85, blue: 1.0) : Color.gray.opacity(0.1))
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(isOutcomeDisabled("Foul"))
                .opacity(isOutcomeDisabled("Foul") ? 0.4 : 1)

            }

            HStack(spacing: 8) {
                toggleButton("Ball", isOn: isBall, disabled: isBallDisabled) {
                    let next = !isBall
                    isBall = next
                    if next {
                        onRequestSymbolPicker(.ball)
                    }
                }
                OutcomeButton(label: "Walk", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Walk"), usesDescriptorSelection: false)
                OutcomeButton(label: "K", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("K"), usesDescriptorSelection: false)
                OutcomeButton(label: "ꓘ", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("ꓘ"), usesDescriptorSelection: false)
            }

        }
        .padding(.horizontal)
    }
}

private struct EventButtonsRow: View {
    @Binding var isWildPitch: Bool
    @Binding var isPassedBall: Bool
    @Binding var isHitBatter: Bool
    @Binding var isError: Bool
    @Binding var selectedOutcome: String?
    let isWildPitchDisabled: Bool
    let isPassedBallDisabled: Bool
    let isHitBatterDisabled: Bool
    let isErrorDisabled: Bool

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
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isOn ? Color(red: 0.75, green: 0.85, blue: 1.0) : Color.gray.opacity(0.1))
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isError.toggle()
            } label: {
                Text("E")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isError ? Color(red: 0.75, green: 0.85, blue: 1.0) : Color.gray.opacity(0.1))
                    .cornerRadius(6)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(isErrorDisabled)
            .opacity(isErrorDisabled ? 0.4 : 1)

            toggleButton("Wild Pitch", isOn: isWildPitch, disabled: isWildPitchDisabled) {
                let next = !isWildPitch
                isWildPitch = next
                if next { isPassedBall = false }
            }

            toggleButton("Passed Ball", isOn: isPassedBall, disabled: isPassedBallDisabled) {
                let next = !isPassedBall
                isPassedBall = next
                if next { isWildPitch = false }
            }

            toggleButton("Hit Batter", isOn: isHitBatter, disabled: isHitBatterDisabled) {
                let next = !isHitBatter
                isHitBatter = next
                if next {
                    selectedOutcome = "1B"
                } else if selectedOutcome == "1B" {
                    selectedOutcome = nil
                }
            }
        }
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
    private enum PendingSaveIntent {
        case pitchOnly
        case pitchEvent
    }
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

    @State private var symbolPickerTarget: ResultSymbolPickerTarget? = nil
    @State private var strikeSwingingSymbol: String? = nil
    @State private var strikeLookingSymbol: String? = nil
    @State private var ballSymbol: String? = nil
    @State private var foulSymbol: String? = nil
    @State private var showMissingBatterPrompt: Bool = false
    @State private var pendingSaveIntent: PendingSaveIntent? = nil
    @State private var confirmedBallsCount: Int = 0
    @State private var confirmedStrikesCount: Int = 0
    @State private var didInitializeManualCount: Bool = false
    @State private var overrideOpponentJersey: String? = nil
    @State private var overrideOpponentBatterId: String? = nil
    @State private var showMissingLocationPrompt: Bool = false

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
    let allPitchEvents: [PitchEvent]
    let suggestedCountSeed: (balls: Int, strikes: Int)?
    let currentCountSeed: (balls: Int, strikes: Int)?
    var onCountChanged: ((Int, Int) -> Void)? = nil
    let lineupBatters: [JerseyCell]
    let selectedPitcherId: String?
    let saveAction: (PitchEvent) -> Void
    let template: PitchTemplate?
    let pitcherName: String?
    var onMissingLocation: (() -> Void)? = nil

    private var hasSelectedLocation: Bool {
        let trimmed = pendingResultLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty
    }

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
        strikeSwingingSymbol = nil
        strikeLookingSymbol = nil
        ballSymbol = nil
        foulSymbol = nil
        symbolPickerTarget = nil
        showMissingBatterPrompt = false
        pendingSaveIntent = nil
        overrideOpponentJersey = nil
        overrideOpponentBatterId = nil
    }

    private enum TopToggleRule {
        case swinging
        case looking
        case ball
        case wildPitch
        case passedBall
        case hitBatter
    }

    private var grounderRowOutcomes: Set<String> {
        ["Grounder", "Line", "Pop", "Fly"]
    }

    private var activeGrounderSelection: String? {
        guard let selectedDescriptor, grounderRowOutcomes.contains(selectedDescriptor) else { return nil }
        return selectedDescriptor
    }

    private func isTopToggleDisabled(_ toggle: TopToggleRule) -> Bool {
        let strikeSelected = isStrikeSwinging || isStrikeLooking
        let grounderRowSelected = activeGrounderSelection != nil
        let walkSelected = selectedOutcome == "Walk"
        let buntSelected = selectedDescriptor == "Bunt"
        let hrSelected = selectedOutcome == "HR"
        let foulSelected = selectedOutcome == "Foul"

        switch toggle {
        case .swinging:
            if isStrikeSwinging { return false }
            return isStrikeLooking || isBall || isHitBatter || walkSelected || buntSelected || hrSelected || grounderRowSelected || foulSelected
        case .looking:
            if isStrikeLooking { return false }
            return isStrikeSwinging || isBall || isHitBatter || walkSelected || buntSelected || hrSelected || grounderRowSelected || foulSelected
        case .ball:
            if isBall { return false }
            return strikeSelected || isHitBatter || buntSelected || hrSelected || grounderRowSelected || foulSelected
        case .wildPitch:
            if isWildPitch { return false }
            return isPassedBall || isHitBatter || buntSelected || hrSelected || grounderRowSelected || foulSelected
        case .passedBall:
            if isPassedBall { return false }
            return isWildPitch || isHitBatter || buntSelected || hrSelected || grounderRowSelected || foulSelected
        case .hitBatter:
            if isHitBatter { return false }
            return strikeSelected || isBall || isPassedBall || walkSelected || buntSelected || hrSelected || grounderRowSelected || foulSelected
        }
    }

    private func isOutcomeDisabled(_ label: String) -> Bool {
        // Keep selected items tappable so users can deselect.
        if selectedOutcome == label || selectedDescriptor == label { return false }
        if label == "E" && isError { return false }

        let strikeSelected = isStrikeSwinging || isStrikeLooking
        let hrSelected = selectedOutcome == "HR"
        let walkSelected = selectedOutcome == "Walk"
        let foulSelected = selectedOutcome == "Foul"
        let popSelected = selectedDescriptor == "Pop"
        let buntSelected = selectedDescriptor == "Bunt"
        let wpOrPbSelected = isWildPitch || isPassedBall

        // K buttons require matching strike toggle.
        if label == "K" { return !isStrikeSwinging }
        if label == "ꓘ" { return !isStrikeLooking }

        if strikeSelected && ["Ball", "Foul", "E", "HR"].contains(label) {
            return true
        }

        if (strikeSelected || wpOrPbSelected) && (grounderRowOutcomes.contains(label) || label == "Walk" || label == "Bunt") {
            return true
        }

        if isBall && ["Foul", "HR", "Grounder", "Line", "Pop", "Fly", "Bunt"].contains(label) {
            return true
        }

        if isWildPitch && ["Foul", "HR"].contains(label) {
            return true
        }

        if isPassedBall && ["Foul", "E", "HR"].contains(label) {
            return true
        }

        if isHitBatter && ["Foul", "2B", "3B", "HR", "Grounder", "Line", "Pop", "Fly", "Walk", "Bunt", "E"].contains(label) {
            return true
        }

        if foulSelected && ["1B", "2B", "3B", "HR", "Walk", "Bunt"].contains(label) {
            return true
        }

        if selectedOutcome == "1B" && ["2B", "3B", "HR"].contains(label) {
            return true
        }

        if selectedOutcome == "2B" && ["1B", "3B", "HR"].contains(label) {
            return true
        }

        if selectedOutcome == "3B" && ["1B", "2B", "HR"].contains(label) {
            return true
        }

        if hrSelected && ["1B", "2B", "3B", "Pop", "Foul", "Walk", "Bunt"].contains(label) {
            return true
        }

        if popSelected && label == "HR" {
            return true
        }

        if let activeGrounderSelection {
            if grounderRowOutcomes.contains(label) && label != activeGrounderSelection {
                return true
            }
            if label == "Walk" {
                return true
            }
        }

        if walkSelected && (["Foul", "Bunt", "HR"].contains(label) || grounderRowOutcomes.contains(label)) {
            return true
        }

        if buntSelected && ["Walk", "HR", "Fly"].contains(label) {
            return true
        }

        return false
    }

    private var symbolPickerTitle: String {
        switch symbolPickerTarget {
        case .swinging:
            return "Strike Count"
        case .looking:
            return "Strike Count"
        case .ball:
            return "Ball Count"
        case .foul:
            return "Strike Count"
        case .none:
            return "Select"
        }
    }

    private var symbolPickerOptions: [String] {
        switch symbolPickerTarget {
        case .swinging, .looking:
            return ["1.circle", "2.circle", "3.circle"]
        case .ball:
            return ["1.circle", "2.circle", "3.circle", "4.circle"]
        case .foul:
            return ["1.circle", "2.circle", "f.circle"]
        case .none:
            return []
        }
    }

    private func applySelectedSymbol(_ symbol: String?) {
        switch symbolPickerTarget {
        case .swinging:
            strikeSwingingSymbol = symbol
        case .looking:
            strikeLookingSymbol = symbol
        case .ball:
            ballSymbol = symbol
        case .foul:
            foulSymbol = symbol
        case .none:
            break
        }
        symbolPickerTarget = nil
    }

    private func symbolMenuTitle(_ symbol: String) -> String {
        if symbol == "f.circle" { return "F" }
        if let head = symbol.split(separator: ".").first, !head.isEmpty {
            return String(head)
        }
        return symbol
    }

    private var effectiveOpponentJersey: String? {
        overrideOpponentJersey ?? selectedOpponentJersey
    }

    private var effectiveOpponentBatterId: String? {
        overrideOpponentBatterId ?? selectedOpponentBatterId
    }

    private func requiresBatterPromptBeforeSave() -> Bool {
        guard currentMode == .game else { return false }
        guard lineupBatters.isEmpty == false else { return false }
        return effectiveOpponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    private func performSave(_ intent: PendingSaveIntent) {
        guard hasSelectedLocation else {
            showMissingLocationPrompt = true
            onMissingLocation?()
            return
        }
        guard var event = buildCurrentEvent() else { return }

        let balls = max(0, min(3, confirmedBallsCount))
        let strikes = max(0, min(2, confirmedStrikesCount))
        let prior = priorCount(for: event)

        let normalizedOutcome = (event.outcome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isWalkOutcome = normalizedOutcome.caseInsensitiveCompare("Walk") == .orderedSame
        let isKOutcome = normalizedOutcome == "K" || normalizedOutcome == "ꓘ"
        let isStrikeTerminal = isKOutcome || ((event.strikeLooking || event.strikeSwinging) && prior.strikes >= 2)
        let isBallTerminal = isWalkOutcome || ((event.isBall == true) && prior.balls >= 3)

        if isStrikeTerminal {
            event.atBatCount = "Strikeout"
            event.atBatBalls = 0
            event.atBatStrikes = 0
        } else if isBallTerminal {
            event.atBatCount = "Ball 4"
            event.atBatBalls = 0
            event.atBatStrikes = 0
        } else {
            event.atBatBalls = balls
            event.atBatStrikes = strikes
            event.atBatCount = "\(balls)-\(strikes)"
        }

        if intent == .pitchOnly {
            event.debugLog(prefix: "📤 Saving Pitch-Only PitchEvent")
        } else {
            event.debugLog()
        }
        onCountChanged?(event.atBatBalls ?? 0, event.atBatStrikes ?? 0)
        saveAction(event)
        pendingSaveIntent = nil
        isPresented = false
        resetSelections()
    }

    private func initializeManualCountIfNeeded() {
        guard !didInitializeManualCount else { return }
        let source = currentCountSeed ?? suggestedCountSeed ?? (0, 0)
        confirmedBallsCount = max(0, min(3, source.balls))
        confirmedStrikesCount = max(0, min(2, source.strikes))
        didInitializeManualCount = true
    }

    private func syncManualCountFromCurrentSeed() {
        guard let seed = currentCountSeed else { return }
        let normalizedBalls = max(0, min(3, seed.balls))
        let normalizedStrikes = max(0, min(2, seed.strikes))
        guard normalizedBalls != confirmedBallsCount || normalizedStrikes != confirmedStrikesCount else { return }
        confirmedBallsCount = normalizedBalls
        confirmedStrikesCount = normalizedStrikes
    }

    private func priorCount(for event: PitchEvent) -> (balls: Int, strikes: Int) {
        let activeBatterId = effectiveOpponentBatterId
        let activeJersey = effectiveOpponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseEvent = allPitchEvents
            .filter { existing in
                if let activeBatterId, !activeBatterId.isEmpty {
                    return existing.opponentBatterId == activeBatterId
                }
                if let activeJersey, !activeJersey.isEmpty {
                    return existing.opponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines) == activeJersey
                }
                return false
            }
            .sorted(by: { $0.timestamp < $1.timestamp })
            .last

        let parsedFromText: (Int, Int)? = {
            guard let text = baseEvent?.atBatCount else { return nil }
            let parts = text.split(separator: "-", maxSplits: 1).map { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2, let b = parts[0], let s = parts[1] else { return nil }
            return (b, s)
        }()

        let balls = baseEvent?.atBatBalls ?? parsedFromText?.0 ?? suggestedCountSeed?.balls ?? currentCountSeed?.balls ?? 0
        let strikes = baseEvent?.atBatStrikes ?? parsedFromText?.1 ?? suggestedCountSeed?.strikes ?? currentCountSeed?.strikes ?? 0
        return (balls, strikes)
    }

    private func suggestedCount(for event: PitchEvent) -> (balls: Int, strikes: Int) {
        let prior = priorCount(for: event)
        var balls = prior.balls
        var strikes = prior.strikes

        let normalizedOutcome = (event.outcome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isHBP = normalizedOutcome.caseInsensitiveCompare("HBP") == .orderedSame
        let isWalk = normalizedOutcome.caseInsensitiveCompare("Walk") == .orderedSame
        let isK = normalizedOutcome == "K" || normalizedOutcome == "ꓘ"
        let isFoul = normalizedOutcome.caseInsensitiveCompare("Foul") == .orderedSame

        if isHBP {
            return (balls, strikes)
        }
        if isWalk {
            balls = 3
            return (balls, strikes)
        }
        if isK {
            strikes = 2
            return (balls, strikes)
        }

        if event.isBall == true {
            balls = min(3, balls + 1)
            return (balls, strikes)
        }
        if event.strikeLooking || event.strikeSwinging {
            strikes = min(2, strikes + 1)
            return (balls, strikes)
        }
        if isFoul {
            if strikes < 2 {
                strikes += 1
            }
            return (balls, strikes)
        }
        if event.isStrike {
            strikes = min(2, strikes + 1)
        }

        return (balls, strikes)
    }

    @ViewBuilder
    private func countCircle(
        isFilled: Bool,
        fillColor: Color,
        strokeColor: Color
    ) -> some View {
        ZStack {
            Circle()
                .fill(isFilled ? fillColor.opacity(0.9) : Color.clear)
            Circle()
                .stroke(strokeColor, lineWidth: 2)
        }
        .frame(width: 24, height: 24)
        .frame(width: 42, height: 42)
        .contentShape(Rectangle())
    }

    private func handleSave() {
        if requiresBatterPromptBeforeSave() {
            pendingSaveIntent = .pitchEvent
            showMissingBatterPrompt = true
            return
        }
        performSave(.pitchEvent)
    }

    private func handlePitchOnlySave() {
        if requiresBatterPromptBeforeSave() {
            pendingSaveIntent = .pitchOnly
            showMissingBatterPrompt = true
            return
        }
        performSave(.pitchOnly)
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
            opponentJersey: effectiveOpponentJersey,
            opponentBatterId: effectiveOpponentBatterId,
            practiceId: selectedPracticeId,
            pitcherId: selectedPitcherId,
            strikeSwingingMarker: isStrikeSwinging ? strikeSwingingSymbol : nil,
            strikeLookingMarker: isStrikeLooking ? strikeLookingSymbol : nil,
            ballMarker: isBall ? ballSymbol : nil,
            foulMarker: selectedOutcome == "Foul" ? foulSymbol : nil
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
                    Text(hasSelectedLocation ? "Location: \(pendingResultLabel ?? "")" : "Location")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(hasSelectedLocation ? .blue : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if let calledPitch = pitchCall?.pitch, !calledPitch.isEmpty {
                        let calledLocation = pitchCall?.location.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let calledText = calledLocation.isEmpty
                            ? "Called: \(calledPitch)"
                            : "Called: \(calledPitch) • \(calledLocation)"
                        Text(calledText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                } 
                .padding(.top, 8)

                Divider()

                ToggleSection(
                    isStrikeSwinging: $isStrikeSwinging,
                    isStrikeLooking: $isStrikeLooking,
                    isWildPitch: $isWildPitch,
                    isPassedBall: $isPassedBall,
                    isBall: $isBall,
                    isHitBatter: $isHitBatter,
                    isError: $isError,
                    selectedOutcome: $selectedOutcome,
                    selectedDescriptor: $selectedDescriptor,
                    isSwingingDisabled: isTopToggleDisabled(.swinging),
                    isLookingDisabled: isTopToggleDisabled(.looking),
                    isBallDisabled: isTopToggleDisabled(.ball),
                    isWildPitchDisabled: isTopToggleDisabled(.wildPitch),
                    isPassedBallDisabled: isTopToggleDisabled(.passedBall),
                    isHitBatterDisabled: isTopToggleDisabled(.hitBatter),
                    isOutcomeDisabled: isOutcomeDisabled,
                    onRequestSymbolPicker: { target in
                        symbolPickerTarget = target
                    },
                    onFoulActivated: {
                        symbolPickerTarget = .foul
                    }
                )

                Divider()

                OutcomeButtonsSection(
                    selectedOutcome: $selectedOutcome,
                    selectedDescriptor: $selectedDescriptor,
                    isOutcomeDisabled: isOutcomeDisabled
                )
                .padding(.horizontal)

                EventButtonsRow(
                    isWildPitch: $isWildPitch,
                    isPassedBall: $isPassedBall,
                    isHitBatter: $isHitBatter,
                    isError: $isError,
                    selectedOutcome: $selectedOutcome,
                    isWildPitchDisabled: isTopToggleDisabled(.wildPitch),
                    isPassedBallDisabled: isTopToggleDisabled(.passedBall),
                    isHitBatterDisabled: isTopToggleDisabled(.hitBatter),
                    isErrorDisabled: isOutcomeDisabled("E")
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

                VStack(alignment: .leading, spacing: 10) {
                    Text("Count")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Balls")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                ForEach(0..<3, id: \.self) { idx in
                                    let value = idx + 1
                                    Button {
                                        // Tap same filled value to step down by one, else set to that value.
                                        confirmedBallsCount = (confirmedBallsCount == value) ? max(0, value - 1) : value
                                        onCountChanged?(confirmedBallsCount, confirmedStrikesCount)
                                    } label: {
                                        countCircle(
                                            isFilled: value <= confirmedBallsCount,
                                            fillColor: .red,
                                            strokeColor: .red
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Strikes")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                ForEach(0..<2, id: \.self) { idx in
                                    let value = idx + 1
                                    Button {
                                        // Tap same filled value to step down by one, else set to that value.
                                        confirmedStrikesCount = (confirmedStrikesCount == value) ? max(0, value - 1) : value
                                        onCountChanged?(confirmedBallsCount, confirmedStrikesCount)
                                    } label: {
                                        countCircle(
                                            isFilled: value <= confirmedStrikesCount,
                                            fillColor: .green,
                                            strokeColor: .green
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Text("Count: \(confirmedBallsCount)-\(confirmedStrikesCount)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

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
            .confirmationDialog(symbolPickerTitle, isPresented: Binding(
                get: { symbolPickerTarget != nil },
                set: { presented in
                    if !presented { symbolPickerTarget = nil }
                }
            ), titleVisibility: .visible) {
                ForEach(symbolPickerOptions, id: \.self) { symbol in
                    Button {
                        applySelectedSymbol(symbol)
                    } label: {
                        Text(symbolMenuTitle(symbol))
                    }
                }
                Button("Cancel", role: .cancel) {
                    symbolPickerTarget = nil
                }
            }
            .onChange(of: isStrikeSwinging) { _, newValue in
                if !newValue { strikeSwingingSymbol = nil }
            }
            .onChange(of: isStrikeLooking) { _, newValue in
                if !newValue { strikeLookingSymbol = nil }
            }
            .onChange(of: isBall) { _, newValue in
                if !newValue { ballSymbol = nil }
            }
            .onChange(of: selectedOutcome) { _, newValue in
                if newValue == "Foul" {
                    if foulSymbol == nil {
                        symbolPickerTarget = .foul
                    }
                } else {
                    foulSymbol = nil
                }
            }
            .onChange(of: currentCountSeed?.balls) { _, _ in
                syncManualCountFromCurrentSeed()
            }
            .onChange(of: currentCountSeed?.strikes) { _, _ in
                syncManualCountFromCurrentSeed()
            }
            .onChange(of: isPresented) { _, newValue in
                guard newValue else { return }
                didInitializeManualCount = false
                initializeManualCountIfNeeded()
            }
            .onAppear { initializeManualCountIfNeeded() }
            .alert("Result Location Required", isPresented: $showMissingLocationPrompt) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Select a result location on the strike zone before saving.")
            }
            .sheet(isPresented: $showMissingBatterPrompt) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("No batter selected")
                        .font(.headline)
                    Text("Do you want to assign this pitch to a batter before saving?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(lineupBatters) { cell in
                                let isSelected = effectiveOpponentBatterId == cell.id.uuidString
                                Button {
                                    overrideOpponentBatterId = cell.id.uuidString
                                    overrideOpponentJersey = cell.jerseyNumber
                                    let intent = pendingSaveIntent ?? .pitchEvent
                                    pendingSaveIntent = nil
                                    showMissingBatterPrompt = false
                                    performSave(intent)
                                } label: {
                                    Text("#\(cell.jerseyNumber)")
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    HStack(spacing: 10) {
                        Button("Save Without Batter") {
                            let intent = pendingSaveIntent ?? .pitchEvent
                            pendingSaveIntent = nil
                            overrideOpponentBatterId = nil
                            overrideOpponentJersey = nil
                            showMissingBatterPrompt = false
                            performSave(intent)
                        }
                        .buttonStyle(.bordered)

                        Button("Cancel", role: .cancel) {
                            pendingSaveIntent = nil
                            showMissingBatterPrompt = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .presentationDetents([.fraction(0.3), .medium])
                .presentationDragIndicator(.visible)
            }
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
    var isOutcomeDisabled: (String) -> Bool
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Safe:")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)
                OutcomeButton(label: "1B", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("1B"), usesDescriptorSelection: false)
                OutcomeButton(label: "2B", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("2B"), usesDescriptorSelection: false)
                OutcomeButton(label: "3B", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("3B"), usesDescriptorSelection: false)
                OutcomeButton(label: "HR", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("HR"), usesDescriptorSelection: false)
            }
            HStack(spacing: 8) {
                OutcomeButton(label: "Grounder", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Grounder"), usesDescriptorSelection: true)
                OutcomeButton(label: "Line", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Line"), usesDescriptorSelection: true)
                OutcomeButton(label: "Pop", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Pop"), usesDescriptorSelection: true)
                OutcomeButton(label: "Fly", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Fly"), usesDescriptorSelection: true)
                OutcomeButton(label: "Bunt", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Bunt"), usesDescriptorSelection: true)
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
