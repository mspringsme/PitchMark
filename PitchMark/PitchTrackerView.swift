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
import FirebaseAuth
import UniformTypeIdentifiers
import UIKit
import AVFoundation
import CoreImage.CIFilterBuiltins

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
// ✅ Move game-sync wrapping into a View extension (faster to type-check)
private extension View {
    func withGameSync(
        start: @escaping () -> Void,
        stop: @escaping () -> Void,
        gameId: String?,
        ownerId: String?,
        isGame: Bool
    ) -> some View {
        self
            .onAppear { start() }
            .onChange(of: gameId) { _, _ in start() }
            .onChange(of: ownerId) { _, _ in start() }
            .onChange(of: isGame) { _, _ in start() }
            .onDisappear { stop() }
    }
    func eraseToAnyView() -> AnyView { AnyView(self) }
}

struct PitchTrackerView: View {
    @State private var mirroredLivePitchEventIds: Set<String> = []
    @State private var didAutoDismissCodeSheetForLiveId: String? = nil
    @State private var uiConnected: Bool = false
    @State private var showCodeAssignmentSheet = false
    @State private var pitcherName: String = ""
    @State private var selectedPitches: Set<String> = []
    @State private var calledPitch: PitchCall? = nil
    @State private var lastCallInitiatedAt: Date? = nil
    @State private var lastObservedPendingCallId: String? = nil
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
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var showProfileSheet = false
    @State private var showSignOutConfirmation = false
    @State private var selectedTemplate: PitchTemplate? = nil
    @State private var showTemplateEditor = false
    @State private var showInviteJoinSheet = false
    @State private var inviteJoinText: String = ""
    @State private var inviteJoinError: String? = nil
    @State private var showProPaywall = false
    @State private var showProGateAlert = false
    @State private var proGateMessage: String = ""
    @State private var showCameraPicker = false
    @State private var showCameraUnavailableAlert = false
    @State private var showCameraPermissionAlert = false
    @State private var showQRScanner = false
    @State private var pitchers: [Pitcher] = []
    @State private var selectedPitcherId: String? = nil
    @State private var isRecordingResult = false
    @State private var activeCalledPitchId: String? = nil
    @State private var deferredPendingPitch: Game.PendingPitch? = nil
    @State private var deferredDisplayCode: (colorName: String, code: String)? = nil
    @State private var actualLocationRecorded: String? = nil
    @State private var resultVisualState: String? = nil
    @State private var pendingResultLabel: String? = nil
    @State private var autoPitchOnlyEnabled: Bool = false
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
    @State private var showGameStatsSheet = false
    @State private var opponentName: String? = nil
    @State private var selectedGameId: String? = nil
    // Participant overlay state
    @State private var showParticipantOverlay: Bool = false
    @State private var ownerTemplateName: String? = nil
    @State private var showPracticeSheet = false
    @State private var practiceName: String? = nil
    @State private var selectedPracticeId: String? = nil
    
    @State private var jerseyCells: [JerseyCell] = sampleJerseyCells
    @State private var draggingJersey: JerseyCell?
    @State private var showAddJerseyPopover = false
    @State private var newJerseyNumber: String = ""
    @State private var showBulkJerseyPrompt = false
    @State private var showBulkJerseyInput = false
    @State private var bulkJerseyNumbers: String = ""
    @State private var selectedBatterId: UUID? = nil
    @State private var selectedBatterJersey: String? = nil
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
    @State private var lastAppliedTemplateId: UUID? = nil
    @State private var pendingGameConfirmation: PendingSessionConfirmation? = nil
    @State private var pendingConfirmationPitcherId: String? = nil
    @State private var pendingConfirmationTemplateId: UUID? = nil

    // Added per instructions:
    @State private var encryptedSelectionByGameId: [String: Bool] = [:]
    @State private var encryptedSelectionByPracticeId: [String: Bool] = [:]
    
    // Added progressRefreshToken as per instruction 1
    @State private var progressRefreshToken = UUID()

    fileprivate enum OverlayTab { case cards, progress }
    @State private var overlayTab: OverlayTab = .progress

    enum DefaultsKeys {
        static let lastTemplateId = "lastTemplateId"
        static let lastBatterSide = "lastBatterSide"
        static let lastMode = "lastMode"
        static let activePitchesPrefix = "activePitches."
        static let lastView = "lastView"
        static let activeGameId = "activeGameId"
        static let activeIsPractice = "activeIsPractice"
        static let activePracticeId = "activePracticeId"
        static let storedPracticeSessions = "storedPracticeSessions"
        static let lastPitcherId = "lastPitcherId"
        static let lastTemplateByGameId = "lastTemplateByGameId"
        static let lastPitcherByGameId = "lastPitcherByGameId"
        static let encryptedByGameId = "encryptedByGameId"
        static let encryptedByPracticeId = "encryptedByPracticeId"
        static let practiceCodesEnabled = "practiceCodesEnabled"
        static let activeGameOwnerUserId = "activeGameOwnerUserId"
        static let displayOnlyLiveId = "displayOnlyLiveId"
        static let displayOnlyMode = "displayOnlyMode"
        static let hiddenTemplateIds = "hiddenTemplateIds"
        static let hiddenPitcherIds = "hiddenPitcherIds"
        static let lastBackgroundAt = "lastBackgroundAt"
        static let forceSettingsOnNextLaunch = "forceSettingsOnNextLaunch"
        static let lastProgressByGameId = "lastProgressByGameId"
    }

    private struct LocalProgressSnapshot: Codable {
        let balls: Int
        let strikes: Int
        let inning: Int
        let hits: Int
        let walks: Int
        let us: Int
        let them: Int
        let updatedAt: TimeInterval
    }
    @State private var isSelecting: Bool = false
    @State private var selectedEventIDs: Set<String> = []
    @State private var localTemplateOverrides: [String: String] = [:]
    @State private var pitchFirst = true
    @State private var showCodeShareSheet = false
    @State private var showCodeShareModePicker = false
    @State private var codeShareInitialTab: Int = 0 // 0 = Generate, 1 = Enter
    @State private var showSelectGameFirstAlert = false
    @State private var showCodeShareErrorAlert = false
    @State private var codeShareErrorMessage: String = ""
    @State private var shareCode: String = ""
    @AppStorage(DefaultsKeys.displayOnlyMode) private var isDisplayOnlyMode: Bool = false
    @AppStorage(DefaultsKeys.displayOnlyLiveId) private var displayOnlyLiveIdStorage: String = ""
    @State private var displayOnlyLiveId: String? = nil
    @State private var displayCodePayload: CodeDisplayOverlayPayload? = nil
    @State private var displayCodeClearWork: DispatchWorkItem? = nil
    @State private var displayListener: ListenerRegistration? = nil
    @State private var displayStateListener: ListenerRegistration? = nil
    @State private var displayHeartbeatTimer: Timer? = nil
    @State private var displaySessionListener: ListenerRegistration? = nil
    @State private var showSessionConflictAlert = false
    @State private var showDisplayAppMissingAlert = false
    @State private var sessionCheckInProgress = false
    @State private var autoLiveCreateInProgress = false
    @State private var didAutoCreateLiveSessionForGameId: String? = nil
    @State private var activeGameOwnerUserId: String? = nil
    @State private var gameListener: ListenerRegistration? = nil
    @State private var livePitchEventsListener: ListenerRegistration? = nil
    @State private var gamePitchEventsListener: ListenerRegistration? = nil
    @State private var gamePitchEvents: [PitchEvent] = []
    @State private var lastLocalProgressUpdate: Date? = nil
    @State private var bufferedSharedPitcherEvents: [BufferedPitcherEvent] = []
    @State private var lastObservedResultSelectionId: String? = nil
    @State private var codeShareSheetID = UUID()
    // MARK: - Startup gating (prevents sheet-flash on launch)

    private enum StartupPhase { case launching, ready }
    private struct BufferedPitcherEvent: Codable {
        let pitcherId: String
        let event: PitchEvent
    }

    @State private var startupPhase: StartupPhase = .launching
    @State private var isRestoringState = false

    // ✅ Live-room mirrored scoreboard fields (used when activeLiveId != nil)
    @State private var balls: Int = 0
    @State private var strikes: Int = 0
    @State private var inning: Int = 1
    @State private var hits: Int = 0
    @State private var walks: Int = 0
    @State private var us: Int = 0
    @State private var them: Int = 0
    @State private var heartbeatTimer: Timer? = nil
    @State private var isJoiningSession: Bool = false
    @State private var pendingRestoreGameId: String? = nil
    @State private var pendingLiveTemplateId: String? = nil
    @State private var pendingLiveTemplateName: String? = nil
    @State private var liveTemplateOverrideLocked: Bool = false

    private func dismissAllTopLevelSheets() {
        showSettings = false
        showGameSheet = false
        showPracticeSheet = false
        showCodeShareSheet = false
        showCodeAssignmentSheet = false
        // NOTE: do NOT touch confirmSheetBinding/showConfirmSheet here unless you truly want to cancel it.
    }

    private func presentExclusive(settings: Bool = false, game: Bool = false, practice: Bool = false) {
        dismissAllTopLevelSheets()
        if settings { showSettings = true }
        else if game { showGameSheet = true }
        else if practice { showPracticeSheet = true }
    }

    /// Call once after boot to choose exactly one initial sheet (if needed)
    private func presentInitialSheetIfNeeded() {
        guard authManager.isSignedIn else { return }
        guard startupPhase == .ready else { return }

        // 1) If no template, push user to Settings first
        if selectedTemplate == nil {
            presentExclusive(settings: true)
            return
        }

        // 2) If mode is game and no game selected, open game picker
        if sessionManager.currentMode == .game, selectedGameId == nil {
            presentExclusive(game: true)
            return
        }

        // 3) If mode is practice and no practice selected, open practice picker
        if sessionManager.currentMode == .practice, selectedPracticeId == nil {
            presentExclusive(practice: true)
            return
        }

        // Otherwise: nothing needed; user can use PitchTrackerView immediately.
    }
 
    private func hydrateChosenGameUI(ownerUid: String, gameId: String) {
        // ✅ FAST PATH: use local cached games immediately (no network)
        if let local = self.games.first(where: { ($0.id ?? "") == gameId }) {
            // IDs + owner
            self.selectedGameId = local.id ?? gameId
            self.activeGameOwnerUserId = ownerUid

            // Make the "Game" button show opponent immediately
            self.opponentName = local.opponent

            // Build jersey cells
            if let ids = local.batterIds, ids.count == local.jerseyNumbers.count {
                self.jerseyCells = zip(ids, local.jerseyNumbers).map { (idStr, num) in
                    JerseyCell(id: UUID(uuidString: idStr) ?? UUID(), jerseyNumber: num)
                }
            } else {
                // Temporary cells immediately, then migrate in background
                let tempIds = local.jerseyNumbers.map { _ in UUID().uuidString }
                self.jerseyCells = zip(tempIds, local.jerseyNumbers).map {
                    JerseyCell(id: UUID(uuidString: $0.0) ?? UUID(), jerseyNumber: $0.1)
                }
                let gid = local.id ?? gameId
                self.authManager.migrateBatterIdsIfMissing(ownerUserId: ownerUid, gameId: gid)
            }

            // Match your existing selection side-effects
            self.selectedBatterId = nil
            self.ownerTemplateName = self.selectedTemplate?.name
            self.showParticipantOverlay = !self.isOwnerForActiveGame

            return
        }

        // ✅ SLOW FALLBACK: only if the game wasn't already in memory (rare)
        let ref = Firestore.firestore()
            .collection("users").document(ownerUid)
            .collection("games").document(gameId)

        ref.getDocument { snap, err in
            if let err = err {
                print("❌ hydrateChosenGameUI getDocument error:", err)
                return
            }
            guard let snap, snap.exists else {
                print("⚠️ hydrateChosenGameUI missing game doc:", ref.path)
                return
            }

            DispatchQueue.main.async {
                do {
                    let game = try snap.data(as: Game.self)

                    self.selectedGameId = game.id ?? gameId
                    self.activeGameOwnerUserId = ownerUid
                    self.opponentName = game.opponent

                    if let ids = game.batterIds, ids.count == game.jerseyNumbers.count {
                        self.jerseyCells = zip(ids, game.jerseyNumbers).map { (idStr, num) in
                            JerseyCell(id: UUID(uuidString: idStr) ?? UUID(), jerseyNumber: num)
                        }
                    } else {
                        let tempIds = game.jerseyNumbers.map { _ in UUID().uuidString }
                        self.jerseyCells = zip(tempIds, game.jerseyNumbers).map {
                            JerseyCell(id: UUID(uuidString: $0.0) ?? UUID(), jerseyNumber: $0.1)
                        }
                        let gid = game.id ?? gameId
                        self.authManager.migrateBatterIdsIfMissing(ownerUserId: ownerUid, gameId: gid)
                    }

                    self.selectedBatterId = nil
                    self.ownerTemplateName = self.selectedTemplate?.name
                    self.showParticipantOverlay = !self.isOwnerForActiveGame

                } catch {
                    print("❌ hydrateChosenGameUI decode error:", error)
                }
            }
        }
    }

    private var effectiveGameOwnerUserId: String? {
        if let host = activeGameOwnerUserId, !host.isEmpty { return host }
        return authManager.user?.uid
    }

    private var isOwnerForActiveGame: Bool {
        guard let me = authManager.user?.uid,
              let owner = effectiveGameOwnerUserId else { return false }
        return me == owner
    }

    private var canInitiateCall: Bool {
        // Practice: always allowed. Game: owner only.
        return !isGame || isOwnerForActiveGame
    }

    private func handleSetCalledPitch(_ newCall: PitchCall?) {
        calledPitch = newCall
        lastCallInitiatedAt = newCall == nil ? nil : Date()

        guard isGame, isOwnerForActiveGame else { return }


        // If owner cleared the call, clear pending too.
        guard let newCall else {
            deferredPendingPitch = nil
            if let liveId = activeLiveId {
                LiveGameService.shared.updateLiveFields(liveId: liveId, fields: [
                    "pending": FieldValue.delete(),
                    "resultSelection": FieldValue.delete(),
                    "displayCode": FieldValue.delete()
                ])
            } else if let gid = selectedGameId, let owner = effectiveGameOwnerUserId {
                authManager.clearPendingPitch(ownerUserId: owner, gameId: gid)
                clearResultSelection()
            }
            return
        }


        let callId = UUID().uuidString
        activeCalledPitchId = callId
        isRecordingResult = false
        
        let prefix = newCall.isStrike ? "Strike" : "Ball"
        let fullLabel = "\(prefix) \(newCall.location)"

        let pending = Game.PendingPitch(
            isActive: true,
            id: callId,
            label: fullLabel,
            pitch: newCall.pitch,
            location: newCall.location,
            batterSide: batterSide == .left ? "left" : "right",
            createdAt: Date(),
            createdByUid: authManager.user?.uid ?? "",
            isStrike: newCall.isStrike
        )
        guard let liveId = activeLiveId else {
            deferredPendingPitch = pending
            ensureAutoLiveSessionIfNeeded()
            print("⚠️ No activeLiveId — deferring pending write until live session exists.")
            return
        }

        do {
            let pendingData = try Firestore.Encoder().encode(pending)
            LiveGameService.shared.updateLiveFields(liveId: liveId, fields: [
                "pending": pendingData,
                "displayCode": FieldValue.delete()
            ]) { err in
                if let err { print("❌ pending update error:", err.localizedDescription) }
            }
        } catch {
            print("❌ encode pending failed:", error)
        }


    }
    private func applyPendingFromLiveData(_ data: [String: Any]) {
        guard isGame else { return }
        guard !isOwnerForActiveGame else { return } // owner already has full call with codes

        guard let pending = data["pending"] as? [String: Any],
              (pending["isActive"] as? Bool) == true,
              let pitch = pending["pitch"] as? String,
              let loc = pending["location"] as? String
        else {
            // no pending: clear joiner UI
            pendingResultLabel = nil
            calledPitch = nil
            activeCalledPitchId = nil
            isRecordingResult = false
            return
        }

        let callId = pending["id"] as? String
        let label = (pending["label"] as? String) ?? loc

        let isNewCall: Bool = {
            if let callId {
                return callId != activeCalledPitchId
            }
            return activeCalledPitchId == nil
        }()

        if isNewCall {
            resetCallAndResultUIState()
        }

        if showConfirmSheet && !isNewCall {
            return
        }

        pendingResultLabel = label
        calledPitch = PitchCall(
            pitch: pitch,
            location: loc,
            isStrike: (pending["isStrike"] as? Bool) ?? true,
            codes: [] // joiner never sees codes
        )

        activeCalledPitchId = callId
        isRecordingResult = true
    }

    private func applyResultSelectionFromLiveData(_ data: [String: Any]) {
        guard isGame else { return }

        guard let sel = data["resultSelection"] as? [String: Any] else { return }
        let label = (sel["label"] as? String) ?? ""

        // If you already have a local "resultSelection" UI variable, set it here.
        // If not, this is still useful because your existing UI reads pendingResultLabel etc.
        if !label.isEmpty {
            // Optionally: keep a local var if you have one
            // self.lastResultSelectionLabel = label
        }
    }
    /// Owner-side: keep CalledPitchView in sync with the shared live doc.
    /// When the participant saves, they delete `pending` from /liveGames/{liveId},
    /// so the owner should dismiss their CalledPitchView automatically.
    private func syncOwnerCallStateFromLiveData(_ data: [String: Any]) {
        guard isGame, isOwnerForActiveGame else { return }

        let pending = data["pending"] as? [String: Any]
        let isActive = (pending?["isActive"] as? Bool) == true
        let pendingId = pending?["id"] as? String

        if let pendingId {
            lastObservedPendingCallId = pendingId
        }

        // If pending is gone (or inactive), the participant has saved/canceled — dismiss owner's call UI
        // BUT only if we previously saw this exact call id in Firestore.
        if !isActive {
            if let startedAt = lastCallInitiatedAt,
               Date().timeIntervalSince(startedAt) < 1.0 {
                return
            }

            if let activeId = activeCalledPitchId,
               let observedId = lastObservedPendingCallId,
               activeId == observedId {
                if calledPitch != nil || activeCalledPitchId != nil || isRecordingResult || pendingResultLabel != nil {
                    resetCallAndResultUIState()
                }
            }
            return
        }

        // If live doc is pointing at a different callId than we're showing, reset to avoid a stuck overlay.
        if let pendingId, let activeCalledPitchId, pendingId != activeCalledPitchId {
            resetCallAndResultUIState()
        }
    }

    func applyPendingFromGame(_ updated: Game) {
        // Only relevant in game mode
        guard isGame else { return }

        // Never overwrite the owner's local calledPitch (it contains real codes)
        guard !isOwnerForActiveGame else { return }

        // If there's no active pending pitch, clear joiner UI
        guard
            let pending = updated.pending,
            pending.isActive == true,
            let pitch = pending.pitch,
            let loc = pending.location
        else {
            pendingResultLabel = nil
            calledPitch = nil
            activeCalledPitchId = nil
            isRecordingResult = false
            lastTappedPosition = nil
            showConfirmSheet = false
            return
        }

        // ✅ If this is a NEW pending pitch, reset local result-selection state
        if activeCalledPitchId != pending.id {
            pendingResultLabel = nil
            showConfirmSheet = false
            lastTappedPosition = nil
        }

        // Mirror pending pitch locally for joiner UI
        let resolvedLabel = pending.label ?? loc

        // ✅ CRITICAL: do NOT overwrite participant's chosen actual location while they are confirming/saving
        if !showConfirmSheet && pendingResultLabel == nil {
            pendingResultLabel = resolvedLabel
            print("🔆 pendingResultLabel seeded from Firestore=", resolvedLabel)
        } else {
            // Keep whatever the participant selected
            // print("🔆 keeping local pendingResultLabel=", pendingResultLabel ?? "nil")
        }

        calledPitch = PitchCall(
            pitch: pitch,
            location: loc,
            isStrike: pending.isStrike ?? true,
            codes: [] // joiner never sees codes
        )

        activeCalledPitchId = pending.id
        isRecordingResult = true
    }


    private func writeResultSelection(label: String?) {
        guard isGame else { return }

        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "label": label ?? "",
            "createdAt": FieldValue.serverTimestamp(),
            "createdByUid": authManager.user?.uid ?? "",
            "callId": activeCalledPitchId ?? ""
        ]

        if let liveId = activeLiveId {
            LiveGameService.shared.updateLiveFields(liveId: liveId, fields: [
                "resultSelection": payload
            ])
            return
        }

        // Legacy fallback (keep only while transitioning)
        guard let gid = selectedGameId,
              let owner = effectiveGameOwnerUserId
        else { return }

