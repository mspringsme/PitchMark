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

private let pitchResultSelectedGradient = LinearGradient(
    colors: [
        Color(red: 0.08, green: 0.44, blue: 0.32),
        Color(red: 0.73, green: 0.23, blue: 0.18)
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private extension View {
    @ViewBuilder
    func pitchResultSelectionBackground(isSelected: Bool, inactiveOpacity: Double = 0.1) -> some View {
        if isSelected {
            background(pitchResultSelectedGradient)
        } else {
            background(Color.gray.opacity(inactiveOpacity))
        }
    }
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
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .pitchResultSelectionBackground(isSelected: isSelected)
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
        .contentShape(Rectangle())
    }
}

private struct AssetOutcomeButton: View {
    let assetName: String
    let width: CGFloat
    let height: CGFloat
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: width, height: height)
                .padding(4)
                .pitchResultSelectionBackground(isSelected: isSelected, inactiveOpacity: 0.08)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSelected ? Color.black.opacity(0.8) : Color.black.opacity(0.08), lineWidth: isSelected ? 1.6 : 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
        .contentShape(Rectangle())
    }
}

/// Stage 2 of the ball-in-play field: where the batter ended up and what
/// they're credited with. Replaced the 1B/2B/3B/HR mini-diamond that sat at
/// the end of the outcome scroll, where nobody found it. Rules live in
/// BaseRunnerRules.swift; this view only collects the three answers.
///
/// Phase 1 places the batter only. Phase 2 adds runner tokens on the bases
/// with the same tap-a-token, tap-a-base interaction.
private struct BasesDiamondView: View {
    @Binding var reachedBase: Int?
    @Binding var credit: BatterCredit?
    @Binding var extraBasesOn: ExtraBasesReason?
    let batterLabel: String
    let sprayRegion: String?
    let isBatterOut: Bool
    /// The Error button is on: a newly placed batter reached on error.
    let prefersReachedOnError: Bool
    let onBackToField: () -> Void

    private func selectBase(_ base: Int) {
        if reachedBase == base {
            reachedBase = nil
            credit = nil
            extraBasesOn = nil
            return
        }
        reachedBase = base
        credit = prefersReachedOnError ? .reachedOnError : BaseRunnerRules.defaultCredit(reached: base)
        extraBasesOn = nil
    }

    private var needsExtraBasesReason: Bool {
        guard let reachedBase, let credit else { return false }
        return BaseRunnerRules.needsExtraBasesReason(credit: credit, reached: reachedBase)
    }

    private func selectCredit(_ option: BatterCredit) {
        guard let reachedBase else { return }
        credit = option
        if !BaseRunnerRules.needsExtraBasesReason(credit: option, reached: reachedBase) {
            extraBasesOn = nil
        }
    }

    private func basePoint(_ base: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        switch base {
        case Base.first: return CGPoint(x: center.x + radius, y: center.y)
        case Base.second: return CGPoint(x: center.x, y: center.y - radius)
        case Base.third: return CGPoint(x: center.x - radius, y: center.y)
        default: return CGPoint(x: center.x, y: center.y + radius)
        }
    }

    private func diamondPath(center: CGPoint, radius: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: center.x, y: center.y + radius))
            path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            path.addLine(to: CGPoint(x: center.x, y: center.y - radius))
            path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
            path.closeSubpath()
        }
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .frame(minWidth: 52, minHeight: 36)
                .pitchResultSelectionBackground(isSelected: isSelected)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.black.opacity(0.8) : Color.black.opacity(0.08), lineWidth: isSelected ? 1.6 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func creditTitle(_ option: BatterCredit) -> String {
        option == .reachedOnError ? "E (ROE)" : option.rawValue
    }

    private var prompt: String {
        if isBatterOut { return "Batter out - tap a base to mark them safe instead" }
        guard let reachedBase else { return "Tap the base the batter reached" }
        guard let credit else { return "Safe at \(Base.name(reachedBase))" }
        if BaseRunnerRules.needsExtraBasesReason(credit: credit, reached: reachedBase), extraBasesOn == nil {
            return "How did they get the extra base?"
        }
        return "Safe at \(Base.name(reachedBase))"
    }

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: onBackToField) {
                    Label("Field", systemImage: "chevron.left")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)

                Text(sprayRegion.map { "Hit to \($0)" } ?? "No hit location yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)
            }

            Text(prompt)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2 + side * 0.04)
                let radius = side * 0.34
                let batterBase = reachedBase ?? Base.home
                let batterPoint: CGPoint = {
                    let p = basePoint(batterBase == Base.scored ? Base.home : batterBase, center: center, radius: radius)
                    // Sit just inside the bag so the bag stays visible and tappable.
                    return CGPoint(x: p.x + (center.x - p.x) * 0.28, y: p.y + (center.y - p.y) * 0.28)
                }()

                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.22, green: 0.52, blue: 0.27))

                    diamondPath(center: center, radius: radius * 1.22)
                        .fill(Color(red: 0.72, green: 0.52, blue: 0.34))

                    diamondPath(center: center, radius: radius * 0.74)
                        .fill(Color(red: 0.25, green: 0.57, blue: 0.3))

                    diamondPath(center: center, radius: radius)
                        .stroke(Color.white.opacity(0.85), lineWidth: 2)

                    if let reachedBase, reachedBase > Base.home {
                        // Path run, home through each base reached.
                        Path { path in
                            path.move(to: basePoint(Base.home, center: center, radius: radius))
                            for base in 1...min(reachedBase, Base.scored) {
                                path.addLine(to: basePoint(base == Base.scored ? Base.home : base, center: center, radius: radius))
                            }
                        }
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [8, 6]))
                    }

                    ForEach([Base.first, Base.second, Base.third, Base.scored], id: \.self) { base in
                        let point = basePoint(base == Base.scored ? Base.home : base, center: center, radius: radius)
                        let isSelected = reachedBase == base
                        Button {
                            selectBase(base)
                        } label: {
                            VStack(spacing: 4) {
                                if base == Base.scored {
                                    Image(systemName: "pentagon.fill")
                                        .font(.system(size: 18))
                                        .rotationEffect(.degrees(180))
                                        .foregroundStyle(isSelected ? Color.pitchMarkActiveGray : .white)
                                } else {
                                    Rectangle()
                                        .fill(isSelected ? Color.pitchMarkActiveGray : .white)
                                        .frame(width: 18, height: 18)
                                        .rotationEffect(.degrees(45))
                                }
                                Text(base == Base.scored ? "Score" : Base.name(base))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 1)
                            }
                            .frame(width: 64, height: 64)
                            .background(
                                Circle()
                                    .fill(isSelected ? Color.white.opacity(0.35) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .position(point)
                    }

                    if !isBatterOut {
                        Text(batterLabel)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.pitchMarkActiveGray))
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
                            .position(batterPoint)
                            .allowsHitTesting(false)
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: reachedBase)
                    }
                }
            }
            .frame(height: 280)

            if !isBatterOut {
                VStack(spacing: 8) {
                    if let reachedBase {
                        Text("Credit")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(BaseRunnerRules.creditOptions(reached: reachedBase), id: \.self) { option in
                                chip(creditTitle(option), isSelected: credit == option) {
                                    selectCredit(option)
                                }
                            }
                        }
                    }

                    // Always shown so the option is discoverable; live only
                    // once the credit is worth fewer bases than the batter took.
                    Text("Extra bases on")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    HStack(spacing: 6) {
                        ForEach(ExtraBasesReason.allCases, id: \.self) { reason in
                            chip(reason.label, isSelected: extraBasesOn == reason) {
                                extraBasesOn = (extraBasesOn == reason) ? nil : reason
                            }
                        }
                    }
                    .disabled(!needsExtraBasesReason)
                    .opacity(needsExtraBasesReason ? 1 : 0.4)
                }
            }
        }
    }
}

