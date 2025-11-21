//
//  CalledPitchRecord.swift
//  PitchMark
//
//  Created by Mark Springer on 10/9/25.
//


import Foundation
import FirebaseFirestore
import SwiftUI

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
    }
    
    private var content: some View {
        HStack(alignment: .center, spacing: 8) {
            leadingImages
                .padding(.leading, 8)
            
            Spacer()
            
            VStack(alignment: .center, spacing: 6) {
                HStack{
                    Text(topText)
                        .font(.subheadline)
                        .bold()
                        .multilineTextAlignment(.center)
                    
                    verticalTopImage
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                }
                Text(middleText)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                
                Text(bottomText)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .frame(minWidth: 80)
            .layoutPriority(1)
            
            Spacer()
            
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
            .padding(.horizontal, 2)
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
            pitchNumber: pitchNumber(for: event, in: allEvents)
        )
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
    let calledPitch: PitchCall?
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

