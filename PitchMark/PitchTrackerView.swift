//
//  ContentView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/16/25.
//

import SwiftUI
import FirebaseCore
import FirebaseFirestore
import UniformTypeIdentifiers
import UIKit

private extension Notification.Name {
    static let gameOrSessionChosen = Notification.Name("gameOrSessionChosen")
    static let gameOrSessionDeleted = Notification.Name("gameOrSessionDeleted")
}

// 🧩 Toggle Chip Component
struct ToggleChip: View {
    let pitch: String
    @Binding var selectedPitches: Set<String>
    var template: PitchTemplate?
    var codeAssignments: [PitchCodeAssignment] = []
    
    @State private var showColorPicker = false
    @State private var tempColor: Color = .blue
    
    var isSelected: Bool {
        selectedPitches.contains(pitch)
    }
    
    var isInTemplate: Bool {
        template?.pitches.contains(pitch) == true
    }
    
    var assignedCodeCount: Int {
        codeAssignments.filter { $0.pitch == pitch }.count
    }
    
    @ViewBuilder
    private var codeBadge: some View {
        if assignedCodeCount > 0 {
            let chipColor = colorForPitch(pitch)
            let badgeBackground = isSelected ? chipColor : chipColor.opacity(0.25)

            Text("\(assignedCodeCount)")
                .font(.caption2)
                .foregroundColor(.white)
                .padding(4)
                .background(badgeBackground)
                .clipShape(Circle())
                .offset(x: 1, y: -12)
        }
    }
    
