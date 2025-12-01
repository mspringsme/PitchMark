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
    @State private var customPitchName: String = ""
    @State private var customPitches: [String] = []
    @FocusState private var customPitchFieldFocused: Bool
    @FocusState private var nameFieldFocused: Bool
    
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
        _customPitches = State(initialValue: (template?.pitches ?? []).filter { !pitchOrder.contains($0) })
        self.templateID = id
    }
    
    private var availablePitches: [String] {
        // Base pitch order followed by any custom pitches the user adds
        pitchOrder + customPitches
    }

    private func addCustomPitch() {
        let trimmed = customPitchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Check if it already exists (case-insensitive) in the base list
        if let existingBase = pitchOrder.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            selectedPitches.insert(existingBase)
            customPitchName = ""
            customPitchFieldFocused = false
            return
        }

        // Check if it already exists (case-insensitive) in custom list
        if let existingCustom = customPitches.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            selectedPitches.insert(existingCustom)
            customPitchName = ""
            customPitchFieldFocused = false
            return
        }

        // Otherwise, add new custom pitch and select it
        customPitches.append(trimmed)
        selectedPitches.insert(trimmed)
        customPitchName = ""
        customPitchFieldFocused = false
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.endEditing()
                    }
                VStack(spacing: 10) {
                    Divider()
                    TextField("Template Name", text: $name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($nameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { nameFieldFocused = false }
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 4)
                        .frame(width: 200)
                        .bold()
                        .foregroundColor(.blue)
                        
                    Divider()
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(availablePitches, id: \.self) { pitch in
                                let isSelected = selectedPitches.contains(pitch)
                                Button(action: {
                                    if isSelected {
                                        selectedPitches.remove(pitch)
                                    } else {
                                        selectedPitches.insert(pitch)
                                    }
                                }) {
                                    Label(pitch, systemImage: isSelected ? "checkmark" : "")
                                }
                            }
                        } label: {
                            let hasSelection = !selectedPitches.isEmpty
                            let title = hasSelection ? "Pitches (\(selectedPitches.count))" : "Pitches"
                            HStack(spacing: 8) {
                                Text(title)
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.clear)
                            .overlay(
                                Capsule()
                                    .stroke(Color.red, lineWidth: 2)
                            )
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 2)
                            .padding(.leading, 8)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            
                            TextField("Add custom", text: $customPitchName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 120)
                                .focused($customPitchFieldFocused)
                                .onSubmit { customPitchFieldFocused = false }
                                .submitLabel(.done)

                            Button(action: { addCustomPitch() }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .imageScale(.large)
                                    .foregroundColor(customPitchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .green)
                                    .opacity(customPitchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1.0)
                            }
                            .disabled(customPitchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityLabel("Add custom pitch")

                            Button(action: {
                                customPitchName = ""
                                customPitchFieldFocused = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .imageScale(.large)
                                    .foregroundColor(customPitchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .secondary)
                                    .opacity(customPitchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1.0)
                            }
                            .accessibilityLabel("Cancel adding custom pitch")
                            .disabled(customPitchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
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
                    
                    if !(nameFieldFocused || customPitchFieldFocused) {
                        Button("Save") {
                            saveTemplate()
                        }
                        .disabled(
                            name.isEmpty ||
                            selectedPitches.isEmpty
                        )
                        .padding(.bottom)
                    }
                    
                    Spacer()
                    
                }
                .padding(.horizontal)
            }
            .interactiveDismissDisabled(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Save and Close") {
                        saveTemplate()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .imageScale(.medium)
                            .padding(8)
                    }
                    .accessibilityLabel("Close without saving")
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
    
    @State private var showLocationPicker: Bool = false
    @State private var showSelectionOverlay: Bool = false
    
    private var groupedCodes: [[String]] {
        stride(from: 1, through: 599, by: 100).map { start in
            let end = min(start + 99, 599)
            return (start...end).map { String(format: "%03d", $0) }
        }
    }

    private var assignedCodesForSelection: [String] {
        // If no pitch is selected, don't show anything
        guard !selectedPitch.isEmpty else { return [] }

        // All codes already assigned to this pitch (across all locations)
        let assignedForPitch = Set(
            pitchCodeAssignments
                .filter { $0.pitch == selectedPitch }
                .map(\.code)
        )

        // Union with currently selected (staged) codes so they appear immediately
        let combined = assignedForPitch.union(selectedCodes)

        // Return a stable ordering
        return combined.sorted()
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


            ZStack {
                
                HStack(spacing: 12) {
                    Spacer()
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
                        let title = selectedPitch.isEmpty ? "Pitch" : selectedPitch
                        HStack(spacing: 8) {
                            Text(title)
                                .font(.subheadline)
                                .foregroundColor((!selectedPitch.isEmpty) ? .white : .primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill((!selectedPitch.isEmpty) ? Color.gray.opacity(0.85) : Color.gray.opacity(0.1))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.black, lineWidth: 1)
                        )
                    }
                    
                    // 🔹 Location Picker (Strike + Ball)
                    Button(action: { showLocationPicker = true }) {
                        let title: String = {
                            if selectedLocation.isEmpty { return "Location" }
                            return selectedLocation
                                .replacingOccurrences(of: "Strike ", with: "")
                                .replacingOccurrences(of: "Ball ", with: "")
                        }()
                        HStack(spacing: 8) {
                            Text(title)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill((!selectedLocation.isEmpty) ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.black, lineWidth: 1)
                        )
                    }
                    .disabled(selectedPitch.isEmpty)
                    .sheet(isPresented: $showLocationPicker) {
                        StrikeZoneLocationPicker(
                            selectedPitch: selectedPitch,
                            pitchCodeAssignments: pitchCodeAssignments
                        ) { pickedLabel in
                            selectedLocation = pickedLabel
                            showLocationPicker = false
                            // Do not present selection overlay; just update the button title
                            showSelectionOverlay = false
                        }
                        .presentationDetents([.fraction(0.8), .large])
                        .presentationDragIndicator(.visible)
                    }
                    
                    // Action buttons shown after a location is selected
                    // Action buttons are always shown, but inactive until a pitch and location are selected
                    //Spacer()
                    let hasSelection = !selectedPitch.isEmpty && !selectedLocation.isEmpty
                    
                        Button(action: {
                            // Confirm assignment and reset selections (mirror overlay behavior)
                            assignAction()
                            selectedPitch = ""
                            selectedLocation = ""
                            showSelectionOverlay = false
                        }) {
                            Image(systemName: "checkmark.circle.fill")
                                .imageScale(.large)
                                .foregroundColor((hasSelection && !selectedCodes.isEmpty) ? .green : Color.gray.opacity(0.5))
                                .opacity((hasSelection && !selectedCodes.isEmpty) ? 1.0 : 0.6)
                                //.padding(.horizontal, 4)
                        }
                        .accessibilityLabel("Done")
                        .disabled(!hasSelection || selectedCodes.isEmpty)

                        Button(action: {
                            // Cancel selection and clear staged codes (mirror overlay behavior)
                            selectedCodes.removeAll()
                            selectedPitch = ""
                            selectedLocation = ""
                            showSelectionOverlay = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .imageScale(.large)
                                .foregroundColor(hasSelection ? .red : Color.gray.opacity(0.5))
                                .opacity(hasSelection ? 1.0 : 0.6)
                                //.padding(.horizontal, 4)
                        }
                        .accessibilityLabel("Cancel")
                        .disabled(!hasSelection)
                    
                    Spacer()
                    
                }
                .blur(radius: showSelectionOverlay ? 3 : 0)
                .allowsHitTesting(!showSelectionOverlay)
                .frame(maxWidth: .infinity, alignment: .leading)

                if showSelectionOverlay {
                    // Overlay card prompting to choose codes
                    VStack(spacing: 10) {
                        Text("\(selectedPitch) — \(selectedLocation.replacingOccurrences(of: "Strike ", with: "").replacingOccurrences(of: "Ball ", with: ""))")
                            .font(.headline)
                        Text("Choose codes for this pitch/location")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 6)
                        HStack(spacing: 12) {
                            Button("Cancel") {
                                // Reset selections
                                selectedCodes.removeAll()
                                selectedPitch = ""
                                selectedLocation = ""
                                showSelectionOverlay = false
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Done") {
                                // Assign and reset
                                assignAction()
                                selectedPitch = ""
                                selectedLocation = ""
                                showSelectionOverlay = false
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(selectedCodes.isEmpty)
                        }
                    }
                    .padding(14)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            
            // Removed onChange modifiers as requested
            
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
            .frame(minHeight: 28, maxHeight: 36, alignment: .leading)
            
            

            
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
                                        if isAssignedToSelectedPitch {
                                            return Color.gray.opacity(0.85)
                                        } else if isGloballyAssigned {
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
                                        } else if isAssignedToSelectedPitch {
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
//                                    let shadowColor: Color = isAssignedToSelectedPitch ? Color.purple.opacity(0.4) : .clear
                                    let pitchHighlight: Color = isAssignedToSelectedPitch ? Color.purple.opacity(0.2) : .clear
                                    let textColor: Color = {
                                        if isAssignedToSelectedPitch {
                                            return .white
                                        } else if isGloballyAssigned {
                                            return .red
                                        } else {
                                            return .black
                                        }
                                    }()

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
//                                            .shadow(color: shadowColor, radius: isAssignedToSelectedPitch ? 4 : 0)
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

struct StrikeZoneLocationPicker: View {
    let selectedPitch: String
    let pitchCodeAssignments: [PitchCodeAssignment]
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    private func codeCount(for fullLabel: String) -> Int {
        guard !selectedPitch.isEmpty else { return 0 }
        return pitchCodeAssignments.filter { $0.pitch == selectedPitch && $0.location == fullLabel }.count
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text("Tap a Location")
                    if !selectedPitch.isEmpty {
                        Text("— \(selectedPitch)")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.headline)
                .padding(.top, 8)
                Spacer(minLength: 0)
                GeometryReader { geo in
                    let availableWidth = geo.size.width
                    let availableHeight = geo.size.height
                    let zoneWidth = availableWidth * 0.5
                    let zoneHeight = availableHeight * 0.65
                    let cellWidth = zoneWidth / 3
                    let cellHeight = zoneHeight / 3
                    let buttonSize = min(cellWidth, cellHeight) * 0.8
                    let originX = (availableWidth - zoneWidth) / 2
                    let originY: CGFloat = 40

                    ZStack(alignment: .topLeading) {
                        // Strike zone frame
                        Rectangle()
                            .stroke(Color.black, lineWidth: 2)
                            .frame(width: zoneWidth, height: zoneHeight)
                            .position(x: originX + zoneWidth / 2, y: originY + zoneHeight / 2)

                        // Strike zone locations (3x3)
                        ForEach(strikeGrid) { loc in
                            let x = originX + CGFloat(loc.col) * cellWidth + cellWidth / 2
                            let y = originY + CGFloat(loc.row) * cellHeight + cellHeight / 2

                            Button(action: {
                                onSelect("Strike \(loc.label)")
                                dismiss()
                            }) {
                                let count = codeCount(for: "Strike \(loc.label)")
                                ZStack {
                                    Text(loc.label)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .frame(width: buttonSize, height: buttonSize)
                                        .background(Color.green.opacity(0.8))
                                        .clipShape(Circle())
                                }
                                .overlay(alignment: .topTrailing) {
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                            .padding(4)
                                            .background(Color.black.opacity(0.75))
                                            .clipShape(Circle())
                                            .offset(x: 6, y: -6)
                                    }
                                }
                            }
                            .position(x: x, y: y)
                        }

                        // Ball locations around the zone
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
                            Button(action: {
                                onSelect("Ball \(label)")
                                dismiss()
                            }) {
                                let count = codeCount(for: "Ball \(label)")
                                ZStack {
                                    Text(label)
                                        .font(.caption2)
                                        .multilineTextAlignment(.center)
                                        .minimumScaleFactor(0.6)
                                        .lineLimit(2)
                                        .foregroundColor(.white)
                                        .frame(width: buttonSize, height: buttonSize)
                                        .background(Color.red.opacity(0.85))
                                        .clipShape(Circle())
                                }
                                .overlay(alignment: .topTrailing) {
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                            .padding(4)
                                            .background(Color.black.opacity(0.75))
                                            .clipShape(Circle())
                                            .offset(x: 6, y: -6)
                                    }
                                }
                            }
                            .position(x: x, y: y)
                        }
                    }
                }
                .frame(height: 420)
                .padding(.horizontal)

                Spacer(minLength: 0)
            }
//            .navigationTitle("Choose Location")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
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


#Preview("Template Editor – New Template") {
    let samplePitches = ["FB", "SL", "CH", "CB", "SI", "CT"]
    return TemplateEditorView(
        template: nil,
        allPitches: samplePitches,
        onSave: { _ in }
    )
}

#Preview("Template Editor – Existing Template") {
    let samplePitches = ["FB", "SL", "CH", "CB", "SI", "CT"]
    let sampleTemplate = PitchTemplate(
        id: UUID(),
        name: "Bullpen vs L",
        pitches: ["FB", "SL", "CH"],
        codeAssignments: [
            PitchCodeAssignment(code: "101", pitch: "FB", location: "Strike Middle"),
            PitchCodeAssignment(code: "115", pitch: "FB", location: "Strike Up"),
            PitchCodeAssignment(code: "205", pitch: "SL", location: "Ball ↓ & Out"),
            PitchCodeAssignment(code: "309", pitch: "CH", location: "Strike Down")
        ]
    )
    return TemplateEditorView(
        template: sampleTemplate,
        allPitches: samplePitches,
        onSave: { _ in }
    )
}

