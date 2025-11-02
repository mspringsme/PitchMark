//
//  PitchResultsSheetView.swift
//  PitchMark
//
//  Created by Mark Springer on 11/2/25.
//
import SwiftUI

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
                Toggle("Passed Ball", isOn: $isPassedBall)
            }
            .padding(.horizontal)

            Divider()

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Spacer(minLength: 60)
                    Button("ꓘ") {
                        selectedOutcome = "ꓘ"
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedOutcome == "ꓘ" ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(6)

                    Button("K") {
                        selectedOutcome = "K"
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedOutcome == "K" ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(6)
                    Spacer(minLength: 60)
                }
                HStack(spacing: 8) {
                    Button("1B") {
                        selectedOutcome = "1B"
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedOutcome == "1B" ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(6)

                    Button("Pop") {
                        selectedOutcome = "Pop"
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedOutcome == "Pop" ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(6)

                    Button("BB") {
                        selectedOutcome = "BB"
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedOutcome == "BB" ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(6)
                }
                HStack(spacing: 8) {
                    Button("2B") {
                        selectedOutcome = "2B"
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedOutcome == "2B" ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(6)

                    Button("Line") {
                        selectedOutcome = "Line"
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedOutcome == "Line" ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(6)

                    Button("Bunt") {
                        selectedOutcome = "Bunt"
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedOutcome == "Bunt" ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(6)
                }
                HStack(spacing: 8) {
                    Button("3B") {
                        selectedOutcome = "3B"
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedOutcome == "3B" ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(6)

                    Button("Fly") {
                        selectedOutcome = "Fly"
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedOutcome == "Fly" ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(6)

                    Button("E") {
                        selectedOutcome = "E"
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedOutcome == "E" ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(6)
                }
                HStack(spacing: 8) {
                    Button("HR") {
                        selectedOutcome = "HR"
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedOutcome == "HR" ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(6)

                    Button("Grounder") {
                        selectedOutcome = "Grounder"
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedOutcome == "Grounder" ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(6)

                    Button("Foul") {
                        selectedOutcome = "Foul"
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selectedOutcome == "Foul" ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(6)
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

