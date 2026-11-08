//
//  CalledPitchRecord.swift
//  PitchMark
//
//  Created by Mark Springer on 10/9/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct FocusableNotesTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: FocusableNotesTextView
        weak var textView: UITextView?
        init(parent: FocusableNotesTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused { parent.isFocused = false }
        }

        @objc func doneTapped() {
            parent.isFocused = false
            textView?.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.backgroundColor = .clear
        // Avoid nested scroll-view gesture competition inside the popover sheet.
        textView.isScrollEnabled = false
        textView.alwaysBounceVertical = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.keyboardDismissMode = .none
        textView.isEditable = true
        textView.isSelectable = true
        textView.delaysContentTouches = false
        textView.canCancelContentTouches = true

        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(title: "Done", style: .done, target: context.coordinator, action: #selector(Coordinator.doneTapped))
        toolbar.items = [flex, done]
        textView.inputAccessoryView = toolbar
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if isFocused, !uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        } else if !isFocused, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }
}

func outcomeSummaryLines(for event: PitchEvent) -> [String] {
    var lines: [String] = []

    // Remove any leading label before a separator for outcome/descriptor only
    func sanitize(_ input: String?) -> String? {
        guard let input = input?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else { return nil }

        // Consider multiple separator variants
        let separators = ["--", " — ", " – ", "-", "—", "–", ":"]
        // Labels we want to strip if they appear before the separator
        let stripLabels: Set<String> = [
            "foul", "field", "hr", "home run", "homerun", "fly", "ground", "line drive", "linedrive"
        ]

        for sep in separators {
            if let range = input.range(of: sep) {
                let before = input[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let after = input[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)

                // If the prefix is a known label or very short (likely a label), strip it
                if stripLabels.contains(before) || before.count <= 6 {
                    if !after.isEmpty { return after }
                }
            }
        }
        return input
    }

    // Add a line if unique; optionally sanitize first
    func addUnique(_ line: String?, sanitizeText: Bool = true) {
        var candidate: String?
        if sanitizeText {
            candidate = sanitize(line)
        } else {
            candidate = line?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let raw = candidate, !raw.isEmpty else { return }
        let lower = raw.lowercased()
        if lines.contains(where: { $0.lowercased() == lower }) { return }
        lines.append(raw)
    }

    // Primary flags
    if event.strikeSwinging {
        let marker = event.strikeSwingingMarker?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let marker, !marker.isEmpty {
            addUnique("\(marker) Strike — Swinging", sanitizeText: false)
        } else {
            addUnique("Strike — Swinging")
        }
    }
    if event.strikeLooking {
        let marker = event.strikeLookingMarker?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let marker, !marker.isEmpty {
            addUnique("\(marker) Strike — Looking", sanitizeText: false)
        } else {
            addUnique("Strike — Looking")
        }
    }
    if event.wildPitch { addUnique("Wild Pitch") }
    if event.passedBall { addUnique("Passed Ball") }
    // The play line already says the result ("2B", "Out", "Walk"), so the
    // outcome isn't repeated under it.
    var playSaysOutcome = false
    if let play = event.play, let playSummary = BaseRunnerRules.cardSummary(for: play) {
        addUnique(playSummary, sanitizeText: false)
        playSaysOutcome = !play.isRunnersOnly
    } else if event.errorOnPlay {
        addUnique("Error on play")
    }
    if let fielding = FieldingPlay.summary(outs: event.fieldingOuts, errors: event.errorPositions,
                                           descriptor: event.descriptor) {
        addUnique(fielding, sanitizeText: false)
    }
    if event.isBall == true {
        let marker = event.ballMarker?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let marker, !marker.isEmpty {
            addUnique("\(marker) Ball", sanitizeText: false)
        } else {
            addUnique("Ball")
        }
    }

    // Outcome/descriptor first (sanitize these to remove labels like "field --")
    let rawOutcome = event.outcome?.trimmingCharacters(in: .whitespacesAndNewlines)
    let isFoulOutcome = rawOutcome?.caseInsensitiveCompare("Foul") == .orderedSame
    let isOutOutcome = rawOutcome?.caseInsensitiveCompare("Out") == .orderedSame
    if isFoulOutcome {
        let marker = event.foulMarker?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let marker, !marker.isEmpty {
            addUnique("\(marker) Foul", sanitizeText: false)
        } else {
            addUnique(event.outcome, sanitizeText: true)
        }
    } else if isOutOutcome {
        let marker = event.foulMarker?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let marker, !marker.isEmpty {
            addUnique("\(marker) Foul Out", sanitizeText: false)
        } else if !playSaysOutcome {
            addUnique(event.outcome, sanitizeText: true)
        }
    } else if !playSaysOutcome {
        addUnique(event.outcome, sanitizeText: true)
    }

    // Batted ball details — show only the region label in cards (ignore type)
    let regionLower = (event.battedBallRegion ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let existingCombined = lines.map { $0.lowercased() }.joined(separator: " \n ")

    func alreadyRepresentsRegion(_ region: String) -> Bool {
        return !region.isEmpty && existingCombined.contains(region)
    }

    // Ball type and where it went share one line: "Line · Deep Right".
    // "Hit" is dropped from the descriptor on a hit - the card's header
    // and the play line already say it.
    let descriptorText: String? = sanitize(event.descriptor).map { text in
        guard pitchEventCountsAsHit(event) else { return text }
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare("Hit") != .orderedSame }
        return parts.joined(separator: ", ")
    }
    let region = event.battedBallRegion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let showRegion = !region.isEmpty && !alreadyRepresentsRegion(regionLower)
    let detail = [descriptorText ?? "", showRegion ? region : ""].filter { !$0.isEmpty }
    // Do NOT sanitize constructed lines; keep user-facing labels intact
    addUnique(detail.joined(separator: " · "), sanitizeText: false)

    return lines
}

struct OutcomeSummaryBackground: View {
    let isPositive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.white))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
            .shadow(
                color: isPositive ? Color.green.opacity(0.35) : Color.red.opacity(0.35),
                radius: 4,
                x: 0,
                y: 3
            )
    }
}

struct OutcomeSummaryView: View {
    let lines: [String]
    let jerseyNumber: String?
    let countText: String?
    let minHeight: CGFloat?
    let maxHeight: CGFloat?

    init(lines: [String], jerseyNumber: String?, countText: String? = nil, minHeight: CGFloat? = 118, maxHeight: CGFloat? = nil) {
        self.lines = lines
        self.jerseyNumber = jerseyNumber
        self.countText = countText
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }

    private var isPositiveOutcome: Bool {
        let text = lines.joined(separator: " ").lowercased()
        return text.contains("swinging")
            || text.contains("looking")
            || text.contains("out")
            || text.contains("foul")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if (countText?.isEmpty == false) || (jerseyNumber?.isEmpty == false) {
                HStack(spacing: 6) {
                    if let countText, !countText.isEmpty {
                        Text(countText)
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(.black.opacity(0.75))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if let num = jerseyNumber, !num.isEmpty {
                        Text(num)
                            .font(.system(size: 15, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, num.count > 1 ? 8 : 0)
                            .frame(width: num.count > 1 ? nil : 22, height: 22)
                            .background(
                                Group {
                                    if num.count > 1 {
                                        Capsule().fill(Color.blue)
                                    } else {
                                        Circle().fill(Color.blue)
                                    }
                                }
                            )
                    }
                }
                .padding(.bottom, 6)
            }
            ForEach(lines, id: \.self) { line in
                let tokens = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                let firstToken = tokens.first.map(String.init) ?? ""
                let hasSymbolPrefix = firstToken.hasSuffix(".circle") || firstToken == "f.circle"
                let displayText: String = {
                    guard hasSymbolPrefix else { return line }
                    if tokens.count > 1 { return String(tokens[1]) }
                    return line
                }()

                let showRunner: Bool = ["1B", "2B", "3B", "HR"].contains { prefix in
                    displayText.uppercased().hasPrefix(prefix)
                }

                HStack(spacing: 4) {
                    if hasSymbolPrefix {
                        Image(systemName: firstToken)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.black)
                    }
                    if showRunner {
                        Image(systemName: "figure.run")
                            .foregroundColor(.black)
                    }
                    Text(displayText)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                        .multilineTextAlignment(.leading)
                        .allowsTightening(true)
                }
            }
        }
        .frame(minWidth: 92, maxWidth: 132, minHeight: minHeight, maxHeight: maxHeight, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(OutcomeSummaryBackground(isPositive: isPositiveOutcome))
        .padding(.trailing, 6)
    }
}

/// The review step's pitch (SavedPlayReviewSheetView). Internal for tests.
func buildSavedPlayReviewedEvent(
    from base: PitchEvent,
    balls: Int,
    strikes: Int,
    isStrike: Bool,
    isBall: Bool,
    strikeLooking: Bool,
    strikeSwinging: Bool,
    wildPitch: Bool,
    passedBall: Bool,
    countsAsWalk: Bool,
    countsAsHit: Bool
) -> PitchEvent {
    let baseOutcome = (base.outcome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let baseDescriptor = (base.descriptor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    // Reached on error is stored as "1B" + errorOnPlay, so it looks like a hit
    // to pitchEventCountsAsHit. Hit off must keep that "1B" (the batter is
    // still on base); Hit on turns it into a real single by clearing the error.
    let baseIsReachedOnError = pitchEventCountsAsHit(base)
        && BaseRunnerRules.isReachedOnError(errorOnPlay: base.errorOnPlay, play: base.play)
    let errorOnPlay = (countsAsHit && baseIsReachedOnError) ? false : base.errorOnPlay

    let outcome: String? = {
        if countsAsWalk { return "Walk" }
        if countsAsHit {
            if pitchEventCountsAsHit(base) {
                return baseOutcome.isEmpty ? "1B" : baseOutcome
            }
            return "1B"
        }
        if baseOutcome.caseInsensitiveCompare("Walk") == .orderedSame || baseOutcome == "BB" {
            return nil
        }
        if baseIsReachedOnError {
            return baseOutcome
        }
        if pitchEventCountsAsHit(base) {
            return nil
        }
        return baseOutcome.isEmpty ? nil : baseOutcome
    }()

    let descriptor: String? = {
        if countsAsHit {
            if baseDescriptor.isEmpty {
                return "Hit"
            }
            if baseDescriptor.lowercased().contains("hit") {
                return baseDescriptor
            }
            return "\(baseDescriptor), Hit"
        }
        if baseIsReachedOnError {
            // Keep Fly/Pop/..., drop any Hit tag.
            let kept = baseDescriptor
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.lowercased() != "hit" }
            return kept.isEmpty ? nil : kept.joined(separator: ", ")
        }
        if pitchEventCountsAsHit(base) {
            return nil
        }
        return baseDescriptor.isEmpty ? nil : baseDescriptor
    }()

    let inPlayRegion = base.battedBallRegion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    let normalizedOutcome = outcome?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let inPlayOutcomes: Set<String> = ["1b", "2b", "3b", "hr", "hit", "out"]
    let resultForcesStrike = strikeLooking
        || strikeSwinging
        || base.isFoulInferred
        || countsAsHit
        || inPlayRegion
        || inPlayOutcomes.contains(normalizedOutcome)
    let resolvedIsStrike = isStrike || resultForcesStrike
    let resolvedIsBall = resultForcesStrike ? false : isBall

    var reviewed = PitchEvent(
        id: base.id,
        timestamp: base.timestamp,
        pitch: base.pitch,
        location: base.location,
        codes: base.codes,
        isStrike: resolvedIsStrike,
        isBall: resolvedIsBall,
        mode: base.mode,
        calledPitch: base.calledPitch,
        batterSide: base.batterSide,
        templateId: base.templateId,
        strikeSwinging: strikeSwinging,
        wildPitch: wildPitch,
        passedBall: passedBall,
        strikeLooking: strikeLooking,
        outcome: outcome,
        descriptor: descriptor,
        errorOnPlay: errorOnPlay,
        battedBallRegion: base.battedBallRegion,
        battedBallType: base.battedBallType,
        battedBallTapX: base.battedBallTapX,
        battedBallTapY: base.battedBallTapY,
        gameId: base.gameId,
        opponentJersey: base.opponentJersey,
        opponentBatterId: base.opponentBatterId,
        pitcherId: base.pitcherId,
        hitterId: base.hitterId,
        createdByUid: base.createdByUid,
        strikeSwingingMarker: strikeSwinging ? base.strikeSwingingMarker : nil,
        strikeLookingMarker: strikeLooking ? base.strikeLookingMarker : nil,
        ballMarker: resolvedIsBall ? base.ballMarker : nil,
        foulMarker: base.foulMarker,
        trackingMode: base.trackingMode,
        catcherEstimate: base.catcherEstimate,
        play: BaseRunnerRules.playIfConsistent(base.play, outcome: outcome, errorOnPlay: errorOnPlay),
        basesBefore: base.basesBefore,
        defense: base.defense,
        fieldingTeamId: base.fieldingTeamId
    )
    reviewed.fieldingOuts = FieldingPlay.consistentOuts(base.fieldingOuts, for: reviewed)
    reviewed.errorPositions = FieldingPlay.consistentErrors(base.errorPositions, for: reviewed)
    // Through applyCount like every other save, so a walk or strikeout keeps
    // its "Ball 4" / "Strikeout" label and the reset count.
    PitchEventEdit.stampReviewedCount(&reviewed, balls: balls, strikes: strikes)
    return reviewed
}

/// Where the review sheet's Back/Save row goes when it opens from Save
/// Result (2026-11-05, user's call: tap Save Result, then Save, without
/// moving the finger). All in the sheet's own points.
enum ReviewSaveLayout {
    static let barHeight: CGFloat = 56
    static let topPadding: CGFloat = 20
    /// Room left under the row so it never sits on the sheet's bottom edge.
    static let bottomRoom: CGFloat = 120

    /// The row's top inside the sheet: centred on the anchor, kept inside.
    static func barTop(anchorMidY: CGFloat, sheetMinY: CGFloat, sheetHeight: CGFloat, barHeight: CGFloat) -> CGFloat {
        let wanted = anchorMidY - sheetMinY - barHeight / 2
        let highest = sheetHeight > 0 ? sheetHeight - barHeight - bottomRoom : wanted
        return max(0, min(wanted, highest))
    }

    /// Which of the header and count card fit above the row (in order -
    /// the count never sits above without the header).
    static func above(room: CGFloat, headerHeight: CGFloat, countHeight: CGFloat) -> (header: Bool, count: Bool) {
        let gap: CGFloat = 10
        let header = topPadding + headerHeight + gap <= room
        // Its room includes the header's, so it can't fit when the header doesn't.
        let count = topPadding + headerHeight + 18 + countHeight + gap <= room
        return (header, count)
    }

    /// Save's centre x inside the sheet, kept clear of Back and the edge.
    static func saveCenterX(anchorMidX: CGFloat, sheetMinX: CGFloat, sheetWidth: CGFloat, saveWidth: CGFloat) -> CGFloat {
        let wanted = anchorMidX - sheetMinX
        guard sheetWidth > 0 else { return wanted }
        let backClearance: CGFloat = 110
        let lowest = backClearance + saveWidth / 2
        let highest = sheetWidth - 16 - saveWidth / 2
        return max(lowest, min(wanted, max(lowest, highest)))
    }
}

struct SavedPlayReviewSheetView: View {
    let title: String
    let summaryLines: [String]
    let initialEvent: PitchEvent
    let onBack: () -> Void
    let onSave: (PitchEvent) -> Void
    /// Screen frame of the Save Result button that opened this sheet; Save
    /// goes in the same spot so saving is two taps in one place. nil keeps
    /// Back and Save at the bottom.
    let saveAnchor: CGRect?

    @State private var sheetFrame: CGRect = .zero
    @State private var headerHeight: CGFloat = 34
    @State private var countCardHeight: CGFloat = 150
    @State private var draftBalls: Int
    @State private var draftStrikes: Int
    @State private var draftIsStrike: Bool
    @State private var draftIsBall: Bool
    @State private var draftStrikeLooking: Bool
    @State private var draftStrikeSwinging: Bool
    @State private var draftWildPitch: Bool
    @State private var draftPassedBall: Bool
    @State private var draftWalk: Bool
    @State private var draftHit: Bool

    init(
        title: String,
        summaryLines: [String],
        initialEvent: PitchEvent,
        onBack: @escaping () -> Void,
        onSave: @escaping (PitchEvent) -> Void,
        saveAnchor: CGRect? = nil
    ) {
        self.saveAnchor = saveAnchor
        self.title = title
        self.summaryLines = summaryLines
        self.initialEvent = initialEvent
        self.onBack = onBack
        self.onSave = onSave

        let balls = max(0, min(3, initialEvent.atBatBalls ?? 0))
        let strikes = max(0, min(2, initialEvent.atBatStrikes ?? 0))
        let normalizedOutcome = (initialEvent.outcome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isWalk = normalizedOutcome.caseInsensitiveCompare("Walk") == .orderedSame || normalizedOutcome == "BB"
        // Credited hit, not "looks like a hit": a reached-on-error "1B" must
        // start with the toggle off or it counts against the pitcher.
        let isHit = pitchEventIsCreditedHit(initialEvent)
        let initialForcesStrike = PitchEventEdit.reviewStartsAsStrike(initialEvent)

        _draftBalls = State(initialValue: balls)
        _draftStrikes = State(initialValue: strikes)
        _draftIsStrike = State(initialValue: initialEvent.isStrike || initialForcesStrike)
        _draftIsBall = State(initialValue: initialForcesStrike ? false : (initialEvent.isBall ?? !initialEvent.isStrike))
        _draftStrikeLooking = State(initialValue: initialEvent.strikeLooking)
        _draftStrikeSwinging = State(initialValue: initialEvent.strikeSwinging)
        _draftWildPitch = State(initialValue: initialEvent.wildPitch)
        _draftPassedBall = State(initialValue: initialEvent.passedBall)
        _draftWalk = State(initialValue: isWalk)
        _draftHit = State(initialValue: isHit)
    }

    private var countText: String {
        "\(draftBalls)-\(draftStrikes)"
    }

    private func countCircle(isFilled: Bool, fillColor: Color, strokeColor: Color) -> some View {
        ZStack {
            Circle()
                .fill(isFilled ? fillColor.opacity(0.9) : Color.clear)
            Circle()
                .stroke(strokeColor, lineWidth: 2)
        }
        .frame(width: 18, height: 18)
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
    }

    private func countStepper(
        label: String,
        value: Int,
        maxValue: Int,
        fillColor: Color,
        strokeColor: Color,
        setValue: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(1...maxValue, id: \.self) { step in
                    Button {
                        setValue(value == step ? max(0, step - 1) : step)
                    } label: {
                        countCircle(isFilled: step <= value, fillColor: fillColor, strokeColor: strokeColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func statToggle(title: String, detail: String, isOn: Binding<Bool>, tint: Color) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(tint)
    }

    private func summaryLineDisplay(for line: String) -> (symbolName: String?, text: String) {
        let tokens = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let firstToken = tokens.first.map(String.init) else {
            return (nil, line)
        }

        let hasSymbolPrefix = firstToken.hasSuffix(".circle") || firstToken == "f.circle"
        guard hasSymbolPrefix else {
            return (nil, line)
        }

        let text = tokens.count > 1 ? String(tokens[1]) : line
        return (firstToken, text)
    }

    private var reviewHeaderText: String {
        if let jersey = initialEvent.opponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines), !jersey.isEmpty {
            return "\(title) • #\(jersey)"
        }
        return title
    }

    private func reviewedEvent() -> PitchEvent {
        buildSavedPlayReviewedEvent(
            from: initialEvent,
            balls: draftBalls,
            strikes: draftStrikes,
            isStrike: draftIsStrike,
            isBall: draftIsBall,
            strikeLooking: draftStrikeLooking,
            strikeSwinging: draftStrikeSwinging,
            wildPitch: draftWildPitch,
            passedBall: draftPassedBall,
            countsAsWalk: draftWalk,
            countsAsHit: draftHit
        )
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reviewHeaderText)
                .font(.title2.weight(.semibold))
                .foregroundColor(.primary)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
    }

    private var countSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Count")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(countText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            HStack(alignment: .top, spacing: 14) {
                countStepper(label: "Balls", value: draftBalls, maxValue: 3, fillColor: .red, strokeColor: .red) { next in
                    draftBalls = next
                }

                countStepper(label: "Strikes", value: draftStrikes, maxValue: 2, fillColor: .green, strokeColor: .green) { next in
                    draftStrikes = next
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        )
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { countCardHeight = $0 }
    }

    private var pitchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pitch")
                            .font(.subheadline.weight(.semibold))
                        Text("Always adds one pitch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }

                statToggle(title: "Strike", detail: "Counts as a strike for the pitcher.", isOn: $draftIsStrike, tint: .green)
                statToggle(title: "Ball", detail: "Counts as a ball for the pitcher.", isOn: $draftIsBall, tint: .red)
                statToggle(title: "Called Strike", detail: "Adds a looking strike.", isOn: $draftStrikeLooking, tint: .green)
                statToggle(title: "Swinging Strike", detail: "Adds a swinging strike.", isOn: $draftStrikeSwinging, tint: .green)
                statToggle(title: "Walk", detail: "Counts as a walk / BB.", isOn: $draftWalk, tint: .orange)
                statToggle(title: "Hit", detail: "Counts as a hit against the pitcher.", isOn: $draftHit, tint: .pink)
                statToggle(title: "Wild Pitch", detail: "Counts as a wild pitch.", isOn: $draftWildPitch, tint: .purple)
                statToggle(title: "Passed Ball", detail: "Counts as a passed ball.", isOn: $draftPassedBall, tint: .purple)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
            )
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved play details")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(summaryLines, id: \.self) { line in
                    let display = summaryLineDisplay(for: line)
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.black.opacity(0.35))
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)

                        HStack(spacing: 6) {
                            if let symbolName = display.symbolName {
                                Image(systemName: symbolName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                            }

                            Text(display.text)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
            )
        }
    }