    var body: some View {
        let chipColor = colorForPitch(pitch)
        let isActive = isSelected
        let bgColor = chipColor.opacity(isActive ? 1.0 : 0.2)
        let shadowColor = isActive ? chipColor.opacity(0.4) : .clear

        return Text(pitch)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(bgColor)
            .foregroundColor(.white)
            .cornerRadius(16)
            .shadow(color: shadowColor, radius: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(1.0), lineWidth: isActive ? 1.5 : 0)
            )
            .overlay(codeBadge, alignment: .topTrailing)
            .gesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in
                        // Long press: open color picker
                        tempColor = chipColor
                        showColorPicker = true
                    }
                    .exclusively(before: TapGesture().onEnded {
                        // Tap: toggle activate/deactivate
                        if isSelected {
                            selectedPitches.remove(pitch)
                        } else {
                            selectedPitches.insert(pitch)
                        }
                    })
            )
            .sheet(isPresented: $showColorPicker) {
                VStack(spacing: 12) {
                    Text("Choose a color for \(pitch)").font(.headline)
                    ColorPicker("Color", selection: $tempColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .center)
                    HStack {
                        Button("Cancel") { showColorPicker = false }
                        Spacer()
                        Button("Save") {
                            setPitchColorOverride(pitch: pitch, color: tempColor)
                            // Notify the app that a pitch color changed so views can refresh
                            NotificationCenter.default.post(name: .pitchColorDidChange, object: pitch)
                            showColorPicker = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .presentationDetents([.fraction(0.25), .medium])
            }
    }
}

struct PitchTrackerView: View {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var showCodeAssignmentSheet = false
    @State private var pitcherName: String = ""
    @State private var selectedPitches: Set<String> = []
    @State private var calledPitch: PitchCall? = nil
    @State private var lastTappedPosition: CGPoint? = nil
    @State private var batterSide: BatterSide = .right
    @State private var pitchCodeAssignments: [PitchCodeAssignment] = []
    @State private var selectedCode: String = ""
    @State private var selectedPitch: String = ""
    @State private var selectedLocation: String = ""
    @State private var gameIsActive: Bool = false
    @State private var showSettings = false
    @State private var showProfile = false
    @State private var templates: [PitchTemplate] = []
    @EnvironmentObject var authManager: AuthManager
    @State private var showProfileSheet = false
    @State private var showSignOutConfirmation = false
    @State private var selectedTemplate: PitchTemplate? = nil
    @State private var showTemplateEditor = false
    @State private var isRecordingResult = false
    @State private var activeCalledPitchId: String? = nil
    @State private var actualLocationRecorded: String? = nil
    @State private var resultVisualState: String? = nil
    @State private var pendingResultLabel: String? = nil
    @State private var showResultConfirmation = false
    @State private var isGameMode: Double = 1
    @StateObject var sessionManager = PitchSessionManager()
    @State private var modeSliderValue: Double = 0 // 0 = practice, 1 = game
    @State private var pitchEvents: [PitchEvent] = []
    @State private var games: [Game] = []
    @State private var showPitchResults = false
    @State private var filterMode: PitchMode? = nil
    @State private var showTemplateStatsSheet = false
    @State private var menuSelectedStatsTemplate: PitchTemplate?
    @State private var showConfirmSheet = false
    @State private var isStrikeSwinging = false
    @State private var isStrikeLooking = false
    @State private var isWildPitch = false
    @State private var isPassedBall = false
    @State private var isBall = false
    @State private var isCalledPitchViewVisible = false
    @State private var shouldBlurBackground = false
    @State private var isGame = false
    @State private var selectedOutcome: String? = nil
    @State private var selectedDescriptor: String? = nil
    @State private var isError: Bool = false
    @State private var showGameSheet = false
    @State private var opponentName: String? = nil
    @State private var selectedGameId: String? = nil
    
    @State private var showPracticeSheet = false
    @State private var practiceName: String? = nil
    @State private var selectedPracticeId: String? = nil
    
    @State private var jerseyCells: [JerseyCell] = sampleJerseyCells
    @State private var draggingJersey: JerseyCell?
    @State private var showAddJerseyPopover = false
    @State private var newJerseyNumber: String = ""
    @State private var selectedBatterId: UUID? = nil
    @FocusState private var jerseyInputFocused: Bool
    
    @State private var editingCell: JerseyCell?
    @State private var pitchesFacedBatterId: UUID? = nil

    @State private var isReorderingMode: Bool = false
    @State private var colorRefreshToken = UUID()
    @State private var hasPresentedInitialSettings = false

    @State private var suppressNextGameSheet = false

    fileprivate enum OverlayTab { case cards, progress }
    @State private var overlayTab: OverlayTab = .progress

    fileprivate enum DefaultsKeys {
        static let lastTemplateId = "lastTemplateId"
        static let lastBatterSide = "lastBatterSide"
        static let lastMode = "lastMode"
        static let activePitchesPrefix = "activePitches."
        static let lastView = "lastView"
        static let activeGameId = "activeGameId"
        static let activeIsPractice = "activeIsPractice"
        static let activePracticeId = "activePracticeId"
        static let storedPracticeSessions = "storedPracticeSessions"
    }
    
    // MARK: - Persistence
    private func persistSelectedTemplate(_ template: PitchTemplate?) {
        let defaults = UserDefaults.standard
        if let id = template?.id.uuidString {
            defaults.set(id, forKey: DefaultsKeys.lastTemplateId)
        } else {
            defaults.removeObject(forKey: DefaultsKeys.lastTemplateId)
        }
    }

    private func persistBatterSide(_ side: BatterSide) {
        UserDefaults.standard.set(side == .left ? "left" : "right", forKey: DefaultsKeys.lastBatterSide)
    }

    private func persistMode(_ mode: PitchMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKeys.lastMode)
    }

    private func restorePersistedState(loadedTemplates: [PitchTemplate]) {
        let defaults = UserDefaults.standard
        // Restore template
        if let idString = defaults.string(forKey: DefaultsKeys.lastTemplateId),
           let template = loadedTemplates.first(where: { $0.id.uuidString == idString }) {
            selectedTemplate = template
            selectedPitches = loadActivePitches(for: template.id, fallback: template.pitches)
            pitchCodeAssignments = template.codeAssignments
        }
        // Restore batter side
        if let sideString = defaults.string(forKey: DefaultsKeys.lastBatterSide) {
            batterSide = (sideString == "left") ? .left : .right
        }
        // Restore mode
        if let modeString = defaults.string(forKey: DefaultsKeys.lastMode),
           let restoredMode = PitchMode(rawValue: modeString) {
            sessionManager.switchMode(to: restoredMode)
            isGame = (restoredMode == .game)
        }
    }
    
    // MARK: - Active Pitches Overrides (per-template)
    private func persistActivePitches(for templateId: UUID, active: Set<String>) {
        let key = DefaultsKeys.activePitchesPrefix + templateId.uuidString
        UserDefaults.standard.set(Array(active), forKey: key)
    }

    private func loadActivePitches(for templateId: UUID, fallback: [String]) -> Set<String> {
        let key = DefaultsKeys.activePitchesPrefix + templateId.uuidString
        if let arr = UserDefaults.standard.stringArray(forKey: key) {
            return Set(arr)
        }
        return Set(fallback)
    }
    
    // Helper property to merge pitchOrder with template-specific custom pitches
    fileprivate var orderedPitchesForTemplate: [String] {
        let base = pitchOrder
        let extras = selectedTemplate.map { tmpl in
            tmpl.pitches.filter { !pitchOrder.contains($0) }
        } ?? []
        return base + extras
    }
    
    // MARK: - Practice Sessions Persistence (local)
    private func savePracticeSessions(_ sessions: [PracticeSession]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(sessions) {
            UserDefaults.standard.set(data, forKey: DefaultsKeys.storedPracticeSessions)
        }
    }

    private func loadPracticeSessions() -> [PracticeSession] {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKeys.storedPracticeSessions) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([PracticeSession].self, from: data)) ?? []
    }

    private func persistActivePracticeId(_ id: String?) {
        let defaults = UserDefaults.standard
        if let id = id { defaults.set(id, forKey: DefaultsKeys.activePracticeId) }
        else { defaults.removeObject(forKey: DefaultsKeys.activePracticeId) }
    }

    private func restoreActivePracticeSelection() {
        let defaults = UserDefaults.standard
        if let pid = defaults.string(forKey: DefaultsKeys.activePracticeId) {
            let sessions = loadPracticeSessions()
            if let session = sessions.first(where: { $0.id == pid }) {
                selectedPracticeId = session.id
                practiceName = session.name
            }
        }
    }
    
    // MARK: - Preview-friendly initializer
    // Allows previews to seed internal @State with dummy data without affecting app code
    init(
        previewTemplate: PitchTemplate? = nil,
        previewTemplates: [PitchTemplate] = [],
        previewIsGame: Bool = false
    ) {
        if let t = previewTemplate {
            _selectedTemplate = State(initialValue: t)
            _selectedPitches = State(initialValue: Set(t.pitches))
            _pitchCodeAssignments = State(initialValue: t.codeAssignments)
        }
        _templates = State(initialValue: previewTemplates)
        _isGame = State(initialValue: previewIsGame)
    }
    
    // MARK: - Helpers for Pitches Faced Popover
    private func normalizeJersey(_ s: String?) -> String? {
        guard let s = s else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let noLeadingZeros = trimmed.drop { $0 == "0" }
        return String(noLeadingZeros.isEmpty ? "0" : noLeadingZeros)
    }

    private var selectedJerseyNumberDisplay: String? {
        jerseyCells.first(where: { $0.id == selectedBatterId })?.jerseyNumber
    }

    private var pitchesFacedTitle: String {
        if let num = selectedJerseyNumberDisplay, !num.isEmpty {
            return "Pitches Faced – #\(num)"
        }
        return "Pitches Faced"
    }

    private var filteredPitchesFacedEvents: [PitchEvent] {
        let batterIdStr = selectedBatterId?.uuidString
        let normalizedSelectedJersey = normalizeJersey(selectedJerseyNumberDisplay)

        return pitchEvents
            .filter { event in
                if let gid = selectedGameId, event.gameId != gid { return false }
                if let idStr = batterIdStr, let evId = event.opponentBatterId, evId == idStr { return true }
                if let selJersey = normalizedSelectedJersey, let evJersey = normalizeJersey(event.opponentJersey), selJersey == evJersey {
                    return true
                }
                return false
            }
            .sorted { lhs, rhs in
                lhs.timestamp > rhs.timestamp
            }
    }
    
    @ViewBuilder
    private var chooseResultPrompt: some View {
        let shouldShowChooseResultText = isRecordingResult && pendingResultLabel == nil
        if shouldShowChooseResultText {
            Text("Choose a Pitch Result")
                .opacity(shouldShowChooseResultText ? 1 : 0)
                .scaleEffect(shouldShowChooseResultText ? 1.05 : 1)
                .shadow(color: .yellow.opacity(shouldShowChooseResultText ? 0.3 : 0), radius: 4)
                .animation(.easeInOut(duration: 0.3), value: shouldShowChooseResultText)
                .padding(.top, 4)
        }
    }
    
    
    
    private var cardsAndOverlay: some View {
        ZStack {
            VStack(spacing: 8) {
                // Top toggle buttons
                HStack(spacing: 8) {
                    Spacer()

                    Button(action: { overlayTab = .progress }) {
                        Text("Progress")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(overlayTab == .progress ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(overlayTab == .progress ? Color.accentColor : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: { overlayTab = .cards }) {
                        Text("Cards")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(overlayTab == .cards ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(overlayTab == .cards ? Color.accentColor : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 4)

                // Content switches with tab
                Group {
                    switch overlayTab {
                    case .cards:
                        VStack {
                            if selectedTemplate != nil {
                                PitchResultSheet(
                                    allEvents: pitchEvents,
                                    games: games,
                                    templates: templates,
                                    filterMode: $filterMode
                                )
                                .environmentObject(authManager)
                            }
                        }
                    case .progress:
                        VStack(spacing: 12) {
                            // Placeholder progress content — replace with your real progress view as needed
                            Image(systemName: "chart.bar.xaxis")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("Progress")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Add your progress visualization here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.top, 12)
                    }
                }
            }
            .blur(radius: shouldBlurBackground ? 6 : 0)
            .animation(.easeInOut(duration: 0.2), value: shouldBlurBackground)
            .transition(.opacity)

            Group {
                if let call = calledPitch {
                    CalledPitchView(
                        isRecordingResult: $isRecordingResult,
                        activeCalledPitchId: $activeCalledPitchId,
                        call: call,
                        pitchCodeAssignments: pitchCodeAssignments,
                        batterSide: batterSide
                    )
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(8)
                    .shadow(radius: 4)
                    .transition(.opacity)
                    .padding(.top, 4)
                    .onAppear { shouldBlurBackground = true }
                    .onDisappear { shouldBlurBackground = false }
                }
            }
        }
        // Make this layer fill the entire screen space and bleed off the edges
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: [.horizontal, .bottom])
        //.background(Color.red.opacity(0.9))
        .background(.regularMaterial)
    }
    
    
    private var headerContainer: some View {
        VStack(spacing: 8) {
            topBar
            pitchSelectionChips
        }
        .padding(.vertical, 8)
        .background(
            .thickMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous) // proper clipping for the material
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1) // optional: edge definition
        )
        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 4)
        
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    private var contentSection: some View {
        Group {
            batterAndModeBar
            mainStrikeZoneSection
            Spacer(minLength: 20)
            chooseResultPrompt
            cardsAndOverlay
        }
    }
    
    private var contentSectionDimmed: some View {
        let isDimmed = (selectedTemplate == nil)
        return contentSection
            .opacity(isDimmed ? 0.6 : 1.0)
            .blur(radius: isDimmed ? 4 : 0)
            .allowsHitTesting(!isDimmed)
            .animation(.easeInOut(duration: 0.3), value: selectedTemplate)
    }
    
    // MARK: - Extracted subviews to help type-checker
    private var topBar: some View {
        HStack {
            Menu {
                ForEach(templates, id: \.id) { template in
                    Button(template.name) {
                        selectedTemplate = template
                        selectedPitches = loadActivePitches(for: template.id, fallback: template.pitches)
                        pitchCodeAssignments = template.codeAssignments
                        // 🧹 Reset strike zone and called pitch state
                        lastTappedPosition = nil
                        calledPitch = nil
                        // 💾 Persist last used template
                        persistSelectedTemplate(template)
                    }
                }
            } label: {
                let currentLabel = selectedTemplate?.name ?? "Select a template"
                let widestLabel = ([currentLabel] + templates.map { $0.name }).max(by: { $0.count < $1.count }) ?? currentLabel

                ZStack {
                    // Invisible widest label to reserve width and prevent size jumps
                    HStack(spacing: 8) {
                        Text(widestLabel)
                            .font(.headline)
                            .opacity(0)
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .opacity(0)
                    }

                    // Visible current label
                    HStack(spacing: 8) {
                        Text(currentLabel)
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundColor(.primary)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
                .opacity(templates.isEmpty ? 0.6 : 1.0)
                .contentShape(Capsule())
                .animation(.easeInOut(duration: 0.2), value: selectedTemplate?.id)
            }
            .disabled(templates.isEmpty)

            Spacer()

            Button(action: {
                showSettings = true
            }) {
                Image(systemName: "gearshape")
                    .imageScale(.large)
            }
            .tint(.gray)
            Button(action: {
                showSignOutConfirmation = true
            }) {
                Image(systemName: "person.crop.circle")
                    .foregroundColor(.gray)
                    .imageScale(.large)
            }
            
            .accessibilityLabel("Sign Out")
            .confirmationDialog(
                "Are you sure you want to sign out of \(authManager.userEmail)?",
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    authManager.signOut()
                }
                Button("Cancel", role: .cancel) { }
            }
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }
    
    private var pitchSelectionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(orderedPitchesForTemplate, id: \.self) { pitch in
                    ToggleChip(
                        pitch: pitch,
                        selectedPitches: $selectedPitches,
                        template: selectedTemplate,
                        codeAssignments: pitchCodeAssignments
                    )
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
            .padding(.top, 10)
            .id(colorRefreshToken)
        }
    }
    
    private var mainStrikeZoneSection: some View {
        let deviceWidth = UIScreen.main.bounds.width
        let SZwidth: CGFloat = isGame ? (deviceWidth * 0.78) : (deviceWidth * 0.85)

        return VStack {
            HStack(alignment: .top, spacing: 8) {
                atBatSidebar
                strikeZoneArea(width: SZwidth)
            }
        }
        .padding(.horizontal, 12)
    }
    
    @ViewBuilder
    private var atBatSidebar: some View {
        if isGame {
            VStack(spacing: 0) {
                Text("At Bat")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.gray)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(jerseyCells) { cell in
                            JerseyRow(
                                cell: cell,
                                jerseyCells: $jerseyCells,
                                selectedBatterId: $selectedBatterId,
                                draggingJersey: $draggingJersey,
                                editingCell: $editingCell,
                                newJerseyNumber: $newJerseyNumber,
                                showAddJerseyPopover: $showAddJerseyPopover,
                                selectedGameId: selectedGameId,
                                pitchesFacedBatterId: $pitchesFacedBatterId,
                                isReordering: $isReorderingMode
                            )
                            .environmentObject(authManager)
                        }

                        if showAddJerseyPopover {
                            VStack(spacing: 6) {
                                TextField("##", text: $newJerseyNumber)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(height: 36)
                                    .focused($jerseyInputFocused)
                                    .onAppear { jerseyInputFocused = true }
                            }
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Button("Cancel") {
                                        // Dismiss without changes
                                        showAddJerseyPopover = false
                                        jerseyInputFocused = false
                                        newJerseyNumber = ""
                                        editingCell = nil
                                    }
                                    Spacer()
                                    Button("Save") {
                                        let trimmed = newJerseyNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                                        guard !trimmed.isEmpty else { return }
                                        let normalized = normalizeJersey(trimmed) ?? trimmed

                                        if let editing = editingCell, let idx = jerseyCells.firstIndex(where: { $0.id == editing.id }) {
                                            // Edit existing cell
                                            jerseyCells[idx].jerseyNumber = normalized
                                        } else {
                                            // Add new cell
                                            let newCell = JerseyCell(jerseyNumber: normalized)
                                            jerseyCells.append(newCell)
                                        }

                                        // Persist lineup if in a selected game
                                        if let gameId = selectedGameId {
                                            authManager.updateGameLineup(gameId: gameId, jerseyNumbers: jerseyCells.map { $0.jerseyNumber })
                                        }

                                        // Reset UI state
                                        showAddJerseyPopover = false
                                        jerseyInputFocused = false
                                        newJerseyNumber = ""
                                        editingCell = nil
                                    }
                                    .disabled(newJerseyNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                        }

                        Button(action: {
                            editingCell = nil
                            newJerseyNumber = ""
                            showAddJerseyPopover = true
                            jerseyInputFocused = true
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 32, height: 32)

                                Image(systemName: "plus")
                                    .foregroundColor(.secondary)
                                    .font(.headline)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 6)
                    }
                    .padding(.vertical,12)
                    .padding(.horizontal, 0)
                }
            }
            .frame(width: 60, height: 390)
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 4)
        }
    }
    
    @ViewBuilder
    private func strikeZoneArea(width SZwidth: CGFloat) -> some View {
        ZStack(alignment: .top) {
            VStack {
                StrikeZoneView(
                    width: SZwidth,
                    isGame: $isGame,
                    batterSide: batterSide,
                    lastTappedPosition: lastTappedPosition,
                    setLastTapped: { lastTappedPosition = $0 },
                    calledPitch: calledPitch,
                    setCalledPitch: { calledPitch = $0 },
                    selectedPitches: selectedPitches,
                    gameIsActive: gameIsActive,
                    selectedPitch: selectedPitch,
                    pitchCodeAssignments: pitchCodeAssignments,
                    isRecordingResult: isRecordingResult,
                    setIsRecordingResult: { isRecordingResult = $0 },
                    setActualLocation: { actualLocationRecorded = $0 },
                    actualLocationRecorded: actualLocationRecorded,
                    setSelectedPitch: { selectedPitch = $0 },
                    resultVisualState: resultVisualState,
                    setResultVisualState: { resultVisualState = $0 },
                    pendingResultLabel: $pendingResultLabel,
                    showResultConfirmation: $showResultConfirmation,
                    showConfirmSheet: $showConfirmSheet
                )
                .id(colorRefreshToken)
            }
            .frame(width: SZwidth, height: 390)
            .background(
                .thickMaterial,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous) // proper clipping for the material
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1) // optional: edge definition
            )
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 4)
            