private struct ResultCircleButton: View {
    let title: String
    let isSelected: Bool
    let selectedColor: Color
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isSelected ? selectedColor.opacity(0.9) : Color.gray.opacity(0.16))
                Circle()
                    .stroke(isSelected ? selectedColor : Color.black.opacity(0.28), lineWidth: isSelected ? 2 : 1.2)

                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 46, height: 46)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
        .contentShape(Rectangle())
    }
}

private struct SafeOutButtonsRow: View {
    @Binding var selectedOutcome: String?
    @Binding var selectedDescriptor: String?
    @Binding var isStrikeSwinging: Bool
    @Binding var isStrikeLooking: Bool
    @Binding var isBall: Bool
    @Binding var isHitTagSelected: Bool
    @Binding var isHitBatter: Bool
    @Binding var isFoulSelected: Bool
    let isSafeDisabled: Bool
    let isOutDisabled: Bool
    /// Safe no longer means "single": it opens the bases stage, and the
    /// batter's base there sets the outcome.
    let onSelectSafe: () -> Void

    private var safeCircleSelected: Bool {
        if isHitTagSelected { return true }
        guard let selectedOutcome else { return false }
        return ["1B", "2B", "3B", "HR"].contains(selectedOutcome)
    }

    private var outCircleSelected: Bool {
        guard let selectedOutcome else { return false }
        return ["Out", "K", "ꓘ"].contains(selectedOutcome)
    }

    private func selectSafeCategory() {
        if safeCircleSelected {
            if isHitTagSelected {
                isHitTagSelected = false
            }
            if let selectedOutcome, ["1B", "2B", "3B", "HR"].contains(selectedOutcome) {
                self.selectedOutcome = nil
            } else if selectedOutcome == nil {
                self.selectedOutcome = nil
            }
            selectedDescriptor = nil
            isFoulSelected = false
            return
        }

        isHitTagSelected = false
        isFoulSelected = false
        onSelectSafe()
    }

