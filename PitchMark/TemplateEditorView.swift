//
//  TemplateEditorView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/30/25.
//
import SwiftUI
import UIKit
import Combine

// Shared validation helpers and environment to coordinate top-row rules across Strike and Balls grids
private func alnumOnlyUppercased(_ string: String) -> [Character] {
    return string.uppercased().filter { $0.isNumber || ($0.isLetter && $0.isASCII) }
}

private func isSequentialDigits(_ chars: [Character]) -> Bool {
    if chars.count <= 1 { return true }
    let ints = chars.compactMap { $0.wholeNumberValue }
    let asc = ints.enumerated().allSatisfy { idx, val in idx == 0 || val == ints[idx - 1] + 1 }
    if asc { return true }
    let desc = ints.enumerated().allSatisfy { idx, val in idx == 0 || val == ints[idx - 1] - 1 }
    return desc
}

// Environment object to share the combined top row between StrikeLocationGridView and BallsLocationGridView
final class TopRowValidationCoordinator: ObservableObject {
    // Top rows
    @Published var strikeTopRow: [String] = Array(repeating: "", count: 3)
    @Published var ballsTopRow: [String] = Array(repeating: "", count: 3)

    // Body rows (rows 1..3) for both grids
    @Published var strikeRows: [[String]] = Array(repeating: Array(repeating: "", count: 3), count: 4)
    @Published var ballsRows: [[String]] = Array(repeating: Array(repeating: "", count: 3), count: 4)

    // MARK: - Top row helpers
    func usedAlnum(excluding isStrike: Bool, index: Int) -> Set<Character> {
        var set: Set<Character> = []
        for (i, v) in strikeTopRow.enumerated() where !(isStrike && i == index) {
            for ch in alnumOnlyUppercased(v) { set.insert(ch) }
        }
        for (i, v) in ballsTopRow.enumerated() where !(!isStrike && i == index) {
            for ch in alnumOnlyUppercased(v) { set.insert(ch) }
        }
        return set
    }

    func sanitizeTopRowInput(isStrike: Bool, index: Int, newValue: String) -> String {
        let onlyAlnum = String(alnumOnlyUppercased(newValue).prefix(3))
        let existing = usedAlnum(excluding: isStrike, index: index)
        var result: [Character] = []
        for ch in onlyAlnum {
            if existing.contains(ch) { continue }
            if result.contains(ch) { continue }
            result.append(ch)
        }
        return String(result)
    }

    // MARK: - Body rows (rows 1..3)
    // Sanitize: up to 3 uppercase alnum
    func sanitizeBodyInput(_ value: String) -> String {
        String(alnumOnlyUppercased(value).prefix(3))
    }

    // For a specific column, gather all characters already used in that column across rows 1..3 in both grids
    private func usedCharactersInColumn(_ col: Int, excludingRow excludedRow: Int) -> Set<Character> {
        var set: Set<Character> = []
        // Strike
        for r in 1...3 where r != excludedRow {
            for ch in alnumOnlyUppercased(strikeRows[r][col]) { set.insert(ch) }
        }
        // Balls
        for r in 1...3 where r != excludedRow {
            for ch in alnumOnlyUppercased(ballsRows[r][col]) { set.insert(ch) }
        }
        return set
    }

    // Apply column-uniqueness filter to a proposed value for (row, col)
    private func filteredForColumnUniqueness(row: Int, col: Int, proposed: String) -> String {
        guard (1...3).contains(row) else { return proposed }
        let used = usedCharactersInColumn(col, excludingRow: row)
        var result: [Character] = []
        for ch in alnumOnlyUppercased(proposed) {
            if used.contains(ch) { continue }
            if result.contains(ch) { continue }
            result.append(ch)
        }
        return String(result.prefix(3))
    }

