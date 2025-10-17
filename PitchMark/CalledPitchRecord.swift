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
    
    var body: some View {
        VStack {
            content
                .padding(.horizontal, 2)
                .padding(.vertical, 6)
                .background(cardBackground)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 8) {
            leadingImages

            VStack(alignment: .center, spacing: 6) {
                verticalTopImage
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32) // ⬅️ Slightly larger for clarity

                Text(topText)
                    .font(.headline)
                    .bold()
                    .multilineTextAlignment(.center)

                Text(middleText)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)

                Text(bottomText)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            }
            .frame(minWidth: 100)
            .layoutPriority(1)

            rightImage
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 130)
                .shadow(
                    color: rightImageShouldHighlight ? .green.opacity(0.7) : .red.opacity(0.5),
                    radius: 6, x: 0, y: 0
                )
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
            .frame(width: 100, height: 130)
    }

    private var batImageView: some View {
        Image("Bat")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 20, height: 82)
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

struct PitchResultCard: View {
    let event: PitchEvent

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

        // ✅ NEW: Determine if the actual pitch hit the called location
        let didHitLocation = event.calledPitch?.location == event.location
        let verticalTopImageName = didHitLocation ? "hitCircle" : "missedCircle"

        return PitchCardView(
            batterSide: event.batterSide,
            leftImage: Image(leftImageName),
            topText: event.calledPitch?.pitch ?? "-",
            middleText: "61% overall", // placeholder
            bottomText: "41% @ location", // placeholder
            verticalTopImage: Image(verticalTopImageName),
            rightImage: Image(rightImageName),
            rightImageShouldHighlight: didHitLocation
        )
    }
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

struct PitchResultsView: View {
    let thePitches: [PitchEvent]
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        ScrollView {
            if thePitches.isEmpty {
                Text("No pitch history found.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                VStack(spacing: 12) {
                    ForEach(thePitches.reversed()) { pitch in
                        PitchResultCard(event: pitch)
                    }
                }
                .padding()
            }
        }
    }
}

struct PitchResultSheet: View {
    let allEvents: [PitchEvent]
    @Binding var filterMode: PitchMode?
    @Environment(\.dismiss) private var dismiss

    private var filteredEvents: [PitchEvent] {
        guard let mode = filterMode else { return allEvents.reversed() }
        return allEvents.filter { $0.mode == mode }.reversed()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            modePicker
            
            Text("Pitch Count: \(filteredEvents.count)")
                .font(.headline)
                .padding(.horizontal)

            GeometryReader { geo in
                ScrollView([.vertical]) {
                    VStack(spacing: 12) {
                        ForEach(Array(filteredEvents.enumerated()), id: \.element.id) { index, event in
                            PitchResultCard(event: event)
                                .padding(.horizontal)
                        }
                    }
                    .frame(minHeight: geo.size.height, alignment: .top) // ✅ Force top alignment
                    .padding(.horizontal)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top)
        .onAppear {
            print("🧪 Filtered Events Count: \(filteredEvents.count)")
        }
    }

    private var modePicker: some View {
        HStack {
            Picker("Filter", selection: $filterMode) {
                Text("All").tag(nil as PitchMode?)
                Text("Game").tag(PitchMode.game as PitchMode?)
                Text("Practice").tag(PitchMode.practice as PitchMode?)
            }
            .pickerStyle(.segmented)

            Spacer()

            Button(action: {
                dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel("Close")
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

extension PitchCall {
    var displayTitle: String { "\(type) \(location)" } // location will now already be "Up & In" style
    var shortLabel: String { "\(pitch) — \(displayTitle)" }
}


