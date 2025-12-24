//
//  TemplateEditorView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/30/25.
//
import SwiftUI
import UIKit

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
    @State private var showAssignedLocations = false
    @State private var templateType: String = "encrypted"
    
    let allPitches: [String]
    let templateID: UUID
    let onSave: (PitchTemplate) -> Void
    @Environment(\.dismiss) var dismiss

    // MARK: - Active Pitches Overrides (per-template)
    private static func loadActivePitches(for templateId: UUID, fallback: [String]) -> Set<String> {
        let key = "activePitches." + templateId.uuidString
        if let arr = UserDefaults.standard.stringArray(forKey: key) {
            return Set(arr)
        }
        return Set(fallback)
    }
    
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
        let initialPitches: Set<String> = {
            if let t = template {
                return Self.loadActivePitches(for: t.id, fallback: t.pitches)
            } else {
                return Set([])
            }
        }()
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
                    ColoredDivider(color: .blue, height: 1.0)
                    Text("Template Name")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                    TextField("", text: $name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($nameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { nameFieldFocused = false }
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 4)
                        .frame(width: 200)
                        .bold()
                        .foregroundColor(.blue)
                        // Add some right padding so text doesn't run under the icon
                        .padding(.trailing, 32)
                        // Overlay the icon on the trailing edge
                        .overlay(alignment: .trailing) {
                            Button {
                                nameFieldFocused = true
                            } label: {
                                Image(systemName: "square.and.pencil") // or "pencil"
                                    .foregroundColor(nameFieldFocused ? .blue : .secondary)
                                    .padding(.trailing, 8)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit template name")
                        }
                        
                    ColoredDivider(color: .blue, height: 1.0)
                    Text("Pitcher's Pitches")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
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
                            //let title = hasSelection ? "Pitches (\(selectedPitches.count))" : "Pitches"
                            let title = "Pitches"
                            HStack(spacing: 8) {
                                Text(title)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.clear)
                            .overlay(
                                Capsule()
                                    .stroke(Color.gray, lineWidth: 1)
                            )
                            .clipShape(Capsule())
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
                    ColoredDivider(color: .blue, height: 1.0)
                    if templateType != "encrypted" {
                        Text("Assign locations / codes to pitches")
                            .font(.system(size: 10))
                            .foregroundStyle(.gray)
                        // 🔹 Code Assignment Panel
                        CodeAssignmentPanel(
                            selectedCodes: $selectedCodes,
                            selectedPitch: $selectedPitch,
                            selectedLocation: $selectedLocation,
                            pitchCodeAssignments: $codeAssignments,
                            allPitches: availablePitches,
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
                            HStack(spacing: 12) {
                                Spacer()
                                Button("Assigned locations") {
                                    showAssignedLocations = true
                                }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.capsule)
                                .tint(.white)
                                .foregroundColor(.black)
                                .shadow(color: .black.opacity(0.2),
                                        radius: 3, x: 0, y: 2)
                                .sheet(isPresented: $showAssignedLocations) {
                                    AssignedLocationsOverview(codeAssignments: codeAssignments)
                                        .presentationDetents([.fraction(0.8), .large])
                                        .presentationDragIndicator(.visible)
                                }
                            Spacer()
                                Button("Save") {
                                    saveTemplate()
                                }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.capsule)
                                .tint(.white)
                                .foregroundColor(.black)
                                .shadow(color: .black.opacity(0.2),
                                        radius: 3, x: 0, y: 2)
                                .disabled(
                                    name
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                        .isEmpty || selectedPitches.isEmpty
                                )
                                Spacer()
                            }
                            .padding(.top)
                        }
                        
                        Spacer()
                    }
                    else {
                        // Encrypted template: show pitch grid editor
                        Text("Pitcher's Pitches Key Grid")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        PitchGridView(availablePitches: availablePitches)
                            .padding(.top, 20)
                        Spacer()
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
                    .fixedSize()
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Template Type", selection: $templateType) {
                        Text("Encrypted").tag("encrypted")
                        Text("Classic").tag("classic")
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityLabel("Template type")
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
                                .foregroundColor(.red)
                                .opacity(1.0)
                                //.padding(.horizontal, 4)
                        }
                        .accessibilityLabel("Cancel")
                    
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
            
            

            
            ColoredDivider(color: .blue, height: 1.0)
            

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
                                        if isAssignedToCurrentLocation {
                                            return Color.black
                                        } else if isAssignedToSelectedPitch {
                                            return Color.gray.opacity(0.85)
                                        } else if isGloballyAssigned {
                                            return .clear
                                        } else if isSelected {
                                            return Color.green.opacity(0.2)
                                        } else {
                                            return Color.blue.opacity(0.2)
                                        }
                                    }()

                                    let borderColor: Color = {
                                        if isAssignedToCurrentLocation {
                                            return .clear
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

                                    let borderWidth: CGFloat = isAssignedToCurrentLocation ? 0 : (isAssignedToSelectedPitch ? 1 : 1)
                                    let pitchHighlight: Color = isAssignedToSelectedPitch ? Color.purple.opacity(0.2) : .clear
                                    let textColor: Color = {
                                        if isAssignedToCurrentLocation {
                                            return .white
                                        } else if isAssignedToSelectedPitch {
                                            return .white
                                        } else if isGloballyAssigned {
                                            return .red
                                        } else {
                                            return .black
                                        }
                                    }()

                                    Button(action: {
                                        // If both a pitch and a location are selected and this code is assigned at that exact pair,
                                        // remove the assignment and clear any staged selection so the button returns to blue.
                                        if !selectedPitch.isEmpty, !selectedLocation.isEmpty, isAssignedToCurrentLocation {
                                            pitchCodeAssignments.removeAll { $0 == assignment }
                                            selectedCodes.remove(code)
                                            return
                                        }

                                        // Otherwise, if this code isn't globally assigned yet, toggle staged selection.
                                        if !isGloballyAssigned {
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
                                            .shadow(color: isAssignedToCurrentLocation ? Color.black.opacity(0.4) : .clear, radius: isAssignedToCurrentLocation ? 6 : 0, x: 0, y: 2)
                                            .background(pitchHighlight)
                                            .cornerRadius(6)
                                    }
                                    .disabled(isGloballyAssigned && !isAssignedToCurrentLocation)
                                }
                            }
                        }
                    }
                }
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

