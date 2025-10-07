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
    @State private var hasUnsavedChanges = false
    @State private var showSaveAlert = false
    
    let allPitches: [String]
    let templateID: UUID
    let onSave: (PitchTemplate) -> Void
    @Environment(\.dismiss) var dismiss
    
    private func saveTemplate() {
        if !selectedCodes.isEmpty && !selectedPitch.isEmpty && !selectedLocation.isEmpty {
            let newAssignments = selectedCodes.map {
                PitchCodeAssignment(code: $0, pitch: selectedPitch, location: selectedLocation)
            }

            for assignment in newAssignments {
                if !codeAssignments.contains(assignment) {
                    codeAssignments.append(assignment)
                }
            }

            selectedCodes.removeAll()
        }

        let newTemplate = PitchTemplate(
            id: templateID,
            name: name,
            pitches: Array(selectedPitches),
            codeAssignments: codeAssignments
        )
        onSave(newTemplate)
    }
    
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
        NavigationStack {
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
                            ForEach(pitchOrder, id: \.self) { pitch in
                                let isSelected = selectedPitches.contains(pitch)
                                Button(action: {
                                    if isSelected {
                                        selectedPitches.remove(pitch)
                                    } else {
                                        selectedPitches.insert(pitch)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        }
                                        
                                        Text(pitch)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
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
                    
                    Button("Save") {
                        saveTemplate()
                    }
                    .disabled(
                        name.isEmpty ||
                        selectedPitches.isEmpty
                    )
                    .padding(.bottom)
                    
                    Spacer()
                    
                }
                .padding()
            }
            .interactiveDismissDisabled(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Save and Close") {
                        saveTemplate()
                        dismiss()
                    }
                }
            }
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
        let allForPitch = pitchCodeAssignments.filter { $0.pitch == selectedPitch }

        if selectedLocation.isEmpty {
            return Array(Set(allForPitch.map(\.code))) // all codes for pitch
        } else {
            return allForPitch
                .filter { $0.location == selectedLocation }
                .map(\.code)
        }
    }
    
    private func codeCount(for pitch: String) -> Int {
        pitchCodeAssignments.filter { $0.pitch == pitch }.count
    }

    private func codeCount(forLocation label: String, isStrike: Bool) -> Int {
        let prefix = isStrike ? "Strike" : "Ball"
        let fullLabel = "\(prefix) \(label)"
        return pitchCodeAssignments.filter {
            $0.pitch == selectedPitch && $0.location == fullLabel
        }.count
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
                            .background(Color.black.opacity(0.8))
                            .foregroundStyle(Color.white)
                            .cornerRadius(6)
                    }
                }
                .padding(.horizontal)
            }

            HStack(spacing: 12) {
                
                // 🔹 Select Pitch
                Menu {
                    ForEach(allPitches.sorted(by: {
                        pitchOrder.firstIndex(of: $0) ?? .max
                        < pitchOrder.firstIndex(of: $1) ?? .max
                    }), id: \.self) { pitch in
                        Button(action: {
                            selectedPitch = pitch
                        }) {
                            let count = codeCount(for: pitch)
                            Label(count > 0 ? "\(pitch) (\(count))" : pitch, systemImage: selectedPitch == pitch ? "checkmark" : "")
                        }
                    }
                } label: {
                    menuLabel(
                        title: selectedPitch.isEmpty ? "Select Pitch" : selectedPitch,
                        isActive: !selectedPitch.isEmpty,
                        activeColor: Color.purple.opacity(0.2)
                    )
                }
                
                // 🔹 Strike Location
                Menu {
                    ForEach(strikeGrid.map(\.label), id: \.self) { label in
                        let fullLabel = "Strike \(label)"
                        Button(action: {
                            selectedLocation = fullLabel
                        }) {
                            let count = codeCount(forLocation: label, isStrike: true)
                            menuOption(label: count > 0 ? "\(label) (\(count))" : label, isSelected: selectedLocation == fullLabel)
                        }
                    }
                } label: {
                    menuLabel(
                        title: selectedLocation.starts(with: "Strike") ?
                            selectedLocation.replacingOccurrences(of: "Strike ", with: "") :
                            "Strike Location",
                        isActive: selectedLocation.starts(with: "Strike")
                    )
                }
                .disabled(selectedPitch.isEmpty)
                
                // 🔹 Ball Location
                Menu {
                    ForEach([
                        "Up & Out", "Up", "Up & In",
                        "Out", "In",
                        "↓ & Out", "↓ ", "↓ & In"
                    ], id: \.self) { label in
                        let fullLabel = "Ball \(label)"
                        Button(action: {
                            selectedLocation = fullLabel
                        }) {
                            let count = codeCount(forLocation: label, isStrike: false)
                            menuOption(label: count > 0 ? "\(label) (\(count))" : label, isSelected: selectedLocation == fullLabel)
                        }
                    }
                } label: {
                    menuLabel(
                        title: selectedLocation.starts(with: "Ball") ?
                            selectedLocation.replacingOccurrences(of: "Ball ", with: "") :
                            "Ball Location",
                        isActive: selectedLocation.starts(with: "Ball")
                    )
                }
                .disabled(selectedPitch.isEmpty)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8) // 👈 tighter left/right padding
            .padding(.bottom, 4)
            
            Text("\(selectedCodes.sorted().joined(separator: ", "))")
                .font(.headline)
                .padding(.top, 4)

            
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
                                    let assignment = PitchCodeAssignment(code: code, pitch: selectedPitch, location: selectedLocation)
                                    let isGloballyAssigned = pitchCodeAssignments.contains { $0.code == code }
                                    let isAssignedToCurrentLocation = pitchCodeAssignments.contains(assignment)
                                    let isSelected = selectedCodes.contains(code)
                                    let isAssignedToSelectedPitch = pitchCodeAssignments.contains {
                                        $0.code == code && $0.pitch == selectedPitch
                                    }

                                    // Visual styling
                                    let backgroundColor: Color = {
                                        if isGloballyAssigned {
                                            return .clear
                                        } else if isAssignedToCurrentLocation {
                                            return Color.blue.opacity(0.2)
                                        } else if isSelected {
                                            return Color.green.opacity(0.2)
                                        } else {
                                            return Color.blue.opacity(0.2)
                                        }
                                    }()

                                    let borderColor: Color = {
                                        if isAssignedToCurrentLocation {
                                            return .black
                                        } else if isGloballyAssigned {
                                            return .red
                                        } else if isSelected {
                                            return .green
                                        } else {
                                            return .blue
                                        }
                                    }()

                                    let borderWidth: CGFloat = isAssignedToCurrentLocation ? 3 : 1
                                    let shadowColor: Color = isAssignedToSelectedPitch ? Color.purple.opacity(0.4) : .clear
                                    let pitchHighlight: Color = isAssignedToSelectedPitch ? Color.purple.opacity(0.2) : .clear
                                    let textColor: Color = isGloballyAssigned ? .red : .black

                                    Button(action: {
                                        if isAssignedToCurrentLocation {
                                            pitchCodeAssignments.removeAll { $0 == assignment }
                                        } else if !isGloballyAssigned {
                                            if isSelected {
                                                selectedCodes.remove(code)
                                            } else {
                                                selectedCodes.insert(code)
                                            }
                                        }
                                    }) {
                                        Text(code)
                                            .font(.body)
                                            .frame(width: 60, height: 36)
                                            .background(backgroundColor)
                                            .foregroundColor(textColor)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(borderColor, lineWidth: borderWidth)
                                            )
                                            .shadow(color: shadowColor, radius: isAssignedToSelectedPitch ? 4 : 0)
                                            .background(pitchHighlight)
                                            .cornerRadius(6)
                                    }
                                    .disabled(isGloballyAssigned && !isAssignedToCurrentLocation)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom)
            }
            .onChange(of: selectedPitch) {
                selectedLocation = ""
            }
        }
        
    }
}
@ViewBuilder
func menuLabel(title: String, isActive: Bool, activeColor: Color = Color.gray.opacity(0.1)) -> some View {
    HStack {
        Text(title)
            .font(.subheadline)
            .foregroundColor(isActive ? .primary : Color.gray.opacity(0.5))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        Image(systemName: "chevron.down")
            .font(.caption)
            .foregroundColor(.gray)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(isActive ? activeColor : Color.gray.opacity(0.1))
    .cornerRadius(8)
    .overlay(
        RoundedRectangle(cornerRadius: 8)
            .stroke(isActive ? Color.black : Color.blue.opacity(0.3), lineWidth: isActive ? 2 : 1)
    )
}

@ViewBuilder
func menuOption(label: String, isSelected: Bool) -> some View {
    HStack {
        Text(label)
            .font(.caption)
            .foregroundColor(.primary)
        if isSelected {
            Spacer()
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundColor(.blue)
        }
    }
    .padding(.vertical, 4)
}