    private var saveTapped: () -> Void {
        { onSave(reviewedEvent()) }
    }

    var body: some View {
        layout
        .onChange(of: draftStrikeLooking) { _, newValue in
            if newValue {
                draftStrikeSwinging = false
                draftIsStrike = true
                draftIsBall = false
                draftWalk = false
            }
        }
        .onChange(of: draftStrikeSwinging) { _, newValue in
            if newValue {
                draftStrikeLooking = false
                draftIsStrike = true
                draftIsBall = false
                draftWalk = false
            }
        }
        .onChange(of: draftIsStrike) { _, newValue in
            if newValue {
                draftIsBall = false
            }
        }
        .onChange(of: draftIsBall) { _, newValue in
            if newValue {
                draftIsStrike = false
            }
        }
        .onChange(of: draftWildPitch) { _, newValue in
            if newValue {
                draftPassedBall = false
            }
        }
        .onChange(of: draftPassedBall) { _, newValue in
            if newValue {
                draftWildPitch = false
            }
        }
        .onChange(of: draftWalk) { _, newValue in
            if newValue {
                draftHit = false
                draftIsBall = true
                draftIsStrike = false
                draftStrikeLooking = false
                draftStrikeSwinging = false
            }
        }
        .onChange(of: draftHit) { _, newValue in
            if newValue {
                draftWalk = false
                draftIsStrike = true
                draftIsBall = false
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var layout: some View {
        if let saveAnchor {
            anchoredLayout(saveAnchor)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection
                    countSection
                    pitchSection
                    detailsSection
                    HStack(spacing: 10) {
                        Button("Back") {
                            onBack()
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button("Save", action: saveTapped)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(20)
            }
        }
    }

    /// Opened from Save Result: Back and Save sit in a row at the height
    /// Save Result was, with Save under where the finger already is. What
    /// fits above the row stays there; the rest scrolls below it.
    private func anchoredLayout(_ anchor: CGRect) -> some View {
        let barTop = ReviewSaveLayout.barTop(
            anchorMidY: anchor.midY, sheetMinY: sheetFrame.minY,
            sheetHeight: sheetFrame.height, barHeight: ReviewSaveLayout.barHeight
        )
        let above = ReviewSaveLayout.above(room: barTop, headerHeight: headerHeight, countHeight: countCardHeight)
        let saveWidth = max(anchor.width, 90)
        let saveCenterX = ReviewSaveLayout.saveCenterX(
            anchorMidX: anchor.midX, sheetMinX: sheetFrame.minX,
            sheetWidth: sheetFrame.width, saveWidth: saveWidth
        )
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                if above.header { headerSection }
                if above.count { countSection }
            }
            .padding(.horizontal, 20)
            .padding(.top, ReviewSaveLayout.topPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: barTop, alignment: .top)
            .clipped()

            ZStack(alignment: .leading) {
                Button("Back") {
                    onBack()
                }
                .buttonStyle(.bordered)
                .padding(.leading, 20)

                Button(action: saveTapped) {
                    Text("Save")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: saveWidth, height: max(anchor.height, 40))
                        .background(Capsule().fill(Color.green))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .offset(x: saveCenterX - saveWidth / 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: ReviewSaveLayout.barHeight)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !above.header { headerSection }
                    if !above.count { countSection }
                    pitchSection
                    detailsSection
                }
                .padding(20)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { sheetFrame = $0 }
    }
}

struct PitchCardView: View {
    
    let batterSide: BatterSide
    let leftImage: Image
    let topText: String
    let middleText: String
    let bottomText: String
    let verticalTopImage: Image
    let rightImage: Image?
    let rightImageShouldHighlight: Bool
    let footerTextName: String
    let footerTextDate: String
    let gameTitle: String?
    let pitchNumber: Int?
    let outcomeSummary: [String]?
    let jerseyNumber: String?
    let atBatCountText: String?
    let trackingMode: TrackingMode
    let hideHeader: Bool

    let onLongPress: () -> Void
    
    init(
        batterSide: BatterSide,
        leftImage: Image,
        topText: String,
        middleText: String,
        bottomText: String,
        verticalTopImage: Image,
        rightImage: Image?,
        rightImageShouldHighlight: Bool,
        footerTextName: String,
        footerTextDate: String,
        pitchNumber: Int?,
        outcomeSummary: [String]?,
        jerseyNumber: String?,
        atBatCountText: String? = nil,
        trackingMode: TrackingMode = .coach,
        gameTitle: String? = nil,
        hideHeader: Bool = false,
        onLongPress: @escaping (() -> Void) = {}
    ) {
        self.batterSide = batterSide
        self.leftImage = leftImage
        self.topText = topText
        self.middleText = middleText
        self.bottomText = bottomText
        self.verticalTopImage = verticalTopImage
        self.rightImage = rightImage
        self.rightImageShouldHighlight = rightImageShouldHighlight
        self.footerTextName = footerTextName
        self.footerTextDate = footerTextDate
        self.pitchNumber = pitchNumber
        self.outcomeSummary = outcomeSummary
        self.jerseyNumber = jerseyNumber
        self.atBatCountText = atBatCountText
        self.trackingMode = trackingMode
        self.gameTitle = gameTitle
        self.hideHeader = hideHeader
        self.onLongPress = onLongPress
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if hideHeader == false {
                // 🧠 Header at top-left
                HStack(spacing: 4) {
                    Text({
                        if let game = gameTitle, !game.isEmpty {
                            return "\(footerTextName) vs. \(game)"
                        } else {
                            return footerTextName
                        }
                    }())
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .padding(.top, 8)
                        .padding(.leading, 8)
                    Spacer()
                    if let pitchNumber = pitchNumber {
                        Text("Pitch #\(pitchNumber)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .padding(.trailing, 8)
                            .padding(.top, 8)
                    }
                }
            }
            
            // 🧩 Main card content
            content
                .padding(.horizontal, 0)
                .padding(.vertical, 0)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(trackingMode == .scout ? 0.16 : 0.3), radius: trackingMode == .scout ? 4 : 6, x: 0, y: trackingMode == .scout ? 2 : 3)
        .onLongPressGesture(minimumDuration: 0.45) { onLongPress() }
    }
    
    @ViewBuilder
    private var content: some View {
        if trackingMode == .scout {
            scoutCompactContent
        } else {
            HStack(alignment: .center, spacing: 2) {
                leadingImages
                    .padding(.leading, 10)
                    .padding(.vertical, 6)
                
                VStack(alignment: .leading, spacing: isCatcherCard ? 2 : 6) {
                    HStack{
                        Text(topText)
                            .font(.system(size: topText == "Catcher" ? 13 : 15, weight: .semibold))
                            .bold()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.leading)
                    }
                    if !isCatcherCard {
                        Text(middleText)
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                        
                        Text(bottomText)
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(minWidth: 70)
                .layoutPriority(1)
                
                Spacer()
                
                let hasJerseyNumber = (jerseyNumber?.isEmpty == false)
                if (outcomeSummary != nil && !(outcomeSummary?.isEmpty ?? true)) || hasJerseyNumber {
                    OutcomeSummaryView(
                        lines: outcomeSummary ?? [],
                        jerseyNumber: jerseyNumber,
                        countText: atBatCountText,
                        minHeight: isCatcherCard ? 0 : 90,
                        maxHeight: isCatcherCard ? 72 : 90
                    )
                    .padding(.vertical, 6)
                }
                
                Group {
                    if let rightImage {
                        rightImage
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: isCatcherCard ? 72 : 90)
                            .shadow(
                                color: rightImageShouldHighlight ? .green.opacity(0.7) : .red.opacity(0.5),
                                radius: 6, x: 0, y: 0
                            )
                    } else {
                        Color.clear
                            .frame(width: 60, height: isCatcherCard ? 72 : 90)
                    }
                }
                .padding(.vertical, 6)
                .padding(.trailing, 10)
            }
        }
    }

    private var isCatcherCard: Bool {
        topText == "Catcher"
    }

    private var scoutCompactContent: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    if let primaryLine = scoutPrimaryLine {
                        scoutSummaryLine(primaryLine, font: .system(size: 20, weight: .medium))
                    } else {
                        Text("Tracked")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.black)
                    }

                    ForEach(Array(scoutSecondaryLines.prefix(2).enumerated()), id: \.offset) { item in
                        scoutSummaryLine(item.element, font: .system(size: 14, weight: .regular))
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    if let num = jerseyNumber, !num.isEmpty {
                        HStack(spacing: 6) {
                            Text(num)
                                .font(.system(size: 15, weight: .bold))
                                .monospacedDigit()
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .padding(.horizontal, num.count > 1 ? 8 : 0)
                                .frame(width: num.count > 1 ? nil : 22, height: 22)
                                .background(
                                    Group {
                                        if num.count > 1 {
                                            Capsule().fill(Color.blue)
                                        } else {
                                            Circle().fill(Color.blue)
                                        }
                                    }
                                )
                            if let count = atBatCountText, !count.isEmpty {
                                Text(count)
                                    .font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundColor(.black.opacity(0.75))
                            }
                        }
                    } else if let count = atBatCountText, !count.isEmpty {
                        Text(count)
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(.black.opacity(0.75))
                    }
                }
            }

            Spacer(minLength: 0)

            Group {
                if let rightImage {
                    rightImage
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 90, alignment: .top)
                        .shadow(
                            color: rightImageShouldHighlight ? .green.opacity(0.7) : .red.opacity(0.5),
                            radius: 6, x: 0, y: 0
                        )
                } else {
                    Color.clear
                        .frame(width: 60, height: 90)
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 0)
    }
    
