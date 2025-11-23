//
//  CalledPitchRecord.swift
//  PitchMark
//
//  Created by Mark Springer on 10/9/25.
//

import Foundation
import FirebaseFirestore
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
                HStack(spacing: 4) {
                    let showRunner = ["1B", "2B", "3B", "HR"].contains { prefix in
                        line.uppercased().hasPrefix(prefix)
                    }
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
        self.onLongPress = onLongPress
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 🧠 Header at top-left
            HStack(spacing: 4) {
                
                Text(footerTextDate)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 8)
                                
                Spacer()
                
                Text(footerTextName)
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
                .padding(.horizontal, 2)
                .padding(.vertical, 6)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
        .onLongPressGesture(minimumDuration: 0.45) { onLongPress() }
    }
    
    private var content: some View {
        HStack(alignment: .center, spacing: 2) {
            leadingImages
                .padding(.leading, 2)
            
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
            .frame(minWidth: 80)
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
                .padding(.trailing, 8)
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
    static func imageName(for rawLabel: String, isStrike: Bool, batterSide: BatterSide) -> String {
        let manager = PitchLabelManager(batterSide: batterSide)
        let adjusted = manager.adjustedLabel(from: rawLabel)
        
        // Remove "Strike " or "Ball " prefix if present
        let cleaned = adjusted
            .replacingOccurrences(of: "Strike ", with: "")
            .replacingOccurrences(of: "Ball ", with: "")
            .replacingOccurrences(of: " ", with: "") // remove spaces for asset name
        
        let neutralZones = ["High", "Low", "Middle"]
        if neutralZones.contains(cleaned) {
            return isStrike ? "Strike\(cleaned)" : "ball\(cleaned)"
        }
        
        let suffix = batterSide == .left ? "Right" : "Left"
        return isStrike ? "Strike\(cleaned)\(suffix)" : "ball\(cleaned)\(suffix)"
    }
}

// Used in PitchResultSheet
struct PitchResultCard: View {
    let event: PitchEvent
    let allEvents: [PitchEvent] // ✅ Add this
    let templateName: String
    @State private var showDetails = false
    
    func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "'Today,' h:mm a"
        } else {
            formatter.dateFormat = "MM/dd/yy h:mm a"
        }
        
        return formatter.string(from: date)
    }
    
    var body: some View {
        let leftImageName = PitchImageDictionary.imageName(
            for: event.calledPitch?.location ?? "-",
            isStrike: event.calledPitch?.isStrike ?? false,
            batterSide: event.batterSide
        )
        
        let rightImageName = PitchImageDictionary.imageName(
            for: event.location,
            isStrike: event.isStrike,
            batterSide: event.batterSide
        )
        
        let didHitLocation = isLocationMatch(event)
        let verticalTopImageName = didHitLocation ? "hitCircle" : "missedCircle"
        
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
        
        let timestampText = formattedTimestamp(event.timestamp)
        let outcomeSummary = outcomeSummaryLines(for: event)
        let jerseyNumber = event.opponentJersey
        
        return PitchCardView(
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
            onLongPress: { showDetails = true }
        )
        .popover(isPresented: $showDetails) {
            PitchEventDetailPopover(event: event, allEvents: allEvents, templateName: templateName)
                .padding()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
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
        let eventsWithCoords = batterEvents.filter { $0.battedBallTapX != nil && $0.battedBallTapY != nil }
        let hasIdentity = (batterEvents.first?.opponentBatterId?.isEmpty == false) || (batterEvents.first?.opponentJersey?.isEmpty == false)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.calledPitch?.pitch ?? event.pitch)
                        .font(.headline)
                    Text(templateName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                OutcomeSummaryView(
                    lines: outcomeSummaryLines(for: event),
                    jerseyNumber: event.opponentJersey,
                    minHeight: 0
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Batter spray chart")
                            .font(.subheadline).bold()
                        Spacer()
                        if hasIdentity {
                            Text("\(eventsWithCoords.count) hits")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    FieldSprayOverlay(
                        fieldImageName: "FieldImage",
                        events: batterEvents.filter { $0.battedBallTapX != nil && $0.battedBallTapY != nil },
                        homePlateNormalized: CGPoint(x: 0.5, y: 0.69) // tweak per asset if needed
                    )
                    .frame(maxWidth: .infinity, minHeight: 270)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
            }
            .padding(.vertical, 8)
        }
    }
}