    // Set a body row value (rows 1..3): mirror to all three columns in that row for BOTH grids, after enforcing column uniqueness.
    func setBodyRowMirrored(row: Int, col: Int, rawValue: String) {
        guard (1...3).contains(row) else { return }
        // Sanitize
        let sanitized = sanitizeBodyInput(rawValue)
        // Enforce column uniqueness for the originating column first
        let filtered = filteredForColumnUniqueness(row: row, col: col, proposed: sanitized)
        // Mirror across all 3 columns in this row for both grids, but for each column re-apply column-specific uniqueness
        for c in 0..<3 {
            let colFiltered = filteredForColumnUniqueness(row: row, col: c, proposed: filtered)
            if strikeRows.indices.contains(row) && strikeRows[row].indices.contains(c) {
                strikeRows[row][c] = colFiltered
            }
            if ballsRows.indices.contains(row) && ballsRows[row].indices.contains(c) {
                ballsRows[row][c] = colFiltered
            }
        }
    }
    
    func randomizeTopRowsWithUpToTwoAlnum() {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let digits = Array("0123456789")
        let pool = letters + digits

        func proposeFor(isStrike: Bool, index: Int) -> String {
            for _ in 0..<40 { // more attempts to find a valid combo
                var candidate: [Character] = []
                let len = Int.random(in: 1...2)
                for _ in 0..<len {
                    if let ch = pool.randomElement() {
                        candidate.append(ch)
                    }
                }
                let proposed = String(candidate)
                let sanitized = sanitizeTopRowInput(isStrike: isStrike, index: index, newValue: proposed)
                if !sanitized.isEmpty && sanitized.count <= 2 {
                    return sanitized
                }
            }
            return ""
        }

        for i in 0..<3 {
            let value = proposeFor(isStrike: true, index: i)
            if strikeTopRow.indices.contains(i) {
                strikeTopRow[i] = value
            }
        }
        for i in 0..<3 {
            let value = proposeFor(isStrike: false, index: i)
            if ballsTopRow.indices.contains(i) {
                ballsTopRow[i] = value
            }
        }
    }
    
    func randomizeTopRowsWithSequentialPairs() {
        // Generate two-character pairs for top rows across both grids.
        // Mostly sequential digit pairs (e.g., 12, 23, 34, 90), with occasional letter substitutions.
        // Maintain uniqueness across the combined top rows using existing sanitizeTopRowInput.
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

        // Build ascending sequential digit pairs with wrap from 9->0 (01,12,...,89,90)
        var seqPairs: [String] = []
        for i in 0..<10 {
            let next = (i + 1) % 10
            seqPairs.append("\(i)\(next)")
        }
        // Deduplicate while keeping order
        var seen: Set<String> = []
        let basePairs: [String] = seqPairs.filter { seen.insert($0).inserted }

        func maybeLetterize(_ s: String) -> String {
            guard s.count == 2 else { return s }
            // 5% chance to replace one character with a letter
            if Int.random(in: 0..<20) == 0 {
                let idxToReplace = Int.random(in: 0..<2)
                let ch = letters.randomElement() ?? "A"
                var arr = Array(s)
                arr[idxToReplace] = ch
                return String(arr)
            }
            return s
        }

        // Fallback creator: ensure we always return exactly 2 characters by replacing conflicts with letters
        func conflictResolvingFallback(isStrike: Bool, index: Int) -> String {
            let used = usedAlnum(excluding: isStrike, index: index)
            // Phase A: try to find a digits-only ascending pair that doesn't use any 'used' chars
            for raw in basePairs {
                let arr = Array(raw)
                if !used.contains(arr[0]) && !used.contains(arr[1]) {
                    // Both digits available
                    return raw
                }
            }
            // Phase B: allow substituting conflicts with letters to keep length==2
            for raw in basePairs {
                var arr = Array(raw)
                for i in 0..<arr.count {
                    if used.contains(arr[i]) {
                        if let replacement = ("ABCDEFGHIJKLMNOPQRSTUVWXYZ").first(where: { ch in
                            let c = Character(String(ch))
                            return !used.contains(c) && !arr.contains(c)
                        }) {
                            arr[i] = replacement
                        }
                    }
                }
                // Ensure two distinct alnum chars
                let only = alnumOnlyUppercased(String(arr))
                var result: [Character] = []
                for ch in only where !result.contains(ch) { result.append(ch) }
                if result.count == 2 { return String(result) }
            }
            // Absolute last resort: two letters
            let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
            let a = letters.randomElement() ?? "A"
            let b = letters.first(where: { $0 != a }) ?? "B"
            return String([a, b])
        }

        func fill(isStrike: Bool) {
            var bag = basePairs.shuffled()
            for col in 0..<3 {
                var placed = ""
                // Phase 1: try a number of randomized candidates (with occasional letterization)
                for _ in 0..<60 {
                    if bag.isEmpty { bag = basePairs.shuffled() }
                    let raw = maybeLetterize(bag.removeFirst())
                    let sanitized = sanitizeTopRowInput(isStrike: isStrike, index: col, newValue: raw)
                    if sanitized.count == 2 { placed = sanitized; break }
                }
                // Phase 2: deterministic conflict-resolving fallback to guarantee non-empty two chars
                if placed.isEmpty {
                    placed = conflictResolvingFallback(isStrike: isStrike, index: col)
                }
                if isStrike {
                    if strikeTopRow.indices.contains(col) { strikeTopRow[col] = placed }
                } else {
                    if ballsTopRow.indices.contains(col) { ballsTopRow[col] = placed }
                }
            }
        }

        fill(isStrike: true)
        fill(isStrike: false)
    }
}