    @ViewBuilder
    private var leadingImages: some View {
        if batterSide == .right {
            leftImageView
            if topText != "Catcher" {
                batImageView
            }
        } else {
            if topText != "Catcher" {
                batImageView
            }
            leftImageView
        }
    }
    
    private var leftImageView: some View {
        leftImage
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 60, height: isCatcherCard ? 72 : 90)
    }
    
    private var batImageView: some View {
        Image("Bat")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 20, height: 70)
            .padding(.horizontal, 0)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(trackingMode == .scout ? 0.08 : 0.15), radius: trackingMode == .scout ? 4 : 6, x: 0, y: trackingMode == .scout ? 2 : 3)
    }

    private var scoutPrimaryLine: String? {
        let lines = outcomeSummary ?? []
        return lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    private var scoutSecondaryLines: [String] {
        let lines = outcomeSummary ?? []
        guard !lines.isEmpty else { return [] }
        return Array(lines.dropFirst()).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    @ViewBuilder
    private func scoutSummaryLine(_ line: String, font: Font) -> some View {
        let tokens = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let firstToken = tokens.first.map(String.init) ?? ""
        let hasSymbolPrefix = firstToken.hasSuffix(".circle") || firstToken == "f.circle"
        let displayText: String = {
            guard hasSymbolPrefix else { return line }
            if tokens.count > 1 { return String(tokens[1]) }
            return line
        }()
        let showRunner: Bool = ["1B", "2B", "3B", "HR"].contains { prefix in
            displayText.uppercased().hasPrefix(prefix)
        }

        HStack(spacing: 4) {
            if hasSymbolPrefix {
                Image(systemName: firstToken)
                    .font(font)
                    .foregroundColor(.black)
            }
            if showRunner {
                Image(systemName: "figure.run")
                    .font(font)
                    .foregroundColor(.black)
            }
            Text(displayText)
                .font(font)
                .foregroundColor(.black)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}

enum PitchAssetMapper {
    private static func normalizedKey(from label: String) -> String {
        var key = label
        // Standardize common phrases and symbols
        key = key.replacingOccurrences(of: " & ", with: " And ")
        key = key.replacingOccurrences(of: "&", with: "And")
        key = key.replacingOccurrences(of: "↓", with: "Down")
        key = key.replacingOccurrences(of: "↑", with: "Up")
        key = key.replacingOccurrences(of: "→", with: "Right")
        key = key.replacingOccurrences(of: "←", with: "Left")
        // Remove em/en dashes and hyphens
        key = key.replacingOccurrences(of: "—", with: " ")
        key = key.replacingOccurrences(of: "–", with: " ")
        key = key.replacingOccurrences(of: "-", with: " ")
        // Collapse multiple spaces and then remove spaces
        key = key.replacingOccurrences(of: "  ", with: " ")
        key = key.replacingOccurrences(of: "  ", with: " ")
        key = key.replacingOccurrences(of: " ", with: "")
        return key
    }
    
    static func imageName(for rawLabel: String, isStrike: Bool, batterSide: BatterSide) -> String {
        // Build adjusted label using the same manager the rest of the app uses
        let manager = PitchLabelManager(batterSide: batterSide)
        let adjusted = manager.adjustedLabel(from: rawLabel)

        // Compose the same lookup key used by PitchImageDictionary
        let prefix = isStrike ? "Strike" : "Ball"
        let sideKey = batterSide.rawValue // "left" or "right"
        let trimmed = adjusted.trimmingCharacters(in: .whitespacesAndNewlines)
        let lookupKey = "\(prefix) \(trimmed)|\(sideKey)"
        debugLog("🔎 Left-image lookup key: \(lookupKey)")

        // If the dictionary has an explicit mapping, use it for perfect parity with the right image
        if let mapped = PitchImageDictionary.imageMap[lookupKey] {
            debugLog("✅ Using mapped asset: \(mapped)")
            return mapped
        }

        // If not mapped explicitly, fall back to our normalized construction
        let cleaned = adjusted
            .replacingOccurrences(of: "Strike ", with: "")
            .replacingOccurrences(of: "Ball ", with: "")
        let normalized = normalizedKey(from: cleaned)

        // Neutral zones without side suffix
        let neutralZones = ["High", "Low", "Middle"]
        if neutralZones.contains(normalized) {
            let candidate = (isStrike ? "Strike" : "ball") + normalized
            if UIImage(named: candidate) != nil {
                debugLog("🔧 Asset name (neutral): \(candidate)")
                return candidate
            } else {
                let fallback = isStrike ? "StrikeMiddle" : "ballMiddle"
                debugLog("⚠️ Missing asset: \(candidate). Falling back to \(fallback)")
                return fallback
            }
        }

        // Try side-agnostic first (some assets may omit side suffix)
        let base = (isStrike ? "Strike" : "ball") + normalized
        if UIImage(named: base) != nil {
            debugLog("🔧 Asset name (agnostic): \(base)")
            return base
        }

        // Then side-specific
        let suffix = batterSide == .left ? "Right" : "Left"
        let candidate = base + suffix
        if UIImage(named: candidate) != nil {
            debugLog("🔧 Asset name: \(candidate)")
            return candidate
        }

        // Final fallback
        let fallback = isStrike ? "StrikeMiddle" : "ballMiddle"
        debugLog("❌ Missing assets for key=\(lookupKey). Falling back to \(fallback)")
        return fallback
    }
}

// Used in PitchResultSheet
struct PitchResultCard: View {
    let event: PitchEvent
    let allEvents: [PitchEvent] // ✅ Add this
    let games: [Game]
    let templateName: String
    let isParticipant: Bool
    let selectedPlayerName: String
    
    @Binding var isSelecting: Bool
    @Binding var isSelected: Bool

    init(
        event: PitchEvent,
        allEvents: [PitchEvent],
        games: [Game],
        templateName: String,
        selectedPlayerName: String,
        isSelecting: Binding<Bool> = .constant(false),
        isSelected: Binding<Bool> = .constant(false),
        isParticipant: Bool = false
    ) {
        self.event = event
        self.allEvents = allEvents
        self.games = games
        self.templateName = templateName
        self.selectedPlayerName = selectedPlayerName
        self._isSelecting = isSelecting
        self._isSelected = isSelected
        self.isParticipant = isParticipant
    }

    private func isLocationMatch(_ event: PitchEvent) -> Bool {
        return strictIsLocationMatch(event)
    }
    
    private func isFullySuccessful(_ event: PitchEvent) -> Bool {
        // Provide a simple heuristic for success (stub)
        return isLocationMatch(event)
    }

        var body: some View {
        let leftImageName: String = {
            let calledPitchName = event.calledPitch?.pitch.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if calledPitchName == "Catcher" {
                return "Catcher"
            }
            let calledIsStrike = event.calledPitch?.isStrike ?? false
            let rawCalledLocation = (event.calledPitch?.location ?? "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedCalledLocation: String
            if rawCalledLocation.hasPrefix("Strike ") || rawCalledLocation.hasPrefix("Ball ") {
                normalizedCalledLocation = rawCalledLocation
            } else {
                normalizedCalledLocation = "\(calledIsStrike ? "Strike" : "Ball") \(rawCalledLocation)"
            }
            return PitchImageDictionary.imageName(
                for: normalizedCalledLocation,
                isStrike: calledIsStrike,
                batterSide: event.batterSide
            )
        }()
        
        let rightImageName: String? = {
            let calledPitchName = event.calledPitch?.pitch.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let savedLocation = event.location.trimmingCharacters(in: .whitespacesAndNewlines)
            let callLocation = event.calledPitch?.location.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Catcher calls can keep a placeholder saved location while the tapped result lives on the call payload.
            let resolvedLocation: String = {
                if !savedLocation.isEmpty, savedLocation != "Catcher" {
                    return savedLocation
                }
                if calledPitchName == "Catcher", !callLocation.isEmpty, callLocation != "Catcher" {
                    return callLocation
                }
                return savedLocation
            }()

            guard !resolvedLocation.isEmpty, resolvedLocation != "Catcher" else {
                return nil
            }

            return PitchImageDictionary.imageName(
                for: resolvedLocation,
                isStrike: event.isStrike,
                batterSide: event.batterSide
            )
        }()
        
        let didHitLocation: Bool = isLocationMatch(event)
        let actualResultIsStrikeZone: Bool = event.isStrike
        
        // TEMP DEBUG: print normalized comparison inputs and result (no extra scope to satisfy some View body)
        let _ = {
            func normalizedPitch(_ raw: String) -> String {
                raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            struct ParsedLocation { let type: String?; let zone: String }
            func parseLocation(_ raw: String, batterSide: BatterSide) -> ParsedLocation {
                let manager = PitchLabelManager(batterSide: event.batterSide)
                let adjusted = manager.adjustedLabel(from: raw)
                let cleaned = adjusted
                    .replacingOccurrences(of: "—", with: " ")
                    .replacingOccurrences(of: "–", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .replacingOccurrences(of: "&", with: "and")
                    .replacingOccurrences(of: "  ", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if cleaned.hasPrefix("strike ") {
                    let zone = String(cleaned.dropFirst("strike ".count)).trimmingCharacters(in: .whitespaces)
                    return ParsedLocation(type: "strike", zone: zone)
                } else if cleaned.hasPrefix("ball ") {
                    let zone = String(cleaned.dropFirst("ball ".count)).trimmingCharacters(in: .whitespaces)
                    return ParsedLocation(type: "ball", zone: zone)
                } else {
                    return ParsedLocation(type: nil, zone: cleaned)
                }
            }
            let calledPitchRaw = event.calledPitch?.pitch ?? "<nil>"
            let calledLocRaw = event.calledPitch?.location ?? "<nil>"
            let actualPitchRaw = event.pitch
            let actualLocRaw = event.location
            let calledPitchNorm = normalizedPitch(calledPitchRaw)
            let actualPitchNorm = normalizedPitch(actualPitchRaw)
            let calledLoc = parseLocation(calledLocRaw, batterSide: event.batterSide)
            let actualLoc = parseLocation(actualLocRaw, batterSide: event.batterSide)
            debugLog("🧪 Match debug — didHitLocation=\(didHitLocation)\n  called.pitch=\(calledPitchRaw) -> \(calledPitchNorm)\n  actual.pitch=\(actualPitchRaw) -> \(actualPitchNorm)\n  called.loc=\(calledLocRaw) -> type=\(calledLoc.type ?? "<none>") zone=\(calledLoc.zone)\n  actual.loc=\(actualLocRaw) -> type=\(actualLoc.type ?? "<none>") zone=\(actualLoc.zone)")
            return ()
        }()
        
        let verticalTopImageName: String = didHitLocation ? "hitCircle" : "missedCircle"
        
        let overallSuccessRate: Int = {
            let matchingCalls = allEvents.filter {
                return $0.calledPitch?.pitch == event.calledPitch?.pitch
            }
            let successes = matchingCalls.filter { isFullySuccessful($0) }.count
            let total = matchingCalls.count
            return statPercent(successes, of: total)
        }()
        
        let locationSuccessRate: Int = {
            let matchingCalls = allEvents.filter {
                $0.calledPitch?.pitch == event.calledPitch?.pitch &&
                $0.calledPitch?.location == event.calledPitch?.location
            }
            let successes = matchingCalls.filter { isFullySuccessful($0) }.count
            let total = matchingCalls.count
            return statPercent(successes, of: total)
        }()
        
        let timestampText: String = formattedTimestamp(event.timestamp)
        let outcomeSummary: [String] = outcomeSummaryLines(for: event)
        let jerseyNumber: String? = event.opponentJersey
        let resolvedAllEvents: [PitchEvent] = allEvents.map { candidate in
            if candidate.identity == event.identity {
                return event
            }
            return candidate
        }

        HStack(alignment: .center, spacing: 8) {
            if isSelecting {
                VStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .secondary)
                        .font(.title3)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isSelected.toggle()
                        }
                }
                .padding(.leading, 8)
            }

            PitchCardView(
                batterSide: event.batterSide,
                leftImage: Image(leftImageName),
                topText: event.calledPitch?.pitch ?? "-",
                middleText: "\(overallSuccessRate)% overall",
                bottomText: "\(locationSuccessRate)% @ location",
                verticalTopImage: Image(verticalTopImageName),
                rightImage: rightImageName.map { Image($0) },
                rightImageShouldHighlight: actualResultIsStrikeZone,
                footerTextName: selectedPlayerName,
                footerTextDate: "\(timestampText)",
                pitchNumber: pitchNumber(for: event, in: resolvedAllEvents),
                outcomeSummary: outcomeSummary,
                jerseyNumber: jerseyNumber,
                atBatCountText: event.atBatCount,
                trackingMode: event.trackingMode ?? .coach,
                gameTitle: derivedGameTitle(from: event),
                hideHeader: isParticipant,
                onLongPress: { }
            )
        }
        .padding(.horizontal, 2)
    }
    
    private func derivedGameTitle(from event: PitchEvent) -> String? {
        guard let gid = event.gameId, !gid.isEmpty else { return nil }
        if let game = games.first(where: { $0.id == gid }) {
            return game.opponent
        }
        return nil
    }
    
    private func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "'Today,' h:mm a"
        } else {
            formatter.dateFormat = "MM/dd/yy h:mm a"
        }
        
        return formatter.string(from: date)
    }
}

func pitchNumber(for event: PitchEvent, in allEvents: [PitchEvent]) -> Int {
    let eventGameId = event.gameId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let eventPitcherId = event.pitcherId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    let scopedEvents = allEvents.filter { evt in
        guard evt.mode == .game else { return false }

        let evtGameId = evt.gameId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let evtPitcherId = evt.pitcherId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // In game mode, require a strict gameId match whenever either side has one.
        if !eventGameId.isEmpty || !evtGameId.isEmpty {
            guard eventGameId == evtGameId else { return false }
        }

        // Keep numbering scoped per pitcher whenever either event declares a pitcher.
        if !eventPitcherId.isEmpty || !evtPitcherId.isEmpty {
            guard eventPitcherId == evtPitcherId else { return false }
        }

        return true
    }

    // Make ordering deterministic when timestamps tie.
    let sorted = scopedEvents.sorted { lhs, rhs in
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        return lhs.identity < rhs.identity
    }

    if let index = sorted.firstIndex(where: { $0.identity == event.identity }) {
        return index + 1
    }

    // Fallback: if identity changed due to local overrides, match by stable Firestore id.
    if let eventId = event.id, !eventId.isEmpty,
       let index = sorted.firstIndex(where: { $0.id == eventId }) {
        return index + 1
    }

    return nilCoalescedPitchNumber(from: sorted, for: event)
}

private func nilCoalescedPitchNumber(from sorted: [PitchEvent], for event: PitchEvent) -> Int {
    // Last-resort deterministic insertion position rather than returning 0.
    for (index, candidate) in sorted.enumerated() {
        if event.timestamp < candidate.timestamp {
            return max(1, index + 1)
        }
        if event.timestamp == candidate.timestamp && event.identity < candidate.identity {
            return max(1, index + 1)
        }
    }
    return max(1, sorted.count + 1)
}


struct CalledPitchRecord: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let pitch: String
    let calledLocation: String
    let actualLocation: String?
    let isCalledStrike: Bool
    let isActualStrike: Bool?
    let assignedCodes: [String]
    let batterSideRaw: String?
    let notes: String?
    let mode: String
}

/// One team's slice of the lineup for the pin sheet's batter strip.
///
/// The strip shows *every* cell in the lineup, both teams' - which cell you
/// can select and edit here is deliberately not scoped the way the At Bat
/// scroll is. Without a break between them it reads as one undifferentiated
/// row of numbers with no way to tell whose batter is whose.
struct LineupBatterGroup: Identifiable {
    let id: String
    let title: String
    /// The side currently at bat. Listed first and marked.
    let isBatting: Bool
    let cells: [JerseyCell]
    /// This team's roster players who aren't in the game, shown in a Bench
    /// row under its In Game row. Empty when the team has no roster.
    var bench: [LineupBenchPlayer] = []
    /// Roster players left off the bench because this user archived them.
    /// Named under the bench so a short bench never looks like a bug.
    var archivedNames: [String] = []
}

/// A roster player on the bench, in terms this file can hold - it is also
/// compiled into the Display target, which has no Team/TeamPlayer.
struct LineupBenchPlayer: Identifiable, Equatable {
    /// The TeamPlayer id.
    let id: String
    /// What the chip shows: the jersey, or initials when there's none.
    let label: String
    let name: String
    /// Whether the player has a hitting record to show stats for.
    let hasHitterRecord: Bool
}

/// Whichever chip is highlighted in the lineup sheet - a batter in the game
/// or a player on the bench. The action row and Hitting Stats act on it.
enum LineupPlayerTarget {
    case batter(JerseyCell)
    case bench(LineupBenchPlayer)
}

struct PitchEventDetailPopover: View {
    let event: PitchEvent
    let allEvents: [PitchEvent]
    let templateName: String
    let pitcherNameById: [String: String]
    let gameIdFilter: String?
    let lineupBatters: [JerseyCell]
    /// Grouped view of `lineupBatters`. Empty, or a single group, renders
    /// the original flat strip, so a one-team game looks exactly as before.
    var lineupGroups: [LineupBatterGroup] = []
    /// Cells with no roster link behind them - a bare jersey number typed
    /// into the lineup, or one added before the link was recorded. They sit
    /// in the batting team's row rather than a section of their own, and are
    /// told apart by fill colour alone.
    var unlinkedBatterIds: Set<UUID> = []
    let selectedLineupBatterId: UUID?
    let onEditLineupBatter: (JerseyCell) -> Void
    /// Move `moving` to `target`'s position. Only rearranges - persisting
    /// is `onCommitLineupOrder`.
    let onReorderLineupBatter: (JerseyCell, JerseyCell) -> Void
    /// Write the order down.
    let onCommitLineupOrder: () -> Void
    let onDeleteLineupBatter: (JerseyCell) -> Void
    let currentCountSeed: (balls: Int, strikes: Int)?
    let onCountChanged: ((Int, Int) -> Void)?
    /// Display names for in-game cells that are roster players.
    var batterNameById: [UUID: String] = [:]
    /// Take a roster batter out of the game, onto their team's bench. When
    /// nil (or for a bare jersey number) the row keeps the Delete button.
    var onBenchLineupBatter: ((JerseyCell) -> Void)? = nil
    var onPutInGame: ((LineupBenchPlayer) -> Void)? = nil
    var onEditBenchPlayer: ((LineupBenchPlayer) -> Void)? = nil
    var onHittingStats: ((LineupPlayerTarget) -> Void)? = nil
    /// This game's field positions (LineupFieldPositions).
    var fieldPositionByBatterId: [UUID: String] = [:]
    /// The whole new map after a position change. nil = read-only (an
    /// assistant, or no game).
    var onFieldPositionsChanged: (([UUID: String]) -> Void)? = nil
    @State private var batterNotes: String = ""
    @State private var isBatterNotesFocused: Bool = false
    // Spray chart starts collapsed: it's a 330pt block, and the batters and
    // pitch cards above it are what the sheet is opened for. Notes start
    // expanded - they're one row at the bottom either way.
    @State private var isSprayExpanded: Bool = false
    @State private var isNotesExpanded: Bool = true
    /// The pitch cards start collapsed too (2026-11-02): the lineup above
    /// is what the sheet is opened for.
    @State private var isPitchCardsExpanded: Bool = false
    /// A bench chip that's been tapped. Bench players aren't batters, so
    /// this is the sheet's own highlight rather than the game's selection;
    /// it wins over the selected batter while set.
    @State private var highlightedBenchId: String? = nil
    /// The team whose field view is open.
    @State private var fieldPositionsTarget: FieldPositionsTarget? = nil
    /// The lineup player tapped in this sheet. Looking at a player (their
    /// stats, notes, moving them) never changes who is batting in the game
    /// (user's call, 2026-11-05) - so it's the sheet's own, and the game's
    /// batter is only where it starts.
    @State private var viewedBatterId: UUID? = nil

    private var sheetSelectedBatterId: UUID? {
        viewedBatterId ?? selectedLineupBatterId
    }

    /// Selection still wins over the unassigned tint - otherwise an
    /// unassigned batter you've selected would be the only cell in the strip
    /// with no visible selection.
    private func jerseyFill(isSelected: Bool, isUnlinked: Bool) -> Color {
        if isSelected { return .blue }
        return isUnlinked ? Color.orange.opacity(0.22) : Color(.systemGray6)
    }

    private func jerseyStroke(isSelected: Bool, isUnlinked: Bool) -> Color {
        if isSelected { return Color.blue.opacity(0.95) }
        return isUnlinked ? Color.orange.opacity(0.55) : Color.black.opacity(0.12)
    }

    /// The batting order as a vertical list - order number, jersey chip,
    /// the player's name, and their field position - shared by the flat and
    /// the grouped renderings so the two can't drift. (Was a horizontal
    /// strip until 2026-11-02; drag-to-reorder became the Order arrows
    /// 2026-11-03.)
    private func lineupList(_ cells: [JerseyCell]) -> some View {
        let teamCellIds = Set(cells.map { $0.id })
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                let isSelected = highlightedBenchId == nil && cell.id == sheetSelectedBatterId
                let isUnlinked = unlinkedBatterIds.contains(cell.id)
                HStack(spacing: 6) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .trailing)
                    jerseyChip(cell, isSelected: isSelected, isUnlinked: isUnlinked)
                    Text(batterNameById[cell.id] ?? (isUnlinked ? "Not on roster" : ""))
                        .font(.subheadline)
                        .foregroundStyle(isUnlinked ? Color.secondary : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            highlightedBenchId = nil
                            viewedBatterId = cell.id
                        }
                    fieldPositionButton(for: cell, teamCellIds: teamCellIds)
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }

    /// Where the player is on the field this game. Picking a position
    /// someone else on the team holds moves it (LineupFieldPositions).
    @ViewBuilder
    private func fieldPositionButton(for cell: JerseyCell, teamCellIds: Set<UUID>) -> some View {
        let current = fieldPositionByBatterId[cell.id]
        let label = Text(current ?? "Pos")
            .font(.caption.weight(.bold))
            .foregroundStyle(current == nil ? Color.secondary : Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 34, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(.systemGray5))
            )
        if let onFieldPositionsChanged {
            Menu {
                ForEach(LineupFieldPositions.choices, id: \.self) { position in
                    Button {
                        onFieldPositionsChanged(LineupFieldPositions.assign(
                            position, to: cell.id, in: fieldPositionByBatterId, teamCellIds: teamCellIds
                        ))
                    } label: {
                        if position == current {
                            Label(position, systemImage: "checkmark")
                        } else {
                            Text(position)
                        }
                    }
                }
                if current != nil {
                    Divider()
                    Button("No Position", role: .destructive) {
                        onFieldPositionsChanged(LineupFieldPositions.assign(
                            nil, to: cell.id, in: fieldPositionByBatterId, teamCellIds: teamCellIds
                        ))
                    }
                }
            } label: {
                label
            }
            .accessibilityLabel("Field position for batter \(cell.jerseyNumber): \(current ?? "none")")
        } else {
            label
                .accessibilityLabel("Field position: \(current ?? "none")")
        }
    }

    /// "Position / Order" over the field icon (opens the team's field view)
    /// and the up/down arrows, which move the
    /// selected batter one spot within that team's order.
    private func orderControls(_ group: LineupBatterGroup) -> some View {
        let cells = group.cells
        let selectedId = highlightedBenchId == nil ? sheetSelectedBatterId : nil
        let up = selectedId.flatMap { LineupOrder.neighbor(of: $0, in: cells, direction: .up) }
        let down = selectedId.flatMap { LineupOrder.neighbor(of: $0, in: cells, direction: .down) }
        let moving = selectedId.flatMap { id in cells.first(where: { $0.id == id }) }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Position / Order")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                Button {
                    fieldPositionsTarget = FieldPositionsTarget(id: group.id, title: group.title, cells: cells)
                } label: {
                    Image(systemName: "baseball.diamond.bases")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(.systemGray5))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Field positions")
                orderArrow("chevron.up", label: "Move batter up", target: up, moving: moving)
                orderArrow("chevron.down", label: "Move batter down", target: down, moving: moving)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private func orderArrow(_ systemImage: String, label: String, target: JerseyCell?, moving: JerseyCell?) -> some View {
        Button {
            guard let moving, let target else { return }
            withAnimation { onReorderLineupBatter(moving, target) }
            onCommitLineupOrder()
        } label: {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .frame(width: 36, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(.systemGray5))
                )
        }
        .buttonStyle(.plain)
        .disabled(moving == nil || target == nil)
        .opacity(moving == nil || target == nil ? 0.35 : 1)
        .accessibilityLabel(label)
    }

    private func jerseyChip(_ cell: JerseyCell, isSelected: Bool, isUnlinked: Bool) -> some View {
        Button {
            highlightedBenchId = nil
            viewedBatterId = cell.id
        } label: {
            // 25% smaller than the original 48x40, with the corner radius
            // and type scaled to match so a two-digit number still fits.
            Text(cell.jerseyNumber)
                .font(.subheadline.weight(.semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 36, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(jerseyFill(isSelected: isSelected, isUnlinked: isUnlinked))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            jerseyStroke(isSelected: isSelected, isUnlinked: isUnlinked),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isUnlinked
            ? "Batter \(cell.jerseyNumber), not on a roster"
            : "Batter \(cell.jerseyNumber)"
        )
        .accessibilityIdentifier("lineup.batter.\(cell.jerseyNumber)")
        .accessibilityValue(isSelected ? "selected" : "")
    }

    private var activeLineupCell: JerseyCell? {
        if let id = sheetSelectedBatterId,
           let matched = lineupBatters.first(where: { $0.id == id }) {
            return matched
        }
        if let eid = event.opponentBatterId,
           let uuid = UUID(uuidString: eid),
           let matched = lineupBatters.first(where: { $0.id == uuid }) {
            return matched
        }
        return lineupBatters.first
    }

    private var activeBatterIdString: String? {
        if let activeLineupCell { return activeLineupCell.id.uuidString }
        if let id = event.opponentBatterId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return id
        }
        return nil
    }

    private var activeJersey: String? {
        if let activeLineupCell { return activeLineupCell.jerseyNumber }
        if let jersey = event.opponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines), !jersey.isEmpty {
            return jersey
        }
        return nil
    }

    var batterEvents: [PitchEvent] {
        let sameGame = allEvents.filter { evt in
            if let gid = gameIdFilter {
                if let evGid = evt.gameId, !evGid.isEmpty { return evGid == gid }
                return true
            }
            if let gid = event.gameId {
                return evt.gameId == gid
            }
            return true
        }

        let idToMatch = activeBatterIdString
        let jerseyToMatch = activeJersey

        let matches = sameGame.filter { other in
            let idMatch = (idToMatch != nil) ? (other.opponentBatterId == idToMatch) : false
            let jerseyMatch = (jerseyToMatch != nil) ? (other.opponentJersey == jerseyToMatch) : false
            return idMatch || jerseyMatch
        }

        if idToMatch == nil && jerseyToMatch == nil {
            return sameGame.sorted { $0.timestamp < $1.timestamp }
        }

        if matches.isEmpty { return [] }
        return matches.sorted { $0.timestamp < $1.timestamp }
    }

    private var batterNotesKey: String? {
        if let id = activeBatterIdString {
            return "batterNotes_id_\(id)"
        }
        if let jersey = activeJersey {
            return "batterNotes_jersey_\(jersey)"
        }
        return nil
    }

    private func normalizeCardPitchDescription(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()

        if collapsed == "strike out" {
            return "Strike outer 1/2"
        }
        return trimmed
    }

    private var eventsWithCoords: [PitchEvent] {
        batterEvents.filter { $0.battedBallTapX != nil && $0.battedBallTapY != nil }
    }

    private var hasIdentity: Bool {
        (batterEvents.first?.opponentBatterId?.isEmpty == false)
            || (batterEvents.first?.opponentJersey?.isEmpty == false)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Batters first: picking which batter this sheet is about is
                // what everything below it depends on.
                battersSection
                pitchCardsSection
                sprayChartSection
                // Notes scroll with everything else, by request. The older
                // arrangement kept this editor outside the scroll view
                // because its tap/focus handling can compete with nested
                // sheet scroll gestures - if typing in here ever starts
                // fighting the scroll, that's the cause.
                notesSection
            }
            // Breathing room between the first header and the top edge of
            // the sheet.
            .padding(.top, 10)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $fieldPositionsTarget) { target in
            // The team's current cells, so a change made since opening
            // shows; falls back to the snapshot taken on tap.
            let cells = lineupGroups.first(where: { $0.id == target.id })?.cells
                ?? (lineupGroups.count <= 1 ? lineupBatters : target.cells)
            FieldPositionsView(
                title: target.title,
                cells: cells,
                positions: fieldPositionByBatterId,
                nameById: batterNameById,
                onChange: onFieldPositionsChanged
            )
            .presentationDetents([.large])
        }
        .onAppear {
            guard let key = batterNotesKey else { return }
            batterNotes = UserDefaults.standard.string(forKey: key) ?? ""
        }
        .onChange(of: batterNotesKey) { _, newKey in
            guard let key = newKey else {
                batterNotes = ""
                return
            }
            batterNotes = UserDefaults.standard.string(forKey: key) ?? ""
        }
        .onChange(of: batterNotes) { _, newValue in
            guard let key = batterNotesKey else { return }
            UserDefaults.standard.set(newValue, forKey: key)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// Header row that doubles as the collapse control, so the whole strip
    /// is the tap target rather than just a chevron.
    private func collapsibleHeader(
        title: String,
        isExpanded: Bool,
        trailing: String? = nil,
        toggle: @escaping () -> Void
    ) -> some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline).bold()
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.subheadline).bold()
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            collapsibleHeader(
                title: "Batter notes",
                isExpanded: isNotesExpanded,
                trailing: isNotesExpanded ? nil : notesSummary
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isNotesExpanded.toggle()
                }
            }

            if isNotesExpanded {
                ZStack(alignment: .topLeading) {
                    FocusableNotesTextView(
                        text: $batterNotes,
                        isFocused: $isBatterNotesFocused
                    )
                    .frame(maxWidth: .infinity, minHeight: 45, maxHeight: 90)

                    if batterNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add notes for this batter...")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 45)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture {
                    isBatterNotesFocused = true
                }
            }
        }
    }

    /// Collapsed, the header says whether there's anything in there at all -
    /// otherwise notes already written would be invisible with no hint.
    private var notesSummary: String? {
        let trimmed = batterNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : "1 note"
    }

    @ViewBuilder
    private var sprayChartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            collapsibleHeader(
                title: "Batter spray chart",
                isExpanded: isSprayExpanded,
                trailing: hasIdentity ? "\(eventsWithCoords.count) \(eventsWithCoords.count == 1 ? "hit" : "hits")" : nil
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSprayExpanded.toggle()
                }
            }

            if isSprayExpanded {
                ZStack {
                    // Background rounded container that clips content
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)

                    // Centered, size-aware spray overlay.
                    //
                    // `allowsHitTesting(false)` is load-bearing, not tidiness:
                    // FieldSprayOverlay deliberately renders an oversized,
                    // cropping image (see its `overscan`), and `.clipped()`
                    // clips *drawing* only - hit testing still covers the
                    // full oversized frame. That overflow sat on top of the
                    // section header above it and swallowed every tap, so
                    // once this chart was expanded it could not be collapsed
                    // again. The chart is display-only here, so it wants no
                    // taps at all.
                    FieldSprayOverlay(
                        fieldImageName: "FieldImage2",
                        events: eventsWithCoords,
                        homePlateNormalized: CGPoint(x: 0.5, y: 0.69),
                        focalNormalized: CGPoint(x: 0.5, y: 0.45),
                        overscan: 1.0
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, minHeight: 330, maxHeight: 330)
                .clipped()
                // Bounds hit testing to the container itself, for the same
                // reason - `.clipped()` alone would not.
                .contentShape(Rectangle())
            }
        }
    }

    private var pitchCardsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            collapsibleHeader(
                title: "Pitch cards",
                isExpanded: isPitchCardsExpanded,
                trailing: hasIdentity ? "\(batterEvents.count) \(batterEvents.count == 1 ? "pitch" : "pitches")" : nil
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPitchCardsExpanded.toggle()
                }
            }
            if isPitchCardsExpanded {
                pitchCardsStrip
            }
        }
    }

    private var pitchCardsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(batterEvents.reversed().enumerated()), id: \.offset) { item in
                    let evt = item.element
                    let isSource = (evt.id != nil && evt.id == event.id) || (evt.id == nil && event.id == nil && evt.timestamp == event.timestamp)
                    HStack(alignment: .top, spacing: 10) {
                        let calledLabel = evt.calledPitch.map { normalizeCardPitchDescription("\($0.type) \($0.location)") }
                        let resultLabel: String = {
                            let loc = evt.location.trimmingCharacters(in: .whitespacesAndNewlines)
                            let lowered = loc.lowercased()
                            // Avoid duplicating "Strike"/"Ball" when location already includes it.
                            if lowered.hasPrefix("strike ") || lowered == "strike" || lowered.hasPrefix("ball ") || lowered == "ball" {
                                return normalizeCardPitchDescription(loc)
                            }
                            return normalizeCardPitchDescription("\(evt.isStrike ? "Strike" : "Ball") \(loc)")
                        }()
                        let pitcherName: String = {
                            if let pid = evt.pitcherId,
                               let name = pitcherNameById[pid],
                               !name.isEmpty {
                                return name
                            }
                            return "-"
                        }()
                        VStack(alignment: .leading, spacing: 2) {
                            if let calledLabel {
                                Text("(Coach): \(calledLabel)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text("(Result): \(resultLabel)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("(Pitcher): \(pitcherName)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(minWidth: 180, maxWidth: 220, alignment: .leading)
                        .layoutPriority(1)

                        OutcomeSummaryView(
                            lines: outcomeSummaryLines(for: evt),
                            jerseyNumber: evt.opponentJersey,
                            countText: evt.atBatCount,
                            minHeight: 0
                        )
                        .frame(width: 112)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.systemBackground))
                            .shadow(color: isSource ? Color.blue.opacity(0.45) : Color.black.opacity(0.15), radius: isSource ? 6 : 6, x: 0, y: isSource ? 0 : 3)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSource ? Color.blue.opacity(0.6) : Color.black.opacity(0.08), lineWidth: isSource ? 2 : 1)
                    )
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 8)
        }
        .frame(minHeight: 160)
    }

    /// Two teams side by side, each a vertical list: bold team name, the
    /// batting order (order number, jersey, name), then the bench. The
    /// columns together take about 70% of the screen height and scroll on
    /// their own (2026-11-02, user's layout).
    @ViewBuilder
    private var battersSection: some View {
        let showsGroups = lineupGroups.count > 1 || lineupGroups.contains { !$0.bench.isEmpty || !$0.archivedNames.isEmpty }
        if !lineupBatters.isEmpty || showsGroups {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    if showsGroups {
                        ForEach(lineupGroups) { group in
                            teamColumn(group)
                        }
                    } else {
                        teamColumn(LineupBatterGroup(id: "lineup", title: "Lineup", isBatting: true, cells: lineupBatters))
                    }
                }
                .frame(height: lineupColumnsHeight)

                if let benchPlayer = highlightedBenchPlayer {
                    benchActionRow(benchPlayer)
                } else if let selectedCell = selectedLineupCell {
                    batterActionRow(selectedCell)
                } else {
                    Text("Tap a player to edit them, see their hitting stats, or move them between the game and the bench.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 0)
        }
    }

    private var lineupColumnsHeight: CGFloat {
        UIScreen.main.bounds.height * 0.7
    }

    private func teamColumn(_ group: LineupBatterGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(group.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(group.isBatting ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if group.isBatting, lineupGroups.count > 1 {
                    Text("at bat")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.pitchMarkActiveGray))
                        .fixedSize()
                }
            }
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {
                    rowCaption("In Game")
                    if group.cells.isEmpty {
                        emptyRowNote("No one in the game yet.")
                    } else {
                        lineupList(group.cells)
                    }
                    if !group.bench.isEmpty {
                        rowCaption("Bench")
                            .padding(.top, 6)
                        benchList(group.bench)
                    }
                    if !group.archivedNames.isEmpty {
                        Label(
                            "Archived, not shown: \(group.archivedNames.joined(separator: ", ")). Unarchive from the team roster on Home.",
                            systemImage: "archivebox"
                        )
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !group.cells.isEmpty {
                orderControls(group)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    /// Only an explicit selection - unlike `activeLineupCell`, never falls
    /// back to the first batter, so the action row can't act on someone
    /// who isn't highlighted.
    private var selectedLineupCell: JerseyCell? {
        guard let id = sheetSelectedBatterId else { return nil }
        return lineupBatters.first(where: { $0.id == id })
    }

    private var highlightedBenchPlayer: LineupBenchPlayer? {
        guard let highlightedBenchId else { return nil }
        return lineupGroups.lazy.flatMap(\.bench).first(where: { $0.id == highlightedBenchId })
    }

    private func rowCaption(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func emptyRowNote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
    }

    /// Bench rows: the chip is the same size as the lineup's, outlined
    /// rather than filled so the two lists read differently at a glance,
    /// with the name beside it. No order number or drag handle - the bench
    /// has no batting order.
    private func benchList(_ players: [LineupBenchPlayer]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(players) { player in
                let isSelected = player.id == highlightedBenchId
                Button {
                    highlightedBenchId = isSelected ? nil : player.id
                } label: {
                    HStack(spacing: 6) {
                        Color.clear.frame(width: 18, height: 1)
                        Text(player.label)
                            .font(.subheadline.weight(.semibold))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                            .foregroundStyle(isSelected ? Color.white : Color.secondary)
                            .frame(width: 36, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? Color.blue : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        isSelected ? Color.blue.opacity(0.95) : Color.secondary.opacity(0.5),
                                        style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: isSelected ? [] : [3, 2])
                                    )
                            )
                        Text(player.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(player.name), on the bench")
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }

    private func benchActionRow(_ player: LineupBenchPlayer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(player.name) · on the bench")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: 8) {
                if let onEditBenchPlayer {
                    batterLabelButton("#", systemImage: "pencil", fills: false) {
                        onEditBenchPlayer(player)
                    }
                }
                if let onHittingStats, player.hasHitterRecord {
                    batterLabelButton("Hit & Field", systemImage: "chart.bar", fills: false) {
                        onHittingStats(.bench(player))
                    }
                }

                Spacer(minLength: 8)

                if let onPutInGame {
                    batterLabelButton("Put In Game", systemImage: "arrow.up", fills: false) {
                        highlightedBenchId = nil
                        onPutInGame(player)
                    }
                }
            }
        }
    }

    /// Reordering is the Order arrows under each team's column
    /// (2026-11-03), so this row is just the two actions that apply to the
    /// selected batter.
    ///
    /// `buttonBorderShape` is explicit because a large bordered button
    /// defaults to a capsule, which on a one-glyph label like "#" renders as
    /// a near-circle.
    private func batterActionRow(_ activeCell: JerseyCell) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(batterNameById[activeCell.id].map { "\($0) · in the game. Move them with the arrows above." }
                 ?? "Batting order: use the arrows under Position / Order")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: 8) {
                batterLabelButton("#", systemImage: "pencil", fills: false) {
                    onEditLineupBatter(activeCell)
                }
                let isRosterPlayer = !unlinkedBatterIds.contains(activeCell.id)
                if let onHittingStats, isRosterPlayer {
                    batterLabelButton("Hit & Field", systemImage: "chart.bar", fills: false) {
                        onHittingStats(.batter(activeCell))
                    }
                }

                Spacer(minLength: 8)

                // A roster player goes back to the bench - they still exist
                // on the team. A bare jersey number has no bench to go to,
                // so it keeps Delete.
                if let onBenchLineupBatter, isRosterPlayer {
                    batterLabelButton("Bench", systemImage: "arrow.down", fills: false) {
                        onBenchLineupBatter(activeCell)
                    }
                } else {
                    batterIconButton(
                        "trash",
                        accessibilityLabel: "Delete batter",
                        role: .destructive
                    ) {
                        onDeleteLineupBatter(activeCell)
                    }
                }
            }
        }
    }

    private func batterIconButton(
        _ systemImage: String,
        accessibilityLabel: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .frame(width: 30)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .accessibilityLabel(accessibilityLabel)
    }

    /// `fills: true` hands the button the row's leftover width; `false`
    /// keeps it to its own content. Either way the label is one line at
    /// full size - never scaled down, so nothing truncates.
    private func batterLabelButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        fills: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: fills ? .infinity : nil)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: 10))
    }

}

