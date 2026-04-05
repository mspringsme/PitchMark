//
//  TemplateEditorView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/30/25.
//
import SwiftUI
import UIKit
import Combine

// MARK: - PNG Rendering & Share Sheet
extension View {
    func renderAsPNG(size: CGSize, scale: CGFloat = 3.0, alignment: Alignment = .center) -> UIImage? {
        let renderer = ImageRenderer(
            content: self.frame(width: size.width, height: size.height, alignment: alignment)
        )
        renderer.scale = scale
        return renderer.uiImage
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

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
    
    private func formatWithInterpunct(_ raw: String) -> String {
        let chars = Array(raw)
        guard chars.count > 1 else { return raw }
        return chars.map(String.init).joined(separator: "·")
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
        return formatWithInterpunct(String(result))
    }
    
    // MARK: - Body rows (rows 1..3)
    // Sanitize: up to 3 uppercase alnum
    func sanitizeBodyInput(_ value: String) -> String {
        let raw = String(alnumOnlyUppercased(value).prefix(3))
        return formatWithInterpunct(raw)
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
            let formatted = formatWithInterpunct(colFiltered)
            if strikeRows.indices.contains(row) && strikeRows[row].indices.contains(c) {
                strikeRows[row][c] = formatted
            }
            if ballsRows.indices.contains(row) && ballsRows[row].indices.contains(c) {
                ballsRows[row][c] = formatted
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
        // Randomize two-character pairs, avoiding ambiguous letters/digits.
        // Excludes digits 0/1 and letters that look/sound like numbers (O, I, S, Z, B, G, Q).
        let safeDigits = Array("23456789")
        let safeLetters = Array("AFHJKLMPQRSTVWXY")
        let pool = safeDigits + safeLetters

        func randomPair(excluding used: Set<Character>, maxLetters: Int) -> String {
            var attempts = 0
            while attempts < 80 {
                attempts += 1

                var a: Character?
                var b: Character?

                switch maxLetters {
                case ...0:
                    if let da = safeDigits.randomElement(), let db = safeDigits.randomElement() {
                        a = da; b = db
                    }
                case 1:
                    let useLetterFirst = Bool.random()
                    if useLetterFirst {
                        if let la = safeLetters.randomElement(), let db = safeDigits.randomElement() {
                            a = la; b = db
                        }
                    } else {
                        if let da = safeDigits.randomElement(), let lb = safeLetters.randomElement() {
                            a = da; b = lb
                        }
                    }
                default:
                    if let pa = pool.randomElement(), let pb = pool.randomElement() {
                        a = pa; b = pb
                    }
                }

                guard let a, let b else { continue }
                if a == b { continue }
                if used.contains(a) || used.contains(b) { continue }
                return String([a, b])
            }

            // Fallback to digits-only (duplicates allowed if needed)
            let a = safeDigits.randomElement() ?? "2"
            let b = safeDigits.first(where: { $0 != a }) ?? "3"
            return String([a, b])
        }

        func fill(isStrike: Bool, lettersUsed: inout Int) {
            for col in 0..<3 {
                let used = usedAlnum(excluding: isStrike, index: col)
                let lettersRemaining = max(0, 4 - lettersUsed)
                var raw = randomPair(excluding: used, maxLetters: lettersRemaining)

                var sanitized = sanitizeTopRowInput(isStrike: isStrike, index: col, newValue: raw)
                var addedLetters = sanitized.filter { safeLetters.contains($0) }.count

                // If sanitization reintroduces too many letters, force digits-only
                if lettersUsed + addedLetters > 4 {
                    raw = randomPair(excluding: used, maxLetters: 0)
                    sanitized = sanitizeTopRowInput(isStrike: isStrike, index: col, newValue: raw)
                    addedLetters = sanitized.filter { safeLetters.contains($0) }.count
                }

                // Absolute fallback: if sanitization removes everything, keep digits-only raw
                if sanitized.isEmpty {
                    sanitized = formatWithInterpunct(raw)
                    addedLetters = sanitized.filter { safeLetters.contains($0) }.count
                }

                lettersUsed += addedLetters
                if isStrike {
                    if strikeTopRow.indices.contains(col) { strikeTopRow[col] = sanitized }
                } else {
                    if ballsTopRow.indices.contains(col) { ballsTopRow[col] = sanitized }
                }
            }
        }

        var lettersUsed = 0
        fill(isStrike: true, lettersUsed: &lettersUsed)
        fill(isStrike: false, lettersUsed: &lettersUsed)
    }
    // Populate rows 1..3 in both grids with sequential two-digit codes, repeating across columns but unique per row and never repeating down
    func randomizeBodyRowsWithSequentialPairs() {
        // Build ascending sequential digit pairs with wrap from 9->0 (01,12,...,89,90)
        var pairs: [String] = []
        for i in 0..<10 {
            let next = (i + 1) % 10
            pairs.append("\(i)\(next)")
        }
        
        // Helper to extract the two digits as Characters
        func digits(of s: String) -> (Character, Character)? {
            guard s.count == 2, let a = s.first, let b = s.last, a.isNumber, b.isNumber else { return nil }
            return (a, b)
        }
        
        // Find three pairs that do not share any digit among them (six distinct digits total)
        var picked: [String] = []
        var usedDigits: Set<Character> = []
        let shuffled = pairs.shuffled()
        
        for first in shuffled {
            guard let (f1, f2) = digits(of: first) else { continue }
            let used1: Set<Character> = [f1, f2]
            for second in shuffled where second != first {
                guard let (s1, s2) = digits(of: second) else { continue }
                if used1.contains(s1) || used1.contains(s2) { continue }
                var used2 = used1
                used2.insert(s1); used2.insert(s2)
                for third in shuffled where third != first && third != second {
                    guard let (t1, t2) = digits(of: third) else { continue }
                    if used2.contains(t1) || used2.contains(t2) { continue }
                    picked = [first, second, third]
                    usedDigits = used2
                    usedDigits.insert(t1); usedDigits.insert(t2)
                    break
                }
                if picked.count == 3 { break }
            }
            if picked.count == 3 { break }
        }
        
        // Fallback: if not found (should be rare), greedily pick without digit overlap where possible
        if picked.count < 3 {
            picked.removeAll()
            usedDigits.removeAll()
            for p in shuffled {
                guard let (d1, d2) = digits(of: p) else { continue }
                if usedDigits.contains(d1) || usedDigits.contains(d2) { continue }
                picked.append(p)
                usedDigits.insert(d1); usedDigits.insert(d2)
                if picked.count == 3 { break }
            }
        }
        
        // Absolute safety: if still < 3, fill with any remaining pairs (won't happen realistically)
        var idx = 0
        while picked.count < 3 && idx < pairs.count {
            let cand = pairs[idx]
            if !picked.contains(cand) { picked.append(cand) }
            idx += 1
        }
        
        // Assign to rows 1..3, mirror across all three columns, for both strike and balls grids
        for r in 1...3 {
            let value = picked[r - 1]
            let formatted = formatWithInterpunct(value)
            for c in 0..<3 {
                if strikeRows.indices.contains(r) && strikeRows[r].indices.contains(c) {
                    strikeRows[r][c] = formatted
                }
                if ballsRows.indices.contains(r) && ballsRows[r].indices.contains(c) {
                    ballsRows[r][c] = formatted
                }
            }
        }
    }
    
    // Added clear helper for intent clarity
    func clearAll() {
        strikeTopRow = Array(repeating: "", count: 3)
        ballsTopRow = Array(repeating: "", count: 3)
        strikeRows = Array(repeating: Array(repeating: "", count: 3), count: 4)
        ballsRows = Array(repeating: Array(repeating: "", count: 3), count: 4)
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

private enum GridPaletteColor: String, CaseIterable, Identifiable {
    case red
    case black
    case green
    case white
    case blue

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: return .red
        case .black: return .black
        case .green: return .green
        case .white: return .white
        case .blue: return .blue
        }
    }
}

private struct AnimatedGridShieldOverlay: View {
    let baseSizeScale: CGFloat

    @State private var offsetX: CGFloat = 0
    @State private var offsetY: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1
    @State private var hasStarted = false

    var body: some View {
        GeometryReader { proxy in
            Image(systemName: "bubbles.and.sparkles.fill")
                .font(.system(size: min(proxy.size.width, proxy.size.height) * baseSizeScale, weight: .bold))
                .foregroundStyle(Color(.systemGray4))
                .shadow(color: Color(.systemGray5), radius: 12, x: 0, y: 0)
                .scaleEffect(scale)
                .rotationEffect(.degrees(rotation))
                .offset(x: offsetX, y: offsetY)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .onAppear {
                    guard !hasStarted else { return }
                    hasStarted = true
                    animateToNextPosition(in: proxy.size)
                }
        }
    }

    private func animateToNextPosition(in size: CGSize) {
        let xRange = max(12, size.width * 0.14)
        let yRange = max(10, size.height * 0.14)

        withAnimation(.easeInOut(duration: Double.random(in: 1.8...3.0))) {
            offsetX = CGFloat.random(in: -xRange...xRange)
            offsetY = CGFloat.random(in: -yRange...yRange)
            rotation = Double.random(in: -18...18)
            scale = CGFloat.random(in: 0.9...1.12)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 2.0...3.2)) {
            animateToNextPosition(in: size)
        }
    }
}

private enum ShieldedGridTarget {
    case top
    case strikes
    case balls
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
    @State private var showRandomConfirm = false
    @State private var showClearConfirm = false
    @State private var hasAnyPitchInTopRow = false
    @State private var showNoPitchAlert = false
    @State private var hiddenShieldTarget: ShieldedGridTarget? = nil
    @State private var shieldRestoreWorkItem: DispatchWorkItem? = nil
    @State private var showProPaywall = false
    private let showGridShieldOverlays = false
    @State private var showProPitchLimitAlert = false

