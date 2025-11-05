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
                .frame(maxWidth: .infinity)
                .frame(height: 36) // 👈 Shorter height
                .background(isSelected ? Color(red: 0.75, green: 0.85, blue: 1.0) : Color.gray.opacity(0.1))
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2) // 👈 Add shadow
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
        .contentShape(Rectangle())
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
    @Binding var selectedDescriptor: String?
    @Binding var isError: Bool

    let pendingResultLabel: String?
    let pitchCall: PitchCall?
    let batterSide: BatterSide
    let selectedTemplateId: String?
    let currentMode: PitchMode
    let saveAction: (PitchEvent) -> Void
    let template: PitchTemplate?

    private func resetSelections() {
        isStrikeSwinging = false
        isStrikeLooking = false
        isWildPitch = false
        isPassedBall = false
        selectedOutcome = nil
        selectedDescriptor = nil
        isError = false
    }

    private func isOutcomeDisabled(_ label: String) -> Bool {
        if selectedOutcome == "HBP" {
                return label != "HBP"
            }
        if selectedOutcome == "ꓘ" && label == "Foul" {
            return true
        }
        // Determine if any of the top toggles are selected
        let anyTopToggle = isStrikeSwinging || isStrikeLooking || isWildPitch || isPassedBall
        // Determine if either strike toggle is selected
        let anyStrikeToggle = isStrikeSwinging || isStrikeLooking
        // Determine if either K or backwards K is selected
        let isKSelected = selectedOutcome == "K" || selectedOutcome == "ꓘ"

        // Descriptor group (mutually exclusive within the group, but can co-exist with base outcome)
        let descriptorGroup: Set<String> = ["Pop", "Line", "Fly", "Grounder", "Bunt"]
        // Base outcome group that should be mutually exclusive among themselves
        let baseOutcomeGroup: Set<String> = ["1B", "2B", "3B", "HR"]

        // Special rule: If HR is selected
        if selectedOutcome == "HR" {
            // Among descriptors, only allow Line or Fly; disable others.
            let allowedDescriptors: Set<String> = ["Line", "Fly"]
            if descriptorGroup.contains(label) {
                return !allowedDescriptors.contains(label)
            }
            // Disable the following non-descriptor outcomes when HR is selected
            let disallowedWhenHR: Set<String> = [
                "BB", "Bunt", "E", "Foul", "K", "ꓘ", "HBP", "Safe", "Out"
            ]
            if disallowedWhenHR.contains(label) {
                return true
            }
        }
        

        // 1) If K or backwards K is selected, deactivate all other buttons except 1B, E, Foul.
        //    K/ꓘ must remain active to allow deselection.
        if isKSelected {
            if label == "K" || label == "ꓘ" { return false }
            if label == "1B" || label == "E" || label == "Foul" { return false }
            return true
        }

        // 2) If any top toggle is on, disable descriptor group only (per earlier rule)
        if anyTopToggle && descriptorGroup.contains(label) {
            return true
        }

        // 3) If either strike toggle is on, also deactivate BB
        if anyStrikeToggle && label == "BB" {
            return true
        }

        // 4) Do not disable descriptor or base groups due to each other — co-selection is allowed.
        if descriptorGroup.contains(label) || baseOutcomeGroup.contains(label) {
            return false
        }

        return false
    }

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
                    OutcomeButton(label: "ꓘ", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("ꓘ"), usesDescriptorSelection: false)
                    OutcomeButton(label: "K", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("K"), usesDescriptorSelection: false)
                    Spacer()
                    OutcomeButton(label: "HBP", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("HBP"), usesDescriptorSelection: false)
                    Spacer()
                    OutcomeButton(label: "Safe", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Safe"), usesDescriptorSelection: false)
                    OutcomeButton(label: "Out", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Out"), usesDescriptorSelection: false)
                }
                HStack(spacing: 8) {
                    OutcomeButton(label: "1B", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("1B"), usesDescriptorSelection: false)
                    OutcomeButton(label: "Pop", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Pop"), usesDescriptorSelection: true)
                    OutcomeButton(label: "BB", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("BB"), usesDescriptorSelection: false)
                }
                HStack(spacing: 8) {
                    OutcomeButton(label: "2B", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("2B"), usesDescriptorSelection: false)
                    OutcomeButton(label: "Line", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Line"), usesDescriptorSelection: true)
                    OutcomeButton(label: "Bunt", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Bunt"), usesDescriptorSelection: true)
                }
                HStack(spacing: 8) {
                    OutcomeButton(label: "3B", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("3B"), usesDescriptorSelection: false)
                    OutcomeButton(label: "Fly", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Fly"), usesDescriptorSelection: true)
                    Button {
                        isError.toggle()
                    } label: {
                        Text("E")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36) // 👈 Shorter height
                            .background(isError ? Color(red: 0.75, green: 0.85, blue: 1.0) : Color.gray.opacity(0.1))
                            .cornerRadius(6)
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2) // 👈 Add shadow
                    }
                    .buttonStyle(.plain)
                    .disabled(isOutcomeDisabled("E"))
                }
                HStack(spacing: 8) {
                    OutcomeButton(label: "HR", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("HR"), usesDescriptorSelection: false)
                    OutcomeButton(label: "Grounder", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Grounder"), usesDescriptorSelection: true)
                    OutcomeButton(label: "Foul", selectedOutcome: $selectedOutcome, selectedDescriptor: $selectedDescriptor, isDisabled: isOutcomeDisabled("Foul"), usesDescriptorSelection: false)
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
                resetSelections()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)

            Button("Cancel", role: .cancel) {
                isPresented = false
                resetSelections()
            }
            .padding(.bottom)
        }
        .padding()
        .presentationDetents([.large])
        .onChange(of: isPresented) { _, newValue in
            if newValue == false {
                resetSelections()
            }
        }

        .onChange(of: isStrikeSwinging) { _, _ in deselectIfDisabled() }
        .onChange(of: isStrikeLooking) { _, _ in deselectIfDisabled() }
        .onChange(of: isWildPitch) { _, _ in deselectIfDisabled() }
        .onChange(of: isPassedBall) { _, _ in deselectIfDisabled() }
        .onChange(of: selectedOutcome) { _, _ in deselectIfDisabled() }
        .onChange(of: selectedDescriptor) { _, _ in deselectIfDisabled() }
        .onChange(of: isError) { _, _ in deselectIfDisabled() }
        .onChange(of: selectedOutcome) { _, newValue in
            if newValue == "HBP" {
                isWildPitch = true
                isStrikeSwinging = false
                isStrikeLooking = false
                isPassedBall = false
            }
            if newValue == "ꓘ" && selectedDescriptor == "Foul" {
                    selectedDescriptor = nil
            }
            
            deselectIfDisabled()
        }
    }
    private func deselectIfDisabled() {
        if let outcome = selectedOutcome, isOutcomeDisabled(outcome) {
            selectedOutcome = nil
        }
        if let descriptor = selectedDescriptor, isOutcomeDisabled(descriptor) {
            selectedDescriptor = nil
        }
        if isError && isOutcomeDisabled("E") {
            isError = false
        }
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
        selectedDescriptor: .constant(nil),
        isError: .constant(false),
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