struct AssignedLocationsOverview: View {
    let codeAssignments: [PitchCodeAssignment]
    @Environment(\.dismiss) private var dismiss

    private func count(for fullLabel: String) -> Int {
        Set(codeAssignments
            .filter { $0.location == fullLabel }
            .map(\.code)).count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Assigned Locations")
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

                        // Strike zone locations (3x3) with codes
                        ForEach(strikeGrid) { loc in
                            let x = originX + CGFloat(loc.col) * cellWidth + cellWidth / 2
                            let y = originY + CGFloat(loc.row) * cellHeight + cellHeight / 2

                            let fullStrikeLabel = "Strike \(loc.label)"
                            let countHere = count(for: fullStrikeLabel)

                            ZStack {
                                Text(loc.label)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .frame(width: buttonSize, height: buttonSize)
                                    .background(Color.green.opacity(0.8))
                                    .clipShape(Circle())
                            }
                            .overlay(alignment: .topTrailing) {
                                if countHere > 0 {
                                    Text("\(countHere)")
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                        .padding(4)
                                        .background(Color.black.opacity(0.75))
                                        .clipShape(Circle())
                                        .offset(x: 6, y: -6)
                                }
                            }
                            .position(x: x, y: y)
                        }

                        // Ball locations around the zone with codes
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
                            let fullLabel = "Ball \(label)"
                            let countHere = count(for: fullLabel)

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
                                if countHere > 0 {
                                    Text("\(countHere)")
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                        .padding(4)
                                        .background(Color.black.opacity(0.75))
                                        .clipShape(Circle())
                                        .offset(x: 6, y: -6)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
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

struct ColoredDivider: View {
    let color: Color
    let height: CGFloat

    init(color: Color = Color(UIColor.separator), height: CGFloat = 1) {
        self.color = color
        self.height = height
    }

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: height)
    }
}


struct PitchGridView: View {
    @State private var pitches: [String] = []
    @State private var rowLabels: [String] = ["", "", ""]
    @State private var grid: [[String]] = [
        [],
        [],
        []
    ]
    @State private var isDeleteMode: Bool = false
    @State private var abbreviations: [String: String] = [:]
    @State private var showAbbrevEditorForIndex: Int? = nil
    @State private var pendingAbbreviation: String = ""
    let availablePitches: [String]
    
    @State private var showDuplicateAlert: Bool = false
    @State private var duplicateAlertMessage: String = ""
    @State private var lastInvalidPosition: (row: Int, col: Int)? = nil
    @State private var lastInvalidValue: String = ""

    let cellWidth: CGFloat = 60
    let cellHeight: CGFloat = 36
    
    private func displayName(for pitch: String) -> String {
        if let abbr = abbreviations[pitch], !abbr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return abbr
        }
        return pitch
    }
    
    private func normalizeGrid() {
        // Ensure each row has the same number of columns as pitches
        for row in grid.indices {
            if grid[row].count < pitches.count {
                grid[row].append(contentsOf: Array(repeating: "", count: pitches.count - grid[row].count))
            } else if grid[row].count > pitches.count {
                grid[row].removeLast(grid[row].count - pitches.count)
            }
        }
    }
    