    private let freePitchLimit = 2
    
    // Added new states for encrypted share sheet
    
    @State private var randomizeFirstColumnAction: (() -> Void)? = nil
    @State private var clearPitchGridAction: (() -> Void)? = nil
    @State private var pitchGridSnapshotProvider: (() -> (headers: [PitchHeader], grid: [[String]]))? = nil
    
    // Added new states for initial snapshot injection
    @State private var initialPitchGridHeaders: [PitchHeader]? = nil
    @State private var initialPitchGridValues: [[String]]? = nil
    @State private var gridPaletteSelections: [GridPaletteColor?] = Array(repeating: nil, count: 5)
    
    @StateObject private var topRowCoordinator = TopRowValidationCoordinator()
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
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
        if !subscriptionManager.isPro && selectedPitches.count > freePitchLimit {
            showProPaywall = true
            return
        }

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
        
        // Collect encrypted grid states
        let snapshot = pitchGridSnapshotProvider?()
        let headers: [PitchHeader] = snapshot?.headers ?? []
        let gridValues: [[String]] = snapshot?.grid ?? []
        
        let strikeTop = topRowCoordinator.strikeTopRow
        let strikeRows = topRowCoordinator.strikeRows
        let ballsTop = topRowCoordinator.ballsTopRow
        let ballsRows = topRowCoordinator.ballsRows
        let pitchFirstColors = gridPaletteSelections.prefix(2).compactMap { $0?.rawValue }
        let locationFirstColors = gridPaletteSelections.suffix(3).compactMap { $0?.rawValue }
        
        let newTemplate = PitchTemplate(
            id: templateID,
            name: name,
            pitches: Array(selectedPitches),
            codeAssignments: codeAssignments,
            pitchGridHeaders: headers,
            pitchGridValues: gridValues,
            strikeTopRow: strikeTop,
            strikeRows: strikeRows,
            ballsTopRow: ballsTop,
            ballsRows: ballsRows,
            pitchFirstColors: pitchFirstColors,
            locationFirstColors: locationFirstColors
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
        let initialPalette = Self.paletteSelections(from: template)
        
        _name = State(initialValue: initialName)
        _selectedPitches = State(initialValue: initialPitches)
        _codeAssignments = State(initialValue: initialAssignments)
        _customPitches = State(initialValue: (template?.pitches ?? []).filter { !pitchOrder.contains($0) })
        _gridPaletteSelections = State(initialValue: initialPalette)
        self.templateID = id
        
    }

    private static func paletteSelections(from template: PitchTemplate?) -> [GridPaletteColor?] {
        let pitchColors = template?.pitchFirstColors ?? []
        let locationColors = template?.locationFirstColors ?? []
        let names = Array(pitchColors.prefix(2)) + Array(locationColors.prefix(3))
        var selections = names.map { GridPaletteColor(rawValue: $0.lowercased()) }
        while selections.count < 5 {
            selections.append(nil)
        }
        return Array(selections.prefix(5))
    }
    
    private var availablePitches: [String] {
        // Base pitch order followed by any custom pitches the user adds
        pitchOrder + customPitches
    }
    
    private func addCustomPitch() {
        let trimmed = customPitchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if !subscriptionManager.isPro && selectedPitches.count >= freePitchLimit {
            showProPaywall = true
            return
        }
        
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

    private func availablePaletteColors(for index: Int) -> [GridPaletteColor] {
        let used = Set(
            gridPaletteSelections.enumerated().compactMap { offset, selection in
                offset == index ? nil : selection
            }
        )
        return GridPaletteColor.allCases.filter { !used.contains($0) }
    }

    private func autoFillPaletteSelections() {
        let topIndices = [0, 1]
        let bottomIndices = [2, 3, 4]
        let topComplete = topIndices.allSatisfy { gridPaletteSelections[$0] != nil }
        let bottomComplete = bottomIndices.allSatisfy { gridPaletteSelections[$0] != nil }

        var selections = gridPaletteSelections
        let selected = Set(selections.compactMap { $0 })
        let remaining = GridPaletteColor.allCases.filter { !selected.contains($0) }
        var remainingIterator = remaining.makeIterator()

        if topComplete {
            for index in bottomIndices where selections[index] == nil {
                selections[index] = remainingIterator.next()
            }
        }

        if bottomComplete {
            for index in topIndices where selections[index] == nil {
                selections[index] = remainingIterator.next()
            }
        }

        gridPaletteSelections = selections
    }

    private func randomizePaletteSelections() {
        let shuffled = GridPaletteColor.allCases.shuffled()
        gridPaletteSelections = shuffled.map { Optional($0) }
    }

    private func noteGridInteraction(_ target: ShieldedGridTarget) {
        shieldRestoreWorkItem?.cancel()
        hiddenShieldTarget = target

        let workItem = DispatchWorkItem {
            hiddenShieldTarget = nil
            shieldRestoreWorkItem = nil
        }
        shieldRestoreWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: workItem)
    }

    @ViewBuilder
    private func palettePickerButton(at index: Int) -> some View {
        Menu {
            ForEach(availablePaletteColors(for: index)) { option in
                Button {
                    gridPaletteSelections[index] = option
                    autoFillPaletteSelections()
                } label: {
                    Label(option.rawValue.capitalized, systemImage: "circle.fill")
                        .foregroundStyle(option.color)
                }
            }
            if gridPaletteSelections[index] != nil {
                Button("Clear") {
                    gridPaletteSelections[index] = nil
                }
            }
        } label: {
            Circle()
                .fill(gridPaletteSelections[index]?.color ?? .white)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .stroke(Color.black, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private var topGridPickerRow: some View {
        HStack(alignment: .center, spacing: 14) {
            ForEach(0..<2, id: \.self) { index in
                palettePickerButton(at: index)
            }
        }
    }

    private var bottomGridPickerRow: some View {
        HStack(alignment: .center, spacing: 14) {
            ForEach(2..<5, id: \.self) { index in
                palettePickerButton(at: index)
            }
        }
    }

    private var palettePickerColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<5, id: \.self) { index in
                if index == 2 {
                    Spacer()
                        .frame(height: 40)
                }
                palettePickerButton(at: index)
            }
        }
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 3)
    }