//            .background(.regularMaterial)
//            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
//            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            
            .overlay(
                Group {
                    ResetPitchButton() {
                        isRecordingResult = false
                        selectedPitch = ""
                        selectedLocation = ""
                        lastTappedPosition = nil
                        calledPitch = nil
                        resultVisualState = nil
                        actualLocationRecorded = nil
                        pendingResultLabel = nil
                    }
                },
                alignment: .bottomLeading
            )
            .overlay(
                Group {
                    let sortedTemplates: [PitchTemplate] = {
                        guard let activeID = selectedTemplate?.id else {
                            return templates.sorted { $0.name < $1.name }
                        }
                        let others = templates.filter { $0.id != activeID }.sorted { $0.name < $1.name }
                        if let active = templates.first(where: { $0.id == activeID }) {
                            return [active] + others
                        }
                        return others
                    }()
                    ShowPitchLogTemplates(
                        sortedTemplates: sortedTemplates,
                        onSelectTemplate: { template in
                            menuSelectedStatsTemplate = template
                            showTemplateStatsSheet = true
                        }
                    )
                },
                alignment: .bottomTrailing
            )
            .overlay(
                Group {
                    Button(action: {
                        if isGame {
                            showGameSheet = true
                        } else {
                            showPracticeSheet = true
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape")
                            Text(isGame ? (opponentName ?? "Game") : (practiceName ?? "Practice"))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: 160)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .offset(y: 6)
                },
                alignment: .bottom
            )

            HStack {
                let iconSize: CGFloat = 36
                Button(action: {
                    withAnimation { batterSide = .left }
                    persistBatterSide(.left)
                }) {
                    Image("rightBatterIcon")
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: iconSize, height: iconSize)
                        .foregroundColor(batterSide == .left ? .primary : .gray.opacity(0.4))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    withAnimation { batterSide = .right }
                    persistBatterSide(.right)
                }) {
                    Image("leftBatterIcon")
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: iconSize, height: iconSize)
                        .foregroundColor(batterSide == .right ? .primary : .gray.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .frame(width: SZwidth)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .offset(y: -20)
        }
        .frame(width: SZwidth, height: 390)
    }
    
    private var batterAndModeBar: some View {
        HStack {
            Spacer()
            VStack {
                Picker("Mode", selection: $sessionManager.currentMode) {
                    Text("Practice").tag(PitchMode.practice)
                    Text("Game").tag(PitchMode.game)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)   // optional, makes it feel more compact
                .frame(width: 180)     // <- adjust this to taste
                .fixedSize(horizontal: true, vertical: false)
                .onChange(of: sessionManager.currentMode) { _, newValue in
                    sessionManager.switchMode(to: newValue)
                    persistMode(newValue)
                    if newValue == .game {
                        if suppressNextGameSheet {
                            suppressNextGameSheet = false
                            isGame = true
                        } else {
                            showGameSheet = true
                        }
                    } else {
                        // Practice mode
                        isGame = false
                        if suppressNextGameSheet {
                            suppressNextGameSheet = false
                            // Do not present because a selection was already made
                        } else {
                            showPracticeSheet = true
                        }
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.bottom, 6)
        .padding(.top, 14)
    }

    private var backgroundView: some View {
        Color.appBrandBackground
            .ignoresSafeArea()
    }

    private var mainStack: some View {
        VStack(spacing: 4) {
            headerContainer.erasedToAnyView()
            contentSectionDimmed.erasedToAnyView()
        }
    }
    
    // MARK: - Change Handlers
    private func handlePendingResultChange(_ newValue: String?) {
        // Auto-save in Practice mode without presenting the PitchResultSheetView
        guard newValue != nil else { return }
        guard sessionManager.currentMode == .practice else { return }
        guard let pitchCall = calledPitch, let label = pendingResultLabel else { return }

        // Build minimal practice event
        let event = PitchEvent(
            id: UUID().uuidString,
            timestamp: Date(),
            pitch: pitchCall.pitch,
            location: label,
            codes: pitchCall.codes,
            isStrike: pitchCall.isStrike,
            isBall: false,
            mode: sessionManager.currentMode,
            calledPitch: pitchCall,
            batterSide: batterSide,
            templateId: selectedTemplate?.id.uuidString,
            strikeSwinging: false,
            wildPitch: false,
            passedBall: false,
            strikeLooking: false,
            outcome: nil,
            descriptor: nil,
            errorOnPlay: false,
            battedBallRegion: nil,
            battedBallType: nil,
            battedBallTapX: nil,
            battedBallTapY: nil,
            gameId: nil,
            opponentJersey: nil,
            opponentBatterId: nil,
            practiceId: selectedPracticeId
        )
        event.debugLog(prefix: "📤 Auto-saving Practice PitchEvent")

        // Persist and update UI state
        authManager.savePitchEvent(event)
        sessionManager.incrementCount()
        withAnimation(.easeInOut(duration: 0.3)) {
            pitchEvents.append(event)
        }
        authManager.loadPitchEvents { events in
            self.pitchEvents = events
        }

        // Prevent sheet from showing and reset UI state (mirror sheet save reset)
        showConfirmSheet = false
        resultVisualState = event.location
        activeCalledPitchId = UUID().uuidString
        isRecordingResult = false
        selectedPitch = ""
        selectedLocation = ""
        lastTappedPosition = nil
        calledPitch = nil
        resultVisualState = nil
        actualLocationRecorded = nil
        pendingResultLabel = nil
        isStrikeSwinging = false
        isWildPitch = false
        isPassedBall = false
        isBall = false
        selectedOutcome = nil
        selectedDescriptor = nil
    }
    
    var body: some View {
        let background = backgroundView.erasedToAnyView()
        let content = mainStack.erasedToAnyView()
        let base = ZStack {
            background
            content
        }
        return base
            .frame(maxHeight: .infinity, alignment: .top)
        .erasedToAnyView()
        .onChange(of: pendingResultLabel) { _, newValue in
            handlePendingResultChange(newValue)
        }
        .onChange(of: selectedPitches) { _, newValue in
            if let template = selectedTemplate {
                persistActivePitches(for: template.id, active: newValue)
            }
        }
        .sheet(isPresented: $showGameSheet, onDismiss: {
            // If user canceled without creating/choosing, optionally revert to practice
            if sessionManager.currentMode == .game && !isGame {
                sessionManager.switchMode(to: .practice)
            }
        }) {
            GameSelectionSheet(
                onCreate: { name, date in
                    let newGame = Game(id: nil, opponent: name, date: date, jerseyNumbers: jerseyCells.map { $0.jerseyNumber }, batterIds: jerseyCells.map { $0.id.uuidString })
                    authManager.saveGame(newGame)
                },
                onChoose: { gameId in
                    authManager.loadGames { games in
                        if let game = games.first(where: { $0.id == gameId }) {
                            selectedGameId = game.id
                            opponentName = game.opponent
                            if let ids = game.batterIds, ids.count == game.jerseyNumbers.count {
                                jerseyCells = zip(ids, game.jerseyNumbers).map { (idStr, num) in
                                    JerseyCell(id: UUID(uuidString: idStr) ?? UUID(), jerseyNumber: num)
                                }
                            } else {
                                jerseyCells = game.jerseyNumbers.map { JerseyCell(jerseyNumber: $0) }
                            }
                            selectedBatterId = nil
                        }
                        isGame = true
                        // Ensure sessionManager mode sync for button label update
                        sessionManager.switchMode(to: .game)
                        showGameSheet = false
                    }
                },
                onCancel: {
                    // User canceled: preserve any existing game state.
                    // If no game was active, onDismiss will revert to practice.
                    showGameSheet = false
                }
            )
            .presentationDetents([.fraction(0.5)])
            .presentationDragIndicator(.visible)
            .environmentObject(authManager)
        }
        .sheet(isPresented: $showPracticeSheet, onDismiss: {
            // If user canceled without creating/choosing, optionally revert to game
            if sessionManager.currentMode == .practice && practiceName == nil && selectedPracticeId == nil {
                // Stay in practice mode but no active session
            }
        }) {
            PracticeSelectionSheet(
                onCreate: { name, date in
                    var sessions = loadPracticeSessions()
                    let new = PracticeSession(id: UUID().uuidString, name: name, date: date)
                    sessions.append(new)
                    savePracticeSessions(sessions)
                    // No-op here; PracticeSelectionSheet reads from UserDefaults on appear. However, for immediate selection flow, nothing needed.
                },
                onChoose: { practiceId in
                    let sessions = loadPracticeSessions()
                    if let session = sessions.first(where: { $0.id == practiceId }) {
                        selectedPracticeId = session.id
                        practiceName = session.name
                        isGame = false
                        // persist selection
                        let defaults = UserDefaults.standard
                        defaults.set(true, forKey: DefaultsKeys.activeIsPractice)
                        defaults.removeObject(forKey: DefaultsKeys.activeGameId)
                        persistActivePracticeId(session.id)
                        defaults.set("tracker", forKey: DefaultsKeys.lastView)
                        // Ensure sessionManager mode sync for button label update
                        sessionManager.switchMode(to: .practice)
                    }
                    showPracticeSheet = false
                },
                onCancel: {
                    showPracticeSheet = false
                }
            )
            .presentationDetents([.fraction(0.5)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showConfirmSheet) {
            PitchResultSheetView(
                isPresented: $showConfirmSheet,
                isStrikeSwinging: $isStrikeSwinging,
                isStrikeLooking: $isStrikeLooking,
                isWildPitch: $isWildPitch,
                isPassedBall: $isPassedBall,
                isBall: $isBall,
                selectedOutcome: $selectedOutcome,
                selectedDescriptor: $selectedDescriptor,
                isError: $isError,
                pendingResultLabel: pendingResultLabel,
                pitchCall: calledPitch,
                batterSide: batterSide,
                selectedTemplateId: selectedTemplate?.id.uuidString,
                currentMode: sessionManager.currentMode,
                selectedGameId: selectedGameId,
                selectedOpponentJersey: jerseyCells.first(where: { $0.id == selectedBatterId })?.jerseyNumber,
                selectedOpponentBatterId: selectedBatterId?.uuidString,
                selectedPracticeId: selectedPracticeId,
                saveAction: { event in
                    authManager.savePitchEvent(event)
                    sessionManager.incrementCount()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        pitchEvents.append(event)
                    }
                    authManager.loadPitchEvents { events in
                        self.pitchEvents = events
                    }

                    // Reset state
                    resultVisualState = event.location
                    activeCalledPitchId = UUID().uuidString
                    isRecordingResult = false
                    selectedPitch = ""
                    selectedLocation = ""
                    lastTappedPosition = nil
                    calledPitch = nil
                    resultVisualState = nil
                    actualLocationRecorded = nil
                    pendingResultLabel = nil
                    isStrikeSwinging = false
                    isWildPitch = false
                    isPassedBall = false
                    isBall = false
                    selectedOutcome = nil
                    selectedDescriptor = nil
                },
                template: selectedTemplate
            )
        }
        .sheet(isPresented: $showCodeAssignmentSheet) {
            CodeAssignmentSettingsView(
                selectedPitch: $selectedPitch,
                selectedLocation: $selectedLocation,
                pitchCodeAssignments: $pitchCodeAssignments,
                allPitches: allPitches,
                allLocations: allLocationsFromGrid()
            )
            .padding()
        }
        .onAppear {
            // Decide initial landing: Settings first unless an active game/session was in progress and tracker was last
            let defaults = UserDefaults.standard
            let lastViewPref = defaults.string(forKey: DefaultsKeys.lastView)
            let persistedGameId = defaults.string(forKey: DefaultsKeys.activeGameId)
            let persistedIsPractice = defaults.bool(forKey: DefaultsKeys.activeIsPractice)
            if authManager.isSignedIn && !hasPresentedInitialSettings {
                if lastViewPref == "settings" || (persistedGameId == nil && persistedIsPractice == false) {
                    showSettings = true
                    hasPresentedInitialSettings = true
                    defaults.set("settings", forKey: DefaultsKeys.lastView)
                } else {
                    // Restore active session to tracker
                    if persistedIsPractice {
                        isGame = false
                        sessionManager.switchMode(to: .practice)
                        restoreActivePracticeSelection()
                    } else if let gid = persistedGameId {
                        isGame = true
                        sessionManager.switchMode(to: .game)
                        selectedGameId = gid
                        authManager.loadGames { games in
                            if let game = games.first(where: { $0.id == gid }) {
                                opponentName = game.opponent
                                if let ids = game.batterIds, ids.count == game.jerseyNumbers.count {
                                    jerseyCells = zip(ids, game.jerseyNumbers).map { (idStr, num) in
                                        JerseyCell(id: UUID(uuidString: idStr) ?? UUID(), jerseyNumber: num)
                                    }
                                } else {
                                    jerseyCells = game.jerseyNumbers.map { JerseyCell(jerseyNumber: $0) }
                                }
                            }
                        }
                    }
                    hasPresentedInitialSettings = true
                }
            }
            
            if authManager.isSignedIn {
                authManager.loadTemplates { loadedTemplates in
                    self.templates = loadedTemplates
                    // 💾 Restore last used template and settings
                    restorePersistedState(loadedTemplates: loadedTemplates)
                }
                
                authManager.loadPitchEvents { events in
                    self.pitchEvents = events
                    if !events.isEmpty {
                    }
                    self.showPitchResults = true
                }
                
                authManager.loadGames { loadedGames in
                    self.games = loadedGames
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                templates: $templates,
                allPitches: allPitches,
                selectedTemplate: $selectedTemplate
            )
            .environmentObject(authManager)
        }
        .sheet(item: $menuSelectedStatsTemplate) { template in
            TemplateSuccessSheet(template: template)
        }
        .onChange(of: selectedTemplate) { _, newValue in
            // Persist and sync dependent state whenever template changes (from menu or Settings)
            persistSelectedTemplate(newValue)
            if let t = newValue {
                selectedPitches = loadActivePitches(for: t.id, fallback: t.pitches)
                pitchCodeAssignments = t.codeAssignments
                // Reset strike zone and called pitch state
                lastTappedPosition = nil
                calledPitch = nil
                // Force chips/strike zone to refresh colors and content
                colorRefreshToken = UUID()
            }
        }
        .onChange(of: authManager.isSignedIn) { _, signedIn in
            if signedIn && !hasPresentedInitialSettings {
                let defaults = UserDefaults.standard
                let lastViewPref = defaults.string(forKey: DefaultsKeys.lastView)
                let persistedGameId = defaults.string(forKey: DefaultsKeys.activeGameId)
                let persistedIsPractice = defaults.bool(forKey: DefaultsKeys.activeIsPractice)
                if lastViewPref == "settings" || (persistedGameId == nil && persistedIsPractice == false) {
                    showSettings = true
                    hasPresentedInitialSettings = true
                    defaults.set("settings", forKey: DefaultsKeys.lastView)
                } else {
                    if persistedIsPractice {
                        isGame = false
                        sessionManager.switchMode(to: .practice)
                        restoreActivePracticeSelection()
                    } else if let gid = persistedGameId {
                        isGame = true
                        sessionManager.switchMode(to: .game)
                        selectedGameId = gid
                        authManager.loadGames { games in
                            if let game = games.first(where: { $0.id == gid }) {
                                opponentName = game.opponent
                                if let ids = game.batterIds, ids.count == game.jerseyNumbers.count {
                                    jerseyCells = zip(ids, game.jerseyNumbers).map { (idStr, num) in
                                        JerseyCell(id: UUID(uuidString: idStr) ?? UUID(), jerseyNumber: num)
                                    }
                                } else {
                                    jerseyCells = game.jerseyNumbers.map { JerseyCell(jerseyNumber: $0) }
                                }
                            }
                        }
                    }
                    hasPresentedInitialSettings = true
                }
            }
        }
        .onChange(of: showSettings) { _, showing in
            if showing {
                UserDefaults.standard.set("settings", forKey: DefaultsKeys.lastView)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .jerseyOrderChanged)) { notification in
            guard let order = notification.object as? [String] else { return }
            if let gameId = selectedGameId {
                authManager.updateGameLineup(gameId: gameId, jerseyNumbers: order)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pitchColorDidChange)) { _ in
            // Force chips and strike zone to rebuild with updated colors
            colorRefreshToken = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .gameOrSessionChosen)) { notification in
            // Expecting userInfo: ["type": "practice"|"game", "gameId": String?, "opponent": String?]
            guard let userInfo = notification.userInfo as? [String: Any], let type = userInfo["type"] as? String else { return }
            self.suppressNextGameSheet = true
            self.showGameSheet = false
            if type == "practice" {
                if let pid = userInfo["practiceId"] as? String {
                    // Immediately set selection and persist
                    selectedPracticeId = pid
                    persistActivePracticeId(pid)

                    let sessions = loadPracticeSessions()
                    if let session = sessions.first(where: { $0.id == pid }) {
                        practiceName = session.name
                    } else if let providedName = userInfo["practiceName"] as? String {
                        practiceName = providedName
                    } else {
                        practiceName = nil
                    }
                    // Clear any active game state when switching to practice
                    selectedGameId = nil
                    opponentName = nil
                    jerseyCells = []
                    selectedBatterId = nil
                } else if let pname = userInfo["practiceName"] as? String {
                    practiceName = pname
                } else {
                    practiceName = nil
                    selectedPracticeId = nil
                }
                isGame = false
                sessionManager.switchMode(to: .practice)
                let defaults = UserDefaults.standard
                defaults.set(true, forKey: DefaultsKeys.activeIsPractice)
                defaults.removeObject(forKey: DefaultsKeys.activeGameId)
                defaults.set("tracker", forKey: DefaultsKeys.lastView)
            } else if type == "game" {
                if let gid = userInfo["gameId"] as? String {
                    selectedGameId = gid
                    // Always load the game to refresh lineup and opponent
                    authManager.loadGames { games in
                        if let game = games.first(where: { $0.id == gid }) {
                            // Prefer provided opponent name, otherwise use stored
                            if let opp = userInfo["opponent"] as? String {
                                opponentName = opp
                            } else {
                                opponentName = game.opponent
                            }
                            if let ids = game.batterIds, ids.count == game.jerseyNumbers.count {
                                jerseyCells = zip(ids, game.jerseyNumbers).map { (idStr, num) in
                                    JerseyCell(id: UUID(uuidString: idStr) ?? UUID(), jerseyNumber: num)
                                }
                            } else {
                                jerseyCells = game.jerseyNumbers.map { JerseyCell(jerseyNumber: $0) }
                            }
                            selectedBatterId = nil
                        } else {
                            // Fallback: still set provided opponent if available
                            if let opp = userInfo["opponent"] as? String {
                                opponentName = opp
                            }
                        }
                    }
                    isGame = true
                    sessionManager.switchMode(to: .game)
                    let defaults = UserDefaults.standard
                    defaults.set(false, forKey: DefaultsKeys.activeIsPractice)
                    defaults.set(gid, forKey: DefaultsKeys.activeGameId)
                    defaults.set("tracker", forKey: DefaultsKeys.lastView)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gameOrSessionDeleted)) { notification in
            guard let userInfo = notification.userInfo as? [String: Any], let type = userInfo["type"] as? String else { return }
            if type == "game" {
                if let gid = userInfo["gameId"] as? String, selectedGameId == gid {
                    // Clear active game selection and UI label
                    selectedGameId = nil
                    opponentName = nil
                    let defaults = DefaultsKeys.self
                    UserDefaults.standard.removeObject(forKey: defaults.activeGameId)
                    UserDefaults.standard.set(false, forKey: defaults.activeIsPractice)
                }
            } else if type == "practice" {
                if let pid = userInfo["practiceId"] as? String, selectedPracticeId == pid {
                    // Clear active practice selection and UI label
                    selectedPracticeId = nil
                    practiceName = nil
                    persistActivePracticeId(nil)
                }
            }
        }
        .overlay(alignment: .top) {
            if let batterId = pitchesFacedBatterId {
                ZStack(alignment: .top) {
                    // Backdrop to allow tap-to-dismiss
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation { pitchesFacedBatterId = nil } }

                    // Compute title and events based on the specific batter id that triggered the sheet
                    let jerseyNumber = jerseyCells.first(where: { $0.id == batterId })?.jerseyNumber ?? ""
                    let normalizedSelectedJersey = normalizeJersey(jerseyNumber)
                    let events = pitchEvents
                        .filter { event in
                            if let gid = selectedGameId, event.gameId != gid { return false }
                            if let evId = event.opponentBatterId, evId == batterId.uuidString { return true }
                            if let selJersey = normalizedSelectedJersey, let evJersey = normalizeJersey(event.opponentJersey), selJersey == evJersey { return true }
                            return false
                        }
                        .sorted { $0.timestamp > $1.timestamp }

                    VStack(spacing: 0) {
                        HStack {
                            Text(isGame ? ("vs. \(opponentName ?? "Game")") : ("Practice – \(practiceName ?? "Session")"))
                                .font(.headline)
                            Spacer()
                            Button {
                                withAnimation { pitchesFacedBatterId = nil }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                        Divider()

                        ScrollView {
                            PitchesFacedGridView(
                                title: jerseyNumber.isEmpty ? "Pitches Faced" : "Pitches Faced – #\(jerseyNumber)",
                                events: events
                            )
                            .padding(.horizontal)
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.height * 0.33)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.horizontal, 12)
                }
                .animation(.easeInOut(duration: 0.25), value: pitchesFacedBatterId)
            }
        }
    }

}

private struct JerseyDropDelegate: DropDelegate {
    let current: JerseyCell
    @Binding var items: [JerseyCell]
    @Binding var dragging: JerseyCell?

    func dropEntered(info: DropInfo) {
        guard let dragging = dragging, dragging.id != current.id else { return }
        if let from = items.firstIndex(where: { $0.id == dragging.id }),
           let to = items.firstIndex(where: { $0.id == current.id }) {
            withAnimation {
                let item = items.remove(at: from)
                items.insert(item, at: to)
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        // Persist new order if possible
        // We need access to AuthManager and selectedGameId from the environment/scope.
        // Since DropDelegate is not a view, we post a notification with the new order.
        let order = items.map { $0.jerseyNumber }
        NotificationCenter.default.post(name: .jerseyOrderChanged, object: order)
        return true
    }
}

struct JerseyRow: View {
    let cell: JerseyCell
    @Binding var jerseyCells: [JerseyCell]
    @Binding var selectedBatterId: UUID?
    @Binding var draggingJersey: JerseyCell?
    @Binding var editingCell: JerseyCell?
    @Binding var newJerseyNumber: String
    @Binding var showAddJerseyPopover: Bool
    let selectedGameId: String?
    @Binding var pitchesFacedBatterId: UUID?
    @Binding var isReordering: Bool
    
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        JerseyCellView(cell: cell)
            .modifier(JiggleEffect(isActive: isReordering))
            .background(selectedBatterId == cell.id ? Color.blue : Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selectedBatterId == cell.id ? Color.white.opacity(0.9) : Color.secondary.opacity(0.3), lineWidth: selectedBatterId == cell.id ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundColor(selectedBatterId == cell.id ? .white : .primary)
            .onTapGesture {
                guard !isReordering else { return }
                if selectedBatterId == cell.id {
                    selectedBatterId = nil
                } else {
                    selectedBatterId = cell.id
                }
            }
            .onDrop(of: [UTType.text], delegate: JerseyDropDelegate(current: cell, items: $jerseyCells, dragging: $draggingJersey))
            .contextMenu {
                Button("Pitches Faced", systemImage: "baseball") {
                    // Select this batter and drive popover via item binding
                    selectedBatterId = cell.id
                    pitchesFacedBatterId = cell.id
                }
                Button("Edit", systemImage: "pencil") {
                    editingCell = cell
                    newJerseyNumber = cell.jerseyNumber
                    showAddJerseyPopover = true
                }

                Divider()
                Button("Move Up", systemImage: "arrow.up") {
                    if let idx = jerseyCells.firstIndex(where: { $0.id == cell.id }), idx > 0 {
                        withAnimation {
                            let item = jerseyCells.remove(at: idx)
                            jerseyCells.insert(item, at: idx - 1)
                        }
                        if let gameId = selectedGameId {
                            authManager.updateGameLineup(gameId: gameId, jerseyNumbers: jerseyCells.map { $0.jerseyNumber })
                        }
                        // Also notify any listeners of order change
                        NotificationCenter.default.post(name: .jerseyOrderChanged, object: jerseyCells.map { $0.jerseyNumber })
                    }
                }
                Button("Move Down", systemImage: "arrow.down") {
                    if let idx = jerseyCells.firstIndex(where: { $0.id == cell.id }), idx < jerseyCells.count - 1 {
                        withAnimation {
                            let item = jerseyCells.remove(at: idx)
                            jerseyCells.insert(item, at: idx + 1)
                        }
                        if let gameId = selectedGameId {
                            authManager.updateGameLineup(gameId: gameId, jerseyNumbers: jerseyCells.map { $0.jerseyNumber })
                        }
                        // Also notify any listeners of order change
                        NotificationCenter.default.post(name: .jerseyOrderChanged, object: jerseyCells.map { $0.jerseyNumber })
                    }
                }
                Button(isReordering ? "Done Reordering" : "Reorder Mode", systemImage: "arrow.up.arrow.down") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isReordering.toggle()
                    }
                }

                Button("Delete", systemImage: "trash", role: .destructive) {
                    if let idx = jerseyCells.firstIndex(where: { $0.id == cell.id }) {
                        jerseyCells.remove(at: idx)
                        if let gameId = selectedGameId {
                            authManager.updateGameLineup(gameId: gameId, jerseyNumbers: jerseyCells.map { $0.jerseyNumber })
                        }
                        if selectedBatterId == cell.id {
                            selectedBatterId = nil
                        }
                    }
                }
            }
    }
}

struct JiggleEffect: ViewModifier {
    let isActive: Bool
    @State private var animate: Bool = false
    @State private var seedDelay: Double = Double.random(in: 0...0.2)

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isActive && animate ? 2.0 : -2.0), anchor: .center)
            .scaleEffect(isActive ? 0.98 : 1.0)
            .animation(isActive ? .easeInOut(duration: 0.12).repeatForever(autoreverses: true).delay(seedDelay) : .default, value: animate)
            .onAppear {
                if isActive {
                    DispatchQueue.main.asyncAfter(deadline: .now() + seedDelay) {
                        animate = true
                    }
                }
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + seedDelay) {
                        animate = true
                    }
                } else {
                    animate = false
                }
            }
    }
}