struct FieldSprayOverlay: View {
    let fieldImageName: String
    let events: [PitchEvent]
    // Normalized (0..1) position of home plate within the field image
    let homePlateNormalized: CGPoint

    let focalNormalized: CGPoint
    
    let overscan: CGFloat

    init(fieldImageName: String, events: [PitchEvent], homePlateNormalized: CGPoint = CGPoint(x: 0.5, y: 0.88), focalNormalized: CGPoint = CGPoint(x: 0.5, y: 0.60), overscan: CGFloat = 1.0) {
        self.fieldImageName = fieldImageName
        self.events = events
        self.homePlateNormalized = homePlateNormalized
        self.focalNormalized = focalNormalized
        self.overscan = overscan
    }

    var body: some View {
        GeometryReader { geo in
            let availableSize = geo.size
            let uiImage = UIImage(named: fieldImageName) ?? UIImage(named: "FieldImage")
            let aspect: CGFloat = {
                if let img = uiImage, img.size.height > 0 { return img.size.width / img.size.height }
                return 1
            }()

            // Fill the image within the available size (may crop) for better container coverage
            let targetSize: CGSize = {
                if let img = uiImage, img.size.width > 0, img.size.height > 0 {
                    let scale = max(availableSize.width / img.size.width, availableSize.height / img.size.height) * max(overscan, 1.0)
                    return CGSize(width: img.size.width * scale, height: img.size.height * scale)
                } else {
                    // Fallback to filling by width using the computed aspect, and then by height
                    let width = availableSize.width
                    let height = width / max(aspect, 0.0001)
                    if height < availableSize.height {
                        // Fill by height if needed
                        let height = availableSize.height
                        let width = height * max(aspect, 0.0001)
                        return CGSize(width: width, height: height)
                    }
                    return CGSize(width: width, height: height)
                }
            }()
            let targetWidth = targetSize.width
            let targetHeight = targetSize.height

            let imageRect = CGRect(
                x: (availableSize.width - targetWidth) / 2,
                y: (availableSize.height - targetHeight) / 2,
                width: targetWidth,
                height: targetHeight
            )
            
            // Compute focal shift to center a chosen point of the image within the container
            let containerCenter = CGPoint(x: availableSize.width / 2, y: availableSize.height / 2)
            let focalPoint = CGPoint(
                x: imageRect.minX + imageRect.width * focalNormalized.x,
                y: imageRect.minY + imageRect.height * focalNormalized.y
            )
            let focalShift = CGPoint(x: containerCenter.x - focalPoint.x, y: containerCenter.y - focalPoint.y)
            
            // Home plate position within the fitted image, configurable via `homePlateNormalized`
            let origin = CGPoint(
                x: imageRect.minX + imageRect.width * homePlateNormalized.x + focalShift.x,
                y: imageRect.minY + imageRect.height * homePlateNormalized.y + focalShift.y
            )
            
            // Convert normalized tap coordinates to points within the fitted image rect
            let plottedPoints: [CGPoint] = events.compactMap { evt in
                guard let nx = evt.battedBallTapX, let ny = evt.battedBallTapY else { return nil }
                let px = imageRect.minX + CGFloat(nx) * imageRect.width + focalShift.x
                let py = imageRect.minY + CGFloat(ny) * imageRect.height + focalShift.y
                return CGPoint(x: px, y: py)
            }

            ZStack {
                if let uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX + focalShift.x, y: imageRect.midY + focalShift.y)
                }

                // Home plate reference marker
                Circle()
                    .fill(Color.black.opacity(0.25))
                    .frame(width: 4, height: 4)
                    .position(x: origin.x, y: origin.y)
                    .allowsHitTesting(false)
                
                if plottedPoints.isEmpty {
                    // Empty-state hint when there are no plotted points
                    Text("🥹")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX + focalShift.x, y: imageRect.midY + focalShift.y)
                        .allowsHitTesting(false)
                } else {
                    ForEach(Array(plottedPoints.enumerated()), id: \.offset) { item in
                        let index = item.offset
                        let point = item.element
                        let linesLower = outcomeSummaryLines(for: events[index]).map { $0.lowercased() }
                        let isHit = linesLower.contains { line in
                            line.contains("safe") || line.contains("1b") || line.contains("2b") || line.contains("3b") || line.contains("hr")
                        }
                        let isFoul = events[index].isFoulInferred || linesLower.contains { line in
                            line.contains("foul")
                        }
                        let isOut = linesLower.contains { line in
                            line.contains("out")
                        }
                        let foulOnly = isFoul && !isOut

                        // Solid path from home plate to marker
                        SprayPath(start: origin, end: point)
                            .stroke(style: StrokeStyle(lineWidth: 2.0))
                            .foregroundStyle((isHit && !isFoul) ? Color.white : ((!isHit && !isFoul) ? Color.red : Color.black.opacity(0.25)))
                            .frame(width: availableSize.width, height: availableSize.height, alignment: .topLeading)

                        // Use corresponding event to color the marker
                        let event = events[index]
                        MarkerView(isHR: event.isHomeRunInferred, isFoul: foulOnly, highlight: (isHit && !isFoul))
                            .position(x: point.x, y: point.y)
                            .shadow(radius: 2)
                    }
                }
            }
            .frame(width: availableSize.width, height: availableSize.height, alignment: .topLeading)
        }
    }
}