    private func removePitch(at index: Int) {
        guard pitches.indices.contains(index) else { return }
        pitches.remove(at: index)
        for row in grid.indices {
            if grid[row].indices.contains(index) {
                grid[row].remove(at: index)
            } else if !grid[row].isEmpty {
                // If index somehow out of bounds, remove last to keep widths aligned
                grid[row].removeLast()
            }
        }
        // Exit delete mode if nothing left to delete
        if pitches.isEmpty { isDeleteMode = false }
    }
    
    // Returns the first available single-digit string ("0".."9") not in the excluded set
    private func firstAvailableDigit(excluding excluded: Set<String>) -> String? {
        for d in 0...9 {
            let s = String(d)
            if !excluded.contains(s) {
                return s
            }
        }
        return nil
    }
    
    private func isDuplicateInRow(row: Int, col: Int, value: String) -> Bool {
        guard row >= 0, row < grid.count else { return false }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let rowValues = grid[row]
        for (idx, v) in rowValues.enumerated() where idx != col {
            if v == value { return true }
        }
        return false
    }
    
    private func cellBinding(row: Int, col: Int, binding: Binding<String>) -> some View {
        @State var previousValue: String = binding.wrappedValue
        return baseCell {
            TextField("", text: binding)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 0)
                .onChange(of: binding.wrappedValue) { oldValue, newValue in
                    // Validate against duplicates in the same row, excluding this column
                    if isDuplicateInRow(row: row, col: col, value: newValue) {
                        // Revert and alert
                        binding.wrappedValue = previousValue
                        lastInvalidPosition = (row, col)
                        lastInvalidValue = newValue
                        duplicateAlertMessage = "\"\(newValue)\" is already used in another column for this row. Each row must have unique values across columns."
                        showDuplicateAlert = true
                    } else {
                        previousValue = newValue
                    }
                }
        }
    }
    
    var body: some View {
        VStack {
            // Keep grid width in sync with pitches
            // Normalize on appear and when pitches change
            EmptyView()
                .onAppear { normalizeGrid() }
                .onChange(of: pitches) {
                    normalizeGrid()
                }

            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    
                    // MARK: Header Grid
                    LazyVGrid(columns: gridColumns, spacing: 0) {
                        
                        // Top-left blank cell with NO border
                        emptyCell()
                        
                        // Pitch headers
                        ForEach(pitches.indices, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                
                                // Header cell
                                pitchHeaderCell(index: index, binding: $pitches[index])
                                
                                // Delete button overlay
                                if isDeleteMode {
                                    Button {
                                        removePitch(at: index)
                                        isDeleteMode = false
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                            .padding(4)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Delete column \(pitches[index])")
                                }
                            }
                        }
                        
                        // Add/delete menu column
                        Menu {
                            Button {
                                addPitch()
                                isDeleteMode = false
                            } label: {
                                Label("Add column", systemImage: "plus")
                            }
                            
                            Button(role: .destructive) {
                                if !pitches.isEmpty {
                                    isDeleteMode.toggle()
                                }
                            } label: {
                                Label("Delete columns", systemImage: "minus.circle")
                            }
                            .disabled(pitches.isEmpty)
                            
                        } label: {
                            Image(systemName: "plus.slash.minus")
                                .frame(width: cellWidth, height: cellHeight)
                        }
                        .accessibilityLabel("Add or delete columns")
                    }

                    // MARK: Data Rows
                    ForEach(grid.indices, id: \.self) { row in
                        LazyVGrid(columns: gridColumns, spacing: 0) {

                            // Row label
                            boldCellBinding($rowLabels[row])

                            // CASE 1: No pitches yet → show exactly ONE placeholder column
                            if pitches.isEmpty {
                                baseCell { Color.clear }
                            }

                            // CASE 2: Normal rows with pitches
                            else {
                                ForEach(grid[row].indices, id: \.self) { col in
                                    cellBinding(row: row, col: col, binding: $grid[row][col])
                                }
                            }

                            // Trailing empty cell (always required)
                            emptyCell()
                        }
                    }
                }
            }
        }
        .alert("Duplicate Value", isPresented: $showDuplicateAlert) {
            Button("OK", role: .cancel) {
                // After closing, clear the attempted value in the offending cell
                if let pos = lastInvalidPosition {
                    if grid.indices.contains(pos.row) && grid[pos.row].indices.contains(pos.col) {
                        grid[pos.row][pos.col] = ""
                    }
                } else {
                    // Fallback: clear any cell currently equal to the last invalid value in any row
                    for r in grid.indices {
                        for c in grid[r].indices {
                            if grid[r][c] == lastInvalidValue {
                                grid[r][c] = ""
                            }
                        }
                    }
                }
                // Reset trackers
                lastInvalidPosition = nil
                lastInvalidValue = ""
            }
        } message: {
            Text(duplicateAlertMessage)
        }
    }
    
    // MARK: Dynamic Grid Columns
    private var gridColumns: [GridItem] {
        let count = pitches.isEmpty ? 3 : pitches.count + 2
        return Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: count)
    }
    
    private func baseCell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack { content() }
            .frame(width: cellWidth, height: cellHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.4))
            )
    }
    
    private func placeholderCells(count: Int) -> some View {
        ForEach(0..<count, id: \.self) { _ in
            baseCell { Color.clear }
        }
    }
    
    // MARK: Helpers
    private func boldCellBinding(_ binding: Binding<String>) -> some View {
        baseCell {
            ZStack(alignment: .center) {
                // Placeholder when empty
                if binding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Code(s)")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .allowsHitTesting(false)
                }
                TextField("", text: binding)
                    .textFieldStyle(.plain)
                    .bold()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 0)
            }
        }
    }

    private func pitchHeaderCell(index: Int, binding: Binding<String>) -> some View {
        baseCell {
            Menu {
                // Select underlying pitch (unchanged logic)
                ForEach(availablePitches, id: \.self) { pitch in
                    Button(action: { binding.wrappedValue = pitch }) {
                        HStack {
                            Text(pitch)
                            if binding.wrappedValue == pitch {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                // Separator and abbreviation editor only when a pitch is selected
                if !binding.wrappedValue.isEmpty {
                    Divider()
                    Button {
                        // Prepare the editor with existing abbreviation (if any)
                        pendingAbbreviation = abbreviations[binding.wrappedValue] ?? ""
                        // Set the index for the abbreviation editor
                        showAbbrevEditorForIndex = index
                    } label: {
                        Label("Edit Abbreviation", systemImage: "character.cursor.ibeam")
                    }

                    // Option to clear abbreviation
                    if abbreviations[binding.wrappedValue] != nil {
                        Button(role: .destructive) {
                            abbreviations[binding.wrappedValue] = nil
                        } label: {
                            Label("Clear Abbreviation", systemImage: "trash")
                        }
                    }
                }
            } label: {
                // Show abbreviation if it exists, otherwise the pitch name
                Text(binding.wrappedValue.isEmpty ? "Select" : displayName(for: binding.wrappedValue))
                    .bold()
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Alert for editing the abbreviation
        .alert("Edit Abbreviation", isPresented: Binding(
            get: { showAbbrevEditorForIndex == index },
            set: { newValue in if !newValue { showAbbrevEditorForIndex = nil } }
        )) {
            TextField("Abbreviation", text: $pendingAbbreviation)
            Button("Save") {
                let keyPitch = binding.wrappedValue
                // Save only if a pitch is actually selected
                if !keyPitch.isEmpty {
                    let trimmed = pendingAbbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Save empty to remove or keep it empty if user wants nothing
                    if trimmed.isEmpty {
                        abbreviations[keyPitch] = nil
                    } else {
                        abbreviations[keyPitch] = trimmed
                    }
                }
                showAbbrevEditorForIndex = nil
            }
            Button("Cancel", role: .cancel) {
                showAbbrevEditorForIndex = nil
            }
        } message: {
            Text("Enter a short label to display for this pitch.")
        }
    }
    
    private func addPitch() {
        let newName = "P\(pitches.count + 1)"
        pitches.append(newName)

        // Track which digits we've already used in this new column (by row index processed so far)
        var usedInNewColumn: Set<String> = []

        // For each row, append a random single-digit (0-9) not already used in this row
        // AND not already used earlier in this same new column. If none available, append "".
        for row in grid.indices {
            // Digits already used in this row (ignoring empties)
            let usedDigitsInRow: Set<String> = Set(grid[row].filter { !$0.isEmpty })
            // Combine constraints: digits used in this row OR already used in this new column
            let excluded = usedDigitsInRow.union(usedInNewColumn)
            // Build allowed digits 0-9 excluding the set
            let allDigits = (0...9).map { String($0) }
            let allowed = allDigits.filter { !excluded.contains($0) }
            // Choose random allowed digit if available
            let value = allowed.randomElement() ?? ""
            grid[row].append(value)
            if !value.isEmpty { usedInNewColumn.insert(value) }
        }

        normalizeGrid()
    }
    
    private func emptyCell() -> some View {
        Color.clear
            .frame(width: cellWidth, height: cellHeight)
    }
}

