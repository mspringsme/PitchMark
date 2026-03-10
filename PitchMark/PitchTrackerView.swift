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
    @Environment(\.scenePhase) private var scenePhase
    @State private var showProfileSheet = false
    @State private var showSignOutConfirmation = false
    @State private var selectedTemplate: PitchTemplate? = nil
    @State private var showTemplateEditor = false
    @State private var showInviteJoinSheet = false
    @State private var inviteJoinText: String = ""
    @State private var inviteJoinError: String? = nil
    @State private var pitchers: [Pitcher] = []
    @State private var selectedPitcherId: String? = nil
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
        static let encryptedByGameId = "encryptedByGameId"
        static let encryptedByPracticeId = "encryptedByPracticeId"
        static let practiceCodesEnabled = "practiceCodesEnabled"
        static let activeGameOwnerUserId = "activeGameOwnerUserId"
        static let hiddenTemplateIds = "hiddenTemplateIds"
        static let hiddenPitcherIds = "hiddenPitcherIds"
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
    @State private var activeGameOwnerUserId: String? = nil
    @State private var gameListener: ListenerRegistration? = nil
    @State private var livePitchEventsListener: ListenerRegistration? = nil
    @State private var gamePitchEventsListener: ListenerRegistration? = nil
    @State private var gamePitchEvents: [PitchEvent] = []
    @State private var lastObservedResultSelectionId: String? = nil
    @State private var codeShareSheetID = UUID()
    // MARK: - Startup gating (prevents sheet-flash on launch)

    private enum StartupPhase { case launching, ready }

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

        guard isGame, isOwnerForActiveGame else { return }


        // If owner cleared the call, clear pending too.
        guard let newCall else {
            if let liveId = activeLiveId {
                LiveGameService.shared.updateLiveFields(liveId: liveId, fields: [
                    "pending": FieldValue.delete(),
                    "resultSelection": FieldValue.delete()
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
            print("⚠️ No activeLiveId — refusing to write pending to legacy game doc.")
            return
        }

        do {
            let pendingData = try Firestore.Encoder().encode(pending)
            LiveGameService.shared.updateLiveFields(liveId: liveId, fields: [
                "pending": pendingData
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

        // Only seed if the joiner isn't already mid-confirm
        if !showConfirmSheet && pendingResultLabel == nil {
            pendingResultLabel = label
        }

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

        // If pending is gone (or inactive), the participant has saved/canceled — dismiss owner's call UI.
        if !isActive {
            if calledPitch != nil || activeCalledPitchId != nil || isRecordingResult || pendingResultLabel != nil {
                resetCallAndResultUIState()
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
                      let ownerUid = self.activeGameOwnerUserId, !ownerUid.isEmpty,
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
                    // Keep games[] in sync so currentGame works
                    if let idx = self.games.firstIndex(where: { $0.id == gid }) {
                        self.games[idx] = updated
                    } else {
                        self.games.append(updated)
                    }

                    // If not in live mode, you can optionally mirror into local UI state
                    // (ONLY needed if your UI depends on these @State vars outside live mode)
                    if self.activeLiveId == nil {
                        self.balls = updated.balls
                        self.strikes = updated.strikes
                        self.inning = updated.inning
                        self.hits = updated.hits
                        self.walks = updated.walks
                        self.us = updated.us
                        self.them = updated.them
                    }

                    // Ensure owner still sees the lineup if local cells are empty
                    if self.jerseyCells.isEmpty {
                        if let ids = updated.batterIds, ids.count == updated.jerseyNumbers.count {
                            self.jerseyCells = zip(ids, updated.jerseyNumbers).map { (idStr, num) in
                                JerseyCell(id: UUID(uuidString: idStr) ?? UUID(), jerseyNumber: num)
                            }
                        } else {
                            self.jerseyCells = updated.jerseyNumbers.map { JerseyCell(jerseyNumber: $0) }
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

        // Kick a backfill attempt early if we already know owner + game.
        if canBackfillLiveHistory {
            seedLivePitchEventsFromOwnerGameIfNeeded()
        }

        let ref = Firestore.firestore().collection("liveGames").document(liveId)
        liveListener = ref.addSnapshotListener { snap, err in
            if let err {
                print("❌ Live listener error:", err)
                return
            }
            guard let snap, snap.exists, let data = snap.data() else {
                print("⚠️ Live game doc missing:", ref.path)
                return
            }

            DispatchQueue.main.async {
                // ✅ Use existing value as fallback (prevents partial writes from zeroing fields)
                self.balls   = data["balls"]   as? Int ?? self.balls
                self.strikes = data["strikes"] as? Int ?? self.strikes
                self.inning  = data["inning"]  as? Int ?? self.inning
                self.hits    = data["hits"]    as? Int ?? self.hits
                self.walks   = data["walks"]   as? Int ?? self.walks
                self.us      = data["us"]      as? Int ?? self.us
                self.them    = data["them"]    as? Int ?? self.them
                // ✅ FIX: restore opponent label for the Game button in LIVE mode
                if let opp = data["opponent"] as? String, !opp.isEmpty {
                    self.opponentName = opp
                    UserDefaults.standard.set(opp, forKey: "activeOpponentName")
                }

                if let sideRaw = data["batterSide"] as? String,
                   let parsed = BatterSide(rawValue: sideRaw) {
                    self.batterSide = parsed
                }
                // ✅ LIVE TEMPLATE FLOW: apply owner's template on participant (and keep owner consistent too)
                let liveTemplateId = data["templateId"] as? String
                let liveTemplateName = data["templateName"] as? String
                self.pendingLiveTemplateId = liveTemplateId
                self.pendingLiveTemplateName = liveTemplateName

                if let tid = liveTemplateId, !tid.isEmpty {
                    if self.selectedTemplate?.id.uuidString != tid {
                        if let t = self.templates.first(where: { $0.id.uuidString == tid }) {
                            self.applyTemplate(t, source: .live)
                        } else {
                            // templates not loaded yet or participant doesn't have it
                            print("⚠️ Live templateId not found locally:", tid, "name:", liveTemplateName ?? "nil")
                        }
                    }
                } else if let tname = liveTemplateName, !tname.isEmpty {
                    // Fallback match by name
                    if self.selectedTemplate?.name != tname,
                       let t = self.templates.first(where: { $0.name == tname }) {
                        self.applyTemplate(t, source: .live)
                    }
                }
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


                let status = (data["status"] as? String) ?? "active"

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
                    } else if !self.showConfirmSheet {
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
                // Only show green if we’re actually in a live room AND we see the other side recently
                let connectedNow = (self.activeLiveId != nil) && otherRecent
                self.uiConnected = connectedNow

                // ✅ OWNER ONLY: auto-dismiss code sheet when participant connects
                if connectedNow && self.isOwnerForActiveGame {
                    // One-shot per liveId
                    if self.didAutoDismissCodeSheetForLiveId != liveId {
                        self.didAutoDismissCodeSheetForLiveId = liveId

                        // Re-arm the live pitch-events listener right when the
                        // participant connection becomes active. This mirrors the
                        // post-relaunch recovery path and prevents the owner from
                        // getting stuck on a stale live listener after the initial
                        // connect handoff.
                        if self.activeLiveId == liveId {
                            self.startListeningToLivePitchEvents(liveId: liveId)
                        }

                        // Dismiss whichever is currently visible
                        self.showCodeShareSheet = false
                        self.showCodeShareModePicker = false

                        // If you have any other code UI (optional):
                        // self.codeShareInitialTab = 0
                    }
                }

                // If we become disconnected, allow the next connection to auto-dismiss again
                if !connectedNow, self.didAutoDismissCodeSheetForLiveId == liveId {
                    self.didAutoDismissCodeSheetForLiveId = nil
                }
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
    }

    private func resetLiveTemplateOverrideLock() {
        liveTemplateOverrideLocked = false
    }

    private func endLiveSessionLocally(keepCurrentGame: Bool) {
        guard let liveId = activeLiveId else { return }

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
        UserDefaults.standard.removeObject(forKey: "activeLiveId")

        if keepCurrentGame, isGame {
            startListeningToActiveGame()
            startListeningToGamePitchEvents()
        } else {
            isGame = false
            sessionManager.switchMode(to: .practice)
        }
    }

    private func disconnectFromGame(notifyHost: Bool = true) {
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
    }

    private func persistSelectedPitcherId(_ id: String?) {
        let defaults = UserDefaults.standard
        if let id {
            defaults.set(id, forKey: DefaultsKeys.lastPitcherId)
        } else {
            defaults.removeObject(forKey: DefaultsKeys.lastPitcherId)
        }
    }

    private func persistBatterSide(_ side: BatterSide) {
        UserDefaults.standard.set(side == .left ? "left" : "right", forKey: DefaultsKeys.lastBatterSide)
    }
    private func pushBatterSideToActiveGame(_ side: BatterSide) {
        // ✅ Allow BOTH owner and participant to update batterSide
        guard isGame,
              let gid = selectedGameId,
              let owner = effectiveGameOwnerUserId
        else { return }

        let sideString = (side == .left) ? "left" : "right"

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

    private enum TemplateSelectionSource {
        case user
        case live
    }

    // MARK: - Template Apply Helper
    private func applyTemplate(_ template: PitchTemplate, source: TemplateSelectionSource = .user) {
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

        if source == .user {
            liveTemplateOverrideLocked = true
        }
    }

    private func applySelectedPitcher(_ pitcher: Pitcher) {
        selectedPitcherId = pitcher.id
        persistSelectedPitcherId(pitcher.id)

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

    private func joinLiveGameFromInvite() {
        inviteJoinError = nil

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

    private var inningBinding: Binding<Int> {
        intBinding(
            get: { activeLiveId != nil ? inning : (currentGame?.inning ?? 1) },
            set: { newValue in
                if let liveId = activeLiveId {
                    LiveGameService.shared.updateLiveFields(liveId: liveId, fields: ["inning": newValue])
                    inning = newValue
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameInning(ownerUserId: owner, gameId: gid, inning: newValue)

                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].inning = newValue
                }
            }
        )
    }


    private var hitsBinding: Binding<Int> {
        intBinding(
            get: { activeLiveId != nil ? hits : (currentGame?.hits ?? 0) },
            set: { newValue in
                if let liveId = activeLiveId {
                    LiveGameService.shared.updateLiveFields(liveId: liveId, fields: ["hits": newValue])
                    hits = newValue
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameHits(ownerUserId: owner, gameId: gid, hits: newValue)

                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].hits = newValue
                }
            }
        )
    }

    
    private var walksBinding: Binding<Int> {
        intBinding(
            get: { activeLiveId != nil ? walks : (currentGame?.walks ?? 0) },
            set: { newValue in
                if let liveId = activeLiveId {
                    LiveGameService.shared.updateLiveFields(liveId: liveId, fields: ["walks": newValue])
                    walks = newValue
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameWalks(ownerUserId: owner, gameId: gid, walks: newValue)

                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].walks = newValue
                }
            }
        )
    }

    private var ballsBinding: Binding<Int> {
        intBinding(
            get: { activeLiveId != nil ? balls : (currentGame?.balls ?? 0) },
            set: { newValue in
                if let liveId = activeLiveId {
                    LiveGameService.shared.updateLiveFields(liveId: liveId, fields: ["balls": newValue])
                    balls = newValue
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameBalls(ownerUserId: owner, gameId: gid, balls: newValue)

                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].balls = newValue
                }
            }
        )
    }

    private var strikesBinding: Binding<Int> {
        intBinding(
            get: { activeLiveId != nil ? strikes : (currentGame?.strikes ?? 0) },
            set: { newValue in
                if let liveId = activeLiveId {
                    LiveGameService.shared.updateLiveFields(liveId: liveId, fields: ["strikes": newValue])
                    strikes = newValue
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameStrikes(ownerUserId: owner, gameId: gid, strikes: newValue)

                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].strikes = newValue
                }
            }
        )
    }

    private var usBinding: Binding<Int> {
        intBinding(
            get: { activeLiveId != nil ? us : (currentGame?.us ?? 0) },
            set: { newValue in
                if let liveId = activeLiveId {
                    LiveGameService.shared.updateLiveFields(liveId: liveId, fields: ["us": newValue])
                    us = newValue
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameUs(ownerUserId: owner, gameId: gid, us: newValue)

                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].us = newValue
                }
            }
        )
    }

    private var themBinding: Binding<Int> {
        intBinding(
            get: { activeLiveId != nil ? them : (currentGame?.them ?? 0) },
            set: { newValue in
                if let liveId = activeLiveId {
                    LiveGameService.shared.updateLiveFields(liveId: liveId, fields: ["them": newValue])
                    them = newValue
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameThem(ownerUserId: owner, gameId: gid, them: newValue)

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

    private var selectedPitcherName: String {
        guard let pid = selectedPitcherId else { return "Select a pitcher" }
        return pitchers.first(where: { $0.id == pid })?.name ?? "Select a pitcher"
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

            if showSelectBatterOverlay {
                selectBatterOverlayView
            }
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
                    call: call,
                    pitchCodeAssignments: pitchCodeAssignments,
                    batterSide: batterSide,
                    template: selectedTemplate,
                    isEncryptedMode: selectedTemplate.map { useEncrypted(for: $0) } ?? false,
                    isPracticeMode: sessionManager.currentMode == .practice
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

        if isGame && selectedBatterId == nil {
            showSelectBatterOverlay = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showSelectBatterOverlay = false
            }
        }
    }
    private func handleCalledPitchDisappear() {
        shouldBlurBackground = false
        showSelectBatterOverlay = false
    }
    private var selectBatterOverlayView: some View {
        VStack {
            HStack {
                Spacer()
                Text("Select a batter?")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                Spacer()
            }
            Spacer()
        }
        .padding(.top, -10)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.5), value: showSelectBatterOverlay)
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
                selectedGameId: $selectedGameId
            )
            .environmentObject(authManager)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .top)
        }
    }


    private var headerContainer: some View {
        let screen = UIScreen.main.bounds
        
        return VStack(spacing: 4) {
            topBar
        }
        .frame(
            width: screen.width * 0.94,   // 94% of screen width
            height: screen.height * 0.10 // 10% of screen height
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
                .frame(height: UIScreen.main.bounds.height * 0.15)
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
            Spacer(minLength: 40)
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
            if !(isGame && !isOwnerForActiveGame) {
            VStack(alignment: .center, spacing: 4) {
                Text("Pitcher")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Menu {
                    ForEach(visiblePitchers) { pitcher in
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
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .allowsTightening(true)
                                .opacity(0)
                            Image(systemName: "chevron.down")
                                .font(.subheadline.weight(.semibold))
                                .opacity(0)
                        }

                        HStack(spacing: 8) {
                            Text(currentLabel)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .allowsTightening(true)
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
                    .opacity(visiblePitchers.isEmpty ? 0.6 : 1.0)
                    .contentShape(Capsule())
                }
                .disabled(visiblePitchers.isEmpty)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .center, spacing: 4) {
                Text("Template")
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
                                .font(.headline)
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
                                .font(.subheadline.weight(.semibold))
                                .opacity(0)
                        }
                        
                        // Visible current label
                        HStack(spacing: 8) {
                            Text(currentLabel)
                                .font(.headline)
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
                    .opacity(visibleTemplates.isEmpty ? 0.6 : 1.0)
                    .contentShape(Capsule())
                    .animation(.easeInOut(duration: 0.2), value: selectedTemplate?.id)
                }
                .disabled(visibleTemplates.isEmpty)
            }
            .frame(maxWidth: .infinity)
        }
            Spacer()
            
            codeLinkButton

            Button(action: {
                showSettings = true
            }) {
                Image(systemName: "gearshape")
                    .imageScale(.large)
            }
            .tint(.gray)
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
            .overlay(sessionOverlay, alignment: .bottom)

            batterSideOverlay(SZwidth: SZwidth)
        }
        .frame(width: SZwidth, height: 390)
    }
    private var codeLinkButton: some View {
        Button {
            showCodeShareModePicker = true
        } label: {
            Image(systemName: "key.sensor.tag.radiowaves.left.and.right.fill")
                .imageScale(.large)
                .foregroundStyle(uiConnected ? .green : .red)
                .frame(width: 40, height: 32)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Code Link")
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
                            fields: ["status": "ended"]
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
        .padding(.top, 14)
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
    
    private var baseBody: some View {
        ZStack {
            backgroundView
            mainStack
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    private func handleInitialAppear() {
        // If we aren't signed in yet, do NOT mark anything as presented.
        // We'll be called again when sign-in completes.
        guard authManager.isSignedIn else {
            print("⏳ handleInitialAppear: not signed in yet — deferring boot flow")
            startupPhase = .ready
            return
        }

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
                    self.games = loaded
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
                self.selectedTemplate = loadedTemplates.first
            }
            self.applyPendingLiveTemplateIfPossible()
        }

        authManager.loadGames { loadedGames in
            self.games = loadedGames

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

                // ✅ Runtime state
                activeGameOwnerUserId = ownerUid
                selectedGameId = gameId

                isGame = true
                sessionManager.switchMode(to: .game)
                suppressNextGameSheet = true

                // ✅ Persist "active game" so relaunch restores correctly
                let defaults = UserDefaults.standard
                defaults.set(gameId, forKey: DefaultsKeys.activeGameId)
                defaults.set(ownerUid, forKey: DefaultsKeys.activeGameOwnerUserId)
                defaults.set(false, forKey: DefaultsKeys.activeIsPractice)
                defaults.removeObject(forKey: DefaultsKeys.activePracticeId)   // optional safety
                defaults.set("tracker", forKey: DefaultsKeys.lastView)

                hydrateChosenGameUI(ownerUid: ownerUid, gameId: gameId)
                startListeningToActiveGame()
                startListeningToGamePitchEvents()
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

                HStack {
                    Button("Paste") {
                        if let pasted = UIPasteboard.general.string {
                            inviteJoinText = pasted
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }

            if let error = inviteJoinError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    inviteJoinError = nil
                    showInviteJoinSheet = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(isJoiningSession ? "Joining..." : "Join") {
                    joinLiveGameFromInvite()
                }
                .buttonStyle(.borderedProminent)
                .disabled(inviteJoinText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoiningSession)
            }
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
            selectedPitcherId: selectedPitcherId,
            saveAction: { event in
                if isGame, let liveId = activeLiveId {
                    // ✅ Live: save to shared room
                    let uid = authManager.user?.uid ?? ""
                    do {
                        var eventData = try Firestore.Encoder().encode(event)
                        // Firestore.Encoder already encodes event.timestamp correctly (as a Timestamp).
                        eventData["createdByUid"] = uid

                        // ✅ OPTIONAL: keep a server-side write time in a separate field (doesn't break decoding)
                        eventData["serverTimestamp"] = FieldValue.serverTimestamp()

                        if let gid = selectedGameId {
                            eventData["gameId"] = gid
                        }

                        let liveRef = Firestore.firestore()
                            .collection("liveGames").document(liveId)
                            .collection("pitchEvents").document()
                        let liveEventId = liveRef.documentID

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
            },
            template: selectedTemplate
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
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard newPhase != .active else { return }

        let shouldDisconnect = (activeLiveId != nil) || (isGame && selectedGameId != nil && !isOwnerForActiveGame)
        guard shouldDisconnect else { return }

        print("🔌 Scene inactive/background → disconnecting from game")
        disconnectFromGame(notifyHost: true)
    }

    var body: some View {
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
            .onChange(of: overlayTab) { _, newValue in
                if newValue == .progress && sessionManager.currentMode == .practice {
                    progressRefreshToken = UUID()
                }
            }
            .eraseToAnyView()

        let v2 = v1
            .sheet(isPresented: $showGameSheet, onDismiss: {
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
            .eraseToAnyView()

        let v5 = v4
            .sheet(isPresented: $showPracticeSheet, onDismiss: {
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

        // Keep alerts + the rest of your observers, then erase one last time
        return v8
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
            .onAppear {
                handleInitialAppear()
            }
            .onChange(of: authManager.isSignedIn) { _, newValue in
                if newValue {
                    // ✅ If sign-in/restore completes AFTER first appear,
                    // rerun the boot flow so games/templates load and initial sheets can present.
                    handleInitialAppear()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .gameOrSessionChosen)) { note in
                guard let info = note.userInfo as? [String: Any] else { return }

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
                    self.startLivePresenceHeartbeat(liveId: liveId)
                    self.ensureLivePresence(liveId: liveId)
                    self.seedLivePitchEventsOnce(liveId: liveId)

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
                    // If the sender already knew the opponent name, reflect it immediately
                    if let opp = info["opponent"] as? String {
                        self.opponentName = opp
                    }

                    // 🔴 Clear any stale practice UI state before switching
                    self.resetCallAndResultUIState()

                    // ✅ Set IDs first
                    self.activeGameOwnerUserId = ownerUid
                    self.selectedGameId = gid
                    // ✅ Persist active game selection
                    let defaults = UserDefaults.standard
                    defaults.set(gid, forKey: DefaultsKeys.activeGameId)
                    defaults.set(ownerUid, forKey: DefaultsKeys.activeGameOwnerUserId)
                    defaults.set(false, forKey: DefaultsKeys.activeIsPractice)
                    defaults.set("tracker", forKey: DefaultsKeys.lastView)

                    // ✅ Force GAME mode (order matters!)
                    self.suppressNextGameSheet = true
                    self.isGame = true
                    self.sessionManager.switchMode(to: .game)

                    DispatchQueue.main.async {
                        self.hydrateChosenGameUI(ownerUid: ownerUid, gameId: gid)
                        self.startListeningToActiveGame()
                        self.startListeningToGamePitchEvents()
                    }


                    return

                }
            }
            .eraseToAnyView()
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

        var body: some View {
            PitchResultSheet(
                allEvents: gameEvents,   // <- live-updating array
                games: games,
                templates: templates,
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

                withOwnerAndGame { owner, gid in
                    authManager.updateGameBalls(ownerUserId: owner, gameId: gid, balls: newCount)
                }
            }
        }

        .onChange(of: strikeToggles) { _, newValue in
            let newCount = newValue.filter { $0 }.count
            if strikes != newCount {
                strikes = newCount

                withOwnerAndGame { owner, gid in
                    authManager.updateGameStrikes(ownerUserId: owner, gameId: gid, strikes: newCount)
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
            guard let owner = ownerUserId, !owner.isEmpty else { return }

            authManager.loadGame(ownerUserId: owner, gameId: gid) { game in
                guard let game else { return }

                let newBalls = max(0, min(3, game.balls ?? 0))
                let newStrikes = max(0, min(2, game.strikes ?? 0))

                balls = newBalls
                strikes = newStrikes

                ballToggles = (0..<3).map { $0 < newBalls }
                strikeToggles = (0..<2).map { $0 < newStrikes }
            }
        }
    }

    // MARK: - Helpers
    private func withOwnerAndGame(_ action: (_ owner: String, _ gameId: String) -> Void) {
        guard let owner = ownerUserId, !owner.isEmpty else { return }
        guard let gid = selectedGameId, !gid.isEmpty else { return }
        action(owner, gid)
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
                    HStack(spacing: 4) {
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

private struct CodeDisplayOverlayView: View {
    let colorName: String
    let code: String
    let onClose: () -> Void

    private var backgroundColor: Color {
        templatePaletteColor(colorName)
    }

    private var foregroundColor: Color {
        switch colorName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "black", "blue", "red":
            return .white
        default:
            return .black
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                backgroundColor
                    .ignoresSafeArea()

                let horizontalSpan = max(120.0, proxy.size.width - 48)
                let verticalSpan = max(120.0, proxy.size.height - 48)
                let characterSpacing = max(18.0, horizontalSpan * 0.09)
                let fontSize = max(110.0, (verticalSpan - (characterSpacing * 3)) / 2.5)

                HStack(spacing: characterSpacing) {
                    ForEach(Array(code).map(String.init), id: \.self) { character in
                        Text(character)
                            .font(.system(size: fontSize, weight: .black, design: .rounded))
                            .foregroundStyle(foregroundColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(foregroundColor)
                        .padding(12)
                        .background(
                            Circle()
                                .fill(foregroundColor.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
                .padding(20)
            }
        }
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

    private var selectedDisplayedCode: String? {
        guard let tappedCode else { return nil }
        return reorderedCodeIfNeeded(tappedCode)
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
    let initialTab: Int
    let hostUid: String?
    let gameId: String?
    let opponent: String?
    let isGame: Bool
    let templateId: String?
    let templateName: String?
    let onConsume: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var generated: String
    @State private var inviteLink: String = ""
    @State private var didWriteSessionDoc = false
    @State private var writeErrorMessage: String? = nil


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
                    Text("Share this invite link:")
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
    }
    
    private func buildShareCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    @State private var isGenerating: Bool = false

    private func generateLiveGameAndCode() {
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