struct FieldSprayOverlay: View {
    let fieldImageName: String
    let events: [PitchEvent]
    // Normalized (0..1) position of home plate within the field image
    let homePlateNormalized: CGPoint

    init(fieldImageName: String, events: [PitchEvent], homePlateNormalized: CGPoint = CGPoint(x: 0.5, y: 0.88)) {
        self.fieldImageName = fieldImageName
        self.events = events
        self.homePlateNormalized = homePlateNormalized
    }

    var body: some View {
        GeometryReader { geo in
            let availableSize = geo.size
            let uiImage = UIImage(named: fieldImageName)
            let aspect: CGFloat = {
                if let img = uiImage, img.size.height > 0 { return img.size.width / img.size.height }
                return 1
            }()
            // Fit by width to keep image size stable when container height changes
            let baseWidth: CGFloat = availableSize.width
            let baseHeight: CGFloat = baseWidth / max(aspect, 0.0001)

            // Scale up the field image for a zoomed-in look; allow some vertical overflow for tighter crop
            let scale: CGFloat = 2.5
            let scaledWidth = baseWidth * scale
            let scaledHeight = baseHeight * scale
            // Allow up to 1.5x container height before clamping (will be clipped by parent)
            let overflowAllowance: CGFloat = 1.5
            let heightClamp = min((availableSize.height * overflowAllowance) / max(scaledHeight, 1), 1)
            let targetWidth = scaledWidth * heightClamp
            let targetHeight = scaledHeight * heightClamp

            let imageRect = CGRect(
                x: (availableSize.width - targetWidth) / 2,
                y: (availableSize.height - targetHeight) / 2,
                width: targetWidth,
                height: targetHeight
            )
            
            // Home plate position within the fitted image, configurable via `homePlateNormalized`
            let origin = CGPoint(
                x: imageRect.minX + imageRect.width * homePlateNormalized.x,
                y: imageRect.minY + imageRect.height * homePlateNormalized.y
            )
            
            // Convert normalized tap coordinates to points within the fitted image rect
            let plottedPoints: [CGPoint] = events.compactMap { evt in
                guard let nx = evt.battedBallTapX, let ny = evt.battedBallTapY else { return nil }
                let px = imageRect.minX + CGFloat(nx) * imageRect.width
                let py = imageRect.minY + CGFloat(ny) * imageRect.height
                return CGPoint(x: px, y: py)
            }

            ZStack {
                Image(fieldImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                // Home plate reference marker
                Circle()
                    .fill(Color.black.opacity(0.25))
                    .frame(width: 4, height: 4)
                    .position(x: origin.x, y: origin.y)
                    .allowsHitTesting(false)
                
                if plottedPoints.isEmpty {
                    // Empty-state hint when there are no plotted points
                    Text("No hits yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)
                        .allowsHitTesting(false)
                } else {
                    ForEach(Array(plottedPoints.enumerated()), id: \.offset) { index, point in
                        // Dotted path from home plate to marker
                        DottedSprayPath(start: origin, end: point)
                            .stroke(style: StrokeStyle(lineWidth: 1.5))
                            .foregroundStyle(Color.black.opacity(0.25))
                            .frame(width: availableSize.width, height: availableSize.height, alignment: .topLeading)

                        // Use corresponding event to color the marker
                        let event = events[index]
                        MarkerView(isHR: event.isHomeRunInferred, isFoul: event.isFoulInferred)
                            .position(x: point.x, y: point.y)
                            .shadow(radius: 2)
                    }
                }
            }
            .frame(width: availableSize.width, height: availableSize.height, alignment: .topLeading)
            .clipped()
        }
    }
}

private struct MarkerView: View {
    let isHR: Bool
    let isFoul: Bool

    var body: some View {
        let color: Color = isHR ? .purple : (isFoul ? .orange : .red)
        let symbol: String = isHR ? "flag.checkered.fill" : (isFoul ? "xmark.circle.fill" : "smallcircle.filled.circle")

        Image(systemName: symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(color)
            .overlay(
                Circle().stroke(color.opacity(0.4), lineWidth: 2)
                    .frame(width: 18, height: 18)
            )
    }
}

private struct DottedSprayPath: Shape {
    let start: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = max(hypot(dx, dy), 1)
        // Dot spacing in points
        let spacing: CGFloat = 10
        let steps = max(Int(distance / spacing), 1)
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = start.x + dx * t
            let y = start.y + dy * t
            let dotRect = CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)
            path.addEllipse(in: dotRect)
        }
        return path
    }
}