struct ShowPitchLog: View {
    let showLog: () -> Void
    
    var body: some View {
        Button(action: {
            withAnimation {
                showLog()
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: "baseball")
                    .font(.body)
                    .foregroundColor(.green)
                    .padding(6)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Circle())
                
                Text("Cards")
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .accessibilityLabel("Show pitches.")
    }
}

struct ResetPitchButton: View {
    let resetAction: () -> Void
    
    var body: some View {
        Button(action: {
            withAnimation {
                resetAction()
            }
        }) {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .foregroundColor(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: 70, height: 36)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
                .offset(y: 6)
                
        }
        .accessibilityLabel("Reset pitch selection")
    }
}

struct CalledPitchView: View {
    @State private var showResultOverlay = false
    @State private var selectedActualLocation: String?
    @Binding var isRecordingResult: Bool
    @Binding var activeCalledPitchId: String?
    let call: PitchCall
    let pitchCodeAssignments: [PitchCodeAssignment]
    let batterSide: BatterSide
    
    var body: some View {
        let displayLocation = call.location.trimmingCharacters(in: .whitespaces)
        let assignedCodes = pitchCodeAssignments
            .filter {
                $0.pitch == call.pitch &&
                $0.location.trimmingCharacters(in: .whitespacesAndNewlines) == displayLocation.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .map(\.code)
        
        print("Looking for: \(call.pitch) @ \(displayLocation)")
        print("Available: \(pitchCodeAssignments.map { "\($0.pitch) @ \($0.location)" })")
        
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Called Pitch:")
                    Text(call.type)
                        .bold()
                        .foregroundColor(call.type == "Strike" ? .green : .red)
                }
                
                Text("\(call.pitch) (\(displayLocation))")
                    .foregroundColor(.primary)
                
                if !assignedCodes.isEmpty {
                    Text("Calls: \(assignedCodes.joined(separator: ", "))")
                        .font(.subheadline)
                        .foregroundColor(.red)
                } else {
                    Text("No assigned Calls for pitch/location")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            Button(action: {
                isRecordingResult = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                    Text("🥎")
                        .font(.title)
                }
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .font(.headline)
        .padding(.horizontal)
        .transition(.opacity)
    }
}

struct GameSelectionSheet: View {
    var onCreate: (String, Date) -> Void
    var onChoose: (String) -> Void
    var onCancel: () -> Void

    @State private var games: [Game] = []
    @State private var showAddGamePopover: Bool = false
    @State private var newOpponentName: String = ""
    @State private var newGameDate: Date = Date()
    
    @State private var pendingDeleteGameId: String? = nil
    @State private var showDeleteGameConfirm: Bool = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        NavigationStack {
            List {
                if games.isEmpty {
//                    Section {
//                        Text("No games yet. Tap + to add one.")
//                            .foregroundColor(.secondary)
//                    }
                } else {
                    Section() {
                        ForEach(games) { game in
                            Button(action: {
                                if let gid = game.id, !gid.isEmpty {
                                    onChoose(gid)
                                    dismiss()
                                } else {
                                    // Resolve freshly created game by reloading and matching on name/date
                                    authManager.loadGames { loaded in
                                        self.games = loaded
                                        let calendar = Calendar.current
                                        if let resolved = loaded.first(where: { $0.opponent == game.opponent && calendar.isDate($0.date, inSameDayAs: game.date) }) {
                                            onChoose(resolved.id ?? "")
                                        }
                                        dismiss()
                                    }
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(game.opponent)
                                            .font(.headline)
                                        Text(Self.formatter.string(from: game.date))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    if let id = game.id {
                                        pendingDeleteGameId = id
                                        showDeleteGameConfirm = true
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Games")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showAddGamePopover = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)   // sets the symbol color
                            .font(.system(size: 25))   // optional: controls size
                    }
                    .accessibilityLabel("Add Game")
                }
            }
        }
        .confirmationDialog(
            "Delete Game?",
            isPresented: $showDeleteGameConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteGameId {
                    if let idx = games.firstIndex(where: { $0.id == id }) {
                        games.remove(at: idx)
                    }
                    authManager.deleteGame(gameId: id)
                    NotificationCenter.default.post(name: .gameOrSessionDeleted, object: nil, userInfo: ["type": "game", "gameId": id])
                }
                pendingDeleteGameId = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteGameId = nil
            }
        } message: {
            Text("This will permanently remove the game and its lineup.")
        }
        .overlay(
            Group {
                if showAddGamePopover {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .onTapGesture { showAddGamePopover = false }

                        AddGameCard(
                            opponentName: $newOpponentName,
                            gameDate: $newGameDate,
                            onCancel: { showAddGamePopover = false },
                            onSave: {
                                let name = newOpponentName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !name.isEmpty else { return }
                                let item = Game(opponent: name, date: newGameDate, jerseyNumbers: [])
                                games.append(item)
                                onCreate(name, newGameDate)
                                showAddGamePopover = false
                                // Keep the game selection sheet open; do not dismiss here.
                            }
                        )
                        .frame(maxWidth: 360)
                        .padding()
                    }
                    .transition(.opacity.combined(with: .scale))
                    .animation(.easeInOut(duration: 0.2), value: showAddGamePopover)
                }
            }
        )
        .onAppear {
            authManager.loadGames { loadedGames in
                self.games = loadedGames
            }
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

struct GameItem: Identifiable {
    let id = UUID()
    var opponent: String
    var date: Date
}


struct AddGameCard: View {
    @Binding var opponentName: String
    @Binding var gameDate: Date
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("New Game")
                    .font(.headline)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            TextField("Opponent name", text: $opponentName)
                .textFieldStyle(.roundedBorder)

            DatePicker("Date & Time", selection: $gameDate, displayedComponents: [.date, .hourAndMinute])

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(opponentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 10)
    }
}

struct PitchesFacedGridView: View {
    let title: String
    let events: [PitchEvent]

    private static let columns: [GridItem] = [
        GridItem(.flexible(minimum: 80), spacing: 8, alignment: .leading),
        GridItem(.flexible(minimum: 80), spacing: 8, alignment: .leading),
        GridItem(.flexible(minimum: 80), spacing: 8, alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "baseball")
                    .foregroundStyle(.green)
                Text(title.isEmpty ? "Pitches Faced" : title)
                    .font(.headline)
                Spacer()
                Text("\(events.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if events.isEmpty {
                Text("No pitches recorded for this batter yet.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 8) {
                    // Header
                    Text("Pitch Called").font(.subheadline.bold())
                    Text("Result").font(.subheadline.bold())
                    Text("Batter Outcome").font(.subheadline.bold())

                    ForEach(events, id: \.id) { event in
                        // Column 1: Pitch Called
                        Text(event.pitch ?? "-")
                            .font(.body)
                            .lineLimit(1)

                        // Column 2: Result (Strike/Ball/Foul if available)
                        Text(resultText(for: event))
                            .font(.body)
                            .lineLimit(1)

                        // Column 3: Batter Outcome
                        Text(outcomeText(for: event))
                            .font(.body)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(16)
    }

    // Helpers
    private func resultText(for event: PitchEvent) -> String {
        if event.strikeLooking == true { return "Strike Looking" }
        if event.strikeSwinging == true { return "Strike Swinging" }
        if event.isStrike == true { return "Strike" }
        if event.wildPitch == true { return "Wild Pitch" }
        if event.passedBall == true { return "Passed Ball" }
        // Fallback: use calledPitch type if present, else "Ball"
        if let type = event.calledPitch?.type, !type.isEmpty { return type }
        return "Ball"
    }

    private func outcomeText(for event: PitchEvent) -> String {
        if let outcome = event.outcome, !outcome.isEmpty { return outcome }
        if let descriptor = event.descriptor, !descriptor.isEmpty { return descriptor }
        return "-"
    }
}

private extension View {
    func erasedToAnyView() -> AnyView {
        AnyView(self)
    }
}

#Preview("PitchTracker — Dataless") {
    // Provide a lightweight AuthManager and keep it signed-out to avoid network calls in previews
    let auth = AuthManager()
    auth.isSignedIn = false

    // Seed a simple template so the UI has chips and structure without hitting any backend
    let sampleTemplate = PitchTemplate(
        id: UUID(),
        name: "Preview Template",
        pitches: ["4 Seam", "Curve", "Change"],
        codeAssignments: []
    )

    return PitchTrackerView(
        previewTemplate: sampleTemplate,
        previewTemplates: [sampleTemplate],
        previewIsGame: false
    )
    .environmentObject(auth)
}

struct PracticeSession: Identifiable, Codable {
    var id: String?
    var name: String
    var date: Date
}

struct PracticeSelectionSheet: View {
    var onCreate: (String, Date) -> Void
    var onChoose: (String) -> Void
    var onCancel: () -> Void

    @State private var sessions: [PracticeSession] = []
    @State private var showAddPopover: Bool = false
    @State private var newName: String = ""
    @State private var newDate: Date = Date()
    
    @State private var pendingDeleteSessionId: String? = nil
    @State private var showDeleteSessionConfirm: Bool = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    // Optional empty state
                } else {
                    Section() {
                        ForEach(sessions) { session in
                            Button(action: {
                                if let pid = session.id, !pid.isEmpty {
                                    onChoose(pid)
                                    dismiss()
                                } else {
                                    // Resolve from UserDefaults by matching name/date (should be rare)
                                    let key = PitchTrackerView.DefaultsKeys.storedPracticeSessions
                                    if let data = UserDefaults.standard.data(forKey: key),
                                       let decoded = try? JSONDecoder().decode([PracticeSession].self, from: data) {
                                        let calendar = Calendar.current
                                        if let resolved = decoded.first(where: { $0.name == session.name && calendar.isDate($0.date, inSameDayAs: session.date) }) {
                                            onChoose(resolved.id ?? "")
                                        }
                                    }
                                    dismiss()
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.name)
                                            .font(.headline)
                                        Text(Self.formatter.string(from: session.date))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    if let id = session.id {
                                        pendingDeleteSessionId = id
                                        showDeleteSessionConfirm = true
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Practice Sessions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showAddPopover = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 25))
                    }
                    .accessibilityLabel("Add Practice Session")
                }
            }
        }
        .confirmationDialog(
            "Delete Practice Session?",
            isPresented: $showDeleteSessionConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let id = pendingDeleteSessionId else { return }
                // Remove from local list
                if let idx = sessions.firstIndex(where: { $0.id == id }) {
                    sessions.remove(at: idx)
                }
                // Persist removal to UserDefaults
                let key = PitchTrackerView.DefaultsKeys.storedPracticeSessions
                if let data = UserDefaults.standard.data(forKey: key),
                   var decoded = try? JSONDecoder().decode([PracticeSession].self, from: data) {
                    decoded.removeAll { $0.id == id }
                    if let newData = try? JSONEncoder().encode(decoded) {
                        UserDefaults.standard.set(newData, forKey: key)
                    }
                }
                NotificationCenter.default.post(name: .gameOrSessionDeleted, object: nil, userInfo: ["type": "practice", "practiceId": id])
                pendingDeleteSessionId = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteSessionId = nil
            }
        } message: {
            Text("This will remove the session from this device.")
        }
        .overlay(
            Group {
                if showAddPopover {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .onTapGesture { showAddPopover = false }

                        AddGameCard(
                            opponentName: $newName,
                            gameDate: $newDate,
                            onCancel: { showAddPopover = false },
                            onSave: {
                                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !name.isEmpty else { return }
                                onCreate(name, newDate)
                                // Reload sessions from UserDefaults so IDs match the persisted source
                                if let data = UserDefaults.standard.data(forKey: PitchTrackerView.DefaultsKeys.storedPracticeSessions),
                                   let decoded = try? JSONDecoder().decode([PracticeSession].self, from: data) {
                                    self.sessions = decoded
                                }
                                showAddPopover = false
                            }
                        )
                        .frame(maxWidth: 360)
                        .padding()
                    }
                    .transition(.opacity.combined(with: .scale))
                    .animation(.easeInOut(duration: 0.2), value: showAddPopover)
                }
            }
        )
        .onAppear {
            // Load from UserDefaults via a helper in the host view by sending through Notification not available here; instead, mirror logic locally
            if let data = UserDefaults.standard.data(forKey: PitchTrackerView.DefaultsKeys.storedPracticeSessions),
               let decoded = try? JSONDecoder().decode([PracticeSession].self, from: data) {
                self.sessions = decoded
            } else {
                self.sessions = []
            }
        }
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

