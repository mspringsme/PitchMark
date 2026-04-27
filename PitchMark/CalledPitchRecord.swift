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
    if event.errorOnPlay { addUnique("Error on play") }
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
    if isFoulOutcome {
        let marker = event.foulMarker?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let marker, !marker.isEmpty {
            addUnique("\(marker) Foul", sanitizeText: false)
        } else {
            addUnique(event.outcome, sanitizeText: true)
        }
    } else {
        addUnique(event.outcome, sanitizeText: true)
    }
    addUnique(event.descriptor, sanitizeText: true)

    // Batted ball details — show only the region label in cards (ignore type)
    let regionLower = (event.battedBallRegion ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let existingCombined = lines.map { $0.lowercased() }.joined(separator: " \n ")

    func alreadyRepresentsRegion(_ region: String) -> Bool {
        return !region.isEmpty && existingCombined.contains(region)
    }

    if let region = event.battedBallRegion?.trimmingCharacters(in: .whitespacesAndNewlines), !region.isEmpty {
        if !alreadyRepresentsRegion(regionLower) {
            // Do NOT sanitize constructed lines; keep user-facing label intact
            addUnique(region, sanitizeText: false)
        }
    }

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

    init(lines: [String], jerseyNumber: String?, countText: String? = nil, minHeight: CGFloat? = 118) {
        self.lines = lines
        self.jerseyNumber = jerseyNumber
        self.countText = countText
        self.minHeight = minHeight
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
            if let num = jerseyNumber, !num.isEmpty {
                HStack {
                    Text(num)
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, num.count > 1 ? 6 : 0)
                        .frame(width: num.count > 1 ? nil : 18, height: 18)
                        .background(
                            Group {
                                if num.count > 1 {
                                    Capsule().fill(Color.blue)
                                } else {
                                    Circle().fill(Color.blue)
                                }
                            }
                        )
                    if let countText, !countText.isEmpty {
                        Text(countText)
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(.black.opacity(0.75))
                            .lineLimit(1)
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
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.black)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(minWidth: 92, maxWidth: 132, minHeight: minHeight, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(OutcomeSummaryBackground(isPositive: isPositiveOutcome))
        .padding(.trailing, 6)
    }
}

struct PitchCardView: View {
    
    let batterSide: BatterSide
    let leftImage: Image
    let topText: String
    let middleText: String
    let bottomText: String
    let verticalTopImage: Image
    let rightImage: Image
    let rightImageShouldHighlight: Bool
    let footerTextName: String
    let footerTextDate: String
    let gameTitle: String?
    let practiceTitle: String?
    let pitchNumber: Int?
    let outcomeSummary: [String]?
    let jerseyNumber: String?
    let atBatCountText: String?
    let hideHeader: Bool

    let onLongPress: () -> Void
    
    init(
        batterSide: BatterSide,
        leftImage: Image,
        topText: String,
        middleText: String,
        bottomText: String,
        verticalTopImage: Image,
        rightImage: Image,
        rightImageShouldHighlight: Bool,
        footerTextName: String,
        footerTextDate: String,
        pitchNumber: Int?,
        outcomeSummary: [String]?,
        jerseyNumber: String?,
        atBatCountText: String? = nil,
        gameTitle: String? = nil,
        practiceTitle: String? = nil,
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
        self.gameTitle = gameTitle
        self.practiceTitle = practiceTitle
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
                        } else if let practice = practiceTitle, !practice.isEmpty {
                            return "\(footerTextName) — \(practice)"
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
        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
        .onLongPressGesture(minimumDuration: 0.45) { onLongPress() }
    }
    
    private var content: some View {
        HStack(alignment: .center, spacing: 2) {
            leadingImages
                .padding(.leading, 10)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack{
                    Text(topText)
                        .font(.subheadline)
                        .bold()
                        .multilineTextAlignment(.leading)
                    
                    verticalTopImage
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                }
                Text(middleText)
                    .font(.caption)
                    .multilineTextAlignment(.leading)
                
                Text(bottomText)
                    .font(.caption)
                    .multilineTextAlignment(.leading)
            }
            .frame(minWidth: 70)
            .layoutPriority(1)
            
            Spacer()
            
            let hasJerseyNumber = (jerseyNumber?.isEmpty == false)
            if (outcomeSummary != nil && !(outcomeSummary?.isEmpty ?? true)) || hasJerseyNumber {
                OutcomeSummaryView(lines: outcomeSummary ?? [], jerseyNumber: jerseyNumber, countText: atBatCountText)
                    .padding(.bottom, 10)
            }
            
            rightImage
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 90)
                .shadow(
                    color: rightImageShouldHighlight ? .green.opacity(0.7) : .red.opacity(0.5),
                    radius: 6, x: 0, y: 0
                )
                .padding(.trailing, 10)
        }
    }
    
    @ViewBuilder
    private var leadingImages: some View {
        if batterSide == .right {
            leftImageView
            batImageView
        } else {
            batImageView
            leftImageView
        }
    }
    
    private var leftImageView: some View {
        leftImage
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 60, height: 90)
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
            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
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
        print("🔎 Left-image lookup key: \(lookupKey)")

        // If the dictionary has an explicit mapping, use it for perfect parity with the right image
        if let mapped = PitchImageDictionary.imageMap[lookupKey] {
            print("✅ Using mapped asset: \(mapped)")
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
                print("🔧 Asset name (neutral): \(candidate)")
                return candidate
            } else {
                let fallback = isStrike ? "StrikeMiddle" : "ballMiddle"
                print("⚠️ Missing asset: \(candidate). Falling back to \(fallback)")
                return fallback
            }
        }

        // Try side-agnostic first (some assets may omit side suffix)
        let base = (isStrike ? "Strike" : "ball") + normalized
        if UIImage(named: base) != nil {
            print("🔧 Asset name (agnostic): \(base)")
            return base
        }

        // Then side-specific
        let suffix = batterSide == .left ? "Right" : "Left"
        let candidate = base + suffix
        if UIImage(named: candidate) != nil {
            print("🔧 Asset name: \(candidate)")
            return candidate
        }

        // Final fallback
        let fallback = isStrike ? "StrikeMiddle" : "ballMiddle"
        print("❌ Missing assets for key=\(lookupKey). Falling back to \(fallback)")
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
        
        let rightImageName: String = PitchImageDictionary.imageName(
            for: event.location,
            isStrike: event.isStrike,
            batterSide: event.batterSide
        )
        
        let didHitLocation: Bool = isLocationMatch(event)
        
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
            print("🧪 Match debug — didHitLocation=\(didHitLocation)\n  called.pitch=\(calledPitchRaw) -> \(calledPitchNorm)\n  actual.pitch=\(actualPitchRaw) -> \(actualPitchNorm)\n  called.loc=\(calledLocRaw) -> type=\(calledLoc.type ?? "<none>") zone=\(calledLoc.zone)\n  actual.loc=\(actualLocRaw) -> type=\(actualLoc.type ?? "<none>") zone=\(actualLoc.zone)")
            return ()
        }()
        
        let verticalTopImageName: String = didHitLocation ? "hitCircle" : "missedCircle"
        
        let overallSuccessRate: Int = {
            let matchingCalls = allEvents.filter {
                return $0.calledPitch?.pitch == event.calledPitch?.pitch
            }
            let successes = matchingCalls.filter { isFullySuccessful($0) }.count
            let total = matchingCalls.count
            return total == 0 ? 0 : Int(Double(successes) / Double(total) * 100)
        }()
        
        let locationSuccessRate: Int = {
            let matchingCalls = allEvents.filter {
                $0.calledPitch?.pitch == event.calledPitch?.pitch &&
                $0.calledPitch?.location == event.calledPitch?.location
            }
            let successes = matchingCalls.filter { isFullySuccessful($0) }.count
            let total = matchingCalls.count
            return total == 0 ? 0 : Int(Double(successes) / Double(total) * 100)
        }()
        
        let timestampText: String = formattedTimestamp(event.timestamp)
        let outcomeSummary: [String] = outcomeSummaryLines(for: event)
        let jerseyNumber: String? = event.opponentJersey

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
                rightImage: Image(rightImageName),
                rightImageShouldHighlight: didHitLocation,
                footerTextName: selectedPlayerName,
                footerTextDate: "\(timestampText)",
                pitchNumber: pitchNumber(for: event, in: allEvents),
                outcomeSummary: outcomeSummary,
                jerseyNumber: jerseyNumber,
                atBatCountText: event.atBatCount,
                gameTitle: derivedGameTitle(from: event),
                practiceTitle: practiceTitle(for: event),
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
    
    private func practiceTitle(for event: PitchEvent) -> String? {
        struct StoredPracticeSession: Codable { var id: String?; var name: String; var date: Date }
        guard let pid = event.practiceId, !pid.isEmpty else { return nil }
        let key = "storedPracticeSessions"
        guard let data = UserDefaults.standard.data(forKey: key),
              let sessions = try? JSONDecoder().decode([StoredPracticeSession].self, from: data) else { return nil }
        return sessions.first(where: { $0.id == pid })?.name
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
    let sameDayEvents = allEvents.filter { evt in
        guard Calendar.current.isDate(evt.timestamp, inSameDayAs: event.timestamp) else { return false }
        guard evt.mode == event.mode else { return false }

        switch event.mode {
        case .game:
            if let gid = event.gameId?.trimmingCharacters(in: .whitespacesAndNewlines), !gid.isEmpty {
                guard evt.gameId == gid else { return false }
            }
        case .practice:
            let eventPid = event.practiceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let evtPid = evt.practiceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !eventPid.isEmpty || !evtPid.isEmpty {
                guard eventPid == evtPid else { return false }
            }
        }

        if let eventPitcherId = event.pitcherId?.trimmingCharacters(in: .whitespacesAndNewlines), !eventPitcherId.isEmpty {
            let evtPitcherId = evt.pitcherId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return evtPitcherId == eventPitcherId
        }

        return true
    }

    let sorted = sameDayEvents.sorted { $0.timestamp < $1.timestamp }
    let index = sorted.firstIndex { $0.identity == event.identity } ?? -1
    return index + 1
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

struct PitchEventDetailPopover: View {
    let event: PitchEvent
    let allEvents: [PitchEvent]
    let templateName: String
    let pitcherNameById: [String: String]
    let gameIdFilter: String?
    let practiceIdFilter: String?
    let lineupBatters: [JerseyCell]
    let selectedLineupBatterId: UUID?
    let onSelectLineupBatter: (JerseyCell) -> Void
    let onEditLineupBatter: (JerseyCell) -> Void
    let onMoveLineupBatterUp: (JerseyCell) -> Void
    let onMoveLineupBatterDown: (JerseyCell) -> Void
    let onDeleteLineupBatter: (JerseyCell) -> Void
    let currentCountSeed: (balls: Int, strikes: Int)?
    let onCountChanged: ((Int, Int) -> Void)?
    @State private var batterNotes: String = ""
    @State private var isBatterNotesFocused: Bool = false

    private var activeLineupCell: JerseyCell? {
        if let id = selectedLineupBatterId,
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
            if let pid = practiceIdFilter {
                if let evPid = evt.practiceId, !evPid.isEmpty { return evPid == pid }
                return true
            }
            if let gid = event.gameId {
                return evt.gameId == gid
            }
            if let pid = event.practiceId {
                return evt.practiceId == pid
            }
            return false
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

    var body: some View {
        let eventsWithCoords = batterEvents.filter { $0.battedBallTapX != nil && $0.battedBallTapY != nil }
        let hasIdentity = (batterEvents.first?.opponentBatterId?.isEmpty == false) || (batterEvents.first?.opponentJersey?.isEmpty == false)
        let playerEvents = batterEvents
        
        VStack(alignment: .leading, spacing: 16) {
            // Keep notes editor outside the main scroll view so its tap/focus is not
            // competing with nested sheet scroll gestures.
            VStack(alignment: .leading, spacing: 8) {
                Text("Batter notes")
                    .font(.subheadline.weight(.semibold))
                ZStack(alignment: .topLeading) {
                    FocusableNotesTextView(
                        text: $batterNotes,
                        isFocused: $isBatterNotesFocused
                    )
                    .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 120)

                    if batterNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add notes for this batter...")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 60)
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

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Batter spray chart")
                            .font(.subheadline).bold()
                        Spacer()
                        if hasIdentity {
                            let count = eventsWithCoords.count
                            let hitLabel = (count == 1) ? "hit" : "hits"
                            Text("\(count) \(hitLabel)")
                                .font(.subheadline).bold()
                        }
                    }
                    ZStack {
                        // Background rounded container that clips content
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)

                        // Centered, size-aware spray overlay
                        FieldSprayOverlay(
                            fieldImageName: "FieldImage",
                            events: batterEvents.filter { $0.battedBallTapX != nil && $0.battedBallTapY != nil },
                            homePlateNormalized: CGPoint(x: 0.5, y: 0.69),
                            focalNormalized: CGPoint(x: 0.5, y: 0.45),
                            overscan: 1.0
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    }
                    .frame(maxWidth: .infinity, minHeight: 330, maxHeight: 330)
                    .clipped()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(playerEvents.reversed().enumerated()), id: \.offset) { item in
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

                if !lineupBatters.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            if let activeCell = activeLineupCell {
                                Button {
                                    onEditLineupBatter(activeCell)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    onMoveLineupBatterUp(activeCell)
                                } label: {
                                    Label("Up", systemImage: "arrow.up")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    onMoveLineupBatterDown(activeCell)
                                } label: {
                                    Label("Down", systemImage: "arrow.down")
                                }
                                .buttonStyle(.bordered)

                                Button(role: .destructive) {
                                    onDeleteLineupBatter(activeCell)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                            }
                            Spacer()
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(lineupBatters) { cell in
                                    let isSelected = cell.id == selectedLineupBatterId
                                    Button {
                                        onSelectLineupBatter(cell)
                                    } label: {
                                        Text(cell.jerseyNumber)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                                            .frame(width: 42, height: 36)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .fill(isSelected ? Color.blue : Color(.systemGray6))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .stroke(isSelected ? Color.blue.opacity(0.95) : Color.black.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.bottom, 18)
                }
                }
                .frame(maxWidth: .infinity)
            }
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isBatterNotesFocused = false
                }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
            let uiImage = UIImage(named: fieldImageName)
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
                Image(fieldImageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX + focalShift.x, y: imageRect.midY + focalShift.y)

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
    
    @State private var pitcherFilter: String = ""
    @State private var jerseyFilter: String = ""
    @State private var pitchFilter: String = ""
    @State private var didApplyInitialJerseyFilter = false

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
            let pct = total == 0 ? 0 : Int(Double(successes) / Double(total) * 100)
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

        // If in practice mode and we have an active practice session, scope further to that session
        let practiceScoped: [PitchEvent] = {
            if sessionManager.currentMode == .practice, let pid = sessionManager.activePracticeId, !pid.isEmpty {
                return modeScoped.filter { $0.practiceId == pid }
            } else {
                return modeScoped
            }
        }()

        // Apply pitcher filter in game mode if provided
        let trimmedPitcher = pitcherFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let pitcherScoped: [PitchEvent] = {
            if sessionManager.currentMode != .game || trimmedPitcher.isEmpty { return practiceScoped }
            return practiceScoped.filter { event in
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
                                        .imageScale(.medium)
                                }
                                .buttonStyle(.plain)
                                .transition(.scale.combined(with: .opacity))
                                .offset(y: controlButtonsOffsetY)
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
                                        .imageScale(.medium)
                                }
                                .buttonStyle(.plain)
                                .transition(.scale.combined(with: .opacity))
                                .offset(y: controlButtonsOffsetY)

                                Spacer(minLength: 0)
                            }

                            if sessionManager.currentMode == .game {
                                Menu {
                                    if !pitcherFilter.isEmpty {
                                        Button(role: .destructive) {
                                            pitcherFilter = ""
                                        } label: {
                                            Label("Clear Pitcher Filter", systemImage: "xmark.circle")
                                        }
                                    }

                                    ForEach(availablePitchers, id: \.id) { pitcher in
                                        Button {
                                            pitcherFilter = pitcher.id
                                        } label: {
                                            HStack {
                                                Text(pitcher.name)
                                                if pitcherFilter == pitcher.id {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }

                                    Divider()

                                    // Clear option
                                    if !jerseyFilter.isEmpty {
                                        Button(role: .destructive) {
                                            jerseyFilter = ""
                                        } label: {
                                            Label("Clear Jersey Filter", systemImage: "xmark.circle")
                                        }
                                        Divider()
                                    }
                                    // Jersey options
                                    ForEach(availableJerseyNumbers, id: \.self) { num in
                                        Button {
                                            jerseyFilter = num
                                        } label: {
                                            HStack {
                                                Text("#\(num)")
                                                if jerseyFilter == num {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }

                                    Divider()

                                    // Clear pitch filter
                                    if !pitchFilter.isEmpty {
                                        Button(role: .destructive) {
                                            pitchFilter = ""
                                        } label: {
                                            Label("Clear Pitch Filter", systemImage: "xmark.circle")
                                        }
                                        Divider()
                                    }

                                    // Pitch options
                                    ForEach(availablePitchTypes, id: \.self) { type in
                                        Button {
                                            pitchFilter = type
                                        } label: {
                                            HStack {
                                                let pct = pitchTypeSuccessPercent[type]
                                                Text(pct != nil ? "\(type) (\(pct!)%)" : type)
                                                if pitchFilter == type {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    let hasActiveFilters = !pitcherFilter.isEmpty || !jerseyFilter.isEmpty || !pitchFilter.isEmpty
                                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                        .foregroundStyle(hasActiveFilters ? Color.blue : .primary)
                                        .shadow(color: hasActiveFilters ? Color.blue.opacity(0.35) : .clear, radius: hasActiveFilters ? 6 : 0)
                                        .imageScale(.medium)
                                        .clipShape(Capsule())
                                        .compositingGroup()
                                }
                                .offset(y: controlButtonsOffsetY)
                            }
                            else if sessionManager.currentMode == .practice {
                                Menu {
                                    // Clear pitch filter
                                    if !pitchFilter.isEmpty {
                                        Button(role: .destructive) {
                                            pitchFilter = ""
                                        } label: {
                                            Label("Clear Pitch Filter", systemImage: "xmark.circle")
                                        }
                                        Divider()
                                    }

                                    // Pitch options with success percentages
                                    ForEach(availablePitchTypes, id: \.self) { type in
                                        Button {
                                            pitchFilter = type
                                        } label: {
                                            HStack {
                                                let pct = pitchTypeSuccessPercent[type]
                                                Text(pct != nil ? "\(type) (\(pct!)%)" : type)
                                                if pitchFilter == type {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    let hasActiveFilters = !pitchFilter.isEmpty
                                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                        .foregroundStyle(hasActiveFilters ? Color.blue : .primary)
                                        .shadow(color: hasActiveFilters ? Color.blue.opacity(0.35) : .clear, radius: hasActiveFilters ? 6 : 0)
                                        .imageScale(.medium)
                                        .clipShape(Capsule())
                                        .compositingGroup()
                                }
                                .offset(y: controlButtonsOffsetY)
                            }
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
        .confirmationDialog(
            "Delete Selected Pitch Event\(selectedEventIDs.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedEvents()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the selected pitch event\(selectedEventIDs.count == 1 ? "" : "s") from the cards list.")
        }
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
                    batterSide: target.batterSide,
                    selectedTemplateId: target.templateId,
                    currentMode: target.mode,
                    selectedGameId: target.gameId,
                    selectedOpponentJersey: target.opponentJersey,
                    selectedOpponentBatterId: target.opponentBatterId,
                    selectedPracticeId: target.practiceId,
                    allPitchEvents: allEvents,
                    suggestedCountSeed: nil,
                    currentCountSeed: currentCountSeed,
                    onCountChanged: { balls, strikes in
                        onCountChanged?(balls, strikes)
                    },
                    lineupBatters: [],
                    selectedPitcherId: target.pitcherId,
                    saveAction: { edited in
                        saveEditedEvent(edited, original: target)
                    },
                    template: nil,
                    pitcherName: selectedPlayerName
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
    
    private func reassignSelectedEvents(toPitcher pitcher: Pitcher) {
        guard let pitcherId = pitcher.id else { return }
        guard let uid = Auth.auth().currentUser?.uid else {
            return
        }
        
        let db = Firestore.firestore()
        let batch = db.batch()

        let selectedEvents = allEvents.filter { event in
            guard let eid = event.id else { return false }
            return selectedEventIDs.contains(eid)
        }
        for event in selectedEvents {
            for ref in eventDocumentReferences(for: event, currentUid: uid) {
                batch.updateData(["pitcherId": pitcherId], forDocument: ref)
            }
        }

        batch.commit { error in
            if error == nil {
                selectedEventIDs.removeAll()
                isSelecting = false
            }
        }
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
            updateData["opponentBatterId"] = FieldValue.delete()
        }

        // Nothing to apply: just exit selection mode.
        guard !updateData.isEmpty else {
            pendingPitcherSelection = nil
            pendingBatterSelection = nil
            selectedEventIDs.removeAll()
            isSelecting = false
            return
        }

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

        let db = Firestore.firestore()
        let batch = db.batch()
        for event in selectedEvents {
            for ref in eventDocumentReferences(for: event, currentUid: uid) {
                batch.updateData(updateData, forDocument: ref)
            }
        }

        batch.commit { error in
            DispatchQueue.main.async {
                if let error {
                    print("❌ applyPendingSelectionChangesAndPersist failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func reassignSelectedEvents(toBatterJersey jersey: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let trimmed = jersey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let db = Firestore.firestore()
        let batch = db.batch()

        let selectedEvents = allEvents.filter { event in
            guard let eid = event.id else { return false }
            return selectedEventIDs.contains(eid)
        }

        for event in selectedEvents {
            let update: [String: Any] = [
                "opponentJersey": trimmed,
                "opponentBatterId": FieldValue.delete()
            ]
            for ref in eventDocumentReferences(for: event, currentUid: uid) {
                batch.updateData(update, forDocument: ref)
            }
        }

        batch.commit { error in
            if error == nil {
                selectedEventIDs.removeAll()
                isSelecting = false
            }
        }
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

        // Immediate visual feedback in-card.
        for eid in selectedIds {
            localBatterJerseyOverrides[eid] = trimmed
        }
        onApplyBatterJerseyOverride?(selectedIds, trimmed)

        // Persist immediately so the change survives sheet/game close.
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        let batch = db.batch()
        for event in selectedEvents {
            let update: [String: Any] = [
                "opponentJersey": trimmed,
                "opponentBatterId": FieldValue.delete()
            ]
            for ref in eventDocumentReferences(for: event, currentUid: uid) {
                batch.updateData(update, forDocument: ref)
            }
        }
        batch.commit { error in
            if let error {
                print("❌ applySelectedBatterImmediately failed: \(error.localizedDescription)")
            }
        }

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

        for eid in selectedIds {
            localPitcherOverrides[eid] = pitcherId
        }
        onApplyPitcherOverride?(selectedIds, pitcherId)

        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        let batch = db.batch()
        for event in selectedEvents {
            let update: [String: Any] = ["pitcherId": pitcherId]
            for ref in eventDocumentReferences(for: event, currentUid: uid) {
                batch.updateData(update, forDocument: ref)
            }
        }
        batch.commit { error in
            if let error {
                print("❌ applySelectedPitcherImmediately failed: \(error.localizedDescription)")
            }
        }

        pendingPitcherSelection = nil
    }

    private func eventDocumentReferences(for event: PitchEvent, currentUid: String) -> [DocumentReference] {
        guard let eid = event.id else { return [] }
        let db = Firestore.firestore()
        var refs: [DocumentReference] = []
        var seen: Set<String> = []

        func add(_ ref: DocumentReference) {
            let path = ref.path
            guard !seen.contains(path) else { return }
            seen.insert(path)
            refs.append(ref)
        }

        if event.mode == .game {
            if let gid = event.gameId?.trimmingCharacters(in: .whitespacesAndNewlines), !gid.isEmpty,
               let owner = gameOwnerUserId?.trimmingCharacters(in: .whitespacesAndNewlines), !owner.isEmpty {
                add(db.collection("users").document(owner).collection("games").document(gid).collection("pitchEvents").document(eid))
            }

            if let liveId = liveGameId?.trimmingCharacters(in: .whitespacesAndNewlines), !liveId.isEmpty {
                add(db.collection("liveGames").document(liveId).collection("pitchEvents").document(eid))
            }
        }

        // Legacy/fallback path (and practice path)
        if refs.isEmpty || event.mode == .practice {
            let ownerUid = event.createdByUid?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedUid = (ownerUid?.isEmpty == false) ? ownerUid! : currentUid
            add(db.collection("users").document(resolvedUid).collection("pitchEvents").document(eid))
        }

        return refs
    }

    private func deleteSelectedEvents() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let selectedEvents = allEvents.filter { event in
            guard let eid = event.id else { return false }
            return selectedEventIDs.contains(eid)
        }
        guard !selectedEvents.isEmpty else { return }

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

        let db = Firestore.firestore()
        let batch = db.batch()
        for event in selectedEvents {
            for ref in eventDocumentReferences(for: event, currentUid: uid) {
                batch.deleteDocument(ref)
            }
        }
        batch.commit { error in
            if let error {
                print("❌ deleteSelectedEvents failed: \(error.localizedDescription)")
            }
        }
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

    private func saveEditedEvent(_ edited: PitchEvent, original: PitchEvent) {
        guard let uid = Auth.auth().currentUser?.uid,
              let originalId = original.id else { return }

        var updated = PitchEvent(
            id: originalId,
            timestamp: original.timestamp,
            pitch: edited.pitch,
            location: edited.location,
            codes: edited.codes,
            isStrike: edited.isStrike,
            isBall: edited.isBall,
            mode: edited.mode,
            calledPitch: edited.calledPitch,
            batterSide: edited.batterSide,
            templateId: edited.templateId,
            strikeSwinging: edited.strikeSwinging,
            wildPitch: edited.wildPitch,
            passedBall: edited.passedBall,
            strikeLooking: edited.strikeLooking,
            outcome: edited.outcome,
            descriptor: edited.descriptor,
            errorOnPlay: edited.errorOnPlay,
            battedBallRegion: edited.battedBallRegion,
            battedBallType: edited.battedBallType,
            battedBallTapX: edited.battedBallTapX,
            battedBallTapY: edited.battedBallTapY,
            gameId: edited.gameId,
            opponentJersey: edited.opponentJersey,
            opponentBatterId: edited.opponentBatterId,
            practiceId: edited.practiceId,
            pitcherId: edited.pitcherId,
            createdByUid: edited.createdByUid
        )
        updated.id = originalId
        localEditedEventOverrides[originalId] = updated
        onApplyEditedEventOverride?(originalId, updated)

        do {
            var data = try Firestore.Encoder().encode(updated)
            // Keep owner provenance stable for future cross-device edits.
            if let createdBy = updated.createdByUid, !createdBy.isEmpty {
                data["createdByUid"] = createdBy
            }

            let db = Firestore.firestore()
            let batch = db.batch()
            for ref in eventDocumentReferences(for: original, currentUid: uid) {
                batch.setData(data, forDocument: ref, merge: false)
            }
            batch.commit { error in
                if let error {
                    print("❌ saveEditedEvent failed: \(error.localizedDescription)")
                }
            }
            selectedEventIDs.removeAll()
            isSelecting = false
        } catch {
            print("❌ saveEditedEvent encode failed: \(error)")
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
            print("UI: Rendering card for eventId=\(eventId), effectiveTemplateId=\(effectiveTemplateId ?? "<nil>"), templateName=\(templateName)")

            // Create a simple Binding for selection state
            let isSelectedBinding: Binding<Bool> = Binding<Bool>(
                get: {
                    if event.id == nil { return false }
                    return selectedEventIDs.contains(eventId)
                },
                set: { newValue in
                    if event.id == nil {
                        print("UI: Attempted to toggle selection for event with nil id")
                        return
                    }
                    if newValue {
                        selectedEventIDs.insert(eventId)
                        print("UI: Selected eventId=\(eventId). Now selectedEventIDs=\(Array(selectedEventIDs))")
                    } else {
                        selectedEventIDs.remove(eventId)
                        print("UI: Deselected eventId=\(eventId). Now selectedEventIDs=\(Array(selectedEventIDs))")
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
    let pitch: String
    let location: String
    let codes: [String]
    let isStrike: Bool
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
    var practiceId: String?
    var pitcherId: String?
    
    var createdByUid: String?

    var strikeSwingingMarker: String? = nil
    var strikeLookingMarker: String? = nil
    var ballMarker: String? = nil
    var foulMarker: String? = nil
    var atBatBalls: Int? = nil
    var atBatStrikes: Int? = nil
    var atBatCount: String? = nil
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
    case game, practice
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
        let percentage = total == 0 ? 0 : Int(Double(successes) / Double(total) * 100)
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
                print("⚠️ PitchEvent legacy decode used docId=\(doc.documentID)")
                return fallback
            }
            print("❌ PitchEvent decode failed docId=\(doc.documentID) error=\(error)")
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
            if let gameId = data["gameId"] as? String, !gameId.isEmpty {
                return .game
            }
            return .practice
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
        self.practiceId = data["practiceId"] as? String
        self.pitcherId = data["pitcherId"] as? String
        self.createdByUid = data["createdByUid"] as? String
    }

    func debugLog(prefix: String = "📤 Saving PitchEvent") {
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
            let practiceId: String?
            let pitcherId: String?
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
            practiceId: self.practiceId,
            pitcherId: self.pitcherId
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(debug), let json = String(data: data, encoding: .utf8) {
            print("\(prefix):\n\(json)")
        } else {
            print("\(prefix): <failed to encode>")
            print(self)
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
}