    private var gridEditorContent: some View {
        HStack(spacing: 0) {
            palettePickerColumn
                .padding(.top, 32)
                .frame(width: 60, alignment: .leading)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                GeometryReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Spacer(minLength: 0)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Pitch Selection")
                                    .font(.caption)
                                    .foregroundColor(.black)
                                    .padding(.top, 20)
                                    .padding(.bottom, -2)
                                    .frame(maxWidth: .infinity, alignment: .center)

                                PitchGridView2(
                                    availablePitches: availablePitches,
                                    hasAnyPitchInTopRow: $hasAnyPitchInTopRow,
                                    showProPitchLimitAlert: $showProPitchLimitAlert,
                                    onProvideRandomizeAction: { action in
                                        self.randomizeFirstColumnAction = action
                                    },
                                    onProvideClearAction: { action in
                                        self.clearPitchGridAction = action
                                    },
                                    onProvideSnapshot: { provider in
                                        self.pitchGridSnapshotProvider = provider
                                    },
                                    initialHeaders: initialPitchGridHeaders,
                                    initialGrid: initialPitchGridValues
                                )
                                .simultaneousGesture(
                                    TapGesture().onEnded {
                                        noteGridInteraction(.top)
                                    }
                                )
                                .overlay {
                                    if showGridShieldOverlays && hiddenShieldTarget != .top {
                                        ZStack {
                                            AnimatedGridShieldOverlay(baseSizeScale: 0.44)
                                                .offset(x: -44)
                                            AnimatedGridShieldOverlay(baseSizeScale: 0.44)
                                                .offset(x: 44)
                                        }
                                    }
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .frame(minWidth: proxy.size.width)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 170)

                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        VStack {
                            StrikeLocationGridView()
                                .environment(\.topRowCoordinator, topRowCoordinator)
                                .padding(.top, 8)
                                .simultaneousGesture(
                                    TapGesture().onEnded {
                                        noteGridInteraction(.strikes)
                                    }
                                )
                                .overlay {
                                    if showGridShieldOverlays && hiddenShieldTarget != .strikes {
                                        AnimatedGridShieldOverlay(baseSizeScale: 0.52)
                                    }
                                }
                            Text("Strikes")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.black)
                                .padding(.top, -2)
                        }
                        VStack {
                            BallsLocationGridView()
                                .environment(\.topRowCoordinator, topRowCoordinator)
                                .padding(.top, 8)
                                .simultaneousGesture(
                                    TapGesture().onEnded {
                                        noteGridInteraction(.balls)
                                    }
                                )
                                .overlay {
                                    if showGridShieldOverlays && hiddenShieldTarget != .balls {
                                        AnimatedGridShieldOverlay(baseSizeScale: 0.52)
                                    }
                                }
                            Text("Balls")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.black)
                                .padding(.top, -2)
                        }
                    }
                }
            }
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity)
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
                    sectionCard {
                        VStack(spacing: 8) {
                            Text("Template Name")
                                .font(.system(size: 10))
                                .foregroundStyle(.black)
                            TextField("Tap to name your grid key", text: $name)
                                .focused($nameFieldFocused)
                                .submitLabel(.done)
                                .onSubmit { nameFieldFocused = false }
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity)
                                .bold()
                                .foregroundColor(.blue)
                                // Add some right padding so text doesn't run under the icon
                                .padding(.trailing, 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(Color.blue.opacity(nameFieldFocused ? 0.9 : 0.35), lineWidth: 1.5)
                                        )
                                )
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
                        }
                    }

                    sectionCard {
                        VStack(spacing: 8) {
                            Text("Pitcher's Pitches")
                                .font(.system(size: 10))
                                .foregroundStyle(.black)
                            HStack(spacing: 8) {
                                Menu {
                                    ForEach(availablePitches, id: \.self) { pitch in
                                        let isSelected = selectedPitches.contains(pitch)
                                        Button(action: {
                                            if isSelected {
                                                selectedPitches.remove(pitch)
                                            } else {
                                                if !subscriptionManager.isPro && selectedPitches.count >= freePitchLimit {
                                                    showProPaywall = true
                                                    return
                                                }
                                                selectedPitches.insert(pitch)
                                            }
                                        }) {
                                            Label(pitch, systemImage: isSelected ? "checkmark" : "")
                                        }
                                    }
                                } label: {
                                    let title = "Pitches"
                                    HStack(spacing: 8) {
                                        Text(title)
                                            .font(.subheadline)
                                            .foregroundColor(.black)
                                            .lineLimit(1)
                                        Image(systemName: "chevron.down")
                                            .font(.caption)
                                            .foregroundColor(.black)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.clear)
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.black, lineWidth: 1)
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
                        }
                    }
                    
                    // Encrypted template: show pitch grid editor
                    Text("Pitcher's Pitches Grid Key")
                        .font(.title3)
                        .foregroundColor(.black)
                        .padding(.top, 4)
                        .padding(.bottom, -2)
                    // 3 grids
                    gridEditorContent
                    
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
                                    topRowCoordinator.randomizeBodyRowsWithSequentialPairs()
                                    randomizePaletteSelections()
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
                                    topRowCoordinator.clearAll()
                                    clearPitchGridAction?()
                                    gridPaletteSelections = Array(repeating: nil, count: 5)
                                    hasAnyPitchInTopRow = false
                                }
                                Button("Cancel", role: .cancel) { }
                            } message: {
                                Text("This will remove all values from your grids. This action cannot be undone.")
                            }
                        }
                        .padding(.horizontal)
                        Spacer()
                    }
                    .sheet(isPresented: $showProPaywall) {
                        ProPaywallView(
                            title: "PitchMark Pro",
                            message: "Add more than two pitches to grid keys with PitchMark Pro.",
                            allowsClose: true
                        )
                    }
                    .alert("Upgrade to Pro", isPresented: $showProPitchLimitAlert) {
                        Button("Not Now", role: .cancel) { }
                        Button("Upgrade") { showProPaywall = true }
                    } message: {
                        Text("Adding more than two pitches to a grid key is available with PitchMark Pro.")
                    }
                    Spacer()
                    
                    
                    Spacer()
                    
                }
                .padding(.horizontal)
                .task {
                    let loaded = await authManager.loadTemplate(id: templateID.uuidString)
                    guard let t = loaded else { return }

                    // already on main actor because the async loader returns via MainActor.run
                    self.name = t.name
                    self.codeAssignments = t.codeAssignments
                    self.selectedPitches = Self.loadActivePitches(for: t.id, fallback: t.pitches)
                    self.customPitches = t.pitches.filter { !pitchOrder.contains($0) }
                    self.initialPitchGridHeaders = t.pitchGridHeaders
                    self.initialPitchGridValues = t.pitchGridValues

                    if t.strikeTopRow.count == 3 { self.topRowCoordinator.strikeTopRow = t.strikeTopRow }
                    if t.ballsTopRow.count == 3 { self.topRowCoordinator.ballsTopRow = t.ballsTopRow }
                    if t.strikeRows.count == 4 { self.topRowCoordinator.strikeRows = t.strikeRows }
                    if t.ballsRows.count == 4 { self.topRowCoordinator.ballsRows = t.ballsRows }
                    self.gridPaletteSelections = Self.paletteSelections(from: t)
                }

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
                    Button(action: {
                        showSaveAlert = true
                    }) {
                        Image(systemName: "xmark")
                            .imageScale(.medium)
                            .padding(8)
                    }
                    .accessibilityLabel("Close without saving")
                }
            }
        }
        .alert("Unsaved Changes", isPresented: $showSaveAlert) {
            Button("Keep Editing", role: .cancel) { }
            Button("Close Without Saving", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("You have not saved this grid key. Are you sure you want to close?")
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

struct CodeAssignmentPanelWithPrint: View {
    @Binding var selectedCodes: Set<String>
    @Binding var selectedPitch: String
    @Binding var selectedLocation: String
    @Binding var pitchCodeAssignments: [PitchCodeAssignment]
    
    let allPitches: [String]
    let allLocations: [String]
    let assignAction: () -> Void
    
    @State private var showShare = false
    @State private var pngImage: UIImage?
    
    // 3.5" × 2.75" at 72pt per inch ~= 252×198pt; rendering uses scale for higher DPI
    private let cardSize = CGSize(width: 252, height: 198)
    
    private func presentPrintSheet(for image: UIImage) {
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .photo
        printInfo.jobName = "PitchMark Codes"
        
        let printController = UIPrintInteractionController.shared
        printController.printInfo = printInfo
        printController.printingItem = image
        printController.present(animated: true, completionHandler: nil)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Original panel content
            CodeAssignmentPanel(
                selectedCodes: $selectedCodes,
                selectedPitch: $selectedPitch,
                selectedLocation: $selectedLocation,
                pitchCodeAssignments: $pitchCodeAssignments,
                allPitches: allPitches,
                allLocations: allLocations,
                assignAction: assignAction
            )
            .background(Color.white)
            
            // Export PNG button
            Button {
                let view = CodeAssignmentPanel(
                    selectedCodes: $selectedCodes,
                    selectedPitch: $selectedPitch,
                    selectedLocation: $selectedLocation,
                    pitchCodeAssignments: $pitchCodeAssignments,
                    allPitches: allPitches,
                    allLocations: allLocations,
                    assignAction: assignAction
                )
                if let img = view.renderAsPNG(size: cardSize, scale: 3.0) {
                    pngImage = img
                    showShare = true
                }
            } label: {
                Text("Export PNG")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.blue, lineWidth: 1)
                    )
            }
            
            // Print button
            Button {
                let view = CodeAssignmentPanel(
                    selectedCodes: $selectedCodes,
                    selectedPitch: $selectedPitch,
                    selectedLocation: $selectedLocation,
                    pitchCodeAssignments: $pitchCodeAssignments,
                    allPitches: allPitches,
                    allLocations: allLocations,
                    assignAction: assignAction
                )
                if let img = view.renderAsPNG(size: cardSize, scale: 3.0) {
                    presentPrintSheet(for: img)
                }
            } label: {
                Text("Print")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.blue, lineWidth: 1)
                    )
            }
        }
        .padding()
        .sheet(isPresented: $showShare) {
            if let pngImage {
                ShareSheet(items: [pngImage])
            }
        }
    }
}

