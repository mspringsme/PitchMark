//
//  TemplateEditorView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/30/25.
//
import SwiftUI

struct TemplateEditorView: View {
    @State private var name: String
    @State private var selectedPitches: Set<String>
    @State private var selectedPitch: String = ""
    @State private var selectedLocation: String = ""
    @State private var selectedCodes: Set<String> = []
    @State private var codeAssignments: [PitchCodeAssignment]
    
    let allPitches: [String]
    let templateID: UUID
    let onSave: (PitchTemplate) -> Void
    @Environment(\.dismiss) var dismiss
    
    init(template: PitchTemplate?, allPitches: [String], onSave: @escaping (PitchTemplate) -> Void) {
        self.allPitches = allPitches
        self.onSave = onSave
        
        // Use local vars to initialize @State
        let initialName = template?.name ?? ""
        let initialPitches = Set(template?.pitches ?? [])
        let initialAssignments = template?.codeAssignments ?? []
        let id = template?.id ?? UUID()
        
        _name = State(initialValue: initialName)
        _selectedPitches = State(initialValue: initialPitches)
        _codeAssignments = State(initialValue: initialAssignments)
        self.templateID = id
    }
    
    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.endEditing()
                }
            VStack(spacing: 16) {
                TextField("Template Name", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(allPitches, id: \.self) { pitch in
                            let isSelected = selectedPitches.contains(pitch)
                            Button(action: {
                                if isSelected {
                                    selectedPitches.remove(pitch)
                                } else {
                                    selectedPitches.insert(pitch)
                                }
                            }) {
                                Text(pitch)
                                    .padding(8)
                                    .background(isSelected ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isSelected ? Color.green : Color.clear, lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                Divider()
                
                // 🔹 Code Assignment Panel
                CodeAssignmentPanel(
                    selectedCodes: $selectedCodes,
                    selectedPitch: $selectedPitch,
                    selectedLocation: $selectedLocation,
                    pitchCodeAssignments: $codeAssignments,
                    allPitches: Array(selectedPitches),
                    allLocations: allLocationsFromGrid(),
                    assignAction: {
                        for code in selectedCodes {
                            let assignment = PitchCodeAssignment(code: code, pitch: selectedPitch, location: selectedLocation)
                            if !codeAssignments.contains(assignment) {
                                codeAssignments.append(assignment)
                            }
                        }
                        selectedCodes.removeAll()
                    }
                )
                
                Spacer()
                
                Button("Save Template") {
                    // ✅ First, assign any pending codes
                    for code in selectedCodes {
                        let assignment = PitchCodeAssignment(code: code, pitch: selectedPitch, location: selectedLocation)
                        if !codeAssignments.contains(assignment) {
                            codeAssignments.append(assignment)
                        }
                    }
                    selectedCodes.removeAll()

                    // ✅ Then, save the full template
                    let newTemplate = PitchTemplate(
                        id: templateID,
                        name: name,
                        pitches: Array(selectedPitches),
                        codeAssignments: codeAssignments
                    )
                    onSave(newTemplate)
                    dismiss()
                }
                .disabled(name.isEmpty || selectedPitches.isEmpty)
            }
            .padding()
        }
    }
}

struct CodeAssignmentPanel: View {
    @Binding var selectedCodes: Set<String>
    @Binding var selectedPitch: String
    @Binding var selectedLocation: String
    @Binding var pitchCodeAssignments: [PitchCodeAssignment]
    
    let allPitches: [String]
    let allLocations: [String]
    let assignAction: () -> Void
    
    private var groupedCodes: [[String]] {
        stride(from: 1, through: 599, by: 100).map { start in
            let end = min(start + 99, 599)
            return (start...end).map { String(format: "%03d", $0) }
        }
    }

    private var assignedCodesForSelection: [String] {
        pitchCodeAssignments
            .filter { $0.pitch == selectedPitch && $0.location == selectedLocation }
            .map(\.code)
    }
    
    @ViewBuilder
    private func locationButton(label: String, isStrike: Bool) -> some View{
        let strikeLabels = strikeGrid.map(\.label)
        let fullLabel = "\(isStrike ? "Strike" : "Ball") \(label)"
        let isSelected = selectedLocation == fullLabel

        Button(action: {
            selectedLocation = fullLabel
        }) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                .foregroundColor(.primary)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
                )
        }
    }

    var body: some View {
        VStack(spacing: 12) {


            // 🔹 Assigned Codes for Current Pitch/Location
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(assignedCodesForSelection, id: \.self) { code in
                        Text(code)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(6)
                    }
                }
                .padding(.horizontal)
            }

            // 🔹 Dynamic Pitch + Location Label
            Text("\(selectedPitch) → \(selectedLocation)")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(allPitches, id: \.self) { pitch in
                        Button(action: { selectedPitch = pitch }) {
                            Text(pitch)
                                .padding(6)
                                .background(selectedPitch == pitch ? Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                // 🔹 Strike Locations
                Text("Strike Locations")
                    .font(.headline)
                    .padding(.leading)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(strikeGrid.map(\.label), id: \.self) { label in
                            locationButton(label: label, isStrike: true)
                        }
                    }
                    .padding(.horizontal)
                }

                // 🔹 Ball Locations
                Text("Ball Locations")
                    .font(.headline)
                    .padding(.leading)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([
                            "Up & Out", "Up", "Up & In",
                            "Out", "In",
                            "↓ & Out", "↓ ", "↓ & In"
                        ], id: \.self) { label in
                            locationButton(label: label, isStrike: false)
                        }
                    }
                    .padding(.horizontal)
                }
            }            // 🔹 Selected Codes Display
            Text("\(selectedCodes.sorted().joined(separator: ", "))")
                .font(.headline)
                .padding(.top, 4)

            // 🔹 Assign Button
            Button("Assign Codes") {
                for code in selectedCodes {
                    let assignment = PitchCodeAssignment(
                        code: code,
                        pitch: selectedPitch,
                        location: selectedLocation // already prefixed
                    )
                    if !pitchCodeAssignments.contains(assignment) {
                        pitchCodeAssignments.append(assignment)
                    }
                }
                selectedCodes.removeAll()
            }
            .disabled(selectedCodes.isEmpty || selectedPitch.isEmpty || selectedLocation.isEmpty)

            Divider()

            // 🔹 Embedded Scrollable Code Picker
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
                                    let isGloballyAssigned = pitchCodeAssignments.contains { $0.code == code }
                                    let isSelected = selectedCodes.contains(code)

                                    Button(action: {
                                        if isGloballyAssigned { return }
                                        if isSelected {
                                            selectedCodes.remove(code)
                                        } else {
                                            selectedCodes.insert(code)
                                        }
                                    }) {
                                        Text(code)
                                            .font(.body)
                                            .frame(width: 60, height: 36)
                                            .background(isGloballyAssigned ? Color.clear : isSelected ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                                            .foregroundColor(isGloballyAssigned ? .red : .black)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(
                                                        isGloballyAssigned ? Color.red :
                                                        isSelected ? Color.green :
                                                        Color.blue,
                                                        lineWidth: 1
                                                    )
                                            )
                                    }
                                    .disabled(isGloballyAssigned)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom)
            }
            
        }
        
    }
}