    private func selectOutCategory() {
        let next = selectedOutcome != "Out"
        selectedOutcome = next ? "Out" : nil
        if next {
            isStrikeSwinging = false
            isStrikeLooking = false
            isBall = false
            isFoulSelected = false
            isHitTagSelected = false
            isHitBatter = false
            selectedDescriptor = nil
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ResultCircleButton(
                title: "Safe",
                isSelected: safeCircleSelected,
                selectedColor: .red,
                isDisabled: isSafeDisabled
            ) {
                selectSafeCategory()
            }

            ResultCircleButton(
                title: "Out",
                isSelected: outCircleSelected,
                selectedColor: .green,
                isDisabled: isOutDisabled
            ) {
                selectOutCategory()
            }
        }
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
    @Binding var isFoulSelected: Bool
    @Binding var isHitTagSelected: Bool
    @Binding var selectedOutcome: String?
    @Binding var selectedDescriptor: String?
    let isSwingingDisabled: Bool
    let isLookingDisabled: Bool
    let isBallDisabled: Bool
    let isWildPitchDisabled: Bool
    let isPassedBallDisabled: Bool
    let isHitBatterDisabled: Bool
    let isOutcomeDisabled: (String) -> Bool

    private func toggleButton(
        _ title: String,
        leadingSystemImage: String? = nil,
        isOn: Bool,
        disabled: Bool = false,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        alignment: Alignment = .center,
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
                    .foregroundStyle(isOn ? .white : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: width, height: height, alignment: alignment)
            .pitchResultSelectionBackground(isSelected: isOn)
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                toggleButton(
                    "Swinging",
                    leadingSystemImage: "s.circle",
                    isOn: isStrikeSwinging,
                    disabled: isSwingingDisabled,
                    width: 104,
                    height: 36,
                    alignment: .leading
                ) {
                    let next = !isStrikeSwinging
                    isStrikeSwinging = next
                    if next {
                        isStrikeLooking = false
                        isBall = false
                        isHitTagSelected = false
                        isHitBatter = false
                        selectedDescriptor = nil
                        if isFoulSelected || selectedOutcome == "Walk" || selectedOutcome == "K" || selectedOutcome == "ꓘ" || selectedOutcome == "HBP" {
                            selectedOutcome = nil
                        } else if let selectedOutcome, ["1B", "2B", "3B", "HR"].contains(selectedOutcome) {
                            self.selectedOutcome = nil
                        }
                    }
                }

                toggleButton(
                    "Looking",
                    leadingSystemImage: "s.circle",
                    isOn: isStrikeLooking,
                    disabled: isLookingDisabled,
                    width: 104,
                    height: 36,
                    alignment: .leading
                ) {
                    let next = !isStrikeLooking
                    isStrikeLooking = next
                    if next {
                        isStrikeSwinging = false
                        isBall = false
                        isHitTagSelected = false
                        isHitBatter = false
                        selectedDescriptor = nil
                        if isFoulSelected || selectedOutcome == "Walk" || selectedOutcome == "K" || selectedOutcome == "ꓘ" || selectedOutcome == "HBP" {
                            selectedOutcome = nil
                        } else if let selectedOutcome, ["1B", "2B", "3B", "HR"].contains(selectedOutcome) {
                            self.selectedOutcome = nil
                        }
                    }
                }
            }

            VStack(spacing: 8) {
                OutcomeButton(label: "K", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("K"), usesDescriptorSelection: false)
                    .frame(width: 36, height: 36)

                OutcomeButton(label: "ꓘ", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("ꓘ"), usesDescriptorSelection: false)
                    .frame(width: 36, height: 36)
            }

            HStack(spacing: 0) {
                Spacer(minLength: 0)

                Button {
                    let next = !isFoulSelected
                    isFoulSelected = next
                    if next {
                        isBall = false
                        if selectedOutcome != "Out" {
                            selectedOutcome = nil
                        }
                    }
                } label: {
                    Text("Foul")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isFoulSelected ? .white : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(width: 80, height: 48)
                        .pitchResultSelectionBackground(isSelected: isFoulSelected)
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(isOutcomeDisabled("Foul"))
                .opacity(isOutcomeDisabled("Foul") ? 0.4 : 1)

                Spacer(minLength: 10)

                toggleButton(
                    "Ball",
                    isOn: isBall,
                    disabled: isBallDisabled,
                    width: 80,
                    height: 48
                ) {
                    isBall.toggle()
                    if isBall {
                        isStrikeSwinging = false
                        isStrikeLooking = false
                        if isFoulSelected || selectedOutcome == "K" || selectedOutcome == "ꓘ" {
                            selectedOutcome = nil
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(height: 56)
        }
        .padding(.horizontal)
    }
}

private struct EventButtonsRow: View {
    @Binding var isWildPitch: Bool
    @Binding var isPassedBall: Bool
    @Binding var isError: Bool
    @Binding var selectedOutcome: String?
    let isWildPitchDisabled: Bool
    let isPassedBallDisabled: Bool
    let isErrorDisabled: Bool

    private func toggleButton(
        _ title: String,
        isOn: Bool,
        disabled: Bool = false,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? .white : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(width: width)
                .pitchResultSelectionBackground(isSelected: isOn)
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    var body: some View {
        let buttonWidth: CGFloat = 102

        HStack(spacing: 8) {
            toggleButton("Wild Pitch", isOn: isWildPitch, disabled: isWildPitchDisabled, width: buttonWidth) {
                let next = !isWildPitch
                isWildPitch = next
                if next { isPassedBall = false }
            }

            toggleButton("Passed Ball", isOn: isPassedBall, disabled: isPassedBallDisabled, width: buttonWidth) {
                let next = !isPassedBall
                isPassedBall = next
                if next { isWildPitch = false }
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
    var horizontalPadding: CGFloat = 12
    let action: () -> Void

    var body: some View {
        let shape = Capsule()

        Button(action: action) {
            HStack(spacing: 6) {
                if !systemImage.isEmpty {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(.bold))
            .foregroundColor(isEnabled ? .white : .gray)
            .padding(.horizontal, horizontalPadding + 6)
            .padding(.vertical, 12)
            .background(
                shape
                    .fill(isEnabled ? foregroundColor : Color(.systemGray5))
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        // Without this the button only *looks* disabled - it stayed tappable and
        // would still fire its action while greyed out.
        .disabled(!isEnabled)
        .overlay {
            shape
                .stroke((isEnabled ? foregroundColor.opacity(0.95) : .gray.opacity(0.25)), lineWidth: 1.5)
                .allowsHitTesting(false)
        }
        .shadow(color: isEnabled ? foregroundColor.opacity(0.28) : .clear, radius: 8, x: 0, y: 4)
        .animation(.easeOut(duration: 0.15), value: isEnabled)
        .opacity(isEnabled ? 1 : 0.72)
    }
}

struct PitchResultSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool
    @Binding var isStrikeSwinging: Bool
    @Binding var isStrikeLooking: Bool
    @Binding var isWildPitch: Bool
    @Binding var isPassedBall: Bool
    @Binding var isBall: Bool
    @Binding var selectedOutcome: String?
    @Binding var selectedDescriptor: String?
    @Binding var isError: Bool
    var isDemoMode: Bool = false
    @State private var isHitBatter = false
    @State private var isHitTagSelected = false
    @State private var isFoulSelected = false

    @State private var battedBallRegionName: String? = nil
    @State private var battedBallSelection: OverlaySelection? = nil
    @State private var battedBallTapNormalized: CGPoint? = nil

    /// Ball-in-play field stage: spray location first, then where the batter
    /// ended up. See BasesDiamondView.
    private enum FieldStage { case spray, bases }
    @State private var fieldStage: FieldStage = .spray
    @State private var batterReachedBase: Int? = nil
    @State private var batterCredit: BatterCredit? = nil
    @State private var batterExtraBasesOn: ExtraBasesReason? = nil

    @State private var showFieldOverlay: Bool = false

    @State private var showMissingBatterPrompt: Bool = false
    private struct SavedPlayReviewDraft: Identifiable {
        let id = UUID()
        let title: String
        let summaryLines: [String]
        let event: PitchEvent
    }

    @State private var savedPlayReviewDraft: SavedPlayReviewDraft? = nil
    @State private var savedPlayReviewTitle: String = "Saved Play"
    @State private var savedPlayReviewSummaryLines: [String] = []
    @State private var savedPlayReviewEvent: PitchEvent? = nil
    /// The count *before* this pitch. The displayed count is derived from this
    /// plus the current selection - it is never mutated directly.
    @State private var countSeed: AtBatCount = .start
    @State private var didInitializeManualCount: Bool = false
    /// Set only when the user taps the count circles to correct the number by
    /// hand. Keeping this separate from the seed is what stops a manual
    /// correction from being incremented a second time by the pitch rules.
    @State private var manualCountOverride: AtBatCount? = nil
    @State private var overrideOpponentJersey: String? = nil
    @State private var overrideOpponentBatterId: String? = nil
    @State private var showMissingLocationPrompt: Bool = false
    @State private var shouldScrollToInPlayOutcome: Bool = false

    private let inPlayOutcomeAnchorID = "inPlayOutcomeAnchor"

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
    /// The coach's estimate of the opposing catcher's actual call, captured by
    /// `CatcherEstimateView` before this sheet appears. Carried straight
    /// through to the saved `PitchEvent`; nil unless this is a Catcher-mode
    /// pitch the coach chose to guess on.
    var catcherEstimate: PitchCall? = nil
    let batterSide: BatterSide
    let selectedTemplateId: String?
    let currentMode: PitchMode
    let selectedGameId: String?
    let selectedOpponentJersey: String?
    let selectedOpponentBatterId: String?
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

    private var effectiveLocationLabel: String? {
        let explicit = pendingResultLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicit.isEmpty {
            return explicit
        }

        let calledPitchName = pitchCall?.pitch.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let calledLocation = pitchCall?.location.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if calledPitchName == "Catcher", !calledLocation.isEmpty {
            return calledLocation
        }

        return nil
    }

    private var hasSelectedLocation: Bool {
        effectiveLocationLabel != nil
    }

    private func resultIsInsideStrikeZone(_ rawLocation: String) -> Bool {
        let trimmed = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.hasPrefix("strike ") { return true }
        if lower.hasPrefix("ball ") { return false }

        let legacyStrikeLabels: Set<String> = [
            "up & out", "up", "up & in",
            "out", "middle", "in",
            "↓ & out", "↓", "↓ & in",
            "down & out", "down", "down & in",
            "low & out", "low", "low & in",
            "high"
        ]
        return legacyStrikeLabels.contains(lower)
    }

    private func resetSelections() {
        isStrikeSwinging = false
        isStrikeLooking = false
        isWildPitch = false
        isPassedBall = false
        isBall = false
        isHitBatter = false
        isFoulSelected = false
        selectedOutcome = nil
        selectedDescriptor = nil
        isHitTagSelected = false
        isError = false
        battedBallRegionName = nil
        battedBallSelection = nil
        battedBallTapNormalized = nil
        fieldStage = .spray
        batterReachedBase = nil
        batterCredit = nil
        batterExtraBasesOn = nil
        showMissingBatterPrompt = false
        overrideOpponentJersey = nil
        overrideOpponentBatterId = nil
        shouldScrollToInPlayOutcome = false
    }

    @ViewBuilder
    private var interactiveSections: some View {
        if currentMode == .scout {
            reviewCountAndFieldSection
                .id(inPlayOutcomeAnchorID)

            Divider()

            ToggleSection(
                isStrikeSwinging: $isStrikeSwinging,
                isStrikeLooking: $isStrikeLooking,
                isWildPitch: $isWildPitch,
                isPassedBall: $isPassedBall,
                isBall: $isBall,
                isHitBatter: $isHitBatter,
                isError: $isError,
                isFoulSelected: $isFoulSelected,
                isHitTagSelected: $isHitTagSelected,
                selectedOutcome: $selectedOutcome,
                selectedDescriptor: $selectedDescriptor,
                isSwingingDisabled: isTopToggleDisabled(.swinging),
                isLookingDisabled: isTopToggleDisabled(.looking),
                isBallDisabled: isTopToggleDisabled(.ball),
                isWildPitchDisabled: isTopToggleDisabled(.wildPitch),
                isPassedBallDisabled: isTopToggleDisabled(.passedBall),
                isHitBatterDisabled: isTopToggleDisabled(.hitBatter),
                isOutcomeDisabled: isOutcomeDisabled
            )

            Divider()

            OutcomeButtonsSection(
                selectedOutcome: $selectedOutcome,
                selectedDescriptor: $selectedDescriptor,
                isHitTagSelected: $isHitTagSelected,
                isHitBatter: $isHitBatter,
                isError: $isError,
                isFoulSelected: $isFoulSelected,
                isWildPitch: $isWildPitch,
                isPassedBall: $isPassedBall,
                isOutcomeDisabled: isOutcomeDisabled,
                isWildPitchDisabled: isTopToggleDisabled(.wildPitch),
                isPassedBallDisabled: isTopToggleDisabled(.passedBall)
            )
            .padding(.horizontal)
        } else {
            ToggleSection(
                isStrikeSwinging: $isStrikeSwinging,
                isStrikeLooking: $isStrikeLooking,
                isWildPitch: $isWildPitch,
                isPassedBall: $isPassedBall,
                isBall: $isBall,
                isHitBatter: $isHitBatter,
                isError: $isError,
                isFoulSelected: $isFoulSelected,
                isHitTagSelected: $isHitTagSelected,
                selectedOutcome: $selectedOutcome,
                selectedDescriptor: $selectedDescriptor,
                isSwingingDisabled: isTopToggleDisabled(.swinging),
                isLookingDisabled: isTopToggleDisabled(.looking),
                isBallDisabled: isTopToggleDisabled(.ball),
                isWildPitchDisabled: isTopToggleDisabled(.wildPitch),
                isPassedBallDisabled: isTopToggleDisabled(.passedBall),
                isHitBatterDisabled: isTopToggleDisabled(.hitBatter),
                isOutcomeDisabled: isOutcomeDisabled
            )

            Divider()

            OutcomeButtonsSection(
                selectedOutcome: $selectedOutcome,
                selectedDescriptor: $selectedDescriptor,
                isHitTagSelected: $isHitTagSelected,
                isHitBatter: $isHitBatter,
                isError: $isError,
                isFoulSelected: $isFoulSelected,
                isWildPitch: $isWildPitch,
                isPassedBall: $isPassedBall,
                isOutcomeDisabled: isOutcomeDisabled,
                isWildPitchDisabled: isTopToggleDisabled(.wildPitch),
                isPassedBallDisabled: isTopToggleDisabled(.passedBall)
            )
            .padding(.horizontal)

            Divider()

            reviewCountAndFieldSection
                .id(inPlayOutcomeAnchorID)
        }
    }

    @ViewBuilder
    private var reviewCountAndFieldSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {

                HStack(spacing: 16) {
                    Spacer()
                    VStack(alignment: .center, spacing: 6) {
                        Text("Balls")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(0..<3, id: \.self) { idx in
                                let value = idx + 1
                                Button {
                                    // Tap same filled value to step down by one, else set to that value.
                                    let current = resolvedCount
                                    let nextBalls = (current.balls == value) ? max(0, value - 1) : value
                                    manualCountOverride = AtBatCount(
                                        balls: nextBalls,
                                        strikes: current.strikes
                                    )
                                } label: {
                                    countCircle(
                                        isFilled: value <= resolvedCount.balls,
                                        fillColor: .red,
                                        strokeColor: .red
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .center, spacing: 6) {
                        Text("Strikes")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(0..<2, id: \.self) { idx in
                                let value = idx + 1
                                Button {
                                    // Tap same filled value to step down by one, else set to that value.
                                    let current = resolvedCount
                                    let nextStrikes = (current.strikes == value) ? max(0, value - 1) : value
                                    manualCountOverride = AtBatCount(
                                        balls: current.balls,
                                        strikes: nextStrikes
                                    )
                                } label: {
                                    countCircle(
                                        isFilled: value <= resolvedCount.strikes,
                                        fillColor: .green,
                                        strokeColor: .green
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Spacer()

                    Text("Count: \(resolvedCount.displayText)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .layoutPriority(1)
                    Spacer()
                }
            }

            Divider()
                .padding(.top, -6)

            HStack(spacing: 8) {
                Spacer()
                Text(fieldStage == .bases ? "Batter result" : "Ball in play location")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    resetSelections()
                    countSeed = .start
                    manualCountOverride = nil
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                Spacer()
            }

            if fieldStage == .bases {
                BasesDiamondView(
                    reachedBase: $batterReachedBase,
                    credit: $batterCredit,
                    extraBasesOn: $batterExtraBasesOn,
                    batterLabel: effectiveOpponentJersey.map { "#\($0)" } ?? "B",
                    sprayRegion: battedBallRegionName,
                    isBatterOut: selectedOutcome == "Out",
                    prefersReachedOnError: isError,
                    onBackToField: { fieldStage = .spray }
                )
            } else {
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
                    displayImageName: "FieldImage2",
                    showsDismissControls: false
                )
                .frame(height: 520)
                .padding(.horizontal, -12)
                .padding(.top, -12)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        ["Grounder", "Line", "Pop", "Fly", "Bunt"]
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
        let foulSelected = isFoulSelected

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
        if label == "Hit" && isHitBatter { return true }
        if isHitTagSelected && ["Hit Batter", "Wild Pitch", "Passed Ball"].contains(label) {
            return true
        }
        if isFoulSelected && label == "Hit Batter" {
            return true
        }

        let strikeSelected = isStrikeSwinging || isStrikeLooking
        let hrSelected = selectedOutcome == "HR"
        let walkSelected = selectedOutcome == "Walk"
        let foulSelected = isFoulSelected
        let popSelected = selectedDescriptor == "Pop"
        let buntSelected = selectedDescriptor == "Bunt"
        let wpOrPbSelected = isWildPitch || isPassedBall

        // K buttons require matching strike toggle.
        if label == "K" { return !isStrikeSwinging }
        if label == "ꓘ" { return !isStrikeLooking }

        if strikeSelected && ["Ball", "Foul", "E", "Hit", "Hit Batter", "1B", "2B", "3B", "HR"].contains(label) {
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

        if foulSelected && ["1B", "2B", "3B", "HR", "Walk"].contains(label) {
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

    private func strikeMarkerSymbol(outcome: String) -> String {
        if outcome == "K" || outcome == "ꓘ" {
            return "3.circle"
        }
        return "\(max(1, min(2, resolvedCount.strikes))).circle"
    }

    private func ballMarkerSymbol(outcome: String, prior: (balls: Int, strikes: Int)) -> String {
        if outcome.caseInsensitiveCompare("Walk") == .orderedSame || prior.balls >= 3 {
            return "4.circle"
        }
        return "\(max(1, min(3, resolvedCount.balls))).circle"
    }

    private func foulMarkerSymbol(prior: (balls: Int, strikes: Int)) -> String {
        return "\(max(1, min(2, prior.strikes + 1))).circle"
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

    private func performSave() {
        guard hasSelectedLocation else {
            showMissingLocationPrompt = true
            onMissingLocation?()
            return
        }
        guard var event = buildCurrentEvent() else { return }

        // The saved count is exactly what the sheet was showing. Both come from
        // AtBatCountRules, so the preview can no longer disagree with the record.
        let terminal = resolvedTerminal
        event.applyCount(resolvedCount, terminal: terminal)
        if terminal == .walk {
            event.outcome = "Walk"
        }

        event.logDebugPayload()
        savedPlayReviewEvent = event
        savedPlayReviewTitle = "Save Pitch"
        savedPlayReviewSummaryLines = outcomeSummaryLines(for: event)
        savedPlayReviewDraft = SavedPlayReviewDraft(
            title: savedPlayReviewTitle,
            summaryLines: savedPlayReviewSummaryLines,
            event: event
        )
    }

    private func commitReviewedSavedPlayEvent(_ event: PitchEvent) {
        onCountChanged?(event.atBatBalls ?? 0, event.atBatStrikes ?? 0)
        saveAction(event)
        finalizeSavedPlayReview()
    }

    private func finalizeSavedPlayReview() {
        savedPlayReviewDraft = nil
        savedPlayReviewEvent = nil
        savedPlayReviewSummaryLines = []
        isPresented = false
        resetSelections()
        dismiss()
    }

    /// The most recently saved pitch for whichever batter is currently at the
    /// plate. Its `atBatBalls`/`atBatStrikes` are already the right seed for
    /// the next pitch either way - `applyCount` resets them to 0/0 on a
    /// terminal pitch, so there's no need to separately detect an at-bat
    /// boundary here.
    ///
    /// This is preferred over `currentCountSeed` (the live-synced balls/
    /// strikes cache) because that cache is gated by `progressRevision` on
    /// the receiving device and can lag behind a partner's just-saved pitch.
    /// `allPitchEvents` comes from the dedicated pitch-events listener, which
    /// carries no such gate, so it reflects a partner's save sooner - often
    /// before the coalesced progress snapshot does. See the two-device "Ball
    /// 1 instead of Ball 4" bug this was fixed for.
    private var lastPersistedEventForActiveBatter: PitchEvent? {
        let activeBatterId = effectiveOpponentBatterId
        let activeJersey = effectiveOpponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines)
        return allPitchEvents
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
    }

    private func initializeManualCountIfNeeded() {
        guard !didInitializeManualCount else { return }
        let persistedSeed: AtBatCount? = lastPersistedEventForActiveBatter.flatMap { event in
            guard let balls = event.atBatBalls, let strikes = event.atBatStrikes else { return nil }
            return AtBatCount(balls: balls, strikes: strikes)
        }
        let fallback = currentCountSeed ?? suggestedCountSeed ?? (0, 0)
        countSeed = persistedSeed ?? AtBatCount(balls: fallback.balls, strikes: fallback.strikes)
        manualCountOverride = nil
        didInitializeManualCount = true
    }

    /// The count-relevant facts of the pitch currently being composed.
    private var currentPitchFacts: AtBatCountRules.PitchFacts {
        AtBatCountRules.PitchFacts(
            isBall: isBall,
            strikeSwinging: isStrikeSwinging,
            strikeLooking: isStrikeLooking,
            isFoul: isFoulSelected,
            // Location is not consulted for the preview: saving already requires an
            // explicit call (Swinging/Looking/Foul/Ball/Hit), so the explicit facts
            // fully determine the count and preview cannot drift from what is saved.
            locationInStrikeZone: false,
            isHitBatter: isHitBatter,
            outcome: isHitTagSelected ? "Hit" : selectedOutcome
        )
    }

    /// The count shown in the sheet, and the count written onto the saved pitch.
    /// Derived, never mutated - a manual correction replaces it outright rather
    /// than feeding back into the seed.
    private var resolvedCount: AtBatCount {
        manualCountOverride ?? AtBatCountRules.apply(currentPitchFacts, to: countSeed).count
    }

    private var resolvedTerminal: AtBatTerminal? {
        // A hand-corrected count means the user is stating the result directly, so
        // no terminal is inferred for it.
        guard manualCountOverride == nil else { return nil }
        return AtBatCountRules.apply(currentPitchFacts, to: countSeed).terminal
    }

    private func priorCount(for event: PitchEvent) -> (balls: Int, strikes: Int) {
        let baseEvent = lastPersistedEventForActiveBatter

        let preferredSeed: AtBatCount? = didInitializeManualCount
            ? countSeed
            : suggestedCountSeed.map { AtBatCount(balls: $0.balls, strikes: $0.strikes) }

        // `atBatCount` is display text only. It is deliberately not parsed back
        // into a count: it can legitimately hold "Strikeout" / "Ball 4" / "HBP",
        // and treating it as a third source of truth is how the numeric fields and
        // the label used to drift apart.
        let balls = preferredSeed?.balls ?? baseEvent?.atBatBalls ?? 0
        let strikes = preferredSeed?.strikes ?? baseEvent?.atBatStrikes ?? 0
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
            showMissingBatterPrompt = true
            return
        }
        performSave()
    }

    private func buildCurrentEvent() -> PitchEvent? {
        guard let label = effectiveLocationLabel,
              let pitchCall = pitchCall else {
            return nil
        }
        let isCatcherCall = pitchCall.pitch.trimmingCharacters(in: .whitespacesAndNewlines) == "Catcher"
        let locationIsInsideStrikeZone = resultIsInsideStrikeZone(label)
        let normalizedOutcomeBase = (
            isHitBatter
                ? "HBP"
                : (selectedOutcome ?? (isFoulSelected ? "Foul" : ""))
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedIsFoul = isFoulSelected || normalizedOutcomeBase.caseInsensitiveCompare("Foul") == .orderedSame
        let normalizedOutcomeLower = normalizedOutcomeBase.lowercased()
        let inPlayOutcomes: Set<String> = ["1b", "2b", "3b", "hr", "hit", "out"]
        let resultForcesStrike = isStrikeLooking
            || isStrikeSwinging
            || resolvedIsFoul
            || battedBallRegionName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || isHitTagSelected
            || inPlayOutcomes.contains(normalizedOutcomeLower)
        let resolvedIsStrike = locationIsInsideStrikeZone || resultForcesStrike
        let resolvedIsBall = !resultForcesStrike && (isBall || (!isCatcherCall && !locationIsInsideStrikeZone))
        let prior = priorCount(for: PitchEvent(
            id: nil,
            timestamp: Date(),
            pitch: pitchCall.pitch,
            location: label,
            codes: pitchCall.codes,
            isStrike: resolvedIsStrike,
            isBall: resolvedIsBall,
            mode: currentMode,
            calledPitch: pitchCall,
            batterSide: batterSide,
            templateId: selectedTemplateId,
            strikeSwinging: isStrikeSwinging,
            wildPitch: isWildPitch,
            passedBall: isPassedBall,
            strikeLooking: isStrikeLooking,
            outcome: normalizedOutcomeBase.isEmpty ? nil : normalizedOutcomeBase,
            descriptor: selectedDescriptor,
            errorOnPlay: isError,
            battedBallRegion: battedBallRegionName,
            battedBallType: nil,
            battedBallTapX: nil,
            battedBallTapY: nil,
            gameId: selectedGameId,
            opponentJersey: effectiveOpponentJersey,
            opponentBatterId: effectiveOpponentBatterId,
            pitcherId: selectedPitcherId
        ))
        let isTerminalStrikeLooking = isStrikeLooking && prior.strikes >= 2
        let isTerminalStrikeSwinging = isStrikeSwinging && prior.strikes >= 2
        let normalizedOutcome = {
            let trimmed = normalizedOutcomeBase
            if !trimmed.isEmpty { return trimmed }
            if isTerminalStrikeLooking { return "ꓘ" }
            if isTerminalStrikeSwinging { return "K" }
            return ""
        }()

        return PitchEvent(
            id: nil,
            timestamp: Date(),
            pitch: pitchCall.pitch,
            location: label,
            codes: pitchCall.codes,
            isStrike: resolvedIsStrike,
            isBall: resolvedIsBall,
            mode: currentMode,
            calledPitch: pitchCall,
            batterSide: batterSide,
            templateId: selectedTemplateId,
            strikeSwinging: isStrikeSwinging,
            wildPitch: isWildPitch,
            passedBall: isPassedBall,
            strikeLooking: isStrikeLooking,
            outcome: normalizedOutcome.isEmpty ? nil : normalizedOutcome,
            descriptor: {
                if isHitTagSelected {
                    if let selectedDescriptor, !selectedDescriptor.isEmpty {
                        return "\(selectedDescriptor), Hit"
                    }
                    return "Hit"
                }
                return selectedDescriptor
            }(),
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
            pitcherId: selectedPitcherId,
            strikeSwingingMarker: isStrikeSwinging ? strikeMarkerSymbol(outcome: normalizedOutcome) : nil,
            strikeLookingMarker: isStrikeLooking ? strikeMarkerSymbol(outcome: normalizedOutcome) : nil,
            ballMarker: isBall ? ballMarkerSymbol(outcome: normalizedOutcome, prior: prior) : nil,
            foulMarker: isFoulSelected ? foulMarkerSymbol(prior: prior) : nil,
            catcherEstimate: isCatcherCall ? catcherEstimate : nil,
            play: BaseRunnerRules.playIfConsistent(
                currentBatterPlay,
                outcome: normalizedOutcome.isEmpty ? nil : normalizedOutcome,
                errorOnPlay: isError
            )
        )
    }

    /// The batter's play as answered on the bases stage, or nil while it is
    /// unanswered or incomplete.
    private var currentBatterPlay: BasePlay? {
        guard let reached = batterReachedBase, let credit = batterCredit,
              BaseRunnerRules.isComplete(credit: credit, reached: reached, extraBasesOn: batterExtraBasesOn)
        else { return nil }
        return BaseRunnerRules.makePlay(credit: credit, reached: reached, extraBasesOn: batterExtraBasesOn)
    }

    /// Diamond -> the sheet's existing outcome/error selections, which the
    /// count rules, save gating and review sheet already read.
    private func applyBatterPlayToSelections() {
        guard let reached = batterReachedBase, let credit = batterCredit else {
            if let outcome = selectedOutcome, ["1B", "2B", "3B", "HR"].contains(outcome) {
                selectedOutcome = nil
            }
            isError = false
            return
        }
        let reason = BaseRunnerRules.needsExtraBasesReason(credit: credit, reached: reached) ? batterExtraBasesOn : nil
        // Mirror the credit on the Hit button so it doesn't read as cleared
        // while a hit is recorded; reached on error is not a hit.
        isHitTagSelected = credit.isHit
        isHitBatter = false
        isFoulSelected = false
        isStrikeSwinging = false
        isStrikeLooking = false
        isBall = false
        selectedOutcome = BaseRunnerRules.outcome(for: credit)
        isError = BaseRunnerRules.errorOnPlay(credit: credit, extraBasesOn: reason)
    }

    /// The Error button, tapped with the batter already placed: on means
    /// reached on error, off goes back to the clean hit for that base.
    /// Changes the diamond makes itself already agree, so this is a no-op
    /// for them (1B + E sets the flag on and leaves it alone).
    private func syncBatterCreditToErrorButton(_ isOn: Bool) {
        guard let reached = batterReachedBase, let credit = batterCredit else { return }
        let reason = BaseRunnerRules.needsExtraBasesReason(credit: credit, reached: reached) ? batterExtraBasesOn : nil
        guard BaseRunnerRules.errorOnPlay(credit: credit, extraBasesOn: reason) != isOn else { return }
        batterCredit = isOn ? .reachedOnError : BaseRunnerRules.defaultCredit(reached: reached)
        batterExtraBasesOn = nil
    }

    /// The Hit button, tapped with the batter already placed: off means the
    /// batter is safe without a hit (reached on error), on goes back to the
    /// clean hit for that base. A no-op when it already agrees.
    private func syncBatterCreditToHitButton(_ isOn: Bool) {
        guard let reached = batterReachedBase, let credit = batterCredit,
              credit.isHit != isOn else { return }
        batterCredit = isOn ? BaseRunnerRules.defaultCredit(reached: reached) : .reachedOnError
        batterExtraBasesOn = nil
    }

    /// Outcome changed somewhere other than the diamond (Out, Swinging, a
    /// deselect...) - drop a batter placement that no longer describes it.
    private func clearBatterPlayIfOutcomeDiverged(_ outcome: String?) {
        guard let credit = batterCredit else { return }
        if outcome != BaseRunnerRules.outcome(for: credit) {
            batterReachedBase = nil
            batterCredit = nil
            batterExtraBasesOn = nil
        }
    }

    private struct OutcomeChangeHandlers: ViewModifier {
        @Binding var isPresented: Bool
        @Binding var isStrikeSwinging: Bool
        @Binding var isStrikeLooking: Bool
        @Binding var isWildPitch: Bool
        @Binding var isPassedBall: Bool
        @Binding var isBall: Bool
        @Binding var isHitBatter: Bool
        @Binding var isFoulSelected: Bool
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
                .onChange(of: isFoulSelected) { _, _ in deselectIfDisabled() }
                .onChange(of: selectedDescriptor) { _, _ in deselectIfDisabled() }
                .onChange(of: isError) { _, _ in deselectIfDisabled() }
                .onChange(of: selectedOutcome) { _, newValue in
                    if isHitBatter && newValue != "1B" {
                        isHitBatter = false
                    }
                    if newValue != "Out" && isFoulSelected {
                        isFoulSelected = false
                    }
                    if newValue == "ꓘ" && selectedDescriptor == "Foul" {
                        selectedDescriptor = nil
                    }
                    deselectIfDisabled()
                }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        Button {
                            isPresented = false
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Close")
                        }
                        .buttonStyle(.plain)

                        Text("Pitch result: \(hasSelectedLocation ? (effectiveLocationLabel ?? "") : "Select a location")")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(hasSelectedLocation ? .blue : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Spacer(minLength: 0)
                    }
                    .padding(.top, 8)

                    let canSave: Bool = {
                        // Every pitch resolves to exactly one of these primary
                        // outcomes, so require one before the result can be saved.
                        // "Out" and "Safe" (1B/2B/3B/HR) each cover a ball in play
                        // that fielders converted into a full result on their own,
                        // not a supplementary tag. Other supplementary tags (K,
                        // Walk, Wild Pitch, Passed Ball, Error, batted-ball
                        // location, descriptors) refine a result but can no longer
                        // stand in as the whole result.
                        isStrikeSwinging ||
                        isStrikeLooking ||
                        isFoulSelected ||
                        isBall ||
                        isHitTagSelected ||
                        selectedOutcome == "Out" ||
                        (
                            (selectedOutcome.map { ["1B", "2B", "3B", "HR"].contains($0) } ?? false)
                            // A batter placed on the diamond must finish the
                            // "how" question (e.g. 1B to 2nd needs Error/Throw).
                            && (batterReachedBase == nil || currentBatterPlay != nil)
                        )
                    }()

                    Divider()

                    HStack(alignment: .center, spacing: 8) {
                        SafeOutButtonsRow(
                            selectedOutcome: $selectedOutcome,
                            selectedDescriptor: $selectedDescriptor,
                            isStrikeSwinging: $isStrikeSwinging,
                            isStrikeLooking: $isStrikeLooking,
                            isBall: $isBall,
                            isHitTagSelected: $isHitTagSelected,
                            isHitBatter: $isHitBatter,
                            isFoulSelected: $isFoulSelected,
                            isSafeDisabled: isOutcomeDisabled("1B"),
                            isOutDisabled: isOutcomeDisabled("Out"),
                            onSelectSafe: {
                                fieldStage = .bases
                                shouldScrollToInPlayOutcome = true
                            }
                        )

                        HoldActionButton(
                            title: "Save Result",
                            systemImage: "",
                            foregroundColor: .green,
                            tint: .white,
                            isEnabled: canSave,
                            horizontalPadding: 10,
                            action: handleSave
                        )
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
                    .padding(.bottom, 12)

                    Divider()

                    interactiveSections
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
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
                    isFoulSelected: $isFoulSelected,
                    selectedOutcome: $selectedOutcome,
                    selectedDescriptor: $selectedDescriptor,
                    isError: $isError,
                    deselectIfDisabled: { self.deselectIfDisabled() }
                )
            )
                .onChange(of: isStrikeSwinging) { _, _ in
            }
            .onChange(of: isStrikeLooking) { _, _ in
            }
            .onChange(of: isBall) { _, _ in
            }
            .onChange(of: isHitBatter) { _, _ in
            }
            .onChange(of: selectedOutcome) { _, _ in
                if selectedOutcome == "Walk" || selectedOutcome == "K" || selectedOutcome == "ꓘ" || selectedOutcome == "HBP" {
                    isBall = false
                }
            }
            .onChange(of: battedBallTapNormalized) { _, newValue in
                guard currentMode == .scout, newValue != nil else { return }
                shouldScrollToInPlayOutcome = true
            }
            .onChange(of: battedBallTapNormalized) { _, newValue in
                // Stage 1 -> 2: a fair-ball tap moves on to the bases. A ball
                // over the fence is already answered: batter scores, HR.
                guard newValue != nil else { return }
                switch battedBallSelection {
                case .hr?:
                    batterReachedBase = Base.scored
                    batterCredit = .homeRun
                    batterExtraBasesOn = nil
                    fieldStage = .bases
                case .field?:
                    fieldStage = .bases
                case .foul?, nil:
                    break
                }
            }
            .onChange(of: batterReachedBase) { _, _ in applyBatterPlayToSelections() }
            .onChange(of: batterCredit) { _, _ in applyBatterPlayToSelections() }
            .onChange(of: batterExtraBasesOn) { _, _ in applyBatterPlayToSelections() }
            .onChange(of: isError) { _, newValue in syncBatterCreditToErrorButton(newValue) }
            .onChange(of: isHitTagSelected) { _, newValue in syncBatterCreditToHitButton(newValue) }
            .onChange(of: selectedOutcome) { _, newValue in clearBatterPlayIfOutcomeDiverged(newValue) }
            .onChange(of: shouldScrollToInPlayOutcome) { _, newValue in
                guard newValue else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(inPlayOutcomeAnchorID, anchor: .top)
                    }
                }
                shouldScrollToInPlayOutcome = false
            }
            .onChange(of: isPresented) { _, newValue in
                if newValue {
                    didInitializeManualCount = false
                    initializeManualCountIfNeeded()
                } else {
                    manualCountOverride = nil
                    didInitializeManualCount = false
                    resetSelections()
                }
            }
            .onAppear { initializeManualCountIfNeeded() }
            // One notification point for the whole sheet. Previously each tap site
            // called onCountChanged by hand, so any path that forgot to call it
            // left the rest of the app showing a stale count.
            .onChange(of: resolvedCount) { _, newValue in
                // Only publish while the sheet is actually open and seeded.
                //
                // Tearing the sheet down clears every selection, which makes
                // resolvedCount fall back to countSeed - the count from *before*
                // this pitch. Without this guard that stale value was pushed out
                // on dismiss and overwrote the count the save had just committed,
                // so every recorded pitch snapped the game back to its pre-pitch
                // count and the next pitch re-seeded from there.
                guard isPresented, didInitializeManualCount else { return }
                onCountChanged?(newValue.balls, newValue.strikes)
            }
            .alert("Result Location Required", isPresented: $showMissingLocationPrompt) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Select a result location on the strike zone before saving.")
            }
            .sheet(item: $savedPlayReviewDraft) { draft in
                SavedPlayReviewSheetView(
                    title: draft.title,
                    summaryLines: draft.summaryLines,
                    initialEvent: draft.event,
                    onBack: {
                        savedPlayReviewDraft = nil
                    },
                    onSave: { reviewedEvent in
                        commitReviewedSavedPlayEvent(reviewedEvent)
                    }
                )
                .interactiveDismissDisabled(true)
                .fixedAppDynamicType()
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
                                    showMissingBatterPrompt = false
                                    performSave()
                                } label: {
                                    BatterPromptChipButton(
                                        jerseyNumber: cell.jerseyNumber,
                                        isSelected: isSelected
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    HStack(spacing: 10) {
                        Button("Save Without Batter") {
                            overrideOpponentBatterId = nil
                            overrideOpponentJersey = nil
                            showMissingBatterPrompt = false
                            performSave()
                        }
                        .buttonStyle(.bordered)

                        Button("Cancel", role: .cancel) {
                            showMissingBatterPrompt = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .presentationDetents([.fraction(0.3), .medium])
                .presentationDragIndicator(.visible)
                .fixedAppDynamicType()
        }
    }
    }

    private func deselectIfDisabled() {
        if isFoulSelected, let outcome = selectedOutcome, outcome != "Out" {
            isFoulSelected = false
        }
        if let outcome = selectedOutcome, isOutcomeDisabled(outcome) {
            selectedOutcome = nil
        }
        if let descriptor = selectedDescriptor, isOutcomeDisabled(descriptor) {
            selectedDescriptor = nil
        }
        if isError && batterReachedBase == nil && isOutcomeDisabled("E") {
            isError = false
        }
    }

}

private struct BatterPromptChipButton: View {
    let jerseyNumber: String
    let isSelected: Bool

    var body: some View {
        Text("#\(jerseyNumber)")
            .font(.headline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct OutcomeButtonsSection: View {
    @Binding var selectedOutcome: String?
    @Binding var selectedDescriptor: String?
    @Binding var isHitTagSelected: Bool
    @Binding var isHitBatter: Bool
    @Binding var isError: Bool
    @Binding var isFoulSelected: Bool
    @Binding var isWildPitch: Bool
    @Binding var isPassedBall: Bool
    var isOutcomeDisabled: (String) -> Bool
    let isWildPitchDisabled: Bool
    let isPassedBallDisabled: Bool

    private func setDescriptor(_ label: String) {
        if selectedDescriptor == label {
            selectedDescriptor = nil
        } else {
            selectedDescriptor = label
        }
    }

    private func toggleHitTag() {
        isHitTagSelected.toggle()
        if isHitTagSelected {
            if selectedOutcome == "Walk" {
                selectedOutcome = nil
            }
            isFoulSelected = false
            isHitBatter = false
            isWildPitch = false
            isPassedBall = false
        }
    }

    private func toggleWalk() {
        selectedOutcome = (selectedOutcome == "Walk") ? nil : "Walk"
        isFoulSelected = false
        selectedDescriptor = nil
        if selectedOutcome == "Walk" {
            isHitTagSelected = false
        }
    }

    private func toggleError() {
        isError.toggle()
        if isError {
            // Keep the batted-ball type (Fly, Pop...) - an error on a fly
            // ball is still a fly ball.
            isFoulSelected = false
        }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button { toggleHitTag() } label: {
                            Text("Hit")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(isHitTagSelected ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(width: 64, height: 50, alignment: .center)
                                .pitchResultSelectionBackground(isSelected: isHitTagSelected)
                                .cornerRadius(6)
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .disabled(isOutcomeDisabled("Hit"))
                        .opacity(isOutcomeDisabled("Hit") ? 0.4 : 1.0)

                        Button { toggleWalk() } label: {
                            Text("Walk")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(selectedOutcome == "Walk" ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(width: 64, height: 50, alignment: .center)
                                .pitchResultSelectionBackground(isSelected: selectedOutcome == "Walk")
                                .cornerRadius(6)
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .disabled(isOutcomeDisabled("Walk"))
                        .opacity(isOutcomeDisabled("Walk") ? 0.4 : 1.0)

                        Button { toggleError() } label: {
                            Text("Error")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(isError ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(width: 64, height: 50, alignment: .center)
                                .pitchResultSelectionBackground(isSelected: isError)
                                .cornerRadius(6)
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .disabled(isOutcomeDisabled("E"))
                        .opacity(isOutcomeDisabled("E") ? 0.4 : 1.0)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 8) {
                                AssetOutcomeButton(
                                    assetName: "grounder",
                                    width: 58,
                                    height: 46,
                                    isSelected: selectedDescriptor == "Grounder",
                                    isDisabled: isOutcomeDisabled("Grounder")
                                ) {
                                    setDescriptor("Grounder")
                                }

                                AssetOutcomeButton(
                                    assetName: "fly",
                                    width: 58,
                                    height: 46,
                                    isSelected: selectedDescriptor == "Fly",
                                    isDisabled: isOutcomeDisabled("Fly")
                                ) {
                                    setDescriptor("Fly")
                                }

                                AssetOutcomeButton(
                                    assetName: "hit batter",
                                    width: 60,
                                    height: 46,
                                    isSelected: isHitBatter,
                                    isDisabled: isOutcomeDisabled("Hit Batter")
                                ) {
                                    isHitBatter.toggle()
                                    if isHitBatter {
                                        selectedOutcome = "1B"
                                        isHitTagSelected = false
                                        isFoulSelected = false
                                        selectedDescriptor = nil
                                    } else if selectedOutcome == "1B" {
                                        selectedOutcome = nil
                                    }
                                }
                            }

                            HStack(spacing: 8) {
                                AssetOutcomeButton(
                                    assetName: "bunt",
                                    width: 58,
                                    height: 46,
                                    isSelected: selectedDescriptor == "Bunt",
                                    isDisabled: isOutcomeDisabled("Bunt")
                                ) {
                                    setDescriptor("Bunt")
                                }

                                AssetOutcomeButton(
                                    assetName: "Pop",
                                    width: 58,
                                    height: 46,
                                    isSelected: selectedDescriptor == "Pop",
                                    isDisabled: isOutcomeDisabled("Pop")
                                ) {
                                    setDescriptor("Pop")
                                }

                                AssetOutcomeButton(
                                    assetName: "Line",
                                    width: 58,
                                    height: 46,
                                    isSelected: selectedDescriptor == "Line",
                                    isDisabled: isOutcomeDisabled("Line")
                                ) {
                                    setDescriptor("Line")
                                }
                            }

                            EventButtonsRow(
                                isWildPitch: $isWildPitch,
                                isPassedBall: $isPassedBall,
                                isError: $isError,
                                selectedOutcome: $selectedOutcome,
                                isWildPitchDisabled: isWildPitchDisabled,
                                isPassedBallDisabled: isPassedBallDisabled,
                                isErrorDisabled: isOutcomeDisabled("E")
                            )
                        }

                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 0)
                .padding(.trailing, 36)
                .padding(.top, 2)
            }

            LinearGradient(
                colors: [
                    Color.clear,
                    Color(.systemBackground).opacity(0.92),
                    Color(.systemBackground)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 32)
            .allowsHitTesting(false)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.trailing, 4)
                .allowsHitTesting(false)
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
    var displayImageName: String = "FieldImage2"
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
            let displayImage = UIImage(named: displayImageName) ?? UIImage(named: "FieldImage")
            // Prefer the color map's aspect to ensure tap sampling aligns with the displayed image
            let drivingImage: UIImage? = colorMapImage ?? displayImage
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

                if let displayImage {
                    Image(uiImage: displayImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)
                        .shadow(radius: 10)
                        .allowsHitTesting(false)
                }

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