private struct TopRowCoordinatorKey: EnvironmentKey {
    static let defaultValue: TopRowValidationCoordinator? = nil
}

extension EnvironmentValues {
    var topRowCoordinator: TopRowValidationCoordinator? {
        get { self[TopRowCoordinatorKey.self] }
        set { self[TopRowCoordinatorKey.self] = newValue }
    }
}

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
    @State private var showRandomConfirm = false
    @State private var showClearConfirm = false
    @State private var hasAnyPitchInTopRow = false
    @State private var showNoPitchAlert = false
    @State private var randomizeFirstColumnAction: (() -> Void)? = nil
    @State private var topRowCoordinator = TopRowValidationCoordinator()
    
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
                        Text("Pitcher's Pitches Grid Key")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        
                        VStack{
                            PitchGridView2(
                                availablePitches: availablePitches,
                                hasAnyPitchInTopRow: $hasAnyPitchInTopRow,
                                onProvideRandomizeAction: { action in
                                    self.randomizeFirstColumnAction = action
                                }
                            )
                                .padding(.top, 60)
                            Text("Pitch Selection")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, -2)
                        }
                        
//                        PitchGridView(availablePitches: availablePitches)
//                            .padding(.top, 20)

                        // New section for Strike Location Grid
                        HStack{
                            // Shared coordinator so the two grids validate their top rows as one combined row
//                            let coordinator = TopRowValidationCoordinator()
                            VStack{
                                StrikeLocationGridView()
                                    .environment(\ .topRowCoordinator, topRowCoordinator)
                                    .padding(.top, 8)
                                Text("Strikes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, -2)
                            }
                            VStack{
                                BallsLocationGridView()
                                    .environment(\ .topRowCoordinator, topRowCoordinator)
                                    .padding(.top, 8)
                                Text("Balls")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, -2)
                            }
                        }
                        VStack() {
                            Spacer()
                            HStack(spacing: 16) {
                                Button {
                                    showRandomConfirm = true
                                } label: {
                                    Label("Random", systemImage: "shuffle")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .buttonBorderShape(.capsule)
                                .tint(.white)
                                .foregroundColor(.black)
                                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                                .confirmationDialog("Randomize grid values?", isPresented: $showRandomConfirm, titleVisibility: .visible) {
                                    Button("Randomize", role: .destructive) {
                                        if !hasAnyPitchInTopRow {
                                            showNoPitchAlert = true
                                            return
                                        }
                                        // Randomize first column with unique two-digit sequential numbers
                                        randomizeFirstColumnAction?()
                                        topRowCoordinator.randomizeTopRowsWithSequentialPairs()
                                    }
                                    Button("Cancel", role: .cancel) { }
                                } message: {
                                    Text("This will randomize the values in your grids. This action cannot be undone.")
                                }
                                .alert("Add a pitch first", isPresented: $showNoPitchAlert) {
                                    Button("OK", role: .cancel) { }
                                } message: {
                                    Text("Please enter at least one pitch in the top row before randomizing.")
                                }

                                Button {
                                    showClearConfirm = true
                                } label: {
                                    Label("Clear", systemImage: "trash")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .buttonBorderShape(.capsule)
                                .tint(.white)
                                .foregroundColor(.black)
                                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                                .confirmationDialog("Clear all grid values?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                                    Button("Clear", role: .destructive) {
                                        // TODO: Wire up clear logic for encrypted grids
                                    }
                                    Button("Cancel", role: .cancel) { }
                                } message: {
                                    Text("This will remove all values from your grids. This action cannot be undone.")
                                }
                            }
                            .padding(.horizontal)
                            Spacer()
                        }
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
    
    // Helper to match menu action naming; delegates to existing removePitch
    private func removeColumn(at index: Int) {
        removePitch(at: index)
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
                    // Primary actions for a selected pitch in this column
                    Button(role: .destructive) {
                        removeColumn(at: index)
                    } label: {
                        Label("Remove Column", systemImage: "minus.circle")
                    }

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

struct PitchGridView2: View {
    let availablePitches: [String]
    @Binding var hasAnyPitchInTopRow: Bool
    var onProvideRandomizeAction: ((@escaping () -> Void) -> Void)? = nil

    @State private var abbreviations: [String: String] = [:]
    @State private var showAbbrevEditorForIndex: Int? = nil
    @State private var pendingAbbreviation: String = ""
    
    // Maximum number of assigned pitch headers allowed
    private let maxAssignedPitches = 7

    // Cell sizing
    private let cellWidth: CGFloat = 46
    private let cellHeight: CGFloat = 36

    // Dynamic grid: 4 rows, starts with 2 columns
    @State private var grid: [[String]] = Array(repeating: ["", ""], count: 4)

    // Count of non-empty headers in row 0 excluding column 0
    private var assignedHeaderCount: Int {
        grid[0].dropFirst().filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    // MARK: - Dynamic Columns
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: grid[0].count)
    }

    // MARK: - Helpers
    private func displayName(for pitch: String) -> String {
        if let abbr = abbreviations[pitch], !abbr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return abbr
        }
        return pitch
    }

    private func expandGridIfNeeded(col: Int) {
        let lastCol = grid[0].count - 1
        // Only expand if we're typing in the last column AND that cell becomes non-empty
        guard col == lastCol, !grid[0][col].isEmpty else { return }
        // Prevent creating a new select column if we've reached the max assigned headers
        guard assignedHeaderCount < maxAssignedPitches else { return }
        for r in 0..<grid.count {
            grid[r].append("")
        }
    }
    
    private func removeColumn(at col: Int) {
        // Ensure the column index is valid
        guard grid.first?.indices.contains(col) == true else { return }

        // Remove the column entirely from each row
        for r in 0..<grid.count {
            grid[r].remove(at: col)
        }

        // Ensure we always keep at least 2 columns
        while grid.first?.count ?? 0 < 2 {
            for r in 0..<grid.count { grid[r].append("") }
        }

        // After removal, collapse any trailing columns that are entirely empty,
        // but keep a minimum of 2 columns
        while let first = grid.first, first.count > 2 {
            let lastIndex = first.count - 1
            let isLastEmpty = (0..<grid.count).allSatisfy { grid[$0][lastIndex].isEmpty }
            if isLastEmpty {
                for r in 0..<grid.count { grid[r].remove(at: lastIndex) }
            } else {
                break
            }
        }
    }

    private func baseCell<Content: View>(
        strokeColor: Color = .blue,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack { content() }
            .frame(width: cellWidth, height: cellHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(strokeColor)
            )
    }

    // MARK: - Validation Helpers for First Column
    private func digits(in string: String) -> [Character] {
        return string.filter { $0.isNumber }
    }

    private func isSequential(_ chars: [Character]) -> Bool {
        // Allow ascending (e.g., 12, 123) or descending (e.g., 21, 321, 890)
        guard chars.count >= 1 else { return true }
        if chars.count == 1 { return true }
        let ints = chars.compactMap { $0.wholeNumberValue }
        // Check ascending consecutive
        let asc = ints.enumerated().allSatisfy { idx, val in
            idx == 0 || val == ints[idx - 1] + 1
        }
        if asc { return true }
        // Check descending consecutive
        let desc = ints.enumerated().allSatisfy { idx, val in
            idx == 0 || val == ints[idx - 1] - 1
        }
        return desc
    }

    private func rowDigits(excludingCol excludedCol: Int, row: Int) -> Set<Character> {
        var set: Set<Character> = []
        guard row >= 0, row < grid.count else { return set }
        for c in 0..<(grid[row].count) {
            if c == excludedCol { continue }
            for ch in digits(in: grid[row][c]) { set.insert(ch) }
        }
        return set
    }

    private func columnZeroDigits(excludingRow excludedRow: Int) -> Set<Character> {
        var set: Set<Character> = []
        for r in 0..<grid.count {
            if r == excludedRow { continue }
            for ch in digits(in: grid[r][0]) { set.insert(ch) }
        }
        return set
    }
    
    private func sanitizeFirstColumnInput(row: Int, newValue: String) -> String {
        // Keep only digits and limit to 3
        let onlyDigits = String(digits(in: newValue).prefix(3))
        // Must be sequential ascending or descending
        let chars = Array(onlyDigits)
        guard isSequential(chars) else { return String(chars.dropLast()) }
        // No duplicate digits across the same row (other columns)
        let existingInRow = rowDigits(excludingCol: 0, row: row)
        // No duplicate digits across other rows' first column
        let existingInOtherRowsCol0 = columnZeroDigits(excludingRow: row)
        // Remove any digits that already exist elsewhere (row or other rows' col 0)
        var result: [Character] = []
        for ch in chars {
            if existingInRow.contains(ch) { continue }
            if existingInOtherRowsCol0.contains(ch) { continue }
            if result.contains(ch) { continue }
            result.append(ch)
        }
        return String(result)
    }


    // Randomize first column (rows 1..3) with unique two-digit sequential numbers
    func randomizeFirstColumn() {
        // Ensure there is at least one pitch column beyond the header (i.e., grid[0].count > 1 and some non-empty header)
        let hasAtLeastOnePitchColumn = grid[0].count > 1 && grid[0].dropFirst().contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard hasAtLeastOnePitchColumn else { return }

        // Gather all existing values in the grid to avoid duplicates anywhere
        var usedValues: Set<String> = []
        for r in 0..<grid.count {
            for c in 0..<grid[r].count {
                let v = grid[r][c].trimmingCharacters(in: .whitespacesAndNewlines)
                if !v.isEmpty { usedValues.insert(v) }
            }
        }
        // Also remove current first-column rows 1..3 from usedValues temporarily so we can replace them freely
        for r in 1...3 {
            usedValues.remove(grid[r][0].trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // Build all two-digit sequential numbers as strings (ascending or descending): 01..89 and 10..98
        var candidates: [String] = []
        for tens in 0...9 {
            for ones in 0...9 where ones != tens {
                let diff = abs(ones - tens)
                if diff == 1 { // sequential
                    candidates.append(String(format: "%d%d", tens, ones))
                }
            }
        }
        // Filter out any candidate already used anywhere in the grid
        candidates = candidates.filter { !usedValues.contains($0) }
        // Shuffle candidates for randomness
        candidates.shuffle()

        // Helper to get digits of a two-char string
        func digits(of s: String) -> (Character, Character)? {
            guard s.count == 2, let first = s.first, let last = s.last, first.isNumber, last.isNumber else { return nil }
            return (first, last)
        }

        // We need 3 values such that:
        // - All three are unique (already ensured by candidates uniqueness)
        // - No digit repeats across the three values (six digits all distinct)
        var picked: [String] = []
        var usedDigits: Set<Character> = []
        for cand in candidates {
            guard let (d1, d2) = digits(of: cand) else { continue }
            if usedDigits.contains(d1) || usedDigits.contains(d2) { continue }
            picked.append(cand)
            usedDigits.insert(d1)
            usedDigits.insert(d2)
            if picked.count == 3 { break }
        }
        guard picked.count == 3 else { return }

        // Assign to first column rows 1..3
        for r in 1...3 { grid[r][0] = picked[r - 1] }

        // Also randomize subsequent columns under assigned pitch headers
        randomizeSubsequentColumns()
    }


    // Randomize subsequent columns (columns > 0) under assigned pitch headers.
    // Loosened rules: allow vertical repeats (within a column across rows),
    // but still enforce row uniqueness across columns (no repeats within the same row).
    func randomizeSubsequentColumns() {
        // Ensure there is at least one assigned pitch column beyond the header
        let columnCount = grid.first?.count ?? 0
        guard columnCount > 1 else { return }

        // Determine which columns have an assigned pitch in the header (row 0)
        let assignedColumns: [Int] = (1..<columnCount).filter { c in
            !grid[0][c].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !assignedColumns.isEmpty else { return }

        // Track digits used in each row (rows 1..3) to avoid duplicates across columns within that row
        var rowUsed: [Int: Set<String>] = [1: [], 2: [], 3: []]

        // For each assigned column, assign digits to rows 1..3 independently,
        // only checking row uniqueness (vertical duplicates are allowed)
        for c in assignedColumns {
            for r in 1...3 {
                let allDigits = (0...9).map { String($0) }
                let candidates = allDigits.filter { !(rowUsed[r]?.contains($0) ?? false) }
                let chosen = (candidates.randomElement() ?? allDigits.randomElement()) ?? "0"
                grid[r][c] = chosen
                rowUsed[r, default: []].insert(chosen)
            }
        }
    }

    // MARK: - Header Cell
    private func headerCell(col: Int, binding: Binding<String>) -> some View {
        baseCell(strokeColor: .black) {
            Menu {
                ForEach(availablePitches, id: \.self) { pitch in
                    Button {
                        // If this header is currently empty and assigning it would exceed the max, block it
                        let wasEmpty = binding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        if wasEmpty && assignedHeaderCount >= maxAssignedPitches {
                            return
                        }
                        binding.wrappedValue = pitch
                        // Attempt to expand only if under the cap
                        expandGridIfNeeded(col: col)
                        hasAnyPitchInTopRow = grid[0].dropFirst().contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    } label: {
                        HStack {
                            Text(pitch)
                            if binding.wrappedValue == pitch {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                if !binding.wrappedValue.isEmpty {
                    // Primary actions for a selected pitch in this column
                    Button(role: .destructive) {
                        removeColumn(at: col)
                    } label: {
                        Label("Remove Column", systemImage: "minus.circle")
                    }

                    Divider()

                    Button {
                        pendingAbbreviation = abbreviations[binding.wrappedValue] ?? ""
                        showAbbrevEditorForIndex = col
                    } label: {
                        Label("Edit Abbreviation", systemImage: "character.cursor.ibeam")
                    }

                    if abbreviations[binding.wrappedValue] != nil {
                        Button(role: .destructive) {
                            abbreviations[binding.wrappedValue] = nil
                        } label: {
                            Label("Clear Abbreviation", systemImage: "trash")
                        }
                    }
                }
            } label: {
                Text(binding.wrappedValue.isEmpty ? "Select" : displayName(for: binding.wrappedValue))
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .alert("Edit Abbreviation", isPresented: Binding(
            get: { showAbbrevEditorForIndex == col },
            set: { if !$0 { showAbbrevEditorForIndex = nil } }
        )) {
            TextField("Abbreviation", text: $pendingAbbreviation)
            Button("Save") {
                let key = binding.wrappedValue
                let trimmed = pendingAbbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
                abbreviations[key] = trimmed.isEmpty ? nil : trimmed
                showAbbrevEditorForIndex = nil
            }
            Button("Cancel", role: .cancel) {
                showAbbrevEditorForIndex = nil
            }
        } message: {
            Text("Enter a short label to display for this pitch.")
        }
    }

    // MARK: - Cell Binding
    private func cellBinding(row: Int, col: Int) -> some View {
        let binding = Binding(
            get: { grid[row][col] },
            set: { newValue in
                if col == 0 {
                    // Enforce: up to 3 digits, sequential (asc/desc), and no repeated digits within the row
                    let sanitized = sanitizeFirstColumnInput(row: row, newValue: newValue)
                    grid[row][col] = sanitized
                } else {
                    grid[row][col] = newValue
                }
                // Expand grid when typing in header row
                if row == 0 { expandGridIfNeeded(col: col) }
            }
        )

        if row == 0 && col > 0 {
            return AnyView(headerCell(col: col, binding: binding))
        }

        let stroke: Color = (row == 0 || col == 0) ? .black : .blue

        return AnyView(
            baseCell(strokeColor: stroke) {
                TextField("", text: binding)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .fontWeight((row == 0 || col == 0) ? .bold : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        )
    }

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: gridColumns, spacing: 0) {
                ForEach(0..<(grid.count * grid[0].count), id: \.self) { index in
                    let r = index / grid[0].count
                    let c = index % grid[0].count

                    if r == 0 && c == 0 {
                        ZStack { Color.clear }
                            .frame(width: cellWidth, height: cellHeight)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.clear))
                    } else {
                        cellBinding(row: r, col: c)
                    }
                }
            }
            .onAppear {
                hasAnyPitchInTopRow = grid[0].dropFirst().contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                onProvideRandomizeAction?(self.randomizeFirstColumn)
            }
            .onChange(of: grid) { _, _ in
                hasAnyPitchInTopRow = grid[0].dropFirst().contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                onProvideRandomizeAction?(self.randomizeFirstColumn)
            }
        }
    }
}

struct StrikeLocationGridView: View {
    // Match PitchGridView sizing and no spacing
    let cellWidth: CGFloat = 46
    let cellHeight: CGFloat = 36
    // 3 columns x 4 rows of editable cells
    @State private var grid: [[String]] = Array(repeating: Array(repeating: "", count: 3), count: 4)

    @Environment(\.topRowCoordinator) private var topRowCoordinator

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: 3)
    }

    private func baseCell<Content: View>(strokeColor: Color = .green, @ViewBuilder content: () -> Content) -> some View {
        ZStack { content() }
            .frame(width: cellWidth, height: cellHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(strokeColor)
            )
    }

    private func cellBinding(row: Int, col: Int, binding: Binding<String>) -> some View {
        let stroke: Color = (row == 0) ? .black : .green
        return baseCell(strokeColor: stroke) {
            TextField("", text: Binding(
                get: { binding.wrappedValue },
                set: { newValue in
                    if row == 0, let coord = topRowCoordinator {
                        let sanitized = coord.sanitizeTopRowInput(isStrike: true, index: col, newValue: newValue)
                        binding.wrappedValue = sanitized
                        if coord.strikeTopRow.indices.contains(col) {
                            coord.strikeTopRow[col] = sanitized
                        }
                    } else if let coord = topRowCoordinator {
                        // Rows 1..3: sanitize, mirror across row in both grids with column-uniqueness
                        coord.setBodyRowMirrored(row: row, col: col, rawValue: newValue)
                    } else {
                        binding.wrappedValue = String(alnumOnlyUppercased(newValue).prefix(3))
                    }
                }
            ))
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .fontWeight(row == 0 ? .bold : .regular)
            .padding(.horizontal, 0)
            .onAppear {
                if let coord = topRowCoordinator {
                    if row == 0 {
                        if coord.strikeTopRow.indices.contains(col) {
                            coord.strikeTopRow[col] = binding.wrappedValue
                        }
                    } else {
                        if coord.strikeRows.indices.contains(row) && coord.strikeRows[row].indices.contains(col) {
                            coord.strikeRows[row][col] = binding.wrappedValue
                        }
                    }
                }
            }
            .onReceive(
                (topRowCoordinator?
                    .$strikeRows
                    .receive(on: RunLoop.main)
                    .map { $0 }
                    .eraseToAnyPublisher())
                ?? Just([[String]]())
                    .eraseToAnyPublisher()
            ) { rows in
                guard (1...3).contains(row), rows.indices.contains(row), rows[row].indices.contains(col) else { return }
                let v = rows[row][col]
                if binding.wrappedValue != v { binding.wrappedValue = v }
            }
            // Inserted onReceive for strikeTopRow per instructions
            .onReceive(
                (topRowCoordinator?
                    .$strikeTopRow
                    .receive(on: RunLoop.main)
                    .eraseToAnyPublisher())
                ?? Just([String]()).eraseToAnyPublisher()
            ) { row0 in
                guard row == 0, row0.indices.contains(col) else { return }
                let v = row0[col]
                if binding.wrappedValue != v { binding.wrappedValue = v }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: gridColumns, spacing: 0) {
                ForEach(0..<(3 * 4), id: \.self) { index in
                    let r = index / 3
                    let c = index % 3
                    cellBinding(row: r, col: c, binding: $grid[r][c])
                }
            }
        }
    }
}

struct BallsLocationGridView: View {
    // Match PitchGridView sizing and no spacing
    let cellWidth: CGFloat = 46
    let cellHeight: CGFloat = 36
    // 3 columns x 4 rows of editable cells
    @State private var grid: [[String]] = Array(repeating: Array(repeating: "", count: 3), count: 4)

    @Environment(\.topRowCoordinator) private var topRowCoordinator

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: 3)
    }

    private func baseCell<Content: View>(strokeColor: Color = .red, @ViewBuilder content: () -> Content) -> some View {
        ZStack { content() }
            .frame(width: cellWidth, height: cellHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(strokeColor)
            )
    }

    private func cellBinding(row: Int, col: Int, binding: Binding<String>) -> some View {
        // Disable the cell in the 2nd column (index 1) and 3rd row (index 2), fill with green
        if row == 2 && col == 1 {
            return AnyView(
                baseCell(strokeColor: .red) {
                    ZStack {
                        Color.green
                        Text("")
                    }
                }
                .allowsHitTesting(false)
            )
        }

        let stroke: Color = (row == 0) ? .black : .red
        return AnyView(
            baseCell(strokeColor: stroke) {
                TextField("", text: Binding(
                    get: { binding.wrappedValue },
                    set: { newValue in
                        if row == 0, let coord = topRowCoordinator {
                            let sanitized = coord.sanitizeTopRowInput(isStrike: false, index: col, newValue: newValue)
                            binding.wrappedValue = sanitized
                            if coord.ballsTopRow.indices.contains(col) {
                                coord.ballsTopRow[col] = sanitized
                            }
                        } else if let coord = topRowCoordinator {
                            coord.setBodyRowMirrored(row: row, col: col, rawValue: newValue)
                        } else {
                            binding.wrappedValue = String(alnumOnlyUppercased(newValue).prefix(3))
                        }
                    }
                ))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .fontWeight(row == 0 ? .bold : .regular)
                .padding(.horizontal, 0)
                .onAppear {
                    if let coord = topRowCoordinator {
                        if row == 0 {
                            if coord.ballsTopRow.indices.contains(col) {
                                coord.ballsTopRow[col] = binding.wrappedValue
                            }
                        } else {
                            if coord.ballsRows.indices.contains(row) && coord.ballsRows[row].indices.contains(col) {
                                coord.ballsRows[row][col] = binding.wrappedValue
                            }
                        }
                    }
                }
                .onReceive(
                    (topRowCoordinator?
                        .$ballsRows
                        .receive(on: RunLoop.main)
                        .map { $0 }
                        .eraseToAnyPublisher())
                    ?? Just([[String]]())
                        .eraseToAnyPublisher()
                ) { rows in
                    guard (1...3).contains(row), rows.indices.contains(row), rows[row].indices.contains(col) else { return }
                    let v = rows[row][col]
                    if binding.wrappedValue != v { binding.wrappedValue = v }
                }
                // Inserted onReceive for ballsTopRow per instructions
                .onReceive(
                    (topRowCoordinator?
                        .$ballsTopRow
                        .receive(on: RunLoop.main)
                        .eraseToAnyPublisher())
                    ?? Just([String]()).eraseToAnyPublisher()
                ) { row0 in
                    guard row == 0, row0.indices.contains(col) else { return }
                    let v = row0[col]
                    if binding.wrappedValue != v { binding.wrappedValue = v }
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: gridColumns, spacing: 0) {
                ForEach(0..<(3 * 4), id: \.self) { index in
                    let r = index / 3
                    let c = index % 3
                    cellBinding(row: r, col: c, binding: $grid[r][c])
                }
            }
        }
    }
}