private struct MarkerView: View {
    let isHR: Bool
    let isFoul: Bool
    let highlight: Bool

    var body: some View {
        let fill: Color = {
            if highlight { return .green }
            if isFoul { return .white }
            return .red
        }()

        return Circle()
            .fill(fill)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(.white, lineWidth: 1)
            )
    }
}

private struct SprayPath: Shape {
    let start: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}

struct PitchResultSheet: View {
    let allEvents: [PitchEvent]
    let games: [Game]
    let templates: [PitchTemplate]
    let pitchers: [Pitcher]
    let isParticipant: Bool
    let selectedPlayerName: String
    var gameOwnerUserId: String? = nil
    var liveGameId: String? = nil
    var sharedDeletedEventIDs: Set<String> = []
    var onDeleteEventIDs: ((Set<String>) -> Void)? = nil
    var sharedEditedEventOverrides: [String: PitchEvent] = [:]
    var onApplyEditedEventOverride: ((String, PitchEvent) -> Void)? = nil
    var sharedPitcherOverrides: [String: String] = [:]
    var onApplyPitcherOverride: (([String], String) -> Void)? = nil
    var sharedBatterJerseyOverrides: [String: String] = [:]
    var onApplyBatterJerseyOverride: (([String], String) -> Void)? = nil
    var initialJerseyFilter: String? = nil
    var initialSelectedEventID: String? = nil
    var shouldAutoOpenEditOutcome: Bool = false
    var showTopControls: Bool = true
    var onGearTapOverride: (() -> Void)? = nil
    var controlButtonsOffsetY: CGFloat = -30
    var controlButtonsVerticalPadding: CGFloat = 2
    var showInlineTabs: Bool = false
    var isCardsTabSelected: Bool = true
    var onSelectProgressTab: (() -> Void)? = nil
    var onSelectCardsTab: (() -> Void)? = nil
    var currentCountSeed: (balls: Int, strikes: Int)? = nil
    var onCountChanged: ((Int, Int) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionManager: PitchSessionManager

    @State private var isSelecting = false
    @State private var selectedEventIDs: Set<String> = Set<String>()
    @State private var showPitcherPicker = false
    @State private var showBatterPicker = false
    @State private var localTemplateOverrides: [String: String] = [:]
    @State private var localEditedEventOverrides: [String: PitchEvent] = [:]
    @State private var localPitcherOverrides: [String: String] = [:]
    @State private var localBatterJerseyOverrides: [String: String] = [:]
    @State private var pendingPitcherSelection: Pitcher? = nil
    @State private var pendingBatterSelection: String? = nil
    @State private var showEditPitchSheet = false
    @State private var showDeleteConfirm = false
    @State private var editTargetEvent: PitchEvent? = nil
    @State private var editIsStrikeSwinging = false
    @State private var editIsStrikeLooking = false
    @State private var editIsWildPitch = false
    @State private var editIsPassedBall = false
    @State private var editIsBall = false
    @State private var editSelectedOutcome: String? = nil
    @State private var editSelectedDescriptor: String? = nil
    @State private var editIsError = false
    @State private var localDeletedEventIDs: Set<String> = Set<String>()
    @State private var didApplyInitialEditTarget: Bool = false
    
    @State private var pitcherFilter: String = ""
    @State private var jerseyFilter: String = ""
    @State private var pitchFilter: String = ""
    @State private var didApplyInitialJerseyFilter = false
    @State private var showFilterSheet = false

    private var pitcherNameById: [String: String] {
        var map: [String: String] = [:]
        for pitcher in pitchers {
            if let id = pitcher.id {
                map[id] = pitcher.name
            }
        }
        return map
    }

    private var availableJerseyNumbers: [String] {
        let nums = allEvents.compactMap { $0.opponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let unique = Set(nums)
        return unique.sorted { lhs, rhs in
            // Sort numerically when possible, else lexicographically
            if let li = Int(lhs), let ri = Int(rhs) { return li < ri }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }
    
    private var availablePitchTypes: [String] {
        let types = allEvents
            .map { $0.pitch.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let unique = Set(types)
        return unique.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private var availablePitchers: [(id: String, name: String)] {
        let ids = Set(
            allEvents.compactMap { event -> String? in
                guard event.mode == .game else { return nil }
                guard let id = event.pitcherId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return nil }
                return id
            }
        )
        return ids
            .map { id in (id: id, name: pitcherNameById[id] ?? "Unknown Pitcher") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private var pitchTypeSuccessPercent: [String: Int] {
        // Compute overall success rate per called pitch type, mirroring PitchCardView's overallSuccessRate logic
        let withCalls = allEvents.compactMap { evt -> (String, PitchEvent)? in
            guard let call = evt.calledPitch else { return nil }
            return (call.pitch, evt)
        }
        let grouped = Dictionary(grouping: withCalls, by: { $0.0 })
        var result: [String: Int] = [:]
        for (pitchType, pairs) in grouped {
            let total = pairs.count
            // Success uses the same isLocationMatch/isFullySuccessful heuristic used in PitchResultCard
            let successes = pairs.filter { strictIsLocationMatch($0.1) }.count
            let pct = statPercent(successes, of: total)
            result[pitchType] = pct
        }
        return result
    }

    @ViewBuilder
    private func selectionActionButton(
        _ title: String,
        tint: Color = .blue,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .foregroundStyle(disabled ? Color.secondary : tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            disabled ? Color.black.opacity(0.12) : tint.opacity(0.55),
                            lineWidth: disabled ? 1 : 1.6
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var selectionActionColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 120), spacing: 10),
            GridItem(.flexible(minimum: 120), spacing: 10)
        ]
    }

    @ViewBuilder
    private func inlineTabButton(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(isSelected ? .black : .black.opacity(0.4))
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(isSelected ? .ultraThickMaterial : .ultraThinMaterial)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var filteredEvents: [PitchEvent] {
        // Start with all events and scope to current mode
        let modeScoped: [PitchEvent] = allEvents.filter { evt in
            return evt.mode == sessionManager.currentMode
        }

        // Apply pitcher filter in game mode if provided
        let trimmedPitcher = pitcherFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let pitcherScoped: [PitchEvent] = {
            if sessionManager.currentMode != .game || trimmedPitcher.isEmpty { return modeScoped }
            return modeScoped.filter { event in
                guard let id = event.pitcherId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return false }
                return id == trimmedPitcher
            }
        }()

        // Apply jersey filter if provided (trimmed and case-insensitive)
        let trimmedJersey = jerseyFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let jerseyScoped: [PitchEvent] = {
            if trimmedJersey.isEmpty { return pitcherScoped }
            return pitcherScoped.filter { evt in
                guard let jersey = evt.opponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines), !jersey.isEmpty else { return false }
                return jersey.caseInsensitiveCompare(trimmedJersey) == .orderedSame
            }
        }()

        // Apply pitch type filter if provided (trimmed and case-insensitive)
        let trimmedPitch = pitchFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let pitchScoped: [PitchEvent] = {
            if trimmedPitch.isEmpty { return jerseyScoped }
            return jerseyScoped.filter { evt in
                evt.pitch.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(trimmedPitch) == .orderedSame
            }
        }()

        // Sort newest first
        let visible = pitchScoped.filter { event in
            guard let eid = event.id else { return true }
            return !localDeletedEventIDs.contains(eid) && !sharedDeletedEventIDs.contains(eid)
        }
        return visible.sorted { (lhs: PitchEvent, rhs: PitchEvent) -> Bool in
            return lhs.timestamp > rhs.timestamp
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                
                if showTopControls {
                    HStack {
                        if isSelecting {
                            LazyVGrid(columns: selectionActionColumns, spacing: 10) {
                                selectionActionButton("Done", tint: .black) {
                                    applyPendingSelectionChangesAndPersist()
                                }

                                selectionActionButton(
                                    "Change Pitcher",
                                    disabled: selectedEventIDs.isEmpty || !isSelecting
                                ) {
                                    withAnimation(.easeInOut) {
                                        showPitcherPicker = true
                                    }
                                }

                                selectionActionButton(
                                    "Change Batter",
                                    disabled: selectedEventIDs.isEmpty || !isSelecting
                                ) {
                                    withAnimation(.easeInOut) {
                                        showBatterPicker = true
                                    }
                                }

                                selectionActionButton(
                                    "Edit Outcome",
                                    disabled: selectedEventIDs.count != 1 || !isSelecting
                                ) {
                                    prepareEditForSelectedEvent()
                                }

                                selectionActionButton(
                                    "Delete Pitch",
                                    tint: .red,
                                    disabled: selectedEventIDs.isEmpty || !isSelecting
                                ) {
                                    showDeleteConfirm = true
                                }
                            }
                            .padding(.horizontal, 4)
                        } else {
                            if showInlineTabs {
                                HStack(spacing: 6) {
                                    inlineTabButton(
                                        title: "Progress",
                                        systemImage: "chart.bar.xaxis",
                                        isSelected: !isCardsTabSelected
                                    ) {
                                        onSelectProgressTab?()
                                    }
                                    inlineTabButton(
                                        title: "Cards",
                                        systemImage: "square.grid.2x2",
                                        isSelected: isCardsTabSelected
                                    ) {
                                        onSelectCardsTab?()
                                    }
                                }
                                Spacer(minLength: 0)

                                Button {
                                    if let onGearTapOverride {
                                        onGearTapOverride()
                                    } else {
                                        withAnimation(.easeInOut) {
                                            isSelecting = true
                                        }
                                    }
                                } label: {
                                    Image(systemName: "gearshape")
                                        .font(.system(size: 22, weight: .medium))
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                                .transition(.scale.combined(with: .opacity))
                                .offset(y: controlButtonsOffsetY - 12)
                            } else {
                                Button {
                                    if let onGearTapOverride {
                                        onGearTapOverride()
                                    } else {
                                        withAnimation(.easeInOut) {
                                            isSelecting = true
                                        }
                                    }
                                } label: {
                                    Image(systemName: "gearshape")
                                        .font(.system(size: 22, weight: .medium))
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                                .transition(.scale.combined(with: .opacity))
                                .offset(y: controlButtonsOffsetY - 12)

                                Spacer(minLength: 0)
                            }

                            // One button that opens a real, scrollable filter sheet.
                            //
                            // This used to be a SwiftUI `Menu`. A Menu renders as a transient UIMenu
                            // whose contents are regenerated whenever the parent view re-renders, and
                            // this sheet re-renders constantly (Firestore listeners, animations). That
                            // reset the menu's internal scroll offset mid-drag, so a long pitcher or
                            // jersey list was effectively impossible to scroll.
                            Button {
                                showFilterSheet = true
                            } label: {
                                let hasActiveFilters = !pitcherFilter.isEmpty || !jerseyFilter.isEmpty || !pitchFilter.isEmpty
                                Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                    .foregroundStyle(hasActiveFilters ? Color.blue : .primary)
                                    .shadow(color: hasActiveFilters ? Color.blue.opacity(0.35) : .clear, radius: hasActiveFilters ? 6 : 0)
                                    .font(.system(size: 22, weight: .medium))
                                    .padding(6)
                                    .clipShape(Capsule())
                                    .compositingGroup()
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Filter pitches")
                            .offset(y: controlButtonsOffsetY - 12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .background {
                        if isSelecting {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, controlButtonsVerticalPadding)
                }

                ScrollView(.vertical) {
                    VStack(spacing: 12) {
                        ForEach(filteredEvents, id: \.identity) { event in
                            EventRowView(
                                event: event,
                                allEvents: allEvents,
                                games: games,
                                templates: templates,
                                pitcherNameById: pitcherNameById,
                                isSelecting: $isSelecting,
                                selectedEventIDs: $selectedEventIDs,
                                localTemplateOverrides: localTemplateOverrides,
                                localEditedEventOverrides: localEditedEventOverrides,
                                sharedEditedEventOverrides: sharedEditedEventOverrides,
                                localPitcherOverrides: localPitcherOverrides,
                                sharedPitcherOverrides: sharedPitcherOverrides,
                                localBatterJerseyOverrides: localBatterJerseyOverrides,
                                sharedBatterJerseyOverrides: sharedBatterJerseyOverrides,
                                isParticipant: isParticipant,
                                selectedPlayerName: selectedPlayerName
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
                .padding(.top, -2)
            }
        }
        .padding(.horizontal, 10)
        .onAppear {
            applyInitialEditTargetIfNeeded()
        }
        .sheet(isPresented: $showFilterSheet) {
            filterSheetView
        }
        .appConfirmationDialog(
            isPresented: $showDeleteConfirm,
            title: "Delete Selected Pitch Event\(selectedEventIDs.count == 1 ? "" : "s")?",
            message: "This removes the selected pitch event\(selectedEventIDs.count == 1 ? "" : "s") from the cards list.",
            primaryTitle: "Delete",
            primaryRole: .destructive,
            primaryAction: {
                deleteSelectedEvents()
            },
            secondaryTitle: "Cancel"
        )
        .sheet(isPresented: $showPitcherPicker) {
            NavigationView {
                List(pitchers) { pitcher in
                    Button(pitcher.name) {
                        applySelectedPitcherImmediately(pitcher)
                        showPitcherPicker = false
                    }
                }
                .navigationTitle("Select Pitcher")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showPitcherPicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
            .fixedAppDynamicType()
        }
        .sheet(isPresented: $showBatterPicker) {
            NavigationView {
                List(availableJerseyNumbers, id: \.self) { jersey in
                    Button("#\(jersey)") {
                        applySelectedBatterImmediately(jersey)
                        showBatterPicker = false
                    }
                }
                .navigationTitle("Select Batter")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showBatterPicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
            .fixedAppDynamicType()
        }
        .sheet(isPresented: $showEditPitchSheet) {
            if let target = editTargetEvent {
                PitchResultSheetView(
                    isPresented: $showEditPitchSheet,
                    isStrikeSwinging: $editIsStrikeSwinging,
                    isStrikeLooking: $editIsStrikeLooking,
                    isWildPitch: $editIsWildPitch,
                    isPassedBall: $editIsPassedBall,
                    isBall: $editIsBall,
                    selectedOutcome: $editSelectedOutcome,
                    selectedDescriptor: $editSelectedDescriptor,
                    isError: $editIsError,
                    pendingResultLabel: target.location,
                    pitchCall: target.calledPitch ?? PitchCall(
                        pitch: target.pitch,
                        location: target.location,
                        isStrike: target.isStrike,
                        codes: target.codes
                    ),
                    basesBefore: target.basesBefore ?? .empty,
                    catcherEstimate: target.catcherEstimate,
                    batterSide: target.batterSide,
                    selectedTemplateId: target.templateId,
                    currentMode: target.mode,
                    selectedGameId: target.gameId,
                    selectedOpponentJersey: target.opponentJersey,
                    selectedOpponentBatterId: target.opponentBatterId,
                    allPitchEvents: allEvents,
                    suggestedCountSeed: nil,
                    currentCountSeed: currentCountSeed,
                    countSeedOverride: PitchEventEdit.countBefore(target, in: allEvents),
                    onCountChanged: { balls, strikes in
                        // Only the latest pitch's count is the tracker's.
                        guard PitchEventEdit.editMovesTrackerCount(target, in: allEvents) else { return }
                        onCountChanged?(balls, strikes)
                    },
                    lineupBatters: [],
                    selectedPitcherId: target.pitcherId,
                    saveAction: { edited in
                        saveEditedEvent(edited, original: target)
                    },
                    template: nil,
                    pitcherName: selectedPlayerName,
                    initialFieldingOuts: target.fieldingOuts,
                    initialErrorPositions: target.errorPositions,
                    savedPlay: target.play
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .fixedAppDynamicType()
            }
        }
        .onAppear {
            applyInitialJerseyFilterIfNeeded()
        }
    }

    private func applyInitialJerseyFilterIfNeeded() {
        guard !didApplyInitialJerseyFilter else { return }
        let initial = (initialJerseyFilter ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !initial.isEmpty else { return }
        if jerseyFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            jerseyFilter = initial
        }
        didApplyInitialJerseyFilter = true
    }
    
    private func applyPendingSelectionChangesAndPersist() {
        guard let uid = Auth.auth().currentUser?.uid else {
            pendingPitcherSelection = nil
            pendingBatterSelection = nil
            selectedEventIDs.removeAll()
            isSelecting = false
            return
        }

        let selectedEvents = allEvents.filter { event in
            guard let eid = event.id else { return false }
            return selectedEventIDs.contains(eid)
        }

        guard !selectedEvents.isEmpty else {
            pendingPitcherSelection = nil
            pendingBatterSelection = nil
            selectedEventIDs.removeAll()
            isSelecting = false
            return
        }

        var updateData: [String: Any] = [:]
        if let pitcherId = pendingPitcherSelection?.id {
            updateData["pitcherId"] = pitcherId
        }
        if let jersey = pendingBatterSelection?.trimmingCharacters(in: .whitespacesAndNewlines), !jersey.isEmpty {
            updateData["opponentJersey"] = jersey
        }

        // Nothing to apply: just exit selection mode.
        guard !updateData.isEmpty else {
            pendingPitcherSelection = nil
            pendingBatterSelection = nil
            selectedEventIDs.removeAll()
            isSelecting = false
            return
        }

        // Planned before the overrides below change what the cards show.
        let writes = selectionChangeWrites(
            for: selectedEvents,
            newPitcherId: updateData["pitcherId"] as? String,
            jersey: updateData["opponentJersey"] as? String,
            uid: uid
        )

        // Optimistically close selection UI so Done always feels responsive.
        let selectedEventIdsSnapshot = selectedEvents.compactMap(\.id)
        if let jersey = updateData["opponentJersey"] as? String, !jersey.isEmpty {
            for eid in selectedEventIdsSnapshot {
                localBatterJerseyOverrides[eid] = jersey
            }
            onApplyBatterJerseyOverride?(selectedEventIdsSnapshot, jersey)
        }
        if let pitcherId = updateData["pitcherId"] as? String, !pitcherId.isEmpty {
            for eid in selectedEventIdsSnapshot {
                localPitcherOverrides[eid] = pitcherId
            }
            onApplyPitcherOverride?(selectedEventIdsSnapshot, pitcherId)
        }
        pendingPitcherSelection = nil
        pendingBatterSelection = nil
        selectedEventIDs.removeAll()
        isSelecting = false

        sendEventCopies(writes, label: "applyPendingSelectionChangesAndPersist")
    }

    private func applySelectedBatterImmediately(_ jersey: String) {
        let trimmed = jersey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let selectedEvents = allEvents.filter { event in
            guard let eid = event.id else { return false }
            return selectedEventIDs.contains(eid)
        }
        let selectedIds = selectedEvents.compactMap(\.id)
        guard !selectedIds.isEmpty else {
            // Keep pending behavior if no cards are selected yet.
            pendingBatterSelection = trimmed
            return
        }

        let uid = Auth.auth().currentUser?.uid
        let writes = uid.map { selectionChangeWrites(for: selectedEvents, newPitcherId: nil, jersey: trimmed, uid: $0) } ?? []

        // Immediate visual feedback in-card.
        for eid in selectedIds {
            localBatterJerseyOverrides[eid] = trimmed
        }
        onApplyBatterJerseyOverride?(selectedIds, trimmed)

        // Persist immediately so the change survives sheet/game close.
        guard uid != nil else { return }
        sendEventCopies(writes, label: "applySelectedBatterImmediately")

        // Clear pending since this change is already applied/persisted.
        pendingBatterSelection = nil
    }

    private func applySelectedPitcherImmediately(_ pitcher: Pitcher) {
        guard let pitcherId = pitcher.id?.trimmingCharacters(in: .whitespacesAndNewlines), !pitcherId.isEmpty else { return }

        let selectedEvents = allEvents.filter { event in
            guard let eid = event.id else { return false }
            return selectedEventIDs.contains(eid)
        }
        let selectedIds = selectedEvents.compactMap(\.id)
        guard !selectedIds.isEmpty else {
            pendingPitcherSelection = pitcher
            return
        }

        let uid = Auth.auth().currentUser?.uid
        let writes = uid.map { selectionChangeWrites(for: selectedEvents, newPitcherId: pitcherId, jersey: nil, uid: $0) } ?? []

        for eid in selectedIds {
            localPitcherOverrides[eid] = pitcherId
        }
        onApplyPitcherOverride?(selectedIds, pitcherId)

        guard uid != nil else { return }
        sendEventCopies(writes, label: "applySelectedPitcherImmediately")

        pendingPitcherSelection = nil
    }

    /// The pitch as the cards currently show it - a local edit, pitcher or
    /// batter change that hasn't come back from Firestore yet included.
    private func currentState(of event: PitchEvent) -> PitchEvent {
        guard let eid = event.id else { return event }
        var current = localEditedEventOverrides[eid] ?? event
        if let pitcherId = localPitcherOverrides[eid] { current.pitcherId = pitcherId }
        if let jersey = localBatterJerseyOverrides[eid], jersey != current.opponentJersey {
            current.opponentJersey = jersey
            current.opponentBatterId = nil
            current.hitterId = nil
        }
        return current
    }

    /// Every stored copy of a pitch (EventCopyTargets), including the
    /// pitcher's and hitter's own records.
    private func eventCopyTargets(for event: PitchEvent, currentUid: String) -> EventCopyTargets? {
        let current = currentState(of: event)
        return EventCopyTargets.of(
            eventId: current.id,
            isGame: current.mode == .game,
            gameId: current.gameId,
            gameOwnerUid: gameOwnerUserId,
            liveId: liveGameId,
            createdByUid: current.createdByUid,
            currentUid: currentUid,
            pitcherId: current.pitcherId,
            hitterId: current.hitterId
        )
    }

    private func selectionChangeWrites(for events: [PitchEvent], newPitcherId: String?, jersey: String?, uid: String) -> [EventCopyWrite] {
        events.flatMap { event -> [EventCopyWrite] in
            let current = currentState(of: event)
            guard let eid = current.id,
                  let targets = eventCopyTargets(for: event, currentUid: uid),
                  let data = try? Firestore.Encoder().encode(current)
            else { return [] }
            return EventCopyPlan.selectionChange(data, eventId: eid, targets: targets,
                                                 newPitcherId: newPitcherId, jersey: jersey, writerUid: uid)
        }
    }

    /// Sends each write to its copy as its own request.
    ///
    /// These used to go out as a single `WriteBatch`. A batch is atomic, and a
    /// participant has *create-only* access to
    /// users/{owner}/games/{gid}/pitchEvents (see firestore.rules) - so the
    /// denied owner-copy write took the permitted /liveGames write down with
    /// it and the edit landed nowhere, while the optimistic UI above had
    /// already shown it as applied. Sending the copies independently lets each
    /// one succeed on its own merits; the owner's device then mirrors the
    /// /liveGames change into its own copy.
    private func sendEventCopies(_ writes: [EventCopyWrite], label: String) {
        EventCopyWriter.send(writes, label: label, perform: EventCopyWriter.firestore, log: { debugLog($0) })
    }

    private func deleteSelectedEvents() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let selectedEvents = allEvents.filter { event in
            guard let eid = event.id else { return false }
            return selectedEventIDs.contains(eid)
        }
        guard !selectedEvents.isEmpty else { return }

        // Planned before the cleanup below forgets the cards' local changes.
        let writes = selectedEvents
            .compactMap { eventCopyTargets(for: $0, currentUid: uid) }
            .flatMap { EventCopyPlan.delete(targets: $0) }

        let selectedIds = Set(selectedEvents.compactMap(\.id))
        // Optimistic UI cleanup.
        localDeletedEventIDs.formUnion(selectedIds)
        onDeleteEventIDs?(selectedIds)
        selectedEventIDs.removeAll()
        pendingPitcherSelection = nil
        pendingBatterSelection = nil
        isSelecting = false
        localBatterJerseyOverrides = localBatterJerseyOverrides.filter { !selectedIds.contains($0.key) }
        localPitcherOverrides = localPitcherOverrides.filter { !selectedIds.contains($0.key) }
        localEditedEventOverrides = localEditedEventOverrides.filter { !selectedIds.contains($0.key) }

        sendEventCopies(writes, label: "deleteSelectedEvents")
    }

    private func prepareEditForSelectedEvent() {
        guard selectedEventIDs.count == 1,
              let selectedId = selectedEventIDs.first,
              let event = allEvents.first(where: { $0.id == selectedId }) else {
            return
        }
        editTargetEvent = event
        editIsStrikeSwinging = event.strikeSwinging
        editIsStrikeLooking = event.strikeLooking
        editIsWildPitch = event.wildPitch
        editIsPassedBall = event.passedBall
        editIsBall = event.isBall ?? false
        editSelectedOutcome = event.outcome
        editSelectedDescriptor = event.descriptor
        editIsError = event.errorOnPlay
        showEditPitchSheet = true
    }

    /// Filter picker, presented as a sheet with a real `List`.
    ///
    /// A `List` keeps its scroll offset across body updates, unlike the `Menu`
    /// this replaced, whose contents were rebuilt from scratch every time the
    /// parent re-rendered.
    @ViewBuilder
    private var filterSheetView: some View {
        NavigationStack {
            List {
                if sessionManager.currentMode == .game {
                    Section("Pitcher") {
                        filterRow(title: "All Pitchers", isSelected: pitcherFilter.isEmpty) {
                            pitcherFilter = ""
                        }
                        ForEach(availablePitchers, id: \.id) { pitcher in
                            filterRow(title: pitcher.name, isSelected: pitcherFilter == pitcher.id) {
                                pitcherFilter = (pitcherFilter == pitcher.id) ? "" : pitcher.id
                            }
                        }
                    }

                    Section("Batter") {
                        filterRow(title: "All Batters", isSelected: jerseyFilter.isEmpty) {
                            jerseyFilter = ""
                        }
                        ForEach(availableJerseyNumbers, id: \.self) { num in
                            filterRow(title: "#\(num)", isSelected: jerseyFilter == num) {
                                jerseyFilter = (jerseyFilter == num) ? "" : num
                            }
                        }
                    }
                }

                Section("Pitch Type") {
                    filterRow(title: "All Pitches", isSelected: pitchFilter.isEmpty) {
                        pitchFilter = ""
                    }
                    ForEach(availablePitchTypes, id: \.self) { type in
                        let pct = pitchTypeSuccessPercent[type]
                        let label = (type == "Catcher")
                            ? type
                            : (pct != nil ? "\(type) (\(pct!)%)" : type)
                        filterRow(title: label, isSelected: pitchFilter == type) {
                            pitchFilter = (pitchFilter == type) ? "" : type
                        }
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear All") {
                        pitcherFilter = ""
                        jerseyFilter = ""
                        pitchFilter = ""
                    }
                    .disabled(pitcherFilter.isEmpty && jerseyFilter.isEmpty && pitchFilter.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showFilterSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .fixedAppDynamicType()
    }

    private func filterRow(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func applyInitialEditTargetIfNeeded() {
        guard !didApplyInitialEditTarget else { return }
        didApplyInitialEditTarget = true
        guard let targetId = initialSelectedEventID else { return }
        guard allEvents.contains(where: { $0.id == targetId }) else { return }

        selectedEventIDs = [targetId]
        isSelecting = true

        guard shouldAutoOpenEditOutcome else { return }
        DispatchQueue.main.async {
            prepareEditForSelectedEvent()
        }
    }

    private func saveEditedEvent(_ edited: PitchEvent, original: PitchEvent) {
        guard let uid = Auth.auth().currentUser?.uid,
              let originalId = original.id else { return }

        // Only what the sheet answers changes (PitchEventEdit).
        var updated = PitchEventEdit.applying(edited, to: original)
        updated.id = originalId
        localEditedEventOverrides[originalId] = updated
        onApplyEditedEventOverride?(originalId, updated)

        do {
            var data = try Firestore.Encoder().encode(updated)
            // Keep owner provenance stable for future cross-device edits.
            if let createdBy = updated.createdByUid, !createdBy.isEmpty {
                data["createdByUid"] = createdBy
            }

            if let targets = eventCopyTargets(for: original, currentUid: uid) {
                sendEventCopies(EventCopyPlan.edit(data, targets: targets, writerUid: uid), label: "saveEditedEvent")
            }
            selectedEventIDs.removeAll()
            isSelecting = false
        } catch {
            debugLog("❌ saveEditedEvent encode failed: \(error)")
        }
    }
    
    private struct EventRowView: View {
        let event: PitchEvent
        let allEvents: [PitchEvent]
        let games: [Game]
        let templates: [PitchTemplate]
        let pitcherNameById: [String: String]

        @Binding var isSelecting: Bool
        @Binding var selectedEventIDs: Set<String>

        let localTemplateOverrides: [String: String]
        let localEditedEventOverrides: [String: PitchEvent]
        let sharedEditedEventOverrides: [String: PitchEvent]
        let localPitcherOverrides: [String: String]
        let sharedPitcherOverrides: [String: String]
        let localBatterJerseyOverrides: [String: String]
        let sharedBatterJerseyOverrides: [String: String]
        let isParticipant: Bool   // <-- add this
        let selectedPlayerName: String

        var body: some View {
            // Compute ids and effective template id outside of ViewBuilder statements that produce views
            let eventId: String = event.id ?? "<nil>"
            let baseEvent: PitchEvent = {
                guard let eid = event.id else { return event }
                return localEditedEventOverrides[eid] ?? sharedEditedEventOverrides[eid] ?? event
            }()
            let effectiveTemplateId: String? = (event.id.flatMap { localTemplateOverrides[$0] }) ?? baseEvent.templateId
            let effectiveEvent: PitchEvent = {
                guard let eid = event.id else { return baseEvent }
                var overridden = baseEvent
                if let jersey = (localBatterJerseyOverrides[eid] ?? sharedBatterJerseyOverrides[eid])?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !jersey.isEmpty {
                    overridden.opponentJersey = jersey
                    overridden.opponentBatterId = nil
                }
                if let pitcherId = (localPitcherOverrides[eid] ?? sharedPitcherOverrides[eid])?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !pitcherId.isEmpty {
                    overridden.pitcherId = pitcherId
                }
                return overridden
            }()

            // Log rendering for debugging
            let fallbackTemplateName = templates.first?.name ?? "Template"
            let templateName: String = templates.first(where: { $0.id.uuidString == effectiveTemplateId })?.name ?? fallbackTemplateName
            debugLog("UI: Rendering card for eventId=\(eventId), effectiveTemplateId=\(effectiveTemplateId ?? "<nil>"), templateName=\(templateName)")

            // Create a simple Binding for selection state
            let isSelectedBinding: Binding<Bool> = Binding<Bool>(
                get: {
                    if event.id == nil { return false }
                    return selectedEventIDs.contains(eventId)
                },
                set: { newValue in
                    if event.id == nil {
                        debugLog("UI: Attempted to toggle selection for event with nil id")
                        return
                    }
                    if newValue {
                        selectedEventIDs.insert(eventId)
                        debugLog("UI: Selected eventId=\(eventId). Now selectedEventIDs=\(Array(selectedEventIDs))")
                    } else {
                        selectedEventIDs.remove(eventId)
                        debugLog("UI: Deselected eventId=\(eventId). Now selectedEventIDs=\(Array(selectedEventIDs))")
                    }
                }
            )

            let pitcherNameForEvent: String = {
                if let pid = effectiveEvent.pitcherId,
                   let name = pitcherNameById[pid],
                   !name.isEmpty {
                    return name
                }
                return selectedPlayerName
            }()

            return PitchResultCard(
                event: effectiveEvent,
                allEvents: allEvents,
                games: games,
                templateName: templateName,
                selectedPlayerName: pitcherNameForEvent,
                isSelecting: $isSelecting,
                isSelected: isSelectedBinding,
                isParticipant: isParticipant
            )
        }
    }
}

struct PitchEvent: Codable, Identifiable {
    @DocumentID var id: String? // Firestore will auto-assign this
    let timestamp: Date
    var pitch: String
    var location: String
    var codes: [String]
    var isStrike: Bool
    var isBall: Bool?          // Changed from 'var isBall: Bool = false' to optional Bool
    let mode: PitchMode
    var calledPitch: PitchCall?
    var batterSide: BatterSide
    var templateId: String?
    var strikeSwinging: Bool
    var wildPitch: Bool
    var passedBall: Bool
    
    var strikeLooking: Bool

    var outcome: String?
    var descriptor: String?
    var errorOnPlay: Bool

    var battedBallRegion: String?
    var battedBallType: String?
    var battedBallTapX: Double?
    var battedBallTapY: Double?
    
    var gameId: String?
    var opponentJersey: String?
    var opponentBatterId: String?
    var pitcherId: String?
    // The linked roster Hitter this pitch was thrown to, when the batter
    // was selected via the roster picker (PitchTrackerView's
    // batterRosterPickerButton) rather than jersey-only. Independent of
    // opponentJersey/opponentBatterId above - both can be set at once, or
    // just the jersey fields when no roster link was made.
    var hitterId: String?

    var createdByUid: String?

    var strikeSwingingMarker: String? = nil
    var strikeLookingMarker: String? = nil
    var ballMarker: String? = nil
    var foulMarker: String? = nil
    var atBatBalls: Int? = nil
    var atBatStrikes: Int? = nil
    var atBatCount: String? = nil
    var trackingMode: TrackingMode? = .coach

    /// The coach's after-the-fact guess at what the opposing catcher actually
    /// called (pitch type + location), for Catcher-mode pitches only. Distinct
    /// from `calledPitch`, which for Catcher-mode events just mirrors the
    /// observed result location (see `CatcherEstimateView`).
    var catcherEstimate: PitchCall? = nil

    /// Where the batter ended up on a ball in play and what they're credited
    /// with (BaseRunnerRules.swift). Optional: absent on every event saved
    /// before it existed and on anything that isn't a ball in play. Rebuild
    /// sites carry it through `BaseRunnerRules.playIfConsistent`.
    var play: BasePlay? = nil

    /// Who was on base when this pitch was thrown. Stamped on every game
    /// pitch so undo can put the runners back exactly, and so `play` can be
    /// replayed against the bases it was recorded over. Optional for the
    /// same reason as `play`.
    var basesBefore: BaseOccupancy? = nil

    /// Who fielded the play's outs and errors, and who was playing where
    /// (FieldingPlay.swift). Optional: absent before 2026-11-03 and on any
    /// pitch nobody answered them for.
    var fieldingOuts: [FieldingOut]? = nil
    var errorPositions: [String]? = nil
    var defense: [DefenseSlot]? = nil
    /// The team in the field, so a team's fielding includes positions
    /// nobody on its lineup held.
    var fieldingTeamId: String? = nil
}

extension PitchEvent: Hashable {
    static func == (lhs: PitchEvent, rhs: PitchEvent) -> Bool {
        // Prefer Firestore id when available; else fall back to timestamp and pitch/location for stability
        if let l = lhs.id, let r = rhs.id { return l == r }
        return lhs.timestamp == rhs.timestamp && lhs.pitch == rhs.pitch && lhs.location == rhs.location
    }
    func hash(into hasher: inout Hasher) {
        if let id = id {
            hasher.combine(id)
        } else {
            hasher.combine(timestamp.timeIntervalSince1970)
            hasher.combine(pitch)
            hasher.combine(location)
        }
    }
}

extension PitchEvent {
    // Stable identity for UI lists even when Firestore id is nil
    var identity: String {
        if let id = self.id, !id.isEmpty { return id }
        return "\(timestamp.timeIntervalSince1970)-\(pitch)-\(location)"
    }
}

enum PitchMode: String, Codable {
    case game
    case scout
}

struct PitchCall: Codable {
    let pitch: String
    let location: String
    let isStrike: Bool
    let codes: [String]  // ✅ Use array instead of single code
    
    var type: String {
        isStrike ? "Strike" : "Ball"
    }
}

func summarizeOverallSuccess(events: [PitchEvent]) -> [String: Int] {
    let grouped = Dictionary(grouping: events.compactMap { event -> (String, PitchEvent)? in
        guard let call = event.calledPitch else { return nil }
        return (call.pitch, event)
    }, by: { $0.0 })
    
    var result: [String: Int] = [:]
    
    for (pitchType, pairs) in grouped {
        let total = pairs.count
        let successes = pairs.filter { isFullySuccessful($0.1) }.count
        let percentage = statPercent(successes, of: total)
        result[pitchType] = percentage
    }
    
    return result
}

extension PitchCall {
    var displayTitle: String { "\(type) \(location)" } // location will now already be "Up & In" style
    var shortLabel: String { "\(pitch) — \(displayTitle)" }
}

extension PitchEvent {
    static func decodeFirestoreDocument(_ doc: QueryDocumentSnapshot) -> PitchEvent? {
        do {
            return try doc.data(as: PitchEvent.self)
        } catch {
            if let fallback = PitchEvent(legacyData: doc.data(), documentId: doc.documentID) {
                debugLog("⚠️ PitchEvent legacy decode used docId=\(doc.documentID)")
                return fallback
            }
            debugLog("❌ PitchEvent decode failed docId=\(doc.documentID) error=\(error)")
            return nil
        }
    }

    init?(legacyData data: [String: Any], documentId: String?) {
        let resolvedTimestamp: Date
        if let ts = data["timestamp"] as? Timestamp {
            resolvedTimestamp = ts.dateValue()
        } else if let date = data["timestamp"] as? Date {
            resolvedTimestamp = date
        } else {
            return nil
        }

        guard let pitch = data["pitch"] as? String, !pitch.isEmpty,
              let location = data["location"] as? String, !location.isEmpty
        else { return nil }

        let codes: [String] = {
            if let arr = data["codes"] as? [String], !arr.isEmpty {
                return arr
            }
            if let single = data["code"] as? String, !single.isEmpty {
                return [single]
            }
            return []
        }()

        let isStrike = data["isStrike"] as? Bool ?? false
        let isBall = data["isBall"] as? Bool

        let mode: PitchMode = {
            if let raw = data["mode"] as? String, let parsed = PitchMode(rawValue: raw) {
                return parsed
            }
            return .game
        }()

        let calledPitch: PitchCall? = {
            guard let payload = data["calledPitch"] as? [String: Any] else { return nil }
            guard let cpPitch = payload["pitch"] as? String,
                  let cpLocation = payload["location"] as? String
            else { return nil }

            let cpCodes: [String] = {
                if let arr = payload["codes"] as? [String], !arr.isEmpty {
                    return arr
                }
                if let single = payload["code"] as? String, !single.isEmpty {
                    return [single]
                }
                return []
            }()

            return PitchCall(
                pitch: cpPitch,
                location: cpLocation,
                isStrike: payload["isStrike"] as? Bool ?? isStrike,
                codes: cpCodes
            )
        }()

        let batterSide: BatterSide = {
            if let raw = data["batterSide"] as? String, let parsed = BatterSide(rawValue: raw) {
                return parsed
            }
            return .right
        }()

        self.id = documentId
        self.timestamp = resolvedTimestamp
        self.pitch = pitch
        self.location = location
        self.codes = codes
        self.isStrike = isStrike
        self.isBall = isBall
        self.mode = mode
        self.calledPitch = calledPitch
        self.batterSide = batterSide
        self.templateId = data["templateId"] as? String
        self.strikeSwinging = data["strikeSwinging"] as? Bool ?? false
        self.wildPitch = data["wildPitch"] as? Bool ?? false
        self.passedBall = data["passedBall"] as? Bool ?? false
        self.strikeLooking = data["strikeLooking"] as? Bool ?? false
        self.outcome = data["outcome"] as? String
        self.descriptor = data["descriptor"] as? String
        self.errorOnPlay = data["errorOnPlay"] as? Bool ?? false
        self.battedBallRegion = data["battedBallRegion"] as? String
        self.battedBallType = data["battedBallType"] as? String
        self.battedBallTapX = data["battedBallTapX"] as? Double
        self.battedBallTapY = data["battedBallTapY"] as? Double
        self.gameId = data["gameId"] as? String
        self.opponentJersey = data["opponentJersey"] as? String
        self.opponentBatterId = data["opponentBatterId"] as? String
        self.pitcherId = data["pitcherId"] as? String
        self.hitterId = data["hitterId"] as? String
        self.createdByUid = data["createdByUid"] as? String
        if let rawTrackingMode = data["trackingMode"] as? String,
           let parsedTrackingMode = TrackingMode(rawValue: rawTrackingMode) {
            self.trackingMode = parsedTrackingMode
        } else {
            self.trackingMode = .coach
        }
        self.play = (data["play"] as? [String: Any]).flatMap {
            try? Firestore.Decoder().decode(BasePlay.self, from: $0)
        }
        self.basesBefore = (data["basesBefore"] as? [String: Any]).flatMap {
            try? Firestore.Decoder().decode(BaseOccupancy.self, from: $0)
        }
        self.fieldingOuts = (data["fieldingOuts"] as? [[String: Any]])?.compactMap {
            try? Firestore.Decoder().decode(FieldingOut.self, from: $0)
        }
        self.errorPositions = data["errorPositions"] as? [String]
        self.defense = (data["defense"] as? [[String: Any]])?.compactMap {
            try? Firestore.Decoder().decode(DefenseSlot.self, from: $0)
        }
        self.fieldingTeamId = data["fieldingTeamId"] as? String
        self.catcherEstimate = {
            guard let payload = data["catcherEstimate"] as? [String: Any] else { return nil }
            guard let cePitch = payload["pitch"] as? String,
                  let ceLocation = payload["location"] as? String
            else { return nil }

            let ceCodes: [String] = {
                if let arr = payload["codes"] as? [String], !arr.isEmpty {
                    return arr
                }
                if let single = payload["code"] as? String, !single.isEmpty {
                    return [single]
                }
                return []
            }()

            return PitchCall(
                pitch: cePitch,
                location: ceLocation,
                isStrike: payload["isStrike"] as? Bool ?? false,
                codes: ceCodes
            )
        }()
    }

    func logDebugPayload(prefix: String = "📤 Saving PitchEvent") {
        struct DebugEvent: Encodable {
            let id: String?
            let timestamp: Date
            let pitch: String
            let location: String
            let codes: [String]
            let isStrike: Bool
            let isBall: Bool?             // Changed from non-optional Bool to optional Bool
            let mode: PitchMode
            let calledPitch: PitchCall?
            let batterSide: BatterSide
            let templateId: String?
            let strikeSwinging: Bool
            let wildPitch: Bool
            let passedBall: Bool
            let strikeLooking: Bool
            let outcome: String?
            let descriptor: String?
            let errorOnPlay: Bool
            let battedBallRegion: String?
            let battedBallType: String?
            let battedBallTapX: Double?
            let battedBallTapY: Double?
            let gameId: String?
            let opponentJersey: String?
            let opponentBatterId: String?
            let pitcherId: String?
            let hitterId: String?
            let trackingMode: TrackingMode?
            let catcherEstimate: PitchCall?
            let play: BasePlay?
            let basesBefore: BaseOccupancy?
        }
        let debug = DebugEvent(
            id: self.id,
            timestamp: self.timestamp,
            pitch: self.pitch,
            location: self.location,
            codes: self.codes,
            isStrike: self.isStrike,
            isBall: self.isBall,
            mode: self.mode,
            calledPitch: self.calledPitch,
            batterSide: self.batterSide,
            templateId: self.templateId,
            strikeSwinging: self.strikeSwinging,
            wildPitch: self.wildPitch,
            passedBall: self.passedBall,
            strikeLooking: self.strikeLooking,
            outcome: self.outcome,
            descriptor: self.descriptor,
            errorOnPlay: self.errorOnPlay,
            battedBallRegion: self.battedBallRegion,
            battedBallType: self.battedBallType,
            battedBallTapX: self.battedBallTapX,
            battedBallTapY: self.battedBallTapY,
            gameId: self.gameId,
            opponentJersey: self.opponentJersey,
            opponentBatterId: self.opponentBatterId,
            pitcherId: self.pitcherId,
            hitterId: self.hitterId,
            trackingMode: self.trackingMode,
            catcherEstimate: self.catcherEstimate,
            play: self.play,
            basesBefore: self.basesBefore
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(debug), let json = String(data: data, encoding: .utf8) {
            debugLog("\(prefix):\n\(json)")
        } else {
            debugLog("\(prefix): <failed to encode>")
            debugLog(self)
        }
    }
}

extension PitchEvent {
    var isFoulInferred: Bool {
        let text = [outcome, descriptor].compactMap { $0?.lowercased() }.joined(separator: " ")
        return text.contains("foul")
    }
    var isHomeRunInferred: Bool {
        let text = [outcome, descriptor].compactMap { $0?.lowercased() }.joined(separator: " ")
        return text.contains("hr") || text.contains("home run") || text.contains("homerun")
    }

    var supportsLocationAnalytics: Bool {
        // Catcher-mode events set `calledPitch` to mirror the observed result
        // location (see CatcherEstimateView), so they'd trivially "hit spot"
        // 100% of the time - that's not a real call/execution comparison.
        // Their location data belongs in the Catcher Reads section instead.
        guard pitch.trimmingCharacters(in: .whitespacesAndNewlines) != "Catcher" else { return false }
        return (trackingMode ?? .coach) == .coach && calledPitch != nil && !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension EventCopyWriter {
    /// Sends one copy write to Firestore as its own request.
    static func firestore(_ write: EventCopyWrite, completion: @escaping (Error?) -> Void) {
        let ref = Firestore.firestore().document(write.path)
        switch write {
        case .set(_, let data): ref.setData(data, merge: false) { completion($0) }
        case .update(_, let data):
            let fields = data.mapValues { $0 is EventCopyFieldDelete ? FieldValue.delete() : $0 }
            ref.updateData(fields) { completion($0) }
        case .delete: ref.delete { completion($0) }
        }
    }
}