        Firestore.firestore()
            .collection("users").document(owner)
            .collection("games").document(gid)
            .setData(["resultSelection": payload], merge: true)
    }


    private func clearResultSelection() {
        writeResultSelection(label: "")
    }

    private func ensureLivePresence(liveId: String) {
        LiveGameService.shared.heartbeatPresence(liveId: liveId)
    }

    private func seedLivePitchEventsOnce(liveId: String) {
        guard gamePitchEvents.isEmpty else { return }

        let ref = Firestore.firestore()
            .collection("liveGames").document(liveId)
            .collection("pitchEvents")
            .order(by: "timestamp", descending: false)

        ref.getDocuments { snap, err in
            if let err {
                print("❌ seed live pitchEvents failed:", err.localizedDescription)
                return
            }
            let events: [PitchEvent] = snap?.documents.compactMap { doc in
                PitchEvent.decodeFirestoreDocument(doc)
            } ?? []

            DispatchQueue.main.async {
                if self.gamePitchEvents.isEmpty {
                    self.gamePitchEvents = events
                }
            }
        }
    }

    private func applyPendingLiveTemplateIfPossible() {
        guard activeLiveId != nil else { return }
        guard let myUid = authManager.user?.uid else { return }
        // Only participants should be overridden by live doc values.
        guard let ownerUid = activeGameOwnerUserId, !ownerUid.isEmpty else { return }
        guard ownerUid != myUid else { return }
        guard !liveTemplateOverrideLocked else { return }

        if let tid = pendingLiveTemplateId, !tid.isEmpty,
           let template = templates.first(where: { $0.id.uuidString == tid }) {
            if selectedTemplate?.id != template.id {
                applyTemplate(template, source: .live)
            }
            return
        }

        if let tname = pendingLiveTemplateName, !tname.isEmpty,
           let template = templates.first(where: { $0.name == tname }) {
            if selectedTemplate?.id != template.id {
                applyTemplate(template, source: .live)
            }
        }
    }

    func startListeningToLivePitchEvents(liveId: String) {
        livePitchEventsListener?.remove()
        livePitchEventsListener = nil

        let ref = Firestore.firestore()
            .collection("liveGames").document(liveId)
            .collection("pitchEvents")
            .order(by: "timestamp", descending: false)

        print("👂 live pitchEvents listener start liveId=\(liveId)")

        livePitchEventsListener = ref.addSnapshotListener { snap, err in
            if let err = err {
                print("❌ Live pitchEvents listener error:", err.localizedDescription)
                return
            }
            guard let docs = snap?.documents else {
                print("⚠️ Live pitchEvents snapshot has no documents")
                return
            }

            print("🧾 Live pitchEvents snapshot count=\(docs.count) isOwner=\(self.isOwnerForActiveGame) activeLiveId=\(self.activeLiveId ?? "<nil>") selectedGameId=\(self.selectedGameId ?? "<nil>") ownerUid=\(self.effectiveGameOwnerUserId ?? self.activeGameOwnerUserId ?? "<nil>")")

            // Decode for UI (existing behavior)
            let events: [PitchEvent] = docs.compactMap { doc in
                PitchEvent.decodeFirestoreDocument(doc)
            }

            DispatchQueue.main.async {
                if self.isOwnerForActiveGame {
                    // Owner can seed from private history and backfill live collection for participants.
                    self.seedOwnerGamePitchEventsForLiveIfNeeded()
                    if events.isEmpty {
                    }
                }

                let combined = self.mergeLiveAndSeededEvents(liveEvents: events)
                if !combined.isEmpty {
                    self.gamePitchEvents = combined
                } else {
                    print("⚠️ Live merge produced 0 events (seeded=\(self.seededGamePitchEventsForLive.count), live=\(events.count))")
                }

                // ✅ OWNER ONLY: mirror live events into owner’s real game doc
                guard self.isOwnerForActiveGame,
                      let ownerUid = self.effectiveGameOwnerUserId, !ownerUid.isEmpty,
                      let gameId = self.selectedGameId, !gameId.isEmpty
                else { return }

                for doc in docs {
                    let liveEventId = doc.documentID
                    guard !self.mirroredLivePitchEventIds.contains(liveEventId) else { continue }
                    self.mirroredLivePitchEventIds.insert(liveEventId)

                    var data = doc.data()

                    // Ensure required fields exist for game storage / rules
                    data["gameId"] = gameId
                    if data["createdByUid"] == nil {
                        data["createdByUid"] = ownerUid
                    }

                    let dst = Firestore.firestore()
                        .collection("users").document(ownerUid)
                        .collection("games").document(gameId)
                        .collection("pitchEvents").document(liveEventId)

                    dst.setData(data, merge: false) { err in
                        if let err {
                            print("❌ mirror live pitchEvent failed:", err.localizedDescription)
                        } else {
                            print("✅ mirrored live pitchEvent → users/\(ownerUid)/games/\(gameId)/pitchEvents/\(liveEventId)")
                        }
                    }
                }
            }
        }
    }
    private func startListeningToActiveGame() {
        if activeLiveId != nil && !isOwnerForActiveGame { return }
        gameListener?.remove()
        gameListener = nil

        guard isGame,
              let gid = selectedGameId,
              let owner = effectiveGameOwnerUserId
        else { return }

        let ref = Firestore.firestore()
            .collection("users").document(owner)
            .collection("games").document(gid)

        gameListener = ref.addSnapshotListener { snap, err in
            if let err = err {
                print("❌ Game listener error:", err.localizedDescription)
                return
            }
            guard let snap, snap.exists else {
                print("⚠️ Game doc missing while listening:", ref.path)
                return
            }

            do {
                let updated = try snap.data(as: Game.self)
                DispatchQueue.main.async {
                    var merged = updated
                    let shouldApplyProgress = self.activeLiveId == nil
                        && self.shouldApplyProgressFromSnapshot(updated.progressUpdatedAt)

                    if self.activeLiveId == nil {
                        if shouldApplyProgress {
                            print("🧭[PROG] gameSnap APPLY gid=\(gid) snapStamp=\(String(describing: updated.progressUpdatedAt)) localStamp=\(String(describing: self.lastLocalProgressUpdate)) snap=\(updated.balls)/\(updated.strikes)/\(updated.inning)/\(updated.hits)/\(updated.walks)/\(updated.us)/\(updated.them)")
                            self.balls = updated.balls
                            self.strikes = updated.strikes
                            self.inning = updated.inning
                            self.hits = updated.hits
                            self.walks = updated.walks
                            self.us = updated.us
                            self.them = updated.them
                            if let stamp = updated.progressUpdatedAt {
                                self.lastLocalProgressUpdate = stamp
                            }
                        } else {
                            print("🧭[PROG] gameSnap SKIP gid=\(gid) snapStamp=\(String(describing: updated.progressUpdatedAt)) localStamp=\(String(describing: self.lastLocalProgressUpdate)) keep=\(self.balls)/\(self.strikes)/\(self.inning)/\(self.hits)/\(self.walks)/\(self.us)/\(self.them)")
                            merged.balls = self.balls
                            merged.strikes = self.strikes
                            merged.inning = self.inning
                            merged.hits = self.hits
                            merged.walks = self.walks
                            merged.us = self.us
                            merged.them = self.them
                            merged.progressUpdatedAt = self.lastLocalProgressUpdate
                        }
                    }

                    // Keep games[] in sync so currentGame works
                    if let idx = self.games.firstIndex(where: { $0.id == gid }) {
                        self.games[idx] = merged
                    } else {
                        self.games.append(merged)
                    }

                    // If not in live mode, you can optionally mirror into local UI state
                    // (ONLY needed if your UI depends on these @State vars outside live mode)
                    // Ensure owner still sees the lineup if local cells are empty
                    if self.jerseyCells.isEmpty {
                        if let ids = merged.batterIds, ids.count == merged.jerseyNumbers.count {
                            self.jerseyCells = zip(ids, merged.jerseyNumbers).map { (idStr, num) in
                                JerseyCell(id: UUID(uuidString: idStr) ?? UUID(), jerseyNumber: num)
                            }
                        } else {
                            self.jerseyCells = merged.jerseyNumbers.map { JerseyCell(jerseyNumber: $0) }
                        }
                    }
                }
            } catch {
                print("❌ decode Game failed:", error)
            }
        }
    }

    private func startListeningToGamePitchEvents() {
        // remove old listener
        gamePitchEventsListener?.remove()
        gamePitchEventsListener = nil

        // While a live room is active, the cards should be driven only by
        // /liveGames/{liveId}/pitchEvents to avoid stale owner-game snapshots
        // overwriting fresh live updates.
        guard activeLiveId == nil else { return }

        guard isGame,
              let gid = selectedGameId,
              let owner = effectiveGameOwnerUserId
        else { return }

        let ref = Firestore.firestore()
            .collection("users").document(owner)
            .collection("games").document(gid)
            .collection("pitchEvents")
            .order(by: "timestamp", descending: false)

        gamePitchEventsListener = ref.addSnapshotListener { snap, err in
            if let err = err {
                print("❌ Game pitchEvents listener error:", err.localizedDescription)
                return
            }
            guard let docs = snap?.documents else { return }

            let events: [PitchEvent] = docs.compactMap { doc in
                PitchEvent.decodeFirestoreDocument(doc)
            }

            DispatchQueue.main.async {
                self.gamePitchEvents = events
            }
        }
    }

    @State private var liveListener: ListenerRegistration? = nil
    @State private var activeLiveId: String? = nil
    @State private var livePitcherId: String? = nil
    @State private var didHydrateLineupFromLive: Bool = false
    @State private var didSeedOwnerGameEventsForLive: Bool = false
    @State private var didSeedLivePitchEventsFromOwnerGame: Bool = false
    @State private var seededGamePitchEventsForLive: [PitchEvent] = []
    @State private var participantsListener: ListenerRegistration? = nil

    private func seedOwnerGamePitchEventsForLiveIfNeeded() {
        guard activeLiveId != nil else { return }
        guard isOwnerForActiveGame else { return }
        guard !didSeedOwnerGameEventsForLive else { return }
        guard let owner = (effectiveGameOwnerUserId ?? activeGameOwnerUserId),
              let gid = selectedGameId
        else {
            print("⚠️ seedOwnerGamePitchEventsForLiveIfNeeded missing owner/gid")
            return
        }

        let ref = Firestore.firestore()
            .collection("users").document(owner)
            .collection("games").document(gid)
            .collection("pitchEvents")
            .order(by: "timestamp", descending: false)

        ref.getDocuments { snap, err in
            if let err {
                print("❌ seed owner game pitchEvents failed:", err.localizedDescription)
                return
            }

            let docs = snap?.documents ?? []
            let events: [PitchEvent] = docs.compactMap { doc in
                PitchEvent.decodeFirestoreDocument(doc)
            }

            DispatchQueue.main.async {
                guard self.activeLiveId != nil else { return }
                self.didSeedOwnerGameEventsForLive = true
                self.seededGamePitchEventsForLive = events

                print("✅ seeded owner game pitchEvents count=\(events.count)")

                let combined = self.mergeLiveAndSeededEvents(liveEvents: [])
                if !combined.isEmpty {
                    self.gamePitchEvents = combined
                }
            }
        }
    }

    private func seedLivePitchEventsFromOwnerGameIfNeeded() {
        guard activeLiveId != nil else { return }
        guard isOwnerForActiveGame else { return }
        guard !didSeedLivePitchEventsFromOwnerGame else { return }
        guard let owner = (effectiveGameOwnerUserId ?? activeGameOwnerUserId),
              let gid = selectedGameId,
              let liveId = activeLiveId
        else {
            print("⚠️ seedLivePitchEventsFromOwnerGameIfNeeded missing owner/gid/liveId")
            return
        }

        let source = Firestore.firestore()
            .collection("users").document(owner)
            .collection("games").document(gid)
            .collection("pitchEvents")
            .order(by: "timestamp", descending: false)

        source.getDocuments { snap, err in
            if let err {
                print("❌ seed live pitchEvents from owner game failed:", err.localizedDescription)
                return
            }

            let docs = snap?.documents ?? []
            guard !docs.isEmpty else {
                print("⚠️ seed live pitchEvents: owner game has 0 events")
                return
            }

            let liveRef = Firestore.firestore()
                .collection("liveGames").document(liveId)
                .collection("pitchEvents")

            let batch = Firestore.firestore().batch()
            for doc in docs {
                var data = doc.data()
                // Force ownership for live backfill to satisfy rules.
                if let original = data["createdByUid"] as? String, original != owner {
                    data["originalCreatedByUid"] = original
                }
                data["createdByUid"] = owner

                let dst = liveRef.document(doc.documentID)
                batch.setData(data, forDocument: dst, merge: false)
            }

            batch.commit { err in
                if let err {
                    print("❌ seed live pitchEvents batch failed:", err.localizedDescription)
                } else {
                    DispatchQueue.main.async {
                        self.didSeedLivePitchEventsFromOwnerGame = true
                    }
                    print("✅ seeded live pitchEvents from owner game history count=\(docs.count)")
                }
            }
        }
    }

    private func mergeLiveAndSeededEvents(liveEvents: [PitchEvent]) -> [PitchEvent] {
        var byId: [String: PitchEvent] = [:]
        var result: [PitchEvent] = []

        for event in seededGamePitchEventsForLive {
            if let id = event.id {
                byId[id] = event
            } else {
                result.append(event)
            }
        }

        for event in liveEvents {
            if let id = event.id {
                byId[id] = event
            } else {
                result.append(event)
            }
        }

        result.append(contentsOf: byId.values)
        return result.sorted { lhs, rhs in lhs.timestamp > rhs.timestamp }
    }

    private func startListeningToLiveGame(liveId: String) {
        mirroredLivePitchEventIds.removeAll()
        liveListener?.remove()
        liveListener = nil
        gamePitchEventsListener?.remove()
        gamePitchEventsListener = nil

        didSeedOwnerGameEventsForLive = false
        didSeedLivePitchEventsFromOwnerGame = false
        seededGamePitchEventsForLive.removeAll()
        gamePitchEvents = []
        activeLiveId = liveId
        startListeningToLivePitchEvents(liveId: liveId)
        startListeningToLiveParticipants(liveId: liveId)
        syncLivePitcherSelectionIfOwner()

        // Kick a backfill attempt early if we already know owner + game.
        if canBackfillLiveHistory {
            seedLivePitchEventsFromOwnerGameIfNeeded()
        }

        let ref = Firestore.firestore().collection("liveGames").document(liveId)
        liveListener = ref.addSnapshotListener { snap, err in
            if let err {
                print("❌ Live listener error:", err)
                DispatchQueue.main.async {
                    if self.activeLiveId == liveId {
                        self.uiConnected = false
                        self.endLiveSessionLocally(keepCurrentGame: false)
                    }
                }
                return
            }
            guard let snap, snap.exists, let data = snap.data() else {
                print("⚠️ Live game doc missing:", ref.path)
                DispatchQueue.main.async {
                    if self.activeLiveId == liveId {
                        self.uiConnected = false
                        self.endLiveSessionLocally(keepCurrentGame: false)
                    }
                }
                return
            }

            DispatchQueue.main.async {
                let liveStamp = (data["progressUpdatedAt"] as? Timestamp)?.dateValue()
                let shouldApplyLiveProgress = self.shouldApplyProgressFromSnapshot(liveStamp)
                    || self.lastLocalProgressUpdate == nil
                if shouldApplyLiveProgress {
                    self.balls   = data["balls"]   as? Int ?? self.balls
                    self.strikes = data["strikes"] as? Int ?? self.strikes
                    self.inning  = data["inning"]  as? Int ?? self.inning
                    self.hits    = data["hits"]    as? Int ?? self.hits
                    self.walks   = data["walks"]   as? Int ?? self.walks
                    self.us      = data["us"]      as? Int ?? self.us
                    self.them    = data["them"]    as? Int ?? self.them
                    if let liveStamp {
                        self.lastLocalProgressUpdate = liveStamp
                    }
                } else {
                    print("🧭[PROG] liveSnap SKIP stamp=\(String(describing: liveStamp)) localStamp=\(String(describing: self.lastLocalProgressUpdate))")
                }
                // ✅ FIX: restore opponent label for the Game button in LIVE mode
                if let opp = data["opponent"] as? String, !opp.isEmpty {
                    self.opponentName = opp
                    UserDefaults.standard.set(opp, forKey: "activeOpponentName")
                }

                if let sideRaw = data["batterSide"] as? String,
                   let parsed = BatterSide(rawValue: sideRaw) {
                    self.batterSide = parsed
                }

                if let pid = data["pitcherId"] as? String, !pid.isEmpty {
                    self.livePitcherId = pid
                } else {
                    self.livePitcherId = nil
                }

                if let connection = data["connection"] as? [String: Any],
                   let connected = connection["connected"] as? Bool {
                    self.uiConnected = connected
                } else {
                    self.uiConnected = false
                }

                if !self.uiConnected, !self.isOwnerForActiveGame, self.activeLiveId == liveId {
                    self.endLiveSessionLocally(keepCurrentGame: false)
                    return
                }

                if self.uiConnected && self.isOwnerForActiveGame {
                    if self.didAutoDismissCodeSheetForLiveId != liveId {
                        self.didAutoDismissCodeSheetForLiveId = liveId
                        if self.activeLiveId == liveId {
                            self.startListeningToLivePitchEvents(liveId: liveId)
                        }
                        self.showCodeShareSheet = false
                        self.showCodeShareModePicker = false
                    }
                }

                if !self.uiConnected, self.didAutoDismissCodeSheetForLiveId == liveId {
                    self.didAutoDismissCodeSheetForLiveId = nil
                }
                // ✅ LIVE TEMPLATE FLOW: apply owner's template on participant (and keep owner consistent too)
                let liveTemplateId = data["templateId"] as? String
                let liveTemplateName = data["templateName"] as? String
                self.pendingLiveTemplateId = liveTemplateId
                self.pendingLiveTemplateName = liveTemplateName
                self.applyPendingLiveTemplateIfPossible()
                // ✅ selected batter comes over Firestore as STRING uuid
                if let idStr = data["selectedBatterId"] as? String, let uuid = UUID(uuidString: idStr) {
                    self.selectedBatterId = uuid
                } else if data.keys.contains("selectedBatterId") == false {
                    // Field missing: keep existing selection (prevents flicker / needing 2 taps)
                    // (Do nothing)
                } else {
                    // Field explicitly present but not valid → clear
                    self.selectedBatterId = nil
                }

                if let jersey = data["selectedBatterJersey"] as? String {
                    self.selectedBatterJersey = jersey
                } else if data.keys.contains("selectedBatterJersey") == false {
                    // keep existing to avoid UI flicker
                } else {
                    self.selectedBatterJersey = nil
                }


                // ✅ keep owner identity in sync (needed for isOwnerForActiveGame)
                if let ownerUid = data["ownerUid"] as? String, !ownerUid.isEmpty {
                    self.activeGameOwnerUserId = ownerUid
                }
                // ✅ LIVE LINEUP: Prefer jerseyNumbers/batterIds directly from live doc
                if let jerseys = data["jerseyNumbers"] as? [String], !jerseys.isEmpty {
                    let ids = (data["batterIds"] as? [String]) ?? []

                    // Build cells every snapshot so owner instantly reflects participant changes
                    if ids.count == jerseys.count, !ids.isEmpty {
                        self.jerseyCells = zip(ids, jerseys).map { (idStr, num) in
                            JerseyCell(id: UUID(uuidString: idStr) ?? UUID(), jerseyNumber: num)
                        }
                    } else {
                        // Safe fallback if ids missing/mismatched
                        self.jerseyCells = jerseys.map { JerseyCell(id: UUID(), jerseyNumber: $0) }
                    }

                    self.didHydrateLineupFromLive = true
                }

                // ✅ Keep selectedGameId in sync for other downstream UI, and provide fallback hydration
                if let ownerGameId = data["ownerGameId"] as? String, !ownerGameId.isEmpty {

                    // Keep selectedGameId in sync (useful for other game-based actions)
                    if self.selectedGameId != ownerGameId {
                        self.selectedGameId = ownerGameId

                        // Persist so relaunch restores correctly
                        let defaults = UserDefaults.standard
                        defaults.set(ownerGameId, forKey: DefaultsKeys.activeGameId)
                        if let ownerUid = data["ownerUid"] as? String, !ownerUid.isEmpty {
                            defaults.set(ownerUid, forKey: DefaultsKeys.activeGameOwnerUserId)
                        }
                        defaults.set(false, forKey: DefaultsKeys.activeIsPractice)
                        defaults.set("tracker", forKey: DefaultsKeys.lastView)
                    }

                    // Fallback: ONLY the OWNER may hydrate lineup from the owner's private game doc.
                    // Participants cannot read /users/{owner}/games/{gid}, so this would leave them empty.
                    if self.isOwnerForActiveGame {
                        if (data["jerseyNumbers"] as? [String])?.isEmpty ?? true {
                            if !self.didHydrateLineupFromLive || self.jerseyCells.isEmpty {
                                let ownerUid = (data["ownerUid"] as? String) ?? (self.effectiveGameOwnerUserId ?? "")
                                if !ownerUid.isEmpty {
                                    self.didHydrateLineupFromLive = true
                                    self.hydrateChosenGameUI(ownerUid: ownerUid, gameId: ownerGameId)
                                    self.startListeningToActiveGame()
                                }
                            }
                        }

                        if self.gamePitchEvents.isEmpty {
                            self.seedOwnerGamePitchEventsForLiveIfNeeded()
                        }

                        if self.canBackfillLiveHistory {
                            self.seedLivePitchEventsFromOwnerGameIfNeeded()
                        }

                    }
                }


                // ✅ Apply pending/result ONLY while LIVE is active
                let liveStatus = (data["status"] as? String) ?? "active"
                if liveStatus != "active" {
                    print("🔌 Live session ended remotely → disconnecting")

                    self.uiConnected = false
                    self.endLiveSessionLocally(keepCurrentGame: self.isOwnerForActiveGame)
                    return
                }
                let notExpired: Bool = {
                    if let exp = data["expiresAt"] as? Timestamp {
                        return exp.dateValue() > Date()
                    }
                    return true
                }()

                let liveIsActive = (activeLiveId != nil) && (liveStatus == "active") && notExpired

                if liveIsActive {
                    if self.isOwnerForActiveGame {
                        self.syncOwnerCallStateFromLiveData(data)
                    } else {
                        self.applyPendingFromLiveData(data)
                    }
                    self.applyResultSelectionFromLiveData(data)
                } else {
                    // clear stuck UI if ended/expired
                    self.pendingResultLabel = nil
                    self.calledPitch = nil
                    self.activeCalledPitchId = nil
                    self.isRecordingResult = false
                }

            }
        }
    }
    private var canBackfillLiveHistory: Bool {
        guard activeLiveId != nil else { return false }
        guard let owner = (effectiveGameOwnerUserId ?? activeGameOwnerUserId), !owner.isEmpty else { return false }
        guard let gid = selectedGameId, !gid.isEmpty else { return false }
        guard let myUid = authManager.user?.uid, !myUid.isEmpty else { return false }
        return owner == myUid
    }

    private func startListeningToLiveParticipants(liveId: String) {
        participantsListener?.remove()
        participantsListener = nil

        let ref = Firestore.firestore()
            .collection("liveGames").document(liveId)
            .collection("participants")

        participantsListener = ref.addSnapshotListener { snap, err in
            if let err {
                print("❌ Live participants listener error:", err.localizedDescription)
                DispatchQueue.main.async { self.uiConnected = false }
                return
            }

            let docs = snap?.documents ?? []
            let myUid = self.authManager.user?.uid ?? ""
            let now = Date()
            let onlineWindow: TimeInterval = 40 // > 25s heartbeat

            // Connected = we see at least one *other* device recently
            let otherRecent = docs.contains { d in
                let uid = d.documentID
                guard uid != myUid else { return false }
                guard let ts = d.data()["lastSeenAt"] as? Timestamp else { return true }
                return now.timeIntervalSince(ts.dateValue()) <= onlineWindow
            }

            DispatchQueue.main.async {
                let connectedNow = (self.activeLiveId != nil) && self.isGame && otherRecent
                _ = connectedNow
            }
        }
    }
    private func resetCallAndResultUIState() {
        lastTappedPosition = nil
        calledPitch = nil
        activeCalledPitchId = nil
        pendingResultLabel = nil
        showConfirmSheet = false
        showResultConfirmation = false
        isRecordingResult = false
        selectedPitch = ""
        selectedLocation = ""
        resultVisualState = nil
        actualLocationRecorded = nil
        lastCallInitiatedAt = nil
        lastObservedPendingCallId = nil
        clearDisplayCodeIfNeeded()
    }

    private func clearDisplayCodeIfNeeded() {
        guard isGame, isOwnerForActiveGame, let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("displayState")
            .document("current")
            .delete()
    }

    private func resetLiveTemplateOverrideLock() {
        liveTemplateOverrideLocked = false
    }

    private func endLiveSessionLocally(keepCurrentGame: Bool) {
        guard let liveId = activeLiveId else { return }

        flushBufferedSharedPitcherEvents(reason: "endLiveSession")

        if isOwnerForActiveGame {
            flushProgressToGameIfOwner()
        }

        LiveGameService.shared.updateLiveFields(
            liveId: liveId,
            fields: [
                "connection": [
                    "participantUid": NSNull(),
                    "connected": false,
                    "disconnectedAt": FieldValue.serverTimestamp()
                ]
            ]
        )

        liveListener?.remove()
        liveListener = nil
        livePitchEventsListener?.remove()
        livePitchEventsListener = nil
        gamePitchEventsListener?.remove()
        gamePitchEventsListener = nil

        stopHeartbeat()
        participantsListener?.remove()
        participantsListener = nil
        uiConnected = false
        didHydrateLineupFromLive = false
        didAutoDismissCodeSheetForLiveId = nil
        mirroredLivePitchEventIds.removeAll()
        didSeedOwnerGameEventsForLive = false
        didSeedLivePitchEventsFromOwnerGame = false
        seededGamePitchEventsForLive.removeAll()
        gamePitchEvents.removeAll()
        resetCallAndResultUIState()
        resetLiveTemplateOverrideLock()

        let uid = authManager.user?.uid ?? ""
        if !uid.isEmpty {
            Firestore.firestore()
                .collection("liveGames").document(liveId)
                .collection("participants").document(uid)
                .delete()
        }

        activeLiveId = nil
        updateActiveSessionLiveId(nil)
        livePitcherId = nil
        UserDefaults.standard.removeObject(forKey: "activeLiveId")

        if keepCurrentGame, isGame {
            startListeningToActiveGame()
            startListeningToGamePitchEvents()
        } else {
            isGame = false
            sessionManager.switchMode(to: .practice)
        }

        if !isOwnerForActiveGame {
            dismissAllTopLevelSheets()
            showSettings = true
        }
    }

    private func flushProgressToGameIfOwner() {
        guard let gid = selectedGameId,
              let owner = effectiveGameOwnerUserId
        else { return }

        authManager.updateGameBalls(ownerUserId: owner, gameId: gid, balls: balls)
        authManager.updateGameStrikes(ownerUserId: owner, gameId: gid, strikes: strikes)
        authManager.updateGameInning(ownerUserId: owner, gameId: gid, inning: inning)
        authManager.updateGameHits(ownerUserId: owner, gameId: gid, hits: hits)
        authManager.updateGameWalks(ownerUserId: owner, gameId: gid, walks: walks)
        authManager.updateGameUs(ownerUserId: owner, gameId: gid, us: us)
        authManager.updateGameThem(ownerUserId: owner, gameId: gid, them: them)
        markLocalProgressChange()

        if let idx = games.firstIndex(where: { $0.id == gid }) {
            games[idx].balls = balls
            games[idx].strikes = strikes
            games[idx].inning = inning
            games[idx].hits = hits
            games[idx].walks = walks
            games[idx].us = us
            games[idx].them = them
            games[idx].progressUpdatedAt = lastLocalProgressUpdate
        }
    }

    private func shouldApplyProgressFromSnapshot(_ snapshotStamp: Date?) -> Bool {
        guard let localStamp = lastLocalProgressUpdate else { return true }
        guard let snapshotStamp else { return false }
        return snapshotStamp >= localStamp
    }

    private func loadLocalProgressSnapshot(for gameId: String) -> LocalProgressSnapshot? {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "\(DefaultsKeys.lastProgressByGameId).\(gameId)"),
           let snapshot = try? JSONDecoder().decode(LocalProgressSnapshot.self, from: data) {
            return snapshot
        }
        return nil
    }

    private func persistLocalProgressSnapshot() {
        guard let gid = selectedGameId else { return }
        let snapshot = LocalProgressSnapshot(
            balls: balls,
            strikes: strikes,
            inning: inning,
            hits: hits,
            walks: walks,
            us: us,
            them: them,
            updatedAt: Date().timeIntervalSince1970
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: "\(DefaultsKeys.lastProgressByGameId).\(gid)")
        }
    }

    private func mergeLoadedGamesPreservingProgress(_ loaded: [Game]) -> [Game] {
        guard let gid = selectedGameId else { return loaded }

        var merged = loaded
        if let idx = merged.firstIndex(where: { $0.id == gid }) {
            print("🧭[PROG] mergeLoadedGames gid=\(gid) localStamp=\(String(describing: lastLocalProgressUpdate)) snapshotStamp=\(String(describing: merged[idx].progressUpdatedAt)) local=\(balls)/\(strikes)/\(inning)/\(hits)/\(walks)/\(us)/\(them) snap=\(merged[idx].balls)/\(merged[idx].strikes)/\(merged[idx].inning)/\(merged[idx].hits)/\(merged[idx].walks)/\(merged[idx].us)/\(merged[idx].them)")
            if lastLocalProgressUpdate == nil, let local = loadLocalProgressSnapshot(for: gid) {
                balls = local.balls
                strikes = local.strikes
                inning = local.inning
                hits = local.hits
                walks = local.walks
                us = local.us
                them = local.them
                lastLocalProgressUpdate = Date(timeIntervalSince1970: local.updatedAt)
            }

            if lastLocalProgressUpdate == nil {
                if let stamp = merged[idx].progressUpdatedAt {
                    lastLocalProgressUpdate = stamp
                } else if merged[idx].balls != 0
                            || merged[idx].strikes != 0
                            || merged[idx].inning != 1
                            || merged[idx].hits != 0
                            || merged[idx].walks != 0
                            || merged[idx].us != 0
                            || merged[idx].them != 0 {
                    lastLocalProgressUpdate = Date()
                }
            }

            if let localStamp = lastLocalProgressUpdate {
                let snapshotStamp = merged[idx].progressUpdatedAt
                if snapshotStamp == nil || (snapshotStamp ?? Date.distantPast) < localStamp {
                    merged[idx].balls = balls
                    merged[idx].strikes = strikes
                    merged[idx].inning = inning
                    merged[idx].hits = hits
                    merged[idx].walks = walks
                    merged[idx].us = us
                    merged[idx].them = them
                    merged[idx].progressUpdatedAt = localStamp
                }
            }
        }
        return merged
    }

    private func markLocalProgressChange() {
        lastLocalProgressUpdate = Date()
        persistLocalProgressSnapshot()
        print("🧭[PROG] markLocalProgressChange gid=\(selectedGameId ?? "<nil>") stamp=\(String(describing: lastLocalProgressUpdate)) local=\(balls)/\(strikes)/\(inning)/\(hits)/\(walks)/\(us)/\(them)")
        persistProgressSnapshotToOwnerGameAndLive()
    }

    private func persistProgressSnapshotToOwnerGameAndLive() {
        if let liveId = activeLiveId, !liveId.isEmpty {
            LiveGameService.shared.updateLiveFields(liveId: liveId, fields: [
                "balls": balls,
                "strikes": strikes,
                "inning": inning,
                "hits": hits,
                "walks": walks,
                "us": us,
                "them": them,
                "progressUpdatedAt": FieldValue.serverTimestamp()
            ])
        }

        guard isOwnerForActiveGame else { return }
        guard let gid = selectedGameId,
              let owner = effectiveGameOwnerUserId
        else { return }

        authManager.updateGameCounts(
            ownerUserId: owner,
            gameId: gid,
            inning: inning,
            hits: hits,
            walks: walks,
            balls: balls,
            strikes: strikes,
            us: us,
            them: them
        )

        if let idx = games.firstIndex(where: { $0.id == gid }) {
            games[idx].balls = balls
            games[idx].strikes = strikes
            games[idx].inning = inning
            games[idx].hits = hits
            games[idx].walks = walks
            games[idx].us = us
            games[idx].them = them
            games[idx].progressUpdatedAt = lastLocalProgressUpdate
        }
    }

    private func disconnectFromGame(notifyHost: Bool = true) {
        flushBufferedSharedPitcherEvents(reason: "disconnect")
        if activeLiveId != nil {
            endLiveSessionLocally(keepCurrentGame: false)
            return
        }

        // ✅ Capture BEFORE clearing state
        let uid = authManager.user?.uid ?? ""
        let ownerUid = effectiveGameOwnerUserId ?? activeGameOwnerUserId ?? ""
        let gid = selectedGameId ?? ""

        // ✅ Only notify host when this device voluntarily disconnects
        if notifyHost, !uid.isEmpty, !ownerUid.isEmpty, !gid.isEmpty {
            Firestore.firestore()
                .collection("users").document(ownerUid)
                .collection("games").document(gid)
                .updateData([
                    "participants.\(uid)": FieldValue.delete()
                ]) { err in
                    if let err = err {
                        print("❌ Failed to remove participant:", err.localizedDescription)
                    } else {
                        print("✅ Participant removed from game participants")
                    }
                }
        }

        // Stop listening and clear active game selection for this device
        gameListener?.remove()
        gameListener = nil
        livePitchEventsListener?.remove()
        livePitchEventsListener = nil
        gamePitchEventsListener?.remove()
        gamePitchEventsListener = nil
        selectedGameId = nil
        opponentName = nil
        selectedBatterId = nil
        jerseyCells = []
        showParticipantOverlay = false
        lastObservedResultSelectionId = nil
        mirroredLivePitchEventIds.removeAll()
        didSeedOwnerGameEventsForLive = false
        didSeedLivePitchEventsFromOwnerGame = false
        seededGamePitchEventsForLive.removeAll()
        gamePitchEvents.removeAll()
        resetLiveTemplateOverrideLock()
        
        // Persist leaving game
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: DefaultsKeys.activeGameId)
        defaults.removeObject(forKey: DefaultsKeys.activeGameOwnerUserId)
        defaults.set("tracker", forKey: DefaultsKeys.lastView)

        // Switch to practice mode locally
        isGame = false
        sessionManager.switchMode(to: .practice)
    }


    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func startLivePresenceHeartbeat(liveId: String) {
        stopHeartbeat()

        guard let myUid = authManager.user?.uid, !myUid.isEmpty else { return }

        // ✅ Create/update presence doc every 25s
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { _ in
            let db = Firestore.firestore()
            let ref = db.collection("liveGames").document(liveId)
                .collection("participants").document(myUid)

            ref.setData([
                "uid": myUid,
                "lastSeenAt": FieldValue.serverTimestamp(),
                "joinedAt": FieldValue.serverTimestamp() // ok to re-write; server keeps latest
            ], merge: true)
        }

        // fire once immediately so presence shows up right away
        heartbeatTimer?.fire()
    }

    private var hiddenTemplateIdSet: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: DefaultsKeys.hiddenTemplateIds) ?? [])
    }

    private var hiddenPitcherIdSet: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: DefaultsKeys.hiddenPitcherIds) ?? [])
    }

    private var visibleTemplates: [PitchTemplate] {
        templates.filter { !hiddenTemplateIdSet.contains($0.id.uuidString) }
    }

    private var visiblePitchers: [Pitcher] {
        pitchers.filter { !hiddenPitcherIdSet.contains($0.id ?? "") }
    }

    // MARK: - Template Version Indicator
    private var currentTemplateVersionLabel: String {
        // Encrypted mode has been retired; keep label empty.
        return String()
    }

    private var filteredEvents: [PitchEvent] {
        if isGame {
            return gamePitchEvents.sorted { $0.timestamp > $1.timestamp }
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

        if let gameId = selectedGameId, !gameId.isEmpty {
            var map = defaults.dictionary(forKey: DefaultsKeys.lastTemplateByGameId) as? [String: String] ?? [:]
            if let id = template?.id.uuidString {
                map[gameId] = id
            } else {
                map.removeValue(forKey: gameId)
            }
            defaults.set(map, forKey: DefaultsKeys.lastTemplateByGameId)
        }
    }

    private func persistSelectedPitcherId(_ id: String?) {
        let defaults = UserDefaults.standard
        if let id {
            defaults.set(id, forKey: DefaultsKeys.lastPitcherId)
        } else {
            defaults.removeObject(forKey: DefaultsKeys.lastPitcherId)
        }

        if let gameId = selectedGameId, !gameId.isEmpty {
            var map = defaults.dictionary(forKey: DefaultsKeys.lastPitcherByGameId) as? [String: String] ?? [:]
            if let id {
                map[gameId] = id
            } else {
                map.removeValue(forKey: gameId)
            }
            defaults.set(map, forKey: DefaultsKeys.lastPitcherByGameId)
        }
    }

    private func applyStoredSelections(for gameId: String) {
        let defaults = UserDefaults.standard
        if let templateMap = defaults.dictionary(forKey: DefaultsKeys.lastTemplateByGameId) as? [String: String],
           let templateId = templateMap[gameId] {
            if !hiddenTemplateIdSet.contains(templateId),
               let template = templates.first(where: { $0.id.uuidString == templateId }) {
                applyTemplate(template)
            }
        }

        if let pitcherMap = defaults.dictionary(forKey: DefaultsKeys.lastPitcherByGameId) as? [String: String],
           let pitcherId = pitcherMap[gameId],
           let pitcher = pitchers.first(where: { $0.id == pitcherId }) {
            applySelectedPitcher(pitcher)
        }
        if let selected = selectedTemplate,
           hiddenTemplateIdSet.contains(selected.id.uuidString) {
            selectedTemplate = visibleTemplates.first ?? templates.first
        }
    }

    private func persistBatterSide(_ side: BatterSide) {
        UserDefaults.standard.set(side == .left ? "left" : "right", forKey: DefaultsKeys.lastBatterSide)
    }
    private func pushBatterSideToActiveGame(_ side: BatterSide) {
        guard isGame else { return }

        let sideString = (side == .left) ? "left" : "right"

        if let liveId = activeLiveId, !liveId.isEmpty {
            LiveGameService.shared.updateLiveFields(
                liveId: liveId,
                fields: [
                    "batterSide": sideString,
                    "batterSideUpdatedAt": FieldValue.serverTimestamp(),
                    "batterSideUpdatedBy": authManager.user?.uid ?? ""
                ]
            )
            return
        }

        guard let gid = selectedGameId,
              let owner = effectiveGameOwnerUserId
        else { return }

        Firestore.firestore()
            .collection("users").document(owner)
            .collection("games").document(gid)
            .updateData([
                "batterSide": sideString,
                "batterSideUpdatedAt": FieldValue.serverTimestamp(),
                "batterSideUpdatedBy": authManager.user?.uid ?? ""
            ]) { err in
                if let err = err {
                    print("❌ update batterSide:", err.localizedDescription)
                } else {
                    print("✅ batterSide updated:", sideString)
                }
            }
    }


    private func persistMode(_ mode: PitchMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKeys.lastMode)
    }

    private func restorePersistedState(loadedTemplates: [PitchTemplate]) {
        let defaults = UserDefaults.standard

        isRestoringState = true

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

        // Restore mode WITHOUT firing your sheet-presenting onChange logic
        if let modeString = defaults.string(forKey: DefaultsKeys.lastMode),
           let restoredMode = PitchMode(rawValue: modeString) {

            // This prevents the segmented picker onChange from presenting a sheet while restoring.
            suppressNextGameSheet = true

            sessionManager.switchMode(to: restoredMode)
            isGame = (restoredMode == .game)
        }

        // Release the gate on the next runloop tick
        DispatchQueue.main.async {
            self.isRestoringState = false
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

    private func refreshGamesList() {
        authManager.loadGames { loaded in
            let merged = self.mergeLoadedGamesPreservingProgress(loaded)
            self.games = merged

            if let selectedId = self.selectedGameId,
               !merged.contains(where: { $0.id == selectedId }) {
                self.selectedGameId = nil
                self.opponentName = nil
                self.activeGameOwnerUserId = nil
                self.sessionManager.switchMode(to: .practice)
                self.isGame = false

                let defaults = UserDefaults.standard
                defaults.removeObject(forKey: DefaultsKeys.activeGameId)
                defaults.removeObject(forKey: DefaultsKeys.activeGameOwnerUserId)
                defaults.set(true, forKey: DefaultsKeys.activeIsPractice)
            }
        }
    }

    private func loadPracticePitchEventsIfNeeded(force: Bool = false) {
        guard sessionManager.currentMode == .practice else { return }
        guard force || pitchEvents.isEmpty else { return }
        authManager.loadPitchEvents { events in
            DispatchQueue.main.async {
                self.pitchEvents = events
            }
        }
    }

    private enum TemplateSelectionSource {
        case user
        case live
    }

    // MARK: - Template Apply Helper
    private func applyTemplate(_ template: PitchTemplate, source: TemplateSelectionSource = .user) {
        selectedTemplate = template
        lastAppliedTemplateId = template.id
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

        if source == .user {
            liveTemplateOverrideLocked = true
            if isGame {
                syncLiveTemplateSelectionIfOwner()
            }
        }
    }

    private func applySelectedPitcher(_ pitcher: Pitcher, allowTemplateOverride: Bool = true) {
        if isGame && !pitcher.isActiveOwner(currentUid: authManager.user?.uid) {
            return
        }
        selectedPitcherId = pitcher.id
        persistSelectedPitcherId(pitcher.id)

        if isGame {
            syncLivePitcherSelectionIfOwner()
        }

        guard allowTemplateOverride else { return }
        guard !(isGame && !isOwnerForActiveGame) else { return }
        if let tid = pitcher.templateId,
           let template = templates.first(where: { $0.id.uuidString == tid }),
           selectedTemplate?.id != template.id {
            applyTemplate(template)
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
    // MARK: - Current Game Helper
    private var currentGame: Game? {
        guard let gid = selectedGameId else { return nil }
        return games.first(where: { $0.id == gid })
    }

    // MARK: - Game Field Bindings
    private func buildShareCode() -> String {
        // Return a random 6-digit numeric code (leading zeros allowed)
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    private func consumeShareCode(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if !subscriptionManager.isPro {
            showProPaywall = true
            return
        }

        // Accept only exactly 6 digits
        let isSixDigits = trimmed.count == 6 && trimmed.allSatisfy({ $0.isNumber })
        guard isSixDigits else {
            codeShareErrorMessage = "Code must be exactly 6 digits."
            showCodeShareErrorAlert = true
            return
        }

        isJoiningSession = true
        codeShareErrorMessage = ""

        LiveGameService.shared.joinLiveGame(code: trimmed) { result in
            DispatchQueue.main.async {
                self.isJoiningSession = false

                switch result {
                case .success(let liveId):
                    NotificationCenter.default.post(
                        name: .gameOrSessionChosen,
                        object: nil,
                        userInfo: [
                            "type": "liveGame",
                            "liveId": liveId
                        ]
                    )


                    self.showCodeShareSheet = false

                case .failure(let err):
                    self.codeShareErrorMessage = err.localizedDescription
                    self.showCodeShareErrorAlert = true
                }
            }
        }
    }

    private func inviteToken(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
           !token.isEmpty {
            return token
        }

        // Allow raw token input (no URL scheme)
        if trimmed.contains("://") { return nil }
        return trimmed
    }

    private func openCameraForJoin() {
        if showInviteJoinSheet {
            showInviteJoinSheet = false
        }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showCameraUnavailableAlert = true
            }
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            presentCameraFromJoin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        presentCameraFromJoin()
                    } else {
                        showCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showCameraPermissionAlert = true
            }
        @unknown default:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showCameraPermissionAlert = true
            }
        }
    }

    private func presentCameraFromJoin() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showQRScanner = true
        }
    }

    private func joinLiveGameFromInvite() {
        inviteJoinError = nil

        if !subscriptionManager.isPro {
            showProPaywall = true
            return
        }

        guard let token = inviteToken(from: inviteJoinText) else {
            inviteJoinError = "Paste a valid invite link."
            return
        }

        isJoiningSession = true
        LiveGameService.shared.joinLiveGameByInviteToken(token: token) { result in
            DispatchQueue.main.async {
                self.isJoiningSession = false

                switch result {
                case .success(let liveId):
                    NotificationCenter.default.post(
                        name: .gameOrSessionChosen,
                        object: nil,
                        userInfo: [
                            "type": "liveGame",
                            "liveId": liveId
                        ]
                    )
                    self.inviteJoinText = ""
                    self.showInviteJoinSheet = false

                case .failure(let err):
                    self.inviteJoinError = err.localizedDescription
                }
            }
        }
    }

    private func chooseGame(gameId: String, ownerUid: String) {
        if activeLiveId != nil {
            endLiveSessionLocally(keepCurrentGame: false)
        }
        // ✅ Runtime state
        activeGameOwnerUserId = ownerUid
        selectedGameId = gameId
        print("🧭[PROG] chooseGame gid=\(gameId) owner=\(ownerUid)")

        isGame = true
        sessionManager.switchMode(to: .game)
        suppressNextGameSheet = true

        // ✅ Persist "active game" so relaunch restores correctly
        let defaults = UserDefaults.standard
        defaults.set(gameId, forKey: DefaultsKeys.activeGameId)
        defaults.set(ownerUid, forKey: DefaultsKeys.activeGameOwnerUserId)
        defaults.set(false, forKey: DefaultsKeys.activeIsPractice)
        defaults.removeObject(forKey: DefaultsKeys.activePracticeId)
        defaults.set("tracker", forKey: DefaultsKeys.lastView)

        if let local = loadLocalProgressSnapshot(for: gameId) {
            balls = local.balls
            strikes = local.strikes
            inning = local.inning
            hits = local.hits
            walks = local.walks
            us = local.us
            them = local.them
            lastLocalProgressUpdate = Date(timeIntervalSince1970: local.updatedAt)
            print("🧭[PROG] chooseGame loadLocalSnapshot gid=\(gameId) stamp=\(lastLocalProgressUpdate!) values=\(balls)/\(strikes)/\(inning)/\(hits)/\(walks)/\(us)/\(them)")
        } else if let cached = games.first(where: { $0.id == gameId }) {
            balls = cached.balls
            strikes = cached.strikes
            inning = cached.inning
            hits = cached.hits
            walks = cached.walks
            us = cached.us
            them = cached.them
            if let stamp = cached.progressUpdatedAt {
                lastLocalProgressUpdate = stamp
            } else if cached.balls != 0
                        || cached.strikes != 0
                        || cached.inning != 1
                        || cached.hits != 0
                        || cached.walks != 0
                        || cached.us != 0
                        || cached.them != 0 {
                lastLocalProgressUpdate = Date()
            }
            print("🧭[PROG] chooseGame loadCached gid=\(gameId) stamp=\(String(describing: lastLocalProgressUpdate)) values=\(balls)/\(strikes)/\(inning)/\(hits)/\(walks)/\(us)/\(them)")
        }

        hydrateChosenGameUI(ownerUid: ownerUid, gameId: gameId)
        startListeningToActiveGame()
        startListeningToGamePitchEvents()
        applyStoredSelections(for: gameId)
        ensureAutoLiveSessionIfNeeded()
    }

    private func choosePractice(practiceId: String, practiceName: String?) {
        if activeLiveId != nil {
            endLiveSessionLocally(keepCurrentGame: false)
        }
        resetCallAndResultUIState()

        selectedGameId = nil
        opponentName = nil
        activeGameOwnerUserId = nil

        isGame = false
        sessionManager.switchMode(to: .practice)

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: DefaultsKeys.activeIsPractice)
        defaults.removeObject(forKey: DefaultsKeys.activeGameId)
        defaults.removeObject(forKey: DefaultsKeys.activeGameOwnerUserId)
        defaults.set("tracker", forKey: DefaultsKeys.lastView)

        if practiceId == "__GENERAL__" {
            selectedPracticeId = nil
            self.practiceName = nil
            persistActivePracticeId(nil)
            return
        }

        selectedPracticeId = practiceId
        self.practiceName = practiceName
        persistActivePracticeId(practiceId)
    }

    fileprivate enum PendingSessionKind {
        case game
        case practice
    }

    fileprivate struct PendingSessionConfirmation: Identifiable {
        let id = UUID()
        let kind: PendingSessionKind
        let gameId: String?
        let ownerUid: String?
        let opponentName: String?
        let practiceId: String?
        let practiceName: String?
    }

    private func requestGameConfirmation(gameId: String, ownerUid: String) {
        let opponent = games.first(where: { $0.id == gameId })?.opponent ?? opponentName
        let defaults = UserDefaults.standard
        if let map = defaults.dictionary(forKey: DefaultsKeys.lastPitcherByGameId) as? [String: String],
           let pitcherId = map[gameId] {
            pendingConfirmationPitcherId = pitcherId
        } else {
            pendingConfirmationPitcherId = selectedPitcherId
        }
        if let map = defaults.dictionary(forKey: DefaultsKeys.lastTemplateByGameId) as? [String: String],
           let templateId = map[gameId],
           let uuid = UUID(uuidString: templateId) {
            pendingConfirmationTemplateId = uuid
        } else {
            pendingConfirmationTemplateId = selectedTemplate?.id
        }
        if let selected = pendingConfirmationTemplateId,
           hiddenTemplateIdSet.contains(selected.uuidString) {
            pendingConfirmationTemplateId = nil
        }
        if pendingConfirmationTemplateId == nil, let first = visibleTemplates.first ?? templates.first {
            pendingConfirmationTemplateId = first.id
        }
        if let selected = pendingConfirmationTemplateId,
           !templates.contains(where: { $0.id == selected }),
           let first = visibleTemplates.first ?? templates.first {
            pendingConfirmationTemplateId = first.id
        }
        pendingGameConfirmation = PendingSessionConfirmation(
            kind: .game,
            gameId: gameId,
            ownerUid: ownerUid,
            opponentName: opponent,
            practiceId: nil,
            practiceName: nil
        )
    }

    private func requestPracticeConfirmation(practiceId: String, practiceName: String?) {
        pendingConfirmationPitcherId = selectedPitcherId
        pendingConfirmationTemplateId = selectedTemplate?.id
        if let selected = pendingConfirmationTemplateId,
           hiddenTemplateIdSet.contains(selected.uuidString) {
            pendingConfirmationTemplateId = nil
        }
        if pendingConfirmationTemplateId == nil, let first = visibleTemplates.first ?? templates.first {
            pendingConfirmationTemplateId = first.id
        }
        if let selected = pendingConfirmationTemplateId,
           !templates.contains(where: { $0.id == selected }),
           let first = visibleTemplates.first ?? templates.first {
            pendingConfirmationTemplateId = first.id
        }
        pendingGameConfirmation = PendingSessionConfirmation(
            kind: .practice,
            gameId: nil,
            ownerUid: nil,
            opponentName: nil,
            practiceId: practiceId,
            practiceName: practiceName
        )
    }

    private func confirmSessionSelection(
        _ item: PendingSessionConfirmation,
        selectedPitcherId: String?,
        selectedTemplateId: UUID?
    ) {
        let defaults = UserDefaults.standard

        if case .game = item.kind, let gameId = item.gameId {
            if let templateId = selectedTemplateId {
                var map = defaults.dictionary(forKey: DefaultsKeys.lastTemplateByGameId) as? [String: String] ?? [:]
                map[gameId] = templateId.uuidString
                defaults.set(map, forKey: DefaultsKeys.lastTemplateByGameId)
            }
            if let pitcherId = selectedPitcherId {
                var map = defaults.dictionary(forKey: DefaultsKeys.lastPitcherByGameId) as? [String: String] ?? [:]
                map[gameId] = pitcherId
                defaults.set(map, forKey: DefaultsKeys.lastPitcherByGameId)
            }
        }

        switch item.kind {
        case .game:
            if let gid = item.gameId, let ownerUid = item.ownerUid {
                chooseGame(gameId: gid, ownerUid: ownerUid)
            }
            if let templateId = selectedTemplateId,
               let template = templates.first(where: { $0.id == templateId }) {
                applyTemplate(template)
            }
            if let pitcherId = selectedPitcherId,
               let pitcher = pitchers.first(where: { $0.id == pitcherId }) {
                applySelectedPitcher(pitcher, allowTemplateOverride: selectedTemplateId == nil)
            }
        case .practice:
            let pid = item.practiceId ?? "__GENERAL__"
            choosePractice(practiceId: pid, practiceName: item.practiceName)
            if let templateId = selectedTemplateId,
               let template = templates.first(where: { $0.id == templateId }) {
                applyTemplate(template)
            }
            if let pitcherId = selectedPitcherId,
               let pitcher = pitchers.first(where: { $0.id == pitcherId }) {
                applySelectedPitcher(pitcher, allowTemplateOverride: selectedTemplateId == nil)
            }
        }

        persistSelectedTemplate(selectedTemplate)
        persistSelectedPitcherId(self.selectedPitcherId)
        pendingGameConfirmation = nil
    }

    private func resolvedGameName(for item: PendingSessionConfirmation) -> String {
        if let gameId = item.gameId {
            if let match = games.first(where: { $0.id == gameId })?.opponent, !match.isEmpty {
                return match
            }
        }
        if let opponent = item.opponentName, !opponent.isEmpty {
            return opponent
        }
        return "Unknown"
    }

    private func resolvedPracticeName(for item: PendingSessionConfirmation) -> String {
        if let name = item.practiceName, !name.isEmpty {
            return name
        }
        if let pid = item.practiceId, pid != "__GENERAL__" {
            let sessions = loadPracticeSessions()
            if let session = sessions.first(where: { $0.id == pid }) {
                return session.name
            }
        }
        return "General"
    }

    private func resolvedTemplateName(for templateId: UUID?) -> String {
        if let templateId,
           let template = templates.first(where: { $0.id == templateId }) {
            return template.name
        }
        if let template = selectedTemplate {
            return template.name
        }
        return "Not set"
    }

    private func resolvedPitcherName(for pitcherId: String?) -> String {
        if let pitcherId,
           let pitcher = pitchers.first(where: { $0.id == pitcherId }) {
            return pitcher.name
        }
        if let pitcherId = selectedPitcherId,
           let pitcher = pitchers.first(where: { $0.id == pitcherId }) {
            return pitcher.name
        }
        return "Not set"
    }

    // Tiny factory to reduce type-checker work when creating bindings
    private func intBinding(
        get: @escaping () -> Int,
        set: @escaping (Int) -> Void
    ) -> Binding<Int> {
        Binding(get: get, set: set)
    }
    
    private func updateSharedCounts(_ fields: [String: Any]) {
        if let liveId = activeLiveId {
            LiveGameService.shared.updateLiveFields(liveId: liveId, fields: fields)
            return
        }
    }

    private func mirrorLiveProgressToGame(field: String, value: Int) {
        guard isOwnerForActiveGame,
              let gid = selectedGameId,
              let owner = effectiveGameOwnerUserId
        else { return }

        switch field {
        case "inning":
            authManager.updateGameInning(ownerUserId: owner, gameId: gid, inning: value)
            if let idx = games.firstIndex(where: { $0.id == gid }) { games[idx].inning = value }
        case "hits":
            authManager.updateGameHits(ownerUserId: owner, gameId: gid, hits: value)
            if let idx = games.firstIndex(where: { $0.id == gid }) { games[idx].hits = value }
        case "walks":
            authManager.updateGameWalks(ownerUserId: owner, gameId: gid, walks: value)
            if let idx = games.firstIndex(where: { $0.id == gid }) { games[idx].walks = value }
        case "balls":
            authManager.updateGameBalls(ownerUserId: owner, gameId: gid, balls: value)
            if let idx = games.firstIndex(where: { $0.id == gid }) { games[idx].balls = value }
        case "strikes":
            authManager.updateGameStrikes(ownerUserId: owner, gameId: gid, strikes: value)
            if let idx = games.firstIndex(where: { $0.id == gid }) { games[idx].strikes = value }
        case "us":
            authManager.updateGameUs(ownerUserId: owner, gameId: gid, us: value)
            if let idx = games.firstIndex(where: { $0.id == gid }) { games[idx].us = value }
        case "them":
            authManager.updateGameThem(ownerUserId: owner, gameId: gid, them: value)
            if let idx = games.firstIndex(where: { $0.id == gid }) { games[idx].them = value }
        default:
            break
        }
        markLocalProgressChange()
    }

    private var inningBinding: Binding<Int> {
        intBinding(
            get: { inning },
            set: { newValue in
                if let liveId = activeLiveId {
                    LiveGameService.shared.updateLiveFields(liveId: liveId, fields: ["inning": newValue, "progressUpdatedAt": FieldValue.serverTimestamp()])
                    inning = newValue
                    mirrorLiveProgressToGame(field: "inning", value: newValue)
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameInning(ownerUserId: owner, gameId: gid, inning: newValue)

                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].inning = newValue
                }
                print("🧭[PROG] set inning=\(newValue) gid=\(gid)")
                markLocalProgressChange()
            }
        )
    }


    private var hitsBinding: Binding<Int> {
        intBinding(
            get: { hits },
            set: { newValue in
                if let liveId = activeLiveId {
                    LiveGameService.shared.updateLiveFields(liveId: liveId, fields: ["hits": newValue, "progressUpdatedAt": FieldValue.serverTimestamp()])
                    hits = newValue
                    mirrorLiveProgressToGame(field: "hits", value: newValue)
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameHits(ownerUserId: owner, gameId: gid, hits: newValue)

                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].hits = newValue
                }
                print("🧭[PROG] set hits=\(newValue) gid=\(gid)")
                markLocalProgressChange()
            }
        )
    }

    
    private var walksBinding: Binding<Int> {
        intBinding(
            get: { walks },
            set: { newValue in
                if let liveId = activeLiveId {
                    LiveGameService.shared.updateLiveFields(liveId: liveId, fields: ["walks": newValue, "progressUpdatedAt": FieldValue.serverTimestamp()])
                    walks = newValue
                    mirrorLiveProgressToGame(field: "walks", value: newValue)
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameWalks(ownerUserId: owner, gameId: gid, walks: newValue)

                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].walks = newValue
                }
                print("🧭[PROG] set walks=\(newValue) gid=\(gid)")
                markLocalProgressChange()
            }
        )
    }

    private var ballsBinding: Binding<Int> {
        intBinding(
            get: { balls },
            set: { newValue in
                if let liveId = activeLiveId {
                    LiveGameService.shared.updateLiveFields(liveId: liveId, fields: ["balls": newValue, "progressUpdatedAt": FieldValue.serverTimestamp()])
                    balls = newValue
                    mirrorLiveProgressToGame(field: "balls", value: newValue)
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameBalls(ownerUserId: owner, gameId: gid, balls: newValue)

                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].balls = newValue
                }
                print("🧭[PROG] set balls=\(newValue) gid=\(gid)")
                markLocalProgressChange()
            }
        )
    }

    private var strikesBinding: Binding<Int> {
        intBinding(
            get: { strikes },
            set: { newValue in
                if let liveId = activeLiveId {
                    LiveGameService.shared.updateLiveFields(liveId: liveId, fields: ["strikes": newValue, "progressUpdatedAt": FieldValue.serverTimestamp()])
                    strikes = newValue
                    mirrorLiveProgressToGame(field: "strikes", value: newValue)
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameStrikes(ownerUserId: owner, gameId: gid, strikes: newValue)

                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].strikes = newValue
                }
                print("🧭[PROG] set strikes=\(newValue) gid=\(gid)")
                markLocalProgressChange()
            }
        )
    }

    private var usBinding: Binding<Int> {
        intBinding(
            get: { us },
            set: { newValue in
                if let liveId = activeLiveId {
                    LiveGameService.shared.updateLiveFields(liveId: liveId, fields: ["us": newValue, "progressUpdatedAt": FieldValue.serverTimestamp()])
                    us = newValue
                    mirrorLiveProgressToGame(field: "us", value: newValue)
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameUs(ownerUserId: owner, gameId: gid, us: newValue)

                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].us = newValue
                }
                print("🧭[PROG] set us=\(newValue) gid=\(gid)")
                markLocalProgressChange()
            }
        )
    }

    private var themBinding: Binding<Int> {
        intBinding(
            get: { them },
            set: { newValue in
                if let liveId = activeLiveId {
                    LiveGameService.shared.updateLiveFields(liveId: liveId, fields: ["them": newValue, "progressUpdatedAt": FieldValue.serverTimestamp()])
                    them = newValue
                    mirrorLiveProgressToGame(field: "them", value: newValue)
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameThem(ownerUserId: owner, gameId: gid, them: newValue)

                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].them = newValue
                }
                print("🧭[PROG] set them=\(newValue) gid=\(gid)")
                markLocalProgressChange()
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

    private var selectedPitcherName: String {
        guard let pid = selectedPitcherId else { return "Select a pitcher" }
        guard let pitcher = pitchers.first(where: { $0.id == pid }) else { return "Select a pitcher" }
        if isGame && !pitcher.isActiveOwner(currentUid: authManager.user?.uid) {
            return "Owner only"
        }
        return pitcher.name
    }

    private var canSelectPitcherInGame: Bool {
        guard isGame else { return true }
        let uid = authManager.user?.uid
        if let pid = selectedPitcherId, let current = pitchers.first(where: { $0.id == pid }) {
            return current.isActiveOwner(currentUid: uid)
        }
        return pitchers.contains { $0.isActiveOwner(currentUid: uid) }
    }

    private var selectedPitcherForStats: Pitcher? {
        let pid: String? = {
            if activeLiveId != nil {
                return livePitcherId ?? selectedPitcherId
            }
            return selectedPitcherId
        }()
        guard let pid else { return nil }
        return pitchers.first(where: { $0.id == pid })
    }

    private func syncLivePitcherSelectionIfOwner() {
        guard isOwnerForActiveGame,
              let liveId = activeLiveId,
              let pid = selectedPitcherId,
              !pid.isEmpty,
              let pitcher = pitchers.first(where: { $0.id == pid })
        else { return }

        LiveGameService.shared.updateLiveFields(
            liveId: liveId,
            fields: [
                "pitcherId": pid,
                "pitcherName": pitcher.name
            ]
        )
    }

    private func syncLiveTemplateSelectionIfOwner() {
        guard isOwnerForActiveGame,
              let liveId = activeLiveId,
              let template = selectedTemplate
        else { return }

        LiveGameService.shared.updateLiveFields(
            liveId: liveId,
            fields: [
                "templateId": template.id.uuidString,
                "templateName": template.name
            ]
        )
    }

    private var effectivePitcherIdForSave: String? {
        if isGame && activeLiveId != nil { return livePitcherId ?? selectedPitcherId }
        return selectedPitcherId
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
                overlayTabsHeader

                Divider()
                    .padding(.top, 5)

                overlayContent
                    .padding(.top, -14)
                    .frame(maxWidth: .infinity)
                    .frame(height: 170, alignment: .top)
            }
            .blur(radius: shouldBlurBackground ? 6 : 0)
            .animation(.easeInOut(duration: 0.2), value: shouldBlurBackground)
            .transition(.opacity)

            calledPitchLayer

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: [.horizontal])   // ✅ CHANGED (removed .bottom)
        .background(.regularMaterial)
    }

    private var overlayTabsHeader: some View {
        HStack(spacing: 6) {
            OverlayTabButton(
                title: "Progress",
                systemImage: "chart.bar.xaxis",
                isSelected: overlayTab == .progress
            ) {
                overlayTab = .progress
            }

            OverlayTabButton(
                title: "Cards",
                systemImage: "square.grid.2x2",
                isSelected: overlayTab == .cards
            ) {
                overlayTab = .cards
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }
    private struct OverlayTabButton: View {
        let title: String
        let systemImage: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(isSelected ? .black : .black.opacity(0.4))
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .background(isSelected ? .ultraThickMaterial : .ultraThinMaterial)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
    @ViewBuilder
    private var overlayContent: some View {
        switch overlayTab {
        case .cards:
            cardsOverlayContent

        case .progress:
            progressOverlayContent
        }
    }
    @ViewBuilder
    private var cardsOverlayContent: some View {
        let showCards = (selectedTemplate != nil) || (isGame && (activeLiveId != nil || !isOwnerForActiveGame))
        if showCards {
            PitchResultSheet(
                allEvents: filteredEvents,
                games: games,
                templates: templates,
                pitchers: pitchers,
                isParticipant: (isGame && !isOwnerForActiveGame),
                selectedPlayerName: selectedPitcherName
            )
            .environmentObject(authManager)
            .environmentObject(sessionManager)
            .frame(maxWidth: .infinity, minHeight: 170)
        } else {
            EmptyView()
                .frame(maxWidth: .infinity, minHeight: 170)
        }
    }
    private var calledPitchLayer: some View {
        Group {
            if let call = calledPitch {
                CalledPitchView(
                    isRecordingResult: $isRecordingResult,
                    activeCalledPitchId: $activeCalledPitchId,
                    pitchFirst: $pitchFirst,
                    autoPitchOnlyEnabled: $autoPitchOnlyEnabled,
                    liveId: activeLiveId,
                    call: call,
                    pitchCodeAssignments: pitchCodeAssignments,
                    batterSide: batterSide,
                    template: selectedTemplate,
                    isEncryptedMode: selectedTemplate.map { useEncrypted(for: $0) } ?? false,
                    isPracticeMode: sessionManager.currentMode == .practice,
                    onDeferDisplayCode: { colorName, code in
                        deferredDisplayCode = (colorName: colorName, code: code)
                        ensureAutoLiveSessionIfNeeded()
                    }
                )
                .transition(.opacity)
                .padding(.top, 4)
                .onAppear { handleCalledPitchAppear() }
                .onDisappear { handleCalledPitchDisappear() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom)  // ✅ remove maxHeight: .infinity
        .safeAreaPadding(.bottom, 12)                    // ✅ respects home indicator
    }
    private func handleCalledPitchAppear() {
        shouldBlurBackground = true
    }
    private func handleCalledPitchDisappear() {
        shouldBlurBackground = false
    }

    @ViewBuilder
    private var progressOverlayContent: some View {
        if sessionManager.currentMode == .practice {
            ProgressSummaryView(
                events: pitchEvents,
                currentMode: sessionManager.currentMode,
                selectedPracticeId: selectedPracticeId,
                templates: templates
            )
            .id(progressRefreshToken)
            .frame(maxWidth: .infinity, minHeight: 170)
        } else {
            ProgressGameView(
                ownerUserId: effectiveGameOwnerUserId,
                balls: ballsBinding,
                strikes: strikesBinding,
                inning: inningBinding,
                hits: hitsBinding,
                walks: walksBinding,
                us: usBinding,
                them: themBinding,
                selectedGameId: $selectedGameId,
                onProgressChange: {
                    markLocalProgressChange()
                }
            )
            .environmentObject(authManager)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .top)
        }
    }


    private var headerContainer: some View {
        let screen = effectiveScreenSize
        
        return VStack(spacing: 4) {
            topBar
        }
        .frame(
            width: screen.width * 0.94,   // 94% of screen width
            height: headerHeight
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
        .padding(.top, 24)
    }

    private var isCompactHeight: Bool {
        effectiveScreenSize.height <= 700
    }

    private var headerHeight: CGFloat {
        isCompactHeight ? 54 : effectiveScreenSize.height * 0.10
    }

    private var strikeZoneHeight: CGFloat {
        isCompactHeight ? 320 : 390
    }
    
    private var participantHeaderOverlay: some View {
        Group {
            if showParticipantOverlay && isGame && !isOwnerForActiveGame {
                VStack(spacing: 8) {
                    Spacer()

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Game in progress")
                                .font(.headline.weight(.semibold))
                            if let tname = ownerTemplateName, !tname.isEmpty {
                                Text("Template: \(tname)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            disconnectFromGame(notifyHost: false)
                        } label: {
                            Label("Disconnect", systemImage: "xmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: effectiveScreenSize.height * 0.15)
                .background(
                    .ultraThickMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.opacity)
                .allowsHitTesting(true)
            }
        }
    }


    private var contentSection: some View {
        Group {
            batterAndModeBar
            mainStrikeZoneSection
            Spacer(minLength: 16)
            cardsAndOverlay
        }
    }
    
    private var contentSectionDimmed: some View {
        let isActiveLiveParticipant = (activeLiveId != nil && isGame && !isOwnerForActiveGame)
        let isDimmed = (selectedTemplate == nil && !isActiveLiveParticipant)
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
            HStack(spacing: 12) {
                VStack(alignment: .center, spacing: 4) {
                Text(isGame ? "Game" : "Practice")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: {}) {
                    HStack(spacing: 6) {
                        Text(isGame ? (opponentName ?? "Game") : (practiceName ?? "Practice"))
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(true)
                .opacity(0.7)
                }

                if !(isGame && !isOwnerForActiveGame) {
                    VStack(alignment: .center, spacing: 4) {
                        Text("Pitcher")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Menu {
                            let pitchersForMenu = isGame
                            ? visiblePitchers.filter { $0.isActiveOwner(currentUid: authManager.user?.uid) }
                            : visiblePitchers
                            ForEach(pitchersForMenu) { pitcher in
                                Button(pitcher.name) {
                                    applySelectedPitcher(pitcher)
                                }
                            }
                        } label: {
                            let currentLabel = selectedPitcherName
                            let widestLabel = ([currentLabel] + visiblePitchers.map { $0.name }).max(by: { $0.count < $1.count }) ?? currentLabel

                            ZStack {
                                HStack(spacing: 8) {
                                    Text(widestLabel)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .allowsTightening(true)
                                        .opacity(0)
                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.semibold))
                                        .opacity(0)
                                }

                                HStack(spacing: 8) {
                                    Text(currentLabel)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .allowsTightening(true)
                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.semibold))
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
                            .opacity((visiblePitchers.isEmpty || !canSelectPitcherInGame) ? 0.6 : 1.0)
                            .contentShape(Capsule())
                        }
                        .disabled(visiblePitchers.isEmpty || !canSelectPitcherInGame)
                    }

                    VStack(alignment: .center, spacing: 4) {
                        Text("Grid Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Menu {
                            ForEach(visibleTemplates, id: \.id) { template in
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
                            let widestLabel = ([currentLabel] + visibleTemplates.map { $0.name }).max(by: { $0.count < $1.count }) ?? currentLabel
                            
                            ZStack {
                                // Invisible widest label to reserve width and prevent size jumps
                                HStack(spacing: 8) {
                                    Text(widestLabel)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .allowsTightening(true)
                                        .opacity(0)
                                    if !currentTemplateVersionLabel.isEmpty {
                                        Text(currentTemplateVersionLabel)
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.clear)
                                            .opacity(0)
                                    }
                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.semibold))
                                        .opacity(0)
                                }
                                
                                // Visible current label
                                HStack(spacing: 8) {
                                    Text(currentLabel)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .allowsTightening(true)
                                    if !currentTemplateVersionLabel.isEmpty {
                                        Text(currentTemplateVersionLabel)
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .foregroundStyle(Color.gray)
                                            .clipShape(Capsule())
                                            .accessibilityLabel("Template version \(currentTemplateVersionLabel)")
                                    }
                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.semibold))
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
                            .opacity(visibleTemplates.isEmpty ? 0.6 : 1.0)
                            .contentShape(Capsule())
                            .animation(.easeInOut(duration: 0.2), value: selectedTemplate?.id)
                        }
                        .disabled(visibleTemplates.isEmpty)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            codeLinkButton
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

    private func sessionConfirmationSheet(
        pending: PendingSessionConfirmation
    ) -> some View {
        SessionConfirmationSheet(
            pending: pending,
            pitchers: visiblePitchers,
            templates: visibleTemplates,
            selectedPitcherId: $pendingConfirmationPitcherId,
            selectedTemplateId: $pendingConfirmationTemplateId,
            resolvedPitcherName: resolvedPitcherName(for: pendingConfirmationPitcherId),
            resolvedTemplateName: resolvedTemplateName(for: pendingConfirmationTemplateId),
            resolvedGameName: resolvedGameName(for: pending),
            resolvedPracticeName: resolvedPracticeName(for: pending),
            onConfirm: {
                confirmSessionSelection(
                    pending,
                    selectedPitcherId: pendingConfirmationPitcherId,
                    selectedTemplateId: pendingConfirmationTemplateId
                )
            },
            onCancel: {
                pendingGameConfirmation = nil
            }
        )
    }
    
    private var mainStrikeZoneSection: some View {
        let deviceWidth = effectiveScreenSize.width
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
            let needsBatterSelection = selectedBatterId == nil

            VStack(spacing: 0) {
                Text("At Bat")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(needsBatterSelection ? Color.red.opacity(0.7) : Color.gray)

                ZStack(alignment: .top) {
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
                                    effectiveGameOwnerUserId: effectiveGameOwnerUserId,
                                    activeLiveId: activeLiveId,
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

                                            // 1) Apply local change (edit vs add)
                                            if let editing = editingCell,
                                               let idx = jerseyCells.firstIndex(where: { $0.id == editing.id }) {
                                                jerseyCells[idx].jerseyNumber = normalized
                                            } else {
                                                // Add new cell (keep UUID stable across devices by storing batterIds)
                                                let newCell = JerseyCell(jerseyNumber: normalized)
                                                jerseyCells.append(newCell)
                                            }

                                            // 2) Persist lineup (single source of truth)
                                            func persistLineup(jerseyCells: [JerseyCell]) {
                                                let jerseys = jerseyCells.map { $0.jerseyNumber }
                                                let batterIds = jerseyCells.map { $0.id.uuidString }

                                                if let liveId = activeLiveId, !liveId.isEmpty {
                                                    // LIVE session: write to liveGames so owner + participant both update
                                                    LiveGameService.shared.updateLiveFields(
                                                        liveId: liveId,
                                                        fields: [
                                                            "jerseyNumbers": jerseys,
                                                            "batterIds": batterIds
                                                        ]
                                                    )
                                                    if let gameId = selectedGameId,
                                                       let owner = effectiveGameOwnerUserId,
                                                       !owner.isEmpty,
                                                       isOwnerForActiveGame {
                                                        authManager.updateGameLineup(
                                                            ownerUserId: owner,
                                                            gameId: gameId,
                                                            jerseyNumbers: jerseys,
                                                            batterIds: batterIds
                                                        )
                                                    }
                                                } else if let gameId = selectedGameId,
                                                          let owner = effectiveGameOwnerUserId,
                                                          !owner.isEmpty {
                                                    // Non-live: update owner's game doc
                                                    authManager.updateGameLineup(
                                                        ownerUserId: owner,
                                                        gameId: gameId,
                                                        jerseyNumbers: jerseys,
                                                        batterIds: batterIds
                                                    )
                                                } else {
                                                    print("⚠️ Cannot update lineup: missing activeLiveId (live) or selectedGameId/effectiveGameOwnerUserId (non-live)")
                                                }
                                            }

                                            persistLineup(jerseyCells: jerseyCells)

                                            // 3) Reset UI state
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
                                if jerseyCells.isEmpty {
                                    showBulkJerseyPrompt = true
                                } else {
                                    showAddJerseyPopover = true
                                    jerseyInputFocused = true
                                }
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
                            .confirmationDialog(
                                "Add multiple jersey numbers?",
                                isPresented: $showBulkJerseyPrompt,
                                titleVisibility: .visible
                            ) {
                                Button("Add Multiple") {
                                    bulkJerseyNumbers = ""
                                    showBulkJerseyInput = true
                                }
                                Button("Add One", role: .cancel) {
                                    showAddJerseyPopover = true
                                    jerseyInputFocused = true
                                }
                            } message: {
                                Text("Speak or type the jersey numbers with commas in between (example: 2, 7, 18).")
                            }
                            .alert("Add jersey numbers", isPresented: $showBulkJerseyInput) {
                                TextField("2, 7, 18", text: $bulkJerseyNumbers)
                                Button("Cancel", role: .cancel) {
                                    bulkJerseyNumbers = ""
                                }
                                Button("Add") {
                                    let rawParts = bulkJerseyNumbers
                                        .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
                                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    let normalizedParts = rawParts.compactMap { part -> String? in
                                        guard !part.isEmpty else { return nil }
                                        return normalizeJersey(part) ?? part
                                    }
                                    let existing = Set(jerseyCells.map { $0.jerseyNumber })
                                    let unique = normalizedParts.filter { !existing.contains($0) }
                                    guard !unique.isEmpty else {
                                        bulkJerseyNumbers = ""
                                        return
                                    }
                                    let newCells = unique.map { JerseyCell(jerseyNumber: $0) }
                                    jerseyCells.append(contentsOf: newCells)

                                    func persistLineup(jerseyCells: [JerseyCell]) {
                                        let jerseys = jerseyCells.map { $0.jerseyNumber }
                                        let batterIds = jerseyCells.map { $0.id.uuidString }

                                        if let liveId = activeLiveId, !liveId.isEmpty {
                                            LiveGameService.shared.updateLiveFields(
                                                liveId: liveId,
                                                fields: [
                                                    "jerseyNumbers": jerseys,
                                                    "batterIds": batterIds
                                                ]
                                            )
                                            if let gameId = selectedGameId,
                                               let owner = effectiveGameOwnerUserId,
                                               !owner.isEmpty,
                                               isOwnerForActiveGame {
                                                authManager.updateGameLineup(
                                                    ownerUserId: owner,
                                                    gameId: gameId,
                                                    jerseyNumbers: jerseys,
                                                    batterIds: batterIds
                                                )
                                            }
                                        } else if let gameId = selectedGameId,
                                                  let owner = effectiveGameOwnerUserId,
                                                  !owner.isEmpty {
                                            authManager.updateGameLineup(
                                                ownerUserId: owner,
                                                gameId: gameId,
                                                jerseyNumbers: jerseys,
                                                batterIds: batterIds
                                            )
                                        } else {
                                            print("⚠️ Cannot update lineup: missing activeLiveId (live) or selectedGameId/effectiveGameOwnerUserId (non-live)")
                                        }
                                    }

                                    persistLineup(jerseyCells: jerseyCells)

                                    bulkJerseyNumbers = ""
                                }
                            } message: {
                                Text("Speak or type the jersey numbers with commas in between.")
                            }
                        }
                        .padding(.vertical,12)
                        .padding(.horizontal, 0)
                    }
                }

                if needsBatterSelection {
                    Text("Select a batter")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.red.opacity(0.85))
                        )
                        .padding(.top, 6)
                }
                }
            .frame(width: 60, height: strikeZoneHeight)
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(needsBatterSelection ? Color.red.opacity(0.8) : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 4)
        }
    }
    
    private var resetOverlay: some View {
        Group {
            ResetPitchButton {
                // ✅ 1) Reset owner local UI
                isRecordingResult = false
                selectedPitch = ""
                selectedLocation = ""
                lastTappedPosition = nil
                calledPitch = nil
                resultVisualState = nil
                actualLocationRecorded = nil
                pendingResultLabel = nil

                // ✅ 2) Broadcast reset to participant by clearing SHARED pending + resultSelection
                if isGame,
                   let gid = selectedGameId,
                   let owner = effectiveGameOwnerUserId,
                   !owner.isEmpty,
                   isOwnerForActiveGame
                {
                    // Clear the pending pitch so participant UI resets immediately
                    authManager.clearPendingPitch(ownerUserId: owner, gameId: gid)

                    // Clear any resultSelection helper field too (optional but good)
                    writeResultSelection(label: nil)
                }
            }

        }
    }
    
    private var gameStatsOverlay: some View {
        Group {
            if isGame {
                Button(action: {
                    showGameStatsSheet = true
                }) {
                    Image(systemName: "chart.bar")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Game Stats")
            }
        }
    }
    
    @ViewBuilder
    private func batterSideOverlay(SZwidth: CGFloat) -> some View {
        HStack {
            let iconSize: CGFloat = 36
            Button(action: {
                withAnimation { batterSide = .left }
                persistBatterSide(.left)
                pushBatterSideToActiveGame(.left)
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
                pushBatterSideToActiveGame(.right)
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
        let strikeZoneHeight: CGFloat
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
        let canInitiateCall: Bool

        var body: some View {
            VStack {
                StrikeZoneView(
                    width: SZwidth,
                    height: strikeZoneHeight,
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
                    template: template,
                    canInitiateCall: canInitiateCall
                )
                .id(colorRefreshToken)
            }
            .frame(width: SZwidth, height: strikeZoneHeight)
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
                strikeZoneHeight: strikeZoneHeight,
                isGame: $isGame,
                batterSide: batterSide,
                lastTappedPosition: lastTappedPosition,
                setLastTapped: { lastTappedPosition = $0 },
                calledPitch: calledPitch,
                setCalledPitch: { handleSetCalledPitch($0) },
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
                template: selectedTemplate,
                canInitiateCall: canInitiateCall
            )
            .overlay(resetOverlay, alignment: .bottomLeading)
            .overlay(gameStatsOverlay, alignment: .bottomTrailing)

            batterSideOverlay(SZwidth: SZwidth)
        }
        .frame(width: SZwidth, height: strikeZoneHeight)
    }
    private var codeLinkButton: some View {
        Menu {
            Button {
                if !subscriptionManager.isPro {
                    proGateMessage = "Code links require PitchMark Pro."
                    showProGateAlert = true
                    return
                }
                showCodeShareModePicker = true
            } label: {
                Label("Code Link", systemImage: "key.sensor.tag.radiowaves.left.and.right.fill")
            }

            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "key.sensor.tag.radiowaves.left.and.right.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(uiConnected ? .green : .red)
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(
                width: 40,
                height: max(0, headerHeight - 22)
            )
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Code Link and Settings")
        // ✅ Attach the dialog HERE so it anchors to THIS button
        .confirmationDialog(
            "Invite Link",
            isPresented: $showCodeShareModePicker,
            titleVisibility: .visible
        ) {
            Button("Create Invite Link") {
                codeShareInitialTab = 0
                showCodeShareSheet = true
            }

            Button("Join via Invite Link") {
                if !subscriptionManager.isPro {
                    proGateMessage = "Joining games requires PitchMark Pro."
                    showProGateAlert = true
                    return
                }
                inviteJoinError = nil
                inviteJoinText = ""
                showInviteJoinSheet = true
            }

            // ✅ Disconnect (both sides) — only show when currently linked
            if let liveId = activeLiveId, !liveId.isEmpty {
                Button(isOwnerForActiveGame ? "Disconnect Participant" : "Disconnect from Host", role: .destructive) {
                    if let liveId = activeLiveId, !liveId.isEmpty {
                        LiveGameService.shared.updateLiveFields(
                            liveId: liveId,
                            fields: [
                                "connection": [
                                    "participantUid": NSNull(),
                                    "connected": false,
                                    "disconnectedAt": FieldValue.serverTimestamp()
                                ]
                            ]
                        )
                    }
                    endLiveSessionLocally(keepCurrentGame: isOwnerForActiveGame)
                    showCodeShareModePicker = false
                }
            }

            Button("Cancel", role: .cancel) { }
        }
    }


    private var batterAndModeBar: some View {
        HStack(spacing: 10) {
            Spacer()

            Picker("Mode", selection: $sessionManager.currentMode) {
                Text("Practice").tag(PitchMode.practice)
                Text("Game").tag(PitchMode.game)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 180)
            .fixedSize(horizontal: true, vertical: false)
            .onChange(of: sessionManager.currentMode) { _, newValue in
                // HARD GATES: never present sheets during app boot or while restoring persisted state
                if isJoiningSession { return }
                if startupPhase != .ready || isRestoringState {
                    sessionManager.switchMode(to: newValue)
                    persistMode(newValue)
                    isGame = (newValue == .game)
                    return
                }

                sessionManager.switchMode(to: newValue)
                persistMode(newValue)

                if newValue == .game {
                    if suppressNextGameSheet {
                        suppressNextGameSheet = false
                        isGame = true
                    } else {
                        isGame = true
                        presentExclusive(game: true)
                    }
                } else {
                    // Practice mode
                    isGame = false
                    if suppressNextGameSheet {
                        suppressNextGameSheet = false
                    } else {
                        presentExclusive(practice: true)
                    }
                    progressRefreshToken = UUID()
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.bottom, 6)
        .padding(.top, 6)
    }


    private var backgroundView: some View {
        Color.appBrandBackground
            .ignoresSafeArea()
    }

    private var mainStack: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 4) {
                headerContainer
                Spacer(minLength: 10)
                contentSectionDimmed
            }

            // Top overlays (only one should show based on your conditions)
            ZStack(alignment: .top) {
                participantHeaderOverlay
            }
            .allowsHitTesting(true)
        }
    }

    
    // MARK: - Change Handlers
    private func handlePendingResultChange(_ newValue: String?) {
        // Auto-save in Practice, notify owner in Game (participant side)
        guard newValue != nil else { return }

        if autoPitchOnlyEnabled,
           sessionManager.currentMode == .game,
           let value = newValue,
           !value.isEmpty,
           (showConfirmSheet || showResultConfirmation),
           let event = buildPitchOnlyEvent()
        {
            showConfirmSheet = false
            persistPitchEvent(event)
            return
        }

        if sessionManager.currentMode == .game, !isOwnerForActiveGame {
            guard let value = newValue, !value.isEmpty else { return }

            // ✅ Only send after the participant actually starts confirming a result
            // (prevents echoing the incoming pending label back to the owner)
            guard showConfirmSheet || showResultConfirmation else { return }

            writeResultSelection(label: value)
            return
        }

        // Practice: existing auto-save path
        guard sessionManager.currentMode == .practice else { return }
        guard let pitchCall = calledPitch, let label = pendingResultLabel else { return }

        // Build minimal practice event
        let event = PitchEvent(
            id: nil,
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
            practiceId: selectedPracticeId,
            pitcherId: selectedPitcherId
        )
        event.debugLog(prefix: "📤 Auto-saving Practice PitchEvent")

        // Persist and update UI state
        authManager.savePitchEvent(event)
        saveSharedPitcherEventIfAllowed(event)
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
        activeCalledPitchId = nil
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

    private func buildPitchOnlyEvent() -> PitchEvent? {
        guard let label = pendingResultLabel,
              let pitchCall = calledPitch else {
            return nil
        }

        return PitchEvent(
            id: nil,
            timestamp: Date(),
            pitch: pitchCall.pitch,
            location: label,
            codes: pitchCall.codes,
            isStrike: pitchCall.isStrike,
            isBall: isBall,
            mode: sessionManager.currentMode,
            calledPitch: pitchCall,
            batterSide: batterSide,
            templateId: selectedTemplate?.id.uuidString,
            strikeSwinging: isStrikeSwinging,
            wildPitch: isWildPitch,
            passedBall: isPassedBall,
            strikeLooking: isStrikeLooking,
            outcome: selectedOutcome,
            descriptor: selectedDescriptor,
            errorOnPlay: isError,
            battedBallRegion: nil,
            battedBallType: nil,
            battedBallTapX: nil,
            battedBallTapY: nil,
            gameId: selectedGameId,
            opponentJersey: jerseyCells.first(where: { $0.id == selectedBatterId })?.jerseyNumber,
            opponentBatterId: selectedBatterId?.uuidString,
            practiceId: selectedPracticeId,
            pitcherId: effectivePitcherIdForSave
        )
    }

    private func persistPitchEvent(_ event: PitchEvent) {
        var sharedEvent = event
        if isGame, let liveId = activeLiveId {
            // ✅ Live: save to shared room
            let uid = authManager.user?.uid ?? ""
            do {
                var eventData = try Firestore.Encoder().encode(event)
                // Firestore.Encoder already encodes event.timestamp correctly (as a Timestamp).
                eventData["createdByUid"] = uid
                eventData["liveId"] = liveId

                // ✅ OPTIONAL: keep a server-side write time in a separate field (doesn't break decoding)
                eventData["serverTimestamp"] = FieldValue.serverTimestamp()

                if let gid = selectedGameId {
                    eventData["gameId"] = gid
                }

                let liveRef = Firestore.firestore()
                    .collection("liveGames").document(liveId)
                    .collection("pitchEvents").document()
                let liveEventId = liveRef.documentID
                sharedEvent.id = liveEventId

                liveRef.setData(eventData, merge: false) { err in
                    if let err {
                        print("❌ live pitchEvent save failed:", err.localizedDescription)
                    }
                }

                if let owner = effectiveGameOwnerUserId,
                   let gid = selectedGameId,
                   !owner.isEmpty {
                    let ownerRef = Firestore.firestore()
                        .collection("users").document(owner)
                        .collection("games").document(gid)
                        .collection("pitchEvents").document(liveEventId)
                    ownerRef.setData(eventData, merge: false) { err in
                        if let err {
                            print("❌ owner pitchEvent save failed:", err.localizedDescription)
                        }
                    }
                } else {
                    print("⚠️ Owner path unavailable; saved only to liveGames.")
                }

                // clear pending in live doc
                LiveGameService.shared.updateLiveFields(liveId: liveId, fields: [
                    "pending": FieldValue.delete()
                ])
            } catch {
                print("❌ encode event failed:", error)
            }
        } else if isGame, let gid = selectedGameId, let owner = effectiveGameOwnerUserId {
            // Legacy fallback
            authManager.saveGamePitchEvent(ownerUserId: owner, gameId: gid, event: event)
            authManager.clearPendingPitch(ownerUserId: owner, gameId: gid)
        } else {
            // Practice
            authManager.savePitchEvent(event)
        }

        saveSharedPitcherEventIfAllowed(sharedEvent)

        writeResultSelection(label: event.location)

        sessionManager.incrementCount()

        // ✅ LIVE: do NOT append to local pitchEvents (prevents “saved on participant” feeling).
        // Owner will show cards from live listener; practice/legacy continue using pitchEvents.
        if activeLiveId == nil {
            withAnimation(.easeInOut(duration: 0.3)) {
                pitchEvents.append(event)
            }
            authManager.loadPitchEvents { events in
                self.pitchEvents = events
            }
            if overlayTab == .progress && sessionManager.currentMode == .practice {
                progressRefreshToken = UUID()
            }
        }

        resultVisualState = event.location
        activeCalledPitchId = nil
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

    private var bufferedSharedEventsURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("PitchMark", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("buffered_shared_pitcher_events.json")
    }

    private func loadBufferedSharedPitcherEvents() {
        let url = bufferedSharedEventsURL
        guard let data = try? Data(contentsOf: url) else {
            bufferedSharedPitcherEvents = []
            return
        }
        do {
            let decoded = try JSONDecoder().decode([BufferedPitcherEvent].self, from: data)
            bufferedSharedPitcherEvents = decoded
        } catch {
            print("❌ Failed to decode buffered pitcher events:", error.localizedDescription)
            bufferedSharedPitcherEvents = []
        }
    }

    private func persistBufferedSharedPitcherEvents() {
        do {
            let data = try JSONEncoder().encode(bufferedSharedPitcherEvents)
            try data.write(to: bufferedSharedEventsURL, options: [.atomic])
        } catch {
            print("❌ Failed to persist buffered pitcher events:", error.localizedDescription)
        }
    }

    private func bufferSharedPitcherEvent(pitcherId: String, event: PitchEvent) {
        bufferedSharedPitcherEvents.append(BufferedPitcherEvent(pitcherId: pitcherId, event: event))
        persistBufferedSharedPitcherEvents()
    }

    private func flushBufferedSharedPitcherEvents(reason: String) {
        guard !bufferedSharedPitcherEvents.isEmpty else { return }
        print("📤 Flushing \(bufferedSharedPitcherEvents.count) buffered pitcher events (reason: \(reason))")
        for buffered in bufferedSharedPitcherEvents {
            authManager.saveSharedPitcherEvent(pitcherId: buffered.pitcherId, event: buffered.event)
        }
        bufferedSharedPitcherEvents.removeAll()
        persistBufferedSharedPitcherEvents()
    }

    private var shouldWriteSharedPitcherEventImmediately: Bool {
        activeLiveId != nil && uiConnected
    }

    private func saveSharedPitcherEventIfAllowed(_ event: PitchEvent) {
        let targetPitcherId = event.pitcherId ?? selectedPitcherId
        guard let pitcherId = targetPitcherId else { return }
        guard let pitcher = pitchers.first(where: { $0.id == pitcherId }) else { return }
        guard let uid = authManager.user?.uid else { return }

        let isOwner = pitcher.isActiveOwner(currentUid: uid)
        let isShared = pitcher.sharedWith.contains(uid)
        if !isOwner && !isShared {
            print("⚠️ Shared pitcher write not confirmed (owner/shared missing); attempting save to let rules decide.")
        }

        if shouldWriteSharedPitcherEventImmediately {
            authManager.saveSharedPitcherEvent(pitcherId: pitcherId, event: event)
        } else {
            bufferSharedPitcherEvent(pitcherId: pitcherId, event: event)
        }
    }
    
    private var baseBody: some View {
        ZStack {
            backgroundView
                .ignoresSafeArea()
            if isCompactHeight {
                padPortraitContainer(
                    ScrollView(.vertical, showsIndicators: false) {
                        mainStack
                            .padding(.bottom, 12)
                    }
                )
            } else {
                padPortraitContainer(mainStack)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            if isPad && !isDisplayOnlyMode {
                forceOrientation(.portrait)
            }
        }
    }

    @ViewBuilder
    private func displayOnlyBody(liveId: String) -> some View {
        displayLandscape(
            ZStack {
                Color.black.ignoresSafeArea()

            if let payload = displayCodePayload {
                CodeDisplayOverlayView(
                    colorName: payload.colorName,
                    code: payload.code,
                    showsCloseButton: true,
                    onClose: {
                        displayCodePayload = nil
                    }
                )
            } else {
                VStack(spacing: 12) {
                    Text("Display Mode")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Waiting for code…")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button("Exit") {
                        exitDisplayOnlyMode()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.85))
                    .padding(.top, 10)
                    .padding(.trailing, 12)
                }
                Spacer()
            }
        }
        )
        .onAppear {
            forceOrientation(.landscapeRight)
            startDisplaySessionListener()
            startListeningToDisplayState()
            startDisplayHeartbeat(liveId: liveId)
        }
        .onDisappear {
            stopDisplayOnlyListeners()
            forceOrientation(.portrait)
        }
    }

    private func startListeningToDisplayState() {
        displayStateListener?.remove()
        displayStateListener = nil

        guard let uid = authManager.user?.uid, !uid.isEmpty else {
            print("⚠️ Display state listener missing uid")
            return
        }

        print("🖥️ Display state listener attaching to users/\(uid)/displayState/current")
        let ref = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("displayState")
            .document("current")

        displayStateListener = ref.addSnapshotListener { snap, err in
            if let err {
                print("❌ Display state listener error:", err.localizedDescription)
                return
            }
            guard let data = snap?.data() else {
                print("🖥️ Display state cleared / missing. raw=nil")
                DispatchQueue.main.async {
                    self.displayCodePayload = nil
                }
                return
            }

            if let colorName = data["colorName"] as? String,
               let code = data["code"] as? String,
               !colorName.isEmpty,
               !code.isEmpty {
                print("🖥️ Display state received color=\(colorName) code=\(code)")
                DispatchQueue.main.async {
                    self.showDisplayCode(colorName: colorName, code: code)
                }
            } else {
                print("🖥️ Display state missing fields raw=\(data)")
                DispatchQueue.main.async {
                    self.displayCodePayload = nil
                }
            }
        }
    }

    private func showDisplayCode(colorName: String, code: String) {
        displayCodePayload = CodeDisplayOverlayPayload(colorName: colorName, code: code)
        displayCodeClearWork?.cancel()
        displayCodeClearWork = nil
    }

    private func startDisplayHeartbeat(liveId: String) {
        stopDisplayHeartbeat()
        // Presence disabled for display-only mode.
    }

    private func stopDisplayHeartbeat() {
        displayHeartbeatTimer?.invalidate()
        displayHeartbeatTimer = nil
    }

    private func stopDisplayOnlyListeners() {
        displayListener?.remove()
        displayListener = nil
        displayStateListener?.remove()
        displayStateListener = nil
        displaySessionListener?.remove()
        displaySessionListener = nil
        displayCodePayload = nil
        displayCodeClearWork?.cancel()
        displayCodeClearWork = nil
        stopDisplayHeartbeat()
    }

    private func enterDisplayOnlyMode(liveId: String) {
        guard subscriptionManager.isPro else {
            showProPaywall = true
            return
        }

        displayOnlyLiveId = liveId
        displayOnlyLiveIdStorage = liveId
        isDisplayOnlyMode = true
        startDisplaySessionListener()
    }

    private func exitDisplayOnlyMode() {
        isDisplayOnlyMode = false
        displayOnlyLiveId = nil
        displayOnlyLiveIdStorage = ""
        stopDisplayOnlyListeners()
        if isPad {
            NotificationCenter.default.post(name: .displayOnlyExitRequested, object: nil)
        }
    }

    private func displayLandscape<Content: View>(_ content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .statusBarHidden(true)
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var effectiveScreenSize: CGSize {
        if isPad && !isDisplayOnlyMode {
            return iPhoneProMaxPortraitSize
        }
        return UIScreen.main.bounds.size
    }

    private func forceOrientation(_ orientation: UIInterfaceOrientation) {
        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        activeWindowRootViewController()?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private func activeWindowRootViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    }

    private let iPhoneProMaxPortraitSize = CGSize(width: 430, height: 932)

    @ViewBuilder
    private func padPortraitContainer<Content: View>(_ content: Content) -> some View {
        if isPad && !isDisplayOnlyMode {
            GeometryReader { proxy in
                let target = iPhoneProMaxPortraitSize
                let scale = min(1, proxy.size.height / target.height)
                content
                    .frame(width: target.width, height: target.height, alignment: .top)
                    .fixedSize()
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: target.width * scale, height: target.height * scale, alignment: .top)
                    .position(
                        x: proxy.size.width / 2,
                        y: (target.height * scale) / 2
                    )
            }
        } else {
            content
        }
    }

    private func startDisplaySessionListener() {
        guard let ref = activeSessionDocRef else { return }
        displaySessionListener?.remove()
        displaySessionListener = nil
        print("🖥️ Display session listener attaching to activeSession")
        displaySessionListener = ref.addSnapshotListener { snap, err in
            if let err {
                print("⚠️ display session listener error:", err.localizedDescription)
                return
            }
            let data = snap?.data() ?? [:]
            let liveId = data["liveId"] as? String
            let mode = data["mode"] as? String ?? "<nil>"
            let claimedDevice = data["deviceId"] as? String
            print("🖥️ Display session update mode=\(mode) liveId=\(liveId ?? "<nil>")")

            if !self.isDisplayOnlyMode {
                if let claimedDevice, !claimedDevice.isEmpty, claimedDevice != self.deviceSessionId {
                    if !self.showSessionConflictAlert {
                        self.dismissAllTopLevelSheets()
                        self.showSessionConflictAlert = true
                    }
                } else if claimedDevice == self.deviceSessionId {
                    if self.showSessionConflictAlert {
                        self.showSessionConflictAlert = false
                    }
                }
            }

            if let liveId, !liveId.isEmpty {
                if self.displayOnlyLiveId != liveId {
                    self.displayOnlyLiveId = liveId
                    self.displayOnlyLiveIdStorage = liveId
                }
            } else {
                self.displayOnlyLiveId = nil
                self.displayOnlyLiveIdStorage = ""
            }
        }
    }

    private func updateActiveSessionLiveId(_ liveId: String?) {
        guard !isDisplayOnlyMode, !showSessionConflictAlert else { return }
        guard let ref = activeSessionDocRef else { return }
        var payload: [String: Any] = [
            "deviceId": deviceSessionId,
            "mode": "primary"
        ]
        if let liveId, !liveId.isEmpty {
            payload["liveId"] = liveId
        } else {
            payload["liveId"] = FieldValue.delete()
        }
        ref.setData(payload, merge: true)
    }

    private func ensureAutoLiveSessionIfNeeded() {
        guard !isDisplayOnlyMode, !showSessionConflictAlert else { return }
        guard isGame, isOwnerForActiveGame else { return }
        guard activeLiveId == nil else { return }
        guard !autoLiveCreateInProgress else { return }
        guard subscriptionManager.isPro else { return }
        guard let gameId = selectedGameId, !gameId.isEmpty else { return }
        if didAutoCreateLiveSessionForGameId == gameId { return }

        autoLiveCreateInProgress = true
        LiveGameService.shared.createLiveGameAndJoinCode(
            ownerGameId: gameId,
            opponent: opponentName ?? "",
            templateId: selectedTemplate?.id.uuidString,
            templateName: selectedTemplate?.name
        ) { result in
            DispatchQueue.main.async {
                self.autoLiveCreateInProgress = false
                switch result {
                case .success(let tuple):
                    self.didAutoCreateLiveSessionForGameId = gameId
                    NotificationCenter.default.post(
                        name: .gameOrSessionChosen,
                        object: nil,
                        userInfo: [
                            "resolved": true,
                            "type": "liveGame",
                            "liveId": tuple.liveId,
                            "ownerUid": self.authManager.user?.uid ?? "",
                            "gameId": gameId,
                            "opponent": self.opponentName ?? "",
                            "templateId": self.selectedTemplate?.id.uuidString ?? "",
                            "templateName": self.selectedTemplate?.name ?? ""
                        ]
                    )
                case .failure(let err):
                    print("❌ Auto live session create failed:", err.localizedDescription)
                }
            }
        }
    }

    private var deviceSessionId: String {
        let key = "deviceSessionId"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    private var activeSessionDocRef: DocumentReference? {
        guard let uid = authManager.user?.uid, !uid.isEmpty else { return nil }
        return Firestore.firestore().collection("users").document(uid).collection("meta").document("activeSession")
    }

    private func ensurePrimarySessionOrPrompt() {
        guard !isDisplayOnlyMode else { return }
        guard authManager.isSignedIn else { return }
        guard !sessionCheckInProgress else { return }
        guard let ref = activeSessionDocRef else { return }

        sessionCheckInProgress = true
        ref.getDocument { snap, err in
            sessionCheckInProgress = false
            if let err {
                print("⚠️ activeSession read failed:", err.localizedDescription)
                return
            }

            let data = snap?.data() ?? [:]
            let existingDevice = data["deviceId"] as? String
            if existingDevice == nil {
                claimPrimarySession()
                return
            }

            if existingDevice == deviceSessionId {
                return
            }

            dismissAllTopLevelSheets()
            showSessionConflictAlert = true
        }
    }

    private func claimPrimarySession() {
        guard let ref = activeSessionDocRef else { return }
        let payload: [String: Any] = [
            "deviceId": deviceSessionId,
            "claimedAt": FieldValue.serverTimestamp(),
            "mode": "primary"
        ]
        ref.setData(payload, merge: true) { err in
            if let err {
                print("⚠️ activeSession claim failed:", err.localizedDescription)
                return
            }
            self.isDisplayOnlyMode = false
            self.displayOnlyLiveId = nil
            self.displayOnlyLiveIdStorage = ""
            self.dismissAllTopLevelSheets()
            self.showSettings = true
        }
    }

    private var displayOnlyHomeView: some View {
        displayLandscape(
            ZStack {
                Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Display Only")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Waiting for codes from the primary device…")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding()

            VStack {
                HStack {
                    Spacer()
                    Button("Exit") {
                        isDisplayOnlyMode = false
                        displayOnlyLiveId = nil
                        displayOnlyLiveIdStorage = ""
                        showSessionConflictAlert = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.85))
                    .padding(.top, 10)
                    .padding(.trailing, 12)
                }
                Spacer()
            }
        }
        )
        .onAppear {
            forceOrientation(.landscapeRight)
            startDisplaySessionListener()
            startListeningToDisplayState()
        }
    }

    @ViewBuilder
    private var accountInUseOverlay: some View {
        if showSessionConflictAlert {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    Text("Account In Use")
                        .font(.headline)
                    let email = authManager.user?.email ?? "this account"
                    Text("2 devices logged into (\(email))")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    Button("Open Display App") {
                        guard let url = URL(string: "pitchmarkdisplay://") else { return }
                        if UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        } else {
                            showDisplayAppMissingAlert = true
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Take Over Primary", role: .destructive) {
                        showSessionConflictAlert = false
                        claimPrimarySession()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(20)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(radius: 20)
                .padding(.horizontal, 24)
            }
            .transition(.opacity)
            .alert("Display App Not Installed", isPresented: $showDisplayAppMissingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Install and open Pitchmark Display to use this option.")
            }
        }
    }
    
    private func handleInitialAppear() {
        // If we aren't signed in yet, do NOT mark anything as presented.
        // We'll be called again when sign-in completes.
        guard authManager.isSignedIn else {
            print("⏳ handleInitialAppear: not signed in yet — deferring boot flow")
            startupPhase = .ready
            return
        }

        startDisplaySessionListener()
        ensurePrimarySessionOrPrompt()
        if showSessionConflictAlert {
            return
        }

        if shouldForceSettingsOnLaunch() {
            showSettings = true
        }

        if isDisplayOnlyMode, !displayOnlyLiveIdStorage.isEmpty {
            displayOnlyLiveId = displayOnlyLiveIdStorage
            startupPhase = .ready
            return
        }

        loadBufferedSharedPitcherEvents()

        // If we've already presented the initial sheets once, don't do it again.
        // (But we can still refresh loaders below if you want; keeping it tight here.)
        if hasPresentedInitialSettings {
            // Still ensure we have data if somehow empty
            if templates.isEmpty {
                authManager.loadTemplates { loaded in
                    self.templates = loaded
                    if self.selectedTemplate == nil { self.selectedTemplate = loaded.first }
                }
            }
            if games.isEmpty {
                authManager.loadGames { loaded in
                    self.games = self.mergeLoadedGamesPreservingProgress(loaded)
                }
            }
            return
        }

        startupPhase = .launching

        let defaults = UserDefaults.standard
        let lastViewPref = defaults.string(forKey: DefaultsKeys.lastView)

        let persistedGameId = defaults.string(forKey: DefaultsKeys.activeGameId)
        let persistedOwnerId = defaults.string(forKey: DefaultsKeys.activeGameOwnerUserId)
        let persistedIsPractice = defaults.bool(forKey: DefaultsKeys.activeIsPractice)
        // ✅ Restore LIVE session if one was active
        var didRestoreLiveSession = false
        if let persistedLiveId = defaults.string(forKey: "activeLiveId"),
           !persistedLiveId.isEmpty {

            didRestoreLiveSession = true
            print("🔁 Restoring live session:", persistedLiveId)

            self.activeLiveId = persistedLiveId
            self.updateActiveSessionLiveId(persistedLiveId)
            self.startLivePresenceHeartbeat(liveId: persistedLiveId)
            self.ensureLivePresence(liveId: persistedLiveId)
            self.seedLivePitchEventsOnce(liveId: persistedLiveId)

            self.isGame = true
            self.sessionManager.switchMode(to: .game)
            // ✅ Show the last known opponent immediately while live doc loads
            if let cachedOpp = defaults.string(forKey: "activeOpponentName"), !cachedOpp.isEmpty {
                self.opponentName = cachedOpp
            }

            DispatchQueue.main.async {
                self.startListeningToLiveGame(liveId: persistedLiveId)
                self.startListeningToLivePitchEvents(liveId: persistedLiveId)
            }
        }


        self.activeGameOwnerUserId = persistedOwnerId

        // Mark as presented NOW that we know we're signed in
        hasPresentedInitialSettings = true

        // -----------------------------------------
        // Decide initial mode WITHOUT loading games
        // -----------------------------------------

        if lastViewPref == "settings" {
            defaults.set("settings", forKey: DefaultsKeys.lastView)

            // We'll present settings after startupPhase becomes .ready (below)
            // so this doesn't race other boot steps.

        } else if persistedIsPractice {
            isGame = false
            sessionManager.switchMode(to: .practice)
            restoreActivePracticeSelection()
            loadPracticePitchEventsIfNeeded(force: true)

        } else if let gid = persistedGameId {
            isGame = true
            sessionManager.switchMode(to: .game)

            selectedGameId = gid
            activeGameOwnerUserId = persistedOwnerId ?? authManager.user?.uid

            // Defer hydration until loadGames returns
            pendingRestoreGameId = gid
        }

        // -----------------------------------------
        // Normal loaders (run exactly once)
        // -----------------------------------------

        authManager.loadTemplates { loadedTemplates in
            print("✅ Loaded templates:", loadedTemplates.count)
            self.templates = loadedTemplates
            if self.selectedTemplate == nil {
                self.selectedTemplate = self.visibleTemplates.first ?? loadedTemplates.first
            } else if let current = self.selectedTemplate,
                      self.hiddenTemplateIdSet.contains(current.id.uuidString) {
                self.selectedTemplate = self.visibleTemplates.first ?? loadedTemplates.first
            }
            if self.pendingGameConfirmation != nil {
                let hasMatch = self.pendingConfirmationTemplateId.flatMap { id in
                    loadedTemplates.first(where: { $0.id == id })
                } != nil
                if self.pendingConfirmationTemplateId == nil || !hasMatch {
                    let fallback = self.visibleTemplates.first ?? loadedTemplates.first
                    self.pendingConfirmationTemplateId = fallback?.id
                }
            }
            self.applyPendingLiveTemplateIfPossible()
            if let gameId = self.selectedGameId {
                self.applyStoredSelections(for: gameId)
            }
            self.ensureAutoLiveSessionIfNeeded()
        }

        authManager.loadGames { loadedGames in
            self.games = self.mergeLoadedGamesPreservingProgress(loadedGames)

            // Apply deferred restore (if needed)
            if let gid = self.pendingRestoreGameId,
               let game = loadedGames.first(where: { $0.id == gid }) {

                print("🔁 Applying deferred restore for game:", gid)

                self.opponentName = game.opponent

                if let ids = game.batterIds, ids.count == game.jerseyNumbers.count {
                    self.jerseyCells = zip(ids, game.jerseyNumbers).map { (idStr, num) in
                        JerseyCell(id: UUID(uuidString: idStr) ?? UUID(), jerseyNumber: num)
                    }
                } else {
                    self.jerseyCells = game.jerseyNumbers.map { JerseyCell(jerseyNumber: $0) }
                }

                self.pendingRestoreGameId = nil
                self.ensureAutoLiveSessionIfNeeded()
            }
        }

        authManager.loadPitchers { loadedPitchers in
            self.pitchers = loadedPitchers

            let defaults = UserDefaults.standard
            let persistedPitcherId = defaults.string(forKey: DefaultsKeys.lastPitcherId)

            if let pid = persistedPitcherId,
               let pitcher = loadedPitchers.first(where: { $0.id == pid }) {
                self.applySelectedPitcher(pitcher)
            } else if let first = loadedPitchers.first {
                self.applySelectedPitcher(first)
            }

            if let gameId = self.selectedGameId {
                self.applyStoredSelections(for: gameId)
            }
        }

        // -----------------------------------------
        // Startup complete + initial sheet
        // -----------------------------------------

        DispatchQueue.main.async {
            self.startupPhase = .ready

            // If we restored a live session, do NOT present any initial chooser sheets.
            if didRestoreLiveSession {
                return
            }

            // Present settings if that was the last view preference
            if lastViewPref == "settings" {
                self.presentExclusive(settings: true)
            } else {
                // If no active restored session, show the normal chooser sheet
                if !persistedIsPractice && persistedGameId == nil {
                    self.presentInitialSheetIfNeeded()
                }
            }
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
                    .frame(height: effectiveScreenSize.height * 0.33)
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
    
    @ViewBuilder private var gameSheetView: some View {
        GameSelectionSheet(
            onCreate: { name, date in
                let newGame = Game(
                    id: nil,
                    opponent: name,
                    date: date,
                    jerseyNumbers: jerseyCells.map { $0.jerseyNumber },
                    batterIds: jerseyCells.map { $0.id.uuidString }
                )
                authManager.saveGame(newGame)
            },
            onChoose: { gameId in
                let ownerUid = authManager.user?.uid ?? ""

                requestGameConfirmation(gameId: gameId, ownerUid: ownerUid)
                showGameSheet = false
            },

            onCancel: {
                showGameSheet = false
            },
            codeShareInitialTab: $codeShareInitialTab,
            showCodeShareSheet: $showCodeShareSheet,
            shareCode: $shareCode,
            codeShareSheetID: $codeShareSheetID,
            showCodeShareModePicker: $showCodeShareModePicker,
            // ✅ these must be last because your init expects it
            games: $games,
        )
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder private var codeShareSheetView: some View {
        CodeShareSheet(
            initialCode: shareCode,
            initialTab: codeShareInitialTab,
            hostUid: authManager.user?.uid,
            gameId: selectedGameId,
            opponent: opponentName,
            isGame: isGame,
            templateId: selectedTemplate?.id.uuidString,
            templateName: selectedTemplate?.name
        ) { code in
            consumeShareCode(code)
        }
        .id(codeShareSheetID)
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder private var inviteJoinSheetView: some View {
        VStack(spacing: 16) {
            Text("Join a Live Game")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Invite Link")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Paste invite link", text: $inviteJoinText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

            }

            if let error = inviteJoinError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Scan QR Code") {
                openCameraForJoin()
            }
            .buttonStyle(.bordered)

            Button(isJoiningSession ? "Joining..." : "Join") {
                if !subscriptionManager.isPro {
                    proGateMessage = "Joining games requires PitchMark Pro."
                    showProGateAlert = true
                    return
                }
                joinLiveGameFromInvite()
            }
            .buttonStyle(.borderedProminent)
            .disabled(inviteJoinText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoiningSession)
        }
        .padding()
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder private var practiceSheetView: some View {
        PracticeSelectionSheet(
            onCreate: { name, date, templateId, templateName in
                var sessions = loadPracticeSessions()
                let new = PracticeSession(
                    id: UUID().uuidString,
                    name: name,
                    date: date,
                    templateId: templateId,
                    templateName: templateName
                )
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
                    let defaults = UserDefaults.standard
                    defaults.set(true, forKey: DefaultsKeys.activeIsPractice)
                    defaults.removeObject(forKey: DefaultsKeys.activeGameId)
                    persistActivePracticeId(session.id)
                    defaults.set("tracker", forKey: DefaultsKeys.lastView)
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

    @ViewBuilder private var pitchResultSheetView: some View {
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
            selectedPitcherId: effectivePitcherIdForSave,
            saveAction: { event in
                persistPitchEvent(event)
            },
            template: selectedTemplate,
            pitcherName: pitchers.first(where: { $0.id == selectedPitcherId })?.name
        )
    }

    @ViewBuilder private var codeAssignmentSheetView: some View {
        CodeAssignmentSettingsView(
            selectedPitch: $selectedPitch,
            selectedLocation: $selectedLocation,
            pitchCodeAssignments: $pitchCodeAssignments,
            allPitches: allPitches,
            allLocations: allLocationsFromGrid()
        )
        .padding()
    }

    @ViewBuilder private var settingsSheetView: some View {
        SettingsView(
              templates: $templates,
              games: $games,
              pitchers: $pitchers,
              allPitches: allPitches,
              selectedTemplate: $selectedTemplate,
              codeShareInitialTab: $codeShareInitialTab,
              showCodeShareSheet: $showCodeShareSheet,
              shareCode: $shareCode,
              codeShareSheetID: $codeShareSheetID,
              showCodeShareModePicker: $showCodeShareModePicker
          )
        .environmentObject(authManager)
        .environmentObject(subscriptionManager)
    }

    @ViewBuilder private var gameStatsSheetView: some View {
        if let pitcher = selectedPitcherForStats,
           let game = currentGame,
           let gameId = game.id {
            PitcherStatsSheetView(
                pitcher: pitcher,
                games: [game],
                lockToGameId: gameId,
                liveId: activeLiveId
            )
            .environmentObject(authManager)
        } else {
            VStack(spacing: 12) {
                Text("Stats unavailable")
                    .font(.headline)
                Text("Select a game and pitcher to view stats.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }

    private func pauseLiveSessionForBackground() {
        guard activeLiveId != nil else { return }
        print("🔌 Scene inactive/background → pausing live presence (no disconnect)")
        stopHeartbeat()
        liveListener?.remove()
        liveListener = nil
        livePitchEventsListener?.remove()
        livePitchEventsListener = nil
        participantsListener?.remove()
        participantsListener = nil
        uiConnected = false
        flushBufferedSharedPitcherEvents(reason: "background")
    }

    private func resumeLiveSessionIfNeeded() {
        guard let liveId = activeLiveId, !liveId.isEmpty else { return }
        print("🔌 Scene active → resuming live presence")
        startListeningToActiveGame()
        startListeningToLivePitchEvents(liveId: liveId)
        startListeningToLiveParticipants(liveId: liveId)
        startLivePresenceHeartbeat(liveId: liveId)
        ensureLivePresence(liveId: liveId)
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            ensurePrimarySessionOrPrompt()
            resumeLiveSessionIfNeeded()
            evaluateIdleAndMaybeShowSettings()
            clearForceSettingsFlagOnResume()
        case .inactive, .background:
            markBackgroundTimestamp()
            flushBufferedSharedPitcherEvents(reason: "background")
            pauseLiveSessionForBackground()
        @unknown default:
            break
        }
    }

    private func markBackgroundTimestamp() {
        let defaults = UserDefaults.standard
        defaults.set(Date().timeIntervalSince1970, forKey: DefaultsKeys.lastBackgroundAt)
        defaults.set(true, forKey: DefaultsKeys.forceSettingsOnNextLaunch)
    }

    private func clearForceSettingsFlagOnResume() {
        UserDefaults.standard.set(false, forKey: DefaultsKeys.forceSettingsOnNextLaunch)
    }

    private func shouldForceSettingsOnLaunch() -> Bool {
        let defaults = UserDefaults.standard
        let lastBackgroundAt = defaults.double(forKey: DefaultsKeys.lastBackgroundAt)
        let forceFlag = defaults.bool(forKey: DefaultsKeys.forceSettingsOnNextLaunch)
        if forceFlag {
            defaults.set(false, forKey: DefaultsKeys.forceSettingsOnNextLaunch)
            return true
        }
        if lastBackgroundAt > 0 {
            let idleSeconds = Date().timeIntervalSince1970 - lastBackgroundAt
            return idleSeconds >= 15 * 60
        }
        return false
    }

    private func evaluateIdleAndMaybeShowSettings() {
        let defaults = UserDefaults.standard
        let lastBackgroundAt = defaults.double(forKey: DefaultsKeys.lastBackgroundAt)
        guard lastBackgroundAt > 0 else { return }
        let idleSeconds = Date().timeIntervalSince1970 - lastBackgroundAt
        if idleSeconds >= 15 * 60 {
            showSettings = true
        }
    }

    var body: some View {
        let resolvedDisplayLiveId = displayOnlyLiveId ?? (displayOnlyLiveIdStorage.isEmpty ? nil : displayOnlyLiveIdStorage)
        let displayCoverBinding = Binding<Bool>(
            get: { isDisplayOnlyMode && !isPad },
            set: { newValue in if !newValue { exitDisplayOnlyMode() } }
        )
        let displayCoverView: AnyView = {
            if let liveId = resolvedDisplayLiveId {
                return AnyView(displayOnlyBody(liveId: liveId))
            }
            return AnyView(displayOnlyHomeView)
        }()

        let synced = baseBody.withGameSync(
            start: {
                startListeningToActiveGame()
                if let liveId = activeLiveId, !liveId.isEmpty {
                    startListeningToLivePitchEvents(liveId: liveId)
                } else {
                    startListeningToGamePitchEvents()
                }
            },
            stop: {
                gameListener?.remove()
                gameListener = nil
                livePitchEventsListener?.remove()
                livePitchEventsListener = nil
                gamePitchEventsListener?.remove()
                gamePitchEventsListener = nil
            },
            gameId: selectedGameId,
            ownerId: activeGameOwnerUserId,
            isGame: isGame
        )

        let v0 = synced.eraseToAnyView()

        let v1 = v0
            .onChange(of: scenePhase) { _, newValue in
                handleScenePhaseChange(newValue)
            }
            .onChange(of: pendingResultLabel) { _, newValue in
                handlePendingResultChange(newValue)
            }
            .onChange(of: selectedTemplate?.id) { _, newValue in
                guard !isRestoringState else { return }
                guard let newValue else {
                    persistSelectedTemplate(nil)
                    return
                }
                if lastAppliedTemplateId != newValue,
                   let template = templates.first(where: { $0.id == newValue }) {
                    applyTemplate(template, source: .user)
                }
            }
            .onChange(of: selectedPitches) { _, newValue in
                if let template = selectedTemplate {
                    persistActivePitches(for: template.id, active: newValue)
                }
            }
            .onChange(of: selectedPitcherId) { _, _ in
                if isGame {
                    syncLivePitcherSelectionIfOwner()
                }
            }
            .onChange(of: sessionManager.currentMode) { _, newValue in
                if newValue == .practice {
                    loadPracticePitchEventsIfNeeded(force: false)
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
            .onChange(of: overlayTab) { _, newValue in
                if newValue == .progress && sessionManager.currentMode == .practice {
                    progressRefreshToken = UUID()
                }
            }
            .onChange(of: isDisplayOnlyMode) { _, newValue in
                forceOrientation(newValue ? .landscapeRight : .portrait)
                if isPad && newValue {
                    NotificationCenter.default.post(name: .displayOnlyPresentRequested, object: nil)
                }
            }
            .eraseToAnyView()

        let v2 = v1
            .sheet(isPresented: $showGameSheet, onDismiss: {
                refreshGamesList()
                guard !isJoiningSession else { return }

                // ✅ Only force practice if there is no game selected
                if sessionManager.currentMode == .game && selectedGameId == nil {
                    sessionManager.switchMode(to: .practice)
                    isGame = false
                }
            }) { gameSheetView }
            .eraseToAnyView()


        let v3 = v2
            .sheet(isPresented: $showCodeShareSheet) { codeShareSheetView }
            .eraseToAnyView()

        let v4 = v3
            .sheet(isPresented: $showInviteJoinSheet) { inviteJoinSheetView }
            .sheet(isPresented: $showProPaywall) {
                ProPaywallView(
                    title: "PitchMark Pro",
                    message: "Connect participants, unlock full grid keys, and use the display app with PitchMark Pro.",
                    allowsClose: true
                )
            }
            .fullScreenCover(isPresented: $showQRScanner) {
                QRScannerView { scanned in
                    inviteJoinText = scanned
                    inviteJoinError = nil
                    showQRScanner = false
                    joinLiveGameFromInvite()
                } onCancel: {
                    showQRScanner = false
                }
            }
            .alert("Camera Unavailable", isPresented: $showCameraUnavailableAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("This device doesn’t have a camera available.")
            }
            .alert("Camera Access Needed", isPresented: $showCameraPermissionAlert) {
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enable Camera access in Settings to scan the owner’s QR code.")
            }
            .eraseToAnyView()

        let v4b = v4
            .eraseToAnyView()

        let v5 = v4b
            .sheet(isPresented: $showPracticeSheet, onDismiss: {
                refreshGamesList()
                if sessionManager.currentMode == .practice && practiceName == nil && selectedPracticeId == nil {
                    // no-op (your current behavior)
                }
            }) { practiceSheetView }
            .eraseToAnyView()

        let v6 = v5
            .sheet(isPresented: confirmSheetBinding) { pitchResultSheetView }
            .eraseToAnyView()

        let v7 = v6
            .sheet(isPresented: $showCodeAssignmentSheet) { codeAssignmentSheetView }
            .eraseToAnyView()

        let v8 = v7
            .sheet(isPresented: $showSettings) { settingsSheetView }
            .eraseToAnyView()

        let v9 = v8
            .sheet(isPresented: $showGameStatsSheet) { gameStatsSheetView }
            .eraseToAnyView()

        // Keep alerts + the rest of your observers, then erase one last time
        return AnyView(v9
            .allowsHitTesting(!showSessionConflictAlert)
            .alert("Upgrade to Pro", isPresented: $showProGateAlert) {
                Button("Not Now", role: .cancel) { }
                Button("Upgrade") {
                    showProPaywall = true
                }
            } message: {
                Text(proGateMessage)
            }
            .alert("Select a game first", isPresented: $showSelectGameFirstAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Create or choose a game before generating a partner code.")
            }
            .alert("Code Link", isPresented: $showCodeShareErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(codeShareErrorMessage)
            }
            .fullScreenCover(isPresented: displayCoverBinding) {
                displayCoverView
            }
            .sheet(item: $pendingGameConfirmation) { item in
                sessionConfirmationSheet(pending: item)
            }
            .overlay { accountInUseOverlay }
            .onAppear {
                handleInitialAppear()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background || newPhase == .inactive {
                    flushProgressToGameIfOwner()
                }
            }
            .onChange(of: authManager.isSignedIn) { _, newValue in
                if newValue {
                    // ✅ If sign-in/restore completes AFTER first appear,
                    // rerun the boot flow so games/templates load and initial sheets can present.
                    handleInitialAppear()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pitcherSharedUpdated)) { _ in
                authManager.loadPitchers { loaded in
                    self.pitchers = loaded
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .displayOnlyExitRequested)) { _ in
                if isDisplayOnlyMode {
                    exitDisplayOnlyMode()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .gameOrSessionChosen)) { note in
                guard let info = note.userInfo as? [String: Any] else { return }

                if let type = info["type"] as? String, type == "display" {
                    guard let liveId = info["liveId"] as? String else { return }
                    enterDisplayOnlyMode(liveId: liveId)
                    return
                }

                if let type = info["type"] as? String, type == "game" {
                    guard let gameId = info["gameId"] as? String else { return }
                    let ownerUid = (info["ownerUserId"] as? String) ?? (authManager.user?.uid ?? "")
                    requestGameConfirmation(gameId: gameId, ownerUid: ownerUid)
                    return
                }

                if let type = info["type"] as? String, type == "practice" {
                    let practiceId = (info["practiceId"] as? String) ?? "__GENERAL__"
                    let practiceName = info["practiceName"] as? String
                    requestPracticeConfirmation(practiceId: practiceId, practiceName: practiceName)
                    return
                }

                if let type = info["type"] as? String, type == "liveGame" {
                    guard let liveId = info["liveId"] as? String else { return }

                    // 🔴 Clear any stale practice/game UI state before switching
                    self.resetCallAndResultUIState()
                    self.resetLiveTemplateOverrideLock()
                    self.gamePitchEvents.removeAll()
                    self.seededGamePitchEventsForLive.removeAll()
                    self.didSeedOwnerGameEventsForLive = false
                    self.didSeedLivePitchEventsFromOwnerGame = false

                    // ✅ Set in-memory live session id FIRST (this is what your writes check)
                    self.activeLiveId = liveId
                    self.updateActiveSessionLiveId(liveId)
                    self.startLivePresenceHeartbeat(liveId: liveId)
                    self.ensureLivePresence(liveId: liveId)
                    self.seedLivePitchEventsOnce(liveId: liveId)

                    if let deferred = self.deferredPendingPitch {
                        do {
                            let pendingData = try Firestore.Encoder().encode(deferred)
                            LiveGameService.shared.updateLiveFields(liveId: liveId, fields: [
                                "pending": pendingData,
                                "displayCode": FieldValue.delete()
                            ]) { err in
                                if let err { print("❌ deferred pending update error:", err.localizedDescription) }
                            }
                            self.deferredPendingPitch = nil
                        } catch {
                            print("❌ encode deferred pending failed:", error)
                        }
                    }

                    if let deferred = self.deferredDisplayCode {
                        LiveGameService.shared.updateLiveFields(liveId: liveId, fields: [
                            "displayCode": [
                                "colorName": deferred.colorName,
                                "code": deferred.code,
                                "updatedAt": FieldValue.serverTimestamp()
                            ]
                        ]) { err in
                            if let err { print("❌ deferred displayCode update error:", err.localizedDescription) }
                        }
                        self.deferredDisplayCode = nil
                    }

                    // (Optional but recommended) If the notification includes ownerUid, set it
                    if let ownerUid = info["ownerUid"] as? String, !ownerUid.isEmpty {
                        self.activeGameOwnerUserId = ownerUid
                    }

                    // Persist
                    let defaults = UserDefaults.standard
                    defaults.set(liveId, forKey: "activeLiveId")
                    defaults.set(false, forKey: "activeIsPractice")
                    defaults.set("tracker", forKey: DefaultsKeys.lastView)

                    if let gid = info["gameId"] as? String, !gid.isEmpty {
                        self.selectedGameId = gid
                        defaults.set(gid, forKey: DefaultsKeys.activeGameId)

                        let ownerUid = (info["ownerUid"] as? String) ?? (self.authManager.user?.uid ?? "")
                        if !ownerUid.isEmpty {
                            self.activeGameOwnerUserId = ownerUid
                            defaults.set(ownerUid, forKey: DefaultsKeys.activeGameOwnerUserId)
                            self.hydrateChosenGameUI(ownerUid: ownerUid, gameId: gid)
                            self.startListeningToActiveGame()
                        }
                    }

                    self.pendingLiveTemplateId = info["templateId"] as? String
                    self.pendingLiveTemplateName = info["templateName"] as? String
                    self.applyPendingLiveTemplateIfPossible()

                    // ✅ Persist opponent label if provided
                    if let opp = info["opponent"] as? String, !opp.isEmpty {
                        self.opponentName = opp
                        defaults.set(opp, forKey: "activeOpponentName")
                    }

                    // ✅ Force GAME mode (order matters)
                    self.suppressNextGameSheet = true
                    self.isGame = true
                    self.sessionManager.switchMode(to: .game)

                    // ✅ Start listeners
                        self.startListeningToLiveGame(liveId: liveId)
                        self.startListeningToLivePitchEvents(liveId: liveId)

                        // Ensure owner also listens to their /users/{owner}/games/{gid}/pitchEvents
                        if self.isOwnerForActiveGame {
                            self.startListeningToGamePitchEvents()
                        }

                        return
                }


                // ✅ Handle "choose game" (Launch → Select Game flow)
                if let type = info["type"] as? String, type == "game" {
                    guard let gid = info["gameId"] as? String else { return }

                    let owner = (info["ownerUserId"] as? String) ?? authManager.user?.uid
                    let ownerUid = owner ?? (authManager.user?.uid ?? "")
                    guard !ownerUid.isEmpty else { return }

                    print("✅ Resolver received game:", gid, "owner:", ownerUid)
                    self.resetCallAndResultUIState()
                    self.requestGameConfirmation(gameId: gid, ownerUid: ownerUid)

                    return

                }
            }
            .eraseToAnyView()
        )
    }
    
    struct OwnerCalledPitchRecordContainer: View {
        @EnvironmentObject var authManager: AuthManager
        @EnvironmentObject var sessionManager: PitchSessionManager

        // Live events that drive PitchResultSheet
        @State private var gameEvents: [PitchEvent] = []

        // Keep a listener handle to detach on change/disappear
        @State private var pitchEventsListener: ListenerRegistration? = nil

        // Optional: if you show the selected selection in your UI
        @State private var selectedOwnerUid: String = ""
        @State private var selectedGameId: String = ""

        // If you already have these in a parent, pass them in instead
        @State private var games: [Game] = []
        @State private var templates: [PitchTemplate] = []
        @State private var pitchers: [Pitcher] = []

        var body: some View {
            PitchResultSheet(
                allEvents: gameEvents,   // <- live-updating array
                games: games,
                templates: templates,
                pitchers: pitchers,
                isParticipant: false,
                selectedPlayerName: "Pitcher"
            )
            .onReceive(NotificationCenter.default.publisher(for: .gameOrSessionChosen)) { note in
                guard
                    let info = note.userInfo as? [String: Any],
                    let type = info["type"] as? String
                else { return }

                if type == "game" {
                    guard let gameId = info["gameId"] as? String else { return }
                    let ownerUid = (info["ownerUserId"] as? String) ?? (authManager.user?.uid ?? "")

                    selectedOwnerUid = ownerUid
                    selectedGameId = gameId

                    // Attach listener to the owner’s game path
                    attachGameListener(ownerUid: ownerUid, gameId: gameId)

                    // Ensure PitchResultSheet filters as game
                    sessionManager.switchMode(to: .game)
                } else if type == "practice" {
                    // Optional: If you want live practice updates, attach a per-user listener
                    authManager.stopListening(pitchEventsListener)
                    pitchEventsListener = authManager.listenUserPitchEvents(userId: authManager.user?.uid ?? "") { events in
                        // PitchResultSheet will filter to the active practiceId via sessionManager
                        self.gameEvents = events
                    }
                    sessionManager.switchMode(to: .practice)
                }
            }
            .onAppear {
                // Optional: If you persist a last-selected game, re-attach here
                // attachGameListener(ownerUid: <owner>, gameId: <gameId>)

                // Optional: fetch games/templates locally if you’re not already passing them down
                // authManager.loadGames { self.games = $0 }
                // authManager.loadTemplates { self.templates = $0 }
                authManager.loadPitchers { loaded in
                    self.pitchers = loaded
                }
            }
            .onDisappear {
                authManager.stopListening(pitchEventsListener)
                pitchEventsListener = nil
            }
        }

        private func attachGameListener(ownerUid: String, gameId: String) {
            // Detach any previous listener before attaching
            authManager.stopListening(pitchEventsListener)
            pitchEventsListener = nil

            pitchEventsListener = authManager.listenGamePitchEvents(ownerUserId: ownerUid, gameId: gameId) { events in
                // Already ordered by timestamp ascending
                self.gameEvents = events
            }
        }
    }
}

private struct ProgressGameView: View {
    let ownerUserId: String?
    @Binding var balls: Int
    @Binding var strikes: Int
    @Binding var inning: Int
    @Binding var hits: Int
    @Binding var walks: Int
    @Binding var us: Int
    @Binding var them: Int
    @Binding var selectedGameId: String?
    let onProgressChange: () -> Void

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
                onProgressChange()
            }
        }

        .onChange(of: strikeToggles) { _, newValue in
            let newCount = newValue.filter { $0 }.count
            if strikes != newCount {
                strikes = newCount
                onProgressChange()
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
            guard let owner = ownerUserId, !owner.isEmpty else { return }

            authManager.loadGame(ownerUserId: owner, gameId: gid) { game in
                guard let game else { return }

                let newBalls = max(0, min(3, game.balls))
                let newStrikes = max(0, min(2, game.strikes))

                balls = newBalls
                strikes = newStrikes

                ballToggles = (0..<3).map { $0 < newBalls }
                strikeToggles = (0..<2).map { $0 < newStrikes }
            }
        }
    }

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
            guard ev.calledPitch != nil else { continue }
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
            print("[Metrics] Ranking consider id=\(ev.id ?? "-") pitch=\(ev.pitch) hasCall=\(ev.calledPitch != nil) didHit=\(didHitLocation(ev))")
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
        let payload = items.map { ["id": $0.id.uuidString, "num": $0.jerseyNumber] }
        NotificationCenter.default.post(name: .jerseyOrderChanged, object: payload)

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
    let effectiveGameOwnerUserId: String?
    let activeLiveId: String?
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
                syncSelection(selectedBatterId == cell.id ? nil : cell.id)
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
                                NotificationCenter.default.post(
                                    name: .jerseyOrderChanged,
                                    object: jerseyCells.map { $0.jerseyNumber }
                                )
                                let jerseys = jerseyCells.map { $0.jerseyNumber }
                                let batterIds = jerseyCells.map { $0.id.uuidString }

                                if let liveId = activeLiveId, !liveId.isEmpty {
                                    LiveGameService.shared.updateLiveFields(liveId: liveId, fields: [
                                        "jerseyNumbers": jerseys,
                                        "batterIds": batterIds
                                    ])
                                    if let owner = effectiveGameOwnerUserId,
                                       let gameId = selectedGameId,
                                       let myUid = authManager.user?.uid,
                                       !owner.isEmpty,
                                       owner == myUid {
                                        authManager.updateGameLineup(
                                            ownerUserId: owner,
                                            gameId: gameId,
                                            jerseyNumbers: jerseys,
                                            batterIds: batterIds
                                        )
                                    }
                                }

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
                                NotificationCenter.default.post(
                                    name: .jerseyOrderChanged,
                                    object: jerseyCells.map { $0.jerseyNumber }
                                )
                                let jerseys = jerseyCells.map { $0.jerseyNumber }
                                let batterIds = jerseyCells.map { $0.id.uuidString }

                                if let liveId = activeLiveId, !liveId.isEmpty {
                                    LiveGameService.shared.updateLiveFields(liveId: liveId, fields: [
                                        "jerseyNumbers": jerseys,
                                        "batterIds": batterIds
                                    ])
                                    if let owner = effectiveGameOwnerUserId,
                                       let gameId = selectedGameId,
                                       let myUid = authManager.user?.uid,
                                       !owner.isEmpty,
                                       owner == myUid {
                                        authManager.updateGameLineup(
                                            ownerUserId: owner,
                                            gameId: gameId,
                                            jerseyNumbers: jerseys,
                                            batterIds: batterIds
                                        )
                                    }
                                }

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
                        guard let idx = jerseyCells.firstIndex(where: { $0.id == cell.id }) else {
                            showActionsSheet = false
                            return
                        }

                        // 1) Update local UI immediately
                        let removedId = jerseyCells[idx].id
                        jerseyCells.remove(at: idx)

                        if selectedBatterId == removedId {
                            selectedBatterId = nil
                            pitchesFacedBatterId = nil
                        }

                        // 2) Persist lineup so BOTH devices update
                        let jerseys = jerseyCells.map { $0.jerseyNumber }
                        let batterIds = jerseyCells.map { $0.id.uuidString }

                        if let liveId = activeLiveId, !liveId.isEmpty {
                            // LIVE: write to liveGames (two-way)
                            LiveGameService.shared.updateLiveFields(
                                liveId: liveId,
                                fields: [
                                    "jerseyNumbers": jerseys,
                                    "batterIds": batterIds
                                ]
                            )
                            if let owner = effectiveGameOwnerUserId,
                               let gameId = selectedGameId,
                               let myUid = authManager.user?.uid,
                               !owner.isEmpty,
                               owner == myUid {
                                authManager.updateGameLineup(
                                    ownerUserId: owner,
                                    gameId: gameId,
                                    jerseyNumbers: jerseys,
                                    batterIds: batterIds
                                )
                            }

                            // Optional: if you also want to clear live selected batter when deleted
                            // (only needed if you store selectedBatterId on live doc)
                            // LiveGameService.shared.updateLiveFields(liveId: liveId, fields: [
                            //     "selectedBatterId": FieldValue.delete(),
                            //     "selectedBatterJersey": FieldValue.delete()
                            // ])
                        } else if let gameId = selectedGameId,
                                  let owner = effectiveGameOwnerUserId,
                                  !owner.isEmpty {
                            // NON-LIVE: update owner's game doc
                            authManager.updateGameLineup(
                                ownerUserId: owner,
                                gameId: gameId,
                                jerseyNumbers: jerseys,
                                batterIds: batterIds
                            )
                        } else {
                            print("⚠️ Cannot persist delete: missing activeLiveId (live) or selectedGameId/effectiveGameOwnerUserId (non-live)")
                        }

                        showActionsSheet = false
                    }

                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will remove this batter from the lineup.")
                }
            }
    }
    private func syncSelection(_ nextSelection: UUID?) {
        // ✅ optimistic UI
        selectedBatterId = nextSelection

        // ✅ LIVE MODE: write to liveGames so both devices reflect selection
        if let liveId = activeLiveId, !liveId.isEmpty {
            var fields: [String: Any] = [:]
            if let nextSelection {
                fields["selectedBatterId"] = nextSelection.uuidString
                fields["selectedBatterJersey"] = cell.jerseyNumber
            } else {
                fields["selectedBatterId"] = FieldValue.delete()
                fields["selectedBatterJersey"] = FieldValue.delete()
            }
            LiveGameService.shared.updateLiveFields(liveId: liveId, fields: fields)
            return
        }

        // ✅ NON-LIVE: write to owner's game doc as before
        guard
            let gameId = selectedGameId,
            let owner = effectiveGameOwnerUserId,
            !owner.isEmpty
        else {
            print("⚠️ Cannot sync selected batter: missing selectedGameId or effectiveGameOwnerUserId")
            return
        }

        authManager.updateGameSelectedBatter(
            ownerUserId: owner,
            gameId: gameId,
            selectedBatterId: nextSelection?.uuidString,
            selectedBatterJersey: nextSelection == nil ? nil : cell.jerseyNumber
        )
    }


    private func selectJersey(_ cell: JerseyCell) {
        // ✅ Optimistic UI
        selectedBatterId = cell.id

        guard let gid = selectedGameId,
              let owner = effectiveGameOwnerUserId,
              !owner.isEmpty
        else {
            print("⚠️ selectJersey: missing gameId/owner")
            return
        }

        // ✅ Write to the OWNER's game doc so both devices share the same selection
        Firestore.firestore()
            .collection("users").document(owner)
            .collection("games").document(gid)
            .setData([
                "selectedBatterId": cell.id.uuidString,
                "selectedBatterJersey": cell.jerseyNumber
            ], merge: true)
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
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
        }
        .accessibilityLabel("Reset pitch selection")
    }
}

struct CodeOrderToggle: View {
    @Binding var pitchFirst: Bool
    let template: PitchTemplate?
    let selectedCode: String?
    let onColorTap: (String) -> Void

    private var activeColorNames: [String] {
        guard let template else { return [] }
        return pitchFirst
            ? Array(template.pitchFirstColors.prefix(2))
            : Array(template.locationFirstColors.prefix(3))
    }

    private var canShowOverlay: Bool {
        guard let selectedCode else { return false }
        return !selectedCode.isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            if !activeColorNames.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        ForEach(Array(activeColorNames.enumerated()), id: \.offset) { item in
                            let name = item.element
                            Button {
                                onColorTap(name)
                            } label: {
                                Circle()
                                    .fill(templatePaletteColor(name))
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.black, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(!canShowOverlay)
                            .opacity(canShowOverlay ? 1 : 0.5)
                        }
                    }

                    Text("Tap to show")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            else {
                Color.clear
                    .frame(width: 1, height: 36)
            }

            Spacer()

            HStack(spacing: 3) {
                Text("Order")
                    .font(.caption)
                    .foregroundStyle(.black)

                Picker("", selection: $pitchFirst) {
                    Text("Pitch 1st")
                        .tag(true)

                    Text("Location 1st")
                        .tag(false)
                }
                .controlSize(.mini)
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

private struct CodeDisplayOverlayPayload: Identifiable {
    let id = UUID()
    let colorName: String
    let code: String
}

struct CalledPitchView: View {
    @State private var showResultOverlay = false
    @State private var selectedActualLocation: String?
    @State private var tappedCode: String?
    @State private var codeDisplayOverlayPayload: CodeDisplayOverlayPayload?
    @AppStorage(PitchTrackerView.DefaultsKeys.practiceCodesEnabled) private var codesEnabled: Bool = true
    @Binding var isRecordingResult: Bool
    @Binding var activeCalledPitchId: String?
    @Binding var pitchFirst: Bool
    @Binding var autoPitchOnlyEnabled: Bool
    let liveId: String?
    let call: PitchCall
    let pitchCodeAssignments: [PitchCodeAssignment]
    let batterSide: BatterSide
    let template: PitchTemplate?
    let isEncryptedMode: Bool
    let isPracticeMode: Bool
    let onDeferDisplayCode: ((String, String) -> Void)?
    
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

    private var selectedDisplayedCode: String? {
        guard let tappedCode else { return nil }
        return reorderedCodeIfNeeded(tappedCode)
    }

    private func broadcastDisplayCode(colorName: String, code: String) {
        guard !isPracticeMode else {
            print("⚠️ broadcastDisplayCode skipped (practice mode) color=\(colorName) code=\(code)")
            return
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            print("⚠️ broadcastDisplayCode skipped (missing uid) color=\(colorName) code=\(code)")
            return
        }
        print("📤 broadcastDisplayCode user=\(uid) color=\(colorName) code=\(code)")
        Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("displayState")
            .document("current")
            .setData([
                "colorName": colorName,
                "code": code,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
    }

    private func clearDisplayCode() {
        guard !isPracticeMode else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("displayState")
            .document("current")
            .setData([
                "colorName": FieldValue.delete(),
                "code": FieldValue.delete(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
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
                    
                    PitchResultBanner(
                        isRecording: isRecordingResult,
                        callColor: callColor
                    )
                    Spacer()

                    Button {
                        autoPitchOnlyEnabled.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Pitch only")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Image(systemName: autoPitchOnlyEnabled ? "checkmark.circle.fill" : "circle")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
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
                        CodeOrderToggle(
                            pitchFirst: $pitchFirst,
                            template: template,
                            selectedCode: selectedDisplayedCode,
                            onColorTap: { colorName in
                                guard let selectedDisplayedCode else { return }
                                codeDisplayOverlayPayload = CodeDisplayOverlayPayload(
                                    colorName: colorName,
                                    code: selectedDisplayedCode
                                )
                                broadcastDisplayCode(colorName: colorName, code: selectedDisplayedCode)
                            }
                        )
                    }
                    
                } else {
                    // Keep CalledPitchView height stable when Codes are turned Off in Practice
                    if isPracticeMode && !codesEnabled && !displayCodes.isEmpty {
                        // Reserve the chips area height
                        Color.clear
                            .frame(height: 60)
                            .padding(.top, 2)
                        // Reserve space for the CodeOrderToggle to prevent layout jump
                        CodeOrderToggle(
                            pitchFirst: $pitchFirst,
                            template: template,
                            selectedCode: selectedDisplayedCode,
                            onColorTap: { _ in }
                        )
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
        .fullScreenCover(item: $codeDisplayOverlayPayload) { payload in
            CodeDisplayOverlayView(
                colorName: payload.colorName,
                code: payload.code,
                onClose: {
                    codeDisplayOverlayPayload = nil
                    clearDisplayCode()
                }
            )
        }
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
        .onChange(of: tappedCode) { _, newValue in
            if newValue == nil {
                codeDisplayOverlayPayload = nil
                clearDisplayCode()
            }
        }
        
    }
}

struct PitchResultBanner: View {
    let isRecording: Bool
    let callColor: Color

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill")
                    .font(.caption.bold())

                if isRecording {
                    BlendedStrokeCircle(lineWidth: 3, size: 24)
                }

                Text(isRecording ? " Tap result" : "Code")
                    .font(.footnote.weight(.semibold))
            }
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
        .accessibilityLabel(isRecording ? "Tap result" : "Code")
    }
}
private struct CodeShareSheet: View {
    let initialCode: String
    let initialTab: Int
    let hostUid: String?
    let gameId: String?
    let opponent: String?
    let isGame: Bool
    let templateId: String?
    let templateName: String?
    let onConsume: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var generated: String
    @State private var inviteLink: String = ""
    @State private var didWriteSessionDoc = false
    @State private var writeErrorMessage: String? = nil
    @State private var showProPaywall = false


    init(
        initialCode: String,
        initialTab: Int = 0,
        hostUid: String?,
        gameId: String?,
        opponent: String?,
        isGame: Bool,
        templateId: String?,
        templateName: String?,
        onConsume: @escaping (String) -> Void
    ) {
        self.initialCode = initialCode
        self.initialTab = initialTab
        self.hostUid = hostUid
        self.gameId = gameId
        self.opponent = opponent
        self.isGame = isGame
        self.onConsume = onConsume
        self.templateId = templateId
        self.templateName = templateName

        _generated = State(initialValue: initialCode)

    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {

                VStack(alignment: .center, spacing: 12) {
                    Text("Share these invite links:")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let qrImage = qrImage(for: inviteLink) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 720, maxHeight: 720)
                            .padding(.vertical, 6)
                    }

                    if !inviteLink.isEmpty {
                        Text(inviteLink)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.center)
                    } else if isGenerating {
                        Text("Generating…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if let msg = writeErrorMessage {
                        Text(msg)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    HStack {
                        Button {
                            UIPasteboard.general.string = inviteLink
                        } label: {
                            Label("Copy Link", systemImage: "link")
                        }
                        .buttonStyle(.bordered)
                        .disabled(inviteLink.isEmpty)

                        if let url = URL(string: inviteLink) {
                            ShareLink(item: url) {
                                Label("Share Link", systemImage: "square.and.arrow.up")
                            }
                        }
                    }

                }
                .frame(maxWidth: .infinity, alignment: .center)
                .onAppear {
                    inviteLink = ""
                    generateLiveGameAndCode()
                }

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Invite Link")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showProPaywall) {
            ProPaywallView(
                title: "PitchMark Pro",
                message: "Invite links require PitchMark Pro.",
                allowsClose: true
            )
        }
    }
    
    private func buildShareCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    @State private var isGenerating: Bool = false

    private func generateLiveGameAndCode() {
        if !subscriptionManager.isPro {
            writeErrorMessage = "PitchMark Pro is required to create invite links."
            showProPaywall = true
            return
        }

        guard let gameId = gameId else {
            writeErrorMessage = "Select a game first before generating an invite link."
            return
        }

        isGenerating = true
        print("🧩 Generate tapped | gameId=\(gameId) isGame=\(isGame)")
        writeErrorMessage = nil
        generated = ""
        inviteLink = ""

        LiveGameService.shared.createLiveGameAndJoinCode(
            ownerGameId: gameId,
            opponent: opponent ?? "",
            templateId: self.templateId,
            templateName: self.templateName
        ) { result in
            DispatchQueue.main.async {
                self.isGenerating = false
                switch result {
                case .success(let tuple):
                    print("✅ Generated code=\(tuple.code) liveId=\(tuple.liveId)")
                    self.generated = tuple.code
                    self.inviteLink = "pitchmark://join?token=\(tuple.inviteToken)"

                    // Tell the parent to switch into the live session
                    // We pass the LIVE ID now (not the 6-digit code)
                    NotificationCenter.default.post(
                        name: .gameOrSessionChosen,
                        object: nil,
                        userInfo: [
                            "resolved": true,
                            "type": "liveGame",
                            "liveId": tuple.liveId,
                            "ownerUid": self.hostUid ?? "",
                            "gameId": gameId,
                            "opponent": self.opponent ?? "",
                            "templateId": self.templateId ?? "",
                            "templateName": self.templateName ?? ""
                        ]
                    )

                case .failure(let err):
                    print("❌ Generate failed:", err.localizedDescription)
                    self.writeErrorMessage = err.localizedDescription
                }
            }
        }
    }

    private func qrImage(for text: String) -> UIImage? {
        guard !text.isEmpty else { return nil }
        let data = Data(text.utf8)
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("Q", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }





}

struct BlendedStrokeCircle: View {
    var lineWidth: CGFloat = 3
    var size: CGFloat = 24

    var body: some View {
        Circle()
            .stroke(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: .green, location: 0.00),
                        .init(color: .green, location: 0.45),
                        .init(color: .yellow, location: 0.50),
                        .init(color: .red, location: 0.55),
                        .init(color: .red, location: 1.00)
                    ]),
                    center: .center,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(270)
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: size, height: size)
    }
}

struct GameSelectionSheet: View {
    var onCreate: (String, Date) -> Void
    var onChoose: (String) -> Void
    var onCancel: () -> Void
    @Binding var codeShareInitialTab: Int
    @Binding var showCodeShareSheet: Bool
    @Binding var shareCode: String
    @Binding var codeShareSheetID: UUID
    @Binding var showCodeShareModePicker: Bool
    @Binding var games: [Game]
    @State private var showAddGamePopover: Bool = false
    @State private var newOpponentName: String = ""
    @State private var newGameDate: Date = Date()
    
    @State private var pendingDeleteGameId: String? = nil
    @State private var showDeleteGameConfirm: Bool = false
    @State private var showFinalDeleteGameConfirm: Bool = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        NavigationStack {
            List {
                if games.isEmpty {
                    Text("No games yet. Tap “New Game” to create one.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
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
            .refreshable {
                authManager.loadGames { loaded in
                    self.games = loaded
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Spacer()
                        Button {
                            showAddGamePopover = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                Text("New Game")
                            }
                        }
                        Spacer()
                    }
                }
            }

        }
        .confirmationDialog(
            "Delete Game?",
            isPresented: $showDeleteGameConfirm,
            titleVisibility: .visible
        ) {
            Button("Continue", role: .destructive) {
                showFinalDeleteGameConfirm = true
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteGameId = nil
            }
        } message: {
            Text("This will remove the game and its lineup.")
        }
        .confirmationDialog(
            "Delete Game and Stats?",
            isPresented: $showFinalDeleteGameConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                if let id = pendingDeleteGameId {
                    if let idx = games.firstIndex(where: { $0.id == id }) {
                        games.remove(at: idx)
                    }
                    authManager.deleteGameCascade(gameId: id) { result in
                        if case .failure(let error) = result {
                            print("❌ deleteGameCascade failed:", error.localizedDescription)
                        }
                    }
                    NotificationCenter.default.post(name: .gameOrSessionDeleted, object: nil, userInfo: ["type": "game", "gameId": id])
                }
                pendingDeleteGameId = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteGameId = nil
            }
        } message: {
            Text("This will permanently delete the game, all pitch events for that game, and pitcher stats linked to it. This cannot be undone.")
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

private struct SessionConfirmationSheet: View {
    let pending: PitchTrackerView.PendingSessionConfirmation
    let pitchers: [Pitcher]
    let templates: [PitchTemplate]
    @Binding var selectedPitcherId: String?
    @Binding var selectedTemplateId: UUID?
    let resolvedPitcherName: String
    let resolvedTemplateName: String
    let resolvedGameName: String
    let resolvedPracticeName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var headerText: String {
        switch pending.kind {
        case .game:
            return "Confirm Game"
        case .practice:
            return "Confirm Practice"
        }
    }

    private var sessionLabel: String {
        switch pending.kind {
        case .game:
            return "Game: \(resolvedGameName)"
        case .practice:
            return "Practice: \(resolvedPracticeName)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(headerText)
                .font(.headline)

            Text(sessionLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Pitcher")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Pitcher", selection: $selectedPitcherId) {
                    Text("Not set").tag(String?.none)
                    ForEach(pitchers) { pitcher in
                        Text(pitcher.name).tag(pitcher.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Grid Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Grid Key", selection: $selectedTemplateId) {
                    Text("Not set").tag(UUID?.none)
                    ForEach(templates) { template in
                        Text(template.name).tag(Optional(template.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Selected Pitcher: \(resolvedPitcherName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Selected Grid Key: \(resolvedTemplateName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                Spacer()
                Button("Confirm") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .presentationDetents([.fraction(0.35)])
        .presentationDragIndicator(.visible)
        .onAppear {
            if selectedTemplateId == nil, let first = templates.first {
                selectedTemplateId = first.id
            } else if let selected = selectedTemplateId,
                      !templates.contains(where: { $0.id == selected }),
                      let first = templates.first {
                selectedTemplateId = first.id
            }
        }
        .onChange(of: templates.count) { _, _ in
            if selectedTemplateId == nil, let first = templates.first {
                selectedTemplateId = first.id
            } else if let selected = selectedTemplateId,
                      !templates.contains(where: { $0.id == selected }),
                      let first = templates.first {
                selectedTemplateId = first.id
            }
        }
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onComplete: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onComplete: (UIImage?) -> Void

        init(onComplete: @escaping (UIImage?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = info[.originalImage] as? UIImage
            onComplete(image)
        }
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onScan = onScan
        controller.onCancel = onCancel
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {
    }
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didScan = false
    private let overlayLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            onCancel?()
            return
        }

        session.addInput(input)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            onCancel?()
            return
        }

        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        metadataOutput.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview

        overlayLayer.fillRule = .evenOdd
        overlayLayer.fillColor = UIColor.black.withAlphaComponent(0.5).cgColor
        view.layer.addSublayer(overlayLayer)

        borderLayer.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.lineWidth = 2
        view.layer.addSublayer(borderLayer)

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Close", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled()
            config.baseForegroundColor = .white
            config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.6)
            config.cornerStyle = .medium
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            closeButton.configuration = config
        } else {
            closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            closeButton.layer.cornerRadius = 14
            closeButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        }
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        updateOverlayMask()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        didScan = false
        if !session.isRunning {
            session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    @objc private func closeTapped() {
        onCancel?()
    }

    private func updateOverlayMask() {
        let size = min(view.bounds.width, view.bounds.height) * 0.6
        let rect = CGRect(
            x: (view.bounds.width - size) / 2,
            y: (view.bounds.height - size) / 2,
            width: size,
            height: size
        )

        let path = UIBezierPath(rect: view.bounds)
        path.append(UIBezierPath(roundedRect: rect, cornerRadius: 12))
        overlayLayer.path = path.cgPath

        let borderPath = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        borderLayer.path = borderPath.cgPath
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !didScan else { return }
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue else { return }
        didScan = true
        onScan?(value)
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
                        Text(event.pitch)
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
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("New Practice")
                        }
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