// MARK: - Supporting Views Restored

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
                        Rectangle()
                            .stroke(Color.black, lineWidth: 2)
                            .frame(width: zoneWidth, height: zoneHeight)
                            .position(x: originX + zoneWidth / 2, y: originY + zoneHeight / 2)
                        
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
                        Rectangle()
                            .stroke(Color.black, lineWidth: 2)
                            .frame(width: zoneWidth, height: zoneHeight)
                            .position(x: originX + zoneWidth / 2, y: originY + zoneHeight / 2)
                        
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

// MARK: - PitchGrid and Location Grids Restored

struct PitchGridView2: View {
    let availablePitches: [String]
    @Binding var hasAnyPitchInTopRow: Bool
    @Binding var showProPitchLimitAlert: Bool
    var onProvideRandomizeAction: ((@escaping () -> Void) -> Void)? = nil
    var onProvideClearAction: ((@escaping () -> Void) -> Void)? = nil
    var onProvideSnapshot: (((@escaping () -> (headers: [PitchHeader], grid: [[String]]))) -> Void)? = nil

    @EnvironmentObject var subscriptionManager: SubscriptionManager

    private let freePitchLimit = 2
    
    var initialHeaders: [PitchHeader]? = nil
    var initialGrid: [[String]]? = nil
    
    @State private var abbreviations: [String: String] = [:]
    @State private var showAbbrevEditorForIndex: Int? = nil
    @State private var pendingAbbreviation: String = ""
    
    private let maxAssignedPitches = 7
    
    private let cellWidth: CGFloat = 46
    private let cellHeight: CGFloat = 30
    
    @State private var grid: [[String]] = Array(repeating: ["", ""], count: 4)
    
