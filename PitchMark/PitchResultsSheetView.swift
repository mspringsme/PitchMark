//
//  PitchResultsSheetView.swift
//  PitchMark
//
//  Created by Mark Springer on 11/2/25.
//
import SwiftUI

private struct OutcomeButton: View {
    let label: String
    @Binding var selectedOutcome: String?

    var body: some View {
        Button(label) {
            if selectedOutcome == label {
                selectedOutcome = nil
            } else {
                selectedOutcome = label
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .padding(.vertical, 8)
        .background(selectedOutcome == label ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
        .contentShape(Rectangle())
        .cornerRadius(6)
        .buttonStyle(.plain)
    }
}

private struct ToggleSection: View {
    @Binding var isStrikeSwinging: Bool
    @Binding var isStrikeLooking: Bool
    @Binding var isWildPitch: Bool
    @Binding var isPassedBall: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose any that apply:")
                .font(.subheadline)
            Toggle("Strike Swinging", isOn: $isStrikeSwinging)
                .onChange(of: isStrikeSwinging) { oldValue, newValue in
                    if newValue { isStrikeLooking = false }
                }
            Toggle("Strike Looking", isOn: $isStrikeLooking)
                .onChange(of: isStrikeLooking) { oldValue, newValue in
                    if newValue { isStrikeSwinging = false }
                }
            Toggle("Wild Pitch", isOn: $isWildPitch)
                .onChange(of: isWildPitch) { oldValue, newValue in
                    if newValue { isPassedBall = false }
                }
            Toggle("Passed Ball", isOn: $isPassedBall)
                .onChange(of: isPassedBall) { oldValue, newValue in
                    if newValue { isWildPitch = false }
                }
        }
        .padding(.horizontal)
    }
}

struct PitchResultSheetView: View {
    @Binding var isPresented: Bool
    @Binding var isStrikeSwinging: Bool
    @Binding var isStrikeLooking: Bool
    @Binding var isWildPitch: Bool
    @Binding var isPassedBall: Bool
    @Binding var selectedOutcome: String?

    let pendingResultLabel: String?
    let pitchCall: PitchCall?
    let batterSide: BatterSide
    let selectedTemplateId: String?
    let currentMode: PitchMode
    let saveAction: (PitchEvent) -> Void
    let template: PitchTemplate?

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

            ToggleSection(isStrikeSwinging: $isStrikeSwinging, isStrikeLooking: $isStrikeLooking, isWildPitch: $isWildPitch, isPassedBall: $isPassedBall)

            Divider()

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Spacer(minLength: 60)
                    OutcomeButton(label: "ꓘ", selectedOutcome: $selectedOutcome)
                    OutcomeButton(label: "K", selectedOutcome: $selectedOutcome)
                    OutcomeButton(label: "Safe", selectedOutcome: $selectedOutcome)
                    OutcomeButton(label: "Out", selectedOutcome: $selectedOutcome)
                    Spacer(minLength: 60)
                }
                HStack(spacing: 8) {
                    OutcomeButton(label: "1B", selectedOutcome: $selectedOutcome)
                    OutcomeButton(label: "Pop", selectedOutcome: $selectedOutcome)
                    OutcomeButton(label: "BB", selectedOutcome: $selectedOutcome)
                }
                HStack(spacing: 8) {
                    OutcomeButton(label: "2B", selectedOutcome: $selectedOutcome)
                    OutcomeButton(label: "Line", selectedOutcome: $selectedOutcome)
                    OutcomeButton(label: "Bunt", selectedOutcome: $selectedOutcome)
                }
                HStack(spacing: 8) {
                    OutcomeButton(label: "3B", selectedOutcome: $selectedOutcome)
                    OutcomeButton(label: "Fly", selectedOutcome: $selectedOutcome)
                    OutcomeButton(label: "E", selectedOutcome: $selectedOutcome)
                }
                HStack(spacing: 8) {
                    OutcomeButton(label: "HR", selectedOutcome: $selectedOutcome)
                    OutcomeButton(label: "Grounder", selectedOutcome: $selectedOutcome)
                    OutcomeButton(label: "Foul", selectedOutcome: $selectedOutcome)
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
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)

            Button("Cancel", role: .cancel) {
                isPresented = false
            }
            .padding(.bottom)
        }
        .padding()
        .presentationDetents([.large])
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

