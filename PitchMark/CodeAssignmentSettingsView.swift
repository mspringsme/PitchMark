//
//  CodeAssignmentSettingsView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/22/25.
//
import SwiftUI


struct CodeAssignmentSettingsView: View {
    @Binding var selectedPitch: String
    @Binding var selectedLocation: String
    @Binding var pitchCodeAssignments: [PitchCodeAssignment]
    @State private var selectedCodes: Set<String> = []

    let allPitches: [String]
    let allLocations: [String]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Pitch Location and Codes")
                .font(.caption)
                .bold()
                .padding(.top)

            CodeAssignmentPanel(
                selectedCodes: $selectedCodes,
                selectedPitch: $selectedPitch,
                selectedLocation: $selectedLocation,
                pitchCodeAssignments: $pitchCodeAssignments,
                allPitches: allPitches,
                allLocations: allLocations,
                assignAction: {} // ✅ satisfies the required parameter
            )

            Spacer()

            Button("Done") {
                dismiss()
            }
        }
        .padding()
    }
}


struct CodePickerPopover: View {
    let usedCodes: [String]
    let onSelect: (String) -> Void

    private var groupedCodes: [[String]] {
        stride(from: 1, through: 599, by: 100).map { start in
            let end = min(start + 99, 599)
            return (start...end).map { String(format: "%03d", $0) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groupedCodes.indices, id: \.self) { groupIndex in
                    let codes = groupedCodes[groupIndex]
                    let rangeLabel = "\(codes.first!)–\(codes.last!)"

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Codes \(rangeLabel)")
                            .font(.headline)
                            .padding(.leading)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(codes, id: \.self) { code in
                                let isUsed = usedCodes.contains(code)

                                Button(action: {
                                    if !isUsed {
                                        onSelect(code)
                                    }
                                }) {
                                    Text(code)
                                        .font(.body)
                                        .frame(width: 60, height: 36)
                                        .background(isUsed ? Color.clear : Color.blue.opacity(0.2))
                                        .foregroundColor(isUsed ? .red : .black)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(isUsed ? Color.red : Color.blue, lineWidth: 1)
                                        )
                                }
                                .disabled(isUsed)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 500)
    }
}