    private var assignedHeaderCount: Int {
        grid[0].dropFirst().filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }
    
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: grid[0].count)
    }
    
    private func displayName(for pitch: String) -> String {
        if let abbr = abbreviations[pitch], !abbr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return abbr
        }
        return pitch
    }
    
    private func expandGridIfNeeded(col: Int) {
        let lastCol = grid[0].count - 1
        guard col == lastCol, !grid[0][col].isEmpty else { return }
        guard assignedHeaderCount < maxAssignedPitches else { return }
        for r in 0..<grid.count { grid[r].append("") }
    }
    
    private func removeColumn(at col: Int) {
        guard grid.first?.indices.contains(col) == true else { return }
        for r in 0..<grid.count { grid[r].remove(at: col) }
        while grid.first?.count ?? 0 < 2 { for r in 0..<grid.count { grid[r].append("") } }
        while let first = grid.first, first.count > 2 {
            let lastIndex = first.count - 1
            let isLastEmpty = (0..<grid.count).allSatisfy { grid[$0][lastIndex].isEmpty }
            if isLastEmpty { for r in 0..<grid.count { grid[r].remove(at: lastIndex) } } else { break }
        }
    }
    
    private func baseCell<Content: View>(
        strokeColor: Color = .blue,
        lineWidth: CGFloat = 1.0,
        @ViewBuilder content: () -> Content
    ) -> some View {
        return ZStack { content() }
            .frame(width: cellWidth, height: cellHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(strokeColor, lineWidth: lineWidth)
            )
    }

    private func displayAttributedText(for raw: String, isBold: Bool) -> AttributedString {
        let cleaned = String(alnumOnlyUppercased(raw).prefix(3))
        let text = cleaned.map(String.init).joined(separator: "·")
        var result = AttributedString(text)
        result.foregroundColor = .black
        return result
    }
    
    private func digits(in string: String) -> [Character] { string.filter { $0.isNumber } }
    
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

    private func formatWithInterpunct(_ raw: String) -> String {
        let chars = Array(raw)
        guard chars.count > 1 else { return raw }
        return chars.map(String.init).joined(separator: "·")
    }
    
    private func usedCharsInRowNonLeftmost(row: Int, excludingCol excludedCol: Int) -> Set<Character> {
        var set: Set<Character> = []
        guard row >= 0, row < grid.count else { return set }
        for c in 1..<(grid[row].count) {
            if c == excludedCol { continue }
            for ch in alnumOnlyUppercased(grid[row][c]) { set.insert(ch) }
        }
        return set
    }
    
    private func sanitizeNonLeftmostBodyCell(row: Int, col: Int, newValue: String) -> String {
        guard row >= 1, row <= 3, col > 0 else { return newValue }
        let used = usedCharsInRowNonLeftmost(row: row, excludingCol: col)
        let onlyAlnum = String(alnumOnlyUppercased(newValue).prefix(3))
        var result: [Character] = []
        for ch in onlyAlnum {
            if used.contains(ch) { continue }
            if result.contains(ch) { continue }
            result.append(ch)
        }
        return formatWithInterpunct(String(result))
    }
    
    private func sanitizeFirstColumnInput(row: Int, newValue: String) -> String {
        let onlyDigits = String(digits(in: newValue).prefix(3))
        let chars = Array(onlyDigits)
        let existingInOtherRowsCol0 = columnZeroDigits(excludingRow: row)
        var result: [Character] = []
        for ch in chars {
            if existingInOtherRowsCol0.contains(ch) { continue }
            if result.contains(ch) { continue }
            result.append(ch)
        }
        return formatWithInterpunct(String(result))
    }
    
    func randomizeFirstColumn() {
        let hasAtLeastOnePitchColumn = grid[0].count > 1 && grid[0].dropFirst().contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard hasAtLeastOnePitchColumn else { return }
        
        var usedValues: Set<String> = []
        for r in 0..<grid.count {
            for c in 0..<grid[r].count {
                let v = grid[r][c].trimmingCharacters(in: .whitespacesAndNewlines)
                if !v.isEmpty { usedValues.insert(v) }
            }
        }
        for r in 1...3 { usedValues.remove(grid[r][0].trimmingCharacters(in: .whitespacesAndNewlines)) }
        
        var candidates: [String] = []
        for tens in 0...9 {
            for ones in 0...9 where ones != tens {
                let diff = abs(ones - tens)
                if diff == 1 { candidates.append(String(format: "%d%d", tens, ones)) }
            }
        }
        candidates = candidates.filter { !usedValues.contains($0) }
        candidates.shuffle()
        
        func digits(of s: String) -> (Character, Character)? {
            guard s.count == 2, let first = s.first, let last = s.last, first.isNumber, last.isNumber else { return nil }
            return (first, last)
        }
        
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
        
        for r in 1...3 { grid[r][0] = formatWithInterpunct(picked[r - 1]) }
        randomizeSubsequentColumns()
    }
    
    func randomizeSubsequentColumns() {
        let columnCount = grid.first?.count ?? 0
        guard columnCount > 1 else { return }
        let assignedColumns: [Int] = (1..<columnCount).filter { c in !grid[0][c].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !assignedColumns.isEmpty else { return }
        var rowUsed: [Int: Set<String>] = [1: [], 2: [], 3: []]
        for c in assignedColumns {
            for r in 1...3 {
                let allDigits = (0...9).map { String($0) }
                let candidates = allDigits.filter { !(rowUsed[r]?.contains($0) ?? false) }
                let chosen = (candidates.randomElement() ?? allDigits.randomElement()) ?? "0"
                grid[r][c] = formatWithInterpunct(chosen)
                rowUsed[r, default: []].insert(chosen)
            }
        }
    }
    
    func clearAll() {
        grid = Array(repeating: ["", ""], count: 4)
        abbreviations.removeAll()
        hasAnyPitchInTopRow = false
    }
    
    private func buildHeadersFromTopRow() -> [PitchHeader] {
        guard !grid.isEmpty else { return [] }
        var result: [PitchHeader] = []
        let headerRow = grid[0]
        for c in 1..<headerRow.count {
            let pitchName = headerRow[c].trimmingCharacters(in: .whitespacesAndNewlines)
            if pitchName.isEmpty { continue }
            let abbr = abbreviations[pitchName]
            result.append(PitchHeader(pitch: pitchName, abbreviation: abbr))
        }
        return result
    }
    
    private func headerCell(col: Int, binding: Binding<String>) -> some View {
        let isEmpty = binding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shouldGate = isEmpty && !subscriptionManager.isPro && assignedHeaderCount >= freePitchLimit

        return baseCell(strokeColor: .black) {
            if shouldGate {
                Button {
                    showProPitchLimitAlert = true
                } label: {
                    Text("+")
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(minWidth: 44, minHeight: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(availablePitches, id: \.self) { pitch in
                        Button {
                            let wasEmpty = binding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            if wasEmpty && assignedHeaderCount >= maxAssignedPitches { return }
                            if wasEmpty && !subscriptionManager.isPro && assignedHeaderCount >= freePitchLimit {
                                showProPitchLimitAlert = true
                                return
                            }
                            binding.wrappedValue = pitch
                            expandGridIfNeeded(col: col)
                            hasAnyPitchInTopRow = grid[0].dropFirst().contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        } label: {
                            HStack {
                                Text(pitch)
                                if binding.wrappedValue == pitch { Spacer(); Image(systemName: "checkmark") }
                            }
                        }
                    }
                    
                    if !binding.wrappedValue.isEmpty {
                        Button(role: .destructive) { removeColumn(at: col) } label: { Label("Remove Column", systemImage: "minus.circle") }
                        Divider()
                        Button { pendingAbbreviation = abbreviations[binding.wrappedValue] ?? ""; showAbbrevEditorForIndex = col } label: { Label("Edit Abbreviation", systemImage: "character.cursor.ibeam") }
                        if abbreviations[binding.wrappedValue] != nil {
                            Button(role: .destructive) { abbreviations[binding.wrappedValue] = nil } label: { Label("Clear Abbreviation", systemImage: "trash") }
                        }
                    }
                } label: {
                    Text(binding.wrappedValue.isEmpty ? "+" : displayName(for: binding.wrappedValue))
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(minWidth: 44, minHeight: 30)
                        .contentShape(Rectangle())
                }
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
            Button("Cancel", role: .cancel) { showAbbrevEditorForIndex = nil }
        } message: { Text("Enter a short label to display for this pitch.") }
    }
    
    private func cellBinding(row: Int, col: Int) -> some View {
        let binding = Binding(
            get: { grid[row][col] },
            set: { newValue in
                if col == 0 {
                    let sanitized = sanitizeFirstColumnInput(row: row, newValue: newValue)
                    grid[row][col] = sanitized
                } else {
                    let sanitized = sanitizeNonLeftmostBodyCell(row: row, col: col, newValue: newValue)
                    grid[row][col] = sanitized
                }
                if row == 0 { expandGridIfNeeded(col: col) }
            }
        )
        
        if row == 0 && col > 0 { return AnyView(headerCell(col: col, binding: binding)) }
        if row > 0 && col > 0 {
            let isPlusColumn = col == grid[0].count - 1 && grid[0][col].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if isPlusColumn && !subscriptionManager.isPro && assignedHeaderCount >= freePitchLimit {
                return AnyView(
                    baseCell(strokeColor: .blue) {
                        Text("")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showProPitchLimitAlert = true
                    }
                )
            }
        }
        let stroke: Color = (row == 0 || col == 0) ? .black : .blue
        let width: CGFloat = (col == 0 && row > 0) ? 2.0 : 1.0
        return AnyView(
            baseCell(strokeColor: stroke, lineWidth: width) {
                ZStack {
                    TextField("", text: binding)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .fontWeight((row == 0 || col == 0) ? .bold : .regular)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundColor(.clear)
                        .tint(.blue)
                    Text(displayAttributedText(for: binding.wrappedValue, isBold: row == 0 || col == 0))
                        .fontWeight((row == 0 || col == 0) ? .bold : .regular)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                }
            }
        )
    }

    private func leftColumnCell(row: Int) -> some View {
        let binding = Binding(
            get: { grid[row][0] },
            set: { newValue in
                let sanitized = sanitizeFirstColumnInput(row: row, newValue: newValue)
                grid[row][0] = sanitized
            }
        )
        let stroke: Color = (row == 0) ? .black : .black
        let width: CGFloat = (row > 0) ? 2.0 : 1.0
        return baseCell(strokeColor: stroke, lineWidth: width) {
            ZStack {
                TextField("", text: binding)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .fontWeight(row == 0 ? .bold : .bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundColor(.clear)
                    .tint(.blue)
                Text(displayAttributedText(for: binding.wrappedValue, isBold: true))
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            }
        }
    }

    private func dataCell(row: Int, col: Int) -> some View {
        let binding = Binding(
            get: { grid[row][col] },
            set: { newValue in
                let sanitized = sanitizeNonLeftmostBodyCell(row: row, col: col, newValue: newValue)
                grid[row][col] = sanitized
                if row == 0 { expandGridIfNeeded(col: col) }
            }
        )
        if row == 0 { return AnyView(headerCell(col: col, binding: binding)) }
        let isPlusColumn = col == grid[0].count - 1 && grid[0][col].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isPlusColumn && !subscriptionManager.isPro && assignedHeaderCount >= freePitchLimit {
            return AnyView(
                baseCell(strokeColor: .blue) {
                    Text("")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    showProPitchLimitAlert = true
                }
            )
        }
        let stroke: Color = (row == 0) ? .black : .blue
        return AnyView(
            baseCell(strokeColor: stroke, lineWidth: 1.0) {
                ZStack {
                    TextField("", text: binding)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .fontWeight(row == 0 ? .bold : .regular)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundColor(.clear)
                        .tint(.blue)
                    Text(displayAttributedText(for: binding.wrappedValue, isBold: row == 0))
                        .fontWeight(row == 0 ? .bold : .regular)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                }
            }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let spacerWidth: CGFloat = 5
            let gridColumnCount = max(grid[0].count - 1, 1)
            let columns: [GridItem] = [
                GridItem(.fixed(cellWidth), spacing: 0),
                GridItem(.fixed(spacerWidth), spacing: 0)
            ] + Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: gridColumnCount)

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(0..<grid.count, id: \.self) { r in
                    ForEach(0..<(gridColumnCount + 2), id: \.self) { c in
                        if c == 1 {
                            Color.clear
                                .frame(width: spacerWidth, height: cellHeight)
                        } else if c == 0 {
                            if r == 0 {
                                ZStack { Color.clear }
                                    .frame(width: cellWidth, height: cellHeight)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.clear))
                            } else {
                                leftColumnCell(row: r)
                            }
                        } else {
                            let dataCol = c - 1
                            dataCell(row: r, col: dataCol)
                        }
                    }
                }
            }
            .onAppear {
                if let ih = initialHeaders, let ig = initialGrid { applySnapshot(headers: ih, grid: ig) }
                hasAnyPitchInTopRow = grid[0].dropFirst().contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                onProvideRandomizeAction?(self.randomizeFirstColumn)
                onProvideClearAction?(self.clearAll)
                onProvideSnapshot?({ let headers = buildHeadersFromTopRow(); let snapshotGrid = grid; return (headers, snapshotGrid) })
            }
            .onChange(of: initialHeaders?.map { $0.pitch + ( $0.abbreviation ?? "" ) } ?? []) { _, _ in
                if let ih = initialHeaders, let ig = initialGrid { applySnapshot(headers: ih, grid: ig) }
            }
            .onChange(of: initialGrid?.flatMap { $0 } ?? []) { _, _ in
                if let ih = initialHeaders, let ig = initialGrid { applySnapshot(headers: ih, grid: ig) }
            }
            .onChange(of: grid) { _, _ in
                hasAnyPitchInTopRow = grid[0].dropFirst().contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                onProvideRandomizeAction?(self.randomizeFirstColumn)
                onProvideClearAction?(self.clearAll)
                onProvideSnapshot?({ let headers = buildHeadersFromTopRow(); let snapshotGrid = grid; return (headers, snapshotGrid) })
            }
        }
    }
    
    func applySnapshot(headers: [PitchHeader], grid snapshot: [[String]]) {
        var newAbbr: [String: String] = [:]
        for h in headers { if let ab = h.abbreviation { newAbbr[h.pitch] = ab } }
        abbreviations = newAbbr
        if snapshot.count == 4 && snapshot.allSatisfy({ !$0.isEmpty }) {
            grid = snapshot
        } else {
            grid = Array(repeating: ["", ""], count: 4)
        }
        hasAnyPitchInTopRow = grid[0].dropFirst().contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct StrikeLocationGridView: View {
    let cellWidth: CGFloat = 46
    let cellHeight: CGFloat = 30
    @State private var grid: [[String]] = Array(repeating: Array(repeating: "", count: 3), count: 4)
    
    @Environment(\.topRowCoordinator) private var topRowCoordinator
    
    private var gridColumns: [GridItem] { Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: 3) }

    private func formatWithInterpunct(_ raw: String) -> String {
        let chars = Array(raw)
        guard chars.count > 1 else { return raw }
        return chars.map(String.init).joined(separator: "·")
    }
    
    private func baseCell<Content: View>(
        strokeColor: Color = .green,
        lineWidth: CGFloat = 1.0,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack { content() }
            .frame(width: cellWidth, height: cellHeight)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(strokeColor, lineWidth: lineWidth))
    }
    
    private func cellBinding(row: Int, col: Int, binding: Binding<String>) -> some View {
        let stroke: Color = (row == 0) ? .black : .green
        let width: CGFloat = (row == 0) ? 2.0 : 1.0
        return baseCell(strokeColor: stroke, lineWidth: width) {
            ZStack {
                TextField("", text: Binding(
                    get: { binding.wrappedValue },
                    set: { newValue in
                        if row == 0, let coord = topRowCoordinator {
                            let sanitized = coord.sanitizeTopRowInput(isStrike: true, index: col, newValue: newValue)
                            binding.wrappedValue = sanitized
                            if coord.strikeTopRow.indices.contains(col) { coord.strikeTopRow[col] = sanitized }
                        } else if let coord = topRowCoordinator {
                            coord.setBodyRowMirrored(row: row, col: col, rawValue: newValue)
                        } else {
                            let raw = String(alnumOnlyUppercased(newValue).prefix(3))
                            binding.wrappedValue = formatWithInterpunct(raw)
                        }
                    }
                ))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .fontWeight(row == 0 ? .bold : .regular)
                .padding(.horizontal, 0)
                .foregroundColor(.clear)
                .tint(.blue)
                    Text(formatWithInterpunct(String(alnumOnlyUppercased(binding.wrappedValue).prefix(3))))
                        .fontWeight(row == 0 ? .bold : .regular)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                }
                .onAppear {
                    if let coord = topRowCoordinator {
                        if row == 0 {
                            if coord.strikeTopRow.indices.contains(col) { coord.strikeTopRow[col] = binding.wrappedValue }
                        } else {
                            if coord.strikeRows.indices.contains(row) && coord.strikeRows[row].indices.contains(col) { coord.strikeRows[row][col] = binding.wrappedValue }
                        }
                    }
                }
                .onReceive((topRowCoordinator?.$strikeRows.receive(on: RunLoop.main).map { $0 }.eraseToAnyPublisher()) ?? Just([[String]]()).eraseToAnyPublisher()) { rows in
                    guard (1...3).contains(row), rows.indices.contains(row), rows[row].indices.contains(col) else { return }
                    let v = rows[row][col]
                    if binding.wrappedValue != v { binding.wrappedValue = v }
                }
                .onReceive((topRowCoordinator?.$strikeTopRow.receive(on: RunLoop.main).eraseToAnyPublisher()) ?? Just([String]()).eraseToAnyPublisher()) { row0 in
                    guard row == 0, row0.indices.contains(col) else { return }
                    let v = row0[col]
                    if binding.wrappedValue != v { binding.wrappedValue = v }
                }
        }
        .padding(.bottom, row == 0 ? 5 : 0)
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
    let cellWidth: CGFloat = 46
    let cellHeight: CGFloat = 30
    @State private var grid: [[String]] = Array(repeating: Array(repeating: "", count: 3), count: 4)
    
    @Environment(\.topRowCoordinator) private var topRowCoordinator
    
    private var gridColumns: [GridItem] { Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: 3) }

    private func formatWithInterpunct(_ raw: String) -> String {
        let chars = Array(raw)
        guard chars.count > 1 else { return raw }
        return chars.map(String.init).joined(separator: "·")
    }
    
    private func baseCell<Content: View>(
        strokeColor: Color = .red,
        lineWidth: CGFloat = 1.0,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack { content() }
            .frame(width: cellWidth, height: cellHeight)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(strokeColor, lineWidth: lineWidth))
    }
    
    private func cellBinding(row: Int, col: Int, binding: Binding<String>) -> some View {
        if row == 2 && col == 1 {
            return AnyView(
                baseCell(strokeColor: .red) {
                    ZStack { Color.green; Text("") }
                }
                    .allowsHitTesting(false)
            )
        }
        let stroke: Color = (row == 0) ? .black : .red
        let width: CGFloat = (row == 0) ? 2.0 : 1.0
        return AnyView(
            baseCell(strokeColor: stroke, lineWidth: width) {
                ZStack {
                    TextField("", text: Binding(
                        get: { binding.wrappedValue },
                        set: { newValue in
                            if row == 0, let coord = topRowCoordinator {
                                let sanitized = coord.sanitizeTopRowInput(isStrike: false, index: col, newValue: newValue)
                                binding.wrappedValue = sanitized
                                if coord.ballsTopRow.indices.contains(col) { coord.ballsTopRow[col] = sanitized }
                            } else if let coord = topRowCoordinator {
                                coord.setBodyRowMirrored(row: row, col: col, rawValue: newValue)
                            } else {
                                let raw = String(alnumOnlyUppercased(newValue).prefix(3))
                                binding.wrappedValue = formatWithInterpunct(raw)
                            }
                        }
                    ))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .fontWeight(row == 0 ? .bold : .regular)
                    .padding(.horizontal, 0)
                    .foregroundColor(.clear)
                    .tint(.blue)
                    Text(formatWithInterpunct(String(alnumOnlyUppercased(binding.wrappedValue).prefix(3))))
                        .fontWeight(row == 0 ? .bold : .regular)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .allowsHitTesting(false)
                }
                .onAppear {
                    if let coord = topRowCoordinator {
                        if row == 0 {
                            if coord.ballsTopRow.indices.contains(col) { coord.ballsTopRow[col] = binding.wrappedValue }
                        } else {
                            if coord.ballsRows.indices.contains(row) && coord.ballsRows[row].indices.contains(col) { coord.ballsRows[row][col] = binding.wrappedValue }
                        }
                    }
                }
                .onReceive((topRowCoordinator?.$ballsRows.receive(on: RunLoop.main).map { $0 }.eraseToAnyPublisher()) ?? Just([[String]]()).eraseToAnyPublisher()) { rows in
                    guard (1...3).contains(row), rows.indices.contains(row), rows[row].indices.contains(col) else { return }
                    let v = rows[row][col]
                    if binding.wrappedValue != v { binding.wrappedValue = v }
                }
                .onReceive((topRowCoordinator?.$ballsTopRow.receive(on: RunLoop.main).eraseToAnyPublisher()) ?? Just([String]()).eraseToAnyPublisher()) { row0 in
                    guard row == 0, row0.indices.contains(col) else { return }
                    let v = row0[col]
                    if binding.wrappedValue != v { binding.wrappedValue = v }
                }
            }
            .padding(.bottom, row == 0 ? 5 : 0)
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

import SwiftUI

/// PRINT-ONLY view for your encrypted template.
/// Works with the EXACT data shapes you're already using:
/// - `grid` from PitchGridView2 snapshot (4 rows, N cols)
/// - `strikeTopRow` / `ballsTopRow` = 3 strings
/// - `strikeRows` / `ballsRows` = 4 rows x 3 cols (rows 1..3 used; row 0 ignored)
/// - Skips printing the trailing "+" pitch column (if present in grid[0].last)
struct PrintableEncryptedGridsView: View {
    let grid: [[String]]

    let strikeTopRow: [String]
    let strikeRows: [[String]]   // expects count == 4, uses rows 1..3

    let ballsTopRow: [String]
    let ballsRows: [[String]]    // expects count == 4, uses rows 1..3
    let pitchFirstColors: [String]
    let locationFirstColors: [String]
    let outerPadding: CGFloat
    let scale: CGFloat
    let textScale: CGFloat
    
    // Your screenshot has a fixed green block in Balls at (row 2, col 1) in the 4x3 grid
    // (i.e., body row 2, col 1). Keep this default for drop-in compatibility.
    let selectedBallBodyCell: (row: Int, col: Int) = (1, 1)
    
    private let baseBodyFontSize: CGFloat = 18
    private let baseHeaderFontSize: CGFloat = 22
    private let basePrintFontSize: CGFloat = 20
    private let baseCellW: CGFloat = 70
    private let baseCellH: CGFloat = 48
    private let baseCorner: CGFloat = 10
    private let baseLineW: CGFloat = 2.0

    init(
        grid: [[String]],
        strikeTopRow: [String],
        strikeRows: [[String]],
        ballsTopRow: [String],
        ballsRows: [[String]],
        pitchFirstColors: [String] = [],
        locationFirstColors: [String] = [],
        outerPadding: CGFloat = 24,
        scale: CGFloat = 1.0,
        textScale: CGFloat = 1.0
    ) {
        self.grid = grid
        self.strikeTopRow = strikeTopRow
        self.strikeRows = strikeRows
        self.ballsTopRow = ballsTopRow
        self.ballsRows = ballsRows
        self.pitchFirstColors = pitchFirstColors
        self.locationFirstColors = locationFirstColors
        self.outerPadding = outerPadding
        self.scale = scale
        self.textScale = textScale
    }
    
    private let baseTopBlockHeight: CGFloat = 228
    private let baseBottomBlockHeight: CGFloat = 214
    
    private var scaled: CGFloat { max(scale, 0.1) }
    private func s(_ value: CGFloat) -> CGFloat { value * scaled }
    
    private var bodyFontSize: CGFloat { baseBodyFontSize * scaled * textScale }
    private var headerFontSize: CGFloat { baseHeaderFontSize * scaled * textScale }
    private var printFontSize: CGFloat { basePrintFontSize * scaled * textScale }
    private var cellW: CGFloat { baseCellW * scaled }
    private var cellH: CGFloat { baseCellH * scaled }
    private var corner: CGFloat { baseCorner * scaled }
    private var lineW: CGFloat { baseLineW * scaled }
    private var topBlockHeight: CGFloat { baseTopBlockHeight * scaled }
    private var bottomBlockHeight: CGFloat { baseBottomBlockHeight * scaled }

    static func baseContentSize(for grid: [[String]]) -> CGSize {
        let cellW: CGFloat = 70
        let cellH: CGFloat = 48
        let topBlockHeight: CGFloat = 228
        let bottomBlockHeight: CGFloat = 214
        let paletteWidth: CGFloat = 24
        let paletteHeight = topBlockHeight + bottomBlockHeight + 22

        let headerRow = grid.first ?? [""]
        let lastIsPlus = headerRow.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "+"
        let pitchCols = max(0, headerRow.count - 1 - (lastIsPlus ? 1 : 0))
        let leftSpacerWidth: CGFloat = 5
        let gridWidth = (cellW * CGFloat(max(1, pitchCols + 1))) + leftSpacerWidth

        let pitchTitleHeight = UIFont.systemFont(ofSize: 18, weight: .medium).lineHeight
        let pitchBlockHeight = pitchTitleHeight + 8 + (cellH * 4)

        let locationTitleHeight = UIFont.systemFont(ofSize: 16, weight: .regular).lineHeight
        let locationBlockHeight = (cellH * 4) + 8 + locationTitleHeight + 5
        let locationsWidth = (cellW * 3 * 2) + 50

        let rightWidth = max(gridWidth, locationsWidth)
        let rightHeight = pitchBlockHeight + 22 + locationBlockHeight + 4

        let totalWidth = paletteWidth + 28 + rightWidth
        let totalHeight = max(paletteHeight, rightHeight)
        return CGSize(width: totalWidth, height: totalHeight)
    }

    var body: some View {
        HStack(alignment: .top, spacing: s(28)) {
            palettePreviewColumn()

            VStack(alignment: .leading, spacing: s(22)) {
                pitchSelectionBlock()

                HStack(alignment: .top, spacing: s(50)) {
                    locationBlock(
                        title: "Strikes",
                        header: strikeTopRow,
                        rows: strikeRows,
                        border: .green,
                        highlightBodyCell: nil
                    )
                    
                    locationBlock(
                        title: "Balls",
                        header: ballsTopRow,
                        rows: ballsRows,
                        border: .red,
                        highlightBodyCell: selectedBallBodyCell
                    )
                }
                .padding(.top, s(4))
            }
        }
        .padding(outerPadding * scaled)
        .background(Color.white)
        .foregroundColor(.black)
    }
}

private extension PrintableEncryptedGridsView {
    func palettePreviewColumn() -> some View {
        VStack(spacing: s(22)) {
            VStack(spacing: s(14)) {
                ForEach(0..<2, id: \.self) { index in
                    palettePreviewCircle(at: index)
                }
            }
            .frame(width: s(24), height: topBlockHeight, alignment: .center)

            VStack(spacing: s(14)) {
                ForEach(2..<5, id: \.self) { index in
                    palettePreviewCircle(at: index)
                }
            }
            .frame(width: s(24), height: bottomBlockHeight, alignment: .center)
        }
    }

    func palettePreviewCircle(at index: Int) -> some View {
        Circle()
            .fill(palettePreviewColor(at: index))
            .frame(width: s(24), height: s(24))
            .overlay(
                Circle()
                    .stroke(Color.black, lineWidth: s(1.5))
            )
    }

    func palettePreviewColor(at index: Int) -> Color {
        if index < 2, pitchFirstColors.indices.contains(index) {
            return templatePaletteColor(pitchFirstColors[index])
        }

        let locationIndex = index - 2
        if locationIndex >= 0, locationFirstColors.indices.contains(locationIndex) {
            return templatePaletteColor(locationFirstColors[locationIndex])
        }

        return .white
    }
}

// MARK: - Pitch Selection (top table)

private extension PrintableEncryptedGridsView {
    
    func pitchSelectionBlock() -> some View {
        Group {
            guard grid.count >= 2, let headerRow = grid.first else { return AnyView(EmptyView()) }
            
            let pitchCols = printablePitchColumnCount(from: headerRow) // excludes leading "" and trailing "+"
            let headers = printablePitchHeaders(from: headerRow)        // size == pitchCols
            
            let leftSpacerWidth = s(5)
            return AnyView(
                VStack(alignment: .center, spacing: s(8)) {
                    Text("Pitch Selection")
                        .font(.system(size: s(18), weight: .medium))
                        .foregroundColor(.black)
                    
                    VStack(spacing: 0) {
                        // Header row: blank borderless + pitch headers
                        HStack(spacing: 0) {
                            cell("", stroke: .clear, fill: .clear, bold: false, borderless: true)
                            Color.clear
                                .frame(width: leftSpacerWidth, height: cellH)
                            
                            ForEach(headers.indices, id: \.self) { i in
                                cell(headers[i], stroke: .black, fill: .white, bold: true)
                            }
                        }
                        
                        // Body rows (print rows 1..3 if present)
                        ForEach(1..<min(grid.count, 4), id: \.self) { r in
                            HStack(spacing: 0) {
                                // Left label (col 0)
                                cell(value(in: grid, row: r, col: 0), stroke: .black, fill: .white, bold: true, emphasized: true)
                                Color.clear
                                    .frame(width: leftSpacerWidth, height: cellH)
                                
                                // Code columns (col 1...pitchCols) — this automatically skips the "+" col
                                ForEach(1...pitchCols, id: \.self) { c in
                                    cell(value(in: grid, row: r, col: c), stroke: .blue, fill: .white, bold: false)
                                }
                            }
                        }
                    }
                }
            )
        }
    }
}

// MARK: - Locations (Strikes / Balls)

private extension PrintableEncryptedGridsView {
    
    func locationBlock(
        title: String,
        header: [String],
        rows: [[String]],
        border: Color,
        highlightBodyCell: (row: Int, col: Int)?
    ) -> some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                // Header row (3)
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { c in
                        cell(
                            header.indices.contains(c) ? header[c] : "",
                            stroke: .black,
                            fill: .white,
                            bold: true,
                            emphasized: true
                        )
                    }
                }
                .padding(.bottom, s(5))
                
                // Body rows correspond to rows[1], rows[2], rows[3] in your coordinator storage.
                // We render them as bodyRowIndex 0..2, mapping to sourceRow = bodyRowIndex + 1.
                ForEach(0..<3, id: \.self) { bodyRow in
                    let sourceRow = bodyRow + 1
                    
                    HStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { c in
                            let isHighlighted = (highlightBodyCell?.row == bodyRow && highlightBodyCell?.col == c)
                            
                            let txt: String = {
                                guard rows.indices.contains(sourceRow),
                                      rows[sourceRow].indices.contains(c)
                                else { return "" }
                                return rows[sourceRow][c]
                            }()
                            
                            cell(
                                isHighlighted ? "" : txt,
                                stroke: border,
                                fill: isHighlighted ? .green : .white,
                                bold: false
                            )
                        }
                    }
                }
            }
            
        Text(title)
                .font(.system(size: s(16)))
                .foregroundColor(.black)
        }
    }
}

