//
//  PitchTrackerView.swift
//  PitchMark
//
//  Created by Mark Springer on 9/16/25.
//

import SwiftUI
import CoreGraphics
import FirebaseCore
import FirebaseFirestore
import UniformTypeIdentifiers
import UIKit

//Hi
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
    @State private var showSelectBatterOverlay: Bool = false
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
    @State private var showResetConfirm = false
    // Removed @State private var isReset = false here as per instructions

    @State private var isReorderingMode: Bool = false
    @State private var colorRefreshToken = UUID()
    @State private var hasPresentedInitialSettings = false

    @State private var suppressNextGameSheet = false

    // Added according to instructions
    @State private var showTemplateChangeWarning = false
    @State private var pendingTemplateSelection: PitchTemplate? = nil

    // Added per instructions:
    @State private var encryptedSelectionByGameId: [String: Bool] = [:]
    @State private var encryptedSelectionByPracticeId: [String: Bool] = [:]
    
    // Added progressRefreshToken as per instruction 1
    @State private var progressRefreshToken = UUID()

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
        static let encryptedByGameId = "encryptedByGameId"
        static let encryptedByPracticeId = "encryptedByPracticeId"
        static let practiceCodesEnabled = "practiceCodesEnabled"
    }
    @State private var isSelecting: Bool = false
    @State private var selectedEventIDs: Set<String> = []
    @State private var localTemplateOverrides: [String: String] = [:]
    @State private var pitchFirst = true
    @State private var showCodeShareSheet = false
    @State private var showCodeShareModePicker = false
    @State private var codeShareInitialTab: Int = 0 // 0 = Generate, 1 = Enter

    // MARK: - Template Version Indicator
    private var currentTemplateVersionLabel: String {
        // Prefer explicit per-session selection when available
        if isGame, let gid = selectedGameId, let explicit = encryptedSelectionByGameId[gid] {
            return explicit ? "Encrypted" : "Classic"
        }
        if !isGame, let pid = selectedPracticeId, let explicit = encryptedSelectionByPracticeId[pid] {
            return explicit ? "Encrypted" : "Classic"
        }
        // Fallback: infer from template data presence
        if let t = selectedTemplate {
            return templateHasEncryptedData(t) ? "Encrypted" : "Classic"
        }
        return String()
    }

    private var filteredEvents: [PitchEvent] {
        if isGame, let gid = selectedGameId {
            return pitchEvents.filter { $0.gameId == gid }
                .sorted { $0.timestamp > $1.timestamp }
        } else if !isGame {
            if let pid = selectedPracticeId {
                return pitchEvents.filter { $0.practiceId == pid }
                    .sorted { $0.timestamp > $1.timestamp }
            } else {
                return pitchEvents.filter { $0.mode == .practice }
                    .sorted { $0.timestamp > $1.timestamp }
            }
        }
        return []
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
            selectedPitches = loadActivePitches(for: template.id, fallback: availablePitches(for: template))
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
    
    // MARK: - Encrypted/Classic Selection Persistence
    private func loadEncryptedSelections() {
        let defaults = UserDefaults.standard
        if let gameData = defaults.dictionary(forKey: DefaultsKeys.encryptedByGameId) as? [String: Bool] {
            encryptedSelectionByGameId = gameData
        }
        if let practiceData = defaults.dictionary(forKey: DefaultsKeys.encryptedByPracticeId) as? [String: Bool] {
            encryptedSelectionByPracticeId = practiceData
        }
    }

    private func persistEncryptedSelections() {
        let defaults = UserDefaults.standard
        defaults.set(encryptedSelectionByGameId, forKey: DefaultsKeys.encryptedByGameId)
        defaults.set(encryptedSelectionByPracticeId, forKey: DefaultsKeys.encryptedByPracticeId)
    }
    
    // Determine if a template carries encrypted grid data
    private func templateHasEncryptedData(_ t: PitchTemplate?) -> Bool {
        guard let t = t else { return false }
        return !t.pitchGridHeaders.isEmpty || !t.pitchGridValues.isEmpty || !t.strikeTopRow.isEmpty || !t.strikeRows.isEmpty || !t.ballsTopRow.isEmpty || !t.ballsRows.isEmpty
    }

    private func useEncrypted(for template: PitchTemplate?) -> Bool {
        guard let template = template else { return false }
        // Prefer explicit per-session selection
        if isGame, let gid = selectedGameId, let explicit = encryptedSelectionByGameId[gid] {
            return explicit
        }
        if !isGame, let pid = selectedPracticeId, let explicit = encryptedSelectionByPracticeId[pid] {
            return explicit
        }
        // Fallback: infer from template data presence
        return templateHasEncryptedData(template)
    }
    
    private func availablePitches(for template: PitchTemplate?) -> [String] {
        // If no template, fall back to app-wide default order
        guard let t = template else { return pitchOrder }

        if useEncrypted(for: t) {
            let rawHeaders = t.pitchGridHeaders
                .map { $0.pitch.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            // Remove duplicates while preserving first occurrence (stable order)
            var seen = Set<String>()
            let headerList = rawHeaders.filter { seen.insert($0).inserted }

            // If no encrypted headers are effectively present, fall back to Classic ordering
            if headerList.isEmpty {
                let base = pitchOrder
                let extras = t.pitches.filter { !base.contains($0) }
                return base + extras
            }

            let ordered = pitchOrder.filter { headerList.contains($0) }
            let extras = headerList.filter { !pitchOrder.contains($0) }
            print("Encrypted headers used:", headerList)
            return ordered + extras
        }

        // Classic path: start from the preferred order and append any extras listed on the template
        let base = pitchOrder
        let extras = t.pitches.filter { !base.contains($0) }
        return base + extras
    }
    
    private var effectivePitchesForStrikeZone: Set<String> {
        if let t = selectedTemplate, useEncrypted(for: t) {
            return Set(availablePitches(for: t))
        }
        return selectedPitches
    }
    
    fileprivate var orderedPitchesForTemplate: [String] {
        let list = availablePitches(for: selectedTemplate)
        return list
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

    // MARK: - Template Apply Helper
    private func applyTemplate(_ template: PitchTemplate) {
        selectedTemplate = template
        let fallbackList = availablePitches(for: template)
        if useEncrypted(for: template) {
            // In encrypted mode, always show the full set derived from encrypted assignments
            selectedPitches = Set(fallbackList)
        } else {
            selectedPitches = loadActivePitches(for: template.id, fallback: fallbackList)
        }
        pitchCodeAssignments = template.codeAssignments
        // 🧹 Reset strike zone and called pitch state
        lastTappedPosition = nil
        calledPitch = nil
        // 💾 Persist last used template
        persistSelectedTemplate(template)
        // Force chips/strike zone to refresh colors and content
        colorRefreshToken = UUID()
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
    // MARK: - Current Game Helper
    private var currentGame: Game? {
        guard let gid = selectedGameId else { return nil }
        return games.first(where: { $0.id == gid })
    }
    
    // MARK: - Game Field Bindings
    private func buildShareCode() -> String {
        // Encode minimal session info as a simple URL-like string
        if isGame, let gid = selectedGameId {
            let opp = opponentName?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return "pm://join?type=game&gameId=\(gid)&opponent=\(opp)"
        } else {
            let pid = selectedPracticeId ?? "__GENERAL__"
            let pname = (practiceName ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return "pm://join?type=practice&practiceId=\(pid)&practiceName=\(pname)"
        }
    }

    private func consumeShareCode(_ text: String) {
        // Prefer URL-like string (pm://join?type=...&...)
        if let url = URL(string: text),
           let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var userInfo: [String: Any] = [:]
            for item in comps.queryItems ?? [] {
                userInfo[item.name] = item.value
            }
            if let type = comps.queryItems?.first(where: { $0.name == "type" })?.value {
                userInfo["type"] = type
                NotificationCenter.default.post(name: .gameOrSessionChosen, object: nil, userInfo: userInfo)
                return
            }
        }
        // Fallback: try JSON object string
        if let data = text.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = dict["type"] as? String {
            var userInfo = dict
            userInfo["type"] = type
            NotificationCenter.default.post(name: .gameOrSessionChosen, object: nil, userInfo: userInfo)
        }
    }
    // Tiny factory to reduce type-checker work when creating bindings
    private func intBinding(
        get: @escaping () -> Int,
        set: @escaping (Int) -> Void
    ) -> Binding<Int> {
        Binding(get: get, set: set)
    }

    private var inningBinding: Binding<Int> {
        intBinding(
            get: { currentGame?.inning ?? 1 },
            set: { newValue in
                guard let gid = selectedGameId else { return }
                authManager.updateGameInning(gameId: gid, inning: newValue)
                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].inning = newValue
                }
            }
        )
    }

    private var hitsBinding: Binding<Int> {
        intBinding(
            get: { currentGame?.hits ?? 0 },
            set: { newValue in
                guard let gid = selectedGameId else { return }
                authManager.updateGameHits(gameId: gid, hits: newValue)
                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].hits = newValue
                }
            }
        )
    }

    private var walksBinding: Binding<Int> {
        intBinding(
            get: { currentGame?.walks ?? 0 },
            set: { newValue in
                guard let gid = selectedGameId else { return }
                authManager.updateGameWalks(gameId: gid, walks: newValue)
                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].walks = newValue
                }
            }
        )
    }

    private var ballsBinding: Binding<Int> {
        intBinding(
            get: { currentGame?.balls ?? 0 },
            set: { newValue in
                guard let gid = selectedGameId else { return }
                authManager.updateGameBalls(gameId: gid, balls: newValue)
                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].balls = newValue
                }
            }
        )
    }

    private var strikesBinding: Binding<Int> {
        intBinding(
            get: { currentGame?.strikes ?? 0 },
            set: { newValue in
                guard let gid = selectedGameId else { return }
                authManager.updateGameStrikes(gameId: gid, strikes: newValue)
                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].strikes = newValue
                }
            }
        )
    }

    private var usBinding: Binding<Int> {
        intBinding(
            get: { currentGame?.us ?? 0 },
            set: { newValue in
                guard let gid = selectedGameId else { return }
                authManager.updateGameUs(gameId: gid, us: newValue)
                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].us = newValue
                }
            }
        )
    }

    private var themBinding: Binding<Int> {
        intBinding(
            get: { currentGame?.them ?? 0 },
            set: { newValue in
                guard let gid = selectedGameId else { return }
                authManager.updateGameThem(gameId: gid, them: newValue)
                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].them = newValue
                }
            }
        )
    }
    
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
    
    private var cardsAndOverlay: some View {
        ZStack {
            VStack(spacing: 8) {
                // Top toggle buttons
                HStack(spacing: 6) {
                    
                    Button(action: { overlayTab = .progress }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text("Progress")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(overlayTab == .progress ? .black : .black.opacity(0.4))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .background(overlayTab == .progress ? .ultraThickMaterial : .ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: { overlayTab = .cards }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.grid.2x2")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text("Cards")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(overlayTab == .cards ? .black : .black.opacity(0.4))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .background(overlayTab == .cards ? .ultraThickMaterial : .ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.top, 12)

                Divider()
                .padding(.top, 5)
                
                // Content switches with tab
                let overlayContent: AnyView = {
                    switch overlayTab {
                    case .cards:
                        if selectedTemplate != nil {
                            return PitchResultSheet(
                                allEvents: filteredEvents,
                                games: games,
                                templates: templates
                            )
                            .environmentObject(authManager)
                            .environmentObject(sessionManager)
                            .frame(maxWidth: .infinity, minHeight: 170)
                            .erasedToAnyView()
                        } else {
                            return EmptyView().erasedToAnyView()
                        }
                    case .progress:
                        if sessionManager.currentMode == .practice {
                            return ProgressSummaryView(
                                events: pitchEvents,
                                currentMode: sessionManager.currentMode,
                                selectedPracticeId: selectedPracticeId,
                                templates: templates
                            )
                            // Added .id(progressRefreshToken) per instruction 2
                            .id(progressRefreshToken)
                            .frame(maxWidth: .infinity, minHeight: 170)
                            .erasedToAnyView()
                        } else {
                            return ProgressGameView(
                                balls: ballsBinding,
                                strikes: strikesBinding,
                                inning: inningBinding,
                                hits: hitsBinding,
                                walks: walksBinding,
                                us: usBinding,
                                them: themBinding,
                                selectedGameId: $selectedGameId
                            )
                            .environmentObject(authManager)
                            .frame(maxWidth: .infinity, minHeight: 170, alignment: .top)
                            .erasedToAnyView()
                        }
                    }
                }()

                overlayContent
                      .padding(.top, -14)
                      .frame(maxWidth: .infinity)
                      .frame(height: 170, alignment: .top)
                
            }
            .blur(radius: shouldBlurBackground ? 6 : 0)
            .animation(.easeInOut(duration: 0.2), value: shouldBlurBackground)
            .transition(.opacity)
            
            // Called pitch appears view after a user taps a location
            Group {
                if let call = calledPitch {
                    CalledPitchView(
                        isRecordingResult: $isRecordingResult,
                        activeCalledPitchId: $activeCalledPitchId,
                        pitchFirst: $pitchFirst,
                        call: call,
                        pitchCodeAssignments: pitchCodeAssignments,
                        batterSide: batterSide,
                        template: selectedTemplate,
                        isEncryptedMode: {
                            if let t = selectedTemplate {
                                return useEncrypted(for: t)
                            }
                            return false
                        }(),
                        isPracticeMode: sessionManager.currentMode == .practice
                        
                    )
                    
                    .transition(.opacity)
                    .padding(.top, 4)
                    .onAppear {
                        shouldBlurBackground = true
                        // If in game mode and no batter is selected, show a brief overlay prompt
                        if isGame && selectedBatterId == nil {
                            showSelectBatterOverlay = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                showSelectBatterOverlay = false
                            }
                        }
                    }
                    .onDisappear {
                        shouldBlurBackground = false
                        showSelectBatterOverlay = false
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 16) // tweak this value to taste (e.g., 0–16)
            if showSelectBatterOverlay {
                VStack {
                    HStack {
                        Spacer()
                        Text("Select a batter?")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                .ultraThinMaterial,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, -10) // adjust this to sit above the code chips
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.5), value: showSelectBatterOverlay)
            }
            
        }
        // Make this layer fill the entire screen space and bleed off the edges
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: [.horizontal, .bottom])
        .background(.regularMaterial)
    }

    private var headerContainer: some View {
        let screen = UIScreen.main.bounds
        
        return VStack(spacing: 8) {
            topBar
            pitchSelectionChips
        }
        .frame(
            width: screen.width * 0.9,   // 90% of screen width
            height: screen.height * 0.15 // 15% of screen height
        )
        .background(
            .thickMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    private var contentSection: some View {
        Group {
            batterAndModeBar
            mainStrikeZoneSection
            Spacer(minLength: 40)
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

    private var confirmSheetBinding: Binding<Bool> {
        Binding<Bool>(
            get: { sessionManager.currentMode == .game && showConfirmSheet },
            set: { newValue in
                if sessionManager.currentMode == .game {
                    showConfirmSheet = newValue
                } else {
                    // In practice, never allow the sheet to appear
                    showConfirmSheet = false
                }
            }
        )
    }
    
    // MARK: - Extracted subviews to help type-checker
    private var topBar: some View {
        HStack {
            Menu {
                ForEach(templates, id: \.id) { template in
                    Button(template.name) {
                        if sessionManager.currentMode == .practice && selectedPracticeId != nil {
                            pendingTemplateSelection = template
                            showTemplateChangeWarning = true
                        } else {
                            applyTemplate(template)
                        }
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
                        Text(currentTemplateVersionLabel)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.clear)
                            .opacity(0)
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .opacity(0)
                    }

                    // Visible current label
                    HStack(spacing: 8) {
                        Text(currentLabel)
                            .font(.headline)
                        Text(currentTemplateVersionLabel)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                        //.background(Color.gray.opacity(0.2))
                            .foregroundStyle(Color.gray)
                            .clipShape(Capsule())
                            .accessibilityLabel("Template version \(currentTemplateVersionLabel)")
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
        .confirmationDialog(
            "Practice session in progress",
            isPresented: $showTemplateChangeWarning,
            titleVisibility: .visible
        ) {
            Button("Change / Add Session") {
                // Open the practice session picker and switch to the pending template (if any)
                if let toApply = pendingTemplateSelection {
                    applyTemplate(toApply)
                }
                showPracticeSheet = true
                pendingTemplateSelection = nil
            }
            Button("Cancel", role: .cancel) {
                pendingTemplateSelection = nil
            }
        } message: {
            Text("You're currently in a practice session:")
        }
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
                // QR scanner button row
                HStack(spacing: 0) {
                    Button(action: {
                        showCodeShareModePicker = true
                    }) {
                        Image(systemName: "key.sensor.tag.radiowaves.left.and.right.fill")
                            .imageScale(.large)
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 36)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.top, 6)

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
            .confirmationDialog(
                "Code Link",
                isPresented: $showCodeShareModePicker,
                titleVisibility: .visible
            ) {
                Button("Generate Code") {
                    codeShareInitialTab = 0
                    showCodeShareSheet = true
                }
                Button("Enter Code") {
                    codeShareInitialTab = 1
                    showCodeShareSheet = true
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }
    
    private var resetOverlay: some View {
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
        }
    }
    
    private var sessionOverlay: some View {
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
        }
    }
    
    @ViewBuilder
    private func batterSideOverlay(SZwidth: CGFloat) -> some View {
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
    
    private struct StrikeZoneCard: View {
        let SZwidth: CGFloat
        @Binding var isGame: Bool
        let batterSide: BatterSide
        let lastTappedPosition: CGPoint?
        let setLastTapped: (CGPoint?) -> Void
        let calledPitch: PitchCall?
        let setCalledPitch: (PitchCall?) -> Void
        let selectedPitches: Set<String>
        let gameIsActive: Bool
        let selectedPitch: String
        let pitchCodeAssignments: [PitchCodeAssignment]
        let isRecordingResult: Bool
        let setIsRecordingResult: (Bool) -> Void
        let setActualLocation: (String?) -> Void
        let actualLocationRecorded: String?
        let setSelectedPitch: (String) -> Void
        let resultVisualState: String?
        let setResultVisualState: (String?) -> Void
        @Binding var pendingResultLabel: String?
        @Binding var showResultConfirmation: Bool
        var showConfirmSheet: Binding<Bool>
        let isEncryptedMode: Bool
        let colorRefreshToken: UUID
        let template: PitchTemplate?

        var body: some View {
            VStack {
                StrikeZoneView(
                    width: SZwidth,
                    isGame: $isGame,
                    batterSide: batterSide,
                    lastTappedPosition: lastTappedPosition,
                    setLastTapped: setLastTapped,
                    calledPitch: calledPitch,
                    setCalledPitch: setCalledPitch,
                    selectedPitches: selectedPitches,
                    gameIsActive: gameIsActive,
                    selectedPitch: selectedPitch,
                    pitchCodeAssignments: pitchCodeAssignments,
                    isRecordingResult: isRecordingResult,
                    setIsRecordingResult: setIsRecordingResult,
                    setActualLocation: setActualLocation,
                    actualLocationRecorded: actualLocationRecorded,
                    setSelectedPitch: setSelectedPitch,
                    resultVisualState: resultVisualState,
                    setResultVisualState: setResultVisualState,
                    pendingResultLabel: $pendingResultLabel,
                    showResultConfirmation: $showResultConfirmation,
                    showConfirmSheet: showConfirmSheet,
                    isEncryptedMode: isEncryptedMode,
                    template: template
                )
                .id(colorRefreshToken)
            }
            .frame(width: SZwidth, height: 390)
            .background(
                .thickMaterial,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.7), radius: 6, x: 0, y: 6)
        }
    }
    
    @ViewBuilder
    private func strikeZoneArea(width SZwidth: CGFloat) -> some View {
        ZStack(alignment: .top) {
            StrikeZoneCard(
                SZwidth: SZwidth,
                isGame: $isGame,
                batterSide: batterSide,
                lastTappedPosition: lastTappedPosition,
                setLastTapped: { lastTappedPosition = $0 },
                calledPitch: calledPitch,
                setCalledPitch: { calledPitch = $0 },
                selectedPitches: effectivePitchesForStrikeZone,
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
                showConfirmSheet: confirmSheetBinding,
                isEncryptedMode: {
                    if let t = selectedTemplate {
                        return useEncrypted(for: t)
                    }
                    return false
                }(),
                colorRefreshToken: colorRefreshToken,
                template: selectedTemplate
            )
            .overlay(resetOverlay, alignment: .bottomLeading)
            .overlay(sessionOverlay, alignment: .bottom)

            batterSideOverlay(SZwidth: SZwidth)
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
                        // Added per instruction 5: bump progressRefreshToken on practice mode switch
                        progressRefreshToken = UUID()
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
            headerContainer
            Spacer(minLength: 10)
            contentSectionDimmed
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
        // Added per instruction 4: Refresh progress tab token after auto save
        // Ensure Progress tab reflects the latest practice stats immediately
        if overlayTab == .progress && sessionManager.currentMode == .practice {
            progressRefreshToken = UUID()
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
    
    private var baseBody: some View {
        ZStack {
            backgroundView
            mainStack
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    private func handleInitialAppear() {
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
                // Set default encryptedSelectionByGameId to true for all loaded games with id
                for game in loadedGames {
                    if let id = game.id {
                        encryptedSelectionByGameId[id] = true
                    }
                }
            }
            loadEncryptedSelections()
        }
    }
    
    var body: some View {
        baseBody.erasedToAnyView()
        .onChange(of: pendingResultLabel) { _, newValue in
            handlePendingResultChange(newValue)
        }
        .onChange(of: selectedPitches) { _, newValue in
            if let template = selectedTemplate {
                persistActivePitches(for: template.id, active: newValue)
            }
        }
        .onChange(of: encryptedSelectionByGameId) { _, _ in
            persistEncryptedSelections()
            if let t = selectedTemplate {
                let fallbackList = availablePitches(for: t)
                if useEncrypted(for: t) {
                    selectedPitches = Set(fallbackList)
                } else {
                    selectedPitches = loadActivePitches(for: t.id, fallback: fallbackList)
                }
                colorRefreshToken = UUID()
            }
        }
        .onChange(of: encryptedSelectionByPracticeId) { _, _ in
            persistEncryptedSelections()
            if let t = selectedTemplate {
                let fallbackList = availablePitches(for: t)
                if useEncrypted(for: t) {
                    selectedPitches = Set(fallbackList)
                } else {
                    selectedPitches = loadActivePitches(for: t.id, fallback: fallbackList)
                }
                colorRefreshToken = UUID()
            }
        }
        // Added per instruction 6: refresh token bump on overlayTab change to .progress in practice mode
        .onChange(of: overlayTab) { _, newValue in
            if newValue == .progress && sessionManager.currentMode == .practice {
                progressRefreshToken = UUID()
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
        .sheet(isPresented: $showCodeShareSheet) {
            CodeShareSheet(initialCode: buildShareCode(), initialTab: codeShareInitialTab) { code in
                consumeShareCode(code)
            }
            .presentationDetents([.fraction(0.4), .medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPracticeSheet, onDismiss: {
            // If user canceled without creating/choosing, optionally revert to game
            if sessionManager.currentMode == .practice && practiceName == nil && selectedPracticeId == nil {
                // Stay in practice mode but no active session
            }
        }) {
            PracticeSelectionSheet(
                onCreate: { name, date, templateId, templateName in
                    var sessions = loadPracticeSessions()
                    let new = PracticeSession(id: UUID().uuidString, name: name, date: date, templateId: templateId, templateName: templateName)
                    sessions.append(new)
                    savePracticeSessions(sessions)
                },
                onChoose: { practiceId in
                    encryptedSelectionByPracticeId[practiceId] = true
                    if practiceId == "__GENERAL__" {
                        selectedPracticeId = nil
                        practiceName = nil
                        isGame = false
                        let defaults = UserDefaults.standard
                        defaults.set(true, forKey: DefaultsKeys.activeIsPractice)
                        defaults.removeObject(forKey: DefaultsKeys.activeGameId)
                        persistActivePracticeId(nil)
                        defaults.set("tracker", forKey: DefaultsKeys.lastView)
                        sessionManager.switchMode(to: .practice)
                        showPracticeSheet = false
                        return
                    }
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
                },
                currentTemplateId: selectedTemplate?.id.uuidString,
                currentTemplateName: selectedTemplate?.name,
                encryptedSelectionByPracticeId: $encryptedSelectionByPracticeId
            )
            .presentationDetents([.fraction(0.5)])
            .presentationDragIndicator(.visible)
            .environmentObject(authManager)
        }
        .sheet(isPresented: confirmSheetBinding) {
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
                    // Added per instruction 3: bump progressRefreshToken on Practice save when sheet is shown
                    if overlayTab == .progress && sessionManager.currentMode == .practice {
                        progressRefreshToken = UUID()
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
        .onAppear(perform: handleInitialAppear)
        .sheet(isPresented: $showSettings) {
            SettingsView(
                templates: $templates,
                allPitches: allPitches,
                selectedTemplate: $selectedTemplate
            )
            .environmentObject(authManager)
        }
        .onChange(of: selectedTemplate) { _, newValue in
            // Persist and sync dependent state whenever template changes (from menu or Settings)
            persistSelectedTemplate(newValue)
            if let t = newValue {
                let fallbackList = availablePitches(for: t)
                if useEncrypted(for: t) {
                    selectedPitches = Set(fallbackList)
                } else {
                    selectedPitches = loadActivePitches(for: t.id, fallback: fallbackList)
                }
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
                if let t = selectedTemplate {
                    let fallbackList = availablePitches(for: t)
                        if useEncrypted(for: t) {
                            selectedPitches = Set(fallbackList)
                        } else {
                            selectedPitches = loadActivePitches(for: t.id, fallback: fallbackList)
                        }
                    colorRefreshToken = UUID()
                }
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
                    if let t = selectedTemplate {
                        let fallbackList = availablePitches(for: t)
                            if useEncrypted(for: t) {
                                selectedPitches = Set(fallbackList)
                            } else {
                                selectedPitches = loadActivePitches(for: t.id, fallback: fallbackList)
                            }
                        colorRefreshToken = UUID()
                    }
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
        .onReceive(NotificationCenter.default.publisher(for: .templateSelectionDidChange)) { note in
              // If SettingsView sent an explicit templateId, try to resolve it; otherwise just use the current selectedTemplate.
              if let userInfo = note.userInfo as? [String: Any],
                 let tid = userInfo["templateId"] as? String,
                 let resolved = templates.first(where: { $0.id.uuidString == tid }) {
                  applyTemplate(resolved)
              } else if let current = selectedTemplate {
                  // Re-apply to pull in any edits made in the editor and refresh derived state/UI
                  applyTemplate(current)
              }
          }
        .onReceive(NotificationCenter.default.publisher(for: .practiceProgressReset)) { _ in
            authManager.loadPitchEvents { events in
                self.pitchEvents = events
            }
        }
        .overlay(alignment: .bottom) {
            pitchesFacedOverlay
        }
    }
    
    private var pitchesFacedOverlay: some View {
        Group {
            if let batterId = pitchesFacedBatterId {
                ZStack(alignment: .bottom) {
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
                                events: events,
                                templates: templates
                            )
                            .padding(.horizontal)
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.height * 0.33)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .animation(.easeInOut(duration: 0.25), value: pitchesFacedBatterId)
            }
        }
    }

}

private struct ProgressGameView: View {
    @Binding var balls: Int
    @Binding var strikes: Int
    @Binding var inning: Int
    @Binding var hits: Int
    @Binding var walks: Int
    @Binding var us: Int
    @Binding var them: Int
    @Binding var selectedGameId: String?

    @EnvironmentObject var authManager: AuthManager

    @State private var ballToggles: [Bool] = [false, false, false]
    @State private var strikeToggles: [Bool] = [false, false]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ScoreTrackerCompact(usScore: $us, themScore: $them)
                    .padding(.top, 8)
                    .padding(.leading, 12)
                Spacer()
                VStack(alignment: .leading, spacing: 2){
                    InningCounterCompact(inning: $inning)
                        .padding(.top, 9)
                        .padding(.trailing, 8)
                    HitsCounterCompact(hits: $hits)
                        .padding(.trailing, 8)
                    WalksCounterCompact(walks: $walks)
                        .padding(.trailing, 8)
                }
            }
            Divider()
            
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading){
                    Text("  Balls")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 0){
                        ForEach(ballToggles.indices, id: \.self) { idx in
                            toggleChip(isOn: ballBinding(index: idx), activeColor: .red)
                        }
                    }
                }
                .padding(.horizontal, 0)
                .padding(.leading, 10)
                Spacer()
                VStack(alignment: .trailing){
                    Text("Strikes  ")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 0){
                        ForEach(strikeToggles.indices, id: \.self) { idx in
                            toggleChip(isOn: strikeBinding(index: idx), activeColor: .green)
                        }
                    }
                }
                .padding(.horizontal, 0)
                .padding(.trailing, 10)
            }
            .padding(.vertical, -214)
        }
        .padding(.vertical, -6)
        .onAppear {
            let clampedBalls = max(0, min(3, balls))
            let clampedStrikes = max(0, min(2, strikes))
            ballToggles = (0..<3).map { $0 < clampedBalls }
            strikeToggles = (0..<2).map { $0 < clampedStrikes }
        }
        .onChange(of: ballToggles) { _, newValue in
            let newCount = newValue.filter { $0 }.count
            if balls != newCount {
                balls = newCount
                if let gid = selectedGameId {
                    authManager.updateGameBalls(gameId: gid, balls: newCount)
                }
            }
        }
        .onChange(of: strikeToggles) { _, newValue in
            let newCount = newValue.filter { $0 }.count
            if strikes != newCount {
                strikes = newCount
                if let gid = selectedGameId {
                    authManager.updateGameStrikes(gameId: gid, strikes: newCount)
                }
            }
        }
        .onChange(of: balls) { _, newValue in
            let clamped = max(0, min(3, newValue))
            ballToggles = (0..<3).map { $0 < clamped }
        }
        .onChange(of: strikes) { _, newValue in
            let clamped = max(0, min(2, newValue))
            strikeToggles = (0..<2).map { $0 < clamped }
        }
        .onChange(of: selectedGameId) { _, newGameId in
            guard let gid = newGameId else { return }
            authManager.loadGames { games in
                if let game = games.first(where: { $0.id == gid }) {
                    let newBalls = max(0, min(3, game.balls ?? 0))
                    let newStrikes = max(0, min(2, game.strikes ?? 0))
                    balls = newBalls
                    strikes = newStrikes
                    ballToggles = (0..<3).map { $0 < newBalls }
                    strikeToggles = (0..<2).map { $0 < newStrikes }
                }
            }
        }
    }

    // MARK: - Helpers

    private func ballBinding(index: Int) -> Binding<Bool> {
        Binding(
            get: { ballToggles[index] },
            set: { ballToggles[index] = $0 }
        )
    }
    private func strikeBinding(index: Int) -> Binding<Bool> {
        Binding(
            get: { strikeToggles[index] },
            set: { strikeToggles[index] = $0 }
        )
    }
    @ViewBuilder
    private func toggleChip(isOn: Binding<Bool>, activeColor: Color) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                isOn.wrappedValue.toggle()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .imageScale(.medium)
            }
            .foregroundStyle(isOn.wrappedValue ? Color.white : .primary)
            .frame(width: 28, height: 28)
            .background(
                Group {
                    if isOn.wrappedValue {
                        activeColor
                    } else {
                        Color.clear
                    }
                }
            )
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Toggle")
    }
}

struct InningCounterCompact: View {
    @Binding var inning: Int
    
    var body: some View {
        
        HStack(alignment: .center, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    if inning > 1 { inning -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.primary)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                
                // Current inning
                Text("\(inning)")
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 28)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                
                // Increment
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    inning += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.primary)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                
                
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                .ultraThickMaterial,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            
            Text("Inning")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.trailing, 12)
        .padding(.top, 18)
    }
}
struct HitsCounterCompact: View {
    @Binding var hits: Int
    
    var body: some View {
        
        HStack(alignment: .center, spacing: 6) {
            
            HStack(spacing: 6) {
                // Decrement
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    if hits > 0 { hits -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.primary)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                
                // Current inning
                Text("\(hits)")
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 28)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                
                // Increment
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    hits += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.primary)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                
                
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                .ultraThickMaterial,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            
            Text("Hits")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.trailing, 12)
    }
}
struct WalksCounterCompact: View {
    @Binding var walks: Int
    
    var body: some View {
        
        HStack(alignment: .center, spacing: 6) {
            
            HStack(spacing: 6) {
                // Decrement
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    if walks > 0 { walks -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.primary)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                
                // Current inning
                Text("\(walks)")
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 28)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                
                // Increment
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    walks += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.primary)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                
                
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                .ultraThickMaterial,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            
            Text("Walks")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.trailing, 12)
    }
}
struct ScoreTrackerCompact: View {
    @Binding var usScore: Int
    @Binding var themScore: Int
    
    var body: some View {
        VStack(alignment: .center) {
            Text("Score")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 0) {
                // Us row with label above
                VStack(spacing: 1) {   // no extra spacing
                    Text("us")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2) // optional, keep horizontal only
                    scoreRow(score: $usScore)
                }
                .padding(.bottom, 2)
                // Them row with label below
                VStack(spacing: 1) {   // no extra spacing
                    scoreRow(score: $themScore)
                    Text("them")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2) // optional, keep horizontal only
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                .ultraThickMaterial,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            .fixedSize()
        }
        .padding(.top, 16)
    }
    
    // MARK: - Row (no leading label)
    private func scoreRow(score: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            // Decrement
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                if score.wrappedValue > 0 { score.wrappedValue -= 1 }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.primary)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            
            // Score Display
            Text("\(score.wrappedValue)")
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 32)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
            
            // Increment
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                score.wrappedValue += 1
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.primary)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
    }
}

private struct ProgressSummaryView: View {
    let events: [PitchEvent]
    let currentMode: PitchMode
    let selectedPracticeId: String?
    let templates: [PitchTemplate]
    
    @State private var isReset: Bool = false
    
    private func didHitLocation(_ event: PitchEvent) -> Bool {
        return isLocationMatch(event)
    }
    
    private var practiceEvents: [PitchEvent] {
        if isReset { return [] }
        return events.filter { ev in
            guard ev.mode == .practice else { return false }
            if let pid = selectedPracticeId {
                return ev.practiceId == pid
            }
            return true
        }
    }
    
    private var totalCount: Int { practiceEvents.count }
    private var strikeCount: Int { practiceEvents.filter { $0.isStrike == true }.count }
    private var ballCount: Int { practiceEvents.filter { $0.isStrike == false }.count }
    private var hitSpotCount: Int {
        practiceEvents.filter { ev in
            didHitLocation(ev)
        }.count
    }
    
    private var strikeHitSpotCount: Int {
        practiceEvents.filter { ev in
            (ev.isStrike == true || ev.strikeLooking == true || ev.strikeSwinging == true) && didHitLocation(ev)
        }.count
    }

    private var ballHitSpotCount: Int {
        practiceEvents.filter { ev in
            !(ev.isStrike == true || ev.strikeLooking == true || ev.strikeSwinging == true) && didHitLocation(ev)
        }.count
    }
    
    private func percent(_ part: Int, of total: Int) -> String {
        guard total > 0 else { return "0%" }
        let p = (Double(part) / Double(total)) * 100.0
        return String(format: "%.0f%%", p.rounded())
    }
    
    private func templateName(for id: String?) -> String {
        if let tid = id, let t = templates.first(where: { $0.id.uuidString == tid }) {
            return t.name
        }
        return "-"
    }

    private var pitchStats: [(pitch: String, templateId: String?, templateName: String, hits: Int, attempts: Int, percent: Double)] {
        // Aggregate attempts and hits per (pitch, template) based on matching actual == called location
        var dict: [String: (hits: Int, attempts: Int, templateId: String?)] = [:]
        for ev in practiceEvents {
            guard let call = ev.calledPitch else { continue }
              let hit = didHitLocation(ev)
            let name = ev.pitch
            let tid = ev.templateId
            let key = (name) + "|" + (tid ?? "-")

            var current = dict[key] ?? (hits: 0, attempts: 0, templateId: tid)
            current.attempts += 1
            if didHitLocation(ev) {
                current.hits += 1
            }
            dict[key] = current
        }

        // Convert to array and sort by highest success rate, then by attempts
        let mapped: [(pitch: String, templateId: String?, templateName: String, hits: Int, attempts: Int, percent: Double)] = dict.map { (key, value) in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            let pitchName = parts.first ?? "-"
            let tid = value.templateId
            let tname = templateName(for: tid)
            let pct = value.attempts > 0 ? Double(value.hits) / Double(value.attempts) : 0.0
            return (pitch: pitchName, templateId: tid, templateName: tname, hits: value.hits, attempts: value.attempts, percent: pct)
        }
        // Debug summary after mapping to avoid capturing before declaration
        let debugSummary = mapped.map { item in
            "\(item.pitch) [t: \(item.templateName)] hits: \(item.hits)/\(item.attempts) pct: \(String(format: "%.2f", item.percent))"
        }.joined(separator: "\n")
        print("[Metrics] pitchStats summary:\n\(debugSummary)")
        return mapped.sorted { lhs, rhs in
            if lhs.percent == rhs.percent { return lhs.attempts > rhs.attempts }
            return lhs.percent > rhs.percent
        }
    }
    
    private var pitchRanking: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for ev in practiceEvents {
            print("[Metrics] Ranking consider id=\(ev.id ?? "-") pitch=\(ev.pitch ?? "-") hasCall=\(ev.calledPitch != nil) didHit=\(didHitLocation(ev))")
            guard ev.calledPitch != nil else { continue }
            guard didHitLocation(ev) else { continue }
            let name = ev.pitch
            guard !name.isEmpty else { continue }
            print("[Metrics]  Increment ranking for \(name)")
            counts[name, default: 0] += 1
        }

        let rankingArray: [(name: String, count: Int)] = counts.map { (key, value) in
            (name: key, count: value)
        }

        let summary = rankingArray.map { "\($0.name): \($0.count)" }.joined(separator: ", ")
        print("[Metrics] pitchRanking counts: \(summary)")

        return rankingArray.sorted { lhs, rhs in
            if lhs.count == rhs.count { return lhs.name < rhs.name }
            return lhs.count > rhs.count
        }
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            // Centered table with flanking metric stacks
            HStack(alignment: .top, spacing: 16) {
                // Left metrics (vertical)
                VStack(spacing: 10) {
                    Text("Total")
                        .font(Font.caption.italic())
                        .padding(.bottom, -4)
                    metricCard(title: "# Pitches", value: "\(totalCount)")
                    metricCard(title: "% Hit Spot", value: percent(hitSpotCount, of: max(totalCount, 1)))
                }
                .frame(maxWidth: 80)
                
                // Center: Header + Table (constrained and centered)
                VStack(spacing: 8) {
                    Text("Hit Spot Performance")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if pitchStats.isEmpty {
                                Text("No data yet.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                ForEach(Array(pitchStats.enumerated()), id: \.offset) { idx, item in
                                    let percentString = percent(item.hits, of: max(item.attempts, 1))
                                    HStack(alignment: .firstTextBaseline) {
                                        Text("\(idx + 1). \(item.pitch) — \(item.hits)/\(item.attempts) (\(percentString))")
                                            .font(.subheadline)
                                        Spacer()
                                    }
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 8)
                                    .background(
                                        .ultraThinMaterial,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .frame(maxWidth: 480)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.never)
                }
                .frame(maxWidth: .infinity)
                
                // Right metrics (vertical)
                VStack(spacing: 10) {
                    Text("Hit Spot")
                        .font(Font.caption.italic())
                        .padding(.bottom, -4)
                    metricCard(title: "Strike %", value: percent(strikeHitSpotCount, of: max(strikeCount, 1)))
                    metricCard(title: "Ball %", value: percent(ballHitSpotCount, of: max(ballCount, 1)))
                }
                .frame(maxWidth: 80)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal)
        .offset(y: 20)
        .onReceive(NotificationCenter.default.publisher(for: .practiceProgressReset)) { notification in
            guard let userInfo = notification.userInfo as? [String: Any], let pid = userInfo["practiceId"] as? String? else { return }
            // If current view is showing the same practice session (or general when nil), reset displayed stats
            if pid == selectedPracticeId {
                isReset = true
            }
        }
    }
    
    @ViewBuilder
    private func metricCard(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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

    @State private var showActionsSheet: Bool = false
    @State private var showDeleteConfirm: Bool = false

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
            .onLongPressGesture {
                selectedBatterId = cell.id
                showActionsSheet = true
            }
            .onDrop(of: [UTType.text], delegate: JerseyDropDelegate(current: cell, items: $jerseyCells, dragging: $draggingJersey))
            .sheet(isPresented: $showActionsSheet) {
                VStack(alignment: .leading, spacing: 12) {
                    
                    Text("Batter #\(cell.jerseyNumber)")
                        .font(.headline)
                        .padding(.bottom, 4)
                        
                    HStack {
                        Button {
                            // Pitches Faced
                            selectedBatterId = cell.id
                            pitchesFacedBatterId = cell.id
                            showActionsSheet = false
                        } label: {
                            Label("Pitches Faced", systemImage: "baseball")
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

                        Spacer()

                        Button {
                            // Edit Number
                            editingCell = cell
                            newJerseyNumber = cell.jerseyNumber
                            showAddJerseyPopover = true
                            showActionsSheet = false
                        } label: {
                            Label("Edit Number", systemImage: "pencil")
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }

                    Divider()
                    
                    Color.clear.frame(height: 8)
                    
                    HStack{
                        Spacer()
                        Button {
                            // Move Up
                            if let idx = jerseyCells.firstIndex(where: { $0.id == cell.id }), idx > 0 {
                                withAnimation {
                                    let item = jerseyCells.remove(at: idx)
                                    jerseyCells.insert(item, at: idx - 1)
                                }
                                if let gameId = selectedGameId {
                                    authManager.updateGameLineup(gameId: gameId, jerseyNumbers: jerseyCells.map { $0.jerseyNumber })
                                }
                                NotificationCenter.default.post(name: .jerseyOrderChanged, object: jerseyCells.map { $0.jerseyNumber })
                            }
                        } label: {
                            Label("Move Up", systemImage: "arrow.up")
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        Spacer()
                        Button {
                            // Move Down
                            if let idx = jerseyCells.firstIndex(where: { $0.id == cell.id }), idx < jerseyCells.count - 1 {
                                withAnimation {
                                    let item = jerseyCells.remove(at: idx)
                                    jerseyCells.insert(item, at: idx + 1)
                                }
                                if let gameId = selectedGameId {
                                    authManager.updateGameLineup(gameId: gameId, jerseyNumbers: jerseyCells.map { $0.jerseyNumber })
                                }
                                NotificationCenter.default.post(name: .jerseyOrderChanged, object: jerseyCells.map { $0.jerseyNumber })
                            }
                        } label: {
                            Label("Move Down", systemImage: "arrow.down")
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        Spacer()
                    }
                    
                    Color.clear.frame(height: 8)

                    Divider()
                    
                    Color.clear.frame(height: 8)
                    
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .padding()
                .presentationDetents([.fraction(0.35), .medium])
                .confirmationDialog(
                    "Delete Batter?",
                    isPresented: $showDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        if let idx = jerseyCells.firstIndex(where: { $0.id == cell.id }) {
                            jerseyCells.remove(at: idx)
                            if let gameId = selectedGameId {
                                authManager.updateGameLineup(gameId: gameId, jerseyNumbers: jerseyCells.map { $0.jerseyNumber })
                            }
                            if selectedBatterId == cell.id {
                                selectedBatterId = nil
                            }
                        }
                        showActionsSheet = false
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will remove this batter from the lineup.")
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

struct CodeOrderToggle: View {
    @Binding var pitchFirst: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("Code Order")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: $pitchFirst) {
                Text("Pitch 1st")
                    .tag(true)

                Text("Location 1st")
                    .tag(false)
            }
            .controlSize(.mini)
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
    }
}

struct CalledPitchView: View {
    @State private var showResultOverlay = false
    @State private var selectedActualLocation: String?
    @State private var tappedCode: String?
    @AppStorage(PitchTrackerView.DefaultsKeys.practiceCodesEnabled) private var codesEnabled: Bool = true
    @Binding var isRecordingResult: Bool
    @Binding var activeCalledPitchId: String?
    @Binding var pitchFirst: Bool
    let call: PitchCall
    let pitchCodeAssignments: [PitchCodeAssignment]
    let batterSide: BatterSide
    let template: PitchTemplate?
    let isEncryptedMode: Bool
    let isPracticeMode: Bool
    
    private func reorderedCodeIfNeeded(_ code: String) -> String {
        // When pitchFirst is false (Location 1st), swap first two and last two characters of a 4-char code.
        // If the code isn't exactly 4 characters, leave it unchanged.
        if !pitchFirst, code.count == 4 {
            let start = code.startIndex
            let mid = code.index(start, offsetBy: 2)
            let firstTwo = code[start..<mid]
            let lastTwo = code[mid..<code.endIndex]
            return String(lastTwo + firstTwo)
        }
        return code
    }
    
    var body: some View {
        let displayLocation = call.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let assignments = pitchCodeAssignments.filter {
              $0.pitch == call.pitch &&
              $0.location.trimmingCharacters(in: .whitespacesAndNewlines) == displayLocation
          }

          // In encrypted mode, prefer the generated codes already carried on the call.
          // In classic mode, show assigned codes (deciphered via template when present).
          let displayCodes: [String] = {
              if isEncryptedMode {
                  return call.codes
              } else {
                  if let template = template {
                      return assignments.map { decipherDisplayCode(from: $0, using: template) }
                  } else {
                      return assignments.map(\.code)
                  }
              }
          }()

        let isStrike = call.type == "Strike"
        
        let callColor: Color = isStrike ? .green : .red
        
        return HStack(spacing: 12) {
            // Left: Details
            VStack(alignment: .leading, spacing: 8) {
                HStack(){
                    Spacer()
                    VStack(){
                        // Header row: title + call badge
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Called Pitch")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            
                        }
                        // Big pitch name
                        Text(call.pitch)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    
                    PitchResultBanner(isRecording: isRecordingResult, callColor: callColor)
                    Spacer()
                }
                // Assigned codes as chips
                if !displayCodes.isEmpty && (!isPracticeMode || codesEnabled) {
                       ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(displayCodes, id: \.self) { code in
                                let shown = reorderedCodeIfNeeded(code)
                                Button {
                                    // Haptic feedback + trigger recording
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()
                                    tappedCode = code
                                    isRecordingResult = true
                                } label: {
                                    ZStack {
                                        // Base chip background
                                        Capsule()
                                            .fill(callColor.opacity(0.85))
                                        
                                        // Highlight overlay when tapped
                                        if tappedCode == code {
                                            Capsule()
                                                .fill(.white)
                                                .stroke(Color.black.opacity(0.9), lineWidth: 2)
                                                .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 0)
                                                .transition(.opacity)
                                        }
                                        if tappedCode == code {
                                            Text(shown)
                                                .font(.title3.weight(.semibold))
                                                .foregroundColor(callColor.opacity(0.85))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                        } else {
                                            Text(shown)
                                                .font(.title3.weight(.semibold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                        }
                                    }
                                    .frame(height: 32)
                                    .animation(.easeInOut(duration: 0.15), value: tappedCode)
                                }
                                .buttonStyle(.plain) // preserve chip styling
                                .accessibilityLabel("Record for code \(shown)")
                            }
                        }
                        .frame(height: 60)
                    }
                    .padding(.top, 2)
                    // Code order toggle (hidden in practice when codes are Off)
                    if !isPracticeMode || codesEnabled {
                        CodeOrderToggle(pitchFirst: $pitchFirst)
                    }
                    
                } else {
                    // Keep CalledPitchView height stable when Codes are turned Off in Practice
                    if isPracticeMode && !codesEnabled && !displayCodes.isEmpty {
                        // Reserve the chips area height
                        Color.clear
                            .frame(height: 60)
                            .padding(.top, 2)
                        // Reserve space for the CodeOrderToggle to prevent layout jump
                        CodeOrderToggle(pitchFirst: $pitchFirst)
                            .hidden()
                    } else if !isEncryptedMode {
                        Text("No assigned calls for this pitch/location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                // Practice-only: Codes On/Off toggle
                if isPracticeMode {
                    
                    HStack(spacing: 8) {
                        Spacer()
                        Text("Codes:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("", isOn: $codesEnabled)
                            .labelsHidden()
                        Text(codesEnabled ? "On" : "Off")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                
                
            }
        }
        .padding(14)
        .background(
            .thickMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 4)
        .padding(.horizontal)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .onAppear {
            if isPracticeMode {
                // If Codes are Off, allow choosing result without tapping a code first
                isRecordingResult = !codesEnabled
            }
        }
        .onChange(of: codesEnabled) { _, newValue in
            if isPracticeMode {
                // When turning Codes Off, immediately allow result selection; when On, require code tap again
                isRecordingResult = !newValue
                tappedCode = nil
            }
        }
        
    }
}

struct PitchResultBanner: View {
    let isRecording: Bool
    let callColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isRecording ? "checkmark.circle.fill" : "hand.tap.fill")
                .font(.caption.bold())

            Text(isRecording ? "Choose a pitch result" : "Tap a Code")
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(callColor.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: callColor.opacity(0.15), radius: 3, x: 0, y: 2)
        .padding(.top, 6)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.easeInOut(duration: 0.25), value: isRecording)
        .accessibilityLabel(isRecording ? "Choose a pitch result" : "Tap a Code")
    }
}
private struct CodeShareSheet: View {
    let initialCode: String
    let onConsume: (String) -> Void
    let initialTab: Int
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Int // 0 generate, 1 enter
    @State private var generated: String
    @State private var entered: String = ""

    init(initialCode: String, initialTab: Int = 0, onConsume: @escaping (String) -> Void) {
        self.initialCode = initialCode
        self.onConsume = onConsume
        self.initialTab = initialTab
        _generated = State(initialValue: initialCode)
        _tab = State(initialValue: initialTab)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if tab == 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Share this code with your partner:")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        
                        TextEditor(text: $generated)
                            .font(.callout.monospaced())
                            .frame(minHeight: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .disabled(true)
                        
                        HStack {
                            Button {
                                UIPasteboard.general.string = generated
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            
                            ShareLink(item: generated) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Paste the code from your partner:")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        
                        TextEditor(text: $entered)
                            .font(.callout.monospaced())
                            .frame(minHeight: 100)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                        
                        Button {
                            onConsume(entered.trimmingCharacters(in: .whitespacesAndNewlines))
                            dismiss()
                        } label: {
                            Label("Join", systemImage: "arrow.right.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(entered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Code Link")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
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
                } else {
                    Section() {
                        ForEach(games) { game in
                            HStack {
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
                            }
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

struct AddPracticeCard: View {
    @Binding var practiceName: String
    @Binding var practiceDate: Date
    var templateName: String?
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Practice Session")
                    .font(.headline)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            if let templateName, !templateName.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .foregroundColor(.secondary)
                    Text("Template: \(templateName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("No template selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            TextField("Session name", text: $practiceName)
                .textFieldStyle(.roundedBorder)

            DatePicker("Date & Time", selection: $practiceDate, displayedComponents: [.date, .hourAndMinute])

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(practiceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
    let templates: [PitchTemplate]

    private static let columns: [GridItem] = [
        GridItem(.flexible(minimum: 80), spacing: 8, alignment: .leading),
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
                    Text("Pitcher").font(.subheadline.bold())

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

                        // Column 4: Pitcher (Template Name)
                        Text(templateName(for: event))
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
    
    private func templateName(for event: PitchEvent) -> String {
        if let tid = event.templateId, let t = templates.first(where: { $0.id.uuidString == tid }) {
            return t.name
        }
        return "-"
    }
}

extension View {
    func erasedToAnyView() -> AnyView {
        AnyView(self)
    }
}

struct PracticeSession: Identifiable, Codable {
    var id: String?
    var name: String
    var date: Date
    var templateId: String?
    var templateName: String?
}

struct PracticeSelectionSheet: View {
    var onCreate: (String, Date, String?, String?) -> Void
    var onChoose: (String) -> Void
    var onCancel: () -> Void
    
    var currentTemplateId: String?
    var currentTemplateName: String?
    
    @Binding var encryptedSelectionByPracticeId: [String: Bool]

    @State private var sessions: [PracticeSession] = []
    @State private var showAddPopover: Bool = false
    @State private var newName: String = ""
    @State private var newDate: Date = Date()
    
    @State private var pendingDeleteSessionId: String? = nil
    @State private var showDeleteSessionConfirm: Bool = false
    
    // Added for reset progress
    @State private var showResetConfirm: Bool = false
    @State private var pendingResetPracticeId: String? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager

    // Added method as per instructions
    private func deleteSession(withId id: String) {
        // 1) Remove from local list
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions.remove(at: idx)
        }
        // 2) Remove from UserDefaults persistence
        let key = PitchTrackerView.DefaultsKeys.storedPracticeSessions
        if let data = UserDefaults.standard.data(forKey: key),
           var decoded = try? JSONDecoder().decode([PracticeSession].self, from: data) {
            decoded.removeAll { $0.id == id }
            if let newData = try? JSONEncoder().encode(decoded) {
                UserDefaults.standard.set(newData, forKey: key)
            }
        }
        // 3) Clear active selection if it matches the deleted id
        let activeKey = PitchTrackerView.DefaultsKeys.activePracticeId
        if let activeId = UserDefaults.standard.string(forKey: activeKey), activeId == id {
            UserDefaults.standard.removeObject(forKey: activeKey)
        }
        // 4) Notify host view to clear UI if needed
        NotificationCenter.default.post(name: .gameOrSessionDeleted, object: nil, userInfo: ["type": "practice", "practiceId": id])
        // 5) Reset pending state
        pendingDeleteSessionId = nil
    }

    @ViewBuilder
    private func sessionRow(session: PracticeSession) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(session.name)
                .font(.headline)
            Text(Self.formatter.string(from: session.date))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        Spacer()
    }

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    // Optional empty state
                } else {
                    Section() {
                        ForEach(sessions) { session in
                            HStack {
                                Button(action: {
                                    encryptedSelectionByPracticeId[session.id ?? "__GENERAL__"] = true
                                    // Trigger selection: call back with id and dismiss
                                    if let id = session.id {
                                        onChoose(id)
                                    } else {
                                        // Fallback to general when no id is present
                                        onChoose("__GENERAL__")
                                    }
                                    dismiss()
                                }) {
                                    sessionRow(session: session)
                                }
                                .buttonStyle(.plain)
                                
                                Spacer(minLength: 8)

                                Button {
                                    if let id = session.id {
                                        pendingResetPracticeId = id
                                        showResetConfirm = true
                                    }
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                        .foregroundColor(.secondary)
                                        .imageScale(.medium)
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Reset progress for session")
                            }
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
                deleteSession(withId: id)
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteSessionId = nil
            }
        } message: {
            Text("This will remove the session from this device.")
        }
        .confirmationDialog(
            "Reset Progress?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                let id = pendingResetPracticeId
                authManager.deletePracticeEvents(practiceId: id) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            NotificationCenter.default.post(name: .practiceProgressReset, object: nil, userInfo: ["practiceId": id as Any])
                        case .failure(let error):
                            print("Failed to delete practice events: \(error)")
                        }
                        pendingResetPracticeId = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingResetPracticeId = nil
            }
        } message: {
            Text("This will clear the displayed progress for this session.")
        }
        .overlay(
            Group {
                if showAddPopover {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .onTapGesture { showAddPopover = false }

                        AddPracticeCard(
                            practiceName: $newName,
                            practiceDate: $newDate,
                            templateName: currentTemplateName,
                            onCancel: { showAddPopover = false },
                            onSave: {
                                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !name.isEmpty else { return }
                                onCreate(name, newDate, currentTemplateId, currentTemplateName)
                                // Reload sessions from UserDefaults so IDs match the persisted source
                                if let data = UserDefaults.standard.data(forKey: PitchTrackerView.DefaultsKeys.storedPracticeSessions),
                                   let decoded = try? JSONDecoder().decode([PracticeSession].self, from: data) {
                                    self.sessions = decoded
                                    // Set encryptedSelectionByPracticeId to true for newly added session id
                                    if let session = decoded.first(where: { $0.name == name && Calendar.current.isDate($0.date, inSameDayAs: newDate) }), let sid = session.id {
                                        encryptedSelectionByPracticeId[sid] = true
                                    }
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
                // Set default encryptedSelectionByPracticeId to true for all loaded sessions with id
                for session in decoded {
                    encryptedSelectionByPracticeId[session.id ?? "__GENERAL__"] = true
                }
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

struct BallStrikeToggle: View {
    @State private var isBall: Bool = false
    @State private var isStrike: Bool = false
    var mutualExclusion: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            toggleButton(title: "Ball", isOn: isBall, onTap: {
                if mutualExclusion {
                    if !isBall { isStrike = false }
                }
                isBall.toggle()
            }, activeColor: .red)

            toggleButton(title: "Strike", isOn: isStrike, onTap: {
                if mutualExclusion {
                    if !isStrike { isBall = false }
                }
                isStrike.toggle()
            }, activeColor: .green)
        }
    }

    @ViewBuilder
    private func toggleButton(title: String, isOn: Bool, onTap: @escaping () -> Void, activeColor: Color) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) { onTap() }
        }) {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .imageScale(.medium)
                Text(title)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(isOn ? Color.white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isOn {
                        activeColor
                    } else {
                        Color.clear
                    }
                }
            )
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Toggle \(title)")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}












