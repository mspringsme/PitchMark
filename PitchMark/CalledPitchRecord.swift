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
    if event.strikeSwinging { addUnique("Strike — Swinging") }
    if event.strikeLooking { addUnique("Strike — Looking") }
    if event.wildPitch { addUnique("Wild Pitch") }
    if event.passedBall { addUnique("Passed Ball") }
    if event.errorOnPlay { addUnique("Error on play") }
    if event.isBall == true { addUnique("Ball") }

    // Outcome/descriptor first (sanitize these to remove labels like "field --")
    addUnique(event.outcome, sanitizeText: true)
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
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.white))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 3)
    }
}

struct OutcomeSummaryView: View {
    let lines: [String]
    let jerseyNumber: String?
    let minHeight: CGFloat?

    init(lines: [String], jerseyNumber: String?, minHeight: CGFloat? = 44) {
        self.lines = lines
        self.jerseyNumber = jerseyNumber
        self.minHeight = minHeight
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
                }
                .padding(.bottom, 6)
            }
            ForEach(lines, id: \.self) { line in
                let showRunner: Bool = ["1B", "2B", "3B", "HR"].contains { prefix in
                    line.uppercased().hasPrefix(prefix)
                }
                HStack(spacing: 4) {
                    if showRunner {
                        Image(systemName: "figure.run")
                            .foregroundColor(.secondary)
                    }
                    Text(line)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(minWidth: 80, minHeight: minHeight)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(OutcomeSummaryBackground())
        .padding(.trailing, 10)
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
        gameTitle: String? = nil,
        practiceTitle: String? = nil,
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
        self.gameTitle = gameTitle
        self.practiceTitle = practiceTitle
        self.onLongPress = onLongPress
    }
    
    var body: some View {
        VStack(spacing: 0) {
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
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 8)
                
                Spacer()
                
                if let pitchNumber = pitchNumber {
                    Text("Pitch #\(pitchNumber)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .padding(.trailing, 8)
                        .padding(.top, 8)
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
            .frame(minWidth: 90)
            .layoutPriority(1)
            
            Spacer()
            
            if let outcomeSummary, !outcomeSummary.isEmpty {
                OutcomeSummaryView(lines: outcomeSummary, jerseyNumber: jerseyNumber)
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
    @State private var showDetails = false
    
    @Binding var isSelecting: Bool
    @Binding var isSelected: Bool

    init(
        event: PitchEvent,
        allEvents: [PitchEvent],
        games: [Game],
        templateName: String,
        isSelecting: Binding<Bool> = .constant(false),
        isSelected: Binding<Bool> = .constant(false)
    ) {
        self.event = event
        self.allEvents = allEvents
        self.games = games
        self.templateName = templateName
        self._isSelecting = isSelecting
        self._isSelected = isSelected
    }

    private func isLocationMatch(_ event: PitchEvent) -> Bool {
        return strictIsLocationMatch(event)
    }
    
    private func isFullySuccessful(_ event: PitchEvent) -> Bool {
        // Provide a simple heuristic for success (stub)
        return isLocationMatch(event)
    }

    var body: some View {
        let leftImageName: String = PitchAssetMapper.imageName(
            for: event.calledPitch?.location ?? "-",
            isStrike: event.calledPitch?.isStrike ?? false,
            batterSide: event.batterSide
        )
        
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
                $0.calledPitch?.pitch == event.calledPitch?.pitch
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
                footerTextName: "\(templateName)",
                footerTextDate: "\(timestampText)",
                pitchNumber: pitchNumber(for: event, in: allEvents),
                outcomeSummary: outcomeSummary,
                jerseyNumber: jerseyNumber,
                gameTitle: derivedGameTitle(from: event),
                practiceTitle: practiceTitle(for: event),
                onLongPress: { showDetails = true }
            )
        }
        .padding(.horizontal, 8)
        .popover(isPresented: $showDetails) {
            PitchEventDetailPopover(event: event, allEvents: allEvents, templateName: templateName)
                .padding()
                .presentationDetents([.fraction(0.70), .large])
                .presentationDragIndicator(.visible)
        }
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
    let sameDayEvents = allEvents.filter {
        Calendar.current.isDate($0.timestamp, inSameDayAs: event.timestamp) &&
        $0.mode == event.mode &&
        $0.templateId == event.templateId
    }
    
    let sorted = sameDayEvents.sorted { $0.timestamp < $1.timestamp }
    return (sorted.firstIndex { $0.id == event.id } ?? -1) + 1
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

    var batterEvents: [PitchEvent] {
        let sameGame = allEvents.filter { $0.gameId == event.gameId }

        let idToMatch = (event.opponentBatterId?.isEmpty == false) ? event.opponentBatterId : nil
        let jerseyToMatch = (event.opponentJersey?.isEmpty == false) ? event.opponentJersey : nil

        let matches = sameGame.filter { other in
            let idMatch = (idToMatch != nil) ? (other.opponentBatterId == idToMatch) : false
            let jerseyMatch = (jerseyToMatch != nil) ? (other.opponentJersey == jerseyToMatch) : false
            return idMatch || jerseyMatch
        }

        return matches.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        let timestampText: String = {
            let formatter = DateFormatter()
            let calendar = Calendar.current
            if calendar.isDateInToday(event.timestamp) {
                formatter.dateFormat = "'Today,' h:mm a"
            } else {
                formatter.dateFormat = "MM/dd/yy h:mm a"
            }
            return formatter.string(from: event.timestamp)
        }()

        let eventsWithCoords = batterEvents.filter { $0.battedBallTapX != nil && $0.battedBallTapY != nil }
        let hasIdentity = (batterEvents.first?.opponentBatterId?.isEmpty == false) || (batterEvents.first?.opponentJersey?.isEmpty == false)
        let jerseyEvents = batterEvents.filter { $0.opponentJersey == event.opponentJersey }
        let playerEvents = jerseyEvents.isEmpty ? batterEvents : jerseyEvents
        
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(playerEvents.reversed().enumerated()), id: \.offset) { item in
                            let evt = item.element
                            let isSource = (evt.id != nil && evt.id == event.id) || (evt.id == nil && event.id == nil && evt.timestamp == event.timestamp)
                            VStack(alignment: .leading, spacing: 8) {
                                let calledLabel = evt.calledPitch.map { "\($0.type) \($0.location)" }
                                let resultLabel = "\(evt.isStrike ? "Strike" : "Ball") \(evt.location)"
                                VStack(alignment: .leading, spacing: 2) {
                                    if let calledLabel {
                                        Text("(Coach): \(calledLabel)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Text("(Result): \(resultLabel)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.bottom, 4)

                                OutcomeSummaryView(
                                    lines: outcomeSummaryLines(for: evt),
                                    jerseyNumber: evt.opponentJersey,
                                    minHeight: 0
                                )
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
                            focalNormalized: CGPoint(x: 0.5, y: 0.5),
                            overscan: 1.12
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    }
                    .frame(maxWidth: .infinity, minHeight: 415, maxHeight: .infinity)
                    .clipped()
                }
            }
            .frame(maxWidth: .infinity)
        }
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
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionManager: PitchSessionManager

    @State private var isSelecting = false
    @State private var selectedEventIDs: Set<String> = Set<String>()
    @State private var showTemplatePicker = false
    @State private var localTemplateOverrides: [String: String] = [:]
    @State private var pendingTemplateSelection: PitchTemplate? = nil
    
    @State private var jerseyFilter: String = ""
    
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

        // Apply jersey filter if provided (trimmed and case-insensitive)
        let trimmed = jerseyFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let jerseyScoped: [PitchEvent] = {
            if trimmed.isEmpty { return practiceScoped }
            return practiceScoped.filter { evt in
                guard let jersey = evt.opponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines), !jersey.isEmpty else { return false }
                return jersey.caseInsensitiveCompare(trimmed) == .orderedSame
            }
        }()

        // Sort newest first
        return jerseyScoped.sorted { (lhs: PitchEvent, rhs: PitchEvent) -> Bool in
            return lhs.timestamp > rhs.timestamp
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                
                ZStack {
                    if isSelecting {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .transition(.opacity) // fade in/out background
                    }

                    HStack {
                        if isSelecting {
                            Spacer()
                            
                            Button("Done") {
                                withAnimation(.easeInOut) {
                                    if let template = pendingTemplateSelection {
                                        reassignSelectedEvents(to: template)
                                        pendingTemplateSelection = nil
                                    } else {
                                        selectedEventIDs.removeAll()
                                        isSelecting = false
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color(.black))
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            
                            Spacer()
                                .frame(width: 50)
                            
                            Button("Change Template") {
                                withAnimation(.easeInOut) {
                                    showTemplatePicker = true
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color(.blue))
                            .disabled(selectedEventIDs.isEmpty || !isSelecting)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            
                            Spacer()
                        } else {
                            Button {
                                withAnimation(.easeInOut) {
                                    isSelecting = true
                                }
                            } label: {
                                Image(systemName: "gearshape")
                                    .imageScale(.medium)
                            }
                            .buttonStyle(.plain)
                            //.foregroundStyle(Color(.bleu))
                            .transition(.scale.combined(with: .opacity)) // gear fades/scales in
                            
                            Spacer()

                            if sessionManager.currentMode == .game {
                                Menu {
                                    // Clear option
                                    if !jerseyFilter.isEmpty {
                                        Button(role: .destructive) {
                                            jerseyFilter = ""
                                        } label: {
                                            Label("Clear Filter", systemImage: "xmark.circle")
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
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "line.3.horizontal.decrease.circle")
                                        Text(jerseyFilter.isEmpty ? "#" : "#\(jerseyFilter)")
                                            .fontWeight(jerseyFilter.isEmpty ? .regular : .semibold)
                                            .monospacedDigit()
                                            .frame(minWidth: 24, alignment: .leading)
                                    }
                                    .padding(.horizontal, 8)
                                    .clipShape(Capsule())
                                    .compositingGroup()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 75)
                .padding(.vertical, -66)

                ScrollView(.vertical) {
                    VStack(spacing: 12) {
                        ForEach(filteredEvents, id: \.identity) { event in
                            EventRowView(
                                event: event,
                                allEvents: allEvents,
                                games: games,
                                templates: templates,
                                isSelecting: $isSelecting,
                                selectedEventIDs: $selectedEventIDs,
                                localTemplateOverrides: localTemplateOverrides
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .sheet(isPresented: $showTemplatePicker) {
            NavigationView {
                List(templates) { template in
                    Button(template.name) {
                        print("Picker: Chosen template id=\(template.id) name=\(template.name)")
                        pendingTemplateSelection = template
                        showTemplatePicker = false
                    }
                }
                .navigationTitle("Select Template")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            print("Picker: Cancel tapped")
                            showTemplatePicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
    
    private func reassignSelectedEvents(to template: PitchTemplate) {
        print("Batch: Starting reassignSelectedEvents. templateId=\(template.id.uuidString) name=\(template.name)")
        print("Batch: Current selectedEventIDs=\(Array(selectedEventIDs))")
        guard let uid = Auth.auth().currentUser?.uid else {
            print("Batch: No authenticated user; aborting reassignment.")
            return
        }
        
        let db = Firestore.firestore()
        let batch = db.batch()

        let selectedEvents = allEvents.filter { event in
            guard let eid = event.id else { return false }
            return selectedEventIDs.contains(eid)
        }
        print("Batch: selectedEvents count=\(selectedEvents.count)")

        for event in selectedEvents {
            guard let eid = event.id else {
                print("Batch: Skipping event with nil id")
                continue
            }
            print("Batch: Updating eventId=\(eid) -> templateId=\(template.id.uuidString)")
            let ref = db.collection("users").document(uid).collection("pitchEvents").document(eid)
            batch.updateData(["templateId": template.id.uuidString], forDocument: ref)
        }

        batch.commit { error in
            if let error = error {
                print("Batch: Commit failed with error: \(error)")
            } else {
                print("Batch: Commit succeeded. Updating localTemplateOverrides and clearing selection.")
                // Update local UI state for immediate feedback
                for event in selectedEvents {
                    if let eid = event.id {
                        localTemplateOverrides[eid] = template.id.uuidString
                        print("Batch: localTemplateOverrides[\(eid)] = \(template.id.uuidString)")
                    }
                }
                // Clear selection and exit selection mode
                selectedEventIDs.removeAll()
                isSelecting = false
                print("Batch: isSelecting set to false, selection cleared.")
            }
        }
    }
    
    private struct EventRowView: View {
        let event: PitchEvent
        let allEvents: [PitchEvent]
        let games: [Game]
        let templates: [PitchTemplate]

        @Binding var isSelecting: Bool
        @Binding var selectedEventIDs: Set<String>

        let localTemplateOverrides: [String: String]

        var body: some View {
            // Compute ids and effective template id outside of ViewBuilder statements that produce views
            let eventId: String = event.id ?? "<nil>"
            let effectiveTemplateId: String? = (event.id.flatMap { localTemplateOverrides[$0] }) ?? event.templateId

            // Log rendering for debugging
            let templateName: String = templates.first(where: { $0.id.uuidString == effectiveTemplateId })?.name ?? "Unknown"
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

            return PitchResultCard(
                event: event,
                allEvents: allEvents,
                games: games,
                templateName: templateName,
                isSelecting: $isSelecting,
                isSelected: isSelectedBinding
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
            practiceId: self.practiceId
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