// MARK: - Cell + Utilities

private extension PrintableEncryptedGridsView {
    
    func cell(
        _ text: String,
        stroke: Color,
        fill: Color,
        bold: Bool,
        emphasized: Bool = false,
        borderless: Bool = false
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner)
                .fill(borderless ? Color.clear : fill)
            
            if !borderless {
                RoundedRectangle(cornerRadius: corner)
                    .stroke(stroke, lineWidth: lineW)
            }
            
            if !text.isEmpty {
                Text(text)
                    .font(
                        .system(
                            size: emphasized ? headerFontSize : bodyFontSize,
                            weight: bold ? .bold : .regular,
                            design: .rounded
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: cellW, height: cellH)
    }
    
    
    func value(in grid: [[String]], row: Int, col: Int) -> String {
        guard grid.indices.contains(row), grid[row].indices.contains(col) else { return "" }
        return grid[row][col]
    }
    
    /// Printable pitch columns = headerRow count minus:
    /// - leading "" at col 0
    /// - trailing "+" if present as last header cell
    func printablePitchColumnCount(from headerRow: [String]) -> Int {
        guard headerRow.count >= 2 else { return 0 }
        let lastIsPlus = headerRow.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "+"
        let printable = headerRow.count - 1 - (lastIsPlus ? 1 : 0)
        return max(0, printable)
    }
    
    /// Returns headers excluding leading "" and excluding trailing "+"
    func printablePitchHeaders(from headerRow: [String]) -> [String] {
        let n = printablePitchColumnCount(from: headerRow)
        guard n > 0, headerRow.count >= n + 1 else { return [] }
        return Array(headerRow[1...n])
    }
}