struct PitchResultSheet: View {
    let allEvents: [PitchEvent]
    let templates: [PitchTemplate]
    @Binding var filterMode: PitchMode?
    @Environment(\.dismiss) private var dismiss
    
    private var filteredEvents: [PitchEvent] {
        guard let mode = filterMode else { return allEvents.reversed() }
        return allEvents.filter { $0.mode == mode }.reversed()
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            
            modePicker
            
            ScrollView([.vertical]) {
                VStack(spacing: 12) {
                    ForEach(Array(filteredEvents.enumerated()), id: \.element.id) { index, event in
                        let templateName = templates.first(where: { $0.id.uuidString == event.templateId })?.name ?? "Unknown"
                        
                        PitchResultCard(event: event, allEvents: allEvents, templateName: templateName)
                            .padding(.horizontal)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top)
    }
    
    private var modePicker: some View {
        HStack {
            Picker("Filter", selection: $filterMode) {
                Text("All").tag(nil as PitchMode?)
                Text("Game").tag(PitchMode.game as PitchMode?)
                Text("Practice").tag(PitchMode.practice as PitchMode?)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
    }
}

struct PitchEvent: Codable, Identifiable {
    @DocumentID var id: String? // Firestore will auto-assign this
    let timestamp: Date
    let pitch: String
    let location: String
    let codes: [String]
    let isStrike: Bool
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
        }
        let debug = DebugEvent(
            id: self.id,
            timestamp: self.timestamp,
            pitch: self.pitch,
            location: self.location,
            codes: self.codes,
            isStrike: self.isStrike,
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
            opponentBatterId: self.opponentBatterId
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

// MARK: - Previews

#Preview("PitchCard — Right Batter — Hit Location") {
    VStack(spacing: 16) {
        PitchCardView(
            batterSide: .right,
            leftImage: Image(systemName: "square.fill"),
            topText: "Four-Seam Fastball",
            middleText: "62% overall",
            bottomText: "55% @ location",
            verticalTopImage: Image(systemName: "checkmark.circle.fill"),
            rightImage: Image(systemName: "circle.fill"),
            rightImageShouldHighlight: true,
            footerTextName: "Template A",
            footerTextDate: "Today, 3:42 PM",
            pitchNumber: 7,
            outcomeSummary: [
                "Strike — Swinging",
                "1B to LF",
                "Runner to 2nd"
            ],
            jerseyNumber: "27"
        )
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}

#Preview("PitchCard — Left Batter — Missed Location") {
    VStack(spacing: 16) {
        PitchCardView(
            batterSide: .left,
            leftImage: Image(systemName: "square"),
            topText: "Curveball",
            middleText: "48% overall",
            bottomText: "33% @ location",
            verticalTopImage: Image(systemName: "xmark.circle.fill"),
            rightImage: Image(systemName: "circle"),
            rightImageShouldHighlight: false,
            footerTextName: "Template B",
            footerTextDate: "10/09/25 7:18 PM",
            pitchNumber: 2,
            outcomeSummary: [
                "Ball",
                "Groundout — 6-3"
            ],
            jerseyNumber: "5"
        )
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}

#Preview("Outcome Summary Variants") {
    VStack(spacing: 16) {
        OutcomeSummaryView(lines: [
            "HR — Deep CF",
            "Runner scores",
            "Error on play"
        ], jerseyNumber: "12")
        .background(Color(.systemBackground))
        .padding()

        OutcomeSummaryView(lines: [
            "1B — LF",
            "Runner to 3rd"
        ], jerseyNumber: nil)
        .background(Color(.systemBackground))
        .padding()
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

