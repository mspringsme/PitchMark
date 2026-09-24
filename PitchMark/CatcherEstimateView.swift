//
//  CatcherEstimateView.swift
//  PitchMark
//
//  Created by Mark Springer on 11/2/25.
//
import SwiftUI

/// Shown once, right after the coach taps a Catcher-mode pitch's result
/// location, before the normal result-detail sheet. Lets the coach optionally
/// log a guess at what the opposing catcher actually called - pitch type and
/// intended location - as a separate data point from the observed result.
/// See `catcherEstimate` on `PitchEvent`.
struct CatcherEstimateView: View {
    /// The just-recorded actual result call (pitch == "Catcher", location is
    /// the real tapped location, already prefixed "Strike "/"Ball ").
    let resultCall: PitchCall
    let batterSide: BatterSide
    /// Pitch-type pill options, in display order. "Catcher" is expected to be
    /// first, standing in for "didn't identify a type".
    let pitchOptions: [String]
    @Binding var draftPitch: String
    @Binding var draftLocation: String?
    let onReset: () -> Void
    let onSkip: () -> Void
    let onDone: () -> Void

    private var resultDisplayText: String {
        let loc = resultCall.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if loc.hasPrefix("Strike ") || loc.hasPrefix("Ball ") { return loc }
        return "\(resultCall.isStrike ? "Strike" : "Ball") \(loc)"
    }

    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            VStack(spacing: 4) {
                Text("Result: \(resultDisplayText)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.blue)
                Text("Estimate Pitch type and called location?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }

            Divider()

            pitchTypeGrid

            locationGrid
                .frame(height: 320)

            footerButtons
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
    }

    private var pitchTypeGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 88), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(pitchOptions, id: \.self) { pitch in
                pitchTypeButton(pitch)
            }
        }
    }

    private func pitchTypeButton(_ pitch: String) -> some View {
        let isSelected = draftPitch == pitch
        let isUnknown = pitch == "Catcher"
        return Button {
            draftPitch = pitch
        } label: {
            Text(isUnknown ? "Catcher" : pitch)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSelected ? .white : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule().fill(isSelected ? Color.black : Color.gray.opacity(0.15))
                )
                .overlay(
                    Capsule().stroke(Color.black.opacity(0.2), lineWidth: isSelected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var locationGrid: some View {
        GeometryReader { geo in
            let labelManager = PitchLabelManager(batterSide: batterSide)
            let zoneWidth = geo.size.width * 0.5
            let zoneHeight = geo.size.height * 0.62
            let cellWidth = zoneWidth / 3
            let cellHeight = zoneHeight / 3
            let buttonSize = min(cellWidth, cellHeight) * 0.8
            let originX = (geo.size.width - zoneWidth) / 2
            let originY: CGFloat = geo.size.height * 0.16

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .stroke(Color.black, lineWidth: 2)
                    .frame(width: zoneWidth, height: zoneHeight)
                    .position(x: originX + zoneWidth / 2, y: originY + zoneHeight / 2)

                ForEach(strikeGrid) { loc in
                    let x = originX + CGFloat(loc.col) * cellWidth + cellWidth / 2
                    let y = originY + CGFloat(loc.row) * cellHeight + cellHeight / 2
                    locationButton(x: x, y: y, rawLabel: loc.label, isStrike: true, buttonSize: buttonSize, labelManager: labelManager)
                }

                let ballLocations: [(String, CGFloat, CGFloat)] = [
                    ("Up & Out", originX - buttonSize * 0.6, originY - buttonSize * 0.6),
                    ("Up", originX + zoneWidth / 2, originY - buttonSize * 0.75),
                    ("Up & In", originX + zoneWidth + buttonSize * 0.6, originY - buttonSize * 0.6),
                    ("Out", originX - buttonSize * 0.75, originY + zoneHeight / 2),
                    ("In", originX + zoneWidth + buttonSize * 0.75, originY + zoneHeight / 2),
                    ("↓ & Out", originX - buttonSize * 0.6, originY + zoneHeight + buttonSize * 0.6),
                    ("↓", originX + zoneWidth / 2, originY + zoneHeight + buttonSize * 0.75),
                    ("↓ & In", originX + zoneWidth + buttonSize * 0.6, originY + zoneHeight + buttonSize * 0.6)
                ]

                ForEach(ballLocations, id: \.0) { label, x, y in
                    locationButton(x: x, y: y, rawLabel: label, isStrike: false, buttonSize: buttonSize, labelManager: labelManager)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder
    private func locationButton(x: CGFloat, y: CGFloat, rawLabel: String, isStrike: Bool, buttonSize: CGFloat, labelManager: PitchLabelManager) -> some View {
        let adjustedLabel = labelManager.adjustedLabel(from: rawLabel)
        let fullLabel = "\(isStrike ? "Strike" : "Ball") \(adjustedLabel)"
        let isSelected = draftLocation == fullLabel

        Button {
            draftLocation = fullLabel
        } label: {
            StrikeZoneButtonLabel(
                isStrike: isStrike,
                isSelected: isSelected,
                fullLabel: fullLabel,
                segmentColors: [],
                buttonSize: buttonSize,
                isRecordingResult: false,
                actualLocationRecorded: nil,
                calledPitchLocation: nil,
                pendingResultLabel: draftLocation,
                outlineOnly: true
            )
        }
        .buttonStyle(.plain)
        .position(x: x, y: y)
        .zIndex(1)
    }

    private var footerButtons: some View {
        HStack(spacing: 10) {
            Button("Reset", action: onReset)
                .buttonStyle(.bordered)

            Spacer(minLength: 8)

            Button("No", action: onSkip)
                .buttonStyle(.bordered)

            Spacer(minLength: 8)

            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .disabled(draftLocation == nil)
        }
    }
}
