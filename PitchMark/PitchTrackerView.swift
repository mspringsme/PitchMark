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
                .fixedAppDynamicType()
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
    private static let allPitchersSummarySelection = "__ALL_PITCHERS__"
    private static let demoUserId = "pitchmark-demo-user"
    private static let demoGameId = "pitchmark-demo-game"
    private static let demoPitcherId = "pitchmark-demo-pitcher"
    private static let demoTemplateId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    var isDemoMode: Bool = false
    var onRequireSignIn: () -> Void = {}

    enum PitchResultBannerPhase {
        case code
        case tapLocation
        case chooseAny
    }

    @State private var mirroredLivePitchEventIds: Set<String> = []
    // The 153 presentation-state properties that used to be `@State` here
    // live in this object now - see TrackerUIState.swift for why. Each one
    // keeps a same-named forwarding property below, so `foo` still reads and
    // writes exactly as before; only `$foo` became `$ui.foo`.
    @StateObject private var ui = TrackerUIState()

    private var didAutoDismissCodeSheetForLiveId: String? { get { ui.didAutoDismissCodeSheetForLiveId } nonmutating set { ui.didAutoDismissCodeSheetForLiveId = newValue } }
    private var uiConnected: Bool { get { ui.uiConnected } nonmutating set { ui.uiConnected = newValue } }
    private var showCodeAssignmentSheet: Bool { get { ui.showCodeAssignmentSheet } nonmutating set { ui.showCodeAssignmentSheet = newValue } }
    private var pitcherName: String { get { ui.pitcherName } nonmutating set { ui.pitcherName = newValue } }
    @State private var selectedPitches: Set<String> = []
    @State private var calledPitch: PitchCall? = nil
    @State private var lastCallInitiatedAt: Date? = nil
    private var lastObservedPendingCallId: String? { get { ui.lastObservedPendingCallId } nonmutating set { ui.lastObservedPendingCallId = newValue } }
    @State private var lastTappedPosition: CGPoint? = nil
    @State private var batterSide: BatterSide = .right
    @State private var pitchCodeAssignments: [PitchCodeAssignment] = []
    private var selectedCode: String { get { ui.selectedCode } nonmutating set { ui.selectedCode = newValue } }
    private var selectedPitch: String { get { ui.selectedPitch } nonmutating set { ui.selectedPitch = newValue } }
    private var selectedLocation: String { get { ui.selectedLocation } nonmutating set { ui.selectedLocation = newValue } }
    private var gameIsActive: Bool { get { ui.gameIsActive } nonmutating set { ui.gameIsActive = newValue } }
    /// Home/Moments/Family are TabView siblings of Games, not sheets - a
    /// single selection replaces the old showSettings/showMomentsSheet/
    /// showFamilySheet trio (and the onDismiss+asyncAfter(0.05) dance that
    /// used to chain one sheet's dismissal into the next one's presentation).
    @State private var activeHomeArea: HomeArea = .games
    private var showProfile: Bool { get { ui.showProfile } nonmutating set { ui.showProfile = newValue } }
    @State private var templates: [PitchTemplate] = []
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.scenePhase) private var scenePhase
    private var showProfileSheet: Bool { get { ui.showProfileSheet } nonmutating set { ui.showProfileSheet = newValue } }
    private var showSignOutConfirmation: Bool { get { ui.showSignOutConfirmation } nonmutating set { ui.showSignOutConfirmation = newValue } }
    @State private var selectedTemplate: PitchTemplate? = nil
    private var showTemplateEditor: Bool { get { ui.showTemplateEditor } nonmutating set { ui.showTemplateEditor = newValue } }
    private var showInviteJoinSheet: Bool { get { ui.showInviteJoinSheet } nonmutating set { ui.showInviteJoinSheet = newValue } }
    private var inviteJoinText: String { get { ui.inviteJoinText } nonmutating set { ui.inviteJoinText = newValue } }
    private var inviteJoinError: String? { get { ui.inviteJoinError } nonmutating set { ui.inviteJoinError = newValue } }
    private var showProPaywall: Bool { get { ui.showProPaywall } nonmutating set { ui.showProPaywall = newValue } }
    private var showProGateAlert: Bool { get { ui.showProGateAlert } nonmutating set { ui.showProGateAlert = newValue } }
    private var proGateMessage: String { get { ui.proGateMessage } nonmutating set { ui.proGateMessage = newValue } }
    private var showDemoLoginWall: Bool { get { ui.showDemoLoginWall } nonmutating set { ui.showDemoLoginWall = newValue } }
    private var demoLoginWallMessage: String { get { ui.demoLoginWallMessage } nonmutating set { ui.demoLoginWallMessage = newValue } }
    private var showCameraPicker: Bool { get { ui.showCameraPicker } nonmutating set { ui.showCameraPicker = newValue } }
    private var showCameraUnavailableAlert: Bool { get { ui.showCameraUnavailableAlert } nonmutating set { ui.showCameraUnavailableAlert = newValue } }
    private var showCameraPermissionAlert: Bool { get { ui.showCameraPermissionAlert } nonmutating set { ui.showCameraPermissionAlert = newValue } }
    private var showQRScanner: Bool { get { ui.showQRScanner } nonmutating set { ui.showQRScanner = newValue } }
    private var showGridKeySheet: Bool { get { ui.showGridKeySheet } nonmutating set { ui.showGridKeySheet = newValue } }
    private var showCallingPitchesPrompt: Bool { get { ui.showCallingPitchesPrompt } nonmutating set { ui.showCallingPitchesPrompt = newValue } }
    @State private var promptedTrackingModeLiveIds: Set<String> = Set(UserDefaults.standard.array(forKey: DefaultsKeys.promptedTrackingModeLiveIds) as? [String] ?? [])
    @State private var pitchers: [Pitcher] = []
    private var selectedPitcherId: String? { get { ui.selectedPitcherId } nonmutating set { ui.selectedPitcherId = newValue } }
    @State private var activeSide: GameSide = .home
    @State private var awayPitcherIds: Set<String> = []
    private var showSetOpponentSheet: Bool { get { ui.showSetOpponentSheet } nonmutating set { ui.showSetOpponentSheet = newValue } }
    @State private var opponentTeamCandidates: [(team: Team, membership: TeamMembership)] = []
    private var newOpponentTeamName: String { get { ui.newOpponentTeamName } nonmutating set { ui.newOpponentTeamName = newValue } }
    @State private var newOpponentTeamDesignation = TeamDesignationDraft()
    private var activeAwayTeamName: String { get { ui.activeAwayTeamName } nonmutating set { ui.activeAwayTeamName = newValue } }
    @State private var awayRoster: [TeamPlayer] = []
    private var newAwayPitcherName: String { get { ui.newAwayPitcherName } nonmutating set { ui.newAwayPitcherName = newValue } }
    // Mirror of activeAwayTeamName for our own side, so controls that act
    // on a roster can say whose roster it is instead of leaving the coach
    // to infer it from which side is currently pitching.
    private var activeHomeTeamName: String { get { ui.activeHomeTeamName } nonmutating set { ui.activeHomeTeamName = newValue } }
    @State private var homeRoster: [TeamPlayer] = []
    private var showSetMyTeamSheet: Bool { get { ui.showSetMyTeamSheet } nonmutating set { ui.showSetMyTeamSheet = newValue } }
    @State private var myTeamCandidates: [(team: Team, membership: TeamMembership)] = []
    private var newMyTeamName: String { get { ui.newMyTeamName } nonmutating set { ui.newMyTeamName = newValue } }
    @State private var newMyTeamDesignation = TeamDesignationDraft()
    private var showChooseBattersStep: Bool { get { ui.showChooseBattersStep } nonmutating set { ui.showChooseBattersStep = newValue } }
    // Every roster row across every team the user is on, plus those teams.
    // Both pitcher pickers render Home's Players rows from these
    // (PlayerDirectory.swift), which is what lets them disambiguate
    // same-named pitchers from different teams - the job the old
    // pitcherId -> team-names map did as a subtitle string, before the rows
    // carried the team and its designation themselves. Loaded by fanning
    // loadTeamPlayers out across loadMyTeams's result; no collectionGroup
    // query exists for this (only /teams/{id}/members has one), so
    // client-side fan-out is the lowest-risk option.
    @State private var rosterEntries: [PlayerRosterEntry] = []
    @State private var directoryTeams: [Team] = []
    // Both team-setup sheets can now be reached two ways: from the Us/Them
    // toggle itself (where landing on that side afterward is the whole
    // point) or from the batter row's empty-state button while already on
    // the OTHER side (where the goal is just "get batters to pick from,"
    // not switch sides - flipping anyway silently undid the side you were
    // deliberately on, which read as "nothing happened"). Defaults true to
    // match the toggle's own behavior.
    private var teamSetupShouldFlipSide: Bool { get { ui.teamSetupShouldFlipSide } nonmutating set { ui.teamSetupShouldFlipSide = newValue } }
    // Quick-add: build either roster (ours or the opponent's, whichever is
    // relevant to the current side) without leaving the game - reachable
    // from both the pitcher and batter pickers' own "+" action. Writes
    // through the exact same Team/TeamPlayer/Player records as every other
    // roster entry point, so it persists outside the game like any other
    // roster edit, not something scoped to just this session.
    private var showQuickAddPlayerSheet: Bool { get { ui.showQuickAddPlayerSheet } nonmutating set { ui.showQuickAddPlayerSheet = newValue } }
    private var quickAddPlayerName: String { get { ui.quickAddPlayerName } nonmutating set { ui.quickAddPlayerName = newValue } }
    private var quickAddPlayerJersey: String { get { ui.quickAddPlayerJersey } nonmutating set { ui.quickAddPlayerJersey = newValue } }
    private var quickAddTeamId: String? { get { ui.quickAddTeamId } nonmutating set { ui.quickAddTeamId = newValue } }
    @State private var quickAddPlayerPositions: Set<FieldPosition> = []
    @State private var quickAddPlayerBattingSide: BattingSide? = nil
    @State private var quickAddOnCreate: ((TeamPlayer) -> Void)? = nil
    @State private var chooseBattersSelection: Set<String> = []
    // Stamped onto PitchEvent.hitterId - derived automatically from
    // whichever jersey cell is selected (see the onChange below), not set
    // directly by any picker UI anymore. nil for an ephemeral "this game
    // only" cell with no roster link.
    private var selectedHitterId: String? { get { ui.selectedHitterId } nonmutating set { ui.selectedHitterId = newValue } }
    // Session-local roster-link annotation on top of the jersey grid's own
    // existing, persisted cell list - see addJerseyCellForRosterPlayer's
    // doc comment for why this doesn't survive a relaunch yet.
    @State private var hitterIdByJerseyCellId: [UUID: String] = [:]
    private var showAtBatAddMenu: Bool { get { ui.showAtBatAddMenu } nonmutating set { ui.showAtBatAddMenu = newValue } }
    private var showAtBatRosterPickerSheet: Bool { get { ui.showAtBatRosterPickerSheet } nonmutating set { ui.showAtBatRosterPickerSheet = newValue } }
    @State private var bufferedSharedHitterEvents: [BufferedHitterEvent] = []
    private var isRecordingResult: Bool { get { ui.isRecordingResult } nonmutating set { ui.isRecordingResult = newValue } }
    private var activeCalledPitchId: String? { get { ui.activeCalledPitchId } nonmutating set { ui.activeCalledPitchId = newValue } }
    @State private var deferredPendingPitch: Game.PendingPitch? = nil
    @State private var deferredDisplayCode: (colorName: String, code: String)? = nil
    private var actualLocationRecorded: String? { get { ui.actualLocationRecorded } nonmutating set { ui.actualLocationRecorded = newValue } }
    @State private var atBatCountCacheByBatter: [String: (balls: Int, strikes: Int)] = [:]
    private var resultVisualState: String? { get { ui.resultVisualState } nonmutating set { ui.resultVisualState = newValue } }
    private var pendingResultLabel: String? { get { ui.pendingResultLabel } nonmutating set { ui.pendingResultLabel = newValue } }
    /// Whether the coach has already answered (Reset doesn't count; No/Done do)
    /// the "estimate what was called" prompt for the current Catcher-mode
    /// pitch. Reset to false whenever a fresh catcher result location arrives.
    private var catcherEstimateDismissed: Bool { get { ui.catcherEstimateDismissed } nonmutating set { ui.catcherEstimateDismissed = newValue } }
    @State private var catcherEstimate: PitchCall? = nil
    private var catcherEstimateDraftPitch: String { get { ui.catcherEstimateDraftPitch } nonmutating set { ui.catcherEstimateDraftPitch = newValue } }
    private var catcherEstimateDraftLocation: String? { get { ui.catcherEstimateDraftLocation } nonmutating set { ui.catcherEstimateDraftLocation = newValue } }
    private var autoPitchOnlyEnabled: Bool { get { ui.autoPitchOnlyEnabled } nonmutating set { ui.autoPitchOnlyEnabled = newValue } }
    private var showResultConfirmation: Bool { get { ui.showResultConfirmation } nonmutating set { ui.showResultConfirmation = newValue } }
    @State private var isGameMode: Double = 1
    @StateObject var sessionManager = PitchSessionManager()
    @State private var modeSliderValue: Double = 1 // game only
    @State private var pitchEvents: [PitchEvent] = []
    @State private var games: [Game] = []
    /// Live games this account joined as a partner - kept separate from
    /// `games[]` because that array only ever holds games this account owns
    /// (see `currentGame`'s synthetic-Game fallback). Surfaced in the
    /// Settings "My Games" scroll so a partner can re-enter after leaving the
    /// screen, backgrounding, or closing the app, as long as the owner hasn't
    /// ended the session. Synced by `startListeningToJoinedLiveSessions()`.
    @State private var joinedLiveSessions: [JoinedLiveSession] = []
    @State private var joinedLiveSessionsListener: ListenerRegistration? = nil
    /// Guards `recordJoinedLiveSession`'s cosmetic refresh (opponent name,
    /// owner game id) to once per room instead of on every live-doc snapshot.
    private var joinedSessionDetailsSyncedForLiveId: String? { get { ui.joinedSessionDetailsSyncedForLiveId } nonmutating set { ui.joinedSessionDetailsSyncedForLiveId = newValue } }
    private var showPitchResults: Bool { get { ui.showPitchResults } nonmutating set { ui.showPitchResults = newValue } }
    private var showCardsFullScreenSheet: Bool { get { ui.showCardsFullScreenSheet } nonmutating set { ui.showCardsFullScreenSheet = newValue } }
    private var cardsEditTargetEventID: String? { get { ui.cardsEditTargetEventID } nonmutating set { ui.cardsEditTargetEventID = newValue } }
    @State private var sharedDeletedEventIDs: Set<String> = []
    @State private var sharedEditedEventOverrides: [String: PitchEvent] = [:]
    @State private var sharedPitcherOverrides: [String: String] = [:]
    @State private var sharedBatterJerseyOverrides: [String: String] = [:]
    private var showConfirmSheet: Bool { get { ui.showConfirmSheet } nonmutating set { ui.showConfirmSheet = newValue } }
    private var showUndoConfirm: Bool { get { ui.showUndoConfirm } nonmutating set { ui.showUndoConfirm = newValue } }
    @State private var calledPitchComposerDetent: PresentationDetent = .fraction(0.28)
    private var isStrikeSwinging: Bool { get { ui.isStrikeSwinging } nonmutating set { ui.isStrikeSwinging = newValue } }
    private var isStrikeLooking: Bool { get { ui.isStrikeLooking } nonmutating set { ui.isStrikeLooking = newValue } }
    private var isWildPitch: Bool { get { ui.isWildPitch } nonmutating set { ui.isWildPitch = newValue } }
    private var isPassedBall: Bool { get { ui.isPassedBall } nonmutating set { ui.isPassedBall = newValue } }
    private var isBall: Bool { get { ui.isBall } nonmutating set { ui.isBall = newValue } }
    private var isCalledPitchViewVisible: Bool { get { ui.isCalledPitchViewVisible } nonmutating set { ui.isCalledPitchViewVisible = newValue } }
    private var shouldBlurBackground: Bool { get { ui.shouldBlurBackground } nonmutating set { ui.shouldBlurBackground = newValue } }
    private var isGame: Bool { get { ui.isGame } nonmutating set { ui.isGame = newValue } }
    private var selectedOutcome: String? { get { ui.selectedOutcome } nonmutating set { ui.selectedOutcome = newValue } }
    private var selectedDescriptor: String? { get { ui.selectedDescriptor } nonmutating set { ui.selectedDescriptor = newValue } }
    @State private var pitchResultBannerPhase: PitchResultBannerPhase = .code
    private var isError: Bool { get { ui.isError } nonmutating set { ui.isError = newValue } }
    private var showGameSheet: Bool { get { ui.showGameSheet } nonmutating set { ui.showGameSheet = newValue } }
    private var showGameStatsSheet: Bool { get { ui.showGameStatsSheet } nonmutating set { ui.showGameStatsSheet = newValue } }
    private var showGameSummarySheet: Bool { get { ui.showGameSummarySheet } nonmutating set { ui.showGameSummarySheet = newValue } }
    private var showGameSummaryShareSheet: Bool { get { ui.showGameSummaryShareSheet } nonmutating set { ui.showGameSummaryShareSheet = newValue } }
    @State private var selectedGameSummaryPitcherSelection: String = allPitchersSummarySelection
    @State private var currentTrackingMode: TrackingMode = .coach
    private var opponentName: String? { get { ui.opponentName } nonmutating set { ui.opponentName = newValue } }
    private var selectedGameId: String? { get { ui.selectedGameId } nonmutating set { ui.selectedGameId = newValue } }
    // Participant overlay state
    private var showParticipantOverlay: Bool { get { ui.showParticipantOverlay } nonmutating set { ui.showParticipantOverlay = newValue } }
    private var ownerTemplateName: String? { get { ui.ownerTemplateName } nonmutating set { ui.ownerTemplateName = newValue } }
    
    @State private var jerseyCells: [JerseyCell] = sampleJerseyCells
    @State private var draggingJersey: JerseyCell?
    private var showAddJerseyPopover: Bool { get { ui.showAddJerseyPopover } nonmutating set { ui.showAddJerseyPopover = newValue } }
    private var newJerseyNumber: String { get { ui.newJerseyNumber } nonmutating set { ui.newJerseyNumber = newValue } }
    private var showBulkJerseyPrompt: Bool { get { ui.showBulkJerseyPrompt } nonmutating set { ui.showBulkJerseyPrompt = newValue } }
    private var showBulkJerseyInput: Bool { get { ui.showBulkJerseyInput } nonmutating set { ui.showBulkJerseyInput = newValue } }
    private var bulkJerseyNumbers: String { get { ui.bulkJerseyNumbers } nonmutating set { ui.bulkJerseyNumbers = newValue } }
    private var showDummyLineupInput: Bool { get { ui.showDummyLineupInput } nonmutating set { ui.showDummyLineupInput = newValue } }
    private var dummyLineupCount: String { get { ui.dummyLineupCount } nonmutating set { ui.dummyLineupCount = newValue } }
    private var showActivateNewBatterPrompt: Bool { get { ui.showActivateNewBatterPrompt } nonmutating set { ui.showActivateNewBatterPrompt = newValue } }
    @State private var pendingNewBatterActivation: JerseyCell? = nil
    @State private var selectedBatterId: UUID? = nil
    private var selectedBatterJersey: String? { get { ui.selectedBatterJersey } nonmutating set { ui.selectedBatterJersey = newValue } }
    @State private var jerseyDetailEvent: PitchEvent? = nil
    @State private var pendingJerseyDetailCell: JerseyCell? = nil
    private var showJerseyDetailSheet: Bool { get { ui.showJerseyDetailSheet } nonmutating set { ui.showJerseyDetailSheet = newValue } }
    private var showNoJerseyEventsAlert: Bool { get { ui.showNoJerseyEventsAlert } nonmutating set { ui.showNoJerseyEventsAlert = newValue } }
    private var noJerseyEventsMessage: String { get { ui.noJerseyEventsMessage } nonmutating set { ui.noJerseyEventsMessage = newValue } }
    private var showNextBatterAdjustmentAlert: Bool { get { ui.showNextBatterAdjustmentAlert } nonmutating set { ui.showNextBatterAdjustmentAlert = newValue } }
    private var nextBatterAdjustmentMessage: String { get { ui.nextBatterAdjustmentMessage } nonmutating set { ui.nextBatterAdjustmentMessage = newValue } }
    private var didAutoRetryJerseyDetail: Bool { get { ui.didAutoRetryJerseyDetail } nonmutating set { ui.didAutoRetryJerseyDetail = newValue } }
    @State private var jerseyDetailPayload: JerseyDetailPayload? = nil
    private var atBatPulse: Bool { get { ui.atBatPulse } nonmutating set { ui.atBatPulse = newValue } }
    private var showAtBatHeatmapSheet: Bool { get { ui.showAtBatHeatmapSheet } nonmutating set { ui.showAtBatHeatmapSheet = newValue } }
    private var selectedAtBatHeatmapPitch: String { get { ui.selectedAtBatHeatmapPitch } nonmutating set { ui.selectedAtBatHeatmapPitch = newValue } }
    @State private var atBatHeatmapResultFilter: BatterHeatmapResultFilter = .all
    @State private var pendingHeatmapCall: (pitch: String, location: String, isStrike: Bool)? = nil
    @State private var pendingAllPitchesHeatmapTap: (location: String, isStrike: Bool)? = nil
    private var showAllPitchesHeatmapPitchPicker: Bool { get { ui.showAllPitchesHeatmapPitchPicker } nonmutating set { ui.showAllPitchesHeatmapPitchPicker = newValue } }
    private var showHeatmapUnavailablePitchAlert: Bool { get { ui.showHeatmapUnavailablePitchAlert } nonmutating set { ui.showHeatmapUnavailablePitchAlert = newValue } }
    private var heatmapUnavailablePitchMessage: String { get { ui.heatmapUnavailablePitchMessage } nonmutating set { ui.heatmapUnavailablePitchMessage = newValue } }
    @State private var scoutObservedResult: ScoutObservedResult? = nil
    private var scoutInPlayOutcome: String? { get { ui.scoutInPlayOutcome } nonmutating set { ui.scoutInPlayOutcome = newValue } }
    private var scoutHitOnPlay: Bool { get { ui.scoutHitOnPlay } nonmutating set { ui.scoutHitOnPlay = newValue } }
    private var scoutDescriptor: String? { get { ui.scoutDescriptor } nonmutating set { ui.scoutDescriptor = newValue } }
    private var scoutErrorOnPlay: Bool { get { ui.scoutErrorOnPlay } nonmutating set { ui.scoutErrorOnPlay = newValue } }
    private var scoutMiscOutcome: String? { get { ui.scoutMiscOutcome } nonmutating set { ui.scoutMiscOutcome = newValue } }
    @State private var scoutZoneSelection: ScoutZoneSelection? = nil
    private var showScoutFieldMap: Bool { get { ui.showScoutFieldMap } nonmutating set { ui.showScoutFieldMap = newValue } }
    private var scoutBattedBallRegionName: String? { get { ui.scoutBattedBallRegionName } nonmutating set { ui.scoutBattedBallRegionName = newValue } }
    @State private var scoutBattedBallTapNormalized: CGPoint? = nil
    private struct SavedPlayReviewDraft: Identifiable {
        let id = UUID()
        let title: String
        let summaryLines: [String]
        let event: PitchEvent
    }

    @State private var savedPlayReviewDraft: SavedPlayReviewDraft? = nil
    private var savedPlayReviewTitle: String { get { ui.savedPlayReviewTitle } nonmutating set { ui.savedPlayReviewTitle = newValue } }
    @State private var savedPlayReviewSummaryLines: [String] = []
    private var savedPlayReviewCountText: String { get { ui.savedPlayReviewCountText } nonmutating set { ui.savedPlayReviewCountText = newValue } }
    @State private var savedPlayReviewEvent: PitchEvent? = nil
    @FocusState private var jerseyInputFocused: Bool
    
    @State private var editingCell: JerseyCell?
    private var showResetConfirm: Bool { get { ui.showResetConfirm } nonmutating set { ui.showResetConfirm = newValue } }
    // Removed @State private var isReset = false here as per instructions

    private var isReorderingMode: Bool { get { ui.isReorderingMode } nonmutating set { ui.isReorderingMode = newValue } }
    @State private var colorRefreshToken = UUID()
    private var hasPresentedInitialSettings: Bool { get { ui.hasPresentedInitialSettings } nonmutating set { ui.hasPresentedInitialSettings = newValue } }
    private var lastAuthenticatedUserId: String? { get { ui.lastAuthenticatedUserId } nonmutating set { ui.lastAuthenticatedUserId = newValue } }


    // Added according to instructions
    private var showTemplateChangeWarning: Bool { get { ui.showTemplateChangeWarning } nonmutating set { ui.showTemplateChangeWarning = newValue } }
    @State private var pendingTemplateSelection: PitchTemplate? = nil
    @State private var lastAppliedTemplateId: UUID? = nil
    // Tapping a game row sets these and dismisses showGameSheet rather than
    // entering the game immediately - doing both in one transaction is a
    // known SwiftUI race, which is what "create a game, tap into it, it
    // flashes and you can't get in" matched. showGameSheet's onDismiss
    // enters the game only once the sheet has actually finished dismissing.
    private var didLoadTemplates: Bool { get { ui.didLoadTemplates } nonmutating set { ui.didLoadTemplates = newValue } }
    private var keyPickedForActiveGame: Bool { get { ui.keyPickedForActiveGame } nonmutating set { ui.keyPickedForActiveGame = newValue } }
    private var pendingGameChoiceGameId: String? { get { ui.pendingGameChoiceGameId } nonmutating set { ui.pendingGameChoiceGameId = newValue } }
    private var pendingGameChoiceOwnerUid: String? { get { ui.pendingGameChoiceOwnerUid } nonmutating set { ui.pendingGameChoiceOwnerUid = newValue } }

    // Added per instructions:
    @State private var encryptedSelectionByGameId: [String: Bool] = [:]
    
    // Added progressRefreshToken as per instruction 1
    @State private var progressRefreshToken = UUID()

    fileprivate enum OverlayTab { case cards, progress }
    @State private var overlayTab: OverlayTab = .progress

    private enum ScoutObservedResult: String, CaseIterable, Identifiable {
        case ball
        case calledStrike
        case swingingStrike
        case foul
        case inPlay

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ball:
                return "Ball"
            case .calledStrike:
                return "Called Strike"
            case .swingingStrike:
                return "Swinging Strike"
            case .foul:
                return "Foul"
            case .inPlay:
                return "In Play"
            }
        }
    }

    private struct ScoutZoneSelection: Equatable {
        let label: String
        let isStrikeZone: Bool
    }

    enum DefaultsKeys {
        static let lastTemplateId = "lastTemplateId"
        static let lastBatterSide = "lastBatterSide"
        static let lastMode = "lastMode"
        static let activePitchesPrefix = "activePitches."
        static let lastView = "lastView"
        static let activeGameId = "activeGameId"
        static let lastPitcherId = "lastPitcherId"
        static let lastTemplateByGameId = "lastTemplateByGameId"
        static let lastPitcherByGameId = "lastPitcherByGameId"
        static let encryptedByGameId = "encryptedByGameId"
        static let activeGameOwnerUserId = "activeGameOwnerUserId"
        static let displayOnlyLiveId = "displayOnlyLiveId"
        static let displayOnlyMode = "displayOnlyMode"
        static let hiddenTemplateIds = "hiddenTemplateIds"
        static let hiddenPitcherIds = "hiddenPitcherIds"
        static let lastBackgroundAt = "lastBackgroundAt"
        static let forceSettingsOnNextLaunch = "forceSettingsOnNextLaunch"
        static let lastProgressByGameId = "lastProgressByGameId"
        static let didShowDisplayOnboarding = "didShowDisplayOnboarding"
        static let promptedTrackingModeLiveIds = "promptedTrackingModeLiveIds"
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
        /// Still written so older builds reading this cache keep working, but
        /// **no longer restored**: the revision belongs to a single live room,
        /// and carrying a stale floor across relaunches is exactly what made a
        /// device reject the partner's updates. See `progressRevision`.
        let progressRevision: Int?
        /// `outs` rides in the published live snapshot, so it has to survive a
        /// relaunch as well - otherwise a relaunched device keeps outs at 0 and
        /// republishes that 0 over the other device's real count.
        let outs: Int?
    }
    private var isSelecting: Bool { get { ui.isSelecting } nonmutating set { ui.isSelecting = newValue } }
    @State private var selectedEventIDs: Set<String> = []
    @State private var localTemplateOverrides: [String: String] = [:]
    private var pitchFirst: Bool { get { ui.pitchFirst } nonmutating set { ui.pitchFirst = newValue } }
    private var showCodeShareSheet: Bool { get { ui.showCodeShareSheet } nonmutating set { ui.showCodeShareSheet = newValue } }
    private var showCodeShareModePicker: Bool { get { ui.showCodeShareModePicker } nonmutating set { ui.showCodeShareModePicker = newValue } }
    @State private var codeShareInitialTab: Int = 0 // 0 = Generate, 1 = Enter
    private var inviteSheetDismissArmed: Bool { get { ui.inviteSheetDismissArmed } nonmutating set { ui.inviteSheetDismissArmed = newValue } }
    @State private var inviteSheetOpenedAt: Date? = nil
    private var showSelectGameFirstAlert: Bool { get { ui.showSelectGameFirstAlert } nonmutating set { ui.showSelectGameFirstAlert = newValue } }
    private var showCodeShareErrorAlert: Bool { get { ui.showCodeShareErrorAlert } nonmutating set { ui.showCodeShareErrorAlert = newValue } }
    private var codeShareErrorMessage: String { get { ui.codeShareErrorMessage } nonmutating set { ui.codeShareErrorMessage = newValue } }
    private var showGameEntryErrorAlert: Bool { get { ui.showGameEntryErrorAlert } nonmutating set { ui.showGameEntryErrorAlert = newValue } }
    private var gameEntryErrorMessage: String { get { ui.gameEntryErrorMessage } nonmutating set { ui.gameEntryErrorMessage = newValue } }
    private var shareCode: String { get { ui.shareCode } nonmutating set { ui.shareCode = newValue } }
    @AppStorage(DefaultsKeys.displayOnlyMode) private var isDisplayOnlyMode: Bool = false
    @AppStorage(DefaultsKeys.displayOnlyLiveId) private var displayOnlyLiveIdStorage: String = ""
    private var displayOnlyLiveId: String? { get { ui.displayOnlyLiveId } nonmutating set { ui.displayOnlyLiveId = newValue } }
    @State private var displayCodePayload: CodeDisplayOverlayPayload? = nil
    @State private var displayCodeClearWork: DispatchWorkItem? = nil
    @State private var displayListener: ListenerRegistration? = nil
    @State private var displayStateListener: ListenerRegistration? = nil
    @State private var displayHeartbeatTimer: Timer? = nil
    @State private var displaySessionListener: ListenerRegistration? = nil
    private var showSessionConflictAlert: Bool { get { ui.showSessionConflictAlert } nonmutating set { ui.showSessionConflictAlert = newValue } }
    private var showDisplayAppMissingAlert: Bool { get { ui.showDisplayAppMissingAlert } nonmutating set { ui.showDisplayAppMissingAlert = newValue } }
    private var sessionCheckInProgress: Bool { get { ui.sessionCheckInProgress } nonmutating set { ui.sessionCheckInProgress = newValue } }
    private var autoLiveCreateInProgress: Bool { get { ui.autoLiveCreateInProgress } nonmutating set { ui.autoLiveCreateInProgress = newValue } }
    private var didAutoCreateLiveSessionForGameId: String? { get { ui.didAutoCreateLiveSessionForGameId } nonmutating set { ui.didAutoCreateLiveSessionForGameId = newValue } }
    private var activeGameOwnerUserId: String? { get { ui.activeGameOwnerUserId } nonmutating set { ui.activeGameOwnerUserId = newValue } }
    @State private var gameListener: ListenerRegistration? = nil
    @State private var livePitchEventsListener: ListenerRegistration? = nil
    @State private var gamePitchEventsListener: ListenerRegistration? = nil
    @State private var gamePitchEvents: [PitchEvent] = []
    @State private var lastLocalProgressUpdate: Date? = nil
    /// Highest `progressRevision` this device has seen on the **live room
    /// document**. It replaces comparing a Firestore server timestamp against a
    /// local `Date()` - two different clocks, so any skew made the comparison
    /// wrong in one direction and let stale echoes overwrite live edits.
    ///
    /// This value is **server-assigned only**. It used to also be incremented
    /// locally in `markLocalProgressChange()`, which mixed two different number
    /// spaces into one comparison and made the owner silently ignore the
    /// partner's updates:
    ///
    /// - Recording one pitch calls `markLocalProgressChange()` several times in
    ///   a single run-loop turn (outcome → outs → count → batter advance), but
    ///   those are coalesced into **one** publish, so the server revision rose
    ///   by 1 while the local guess rose by 3-4.
    /// - Every progress change made with no live room open (`activeLiveId ==
    ///   nil`) bumped the local guess with no server counterpart at all.
    /// - The inflated value was then persisted per game and restored on relaunch.
    ///
    /// Once the local value ran ahead, `remoteRevision > progressRevision`
    /// rejected the partner's next N snapshots outright - the reported symptom
    /// of ball/strike circles that fail to fill in or fail to clear on the
    /// owner's device after a partner records a pitch. Protection for local
    /// changes that have not reached the room yet now comes from
    /// `hasUnpublishedLocalProgress` instead, which does not pollute the
    /// revision comparison.
    @State private var progressRevision: Int = 0
    /// The live room `progressRevision` was read from. A freshly created room
    /// has no `progressRevision` field, so its first commit lands at 1; a floor
    /// carried over from a previous room would swallow the partner's first
    /// updates in the new one.
    private var progressRevisionRoomId: String? { get { ui.progressRevisionRoomId } nonmutating set { ui.progressRevisionRoomId = newValue } }
    /// Bumped by every local progress mutation. `publishedLocalProgressToken`
    /// trails it until the corresponding publish reports back, which is how
    /// `hasUnpublishedLocalProgress` knows this device is holding newer state.
    @State private var localProgressChangeToken: Int = 0
    @State private var publishedLocalProgressToken: Int = 0
    @State private var lastUnpublishedProgressChangeAt: Date? = nil
    private var progressPublishScheduled: Bool { get { ui.progressPublishScheduled } nonmutating set { ui.progressPublishScheduled = newValue } }
    @State private var bufferedSharedPitcherEvents: [BufferedPitcherEvent] = []
    private var lastObservedResultSelectionId: String? { get { ui.lastObservedResultSelectionId } nonmutating set { ui.lastObservedResultSelectionId = newValue } }
    @State private var codeShareSheetID = UUID()
    // MARK: - Startup gating (prevents sheet-flash on launch)

    private enum StartupPhase { case launching, ready }
    private struct BufferedPitcherEvent: Codable {
        let pitcherId: String
        let event: PitchEvent
    }
    // Deliberately a separate, parallel type/buffer rather than generalizing
    // BufferedPitcherEvent - this mirror pipeline already has several
    // battle-tested, multi-call-site lifecycle hooks (flush on disconnect/
    // background/end-session); duplicating the small mechanical buffer is
    // lower-risk than refactoring shared infra underneath the working
    // pitcher path.
    private struct BufferedHitterEvent: Codable {
        let hitterId: String
        let event: PitchEvent
    }

    @State private var startupPhase: StartupPhase = .launching
    private var isRestoringState: Bool { get { ui.isRestoringState } nonmutating set { ui.isRestoringState = newValue } }

    // ✅ Live-room mirrored scoreboard fields (used when activeLiveId != nil)
    @State private var balls: Int = 0
    @State private var strikes: Int = 0
    @State private var outs: Int = 0
    private var showOutsFlash: Bool { get { ui.showOutsFlash } nonmutating set { ui.showOutsFlash = newValue } }
    @State private var inning: Int = 1
    @State private var hits: Int = 0
    @State private var walks: Int = 0
    @State private var us: Int = 0
    @State private var them: Int = 0
    @State private var heartbeatTimer: Timer? = nil
    private var isJoiningSession: Bool { get { ui.isJoiningSession } nonmutating set { ui.isJoiningSession = newValue } }
    private var pendingRestoreGameId: String? { get { ui.pendingRestoreGameId } nonmutating set { ui.pendingRestoreGameId = newValue } }
    private var pendingLiveTemplateId: String? { get { ui.pendingLiveTemplateId } nonmutating set { ui.pendingLiveTemplateId = newValue } }
    private var pendingLiveTemplateName: String? { get { ui.pendingLiveTemplateName } nonmutating set { ui.pendingLiveTemplateName = newValue } }
    private var liveTemplateOverrideLocked: Bool { get { ui.liveTemplateOverrideLocked } nonmutating set { ui.liveTemplateOverrideLocked = newValue } }
    @State private var pendingOutsResetWorkItem: DispatchWorkItem? = nil
    private var lastOutResetEventIdentity: String? { get { ui.lastOutResetEventIdentity } nonmutating set { ui.lastOutResetEventIdentity = newValue } }
    @State private var lastOutResetPreviousOuts: Int? = nil

    private func dismissAllTopLevelSheets() {
        showGameSheet = false
        showCodeShareSheet = false
        showCodeAssignmentSheet = false
        // NOTE: do NOT touch confirmSheetBinding/showConfirmSheet here unless you truly want to cancel it.
    }

    private func presentExclusive(settings: Bool = false, game: Bool = false) {
        dismissAllTopLevelSheets()
        if settings { activeHomeArea = .home }
        else if game { showGameSheet = true }
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

            // The cells are back, so their roster links - and the two side
            // rosters those links are matched against - have to come back
            // too, or the At Bat scroll can't tell the two sides apart.
            self.mergeHitterLinks(from: local)
            self.loadSideContext(for: local)

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
                debugLog("❌ hydrateChosenGameUI getDocument error:", err)
                return
            }
            guard let snap, snap.exists else {
                debugLog("⚠️ hydrateChosenGameUI missing game doc:", ref.path)
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

                    self.mergeHitterLinks(from: game)
                    self.loadSideContext(for: game)

                    self.selectedBatterId = nil
                    self.ownerTemplateName = self.selectedTemplate?.name
                    self.showParticipantOverlay = !self.isOwnerForActiveGame

                    // Participants never get a continuous listener on the
                    // owner's game doc (startListeningToActiveGame bails for
                    // them), so this one-time fetch is the only place that
                    // can seed games[] for them. Without this, currentGame
                    // (games.first(where: id==selectedGameId)) never resolves
                    // and any sheet gated on it — Pitcher Stats, Game Summary —
                    // is stuck on its "Loading stats…" fallback forever.
                    if let idx = self.games.firstIndex(where: { $0.id == game.id }) {
                        self.games[idx] = game
                    } else {
                        self.games.append(game)
                    }

                } catch {
                    debugLog("❌ hydrateChosenGameUI decode error:", error)
                }
            }
        }
    }

    private var effectiveGameOwnerUserId: String? {
        if isDemoMode { return Self.demoUserId }
        if let host = activeGameOwnerUserId, !host.isEmpty { return host }
        // In game mode, unknown owner must not fall back to self; that can
        // incorrectly flip participant UI/permissions into owner behavior.
        if isGame { return nil }
        return authManager.user?.uid
    }

    private var isOwnerForActiveGame: Bool {
        if isDemoMode { return true }
        guard let me = authManager.user?.uid,
              let owner = effectiveGameOwnerUserId else { return false }
        return me == owner
    }

    private var canInitiateCall: Bool {
        return isGame && isOwnerForActiveGame
    }

    private func markTrackingModePrompted(forLiveId liveId: String) {
        promptedTrackingModeLiveIds.insert(liveId)
        UserDefaults.standard.set(Array(promptedTrackingModeLiveIds), forKey: DefaultsKeys.promptedTrackingModeLiveIds)
    }

    private func handleSetCalledPitch(_ newCall: PitchCall?) {
        calledPitch = newCall
        showConfirmSheet = (newCall != nil)
        isRecordingResult = (newCall != nil)
        if newCall != nil {
            calledPitchComposerDetent = (newCall?.pitch == "Catcher") ? .large : .fraction(0.28)
        }
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
        isRecordingResult = true
        
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
            debugLog("⚠️ No activeLiveId — deferring pending write until live session exists.")
            return
        }

        do {
            let pendingData = try Firestore.Encoder().encode(pending)
            LiveGameService.shared.updateLiveFields(liveId: liveId, fields: [
                "pending": pendingData,
                "displayCode": FieldValue.delete()
            ]) { err in
                if let err { debugLog("❌ pending update error:", err.localizedDescription) }
            }
        } catch {
            debugLog("❌ encode pending failed:", error)
        }


    }

    private func refreshCalledPitchForSelectedPitch() {
        guard let currentCall = calledPitch else { return }

        let selected = selectedPitch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return }

        let fullLabel = "\(currentCall.isStrike ? "Strike" : "Ball") \(currentCall.location)"
        let refreshedCodes: [String] = {
            if let template = selectedTemplate, useEncrypted(for: template) {
                if let (gridKind, columnIndex, rowIndex) = mapLabelToGridInfo(
                    label: currentCall.location,
                    isStrike: currentCall.isStrike
                ) {
                    if template.codeMode == .normal {
                        return EncryptedCodeGenerator.generateNormalCalls(
                            template: template,
                            selectedPitch: selected,
                            gridKind: gridKind,
                            columnIndex: columnIndex,
                            rowIndex: rowIndex
                        )
                    }
                    return EncryptedCodeGenerator.generateCalls(
                        template: template,
                        selectedPitch: selected,
                        gridKind: gridKind,
                        columnIndex: columnIndex,
                        rowIndex: rowIndex
                    )
                }
                return []
            }

            return pitchCodeAssignments
                .filter { $0.pitch == selected && $0.location == fullLabel }
                .map(\.code)
        }()

        let updatedCall = PitchCall(
            pitch: selected,
            location: currentCall.location,
            isStrike: currentCall.isStrike,
            codes: refreshedCodes
        )

        if isGame, isOwnerForActiveGame {
            handleSetCalledPitch(updatedCall)
        } else {
            calledPitch = updatedCall
        }
    }

    private func mapLabelToGridInfo(label: String, isStrike: Bool) -> (gridKind: EncryptedGridKind, columnIndex: Int, rowIndex: Int)? {
        let cleaned = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let strikeRows = [
            ["Up & Out", "Up", "Up & In"],
            ["Out", "Middle", "In"],
            ["↓ & Out", "↓", "↓ & In"]
        ]
        let ballRows = [
            ["Up & Out", "Up", "Up & In"],
            ["Out", "", "In"],
            ["↓ & Out", "↓", "↓ & In"]
        ]
        let rows = isStrike ? strikeRows : ballRows
        let kind: EncryptedGridKind = isStrike ? .strikes : .balls

        for (r, row) in rows.enumerated() {
            for (c, value) in row.enumerated() {
                if value == cleaned {
                    if !isStrike && value.isEmpty { return nil }
                    return (kind, c, r)
                }
            }
        }
        return nil
    }
    private func applyPendingFromLiveData(_ data: [String: Any]) {
        guard isGame else { return }

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
        if currentTrackingMode != .coach {
            currentTrackingMode = .coach
        }
        showConfirmSheet = true
        calledPitchComposerDetent = .fraction(0.28)

        activeCalledPitchId = callId
        isRecordingResult = true
    }

    private func expandCalledPitchComposerToLarge() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard calledPitch != nil else { return }
            calledPitchComposerDetent = .large
        }
    }

    private func applyResultSelectionFromLiveData(_ data: [String: Any]) {
        guard isGame else { return }

        guard let sel = data["resultSelection"] as? [String: Any] else { return }
        let label = (sel["label"] as? String) ?? ""

        // Keep listening to result selection, but do not auto-expand the composer.
        // Expansion should happen only from explicit user result-location taps.
        _ = label
    }
    /// Owner-side: keep CalledPitchView in sync with the shared live doc.
    /// When the participant saves, they delete `pending` from /liveGames/{liveId},
    /// so the owner should dismiss their CalledPitchView automatically.
    private func syncOwnerCallStateFromLiveData(_ data: [String: Any]) {
        guard isGame else { return }

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
            if showConfirmSheet { return }
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
            debugLog("🔆 pendingResultLabel seeded from Firestore=", resolvedLabel)
        } else {
            // Keep whatever the participant selected
            // debugLog("🔆 keeping local pendingResultLabel=", pendingResultLabel ?? "nil")
        }

        calledPitch = PitchCall(
            pitch: pitch,
            location: loc,
            isStrike: pending.isStrike ?? true,
            codes: [] // joiner never sees codes
        )
        if currentTrackingMode != .coach {
            currentTrackingMode = .coach
        }

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

        if isDemoMode {
            debugLog("Demo mode: pitch event kept local only.")
        } else if let liveId = activeLiveId {
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
        guard let uid = authManager.user?.uid, !uid.isEmpty else { return }
        let db = Firestore.firestore()
        db.collection("liveGames").document(liveId)
            .collection("participants").document(uid)
            .setData([
                "uid": uid,
                "joinedAt": FieldValue.serverTimestamp(),
                "lastSeenAt": FieldValue.serverTimestamp()
            ], merge: true)

        // Only participant devices should claim the live `connection` state.
        // If owner writes this field too, invite UI can auto-dismiss from a fake connect event.
        guard !isOwnerForActiveGame else { return }
        LiveGameService.shared.updateLiveFields(
            liveId: liveId,
            fields: [
                "connection": [
                    "participantUid": uid,
                    "connected": true,
                    "connectedAt": FieldValue.serverTimestamp()
                ]
            ]
        )
    }

    private func seedLivePitchEventsOnce(liveId: String) {
        guard gamePitchEvents.isEmpty else { return }

        let ref = Firestore.firestore()
            .collection("liveGames").document(liveId)
            .collection("pitchEvents")
            .order(by: "timestamp", descending: false)

        ref.getDocuments { snap, err in
            if let err {
                debugLog("❌ seed live pitchEvents failed:", err.localizedDescription)
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

        // A fresh listener replays the whole collection as `.added`, and the
        // mirror below skips ids it has already seen. Anything edited or
        // reassigned while the listener was detached would therefore arrive as
        // an `.added` that gets skipped and never reaches the owner's record -
        // the exact staleness the documentChanges mirror exists to prevent.
        // This function is restarted from several places independently of
        // startListeningToLiveGame, so the seen-set has to be dropped here too.
        // Re-mirroring an unchanged event is an idempotent setData; losing an
        // edit is not.
        mirroredLivePitchEventIds.removeAll()

        let ref = Firestore.firestore()
            .collection("liveGames").document(liveId)
            .collection("pitchEvents")
            .order(by: "timestamp", descending: false)

        debugLog("👂 live pitchEvents listener start liveId=\(liveId)")

        livePitchEventsListener = ref.addSnapshotListener { snap, err in
            if let err = err {
                debugLog("❌ Live pitchEvents listener error:", err.localizedDescription)
                return
            }
            guard let docs = snap?.documents else {
                debugLog("⚠️ Live pitchEvents snapshot has no documents")
                return
            }

            debugLog("🧾 Live pitchEvents snapshot count=\(docs.count) isOwner=\(self.isOwnerForActiveGame) activeLiveId=\(self.activeLiveId ?? "<nil>") selectedGameId=\(self.selectedGameId ?? "<nil>") ownerUid=\(self.effectiveGameOwnerUserId ?? self.activeGameOwnerUserId ?? "<nil>")")

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

                // Deletions must be pruned from the seeded backfill as well, and
                // before the merge below. `seededGamePitchEventsForLive` is
                // filled once from the owner's pre-live history and only cleared
                // on teardown, so mergeLiveAndSeededEvents would otherwise
                // re-add a just-deleted pitch from the stale seed array and the
                // card would reappear on the very next snapshot. Applies to both
                // roles, so it sits outside the owner-only mirror below.
                let removedEventIds = Set(
                    (snap?.documentChanges ?? [])
                        .filter { $0.type == .removed }
                        .map(\.document.documentID)
                )
                if !removedEventIds.isEmpty {
                    self.seededGamePitchEventsForLive.removeAll { event in
                        guard let id = event.id else { return false }
                        return removedEventIds.contains(id)
                    }
                }

                let combined = self.mergeLiveAndSeededEvents(liveEvents: events)
                if !combined.isEmpty {
                    self.gamePitchEvents = combined
                } else {
                    debugLog("⚠️ Live merge produced 0 events (seeded=\(self.seededGamePitchEventsForLive.count), live=\(events.count))")
                }

                // ✅ OWNER ONLY: mirror live events into owner’s real game doc
                guard self.isOwnerForActiveGame,
                      let ownerUid = self.effectiveGameOwnerUserId, !ownerUid.isEmpty,
                      let gameId = self.selectedGameId, !gameId.isEmpty
                else { return }

                // Modifications and removals have to be mirrored too, not just
                // insertions. A participant only has *create* access to
                // users/{owner}/games/{gid}/pitchEvents (see firestore.rules),
                // so when they edit an outcome, reassign a pitcher/jersey, or
                // undo a pitch, that change can only land in /liveGames - and
                // this loop is the sole path by which it reaches the owner's
                // permanent record. Keying purely off "have I already seen this
                // id" froze the owner's copy at the event's first-written state
                // for the rest of the session.
                let gameEventsRef = Firestore.firestore()
                    .collection("users").document(ownerUid)
                    .collection("games").document(gameId)
                    .collection("pitchEvents")

                for change in snap?.documentChanges ?? [] {
                    let liveEventId = change.document.documentID
                    let dst = gameEventsRef.document(liveEventId)

                    // The owner's device is also the only one that can keep
                    // /pitchers/{id}/pitchEvents in step during a live session.
                    // A code-joined partner is neither the pitcher's owner nor
                    // in its sharedWith list, so their own attempt is dropped
                    // client-side (saveSharedPitcherEventIfAllowed) and would
                    // be denied by rules anyway - which left every pitch the
                    // partner recorded out of the pitcher's career stats.
                    let pitcherDst: DocumentReference? = {
                        let raw = change.document.data()["pitcherId"] as? String
                        guard let pid = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !pid.isEmpty
                        else { return nil }
                        return Firestore.firestore()
                            .collection("pitchers").document(pid)
                            .collection("pitchEvents").document(liveEventId)
                    }()

                    // Same reasoning as pitcherDst above, for a linked batter:
                    // a code-joined partner has no write access to
                    // /hitters/{id}/pitchEvents (ownerUid-only rules), so the
                    // owner's device is the only place this copy can be kept
                    // in step.
                    let hitterDst: DocumentReference? = {
                        let raw = change.document.data()["hitterId"] as? String
                        guard let hid = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !hid.isEmpty
                        else { return nil }
                        return Firestore.firestore()
                            .collection("hitters").document(hid)
                            .collection("pitchEvents").document(liveEventId)
                    }()

                    if change.type == .removed {
                        self.mirroredLivePitchEventIds.remove(liveEventId)
                        dst.delete { err in
                            if let err {
                                debugLog("❌ mirror live pitchEvent delete failed:", err.localizedDescription)
                            } else {
                                debugLog("🗑️ mirrored live pitchEvent delete → users/\(ownerUid)/games/\(gameId)/pitchEvents/\(liveEventId)")
                            }
                        }
                        pitcherDst?.delete { err in
                            if let err {
                                debugLog("❌ mirror pitcher pitchEvent delete failed:", err.localizedDescription)
                            }
                        }
                        hitterDst?.delete { err in
                            if let err {
                                debugLog("❌ mirror hitter pitchEvent delete failed:", err.localizedDescription)
                            }
                        }
                        continue
                    }

                    // Skip only re-adds of events already mirrored (listener
                    // restarts replay the whole collection as .added); a
                    // .modified always rewrites.
                    if change.type == .added, self.mirroredLivePitchEventIds.contains(liveEventId) { continue }
                    self.mirroredLivePitchEventIds.insert(liveEventId)

                    var data = change.document.data()

                    // Ensure required fields exist for game storage / rules
                    data["gameId"] = gameId

                    // seedLivePitchEventsFromOwnerGameIfNeeded rewrites
                    // createdByUid to the owner so its backfill passes the
                    // live-room create rule, stashing the real author in
                    // originalCreatedByUid. Restore it so the permanent record
                    // keeps the partner's attribution instead of the owner's.
                    if let original = (data["originalCreatedByUid"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !original.isEmpty {
                        data["createdByUid"] = original
                    }
                    if data["createdByUid"] == nil {
                        data["createdByUid"] = ownerUid
                    }

                    dst.setData(data, merge: false) { err in
                        if let err {
                            debugLog("❌ mirror live pitchEvent failed:", err.localizedDescription)
                        } else {
                            debugLog("✅ mirrored live pitchEvent → users/\(ownerUid)/games/\(gameId)/pitchEvents/\(liveEventId)")
                        }
                    }

                    if let pitcherDst {
                        // The pitcher-copy create rule requires the writer to
                        // own the row it writes, so stamp this device's uid and
                        // keep the true author beside it.
                        var pitcherData = data
                        if let author = data["createdByUid"] as? String, author != ownerUid {
                            pitcherData["originalCreatedByUid"] = author
                        }
                        pitcherData["createdByUid"] = ownerUid
                        pitcherDst.setData(pitcherData, merge: false) { err in
                            if let err {
                                debugLog("❌ mirror pitcher pitchEvent failed:", err.localizedDescription)
                            } else {
                                debugLog("✅ mirrored pitcher pitchEvent → \(pitcherDst.path)")
                            }
                        }
                    }

                    if let hitterDst {
                        var hitterData = data
                        if let author = data["createdByUid"] as? String, author != ownerUid {
                            hitterData["originalCreatedByUid"] = author
                        }
                        hitterData["createdByUid"] = ownerUid
                        hitterDst.setData(hitterData, merge: false) { err in
                            if let err {
                                debugLog("❌ mirror hitter pitchEvent failed:", err.localizedDescription)
                            } else {
                                debugLog("✅ mirrored hitter pitchEvent → \(hitterDst.path)")
                            }
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
                debugLog("❌ Game listener error:", err.localizedDescription)
                return
            }
            guard let snap, snap.exists else {
                debugLog("⚠️ Game doc missing while listening:", ref.path)
                // The doc is really gone (deleted, or its cascade delete ran
                // while this was the active game) - not a transient cache
                // miss, since a snapshot listener attached right after this
                // same game was just created already sees the pending local
                // write as existing. Previously this just logged and left
                // isGame=true with nothing ever populating the tracker -
                // indistinguishable from "entering a game does nothing."
                // Bounce back out to the chooser instead of stranding the
                // user on a blank screen for a game that no longer exists.
                DispatchQueue.main.async {
                    self.handleActiveGameDocMissing(gameId: gid)
                }
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
                            debugLog("🧭[PROG] gameSnap APPLY gid=\(gid) snapStamp=\(String(describing: updated.progressUpdatedAt)) localStamp=\(String(describing: self.lastLocalProgressUpdate)) snap=\(updated.balls)/\(updated.strikes)/\(updated.inning)/\(updated.hits)/\(updated.walks)/\(updated.us)/\(updated.them)")
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
                            debugLog("🧭[PROG] gameSnap SKIP gid=\(gid) snapStamp=\(String(describing: updated.progressUpdatedAt)) localStamp=\(String(describing: self.lastLocalProgressUpdate)) keep=\(self.balls)/\(self.strikes)/\(self.inning)/\(self.hits)/\(self.walks)/\(self.us)/\(self.them)")
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
                debugLog("❌ decode Game failed:", error)
            }
        }
    }

    /// Exits game mode back to the chooser when the active game's own
    /// document has been deleted out from under its listener - see the call
    /// site in `startListeningToActiveGame`.
    private func handleActiveGameDocMissing(gameId: String) {
        // The user may have already moved on (switched games, left game mode)
        // by the time this async callback lands - don't clobber whatever is
        // current if it's no longer about this game.
        guard selectedGameId == gameId else { return }

        gameListener?.remove()
        gameListener = nil
        games.removeAll(where: { $0.id == gameId })

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: DefaultsKeys.activeGameId)
        defaults.removeObject(forKey: DefaultsKeys.activeGameOwnerUserId)

        selectedGameId = nil
        activeGameOwnerUserId = nil
        isGame = false

        gameEntryErrorMessage = "That game no longer exists (it may have been deleted). Pick another game to continue."
        showGameEntryErrorAlert = true
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
                debugLog("❌ Game pitchEvents listener error:", err.localizedDescription)
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
    private var activeLiveId: String? { get { ui.activeLiveId } nonmutating set { ui.activeLiveId = newValue } }
    private var livePitcherId: String? { get { ui.livePitcherId } nonmutating set { ui.livePitcherId = newValue } }
    private var livePitcherName: String? { get { ui.livePitcherName } nonmutating set { ui.livePitcherName = newValue } }
    private var didHydrateLineupFromLive: Bool { get { ui.didHydrateLineupFromLive } nonmutating set { ui.didHydrateLineupFromLive = newValue } }
    private var didSeedOwnerGameEventsForLive: Bool { get { ui.didSeedOwnerGameEventsForLive } nonmutating set { ui.didSeedOwnerGameEventsForLive = newValue } }
    private var didSeedLivePitchEventsFromOwnerGame: Bool { get { ui.didSeedLivePitchEventsFromOwnerGame } nonmutating set { ui.didSeedLivePitchEventsFromOwnerGame = newValue } }
    @State private var seededGamePitchEventsForLive: [PitchEvent] = []
    @State private var participantsListener: ListenerRegistration? = nil
    private var liveSessionRenewalInFlight: Bool { get { ui.liveSessionRenewalInFlight } nonmutating set { ui.liveSessionRenewalInFlight = newValue } }

    private func seedOwnerGamePitchEventsForLiveIfNeeded() {
        guard activeLiveId != nil else { return }
        guard isOwnerForActiveGame else { return }
        guard !didSeedOwnerGameEventsForLive else { return }
        guard let owner = (effectiveGameOwnerUserId ?? activeGameOwnerUserId),
              let gid = selectedGameId
        else {
            debugLog("⚠️ seedOwnerGamePitchEventsForLiveIfNeeded missing owner/gid")
            return
        }

        let ref = Firestore.firestore()
            .collection("users").document(owner)
            .collection("games").document(gid)
            .collection("pitchEvents")
            .order(by: "timestamp", descending: false)

        ref.getDocuments { snap, err in
            if let err {
                debugLog("❌ seed owner game pitchEvents failed:", err.localizedDescription)
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

                debugLog("✅ seeded owner game pitchEvents count=\(events.count)")

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
            debugLog("⚠️ seedLivePitchEventsFromOwnerGameIfNeeded missing owner/gid/liveId")
            return
        }

        let source = Firestore.firestore()
            .collection("users").document(owner)
            .collection("games").document(gid)
            .collection("pitchEvents")
            .order(by: "timestamp", descending: false)

        source.getDocuments { snap, err in
            if let err {
                debugLog("❌ seed live pitchEvents from owner game failed:", err.localizedDescription)
                return
            }

            let docs = snap?.documents ?? []
            guard !docs.isEmpty else {
                debugLog("⚠️ seed live pitchEvents: owner game has 0 events")
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
                    debugLog("❌ seed live pitchEvents batch failed:", err.localizedDescription)
                } else {
                    DispatchQueue.main.async {
                        self.didSeedLivePitchEventsFromOwnerGame = true
                    }
                    debugLog("✅ seeded live pitchEvents from owner game history count=\(docs.count)")
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

        // `progressRevision` is scoped to one room. A newly created room carries
        // no `progressRevision` field at all, so its first commit lands at 1 -
        // a floor left over from a previous room would make this device reject
        // the partner's opening updates. Only reset when the room actually
        // changes: this function restarts for the *same* room from several call
        // sites, and zeroing there would re-apply room state over a local change.
        if progressRevisionRoomId != liveId {
            progressRevision = 0
            progressRevisionRoomId = liveId
        }

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
                debugLog("❌ Live listener error:", err)
                DispatchQueue.main.async {
                    if self.activeLiveId == liveId {
                        self.uiConnected = false
                        if self.isOwnerForActiveGame {
                            self.endLiveSessionLocally(keepCurrentGame: false)
                        }
                    }
                }
                return
            }
            guard let snap, snap.exists, let data = snap.data() else {
                debugLog("⚠️ Live game doc missing:", ref.path)
                DispatchQueue.main.async {
                    if self.activeLiveId == liveId {
                        self.uiConnected = false
                        if self.isOwnerForActiveGame {
                            self.endLiveSessionLocally(keepCurrentGame: false)
                        } else {
                            // The room itself is gone, not just unreachable -
                            // nothing left to re-enter.
                            LiveGameService.shared.removeJoinedLiveSession(liveId: liveId)
                            self.endLiveSessionLocally(keepCurrentGame: false)
                        }
                    }
                }
                return
            }

            DispatchQueue.main.async {
                let liveStamp = (data["progressUpdatedAt"] as? Timestamp)?.dateValue()
                let remoteRevision = data["progressRevision"] as? Int
                let shouldApplyLiveProgress: Bool
                if self.hasUnpublishedLocalProgress {
                    // This device changed the count/outs and that change has not
                    // reached the room yet, so every snapshot in flight - even a
                    // higher-revision one - predates it.
                    shouldApplyLiveProgress = false
                } else if let remoteRevision {
                    // Only accept a snapshot strictly newer than the highest
                    // revision the *server* has handed this device.
                    shouldApplyLiveProgress = remoteRevision > self.progressRevision
                    if shouldApplyLiveProgress {
                        self.progressRevision = max(self.progressRevision, remoteRevision)
                    }
                } else {
                    // Rooms written by an older build carry no revision, so fall
                    // back to the previous timestamp comparison for them.
                    shouldApplyLiveProgress = self.shouldApplyProgressFromSnapshot(liveStamp)
                        || self.lastLocalProgressUpdate == nil
                }
                if shouldApplyLiveProgress {
                    self.balls   = data["balls"]   as? Int ?? self.balls
                    self.strikes = data["strikes"] as? Int ?? self.strikes
                    self.inning  = data["inning"]  as? Int ?? self.inning
                    self.hits    = data["hits"]    as? Int ?? self.hits
                    self.walks   = data["walks"]   as? Int ?? self.walks
                    self.us      = data["us"]      as? Int ?? self.us
                    self.them    = data["them"]    as? Int ?? self.them
                    self.outs    = data["outs"]    as? Int ?? self.outs
                    if let liveStamp {
                        self.lastLocalProgressUpdate = liveStamp
                    }
                } else {
                    debugLog("🧭[PROG] liveSnap SKIP remoteRev=\(String(describing: remoteRevision)) localRev=\(self.progressRevision) pendingLocal=\(self.hasUnpublishedLocalProgress) remote=\(data["balls"] as? Int ?? -1)/\(data["strikes"] as? Int ?? -1) local=\(self.balls)/\(self.strikes)")
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
                    self.livePitcherName = data["pitcherName"] as? String
                } else {
                    self.livePitcherId = nil
                    self.livePitcherName = nil
                }

                self.renewLiveSessionIfExpiringSoon(liveId: liveId, data: data)

                // `uiConnected` belongs to the participants listener, which
                // derives it from heartbeat freshness. It used to be reassigned
                // here from `connection.connected` too, so every unrelated
                // live-doc write - every called pitch, every progress update -
                // re-ran this and could stomp the heartbeat's answer. That flag
                // also gates shouldWriteSharedPitcherEventImmediately, so a
                // false reading quietly diverted pitcher events into the
                // on-disk buffer instead of Firestore.
                //
                // Do not forcibly end the participant's live session only because
                // `connection.connected` is false; heartbeat-based participants listener
                // is the source of truth for reconnect visibility.
                if self.inviteSheetDismissArmed,
                   self.isOwnerForActiveGame,
                   self.showCodeShareSheet,
                   self.codeShareInitialTab == 0,
                   let connection = data["connection"] as? [String: Any],
                   let participantUid = connection["participantUid"] as? String,
                   !participantUid.isEmpty,
                   let connected = connection["connected"] as? Bool,
                   connected {
                    let connectedAt = (connection["connectedAt"] as? Timestamp)?.dateValue()
                    let openedAt = self.inviteSheetOpenedAt ?? .distantPast
                    if let connectedAt, connectedAt >= openedAt {
                        self.showCodeShareSheet = false
                        self.showCodeShareModePicker = false
                        self.inviteSheetDismissArmed = false
                    }
                }

                // ✅ LIVE TEMPLATE FLOW: apply owner's template on participant (and keep owner consistent too)
                let liveTemplateId = data["templateId"] as? String
                let liveTemplateName = data["templateName"] as? String
                self.pendingLiveTemplateId = liveTemplateId
                self.pendingLiveTemplateName = liveTemplateName
                self.applyPendingLiveTemplateIfPossible()
                let previousSelectedBatterId = self.selectedBatterId

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

                if previousSelectedBatterId != self.selectedBatterId {
                    self.syncCountFromComposer(balls: 0, strikes: 0)
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
                    debugLog("🔌 Live session ended remotely → disconnecting")

                    self.uiConnected = false
                    if !self.isOwnerForActiveGame {
                        LiveGameService.shared.removeJoinedLiveSession(liveId: liveId)
                    }
                    self.endLiveSessionLocally(keepCurrentGame: self.isOwnerForActiveGame)
                    return
                }
                let notExpired: Bool = {
                    if let exp = data["expiresAt"] as? Timestamp {
                        return exp.dateValue() > Date()
                    }
                    return true
                }()

                // A participant's device never renews `expiresAt` - rules pin
                // that write to the owner - so if the owner's app isn't open
                // to renew inside the 45-min `renewalWindow` and the room
                // genuinely expires, called pitches silently stop arriving.
                // Treat that the same as an explicit "End Live Session" for
                // the participant: tear the session down locally and drop it
                // from their games list. The owner's own device is left
                // alone here - `renewLiveSessionIfExpiringSoon` above already
                // renews before this point while the owner's app is open.
                if !notExpired, !self.isOwnerForActiveGame {
                    debugLog("⏰ Live session expired (unrenewed) → disconnecting participant")
                    self.uiConnected = false
                    LiveGameService.shared.removeJoinedLiveSession(liveId: liveId)
                    self.endLiveSessionLocally(keepCurrentGame: false)
                    return
                }

                let liveIsActive = (activeLiveId != nil) && (liveStatus == "active") && notExpired

                if liveIsActive {
                    let snapshotOwnerUid = (data["ownerUid"] as? String) ?? self.activeGameOwnerUserId
                    let amOwnerForSnapshot = snapshotOwnerUid == self.authManager.user?.uid
                    if amOwnerForSnapshot {
                        self.syncOwnerCallStateFromLiveData(data)
                    } else {
                        self.applyPendingFromLiveData(data)
                        // Keep the games-scroll bookmark's cosmetic fields
                        // (opponent name, owner game id) fresh - once per
                        // room is enough, this doesn't need to race every
                        // snapshot the live doc emits.
                        if self.joinedSessionDetailsSyncedForLiveId != liveId {
                            self.joinedSessionDetailsSyncedForLiveId = liveId
                            LiveGameService.shared.recordJoinedLiveSession(
                                liveId: liveId,
                                ownerUid: snapshotOwnerUid ?? "",
                                ownerGameId: data["ownerGameId"] as? String,
                                opponent: data["opponent"] as? String
                            )
                        }
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
                debugLog("❌ Live participants listener error:", err.localizedDescription)
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
                let wasConnected = self.uiConnected
                self.uiConnected = connectedNow

                // Owns the connected-transition side effects too, now that it
                // is the only writer of `uiConnected`.
                if connectedNow, !wasConnected, self.isOwnerForActiveGame,
                   self.didAutoDismissCodeSheetForLiveId != liveId {
                    self.didAutoDismissCodeSheetForLiveId = liveId
                    if self.activeLiveId == liveId {
                        self.startListeningToLivePitchEvents(liveId: liveId)
                    }
                }

                if !connectedNow, self.didAutoDismissCodeSheetForLiveId == liveId {
                    self.didAutoDismissCodeSheetForLiveId = nil
                }
            }
        }
    }

    /// Feeds the Settings "My Games" scroll's "Live" row. Runs for the whole
    /// signed-in session (started at boot, not per-room) so a joined game
    /// shows up there even before the participant taps back into it -
    /// `startListeningToLiveGame` itself only refreshes/removes an existing
    /// bookmark, it never starts this listener.
    private func startListeningToJoinedLiveSessions() {
        joinedLiveSessionsListener?.remove()
        joinedLiveSessionsListener = nil
        guard let uid = authManager.user?.uid, !uid.isEmpty else {
            joinedLiveSessions = []
            return
        }

        let ref = Firestore.firestore()
            .collection("users").document(uid)
            .collection("joinedLiveSessions")

        joinedLiveSessionsListener = ref.addSnapshotListener { snap, err in
            if let err {
                debugLog("❌ joinedLiveSessions listener error:", err.localizedDescription)
                return
            }
            let sessions = (snap?.documents ?? []).compactMap {
                JoinedLiveSession(liveId: $0.documentID, data: $0.data())
            }
            DispatchQueue.main.async {
                self.joinedLiveSessions = sessions.sorted { ($0.joinedAt ?? .distantPast) > ($1.joinedAt ?? .distantPast) }
            }
        }
    }

    /// Live rooms are created with a fixed `expiresAt` that nothing renewed, so
    /// a session that outlasted it went quiet mid-game: the participant's
    /// listener stops treating the room as active and called pitches simply
    /// stop arriving. Renewal is owner-driven (rules pin `expiresAt` for
    /// participants) and runs off the snapshot already in hand rather than a
    /// polling read.
    private func renewLiveSessionIfExpiringSoon(liveId: String, data: [String: Any]) {
        guard isOwnerForActiveGame, !liveSessionRenewalInFlight else { return }
        guard ((data["status"] as? String) ?? "active") == "active" else { return }
        guard let expiresAt = (data["expiresAt"] as? Timestamp)?.dateValue() else { return }
        guard expiresAt.timeIntervalSinceNow < LiveGameService.renewalWindow else { return }

        liveSessionRenewalInFlight = true
        LiveGameService.shared.renewLiveSession(
            liveId: liveId,
            ownerGameId: data["ownerGameId"] as? String
        ) { _ in
            DispatchQueue.main.async { self.liveSessionRenewalInFlight = false }
        }
    }
    private func resetCallAndResultUIState() {
        lastTappedPosition = nil
        calledPitch = nil
        calledPitchComposerDetent = .fraction(0.28)
        activeCalledPitchId = nil
        pendingResultLabel = nil
        showConfirmSheet = false
        showResultConfirmation = false
        isRecordingResult = false
        selectedLocation = ""
        resultVisualState = nil
        actualLocationRecorded = nil
        lastCallInitiatedAt = nil
        lastObservedPendingCallId = nil
        catcherEstimateDismissed = true
        catcherEstimate = nil
        catcherEstimateDraftPitch = "Catcher"
        catcherEstimateDraftLocation = nil
        resetScoutComposer()
        clearDisplayCodeIfNeeded()
    }

    private func resetScoutComposer() {
        scoutObservedResult = nil
        scoutInPlayOutcome = nil
        scoutHitOnPlay = false
        scoutDescriptor = nil
        scoutErrorOnPlay = false
        scoutMiscOutcome = nil
        scoutZoneSelection = nil
        scoutBattedBallRegionName = nil
        scoutBattedBallTapNormalized = nil
        showScoutFieldMap = false
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
        flushBufferedSharedHitterEvents(reason: "endLiveSession")

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
        // The revision floor was scoped to the room that just ended; rejoining
        // (or joining a different room) must start from scratch.
        progressRevision = 0
        progressRevisionRoomId = nil
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
        livePitcherName = nil
        UserDefaults.standard.removeObject(forKey: "activeLiveId")

        if keepCurrentGame, isGame {
            startListeningToActiveGame()
            startListeningToGamePitchEvents()
        } else {
            isGame = false
            sessionManager.switchMode(to: .game)
        }

        if !isOwnerForActiveGame {
            dismissAllTopLevelSheets()
            activeHomeArea = .home
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
            updatedAt: Date().timeIntervalSince1970,
            progressRevision: progressRevision,
            outs: outs
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: "\(DefaultsKeys.lastProgressByGameId).\(gid)")
        }
    }

    private func mergeLoadedGamesPreservingProgress(_ loaded: [Game]) -> [Game] {
        guard let gid = selectedGameId else { return loaded }

        var merged = loaded
        if let idx = merged.firstIndex(where: { $0.id == gid }) {
            debugLog("🧭[PROG] mergeLoadedGames gid=\(gid) localStamp=\(String(describing: lastLocalProgressUpdate)) snapshotStamp=\(String(describing: merged[idx].progressUpdatedAt)) local=\(balls)/\(strikes)/\(inning)/\(hits)/\(walks)/\(us)/\(them) snap=\(merged[idx].balls)/\(merged[idx].strikes)/\(merged[idx].inning)/\(merged[idx].hits)/\(merged[idx].walks)/\(merged[idx].us)/\(merged[idx].them)")
            if lastLocalProgressUpdate == nil, let local = loadLocalProgressSnapshot(for: gid) {
                balls = local.balls
                strikes = local.strikes
                inning = local.inning
                hits = local.hits
                walks = local.walks
                us = local.us
                them = local.them
                lastLocalProgressUpdate = Date(timeIntervalSince1970: local.updatedAt)
                // `progressRevision` is deliberately NOT restored - see its
                // declaration. It belongs to one live room, and resuming at 0
                // is what lets the room's first snapshot resync this device.
                outs = local.outs ?? outs
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

    /// True while this device holds a progress change that has not reached the
    /// live room yet, so an incoming snapshot - however new its revision - is
    /// still describing a world before that change and must not be applied over
    /// it.
    ///
    /// The window is bounded deliberately. If a publish never reports back (the
    /// device dropped offline mid-transaction, say), an unbounded guard would
    /// leave this device permanently deaf to the partner. After the timeout the
    /// room wins, which is the right outcome for a write that never landed.
    private var hasUnpublishedLocalProgress: Bool {
        guard publishedLocalProgressToken < localProgressChangeToken else { return false }
        guard let changedAt = lastUnpublishedProgressChangeAt else { return false }
        return Date().timeIntervalSince(changedAt) < Self.unpublishedProgressGraceWindow
    }

    private static let unpublishedProgressGraceWindow: TimeInterval = 5

    private func markLocalProgressChange() {
        lastLocalProgressUpdate = Date()
        localProgressChangeToken += 1
        lastUnpublishedProgressChangeAt = Date()
        persistLocalProgressSnapshot()
        debugLog("🧭[PROG] markLocalProgressChange gid=\(selectedGameId ?? "<nil>") stamp=\(String(describing: lastLocalProgressUpdate)) local=\(balls)/\(strikes)/\(inning)/\(hits)/\(walks)/\(us)/\(them)")
        scheduleProgressSnapshotPublish()
    }

    // Recording one pitch result can touch several progress fields in a row -
    // e.g. a ball-in-play out resets the count (syncCountFromComposer) AND
    // advances outs (applyReviewedOutAdvanceIfNeeded) - and each used to fire
    // its own immediate commitLiveProgress transaction with whatever local
    // state existed at that instant. Firestore transactions re-read the
    // document and retry on conflict, but they replay the SAME frozen
    // `fields` payload on retry rather than re-capturing local state, so
    // whichever of those two transactions happened to land on the server
    // last "won" with a higher revision - even when it was the one carrying
    // the stale (pre-out) snapshot. That's what let a partner's recorded out
    // silently fail to reach the owner. Coalescing every markLocalProgressChange()
    // within one run-loop turn into a single deferred publish means only the
    // fully-settled state (after all of this event's adjustments have run)
    // ever reaches the network.
    private func scheduleProgressSnapshotPublish() {
        guard !progressPublishScheduled else { return }
        progressPublishScheduled = true
        DispatchQueue.main.async { [self] in
            progressPublishScheduled = false
            persistProgressSnapshotToOwnerGameAndLive()
        }
    }

    private func persistProgressSnapshotToOwnerGameAndLive() {
        // Every change coalesced into this publish is covered by it, so the
        // token captured here is the one that clears `hasUnpublishedLocalProgress`.
        // A change made *while* this publish is in flight raises the token
        // again and keeps the guard up until its own publish reports back.
        let publishingToken = localProgressChangeToken

        if let liveId = activeLiveId, !liveId.isEmpty {
            LiveGameService.shared.commitLiveProgress(liveId: liveId, fields: [
                "balls": balls,
                "strikes": strikes,
                "inning": inning,
                "hits": hits,
                "walks": walks,
                "us": us,
                "them": them,
                "outs": outs
            ]) { result in
                DispatchQueue.main.async {
                    self.publishedLocalProgressToken = max(self.publishedLocalProgressToken, publishingToken)
                    // A failed commit means the room never got this change, so
                    // the room's own state is the newer truth - leave the
                    // revision floor alone and let the next snapshot apply.
                    guard case .success(let serverRevision) = result else { return }
                    guard self.progressRevisionRoomId == liveId else { return }
                    self.progressRevision = max(self.progressRevision, serverRevision)
                }
            }
        } else {
            // No room to publish to, so there is nothing pending to protect.
            publishedLocalProgressToken = max(publishedLocalProgressToken, publishingToken)
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
        flushBufferedSharedHitterEvents(reason: "disconnect")
        if let liveId = activeLiveId {
            // An explicit Disconnect is a deliberate permanent leave, unlike
            // backgrounding or navigating to Settings (which only pause
            // listeners) - drop the games-scroll bookmark so it isn't offered
            // as re-enterable afterward.
            if !isOwnerForActiveGame {
                LiveGameService.shared.removeJoinedLiveSession(liveId: liveId)
            }
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
                        debugLog("❌ Failed to remove participant:", err.localizedDescription)
                    } else {
                        debugLog("✅ Participant removed from game participants")
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

        // Keep the tracker in game mode locally.
        isGame = false
        sessionManager.switchMode(to: .game)
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
        var seenIds: Set<String> = []
        return pitchers.filter { pitcher in
            if let id = pitcher.id {
                if seenIds.contains(id) { return false }
                seenIds.insert(id)
                return !hiddenPitcherIdSet.contains(id)
            }
            return true
        }
    }

    /// `visiblePitchers` filtered to whichever side is currently active.
    /// `awayPitcherIds` comes from the away Team's roster (TeamPlayer.pitcherId
    /// values) loaded whenever the game's `awayTeamId` is set - a pitcher not
    /// in that set is assumed to be ours (Home), matching today's behavior
    /// for every game that never sets an away team at all.
    private var sideFilteredPitchers: [Pitcher] {
        switch activeSide {
        case .home:
            return visiblePitchers.filter { !awayPitcherIds.contains($0.id ?? "") }
        case .away:
            return visiblePitchers.filter { awayPitcherIds.contains($0.id ?? "") }
        }
    }

    private func loadAwayPitcherIds(awayTeamId: String?, completion: (() -> Void)? = nil) {
        guard let awayTeamId, !awayTeamId.isEmpty else {
            awayPitcherIds = []
            completion?()
            return
        }
        authManager.loadTeamPlayers(teamId: awayTeamId) { players in
            self.awayPitcherIds = Set(players.compactMap { $0.pitcherId })
            completion?()
        }
    }

    /// Tapping Away for a game with no opponent roster yet opens setup
    /// instead of silently switching to an empty picker.
    private func handleSelectAwaySide() {
        let game = selectedGameId.flatMap { gid in games.first(where: { $0.id == gid }) }
        guard let awayTeamId = game?.awayTeamId, !awayTeamId.isEmpty else {
            teamSetupShouldFlipSide = true
            // Pre-fill from the game's own opponent name (set back when the
            // game itself was created) - no reason to make the coach retype
            // the name that's already sitting right there on the game.
            if let opponent = game?.opponent {
                newOpponentTeamName = opponent
            }
            refreshOpponentTeamCandidates()
            showSetOpponentSheet = true
            return
        }
        if activeSide == .away {
            // Already tracking Away - a second tap means "manage the
            // roster" (add another pitcher, etc.) rather than a no-op.
            refreshOpponentTeamCandidates()
            showSetOpponentSheet = true
        } else {
            activeSide = .away
        }
    }

    /// Excludes this game's own "my team" (Game.teamId) from the candidate
    /// list - without this, nothing stopped a coach from picking their own
    /// team as the opponent (it's just "one of my teams" from loadMyTeams's
    /// point of view, with no concept of "opponent-only" teams). Doing so
    /// sets Game.awayTeamId == Game.teamId, which makes awayRoster and
    /// homeRoster load the identical roster - "Them" then shows "Us" data
    /// everywhere, which is exactly what this prevents rather than relying
    /// on the coach never tapping the wrong (only) row in the list.
    private func refreshOpponentTeamCandidates() {
        let myTeamId = activeGameForBatterSetup?.teamId
        authManager.loadMyTeams { teams, _ in
            self.opponentTeamCandidates = teams.filter { $0.team.id != myTeamId }
        }
    }

    private func setOpponentTeam(_ team: Team) {
        guard let gid = selectedGameId, let teamId = team.id,
              let index = games.firstIndex(where: { $0.id == gid }) else { return }
        // Capture before overwriting - this is what distinguishes "picking an
        // opponent for the first time" from "tapping Away again to re-manage
        // an already-set opponent."
        let isFirstTimeSetup = (games[index].awayTeamId ?? "").isEmpty
        games[index].awayTeamId = teamId
        if !isDemoMode {
            authManager.saveGame(games[index])
        }
        activeAwayTeamName = team.name
        refreshAwayRoster(awayTeamId: teamId)
        // Don't flip to Them until the roster is actually loaded - doing it
        // immediately left a brief window where the main screen (visible
        // behind the sheet) showed Them's empty/disabled pitcher picker and
        // swapped count colors before there was anything to pick.
        loadAwayPitcherIds(awayTeamId: teamId) {
            if isFirstTimeSetup {
                // Let the coach pick which of this roster's batters are
                // actually worth tracking before finishing setup, rather
                // than silently defaulting to "every hitter on the roster."
                self.chooseBattersSelection = Set(self.awayRoster.compactMap { $0.hitterId != nil ? $0.id : nil })
                self.showChooseBattersStep = true
            } else if self.teamSetupShouldFlipSide {
                self.activeSide = .away
            }
        }
    }

    private func beginEditingActiveBatters() {
        guard let gid = selectedGameId, let game = games.first(where: { $0.id == gid }) else { return }
        let hitterCapableIds = Set(awayRoster.compactMap { $0.hitterId != nil ? $0.id : nil })
        if let activeIds = game.activeAwayBatterIds, !activeIds.isEmpty {
            chooseBattersSelection = Set(activeIds).intersection(hitterCapableIds)
        } else {
            chooseBattersSelection = hitterCapableIds
        }
        showChooseBattersStep = true
    }

    /// Reached from the first-time setup flow (triggered by tapping Them,
    /// teamSetupShouldFlipSide true - landing on .away is the point),
    /// from revisiting via awayRosterSection (already .away, flipping is a
    /// harmless no-op), and now also from the Us-side batter row's "Set
    /// Opponent" button (teamSetupShouldFlipSide false - the coach wants
    /// opponent batters to pick from while THEY keep pitching, not to
    /// switch to tracking the opponent's pitcher).
    private func confirmChooseBatters(trackAll: Bool) {
        guard let gid = selectedGameId, let index = games.firstIndex(where: { $0.id == gid }) else { return }
        games[index].activeAwayBatterIds = trackAll ? nil : Array(chooseBattersSelection)
        if !isDemoMode {
            authManager.saveGame(games[index])
        }

        // Checking batters here used to write `activeAwayBatterIds` and
        // nothing else - curation for the "Add From Team" picker. To a
        // coach that is indistinguishable from building a lineup (it's a
        // checklist of opponent batters with a Done button), so picking
        // batters here appeared to do nothing: the At Bat scroll stayed
        // empty because only `addBatterFromRoster` ever creates cells.
        // Selecting a batter now puts them in the lineup, which is what
        // the screen looks like it does.
        addChosenBattersToLineup(trackAll: trackAll)

        showChooseBattersStep = false
        showSetOpponentSheet = false
        if teamSetupShouldFlipSide {
            activeSide = .away
        }
    }

    /// Adds every chosen opponent batter who isn't already in the lineup, so
    /// re-opening this step and confirming again is idempotent rather than
    /// adding everyone a second time.
    ///
    /// De-dupes on TWO keys, deliberately. `hitterId` is the precise one
    /// (what `atBatRosterPickerCandidates` uses), but that map is
    /// session-local by design - after a relaunch the lineup's cells are
    /// still there while their roster links are gone, so an "Add Everyone"
    /// would re-add the entire roster as duplicates. The displayed jersey
    /// string survives the relaunch with the cell, so it catches that case.
    private func addChosenBattersToLineup(trackAll: Bool) {
        let linkedHitterIds = Set(hitterIdByJerseyCellId.values)
        let existingDisplays = Set(jerseyCells.map { $0.jerseyNumber })
        let chosen = awayRoster.filter { player in
            guard let hitterId = player.hitterId, !linkedHitterIds.contains(hitterId) else { return false }
            guard !existingDisplays.contains(lineupDisplayNumber(for: player)) else { return false }
            return trackAll || chooseBattersSelection.contains(player.id ?? "")
        }
        for player in chosen {
            addBatterFromRoster(player)
        }
    }

    private func createAndSetOpponentTeam() {
        let name = newOpponentTeamName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let designation = newOpponentTeamDesignation.designation else { return }
        authManager.createTeam(name: name, designation: designation) { result in
            if case .success(let team) = result {
                self.newOpponentTeamName = ""
                self.newOpponentTeamDesignation.reset()
                self.setOpponentTeam(team)
            }
        }
    }

    /// Both sides' rosters, both side team names, and the away pitcher ids
    /// for one game - lifted verbatim out of `chooseGame`, which was the
    /// only place that loaded any of it.
    ///
    /// That was the second half of "the lineup doesn't swap after a cold
    /// launch": a relaunch restores through `hydrateChosenGameUI` / the
    /// deferred boot restore, neither of which went anywhere near this, so
    /// both rosters stayed empty. `currentBattingHitterIds` deliberately
    /// fails open on an empty roster (it can't tell "empty" from "still
    /// loading"), so the At Bat scroll showed every cell on both sides no
    /// matter what the link map said.
    /// Takes the `Game` itself rather than an id on purpose: the slow
    /// branch of `hydrateChosenGameUI` runs precisely because the game is
    /// *not* in `games` yet, so an id lookup there would find nothing and
    /// clear both rosters instead of loading them.
    private func loadSideContext(for game: Game?) {
        if let awayTeamId = game?.awayTeamId, !awayTeamId.isEmpty {
            loadAwayPitcherIds(awayTeamId: awayTeamId)
            refreshAwayRoster(awayTeamId: awayTeamId)
            authManager.loadMyTeams { teams, _ in
                if let match = teams.first(where: { $0.team.id == awayTeamId }) {
                    self.activeAwayTeamName = match.team.name
                }
            }
        } else {
            awayPitcherIds = []
            awayRoster = []
            activeAwayTeamName = ""
        }
        if let teamId = game?.teamId, !teamId.isEmpty {
            refreshHomeRoster(teamId: teamId)
            authManager.loadMyTeams { teams, _ in
                if let match = teams.first(where: { $0.team.id == teamId }) {
                    self.activeHomeTeamName = match.team.name
                }
            }
        } else {
            homeRoster = []
            activeHomeTeamName = ""
        }
    }

    private func refreshAwayRoster(awayTeamId: String, completion: (() -> Void)? = nil) {
        authManager.loadTeamPlayers(teamId: awayTeamId) { players in
            self.awayRoster = players
            completion?()
        }
    }

    private func refreshHomeRoster(teamId: String, completion: (() -> Void)? = nil) {
        authManager.loadTeamPlayers(teamId: teamId) { players in
            self.homeRoster = players
            completion?()
        }
    }

    /// `activeBatterRosterCandidates` reads the cached `awayRoster`/
    /// `homeRoster` snapshots, which only refresh at a few specific call
    /// sites (setting an opponent/my team, adding a pitcher, switching
    /// games). A player added from Home's Team Roster screen while this
    /// game stays mounted in the background (PitchTrackerView is the
    /// permanent root, never torn down) hits none of those, so "Add From
    /// Team" kept showing a stale roster missing the new player. Called
    /// right before presenting that picker; fire-and-forget is fine since
    /// the sheet reads these same `@State` arrays and re-renders when they
    /// land.
    private func refreshBattingRoster(teamId: String) {
        switch activeSide {
        case .home: refreshAwayRoster(awayTeamId: teamId)
        case .away: refreshHomeRoster(teamId: teamId)
        }
    }

    /// Symmetric to `handleSelectAwaySide` - tapping Us for a game with no
    /// linked team yet opens setup instead of silently switching to an
    /// empty batter picker. Unlike Away, Us needs no inline roster-add UI
    /// in this sheet - once linked, that team's roster is already managed
    /// from Home's own Teams and Players screen.
    private func handleSelectHomeSide() {
        guard let gid = selectedGameId, let game = games.first(where: { $0.id == gid }),
              let teamId = game.teamId, !teamId.isEmpty else {
            teamSetupShouldFlipSide = true
            refreshMyTeamCandidates()
            showSetMyTeamSheet = true
            return
        }
        activeSide = .home
    }

    /// Symmetric to refreshOpponentTeamCandidates' exclusion, mirrored.
    private func refreshMyTeamCandidates() {
        let awayTeamId = activeGameForBatterSetup?.awayTeamId
        authManager.loadMyTeams { teams, _ in
            self.myTeamCandidates = teams.filter { $0.team.id != awayTeamId }
        }
    }

    private func setMyTeam(_ team: Team) {
        guard let gid = selectedGameId, let teamId = team.id,
              let index = games.firstIndex(where: { $0.id == gid }) else { return }
        games[index].teamId = teamId
        if !isDemoMode {
            authManager.saveGame(games[index])
        }
        activeHomeTeamName = team.name
        refreshHomeRoster(teamId: teamId)
        if teamSetupShouldFlipSide {
            activeSide = .home
        }
        showSetMyTeamSheet = false
    }

    private func createAndSetMyTeam() {
        let name = newMyTeamName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let designation = newMyTeamDesignation.designation else { return }
        authManager.createTeam(name: name, designation: designation) { result in
            if case .success(let team) = result {
                self.newMyTeamName = ""
                self.newMyTeamDesignation.reset()
                self.setMyTeam(team)
            }
        }
    }

    /// Who the batter picker should draw from: when Us is pitching, the
    /// batter is the opponent's player (away roster); when Them is
    /// pitching, the batter is ours (home roster). Only hitter-capable
    /// (linked) entries show up - a player added with role Pitcher alone
    /// has no `hitterId` and is correctly excluded. On the away side only,
    /// a coach can further narrow a large roster down to just the batters
    /// worth tracking (Game.activeAwayBatterIds) - unset/empty means no
    /// restriction, matching every game's behavior before this existed.
    private var activeBatterRosterCandidates: [TeamPlayer] {
        switch activeSide {
        case .home:
            let hitterCapable = awayRoster.filter { $0.hitterId != nil }
            guard let activeIds = selectedGameId.flatMap({ gid in games.first(where: { $0.id == gid })?.activeAwayBatterIds }),
                  !activeIds.isEmpty else {
                return hitterCapable
            }
            let activeIdSet = Set(activeIds)
            return hitterCapable.filter { activeIdSet.contains($0.id ?? "") }
        case .away:
            return homeRoster.filter { $0.hitterId != nil }
        }
    }

    /// Hitter ids (TeamPlayer.hitterId) belonging to whichever side is
    /// batting right now. Nil means "don't filter at all".
    ///
    /// Two deliberate fail-open cases, both of which previously made
    /// batters vanish from the At Bat scroll:
    ///
    /// 1. The roster array is empty. That is indistinguishable from "still
    ///    loading" (every refresh is an async Firestore read) or "the load
    ///    failed", and an empty set would hide every roster-linked cell in
    ///    the lineup. Showing a stale cell beats blanking the lineup.
    /// 2. This reads the whole side roster, NOT
    ///    `activeBatterRosterCandidates`. That property additionally
    ///    narrows by `Game.activeAwayBatterIds`, which is curation for the
    ///    "Add From Team" picker - whom you *could* add. Letting it reach
    ///    display meant deselecting someone in "Batters to Track" silently
    ///    removed a batter already in the lineup.
    private var currentBattingHitterIds: Set<String>? {
        guard currentBattingTeamId != nil else { return nil }
        let roster = activeSide == .home ? awayRoster : homeRoster
        let hitterIds = Set(roster.compactMap { $0.hitterId })
        return hitterIds.isEmpty ? nil : hitterIds
    }

    /// The "At Bat" scroll, scoped to whoever's actually up: Us pitching
    /// shows Them's lineup and vice versa. A cell only disappears when
    /// it's definitively linked (via hitterIdByJerseyCellId) to the OTHER
    /// side's roster - a cell with no roster link at all (added before
    /// Us/Them existed, or just a bare jersey number typed in) always
    /// shows, so nothing already on a coach's lineup silently vanishes.
    private var visibleJerseyCells: [JerseyCell] {
        guard let battingIds = currentBattingHitterIds else { return jerseyCells }
        return jerseyCells.filter { cell in
            guard let hitterId = hitterIdByJerseyCellId[cell.id] else { return true }
            return battingIds.contains(hitterId)
        }
    }

    /// `sideFilteredPitchers` filters by `awayPitcherIds`, which only ever
    /// contains linked ids. Uses the same always-both-capable path every
    /// other add-player entry point uses, so a player added here (really
    /// "add a player," not just a pitcher - they're hitter-capable too) is
    /// a real cross-team Player, not a pitcher-only, roster-local record.
    private func addAwayPitcher() {
        guard let gid = selectedGameId, let game = games.first(where: { $0.id == gid }),
              let awayTeamId = game.awayTeamId, !awayTeamId.isEmpty else { return }
        let name = newAwayPitcherName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        authManager.addTeamPlayerCreatingNewPlayer(teamId: awayTeamId, name: name, jerseyNumber: nil) { result in
            guard case .success = result else { return }
            self.newAwayPitcherName = ""
            self.loadAwayPitcherIds(awayTeamId: awayTeamId)
            self.refreshAwayRoster(awayTeamId: awayTeamId)
        }
    }

    private var pickOrCreateOpponentSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("New Opponent Roster")
                    .font(.headline)
                TextField("Opponent team name", text: $ui.newOpponentTeamName)
                    .textFieldStyle(.roundedBorder)
                // Same four mandatory choices Home's create-team form
                // collects - a team minted here is a real Team and has to
                // carry the same stamp, or it shows up undesignated
                // everywhere else.
                TeamDesignationForm(draft: $newOpponentTeamDesignation)
                HStack {
                    Spacer()
                    Button("Create") {
                        createAndSetOpponentTeam()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        newOpponentTeamName.trimmingCharacters(in: .whitespaces).isEmpty
                            || !newOpponentTeamDesignation.isComplete
                    )
                }
            }

            if !opponentTeamCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Or Pick a Saved Team")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(opponentTeamCandidates, id: \.team.id) { entry in
                            Button {
                                setOpponentTeam(entry.team)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(entry.team.name)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer(minLength: 8)
                                    TeamDesignationBadge(designation: entry.team.designation)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func awayRosterSection(teamName: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(teamName)
                    .font(.title3.weight(.bold))
                // Was "Pitchers added here show up when you switch to
                // Away" - which described a PITCHING-side effect inside a
                // sheet whose other control builds the BATTING lineup, the
                // single most confusing sentence in this flow.
                Text("The opposing team's roster. Their pitchers appear in Select Pitcher when they're the side pitching; their batters can be added to the At Bat list below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                // This list was headed "Pitchers" but has always rendered
                // the whole roster unfiltered - every player added here is
                // created both pitcher- and hitter-capable.
                Text("Roster")
                    .font(.headline)
                if awayRoster.isEmpty {
                    Text("No players yet - add one below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(awayRoster, id: \.id) { player in
                            Text(player.name)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                // Likewise "Add Pitcher": addAwayPitcher creates a normal
                // both-capable player, same as every other add path.
                Text("Add Player")
                    .font(.headline)
                HStack {
                    TextField("Name", text: $ui.newAwayPitcherName)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        addAwayPitcher()
                    }
                    .disabled(newAwayPitcherName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if awayRoster.contains(where: { $0.hitterId != nil }) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Batters")
                        .font(.headline)
                    Button("Pick Batters for the At Bat List…") {
                        beginEditingActiveBatters()
                    }
                }
            }
        }
    }

    /// Who's actually worth tracking from a roster that can easily have
    /// more hitter-capable players than anyone wants in the Select Batter
    /// scroll. Reached both right after first picking an opponent team and,
    /// later, from awayRosterSection's own "Choose Batters to Track" button
    /// - same screen either way. Just the row content - setOpponentSheetView
    /// supplies the single shared NavigationView/toolbar for every step.
    private var chooseBattersStepContent: some View {
        let candidates = awayRoster.filter { $0.hitterId != nil }

        return Group {
            if candidates.isEmpty {
                Text("No hitter-capable players on this roster yet - add one, or adjust a player's Role, from this team's roster screen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(candidates, id: \.id) { player in
                    let pid = player.id ?? ""
                    let isSelected = chooseBattersSelection.contains(pid)
                    Button {
                        if isSelected {
                            chooseBattersSelection.remove(pid)
                        } else {
                            chooseBattersSelection.insert(pid)
                        }
                    } label: {
                        HStack {
                            Text(player.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
        }
    }

    private var setOpponentSheetView: some View {
        let currentAwayTeamId = selectedGameId.flatMap { gid in games.first(where: { $0.id == gid })?.awayTeamId }
        let hasAwayTeam = currentAwayTeamId?.isEmpty == false

        return NavigationView {
            Group {
                if showChooseBattersStep {
                    List {
                        chooseBattersStepContent
                    }
                } else {
                    ScrollView {
                        Group {
                            if hasAwayTeam {
                                awayRosterSection(teamName: activeAwayTeamName.isEmpty ? "Opponent" : activeAwayTeamName)
                            } else {
                                pickOrCreateOpponentSection
                            }
                        }
                        .padding()
                    }
                }
            }
            // "Batters to Track" / "Track Everyone" / "Done" described
            // curation, and gave no hint that the result should appear in
            // the At Bat scroll - which it now does. The wording says so.
            .navigationTitle(showChooseBattersStep ? "Add Batters" : "Set Opponent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showChooseBattersStep {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Add Everyone") {
                            confirmChooseBatters(trackAll: true)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add Selected") {
                            confirmChooseBatters(trackAll: false)
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(hasAwayTeam ? "Done" : "Cancel") {
                            showSetOpponentSheet = false
                        }
                    }
                }
            }
        }
    }

    /// Simpler than setOpponentSheetView on purpose - once linked, this
    /// team's roster is managed from Home's own Teams and Players screen,
    /// not an inline add-pitcher UI like the away side needs (which has no
    /// other entry point into an opponent's roster).
    private var setMyTeamSheetView: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("New Team")
                            .font(.headline)
                        TextField("Team name", text: $ui.newMyTeamName)
                            .textFieldStyle(.roundedBorder)
                        TeamDesignationForm(draft: $newMyTeamDesignation)
                        HStack {
                            Spacer()
                            Button("Create") {
                                createAndSetMyTeam()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                newMyTeamName.trimmingCharacters(in: .whitespaces).isEmpty
                                    || !newMyTeamDesignation.isComplete
                            )
                        }
                    }

                    if !myTeamCandidates.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Or Pick a Saved Team")
                                .font(.headline)
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(myTeamCandidates, id: \.team.id) { entry in
                                    Button {
                                        setMyTeam(entry.team)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Text(entry.team.name)
                                                .font(.subheadline.weight(.semibold))
                                            Spacer(minLength: 8)
                                            TeamDesignationBadge(designation: entry.team.designation)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Set My Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        showSetMyTeamSheet = false
                    }
                }
            }
        }
    }

    private var demoTemplate: PitchTemplate {
        let demoPitches = ["4 Seam", "Change"]
        let demoLocations = strikeGrid.map { "Strike \($0.label)" } + [
            "Ball Up & Out", "Ball Up", "Ball Up & In",
            "Ball Out", "Ball In",
            "Ball ↓ & Out", "Ball ↓", "Ball ↓ & In"
        ]
        let demoCodeAssignments = demoPitches.enumerated().flatMap { pitchIndex, pitch in
            demoLocations.enumerated().flatMap { locationIndex, location in
                (1...3).map { optionIndex in
                    PitchCodeAssignment(
                        code: String(format: "%@%02d%d", pitchIndex == 0 ? "F" : "C", locationIndex + 1, optionIndex),
                        pitch: pitch,
                        location: location
                    )
                }
            }
        }

        return PitchTemplate(
            id: Self.demoTemplateId,
            name: "Demo Grid Key",
            pitches: demoPitches,
            codeAssignments: demoCodeAssignments,
            isEncrypted: false,
            ownerUid: Self.demoUserId,
            pitchFirstColors: ["blue", "green"],
            locationFirstColors: ["red", "white", "black"]
        )
    }

    private var demoPitcher: Pitcher {
        Pitcher(
            id: Self.demoPitcherId,
            name: "Demo Pitcher",
            templateId: Self.demoTemplateId.uuidString,
            ownerUid: Self.demoUserId,
            sharedWith: [],
            claimedByUid: nil,
            createdAt: Date()
        )
    }

    private var demoGame: Game {
        Game(
            id: Self.demoGameId,
            opponent: "Demo Game",
            date: Date(),
            jerseyNumbers: ["1"],
            batterIds: [UUID().uuidString],
            trackingMode: .coach
        )
    }

    private func requireSignInForDemo(_ message: String = "Sign in to save your own teams, pitchers, and grid keys.") {
        demoLoginWallMessage = message
        showDemoLoginWall = true
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
            return pitchEvents.sorted { $0.timestamp > $1.timestamp }
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

            if let owner = effectiveGameOwnerUserId, !owner.isEmpty {
                authManager.updateGameLastSelections(
                    ownerUserId: owner,
                    gameId: gameId,
                    templateId: template?.id.uuidString,
                    pitcherId: selectedPitcherId
                )
            }
        }

        // This is the only writer of the per-game key map, so it is where
        // the Key control's flash stops (or starts, if a key was cleared).
        refreshKeyPickedForActiveGame()
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

            if let owner = effectiveGameOwnerUserId, !owner.isEmpty {
                authManager.updateGameLastSelections(
                    ownerUserId: owner,
                    gameId: gameId,
                    templateId: selectedTemplate?.id.uuidString,
                    pitcherId: id
                )
            }
        }
    }

    private func applyStoredSelections(for gameId: String) {
        let defaults = UserDefaults.standard
        let serverTemplateId = currentGame?.lastTemplateId
        let serverPitcherId = currentGame?.lastPitcherId

        let templateId: String? = {
            if let templateMap = defaults.dictionary(forKey: DefaultsKeys.lastTemplateByGameId) as? [String: String] {
                if let localTemplateId = templateMap[gameId], !localTemplateId.isEmpty {
                    return localTemplateId
                }
            }
            if let serverTemplateId, !serverTemplateId.isEmpty {
                return serverTemplateId
            }
            return nil
        }()

        if let templateId,
           !hiddenTemplateIdSet.contains(templateId),
           let template = templates.first(where: { $0.id.uuidString == templateId }) {
            applyTemplate(template)
        }

        let pitcherId: String? = {
            if let pitcherMap = defaults.dictionary(forKey: DefaultsKeys.lastPitcherByGameId) as? [String: String] {
                if let localPitcherId = pitcherMap[gameId], !localPitcherId.isEmpty {
                    return localPitcherId
                }
            }
            if let serverPitcherId, !serverPitcherId.isEmpty {
                return serverPitcherId
            }
            return nil
        }()

        if let pitcherId,
           let pitcher = pitchers.first(where: { $0.id == pitcherId }) {
            applySelectedPitcher(pitcher)
        }
        if let selected = selectedTemplate,
           hiddenTemplateIdSet.contains(selected.id.uuidString) {
            selectedTemplate = visibleTemplates.first ?? templates.first
        }
        refreshKeyPickedForActiveGame()
    }

    /// Recomputes `keyPickedForActiveGame` from the only two places a
    /// game's own key is recorded. Called from the two choke points where
    /// either can change: the end of `applyStoredSelections(for:)` (game
    /// entry, and templates arriving afterwards) and the end of
    /// `persistSelectedTemplate(_:)`, which is the sole writer of the
    /// per-game map.
    ///
    /// An id that no longer resolves to a loaded, visible template counts
    /// as "not picked" - a key that was deleted or hidden since the game
    /// last ran is exactly the case the coach needs prompting about.
    private func refreshKeyPickedForActiveGame() {
        guard let gameId = selectedGameId, !gameId.isEmpty else {
            keyPickedForActiveGame = false
            return
        }

        func isUsable(_ id: String?) -> Bool {
            guard let id, !id.isEmpty, !hiddenTemplateIdSet.contains(id) else { return false }
            return templates.contains(where: { $0.id.uuidString == id })
        }

        if let map = UserDefaults.standard.dictionary(forKey: DefaultsKeys.lastTemplateByGameId) as? [String: String],
           isUsable(map[gameId]) {
            keyPickedForActiveGame = true
            return
        }
        keyPickedForActiveGame = isUsable(currentGame?.lastTemplateId)
    }

    private func restorePersistedTemplateIfPossible(from loadedTemplates: [PitchTemplate]) -> Bool {
        let defaults = UserDefaults.standard
        guard let idString = defaults.string(forKey: DefaultsKeys.lastTemplateId),
              !hiddenTemplateIdSet.contains(idString),
              let template = loadedTemplates.first(where: { $0.id.uuidString == idString }) else {
            return false
        }
        applyTemplate(template, source: .live)
        return true
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
                    debugLog("❌ update batterSide:", err.localizedDescription)
                } else {
                    debugLog("✅ batterSide updated:", sideString)
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
    }

    private func persistEncryptedSelections() {
        let defaults = UserDefaults.standard
        defaults.set(encryptedSelectionByGameId, forKey: DefaultsKeys.encryptedByGameId)
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
        if isGame && !isOwnerForActiveGame {
            return Set(orderedPitchesForTemplate)
        }
        if let t = selectedTemplate, useEncrypted(for: t) {
            return Set(availablePitches(for: t))
        }
        return selectedPitches
    }
    
    fileprivate var orderedPitchesForTemplate: [String] {
        let list = availablePitches(for: selectedTemplate)
        return list
    }
    
    private func refreshGamesList() {
        authManager.loadGames { loaded in
            let merged = mergePreservingUnsyncedGames(
                loaded: self.mergeLoadedGamesPreservingProgress(loaded),
                local: self.games
            )
            self.games = merged

            if let selectedId = self.selectedGameId,
               !merged.contains(where: { $0.id == selectedId }) {
                self.selectedGameId = nil
                self.opponentName = nil
                self.activeGameOwnerUserId = nil
                let defaults = UserDefaults.standard
                defaults.removeObject(forKey: DefaultsKeys.activeGameId)
                defaults.removeObject(forKey: DefaultsKeys.activeGameOwnerUserId)
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
        syncSelectedPitchWithVisibleOptions()

        if source == .user {
            liveTemplateOverrideLocked = true
            if isGame {
                syncLiveTemplateSelectionIfOwner()
            }
        }
    }

    private func applySelectedPitcher(_ pitcher: Pitcher, allowTemplateOverride: Bool = true) {
        if !isDemoMode && isGame && !pitcher.isActiveOwner(currentUid: authManager.user?.uid) {
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
        isDemoMode: Bool = false,
        onRequireSignIn: @escaping () -> Void = {},
        previewTemplate: PitchTemplate? = nil,
        previewTemplates: [PitchTemplate] = [],
        previewIsGame: Bool = false
    ) {
        self.isDemoMode = isDemoMode
        self.onRequireSignIn = onRequireSignIn
        if let t = previewTemplate {
            _selectedTemplate = State(initialValue: t)
            _selectedPitches = State(initialValue: Set(t.pitches))
            _pitchCodeAssignments = State(initialValue: t.codeAssignments)
        }
        _templates = State(initialValue: previewTemplates)
        // isGame moved into TrackerUIState, so it is seeded on the object
        // rather than through a `State(initialValue:)` on this struct.
        let seededUI = TrackerUIState()
        seededUI.isGame = previewIsGame
        _ui = StateObject(wrappedValue: seededUI)
    }
    
    // MARK: - Helpers for Pitches Faced Popover
    // MARK: - Current Game Helper
    private var currentGame: Game? {
        guard let gid = selectedGameId else { return nil }
        if let match = games.first(where: { $0.id == gid }) {
            return match
        }
        // A participant can never read the owner's private game doc (the
        // firestore.rules participant-get path requires an activeSessionCode
        // field this app never writes), so games[] never gets a real entry
        // for them — see the "Participants cannot read /users/{owner}/games"
        // comment in startListeningToLiveGame. Without this fallback,
        // currentGame stays nil forever and any UI gated on it (Pitcher
        // Stats, Game Summary) is stuck on its loading state permanently.
        // opponentName already mirrors over the live doc, so use it.
        guard isGame, !isOwnerForActiveGame else { return nil }
        return Game(id: gid, opponent: opponentName ?? "", date: Date(), jerseyNumbers: [])
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
        currentTrackingMode = games.first(where: { $0.id == gameId })?.trackingMode ?? .coach
        activeSide = .home
        selectedHitterId = nil
        // Was an unconditional reset, which is what made the At Bat scroll
        // stop scoping to the batting side after reopening a game.
        seedHitterLinks(from: games.first(where: { $0.id == gameId }))
        loadSideContext(for: games.first(where: { $0.id == gameId }))
        debugLog("🧭[PROG] chooseGame gid=\(gameId) owner=\(ownerUid)")

        isGame = true
        sessionManager.switchMode(to: .game)

        // ✅ Persist "active game" so relaunch restores correctly
        let defaults = UserDefaults.standard
        defaults.set(gameId, forKey: DefaultsKeys.activeGameId)
        defaults.set(ownerUid, forKey: DefaultsKeys.activeGameOwnerUserId)
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
            // `progressRevision` is deliberately NOT restored - see its declaration.
            outs = local.outs ?? outs
            debugLog("🧭[PROG] chooseGame loadLocalSnapshot gid=\(gameId) stamp=\(lastLocalProgressUpdate!) values=\(balls)/\(strikes)/\(inning)/\(hits)/\(walks)/\(us)/\(them)")
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
            debugLog("🧭[PROG] chooseGame loadCached gid=\(gameId) stamp=\(String(describing: lastLocalProgressUpdate)) values=\(balls)/\(strikes)/\(inning)/\(hits)/\(walks)/\(us)/\(them)")
        }

        hydrateChosenGameUI(ownerUid: ownerUid, gameId: gameId)
        startListeningToActiveGame()
        startListeningToGamePitchEvents()
        applyStoredSelections(for: gameId)
        ensureAutoLiveSessionIfNeeded()
    }

    /// Enters a game. Named for what it used to do: present a sheet asking
    /// for the pitcher and grid key before letting you in. That sheet is
    /// gone - `chooseGame` ends in `applyStoredSelections(for:)`, which
    /// already restores this game's own last pitcher and key (the
    /// `lastPitcherByGameId`/`lastTemplateByGameId` maps, with the game
    /// doc's `lastPitcherId`/`lastTemplateId` as the cross-device
    /// fallback), and `persistSelectedPitcherId`/`persistSelectedTemplate`
    /// already write both of those every time either is picked inside the
    /// tracker. So the sheet's own persistence was duplicating work that
    /// happens anyway, and its tracking-mode picker was dead for games
    /// (the confirm path forced `.coach` regardless).
    ///
    /// Deliberately does NOT fall back to the pitcher/key last used in
    /// some *other* game the way the sheet's seeding did. A game with
    /// nothing of its own stored now enters with the pitcher unset and
    /// flashes for it (`MissingPitcherBadge` / `MissingKeyBadge`), which
    /// is honest about it - silently carrying the previous game's pitcher
    /// in is how pitches get logged against the wrong kid.
    private func requestGameConfirmation(gameId: String, ownerUid: String) {
        // The "Account In Use" blocker is a root `.overlay`. Entering a
        // game while a conflict is up would swap the tracker in underneath
        // it, hiding the only control that can resolve the conflict.
        guard !showSessionConflictAlert else { return }

        // `chooseGame` flips `isGame`, which swaps the tracker UI in for
        // the first time. One caller is `showGameSheet`'s onDismiss, and
        // doing that in the same transaction as a sheet dismissal left
        // controls on the newly-appeared tracker (the At Bat scroll's "+")
        // with unresponsive gesture recognizers until a full relaunch
        // forced a clean re-layout. Deferred a run-loop turn so the
        // dismissal finishes first. This is the same deferral the old
        // confirmation sheet got for free from its onDismiss.
        DispatchQueue.main.async {
            self.chooseGame(gameId: gameId, ownerUid: ownerUid)
            self.refreshPlayerDirectory()

            // Re-assert this game's stored pitcher/key once the game
            // listeners started by chooseGame have settled - they can
            // land a stale template or pitcher right after entry. The
            // old confirm path re-asserted here for the same reason.
            DispatchQueue.main.async {
                self.applyStoredSelections(for: gameId)
            }
        }
    }

    /// The roster entries + teams both pitcher pickers build their Players
    /// rows from.
    private func refreshPlayerDirectory() {
        authManager.loadPlayerDirectory { entries, teams in
            self.directoryTeams = teams
            self.rosterEntries = entries
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

    /// The single write path for the non-count progress fields while a live
    /// room is active.
    ///
    /// `markLocalProgressChange()` has to run for BOTH roles, which is why it
    /// is deferred rather than left at the end of the owner-only body. It is
    /// what publishes to the room, and the server stamps that write with the
    /// new `progressRevision` the receiving device gates on (see the live
    /// listener and `commitLiveProgress`). A
    /// participant's inning/hits/walks change used to reach the live document
    /// carrying no new revision, so the owner ignored it - and then the owner's
    /// next change wrote their own stale value back over it with a revision the
    /// participant *would* accept, silently reverting the participant's edit.
    ///
    /// Because `markLocalProgressChange()` publishes the whole progress
    /// snapshot, callers no longer send a separate per-field `updateLiveFields`
    /// first; that write is what carried the missing revision.
    private func commitLiveProgressChange(field: String, value: Int) {
        defer { markLocalProgressChange() }

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
    }

    private var inningBinding: Binding<Int> {
        intBinding(
            get: { inning },
            set: { newValue in
                inning = newValue
                if activeLiveId != nil {
                    commitLiveProgressChange(field: "inning", value: newValue)
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameInning(ownerUserId: owner, gameId: gid, inning: newValue)

                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].inning = newValue
                }
                debugLog("🧭[PROG] set inning=\(newValue) gid=\(gid)")
                markLocalProgressChange()
            }
        )
    }


    private var hitsBinding: Binding<Int> {
        intBinding(
            get: { hits },
            set: { newValue in
                // Always reflect immediately in local UI, even if persistence targets are unavailable.
                hits = newValue
                if activeLiveId != nil {
                    commitLiveProgressChange(field: "hits", value: newValue)
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameHits(ownerUserId: owner, gameId: gid, hits: newValue)

                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].hits = newValue
                }
                debugLog("🧭[PROG] set hits=\(newValue) gid=\(gid)")
                markLocalProgressChange()
            }
        )
    }

    
    private var walksBinding: Binding<Int> {
        intBinding(
            get: { walks },
            set: { newValue in
                // Always reflect immediately in local UI, even if persistence targets are unavailable.
                walks = newValue
                if activeLiveId != nil {
                    commitLiveProgressChange(field: "walks", value: newValue)
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameWalks(ownerUserId: owner, gameId: gid, walks: newValue)

                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].walks = newValue
                }
                debugLog("🧭[PROG] set walks=\(newValue) gid=\(gid)")
                markLocalProgressChange()
            }
        )
    }

    private var ballsBinding: Binding<Int> {
        intBinding(
            get: { balls },
            set: { newValue in
                updateCount(AtBatCount(balls: newValue, strikes: strikes))
            }
        )
    }

    private var strikesBinding: Binding<Int> {
        intBinding(
            get: { strikes },
            set: { newValue in
                updateCount(AtBatCount(balls: balls, strikes: newValue))
            }
        )
    }

    /// The single entry point for changing the count.
    ///
    /// Every caller used to persist balls/strikes itself and then *conditionally*
    /// call markLocalProgressChange() - the live-game branches returned early and
    /// skipped it, so `lastLocalProgressUpdate` went stale and the next incoming
    /// snapshot was free to overwrite a change this device had just made. Routing
    /// everything through here means the local stamp and revision can never be
    /// skipped, and the redundant per-field writes are gone.
    private func updateCount(_ next: AtBatCount) {
        guard balls != next.balls || strikes != next.strikes else { return }
        balls = next.balls
        strikes = next.strikes
        markLocalProgressChange()
    }

    private var usBinding: Binding<Int> {
        intBinding(
            get: { us },
            set: { newValue in
                us = newValue
                if activeLiveId != nil {
                    commitLiveProgressChange(field: "us", value: newValue)
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameUs(ownerUserId: owner, gameId: gid, us: newValue)

                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].us = newValue
                }
                debugLog("🧭[PROG] set us=\(newValue) gid=\(gid)")
                markLocalProgressChange()
            }
        )
    }

    private var themBinding: Binding<Int> {
        intBinding(
            get: { them },
            set: { newValue in
                them = newValue
                if activeLiveId != nil {
                    commitLiveProgressChange(field: "them", value: newValue)
                    return
                }

                guard let gid = selectedGameId else { return }
                guard let owner = effectiveGameOwnerUserId else { return }
                authManager.updateGameThem(ownerUserId: owner, gameId: gid, them: newValue)

                if let idx = games.firstIndex(where: { $0.id == gid }) {
                    games[idx].them = newValue
                }
                debugLog("🧭[PROG] set them=\(newValue) gid=\(gid)")
                markLocalProgressChange()
            }
        )
    }
    
    private func normalizeJersey(_ s: String?) -> String? {
        guard let s = s else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.allSatisfy({ $0 == "0" }) {
            return trimmed
        }
        let noLeadingZeros = trimmed.drop { $0 == "0" }
        return String(noLeadingZeros)
    }

    private var selectedJerseyNumberDisplay: String? {
        jerseyCells.first(where: { $0.id == selectedBatterId })?.jerseyNumber
    }

    private func heatmapResultIsInsideStrikeZone(_ rawLocation: String) -> Bool {
        let trimmed = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // Preferred modern format.
        if lower.hasPrefix("strike ") { return true }
        if lower.hasPrefix("ball ") { return false }

        // Legacy fallback when prefix was not persisted.
        let legacyStrikeLabels: Set<String> = [
            "up & out", "up", "up & in",
            "out", "middle", "in",
            "↓ & out", "↓", "↓ & in",
            "down & out", "down", "down & in",
            "low & out", "low", "low & in",
            "high"
        ]
        return legacyStrikeLabels.contains(lower)
    }

    private struct BatterHeatmapPitchStat: Identifiable {
        let pitch: String
        let events: [PitchEvent]
        let successCount: Int
        let totalCount: Int

        var id: String { pitch }
        var successRate: Double {
            guard totalCount > 0 else { return 0 }
            return Double(successCount) / Double(totalCount)
        }
        var successPercentText: String { "\(Int((successRate * 100).rounded()))%" }
    }
    private let allHeatmapPitchesKey = "__ALL_PITCHES__"

    private enum BatterHeatmapResultFilter: String, CaseIterable, Identifiable {
        case all = "Strikes+Balls"
        case hideStrikes = "Hide Strikes"
        case hideBalls = "Hide Balls"

        var id: String { rawValue }
    }

    private var selectedBatterHeatmapEvents: [PitchEvent] {
        let sourceEvents = isGame ? gamePitchEvents : pitchEvents
        let selectedBatterIdValue = selectedBatterId?.uuidString
        let selectedJersey = normalizeJersey(selectedJerseyNumberDisplay ?? selectedBatterJersey)
        guard selectedBatterIdValue != nil || selectedJersey != nil else { return [] }

        return sourceEvents.filter { event in
            if !event.supportsLocationAnalytics { return false }
            if isGame, let gid = selectedGameId {
                if let evGameId = event.gameId, !evGameId.isEmpty, evGameId != gid { return false }
            }
            if let selectedBatterIdValue, event.opponentBatterId == selectedBatterIdValue {
                return true
            }
            if let selectedJersey, let evJersey = normalizeJersey(event.opponentJersey), selectedJersey == evJersey {
                return true
            }
            return false
        }
    }

    private var currentSessionSupportsLocationAnalytics: Bool {
        let sourceEvents = isGame ? gamePitchEvents : pitchEvents
        return sourceEvents.contains { event in
            guard event.supportsLocationAnalytics else { return false }
            if isGame, let gid = selectedGameId {
                return event.gameId == gid
            }
            return !isGame
        }
    }

    private var batterHeatmapPitchStats: [BatterHeatmapPitchStat] {
        let grouped = Dictionary(grouping: selectedBatterHeatmapEvents, by: { $0.pitch })
        return grouped.map { pitch, events in
            let successCount = events.filter { heatmapResultIsInsideStrikeZone($0.location) }.count
            return BatterHeatmapPitchStat(
                pitch: pitch,
                events: events.sorted { $0.timestamp < $1.timestamp },
                successCount: successCount,
                totalCount: events.count
            )
        }
        .sorted {
            if $0.successRate != $1.successRate { return $0.successRate > $1.successRate }
            if $0.totalCount != $1.totalCount { return $0.totalCount > $1.totalCount }
            return $0.pitch.localizedCaseInsensitiveCompare($1.pitch) == .orderedAscending
        }
    }

    private var selectedBatterHeatmapPitchResolved: BatterHeatmapPitchStat? {
        if selectedAtBatHeatmapPitch == allHeatmapPitchesKey { return nil }
        if let selected = batterHeatmapPitchStats.first(where: { $0.pitch == selectedAtBatHeatmapPitch }) {
            return selected
        }
        return batterHeatmapPitchStats.first
    }

    private var allBatterHeatmapPitchStat: BatterHeatmapPitchStat {
        let events = selectedBatterHeatmapEvents.sorted { $0.timestamp < $1.timestamp }
        let successCount = events.filter { heatmapResultIsInsideStrikeZone($0.location) }.count
        return BatterHeatmapPitchStat(
            pitch: allHeatmapPitchesKey,
            events: events,
            successCount: successCount,
            totalCount: events.count
        )
    }

    private var selectedBatterHeatmapFilteredEvents: [PitchEvent] {
        let all: [PitchEvent] = {
            if selectedAtBatHeatmapPitch == allHeatmapPitchesKey {
                return allBatterHeatmapPitchStat.events
            }
            return selectedBatterHeatmapPitchResolved?.events ?? []
        }()
        switch atBatHeatmapResultFilter {
        case .all:
            return all
        case .hideStrikes:
            return all.filter { !heatmapResultIsInsideStrikeZone($0.location) }
        case .hideBalls:
            return all.filter { heatmapResultIsInsideStrikeZone($0.location) }
        }
    }

    private var atBatBatterHeatmapSheetView: some View {
        let batterLabel = selectedJerseyNumberDisplay ?? selectedBatterJersey ?? "-"
        let allStat = allBatterHeatmapPitchStat
        let hasUsableSelectedPitchChip: Bool = {
            guard let pitch = selectedBatterHeatmapPitchResolved?.pitch else { return false }
            return effectivePitchesForStrikeZone.contains(pitch)
        }()
        let isAllPitchesSelected = selectedAtBatHeatmapPitch == allHeatmapPitchesKey
        let selectedHeatmapChipColor: Color = {
            guard let selectedPitch = selectedBatterHeatmapPitchResolved?.pitch else { return Color.secondary }
            return colorForPitch(selectedPitch)
        }()
        return NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        let isAllSelected = selectedAtBatHeatmapPitch == allHeatmapPitchesKey
                        Button {
                            selectedAtBatHeatmapPitch = allHeatmapPitchesKey
                        } label: {
                            Text("All \(allStat.successPercentText)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isAllSelected ? .white : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(isAllSelected ? Color.secondary : Color(.systemGray6))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(isAllSelected ? Color.secondary.opacity(0.95) : Color.black.opacity(0.2), lineWidth: isAllSelected ? 2 : 1)
                                )
                        }
                        .buttonStyle(.plain)

                        ForEach(batterHeatmapPitchStats) { stat in
                            let isSelected = selectedAtBatHeatmapPitch == stat.pitch
                            let isAvailableInCurrentTemplate = effectivePitchesForStrikeZone.contains(stat.pitch)
                            let chipColor = colorForPitch(stat.pitch)
                            Button {
                                selectedAtBatHeatmapPitch = stat.pitch
                            } label: {
                                Text(stat.pitch == "Catcher" ? stat.pitch : "\(stat.pitch) \(stat.successPercentText)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(isSelected ? .white : .primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? chipColor : chipColor.opacity(0.2))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(isSelected ? chipColor.opacity(0.95) : chipColor.opacity(0.5), lineWidth: isSelected ? 2 : 1)
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(
                                                Color.black.opacity(isAvailableInCurrentTemplate ? 0 : 0.9),
                                                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                
                Text("(% landed in strike zone)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Picker("Display", selection: $atBatHeatmapResultFilter) {
                    ForEach(BatterHeatmapResultFilter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                StrikeZoneHeatmapView(
                    events: selectedBatterHeatmapFilteredEvents,
                    interactionHint: hasUsableSelectedPitchChip ? "Tap a location to begin a pitch event" : nil,
                    resultChipColor: isAllPitchesSelected ? nil : selectedHeatmapChipColor,
                    resultChipColorResolver: isAllPitchesSelected ? { pitch in
                        colorForPitch(pitch)
                    } : nil,
                    onLocationTap: { location, isStrike in
                        if selectedAtBatHeatmapPitch == allHeatmapPitchesKey {
                            pendingAllPitchesHeatmapTap = (location: location, isStrike: isStrike)
                            showAllPitchesHeatmapPitchPicker = true
                            return
                        }
                        guard let selectedPitchStat = selectedBatterHeatmapPitchResolved else { return }
                        beginCallFromHeatmap(
                            pitch: selectedPitchStat.pitch,
                            location: location,
                            isStrike: isStrike
                        )
                    }
                )
                    .padding(.top, 60)
                    .padding(.horizontal, 6)

                Spacer(minLength: 0)
            }
            .navigationTitle("Batter #\(batterLabel) Heat Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showAtBatHeatmapSheet = false }
                }
            }
            .onAppear {
                if selectedAtBatHeatmapPitch.isEmpty {
                    selectedAtBatHeatmapPitch = allHeatmapPitchesKey
                }
                atBatHeatmapResultFilter = .all
            }
            // Folded "Select the pitch type for this location." into the
            // title and dropped the separate message: closure - same
            // precaution as undoButtonOverlay's conversion nearby (see its
            // comment); a dynamic ForEach button list means this one can't
            // move to appConfirmationDialog outright, but avoiding the
            // heavier actions+message confirmationDialog overload is the
            // same fix in spirit.
            .confirmationDialog("Choose Pitch Type - Select the pitch type for this location.", isPresented: $ui.showAllPitchesHeatmapPitchPicker, titleVisibility: .visible) {
                ForEach(availablePitches(for: selectedTemplate), id: \.self) { pitch in
                    Button(pitch) {
                        guard let pendingTap = pendingAllPitchesHeatmapTap else { return }
                        beginCallFromHeatmap(
                            pitch: pitch,
                            location: pendingTap.location,
                            isStrike: pendingTap.isStrike
                        )
                        pendingAllPitchesHeatmapTap = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingAllPitchesHeatmapTap = nil
                }
            }
        }
    }

    private func calledPitchCodes(pitch: String, location: String, isStrike: Bool) -> [String] {
        if let template = selectedTemplate, useEncrypted(for: template) {
            if let (gridKind, columnIndex, rowIndex) = mapLabelToGridInfo(label: location, isStrike: isStrike) {
                if template.codeMode == .normal {
                    return EncryptedCodeGenerator.generateNormalCalls(
                        template: template,
                        selectedPitch: pitch,
                        gridKind: gridKind,
                        columnIndex: columnIndex,
                        rowIndex: rowIndex
                    )
                }
                return EncryptedCodeGenerator.generateCalls(
                    template: template,
                    selectedPitch: pitch,
                    gridKind: gridKind,
                    columnIndex: columnIndex,
                    rowIndex: rowIndex
                )
            }
            return []
        }

        let fullLabel = "\(isStrike ? "Strike" : "Ball") \(location)"
        return pitchCodeAssignments
            .filter { $0.pitch == pitch && $0.location == fullLabel }
            .map(\.code)
    }

    private func beginCallFromHeatmap(pitch: String, location: String, isStrike: Bool) {
        guard canInitiateCall else { return }
        // If this pitch is not currently available in the active template/grid-key, block and explain.
        if !effectivePitchesForStrikeZone.contains(pitch) {
            let templateName = selectedTemplate?.name ?? "current grid key"
            heatmapUnavailablePitchMessage = "\(pitch) is not available in \(templateName). Change the grid key or select an available pitch."
            showHeatmapUnavailablePitchAlert = true
            return
        }

        pendingHeatmapCall = (pitch: pitch, location: location, isStrike: isStrike)
        showAtBatHeatmapSheet = false
    }

    private func executePendingHeatmapCallIfNeeded() {
        guard let pending = pendingHeatmapCall else { return }
        pendingHeatmapCall = nil

        selectedPitch = pending.pitch
        let newCall = PitchCall(
            pitch: pending.pitch,
            location: pending.location,
            isStrike: pending.isStrike,
            codes: calledPitchCodes(pitch: pending.pitch, location: pending.location, isStrike: pending.isStrike)
        )
        // Let sheet dismissal finish before presenting composer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            handleSetCalledPitch(newCall)
        }
    }

    private func beginCatcherCoachCall() {
        guard currentTrackingMode == .coach else { return }
        guard canInitiateCall else { return }

        selectedPitch = ""
        pendingResultLabel = nil
        actualLocationRecorded = nil
        resultVisualState = nil
        lastTappedPosition = nil

        let placeholderLocation = "Catcher"
        let newCall = PitchCall(
            pitch: "Catcher",
            location: placeholderLocation,
            isStrike: false,
            codes: calledPitchCodes(pitch: "Catcher", location: placeholderLocation, isStrike: false)
        )

        handleSetCalledPitch(newCall)
    }

    private var selectedPitcherName: String {
        if isLiveParticipantViewingGame {
            return liveParticipantDisplayPitcher?.name ?? "Select a pitcher"
        }
        guard let pid = selectedPitcherId else { return "Select a pitcher" }
        guard let pitcher = pitchers.first(where: { $0.id == pid }) else { return "Select a pitcher" }
        if isGame && !pitcher.isActiveOwner(currentUid: authManager.user?.uid) {
            return "Owner only"
        }
        return pitcher.name
    }

    private func atBatCountKey(batterId: String?, jersey: String?) -> String? {
        if let batterId, !batterId.isEmpty { return "id:\(batterId)" }
        let trimmed = jersey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return "jersey:\(trimmed)" }
        return nil
    }

    private func migrateEditedJerseyReferences(
        batterId: String,
        oldJersey: String,
        newJersey: String
    ) {
        let oldNorm = normalizeJersey(oldJersey) ?? oldJersey.trimmingCharacters(in: .whitespacesAndNewlines)
        let newNorm = normalizeJersey(newJersey) ?? newJersey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldNorm.isEmpty, !newNorm.isEmpty, oldNorm != newNorm else { return }

        func shouldReplace(_ event: PitchEvent) -> Bool {
            if event.opponentBatterId == batterId { return true }
            return normalizeJersey(event.opponentJersey) == oldNorm
        }

        // Immediate local UI refresh for cards and lists.
        gamePitchEvents = gamePitchEvents.map { ev in
            var updated = ev
            if shouldReplace(ev) { updated.opponentJersey = newNorm }
            return updated
        }
        pitchEvents = pitchEvents.map { ev in
            var updated = ev
            if shouldReplace(ev) { updated.opponentJersey = newNorm }
            return updated
        }
        if selectedBatterId?.uuidString == batterId {
            selectedBatterJersey = newNorm
        }

        // Persist historical correction in Firestore.
        if let liveId = activeLiveId, !liveId.isEmpty {
            let liveRef = Firestore.firestore()
                .collection("liveGames")
                .document(liveId)
                .collection("pitchEvents")
            updateOpponentJerseyInCollection(
                collectionRef: liveRef,
                batterId: batterId,
                oldJersey: oldNorm,
                newJersey: newNorm
            )
        }

        if let gameId = selectedGameId,
           let owner = effectiveGameOwnerUserId,
           !owner.isEmpty {
            let gameRef = Firestore.firestore()
                .collection("users")
                .document(owner)
                .collection("games")
                .document(gameId)
                .collection("pitchEvents")
            updateOpponentJerseyInCollection(
                collectionRef: gameRef,
                batterId: batterId,
                oldJersey: oldNorm,
                newJersey: newNorm
            )
            return
        }

        // Jersey migration only applies to active game collections.
    }

    private func updateOpponentJerseyInCollection(
        collectionRef: CollectionReference,
        batterId: String,
        oldJersey: String,
        newJersey: String
    ) {
        let db = Firestore.firestore()
        let group = DispatchGroup()
        var merged: [String: QueryDocumentSnapshot] = [:]

        group.enter()
        collectionRef
            .whereField("opponentBatterId", isEqualTo: batterId)
            .getDocuments { snapshot, _ in
                (snapshot?.documents ?? []).forEach { merged[$0.documentID] = $0 }
                group.leave()
            }

        group.enter()
        collectionRef
            .whereField("opponentJersey", isEqualTo: oldJersey)
            .getDocuments { snapshot, _ in
                (snapshot?.documents ?? []).forEach { merged[$0.documentID] = $0 }
                group.leave()
            }

        group.notify(queue: .main) {
            let docs = Array(merged.values)
            guard !docs.isEmpty else { return }

            let chunkSize = 400
            var start = 0
            while start < docs.count {
                let end = min(start + chunkSize, docs.count)
                let slice = docs[start..<end]
                let batch = db.batch()
                slice.forEach { doc in
                    batch.updateData(["opponentJersey": newJersey], forDocument: doc.reference)
                }
                batch.commit { err in
                    if let err {
                        debugLog("❌ migrate jersey batch failed:", err.localizedDescription)
                    }
                }
                start = end
            }
        }
    }

    /// A pitcher that IS selected and isn't ours stays locked, as before.
    /// The "nothing selected" case now also passes when there's a top
    /// action to fall back on: with the confirmation sheet gone, "no
    /// pitcher yet" is an ordinary state the coach fixes by tapping the
    /// flashing badge, and an account with no owned pitchers at all would
    /// otherwise have that button disabled - making the "New Pitcher on
    /// <team>" action it leads to unreachable. Same reasoning as
    /// `noPitcherOptionsAvailable` below.
    private var canSelectPitcherInGame: Bool {
        guard isGame else { return true }
        let uid = authManager.user?.uid
        if let pid = selectedPitcherId, let current = pitchers.first(where: { $0.id == pid }) {
            return current.isActiveOwner(currentUid: uid)
        }
        return pitchers.contains { $0.isActiveOwner(currentUid: uid) }
            || !pitcherPickerTopActions.isEmpty
    }

    private var selectedPitcherForStats: Pitcher? {
        let pid: String? = {
            if activeLiveId != nil {
                return livePitcherId ?? selectedPitcherId
            }
            return selectedPitcherId
        }()
        guard let pid else { return nil }
        if let match = pitchers.first(where: { $0.id == pid }) {
            return match
        }
        // A participant is deliberately never added to the pitcher's
        // sharedWith (see the mirroring comment in
        // startListeningToLivePitchEvents) so authManager.loadPitchers()
        // never returns the owner's pitcher for them, and pitchers.first
        // above always misses. livePitcherId/livePitcherName are plain
        // strings mirrored onto the live doc, so build a throwaway Pitcher
        // from those instead of leaving this nil and stranding any UI
        // (Pitcher Stats) gated on it.
        guard activeLiveId != nil, !isOwnerForActiveGame else { return nil }
        return Pitcher(
            id: pid,
            name: livePitcherName ?? "Pitcher",
            templateId: nil,
            ownerUid: effectiveGameOwnerUserId ?? "",
            sharedWith: [],
            claimedByUid: nil,
            createdAt: nil
        )
    }

    private var pitchersForCurrentGameStats: [Pitcher] {
        guard let gameId = selectedGameId else { return [] }
        let pitcherIds = Set(
            gamePitchEvents.compactMap { event -> String? in
                guard event.gameId == gameId,
                      let pitcherId = event.pitcherId?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !pitcherId.isEmpty else { return nil }
                return pitcherId
            }
        )
        return pitchers.filter { pitcher in
            guard let id = pitcher.id else { return false }
            return pitcherIds.contains(id)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

    private func latestEvent(for cell: JerseyCell) -> PitchEvent? {
        let normalizedSelectedJersey = normalizeJersey(cell.jerseyNumber)
        let sourceEvents = isGame ? gamePitchEvents : pitchEvents
        let filtered = sourceEvents.filter { event in
            if isGame, let gid = selectedGameId {
                if let evGameId = event.gameId, !evGameId.isEmpty, evGameId != gid { return false }
            }
            if let evId = event.opponentBatterId, evId == cell.id.uuidString { return true }
            if let selJersey = normalizedSelectedJersey, let evJersey = normalizeJersey(event.opponentJersey), selJersey == evJersey { return true }
            return false
        }
        return filtered.sorted { $0.timestamp > $1.timestamp }.first
    }

    private struct JerseyDetailPayload: Identifiable {
        let id: String
        let event: PitchEvent

        init(event: PitchEvent) {
            let batterId = event.opponentBatterId?.trimmingCharacters(in: .whitespacesAndNewlines)
            let jersey = event.opponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let batterId, !batterId.isEmpty {
                self.id = "batter:\(batterId)"
            } else if let jersey, !jersey.isEmpty {
                self.id = "jersey:\(jersey)"
            } else {
                // Fallback keeps a stable item id when upstream data is sparse.
                self.id = "detail"
            }
            self.event = event
        }
    }

    private func syncSelectedBatterFromDetail(_ cell: JerseyCell?) {
        let previousSelection = selectedBatterId
        selectedBatterId = cell?.id
        selectedBatterJersey = cell?.jerseyNumber

        if previousSelection != cell?.id {
            syncCountFromComposer(balls: 0, strikes: 0)
        }

        if let liveId = activeLiveId, !liveId.isEmpty {
            var fields: [String: Any] = [:]
            if let cell {
                fields["selectedBatterId"] = cell.id.uuidString
                fields["selectedBatterJersey"] = cell.jerseyNumber
            } else {
                fields["selectedBatterId"] = FieldValue.delete()
                fields["selectedBatterJersey"] = FieldValue.delete()
            }
            LiveGameService.shared.updateLiveFields(liveId: liveId, fields: fields)
            return
        }

        guard
            let gameId = selectedGameId,
            let owner = effectiveGameOwnerUserId,
            !owner.isEmpty
        else { return }

        authManager.updateGameSelectedBatter(
            ownerUserId: owner,
            gameId: gameId,
            selectedBatterId: cell?.id.uuidString,
            selectedBatterJersey: cell?.jerseyNumber
        )
    }

    private func persistLineupFromDetail() {
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
            return
        }

        if let gameId = selectedGameId,
           let owner = effectiveGameOwnerUserId,
           !owner.isEmpty {
            authManager.updateGameLineup(
                ownerUserId: owner,
                gameId: gameId,
                jerseyNumbers: jerseys,
                batterIds: batterIds
            )
        }
    }

    /// Drag-handle reorder from the pin sheet's lineup strip. Rearranges
    /// only - this runs repeatedly while a finger is moving, so the write
    /// waits for `persistLineupFromDetail()` on drop.
    ///
    /// Replaced `moveBatterFromDetail(_:direction:)`, which the deleted
    /// Up/Down buttons drove one step at a time.
    private func reorderBatterFromDetail(_ moving: JerseyCell, to target: JerseyCell) {
        guard let from = jerseyCells.firstIndex(where: { $0.id == moving.id }),
              let to = jerseyCells.firstIndex(where: { $0.id == target.id }),
              from != to else { return }
        // `move(fromOffsets:toOffset:)`, not remove + insert.
        //
        // Remove + insert reads to `ForEach` as a delete *and* an insert, so
        // for the length of the animation the same jersey is drawn in both
        // places - the phantom extra chip that appeared mid-drag. A move is
        // a single operation and animates as one.
        //
        // It also fixes an off-by-one that remove + insert had: `to` was
        // computed before the removal, so a forward drag landed one position
        // further than intended. The +1 below is this API's convention for
        // a forward move.
        withAnimation {
            jerseyCells.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: to > from ? to + 1 : to
            )
        }
    }

    private func deleteBatterFromDetail(_ cell: JerseyCell) {
        guard let idx = jerseyCells.firstIndex(where: { $0.id == cell.id }) else { return }
        let removed = jerseyCells.remove(at: idx)
        persistLineupFromDetail()

        // The sheet always closes on a delete. It used to re-present itself
        // on a fallback cell (openJerseyDetail(keepSheetVisible: true)),
        // which read as "the pin sheet relaunches by itself showing a
        // random jersey" - and the fallback was an index-based neighbour
        // picked from the FULL lineup, so once the At Bat scroll became
        // side-scoped it could even land on a batter from the other team,
        // i.e. one not visible in the strip at all.
        jerseyDetailPayload = nil

        guard selectedBatterId == removed.id else { return }

        // Keeping a batter selected is still worth doing (balls/strikes
        // hang off one), but only one that's actually on the batting side.
        let sameSide = visibleJerseyCells
        let fallback = sameSide.indices.contains(idx)
            ? sameSide[idx]
            : sameSide.last
        syncSelectedBatterFromDetail(fallback)
    }

    private func openJerseyDetail(for cell: JerseyCell, keepSheetVisible: Bool = false) async {
        let placeholder = await MainActor.run { placeholderEvent(for: cell) }
        await MainActor.run {
            pendingJerseyDetailCell = cell
            didAutoRetryJerseyDetail = false
            syncSelectedBatterFromDetail(cell)
            jerseyDetailEvent = placeholder
            if !keepSheetVisible {
                jerseyDetailPayload = nil
                showJerseyDetailSheet = false
            }
            // Open immediately so no-data batters don't wait on fetch/listener retries.
            jerseyDetailPayload = JerseyDetailPayload(event: placeholder)
        }

        if isGame {
            if let liveId = activeLiveId, !liveId.isEmpty {
                await MainActor.run {
                    startListeningToLivePitchEvents(liveId: liveId)
                }
            } else {
                await MainActor.run {
                    startListeningToGamePitchEvents()
                }
                if gamePitchEvents.isEmpty, let owner = effectiveGameOwnerUserId, let gid = selectedGameId {
                    let events = await loadGamePitchEventsAsync(ownerUserId: owner, gameId: gid)
                    if !events.isEmpty {
                        await MainActor.run {
                            gamePitchEvents = events
                        }
                    }
                }
            }
        } else {
            if pitchEvents.isEmpty {
                let events = await loadPitchEventsAsync()
                if !events.isEmpty {
                    await MainActor.run {
                        pitchEvents = events
                    }
                }
            }
        }

        let maxAttempts = 8
        for _ in 0..<maxAttempts {
            let event = await MainActor.run { latestEvent(for: cell) }
            if let event {
                await MainActor.run {
                    jerseyDetailEvent = event
                    jerseyDetailPayload = JerseyDetailPayload(event: event)
                }
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func placeholderEvent(for cell: JerseyCell) -> PitchEvent {
        PitchEvent(
            id: nil,
            timestamp: Date(),
            pitch: "No pitches yet",
            location: "-",
            codes: [],
            isStrike: false,
            isBall: nil,
            mode: .game,
            calledPitch: nil,
            batterSide: .right,
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
            gameId: selectedGameId,
            opponentJersey: cell.jerseyNumber,
            opponentBatterId: cell.id.uuidString,
            pitcherId: selectedPitcherId,
            createdByUid: authManager.user?.uid
        )
    }

    private func loadGamePitchEventsAsync(ownerUserId: String, gameId: String) async -> [PitchEvent] {
        await withCheckedContinuation { continuation in
            authManager.loadGamePitchEvents(ownerUserId: ownerUserId, gameId: gameId) { events in
                continuation.resume(returning: events)
            }
        }
    }

    private func loadPitchEventsAsync() async -> [PitchEvent] {
        await withCheckedContinuation { continuation in
            authManager.loadPitchEvents { events in
                continuation.resume(returning: events)
            }
        }
    }

    private func debugLogJerseyDetailState(reason: String, cell: JerseyCell) {
        let total = isGame ? gamePitchEvents.count : pitchEvents.count
        let normalizedSelectedJersey = normalizeJersey(cell.jerseyNumber)
        let sample = (isGame ? gamePitchEvents : pitchEvents).suffix(8)
        let sampleSummary = sample.map { event in
            let gid = event.gameId ?? "-"
            let batterId = event.opponentBatterId ?? "-"
            let jersey = event.opponentJersey ?? "-"
            return "[g:\(gid) batter:\(batterId) jersey:\(jersey) pitch:\(event.pitch) ts:\(event.timestamp.timeIntervalSince1970)]"
        }.joined(separator: " | ")

        debugLog("⚠️ Jersey detail miss (\(reason)) cell=\(cell.jerseyNumber) id=\(cell.id.uuidString) normalized=\(normalizedSelectedJersey ?? "nil") totalEvents=\(total) isGame=\(isGame) selectedGameId=\(selectedGameId ?? "nil") activeLiveId=\(activeLiveId ?? "nil") sample=\(sampleSummary)")
    }

    private func debugLogJerseyDetailOpen(cell: JerseyCell, context: String) {
        let normalizedSelectedJersey = normalizeJersey(cell.jerseyNumber)
        let eventCount = isGame ? gamePitchEvents.count : pitchEvents.count
        debugLog("🟨 Jersey detail open (\(context)) cell=\(cell.jerseyNumber) id=\(cell.id.uuidString) normalized=\(normalizedSelectedJersey ?? "nil") selectedBatterId=\(selectedBatterId?.uuidString ?? "nil") selectedBatterJersey=\(selectedBatterJersey ?? "nil") isGame=\(isGame) selectedGameId=\(selectedGameId ?? "nil") activeLiveId=\(activeLiveId ?? "nil") events=\(eventCount)")
    }

    private var cardsAndOverlay: some View {
        VStack(spacing: 8) {
            overlayTabsHeader

            Divider()
                .padding(.top, 5)

            overlayContent
                .padding(.top, 0)
                .frame(maxWidth: .infinity)
                .frame(height: 250, alignment: .top)
                .overlay(alignment: .top) {
                    if overlayTab == .cards {
                        cardsFilterButton
                            .offset(y: -8)
                    }
                }
        }
        .transition(.opacity)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(.regularMaterial)
        .sheet(isPresented: $ui.showCardsFullScreenSheet, onDismiss: {
            cardsEditTargetEventID = nil
        }) {
            pitchResultSheetBody(
                controlButtonsOffsetY: 10,
                controlButtonsVerticalPadding: 20,
                initialJerseyFilter: selectedJerseyNumberDisplay ?? selectedBatterJersey,
                initialSelectedEventID: cardsEditTargetEventID,
                shouldAutoOpenEditOutcome: false,
                onGearTapOverride: nil
            )
                .ignoresSafeArea()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .fixedAppDynamicType()
        }
    }

    private var overlayTabsHeader: some View {
        Group {
            if sessionManager.currentMode == .game {
                gameOverlayHeaderRow
            } else {
                legacyOverlayTabsRow
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
    }

    /// Compact single-row header: [B/S/O display] [Cards] [Us] [Them].
    /// The count box is read-only — tapping it (like tapping "Cards") just
    /// switches `overlayTab`, and the active box gets a stroke outline.
    /// All editing happens in the revealed panel below (progressOverlayContent).
    ///
    /// The filter button used to float below "Cards" via a GeometryReader +
    /// PreferenceKey reading the pill's frame — too fragile, it silently
    /// failed to appear. Nesting it directly under the pill in ordinary
    /// SwiftUI layout instead can't fail to render.
    private var gameOverlayHeaderRow: some View {
        HStack(alignment: .top, spacing: 8) {
            countDisplaySegment
            cardsSegmentButton
            scoreSegment(label: sideLabel(for: .home, maxLength: 7), value: usBinding.wrappedValue)
            scoreSegment(label: sideLabel(for: .away, maxLength: 7), value: themBinding.wrappedValue)
        }
        .foregroundStyle(.black)
    }

    private var countDisplaySegment: some View {
        let isActive = overlayTab == .progress
        return Button {
            overlayTab = .progress
        } label: {
            HStack(spacing: 10) {
                // Swapped (not just a different color) when tracking Away,
                // so the active side reads at a glance from the same two
                // colors instead of introducing a third.
                staticCountDots(prefix: "B", count: balls, maxCount: 3, filledColor: activeSide == .away ? .green : .red, shape: .circle)
                staticCountDots(prefix: "S", count: strikes, maxCount: 2, filledColor: activeSide == .away ? .red : .green, shape: .circle)
                staticCountDots(prefix: "O", count: outs, maxCount: 3, filledColor: .primary, shape: .square)
                    .scaleEffect(showOutsFlash ? 1.08 : 1.0)
                    .shadow(color: showOutsFlash ? Color.red.opacity(0.35) : .clear, radius: showOutsFlash ? 8 : 0, x: 0, y: 0)
                    .animation(.easeInOut(duration: 0.18), value: showOutsFlash)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit Count, Inning, Hits, Walks and Score")
    }

    private func staticCountDots(
        prefix: String,
        count: Int,
        maxCount: Int,
        filledColor: Color,
        shape: CountDotShape
    ) -> some View {
        HStack(spacing: 4) {
            Text(prefix)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
            HStack(spacing: 3) {
                ForEach(0..<maxCount, id: \.self) { idx in
                    Image(systemName: countDotSystemImageName(filled: idx < max(0, min(maxCount, count)), shape: shape))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(idx < max(0, min(maxCount, count)) ? filledColor : Color.primary.opacity(0.5))
                }
            }
        }
    }

    private var cardsSegmentButton: some View {
        let isActive = overlayTab == .cards
        // Icon rather than the word "Cards": this row also carries both
        // teams' score pills, and since those became real team names instead
        // of "Us"/"Them" the row had no width to spare.
        return Button {
            overlayTab = .cards
        } label: {
            Image(systemName: "baseball")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cards")
    }

    /// Floats above the cards scroll (see `cardsAndOverlay`) rather than
    /// reserving its own row beneath the "Cards" pill — that used to push
    /// the whole header taller and leave a gap above the card list.
    private var cardsFilterButton: some View {
        let latestEditableEvent = filteredEvents.first(where: { $0.id != nil })
        return Button {
            cardsEditTargetEventID = latestEditableEvent?.id
            showCardsFullScreenSheet = true
        } label: {
            Image(systemName: "slider.horizontal.2.arrow.trianglehead.counterclockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(9)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(latestEditableEvent?.id == nil)
        .accessibilityLabel("Filter and Edit Cards")
    }

    private func scoreSegment(label: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.subheadline)
            Text("\(value)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.blue)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Pre-existing tab bar, kept for non-game modes (practice/scout), where
    /// the compact game-score header above doesn't apply.
    private var legacyOverlayTabsRow: some View {
        let showCards = (selectedTemplate != nil) || (isGame && (activeLiveId != nil || !isOwnerForActiveGame))
        let latestEditableEvent = filteredEvents.first(where: { $0.id != nil })
        return HStack(spacing: 6) {
            if showCards {
                // Mid-expression AnyView erasure, same reasoning as
                // undoButtonOverlay's twin (see the comment there) - this
                // button has the identical shape and sits inside the same
                // deeply nested strikeZoneArea chain, so it's erased
                // pre-emptively even though it hasn't specifically crashed.
                let undoButton = AnyView(
                    Button {
                        showUndoConfirm = true
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(lastPersistedEventInCurrentMode == nil)
                    .accessibilityLabel("Undo Last Pitch")
                )
                // The confirm dialog is attached once at baseBody's root,
                // not here: SwiftUI clips an overlay's hit-testing to its
                // parent's frame, so a dialog hung off this little button
                // renders full-screen but only accepts taps inside the
                // button (CLAUDE.md, "Dialogs"). Two of them were bound to
                // $ui.showUndoConfirm - this one and the zone corner button's
                // - so both also presented at once.
                undoButton
            }

            Spacer(minLength: 0)

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

            Spacer(minLength: 0)

            if showCards {
                Button {
                    cardsEditTargetEventID = latestEditableEvent?.id
                    showCardsFullScreenSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.2.arrow.trianglehead.counterclockwise")
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(latestEditableEvent?.id == nil)
                .accessibilityLabel("Edit Last Result")
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 6)
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .foregroundColor(isSelected ? .black : .black.opacity(0.4))
                .padding(.horizontal, 4)
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
    /// Undo moved out to a floating button beside the strike zone
    /// (`undoButtonOverlay`), and the filter/edit button (`cardsFilterButton`)
    /// floats as an overlay on top of `overlayContent` in `cardsAndOverlay` —
    /// so this view is just the card list now, no floating buttons of its own.
    private var cardsOverlayContent: some View {
        let showCards = (selectedTemplate != nil) || (isGame && (activeLiveId != nil || !isOwnerForActiveGame))
        if showCards {
            pitchResultSheetBody(
                controlButtonsOffsetY: -30,
                controlButtonsVerticalPadding: 2,
                initialJerseyFilter: nil,
                showTopControls: false,
                initialSelectedEventID: cardsEditTargetEventID,
                shouldAutoOpenEditOutcome: false,
                onGearTapOverride: { showCardsFullScreenSheet = true }
            )
            .padding(.top, 6)
            .frame(maxWidth: .infinity, minHeight: 170)
        } else {
            EmptyView()
                .frame(maxWidth: .infinity, minHeight: 170)
        }
    }

    private func pitchResultSheetBody(
        controlButtonsOffsetY: CGFloat,
        controlButtonsVerticalPadding: CGFloat,
        initialJerseyFilter: String? = nil,
        showTopControls: Bool = true,
        initialSelectedEventID: String? = nil,
        shouldAutoOpenEditOutcome: Bool = false,
        onGearTapOverride: (() -> Void)? = nil
    ) -> some View {
        PitchResultSheet(
            allEvents: filteredEvents,
            games: games,
            templates: templates,
            pitchers: pitchers,
            isParticipant: (isGame && !isOwnerForActiveGame),
            selectedPlayerName: selectedPitcherName,
            gameOwnerUserId: effectiveGameOwnerUserId,
            liveGameId: activeLiveId,
            sharedDeletedEventIDs: sharedDeletedEventIDs,
            onDeleteEventIDs: { ids in
                sharedDeletedEventIDs.formUnion(ids)
            },
            sharedEditedEventOverrides: sharedEditedEventOverrides,
            onApplyEditedEventOverride: { eventId, event in
                sharedEditedEventOverrides[eventId] = event
            },
            sharedPitcherOverrides: sharedPitcherOverrides,
            onApplyPitcherOverride: { eventIds, pitcherId in
                for id in eventIds {
                    sharedPitcherOverrides[id] = pitcherId
                }
            },
            sharedBatterJerseyOverrides: sharedBatterJerseyOverrides,
            onApplyBatterJerseyOverride: { eventIds, jersey in
                for id in eventIds {
                    sharedBatterJerseyOverrides[id] = jersey
                }
            },
            initialJerseyFilter: initialJerseyFilter,
            initialSelectedEventID: initialSelectedEventID,
            shouldAutoOpenEditOutcome: shouldAutoOpenEditOutcome,
            showTopControls: showTopControls,
            onGearTapOverride: onGearTapOverride,
            controlButtonsOffsetY: controlButtonsOffsetY,
            controlButtonsVerticalPadding: controlButtonsVerticalPadding,
            currentCountSeed: (balls: balls, strikes: strikes),
            onCountChanged: { newBalls, newStrikes in
                syncCountFromComposer(balls: newBalls, strikes: newStrikes)
            }
        )
        .environmentObject(authManager)
        .environmentObject(sessionManager)
    }

    private var calledPitchLayer: some View {
        Group {
            if let call = calledPitch {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        CalledPitchView(
                            pitchResultBannerPhase: $pitchResultBannerPhase,
                            isRecordingResult: $ui.isRecordingResult,
                            activeCalledPitchId: $ui.activeCalledPitchId,
                            pitchFirst: $ui.pitchFirst,
                            autoPitchOnlyEnabled: $ui.autoPitchOnlyEnabled,
                            liveId: activeLiveId,
                            call: call,
                            pitchCodeAssignments: pitchCodeAssignments,
                            batterSide: batterSide,
                            template: selectedTemplate,
                            isEncryptedMode: selectedTemplate.map { useEncrypted(for: $0) } ?? false,
                            onDeferDisplayCode: { colorName, code in
                                deferredDisplayCode = (colorName: colorName, code: code)
                                ensureAutoLiveSessionIfNeeded()
                            }
                        )
                        .transition(.opacity)
                        .padding(.top, 4)
                        .onAppear { handleCalledPitchAppear() }
                        .onDisappear { handleCalledPitchDisappear() }

                        if showConfirmSheet {
                            gatedPitchResultSheetView
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: effectiveScreenSize.height * 0.78)
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
        ProgressGameView(
            homeTeamLabel: sideLabel(for: .home, maxLength: 6).uppercased(),
            awayTeamLabel: sideLabel(for: .away, maxLength: 6).uppercased(),
            ownerUserId: effectiveGameOwnerUserId,
            balls: ballsBinding,
            strikes: strikesBinding,
            outs: outs,
            showOutsFlash: showOutsFlash,
            onOutsTapIndex: { idx in
                pendingOutsResetWorkItem?.cancel()
                let value = idx + 1
                let next = (outs == value) ? max(0, value - 1) : value
                updateOuts(next)
                if next >= 3 {
                    lastOutResetEventIdentity = nil
                    lastOutResetPreviousOuts = nil
                    scheduleOutsResetToZero()
                }
            },
            inning: inningBinding,
            hits: hitsBinding,
            walks: walksBinding,
            us: usBinding,
            them: themBinding,
            selectedGameId: $ui.selectedGameId,
            onProgressChange: {
                markLocalProgressChange()
            }
        )
        .environmentObject(authManager)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .top)
    }


    private var headerContainer: some View {
        let screen = effectiveScreenSize

        return VStack(spacing: 4) {
            topBar
        }
        .frame(
            width: screen.width * 0.94   // 94% of screen width
        )
        .fixedSize(horizontal: false, vertical: true)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thickMaterial)
                .shadow(color: .black.opacity(0.7), radius: 6, x: 0, y: 6)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
        .padding(.horizontal)
        .padding(.top, 6)
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

    private var sidebarColumnWidth: CGFloat { 60 }

    private var topControlRowHeight: CGFloat { 92 }
    private var sidebarControlPanelHeight: CGFloat { 90 }
    
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
        VStack(spacing: 0) {
            mainStrikeZoneSection
                .padding(.bottom, 16)

            Spacer(minLength: 0)

            cardsAndOverlay
        }
    }
    
    /// True while the content section is blurred *and* non-interactive for
    /// want of any code grid key at all. `selectedTemplate` is only nil
    /// when the account has zero keys or templates haven't loaded yet -
    /// `loadTemplates` falls back to the first one otherwise - so this is
    /// not the same thing as "this game has no key of its own"
    /// (`needsKeyForThisGame`), which is an ordinary state with a live
    /// tracker behind it.
    ///
    /// Shared so everything that would be pointless while nothing down
    /// there can be tapped can stay quiet.
    /// The card's own condition, and deliberately *not* the blur's. The
    /// blur asks "is a key selected"; the card speaks about the key list,
    /// so only the key list may answer it. Keying the card off the
    /// selection is what let it keep insisting there was no key on a screen
    /// whose picker was already offering one.
    ///
    /// `visibleTemplates`, not `templates`: archiving is a local hide, and
    /// archiving your last key leaves `templates` full, `selectedTemplate`
    /// nil (Archive clears it) and the tracker just as unusable as having
    /// none at all. Testing `templates.isEmpty` there would blur the screen
    /// and explain nothing.
    ///
    /// `didLoadTemplates` keeps it quiet during the launch window, when the
    /// list is empty only because it hasn't arrived.
    private var hasNoUsableCodeGridKey: Bool {
        didLoadTemplates && visibleTemplates.isEmpty
    }

    /// Distinguishes "you've never made a key" from "all your keys are
    /// archived" - same dead tracker, completely different fix.
    private var allCodeGridKeysAreArchived: Bool {
        hasNoUsableCodeGridKey && !templates.isEmpty
    }

    private var isContentSectionInert: Bool {
        let isActiveLiveParticipant = (activeLiveId != nil && isGame && !isOwnerForActiveGame)
        return selectedTemplate == nil && !isActiveLiveParticipant
    }

    private var contentSectionDimmed: some View {
        let isDimmed = isContentSectionInert
        return contentSection
            .opacity(isDimmed ? 0.6 : 1.0)
            .blur(radius: isDimmed ? 4 : 0)
            .allowsHitTesting(!isDimmed)
            .animation(.easeInOut(duration: 0.3), value: selectedTemplate)
            // Attached AFTER .allowsHitTesting(false), which is the only
            // reason this stays tappable: the overlay is a sibling of the
            // disabled content, not a child of it. It also has to sit here,
            // at the root of the whole section - SwiftUI clips an overlay's
            // hit-testing to its parent's frame, so hanging it off a
            // subview would render it full-screen but accept taps in only
            // that subview's rows (the Sign Out dialog bug in CLAUDE.md).
            //
            // Gated on templates having actually loaded: `selectedTemplate`
            // is nil for the whole launch window before `loadTemplates`
            // returns, and announcing "no key" at every launch would be a
            // lie that then disappears.
            .overlay {
                if isDimmed && hasNoUsableCodeGridKey {
                    NoCodeGridKeyBlocker(
                        allArchived: allCodeGridKeysAreArchived,
                        onOpenKeys: { requestCodeGridKeys(createNew: !allCodeGridKeysAreArchived) }
                    )
                }
            }
    }

    /// Takes the tracker out of its keyless state the moment a key exists,
    /// by whatever route it arrived - created in Home, pulled in by a
    /// reload, purchased, shared in.
    ///
    /// Without this the tracker stayed blurred behind
    /// `NoCodeGridKeyBlocker` after the coach created their very first key.
    /// `handleSavedTemplate` appends to the `templates` binding - which is
    /// why the Key picker could already select the new key - but never
    /// touches `selectedTemplate`, and `isContentSectionInert` keys off
    /// `selectedTemplate`, not off whether any key exists. So the fix
    /// belongs here rather than at that one save site: every other way a
    /// first key can appear had the same hole.
    ///
    /// `applyTemplate` rather than a bare assignment so the pitch chips and
    /// code assignments come with it (a bare `selectedTemplate = x` lifts
    /// the blur onto an unusable strike zone). Source `.live` because the
    /// app chose this, not the coach - `.user` would lock the live template
    /// override and publish the choice to a live room.
    /// `visibleTemplates` only - never `templates`. Adopting a hidden key
    /// here would silently undo an Archive the coach had just performed,
    /// and leave the tracker running on a key they'd deliberately put away.
    /// With everything archived the right outcome is the blur plus the card
    /// telling them so.
    private func adoptFirstTemplateIfNoneSelected() {
        guard selectedTemplate == nil else { return }
        guard let first = visibleTemplates.first else { return }
        applyTemplate(first, source: .live)
    }

    /// The one action that clears a keyless tracker. Switches to the Home
    /// tab and asks it to open Code Grid Keys with a fresh key editor.
    ///
    /// The post is deferred a run-loop turn because the Home tab's body -
    /// and so its `.onReceive` - isn't subscribed until the TabView has
    /// actually selected it. Worst case the notification is missed and the
    /// coach lands on Home with the section collapsed, one tap from the
    /// same place; the tab switch itself is what guarantees they're never
    /// stuck behind the blur.
    /// `createNew: false` when keys exist but are all archived - opening a
    /// blank editor would be the wrong answer there, so Home just expands
    /// Code Grid Keys with the archived list revealed, where Unhide sits.
    private func requestCodeGridKeys(createNew: Bool) {
        activeHomeArea = .home
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .createCodeGridKeyRequested,
                object: nil,
                userInfo: ["createNew": createNew]
            )
        }
    }

    private var shouldBlurForPitchResultSelection: Bool {
        let calledPitchName = calledPitch?.pitch.trimmingCharacters(in: .whitespacesAndNewlines)
        return currentTrackingMode == .coach &&
        calledPitch != nil &&
        calledPitchName != "Catcher" &&
        isRecordingResult &&
        pendingResultLabel == nil
    }

    /// Both of these bind through locals captured BEFORE the closures are
    /// formed - `sessionManager` is a class, so that capture is one pointer,
    /// and `$ui.showConfirmSheet` / `$calledPitch` capture only their @State
    /// boxes. Writing `sessionManager.currentMode` or `showConfirmSheet`
    /// directly inside the closure bodies instead implicitly captures
    /// `self`, and `self` is a struct with hundreds of stored properties -
    /// each such closure then emits a full `outlined init with copy of
    /// PitchTrackerView` into this getter's stack frame, which is what blew
    /// the stack at `___chkstk_darwin` here. Semantics are unchanged: the
    /// closures still read live state through the reference and the boxes.
    private var confirmSheetBinding: Binding<Bool> {
        let manager = sessionManager
        let confirmSheet = $ui.showConfirmSheet
        return Binding<Bool>(
            get: { manager.currentMode == .game && confirmSheet.wrappedValue },
            set: { newValue in
                // Keep the sheet hidden outside game mode.
                confirmSheet.wrappedValue = (manager.currentMode == .game) ? newValue : false
            }
        )
    }

    private var calledPitchComposerBinding: Binding<Bool> {
        let trackingMode = $currentTrackingMode
        let call = $calledPitch
        // The only part that genuinely needs the view: resetCallAndResultUIState
        // touches a dozen @State properties. Kept to ONE capture, in this
        // getter's own frame.
        let reset: () -> Void = { resetCallAndResultUIState() }
        return Binding<Bool>(
            get: { trackingMode.wrappedValue != .scout && call.wrappedValue != nil },
            set: { newValue in
                if !newValue {
                    reset()
                }
            }
        )
    }

    private var calledPitchComposerDetents: Set<PresentationDetent> {
        return [.fraction(0.28), .fraction(0.5), .large]
    }

    @ViewBuilder
    private var calledPitchComposerSheetView: some View {
        if let call = calledPitch {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    CalledPitchView(
                        pitchResultBannerPhase: $pitchResultBannerPhase,
                        isRecordingResult: $ui.isRecordingResult,
                        activeCalledPitchId: $ui.activeCalledPitchId,
                        pitchFirst: $ui.pitchFirst,
                        autoPitchOnlyEnabled: $ui.autoPitchOnlyEnabled,
                        liveId: activeLiveId,
                        call: call,
                        pitchCodeAssignments: pitchCodeAssignments,
                            batterSide: batterSide,
                            template: selectedTemplate,
                            isEncryptedMode: selectedTemplate.map { useEncrypted(for: $0) } ?? false,
                            onDeferDisplayCode: { colorName, code in
                                deferredDisplayCode = (colorName: colorName, code: code)
                                ensureAutoLiveSessionIfNeeded()
                        }
                    )
                    .padding(.top, 4)

                    if showCatcherEstimatePrompt, let call = catcherRealCall {
                        catcherEstimateSheetView(for: call)
                    } else {
                        gatedPitchResultSheetView
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
            }
        } else {
            Color.clear.frame(height: 1)
        }
    }

    /// The observed catcher-mode call once it carries a real (non-placeholder)
    /// location - i.e. once the coach has tapped where the pitch actually
    /// ended up. `beginCatcherCoachCall()` seeds `calledPitch` with a
    /// placeholder location of "Catcher" before that tap happens.
    private var catcherRealCall: PitchCall? {
        guard let calledPitch, calledPitch.pitch.trimmingCharacters(in: .whitespacesAndNewlines) == "Catcher" else {
            return nil
        }
        let loc = calledPitch.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return (loc.isEmpty || loc == "Catcher") ? nil : calledPitch
    }

    private var showCatcherEstimatePrompt: Bool {
        catcherRealCall != nil && !catcherEstimateDismissed
    }

    private func catcherEstimateSheetView(for call: PitchCall) -> some View {
        CatcherEstimateView(
            resultCall: call,
            batterSide: batterSide,
            pitchOptions: ["Catcher"] + (selectedTemplate?.pitches ?? []),
            draftPitch: $ui.catcherEstimateDraftPitch,
            draftLocation: $ui.catcherEstimateDraftLocation,
            onReset: {
                catcherEstimateDraftPitch = "Catcher"
                catcherEstimateDraftLocation = nil
            },
            onSkip: {
                catcherEstimate = nil
                catcherEstimateDismissed = true
            },
            onDone: {
                guard let location = catcherEstimateDraftLocation else { return }
                let isStrike = location.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Strike ")
                catcherEstimate = PitchCall(
                    pitch: catcherEstimateDraftPitch,
                    location: location,
                    isStrike: isStrike,
                    codes: []
                )
                catcherEstimateDismissed = true
            }
        )
        .padding(.horizontal, 12)
    }

    private var gatedPitchResultSheetView: some View {
        ZStack {
            pitchResultSheetView
                .padding(.horizontal, 12)
                .blur(radius: shouldBlurForPitchResultSelection ? 10 : 0)
                .opacity(shouldBlurForPitchResultSelection ? 0.72 : 1)
                .allowsHitTesting(!shouldBlurForPitchResultSelection)

            if shouldBlurForPitchResultSelection {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
                    .opacity(0.54)
                    .padding(.horizontal, 12)
                    .allowsHitTesting(true)
                    .accessibilityLabel("Select a pitch result location on the strike zone before entering result details.")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shouldBlurForPitchResultSelection)
    }
    
    // MARK: - Extracted subviews to help type-checker
    private var topBar: some View {
        HStack(spacing: 6) {
            if isGame && !isOwnerForActiveGame && activeLiveId != nil {
                Text("Pitch Events: Assistant")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
            }

            if !(isGame && !isOwnerForActiveGame) {
                topBarMenu
                    .layoutPriority(1)
            }

            Spacer(minLength: 4)

            if isGame && isOwnerForActiveGame {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Pitching")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    usThemControl
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    /// Left side of the top bar - a single dropdown for the two things that
    /// used to be separate always-visible controls (the Key/template picker
    /// and Invite Assistant). The gear/Settings button that used to sit on
    /// the right is gone entirely - the bottom Home tab already reaches the
    /// same place (`settingsButton`'s action was just `activeHomeArea = .home`).
    private var topBarMenu: some View {
        Menu {
            // With no keys to choose from, the Key item used to be present
            // but disabled - the control the coach reaches for when the
            // tracker is blurred, doing nothing. Offer the fix instead.
            if visibleTemplates.isEmpty {
                Button {
                    requestCodeGridKeys(createNew: !allCodeGridKeysAreArchived)
                } label: {
                    Label(
                        allCodeGridKeysAreArchived ? "Open Code Grid Keys" : "Create a Key",
                        systemImage: "key.badge.plus"
                    )
                }
            } else {
                Button {
                    showGridKeySheet = true
                } label: {
                    Label("Key", systemImage: "key.fill")
                }
            }

            Button {
                triggerAssistantCodeLink()
            } label: {
                Label("Invite Assistant", systemImage: "person.badge.plus")
            }
        } label: {
            topBarMenuLabel
        }
        // Attached to the Menu itself (a stable view), not to anything
        // inside its transient popover content - a .sheet/.confirmationDialog
        // nested inside a Menu's own items is a known-fragile pattern in
        // this codebase (see the "Menu loses scroll position" note in
        // CLAUDE.md); this dialog fires from the Menu's own action closure
        // via $ui.showCodeShareModePicker instead, same as before.
        .confirmationDialog(
            "",
            isPresented: $ui.showCodeShareModePicker,
            titleVisibility: .hidden
        ) {
            Button("Create Invite Link") {
                codeShareInitialTab = 0
                inviteSheetOpenedAt = Date()
                inviteSheetDismissArmed = true
                showCodeShareSheet = true
            }

            if let liveId = activeLiveId, !liveId.isEmpty {
                // Only the owner reaches this menu, and this tears down
                // the owner's whole session - so say so, and actually
                // end the room. It used to write `connection.connected
                // = false` and stop locally, which the partner ignored:
                // they stayed joined and kept recording into a room the
                // owner was no longer mirroring.
                Button("End Live Session", role: .destructive) {
                    LiveGameService.shared.endLiveSession(liveId: liveId)
                    // Deliberately does NOT clear
                    // didAutoCreateLiveSessionForGameId. Doing so let
                    // ensureAutoLiveSessionIfNeeded spin up a new room
                    // and code on the very next called pitch, silently
                    // undoing an explicitly destructive action and
                    // leaving orphan joinCodes behind. Re-inviting has
                    // its own path: CodeShareSheet's Generate button
                    // calls createLiveGameAndJoinCode directly.
                    //
                    // Drop any call deferred while waiting for a room,
                    // so it cannot surface in a session created later.
                    deferredPendingPitch = nil
                    endLiveSessionLocally(keepCurrentGame: isOwnerForActiveGame)
                    showCodeShareModePicker = false
                }
            }

            Button("Cancel", role: .cancel) { }
        }
    }

    private var topBarMenuLabel: some View {
        let currentLabel = selectedTemplate?.name ?? "Select a template"
        let keyPrefix = currentTrackingMode == .scout ? "Pitch Key: " : "Key: "
        let widestLabel = ([currentLabel] + visibleTemplates.map { $0.name }).max(by: { $0.count < $1.count }) ?? currentLabel

        return ZStack {
            // Invisible widest label to reserve width and prevent size jumps
            HStack(spacing: 6) {
                Text(keyPrefix + widestLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                if !currentTemplateVersionLabel.isEmpty {
                    Text(currentTemplateVersionLabel)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                }
            }
            .opacity(0)

            // Visible current label, or the flash when this game has no key
            TopBarKeyLabel(
                prefix: keyPrefix,
                name: currentLabel,
                versionLabel: currentTemplateVersionLabel,
                showVersion: currentTrackingMode != .scout,
                needsKey: needsKeyForThisGame
            )
        }
        .frame(maxWidth: 150, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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

    /// Flashes whenever the active game has no usable key - including the
    /// case where no key exists at all, which is the state that most needs
    /// explaining. Tapping it always leads somewhere now: the Menu offers
    /// "Create a Key" when there is nothing to pick from. A participant's
    /// key comes from the owner's live override, so they aren't asked.
    private var needsKeyForThisGame: Bool {
        isGame && isOwnerForActiveGame && !keyPickedForActiveGame
    }

    /// True while this game still needs a pitcher. An id that doesn't
    /// resolve against the loaded roster counts as unset - that's the same
    /// test the button's own label uses to decide what to draw, so the
    /// badge and the name underneath it can't disagree.
    ///
    /// Silent while the content section is inert: the pitcher button is
    /// behind the blur there, so a flash on it would be an instruction the
    /// coach cannot follow. `NoCodeGridKeyBlocker` is the live control in
    /// that state, and it should be the only thing asking for attention.
    private var needsPitcherForThisGame: Bool {
        guard isGame, !isLiveParticipantViewingGame, !isContentSectionInert else { return false }
        guard let pid = selectedPitcherId, !pid.isEmpty else { return true }
        return !pitchers.contains(where: { $0.id == pid })
    }

    /// True while this device is a live-session participant (not the owner)
    /// watching an active room — the owner's called pitches are arriving, so
    /// the pitcher shown must track the owner's selection, not this device's
    /// own roster.
    ///
    /// Deliberately does not require `isGame`. `isGame` is a local UI-mode
    /// toggle that can flip to false for reasons unrelated to live-session
    /// membership — e.g. `showGameSheet`'s onDismiss handler resets it
    /// whenever `selectedGameId` is nil, which it always is for a participant
    /// whose live session was never linked to a `gameId`. Once that happens
    /// this device is still very much a live participant (`activeLiveId` is
    /// still set, pitch events are still arriving), so gating on `isGame`
    /// permanently stranded the pitcher display on this device's own local
    /// `selectedPitcherId` instead of the owner's live selection.
    private var isLiveParticipantViewingGame: Bool {
        activeLiveId != nil && !isOwnerForActiveGame
    }

    /// The pitcher a participant sees is whatever the owner published to the
    /// live doc (`livePitcherId`/`livePitcherName`), not `selectedPitcherId` —
    /// that field only reflects this device's own roster, which usually
    /// doesn't even contain the owner's pitcher. When the id doesn't resolve
    /// against this device's local `pitchers` (participants can't read the
    /// owner's pitcher doc), a display-only stand-in is built from the name
    /// alone so the avatar falls back to initials instead of nothing.
    private var liveParticipantDisplayPitcher: Pitcher? {
        guard let pid = livePitcherId, !pid.isEmpty else { return nil }
        if let match = pitchers.first(where: { $0.id == pid }) {
            return match
        }
        return Pitcher(
            id: pid,
            name: livePitcherName ?? "Pitcher",
            templateId: nil,
            ownerUid: "",
            sharedWith: [],
            claimedByUid: nil,
            createdAt: nil
        )
    }

    // jerseyNumber(forPitcherId:) is gone with the one-line subtitle it fed:
    // the Players row carries the jersey in its own caption ("Hadley 33"),
    // sourced from the roster entry rather than from whichever side happens
    // to be active.

    /// Lets either roster be built from inside the picker itself, rather
    /// than only being addable by leaving the game - the actual fix for
    /// "no option to add from your team," and for the new player persisting
    /// as a real Team/TeamPlayer/Player record (not something scoped to
    /// just this session) the same way every other add-player path does.
    private var pitcherPickerTopActions: [SelectionSheetAction] {
        guard isGame else { return [] }
        if let teamId = currentPitchingTeamId {
            return [SelectionSheetAction(title: "New Pitcher on \(pitchingTeamDisplayName)", systemImage: "plus") {
                presentQuickAddPlayer(teamId: teamId) { newPlayer in
                    guard let pid = newPlayer.pitcherId,
                          let pitcher = self.pitchers.first(where: { $0.id == pid }) else { return }
                    self.applySelectedPitcher(pitcher)
                }
            }]
        } else if activeSide == .away {
            // No opponent roster yet - route to the same setup flow Tapping
            // Them uses, rather than the Home-side "Set My Team First"
            // fallback below (which opened the wrong sheet for this side).
            return [SelectionSheetAction(title: "Set Opponent Team First", systemImage: "plus") {
                handleSelectAwaySide()
            }]
        } else {
            return [SelectionSheetAction(title: "Set My Team First", systemImage: "plus") {
                teamSetupShouldFlipSide = false
                refreshMyTeamCandidates()
                showSetMyTeamSheet = true
            }]
        }
    }

    /// The selectable pitchers as Home's Players rows - avatar, name/jersey,
    /// team and designation - instead of a bare list of names. Rows come
    /// from the cross-team roster so two same-named kids are tellable apart;
    /// a standalone Pitcher with no roster entry still appears (no team).
    private func pitcherPickerRows(for pitchers: [Pitcher]) -> [PlayerDirectoryRow] {
        let allowedIds = Set(pitchers.compactMap { $0.id })
        return PlayerDirectory.rows(rosterEntries: rosterEntries, pitchers: pitchers)
            .filter { row in
                guard let pitcherId = row.pitcherId else { return false }
                return allowedIds.contains(pitcherId)
            }
    }

    private var pitcherPickerButton: some View {
        let pitchersForMenu = isGame
            ? sideFilteredPitchers.filter { $0.isActiveOwner(currentUid: authManager.user?.uid) }
            : sideFilteredPitchers
        let isParticipantViewing = isLiveParticipantViewingGame
        return PlayerPickerButton(
            title: "Select Pitcher",
            rows: pitcherPickerRows(for: pitchersForMenu),
            teams: directoryTeams,
            topActions: pitcherPickerTopActions,
            emptyMessage: "No pitchers for this side yet.",
            isSelected: { $0.pitcherId == selectedPitcherId },
            onSelect: { row in
                guard let pitcherId = row.pitcherId,
                      let pitcher = pitchers.first(where: { $0.id == pitcherId }) else { return }
                applySelectedPitcher(pitcher)
            },
            // The roster this list is built from is a cached snapshot, and a
            // player added from Home while this view stayed mounted (it is
            // the permanent root, never torn down) wouldn't be in it.
            onOpen: { refreshPlayerDirectory() }
        ) {
            let currentPitcher = isParticipantViewing
                ? liveParticipantDisplayPitcher
                : pitchers.first(where: { $0.id == selectedPitcherId })

            VStack(alignment: .center, spacing: 4) {
                ZStack(alignment: .bottomTrailing) {
                    PitcherAvatarOrMissingBadge(
                        pitcher: currentPitcher,
                        needsSelection: needsPitcherForThisGame,
                        size: 44
                    )

                    if !isParticipantViewing {
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.primary)
                            .padding(3)
                            .background(Color.white.opacity(0.78))
                            .clipShape(Circle())
                            .offset(x: 2, y: 2)
                    }
                }

                Text(currentPitcher?.name ?? "Select a pitcher")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                    .frame(width: 66)
            }
            .opacity((isParticipantViewing ? currentPitcher == nil : (noPitcherOptionsAvailable || !canSelectPitcherInGame)) ? 0.6 : 1.0)
            .contentShape(Rectangle())
            .transaction { transaction in
                transaction.animation = nil
            }
            .animation(nil, value: atBatPulse)
        }
        .disabled(isParticipantViewing || noPitcherOptionsAvailable || !canSelectPitcherInGame)
    }

    /// `sideFilteredPitchers` is empty for a fresh opponent (Them) roster
    /// until a pitcher is linked to it - that used to disable the whole
    /// button, which meant there was no way to tap it and reach the "Add
    /// New Pitcher"/"Set Opponent Team First" top action that fixes exactly
    /// that case. Only treat the button as truly option-less when there's
    /// also no top action to fall back on (i.e. outside a game).
    private var noPitcherOptionsAvailable: Bool {
        sideFilteredPitchers.isEmpty && pitcherPickerTopActions.isEmpty
    }

    private var mainStrikeZoneSection: some View {
        let deviceWidth = effectiveScreenSize.width
        let SZwidth: CGFloat = isGame ? (deviceWidth * 0.78) : (deviceWidth * 0.85)
        let chipStripWidth: CGFloat = SZwidth

        return VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                sidebarControlPanel

                if !activePitchChipOptions.isEmpty {
                    pitchSelectionStrip(width: chipStripWidth)
                } else {
                    Color.clear
                        .frame(width: chipStripWidth, height: topControlRowHeight)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                atBatSidebar

                if currentTrackingMode == .scout {
                    scoutTrackingArea(width: SZwidth)
                } else {
                    strikeZoneArea(width: SZwidth)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private var activeGameForBatterSetup: Game? {
        selectedGameId.flatMap { gid in games.first(where: { $0.id == gid }) }
    }

    /// Whichever team's roster the active PITCHER is drawn from right now.
    private var currentPitchingTeamId: String? {
        switch activeSide {
        case .home: return activeGameForBatterSetup?.teamId
        case .away: return activeGameForBatterSetup?.awayTeamId
        }
    }

    /// Whichever team's roster the active BATTER is drawn from right now -
    /// always the opposite team from currentPitchingTeamId for a given side.
    private var currentBattingTeamId: String? {
        switch activeSide {
        case .home: return activeGameForBatterSetup?.awayTeamId
        case .away: return activeGameForBatterSetup?.teamId
        }
    }

    /// A quick-added away-roster batter needs to join the curated list too
    /// (Game.activeAwayBatterIds, see "Choose Batters to Track") when one
    /// is active - otherwise they'd be created but invisible in the picker
    /// that just created them, since the curated subset would still exclude
    /// them. No-ops when the list is unset/empty (no restriction active).
    private func addToActiveAwayBatterIdsIfCurated(_ teamPlayerId: String?) {
        guard let teamPlayerId,
              let gid = selectedGameId,
              let index = games.firstIndex(where: { $0.id == gid }),
              let activeIds = games[index].activeAwayBatterIds, !activeIds.isEmpty,
              !activeIds.contains(teamPlayerId)
        else { return }
        games[index].activeAwayBatterIds = activeIds + [teamPlayerId]
        if !isDemoMode {
            authManager.saveGame(games[index])
        }
    }

    private func presentQuickAddPlayer(teamId: String, onCreate: @escaping (TeamPlayer) -> Void) {
        quickAddPlayerName = ""
        quickAddPlayerJersey = ""
        quickAddPlayerPositions = []
        quickAddPlayerBattingSide = nil
        quickAddTeamId = teamId
        quickAddOnCreate = onCreate
        showQuickAddPlayerSheet = true
    }

    private func confirmQuickAddPlayer() {
        guard let teamId = quickAddTeamId else { return }
        let name = quickAddPlayerName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let jersey = quickAddPlayerJersey.trimmingCharacters(in: .whitespaces)
        authManager.addTeamPlayerCreatingNewPlayer(
            teamId: teamId,
            name: name,
            jerseyNumber: jersey.isEmpty ? nil : jersey,
            positions: quickAddPlayerPositions.isEmpty ? nil : Array(quickAddPlayerPositions),
            battingSide: quickAddPlayerBattingSide
        ) { result in
            guard case .success(let teamPlayer) = result else { return }
            self.showQuickAddPlayerSheet = false
            // Refresh whichever side(s) this team feeds, and reload the
            // owner's full pitcher list too - applySelectedPitcher (used by
            // the pitcher picker's own onCreate) needs the new Pitcher to
            // actually be present in `pitchers`, not just referenced by id.
            //
            // The onCreate callback has to run AFTER the roster it belongs
            // to has actually reloaded: for a batter it builds a jersey
            // cell, and the At Bat scroll only shows cells whose hitter is
            // in that side's roster (currentBattingHitterIds). Firing it
            // first - as this did - created the cell during the window
            // where the roster didn't know the player yet, so a
            // just-added batter was hidden from the lineup that just
            // added them.
            let runOnCreate = {
                self.quickAddOnCreate?(teamPlayer)
                self.quickAddOnCreate = nil
            }
            self.authManager.loadPitchers { self.pitchers = $0 }

            if teamId == self.activeGameForBatterSetup?.awayTeamId {
                self.loadAwayPitcherIds(awayTeamId: teamId)
                self.refreshAwayRoster(awayTeamId: teamId) {
                    if teamId == self.activeGameForBatterSetup?.teamId {
                        self.refreshHomeRoster(teamId: teamId, completion: runOnCreate)
                    } else {
                        runOnCreate()
                    }
                }
            } else if teamId == self.activeGameForBatterSetup?.teamId {
                self.refreshHomeRoster(teamId: teamId, completion: runOnCreate)
            } else {
                runOnCreate()
            }
        }
    }

    /// Matches TeamRosterView's own position-toggle row (capsules, same
    /// styling) - that one is private to TeamRosterView, so this is a
    /// second small copy rather than a cross-file reuse, to keep this quick
    /// sheet's own state self-contained.
    private func quickAddPositionToggleRow(selected: Binding<Set<FieldPosition>>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(FieldPosition.allCases, id: \.self) { position in
                    let isSelected = selected.wrappedValue.contains(position)
                    Button(position.rawValue) {
                        if isSelected {
                            selected.wrappedValue.remove(position)
                        } else {
                            selected.wrappedValue.insert(position)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(Capsule().fill(isSelected ? Color.pitchMarkActiveGray : Color(.systemGray6)))
                }
            }
        }
    }

    private var quickAddPlayerSheetView: some View {
        NavigationView {
            Form {
                TextField("Name", text: $ui.quickAddPlayerName)
                TextField("Jersey #", text: $ui.quickAddPlayerJersey)

                Section("Position") {
                    quickAddPositionToggleRow(selected: $quickAddPlayerPositions)
                }

                Section("Batting Side") {
                    Picker("Batting Side", selection: $quickAddPlayerBattingSide) {
                        Text("Not Set").tag(BattingSide?.none)
                        ForEach(BattingSide.allCases, id: \.self) { side in
                            Text(side.displayName).tag(BattingSide?.some(side))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .navigationTitle("Add Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showQuickAddPlayerSheet = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        confirmQuickAddPlayer()
                    }
                    .disabled(quickAddPlayerName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    /// The At Bat "+" is the single source for adding a batter, in any of
    /// four ways: an ephemeral this-game-only jersey number (today's
    /// original flow, untouched), picking an existing roster player,
    /// creating a brand new roster player, or setting up/switching which
    /// team that roster even is. All four end up as a real jersey cell in
    /// the same list - a roster pick isn't a separate side-channel control,
    /// it's just another way to populate the one list that was always
    /// there.
    private func promptTeamSetupForBatting() {
        teamSetupShouldFlipSide = false
        switch activeSide {
        case .home:
            // Same pre-fill handleSelectAwaySide already does when Them
            // itself is tapped with no opponent set - this is the other
            // path to the identical "New Opponent Roster" field, from the
            // Add a Batter menu instead.
            if let opponent = activeGameForBatterSetup?.opponent {
                newOpponentTeamName = opponent
            }
            refreshOpponentTeamCandidates()
            showSetOpponentSheet = true
        case .away:
            refreshMyTeamCandidates()
            showSetMyTeamSheet = true
        }
    }

    /// Whose roster the At Bat "+" menu acts on. The batting team is always
    /// the OPPOSITE side from `activeSide` (which names who is pitching),
    /// and that inversion is exactly what made this menu ambiguous - every
    /// item silently targeted the other team from the Select Pitcher menu
    /// sitting right beside it, with nothing on screen saying so.
    private var battingTeamDisplayName: String {
        switch activeSide {
        case .home: return activeAwayTeamName.isEmpty ? "Opponent" : activeAwayTeamName
        case .away: return activeHomeTeamName.isEmpty ? "My Team" : activeHomeTeamName
        }
    }

    /// The other half of the pair - whoever is pitching, i.e. `activeSide`
    /// itself. Named so the Select Pitcher menu can say whose roster it
    /// adds to, the same way the At Bat menu now does.
    private var pitchingTeamDisplayName: String {
        switch activeSide {
        case .home: return activeHomeTeamName.isEmpty ? "My Team" : activeHomeTeamName
        case .away: return activeAwayTeamName.isEmpty ? "Opponent" : activeAwayTeamName
        }
    }

    /// The whole lineup split by the team each cell belongs to, for the pin
    /// sheet's batter strip. Nothing is dropped - the strip there is not
    /// side-scoped the way the At Bat scroll is, so both teams' batters stay
    /// selectable and editable; they're just separated and labelled instead
    /// of running together as one row of numbers.
    ///
    /// A cell with no roster link (a bare jersey number typed in, or one
    /// added before the link was recorded) rides along in the batting team's
    /// row - a section of its own for one or two stray numbers cost more
    /// vertical space than it was worth. `unlinkedBatterIdsForDetail` is
    /// what tells them apart there, by fill colour.
    private var lineupGroupsForDetail: [LineupBatterGroup] {
        let battingRoster = activeSide == .home ? awayRoster : homeRoster
        let pitchingRoster = activeSide == .home ? homeRoster : awayRoster
        let battingHitterIds = Set(battingRoster.compactMap { $0.hitterId })
        let pitchingHitterIds = Set(pitchingRoster.compactMap { $0.hitterId })

        var batting: [JerseyCell] = []
        var fielding: [JerseyCell] = []
        var unlinked: [JerseyCell] = []
        for cell in jerseyCells {
            guard let hitterId = hitterIdByJerseyCellId[cell.id] else {
                unlinked.append(cell)
                continue
            }
            if battingHitterIds.contains(hitterId) {
                batting.append(cell)
            } else if pitchingHitterIds.contains(hitterId) {
                fielding.append(cell)
            } else {
                unlinked.append(cell)
            }
        }

        // Unassigned numbers join the batting side's row, after its own
        // players, keeping the lineup's order within each part.
        let battingRow = batting + unlinked

        var groups: [LineupBatterGroup] = []
        if !battingRow.isEmpty {
            groups.append(
                LineupBatterGroup(
                    id: "batting",
                    title: battingTeamDisplayName,
                    isBatting: true,
                    cells: battingRow
                )
            )
        }
        if !fielding.isEmpty {
            groups.append(
                LineupBatterGroup(
                    id: "fielding",
                    title: pitchingTeamDisplayName,
                    isBatting: false,
                    cells: fielding
                )
            )
        }
        return groups
    }

    /// Lineup cells with no roster link behind them. Same classification as
    /// `lineupGroupsForDetail` above - the pin sheet tints these rather than
    /// separating them out.
    private var unlinkedBatterIdsForDetail: Set<UUID> {
        let linkedHitterIds = Set(
            (homeRoster + awayRoster).compactMap { $0.hitterId }
        )
        var ids: Set<UUID> = []
        for cell in jerseyCells {
            guard let hitterId = hitterIdByJerseyCellId[cell.id],
                  linkedHitterIds.contains(hitterId) else {
                ids.insert(cell.id)
                continue
            }
        }
        return ids
    }

    /// Writes the current cell -> hitter map onto the selected game.
    ///
    /// Owner-only: a participant has no write access to the owner's game
    /// doc, and its own copy of the lineup comes from the live room anyway.
    /// Demo mode never persists. Called from the two places the map
    /// changes - adding a roster-linked cell, and the prune that follows a
    /// cell deletion - so no other lineup path needs to know about it.
    ///
    /// Goes through `updateGameHitterLinks` (one field) rather than
    /// `saveGame` (the whole encoded Game). Using the latter here
    /// resurrected deleted batters: the delete paths write
    /// jerseyNumbers/batterIds straight to the doc via `updateGameLineup`
    /// and leave `games[index]`'s copies stale, and this runs from the
    /// prune a delete triggers - so the whole-doc write landed a stale
    /// lineup on top of the delete that had just happened.
    private func persistHitterLinks() {
        guard !isDemoMode,
              isOwnerForActiveGame,
              let gid = selectedGameId else { return }
        let links = Dictionary(
            uniqueKeysWithValues: hitterIdByJerseyCellId.map { ($0.key.uuidString, $0.value) }
        )
        if let index = games.firstIndex(where: { $0.id == gid }) {
            guard games[index].hitterIdByBatterId != links else { return }
            // Local struct only - the write below is the one that persists.
            games[index].hitterIdByBatterId = links
        }
        authManager.updateGameHitterLinks(
            ownerUserId: effectiveGameOwnerUserId,
            gameId: gid,
            links: links
        )
    }

    /// Adds whatever the game has stored without discarding anything held
    /// in memory, for the paths that rebuild `jerseyCells` *without* being
    /// a deliberate game switch - `hydrateChosenGameUI` (both its fast
    /// local path and its slow fetch) and the deferred boot restore.
    ///
    /// This is the cold-launch case: those paths never call `chooseGame`,
    /// so before this the restored lineup came back with an empty link map,
    /// every cell read as unlinked, and the At Bat scroll failed open -
    /// showing a stale-looking list that didn't change when the Us/Them
    /// toggle moved, until a trip back to Home re-entered through
    /// `chooseGame`.
    ///
    /// In-memory entries win on a key collision (they're the fresher of the
    /// two), and keys for cells that no longer exist are dropped by the
    /// prune on the next `jerseyCells` change.
    private func mergeHitterLinks(from game: Game?) {
        guard let stored = game?.hitterIdByBatterId, !stored.isEmpty else { return }
        for (batterId, hitterId) in stored {
            guard let cellId = UUID(uuidString: batterId),
                  hitterIdByJerseyCellId[cellId] == nil else { continue }
            hitterIdByJerseyCellId[cellId] = hitterId
        }
    }

    /// Replaces the map with the game's stored one. Only for `chooseGame`,
    /// where the coach deliberately switched games and another game's
    /// annotations must not carry over.
    private func seedHitterLinks(from game: Game?) {
        guard let stored = game?.hitterIdByBatterId, !stored.isEmpty else {
            hitterIdByJerseyCellId = [:]
            return
        }
        var seeded: [UUID: String] = [:]
        for (batterId, hitterId) in stored {
            guard let cellId = UUID(uuidString: batterId) else { continue }
            seeded[cellId] = hitterId
        }
        hitterIdByJerseyCellId = seeded
    }

    private var battingTeamSetupMenuLabel: String {
        if currentBattingTeamId != nil {
            return "Change \(battingTeamDisplayName)…"
        }
        return activeSide == .home ? "Set Opponent Team…" : "Set My Team…"
    }

    /// Creates the jersey cell exactly the way the existing Save button
    /// already does (same append + live-transactional-or-direct persist),
    /// then additionally remembers the roster link for this session so
    /// PitchEvent.hitterId gets stamped correctly - including on every
    /// future re-tap of this same cell, via the selectedBatterId onChange
    /// below. Deliberately a separate function from the Save button's
    /// inline logic rather than a refactor of it - this is the single most
    /// fragile, most load-bearing state in the file (CLAUDE.md), so
    /// duplicating the well-understood persistence shape is lower risk
    /// than restructuring the working path underneath it.
    ///
    /// The roster-link annotation is persisted too, as
    /// `Game.hitterIdByBatterId` (see `persistHitterLinks`). It used to be
    /// session-local, which meant reopening a game left every restored cell
    /// looking unlinked - and because `visibleJerseyCells` fails open on an
    /// unlinked cell, the At Bat scroll then showed both teams' cells on
    /// both sides of the Us/Them toggle instead of scoping to whoever was
    /// batting. Keyed by cell id rather than threaded through jerseyCells'
    /// seven rehydration sites, so none of that fragile ordering moves.
    private func addJerseyCellForRosterPlayer(displayNumber: String, hitterId: String?) {
        let newCell = JerseyCell(jerseyNumber: displayNumber)
        jerseyCells.append(newCell)
        if let hitterId {
            hitterIdByJerseyCellId[newCell.id] = hitterId
            persistHitterLinks()
        }

        if let liveId = activeLiveId, !liveId.isEmpty {
            LiveGameService.shared.mutateLiveLineup(liveId: liveId) { jerseys, batterIds in
                jerseys.append(displayNumber)
                batterIds.append(newCell.id.uuidString)
            } completion: { result in
                guard case .success(let merged) = result,
                      let gameId = selectedGameId,
                      let owner = effectiveGameOwnerUserId,
                      !owner.isEmpty,
                      isOwnerForActiveGame else { return }
                authManager.updateGameLineup(
                    ownerUserId: owner,
                    gameId: gameId,
                    jerseyNumbers: merged.jerseys,
                    batterIds: merged.batterIds
                )
            }
        } else if let gameId = selectedGameId,
                  let owner = effectiveGameOwnerUserId,
                  !owner.isEmpty {
            authManager.updateGameLineup(
                ownerUserId: owner,
                gameId: gameId,
                jerseyNumbers: jerseyCells.map { $0.jerseyNumber },
                batterIds: jerseyCells.map { $0.id.uuidString }
            )
        }

        selectedBatterId = newCell.id
    }

    /// Shared completion for both "Add From Team" and "New Player" - a
    /// roster player with no jersey number set yet falls back to their
    /// initials so the fixed-size jersey cell still has something short to
    /// show (JerseyCellView is a rigid 40x40 square, not built for a name).
    private func addBatterFromRoster(_ player: TeamPlayer) {
        if activeSide == .home {
            addToActiveAwayBatterIdsIfCurated(player.id)
        }
        addJerseyCellForRosterPlayer(
            displayNumber: lineupDisplayNumber(for: player),
            hitterId: player.hitterId
        )
    }

    /// What a roster player's jersey cell shows. Shared so the de-dupe in
    /// `addChosenBattersToLineup` compares against the same string this
    /// would actually create.
    private func lineupDisplayNumber(for player: TeamPlayer) -> String {
        if let jersey = player.jerseyNumber, !jersey.isEmpty {
            return jersey
        }
        return String(player.name.prefix(2)).uppercased()
    }

    /// Already-in-the-lineup roster players are excluded so the picker
    /// doesn't offer someone twice.
    private var atBatRosterPickerCandidates: [TeamPlayer] {
        let alreadyAdded = Set(hitterIdByJerseyCellId.values)
        return activeBatterRosterCandidates.filter { !alreadyAdded.contains($0.hitterId ?? "") }
    }

    // Reuses the existing generic ScrollableSelectionSheet (already compiled
    // and in use elsewhere, e.g. the Key picker) rather than a bespoke
    // NavigationView/List/ForEach tree - a second crash after this feature
    // shipped traced back to this exact render path (confirmationDialog
    // deep inside PitchTrackerView's already enormous view graph hitting a
    // Swift runtime metadata-resolution limit, not a logic bug); reusing an
    // existing generic specialization instead of introducing a brand new
    // composite View type is a direct, concrete way to reduce how much NEW
    // type complexity this feature adds to that graph.
    private var atBatRosterPickerSheetView: some View {
        ScrollableSelectionSheet(
            title: "Add From Team",
            items: atBatRosterPickerCandidates,
            topActions: [],
            itemTitle: { $0.name },
            itemSubtitle: { $0.jerseyNumber.flatMap { j in j.isEmpty ? nil : "#\(j)" } },
            isSelected: { _ in false },
            onSelect: { player in
                addBatterFromRoster(player)
            }
        )
    }

    private var scoutInPlayOptions: [String] { ["Out", "1B", "2B", "3B", "HR"] }
    private var scoutDescriptorOptions: [String] { ["Grounder", "Line", "Pop", "Fly", "Bunt"] }
    private var isParticipantCallInProgress: Bool {
        isGame && !isOwnerForActiveGame && (calledPitch != nil || isRecordingResult || activeCalledPitchId != nil)
    }

    /// Same shape as `isParticipantCallInProgress` but for the owner - guards
    /// the Us/Them switch the same way Scout already guards against a
    /// participant switching mid-call, so flipping which roster the pitcher
    /// picker draws from can't happen out from under an in-flight call.
    private var isOwnerCallInProgress: Bool {
        isGame && isOwnerForActiveGame && (calledPitch != nil || isRecordingResult || activeCalledPitchId != nil)
    }

    private var scoutCanSave: Bool {
        guard scoutObservedResult != nil else { return false }
        if scoutObservedResult == .inPlay {
            return scoutInPlayOutcome != nil || scoutHitOnPlay || scoutDescriptor != nil || scoutErrorOnPlay
        }
        return true
    }

    private var scoutBottomBarHeight: CGFloat { 62 }

    @ViewBuilder
    private func scoutTrackingArea(width: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack{
                        Text("Pitch Result")
                            .font(.caption)
                            .foregroundStyle(.gray)
                        Spacer()
                        Text("Count \(balls)-\(strikes)")
                            .font(.subheadline.weight(.semibold))
                            //.padding(.top, 16)
                            .padding(.trailing, 16)
                    }
                    HStack(spacing: 8) {
                        scoutResultButton(.swingingStrike, title: "Swinging")
                        scoutResultButton(.calledStrike, title: "Looking")
                        scoutResultButton(.foul, title: "Foul")
                    }
                }

                HStack(spacing: 8) {
                    scoutResultButton(.ball, title: "Ball")
                    scoutResultButton(.inPlay, title: "In Play")
                    scoutMiscTagButton("HBP")
                    scoutMiscTagButton("WP")
                    scoutMiscTagButton("PB")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Location")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }

                    scoutZoneSelector
                }

                if scoutObservedResult == .inPlay || scoutObservedResult == .foul {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(scoutObservedResult == .foul ? "Foul Outcome" : "In-Play Outcome")
                            .font(.caption)
                            .foregroundStyle(.gray)
                        scoutOptionWrap(options: scoutInPlayOptions, selection: $ui.scoutInPlayOutcome)

                        HStack {
                            scoutBooleanTagButton("Hit", isOn: $ui.scoutHitOnPlay)
                            Spacer()
                        }

                        Text("Contact Type")
                            .font(.caption)
                            .foregroundStyle(.gray)
                        scoutOptionWrap(options: scoutDescriptorOptions, selection: $ui.scoutDescriptor)

                        HStack {
                            scoutBooleanTagButton("E", isOn: $ui.scoutErrorOnPlay)
                            Spacer()
                        }

                        HStack(spacing: 10) {
                            Button {
                                showScoutFieldMap = true
                            } label: {
                                HStack(spacing: 8) {
                                    Label(
                                        scoutBattedBallRegionName == nil ? "Field Map" : "Edit Field Map",
                                        systemImage: "map"
                                    )

                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.semibold))
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)

                            if let scoutBattedBallRegionName, !scoutBattedBallRegionName.isEmpty {
                                Text(scoutBattedBallRegionName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, scoutBottomBarHeight + 10)
        }
        .frame(width: width, height: strikeZoneHeight, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thickMaterial)
                .shadow(color: .black.opacity(0.7), radius: 6, x: 0, y: 6)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
//        .overlay(alignment: .topTrailing) {
//            Text("Count \(balls)-\(strikes)")
//                .font(.subheadline.weight(.semibold))
//                .foregroundStyle(.secondary)
//                .padding(.top, 16)
//                .padding(.trailing, 16)
//        }
        .overlay(alignment: .bottom) {
            scoutBottomActionBar(width: width)
        }
        .overlay(alignment: .center) {
            makeBatterSideOverlay(SZwidth: width, verticalOffset: 0)
        }
        .clipped()
        .sheet(isPresented: $ui.showScoutFieldMap) {
            ScoutFieldMapSheet(
                selectedOutcome: $ui.scoutInPlayOutcome,
                battedBallRegionName: $ui.scoutBattedBallRegionName,
                battedBallTapNormalized: $scoutBattedBallTapNormalized,
                isDemoMode: isDemoMode
            )
            .fixedAppDynamicType()
        }
    }

    @ViewBuilder
    private func scoutBottomActionBar(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)

                HStack(spacing: 10) {
                    ResetPitchButton {
                        resetScoutComposer()
                    }

                    if isGame {
                        scoutBottomBarButton(systemImage: "chart.bar") {
                            showGameStatsSheet = true
                        }

                        scoutBottomBarButton(systemImage: "doc.text") {
                            showGameSummarySheet = true
                        }
                    }

                    Spacer(minLength: 0)

                    Button("Save Event") {
                        saveScoutEvent()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!scoutCanSave)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .frame(width: width)
            .frame(height: scoutBottomBarHeight, alignment: .bottom)
            .background(.ultraThinMaterial)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 12,
                    bottomTrailingRadius: 12,
                    topTrailingRadius: 0
                )
            )
        }
        .frame(width: width, height: strikeZoneHeight, alignment: .bottom)
    }

    private func scoutBottomBarButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .background(.regularMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var sidebarControlPanel: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            sidebarControlButton(title: "Coach", isSelected: currentTrackingMode == .coach) {
                currentTrackingMode = .coach
            }
            Spacer(minLength: 0)
            sidebarControlButton(title: "Scout", isSelected: currentTrackingMode == .scout) {
                guard !isParticipantCallInProgress else { return }
                currentTrackingMode = .scout
            }
            .opacity(isParticipantCallInProgress ? 0.45 : 1.0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(width: sidebarColumnWidth, height: topControlRowHeight, alignment: .center)
        .background(alignment: .top) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(height: topControlRowHeight)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
        }
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                .frame(height: topControlRowHeight)
        }
        .zIndex(10)
    }

    /// Owner-only switch for which side's pitcher is active - a parallel,
    /// independent axis from Coach/Scout (tracking rigor). A participant
    /// always mirrors whatever side the owner is on, same as they already
    /// mirror the owner's selected pitcher, so this never shows for them.
    /// Labeled Us/Them (matching the existing scoreboard vocabulary) - the
    /// underlying GameSide cases stay .home/.away internally.
    private var usThemControl: some View {
        HStack(spacing: 8) {
            usThemButton(side: .away) {
                guard !isOwnerCallInProgress else { return }
                handleSelectAwaySide()
            }
            usThemButton(side: .home) {
                guard !isOwnerCallInProgress else { return }
                handleSelectHomeSide()
            }
        }
        .opacity(isOwnerCallInProgress ? 0.45 : 1.0)
    }

    /// The two sides are labelled with the actual team names now, falling
    /// back to "Us"/"Them" only when a side has no team linked yet (a game
    /// created before the new-game card asked for both sides, or one the
    /// coach skipped). Long names are abbreviated rather than truncated, so
    /// the two capsules stay the same size as before.
    /// `maxLength` is per-call because the places these labels appear have
    /// very different budgets: the pitching toggle is a capsule of its own,
    /// while the Score row squeezes two of them either side of "Score".
    private func sideLabel(for side: GameSide, maxLength: Int = 10) -> String {
        let linked: String
        switch side {
        case .home:
            linked = activeHomeTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
        case .away:
            let name = activeAwayTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
            // The game's own opponent string is the next best thing: it is
            // the opponent team's name for any game made by the new card.
            linked = name.isEmpty
                ? (opponentName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                : name
        }
        guard !linked.isEmpty else { return side.displayName }
        return Self.abbreviatedTeamName(linked, maxLength: maxLength)
    }

    /// Keeps short names intact ("Reds"); turns a long multi-word name into
    /// its initials ("Lady Thunder Gold" -> "LTG") and a long single word
    /// into its first few letters, so neither blows out the capsule.
    static func abbreviatedTeamName(_ name: String, maxLength: Int = 10) -> String {
        if name.count <= maxLength { return name }
        let words = name.split(whereSeparator: { $0.isWhitespace })
        if words.count > 1 {
            let initials = words.compactMap { $0.first }.map(String.init).joined().uppercased()
            if initials.count <= maxLength, !initials.isEmpty { return initials }
            return String(initials.prefix(maxLength))
        }
        return String(name.prefix(maxLength))
    }

    private func usThemButton(side: GameSide, action: @escaping () -> Void) -> some View {
        let isSelected = activeSide == side
        return Button(action: action) {
            Text(sideLabel(for: side))
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(isSelected ? Color.pitchMarkActiveGray : Color(.systemGray6)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(side == .home ? "Our team pitching" : "Opponent pitching")
    }

    private func sidebarControlButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.black : Color(.systemGray6))
                )
        }
        .buttonStyle(.plain)
    }

    private func sidebarInviteButton(isConnected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isConnected {
                    Image(systemName: "link.icloud.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                } else {
                    Text("Invite")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
            }
            .background(
                Capsule()
                    .fill(Color(.systemGray6))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func triggerAssistantCodeLink() {
        if isDemoMode {
            requireSignInForDemo("Sign in to invite another device or use live sharing.")
            return
        }
        if !subscriptionManager.isPro {
            proGateMessage = "Coach + Assistant mode is available in PitchMark Pro."
            showProGateAlert = true
            return
        }
        showCodeShareModePicker = true
    }

    private var scoutZoneSelector: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let zoneWidth = size * 0.48
            let zoneHeight = size * 0.58
            let cellWidth = zoneWidth / 3
            let cellHeight = zoneHeight / 3
            let buttonSize = min(cellWidth, cellHeight) * 0.62
            let originX = (geo.size.width - zoneWidth) / 2
            let originY = (geo.size.height - zoneHeight) / 2

            let strikeLocations: [(String, Int, Int)] = [
                ("Up & Out", 0, 0), ("Up", 0, 1), ("Up & In", 0, 2),
                ("Out", 1, 0), ("Middle", 1, 1), ("In", 1, 2),
                ("↓ & Out", 2, 0), ("↓", 2, 1), ("↓ & In", 2, 2)
            ]

            let ballLocations: [(String, CGFloat, CGFloat)] = [
                ("Up & Out", originX - buttonSize * 0.8, originY - buttonSize * 0.75),
                ("Up", originX + zoneWidth / 2, originY - buttonSize * 0.9),
                ("Up & In", originX + zoneWidth + buttonSize * 0.8, originY - buttonSize * 0.75),
                ("Out", originX - buttonSize, originY + zoneHeight / 2),
                ("In", originX + zoneWidth + buttonSize, originY + zoneHeight / 2),
                ("↓ & Out", originX - buttonSize * 0.8, originY + zoneHeight + buttonSize * 0.75),
                ("↓", originX + zoneWidth / 2, originY + zoneHeight + buttonSize * 0.9),
                ("↓ & In", originX + zoneWidth + buttonSize * 0.8, originY + zoneHeight + buttonSize * 0.75)
            ]

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.7), lineWidth: 1.5)
                    .frame(width: zoneWidth, height: zoneHeight)
                    .position(x: originX + zoneWidth / 2, y: originY + zoneHeight / 2)

                ForEach(strikeLocations, id: \.0) { label, row, col in
                    let x = originX + CGFloat(col) * cellWidth + cellWidth / 2
                    let y = originY + CGFloat(row) * cellHeight + cellHeight / 2
                    scoutZoneDot(
                        selection: .init(label: label, isStrikeZone: true),
                        x: x,
                        y: y,
                        size: buttonSize
                    )
                }

                ForEach(ballLocations, id: \.0) { label, x, y in
                    scoutZoneDot(
                        selection: .init(label: label, isStrikeZone: false),
                        x: x,
                        y: y,
                        size: buttonSize * 0.92
                    )
                }
            }
        }
        .frame(height: 150)
    }

    @ViewBuilder
    private func scoutZoneDot(selection: ScoutZoneSelection, x: CGFloat, y: CGFloat, size: CGFloat) -> some View {
        let isSelected = scoutZoneSelection == selection
        Button {
            scoutZoneSelection = isSelected ? nil : selection
        } label: {
            Circle()
                .fill(selection.isStrikeZone ? Color.green : Color.red)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.black : Color.clear, lineWidth: 2)
                )
                .shadow(color: .black.opacity(isSelected ? 0.22 : 0.1), radius: isSelected ? 2 : 1, x: 0, y: 1)
                .frame(width: size, height: size)
                .scaleEffect(isSelected ? 1.15 : 1.0)
        }
        .buttonStyle(.plain)
        .position(x: x, y: y)
        .accessibilityLabel(selection.isStrikeZone ? "Strike \(selection.label)" : "Ball \(selection.label)")
    }

    private func scoutSelectObservedResult(_ result: ScoutObservedResult) {
        scoutObservedResult = result
        if result != .inPlay && result != .foul {
            scoutInPlayOutcome = nil
            scoutHitOnPlay = false
            scoutBattedBallRegionName = nil
            scoutBattedBallTapNormalized = nil
        }
        if result != .ball {
            scoutMiscOutcome = nil
        }
    }

    @ViewBuilder
    private func scoutResultButton(_ result: ScoutObservedResult, title: String? = nil) -> some View {
        Button {
            scoutSelectObservedResult(result)
        } label: {
            Text(title ?? result.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(scoutObservedResult == result ? Color.white : Color.primary)
                .shadow(color: .clear, radius: 0)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(scoutObservedResult == result ? Color.black : Color(.systemGray6))
                        .shadow(color: .black.opacity(0.12), radius: 1.5, x: 0, y: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func scoutMiscTagButton(_ option: String) -> some View {
        let isSelected = scoutObservedResult == .ball && scoutMiscOutcome == option
        Button {
            if isSelected {
                scoutMiscOutcome = nil
            } else {
                scoutSelectObservedResult(.ball)
                scoutMiscOutcome = option
            }
        } label: {
            Text(option)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .shadow(color: .clear, radius: 0)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.black : Color(.systemGray6))
                        .shadow(color: .black.opacity(0.12), radius: 1.5, x: 0, y: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func scoutBooleanTagButton(_ option: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(option)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isOn.wrappedValue ? Color.white : Color.primary)
                .shadow(color: .clear, radius: 0)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(isOn.wrappedValue ? Color.black : Color(.systemGray6))
                        .shadow(color: .black.opacity(0.12), radius: 1.5, x: 0, y: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func scoutOptionWrap(options: [String], selection: Binding<String?>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection.wrappedValue == option
                Button {
                    selection.wrappedValue = isSelected ? nil : option
                } label: {
                    Text(option)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .shadow(color: .clear, radius: 0)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.black : Color(.systemGray6))
                                .shadow(color: .black.opacity(0.12), radius: 1.5, x: 0, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var activePitchChipOptions: [String] {
        let ordered = orderedPitchesForTemplate
        guard !ordered.isEmpty else { return [] }
        if isGame && !isOwnerForActiveGame {
            return ordered
        }

        let active = effectivePitchesForStrikeZone
        let filtered = ordered.filter { active.contains($0) }
        return filtered.isEmpty ? ordered : filtered
    }

    private var displayedPitchChipOptions: [String] {
        if isGame && !isOwnerForActiveGame && uiConnected {
            return []
        }
        return [""] + activePitchChipOptions
    }

    @ViewBuilder
    private func pitchSelectionStrip(width: CGFloat) -> some View {
        let chipOptions = displayedPitchChipOptions
        let rows = [
            GridItem(.flexible(minimum: 20), spacing: 6),
            GridItem(.flexible(minimum: 20), spacing: 6)
        ]
        let pitcherColumnWidth: CGFloat = 74
        let chipsMinWidth = max(0, width - 16 - pitcherColumnWidth - 8)

        return HStack(spacing: 8) {
            pitcherPickerButton
                .frame(width: pitcherColumnWidth)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: 8) {
                    ForEach(chipOptions, id: \.self) { pitch in
                        pitchChip(pitch)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .frame(minWidth: chipsMinWidth, alignment: .center)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: width, height: topControlRowHeight, alignment: .center)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
    }

    @ViewBuilder
    private func pitchChip(_ pitch: String) -> some View {
        let isNoneChip = pitch.isEmpty
        let isSelectedChip = isNoneChip ? selectedPitch.isEmpty : selectedPitch == pitch
        let chipColor = isNoneChip ? Color.black : colorForPitch(pitch)

        Button {
            if isNoneChip {
                if currentTrackingMode == .coach {
                    beginCatcherCoachCall()
                } else {
                    selectedPitch = ""
                }
            } else if currentTrackingMode == .scout && isSelectedChip {
                selectedPitch = ""
            } else {
                selectedPitch = pitch
            }
        } label: {
            Text(isNoneChip ? "Catcher" : pitch)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelectedChip ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelectedChip ? chipColor : Color(.systemGray6))
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isSelectedChip ? chipColor.opacity(0.9) : Color.black.opacity(0.12),
                            lineWidth: isSelectedChip ? 1.5 : 1
                        )
                )
                .shadow(
                    color: isSelectedChip ? chipColor.opacity(0.35) : .clear,
                    radius: isSelectedChip ? 5 : 0,
                    x: 0,
                    y: 2
                )
        }
        .buttonStyle(.plain)
    }

    private func syncSelectedPitchWithVisibleOptions() {
        let options = activePitchChipOptions
        guard !options.isEmpty else {
            selectedPitch = ""
            return
        }
        if selectedPitch.isEmpty {
            return
        }
        if currentTrackingMode == .scout {
            if !options.contains(selectedPitch) {
                selectedPitch = ""
            }
            return
        }
        if !options.contains(selectedPitch) {
            selectedPitch = options[0]
        }
    }
    
    private var atBatSidebar: AnyView {
        guard isGame else { return AnyView(EmptyView()) }
        let needsBatterSelection = selectedBatterId == nil

        return AnyView(
            VStack(spacing: 0) {
                Text("At Bat")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        needsBatterSelection
                            ? Color.red.opacity(atBatPulse ? 0.95 : 0.25)
                            : Color.gray
                    )
                    .task(id: needsBatterSelection) {
                        guard needsBatterSelection else {
                            atBatPulse = false
                            return
                        }
                        atBatPulse = false
                        while !Task.isCancelled {
                            withAnimation(.easeInOut(duration: 1.4)) {
                                atBatPulse.toggle()
                            }
                            try? await Task.sleep(nanoseconds: 800_000_000)
                        }
                    }

                    AnyView(
                        ScrollView(.vertical, showsIndicators: false) {
                            AnyView(
                                VStack(spacing: 6) {
                            ForEach(visibleJerseyCells) { cell in
                                JerseyRow(
                                    cell: cell,
                                    jerseyCells: $jerseyCells,
                                    selectedBatterId: $selectedBatterId,
                                    draggingJersey: $draggingJersey,
                                    editingCell: $editingCell,
                                    newJerseyNumber: $ui.newJerseyNumber,
                                    showAddJerseyPopover: $ui.showAddJerseyPopover,
                                    selectedGameId: selectedGameId,
                                    effectiveGameOwnerUserId: effectiveGameOwnerUserId,
                                    activeLiveId: activeLiveId,
                                    isReordering: $ui.isReorderingMode,
                                    onSelectedBatterChanged: { _ in
                                        ballsBinding.wrappedValue = 0
                                        strikesBinding.wrappedValue = 0
                                    }
                                )
                                .environmentObject(authManager)
                            }

                            if showAddJerseyPopover {
                                VStack(spacing: 6) {
                                    TextField("##", text: $ui.newJerseyNumber)
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
                                            pendingNewBatterActivation = nil
                                        }
                                        Spacer()
                                        Button("Save") {
                                            let trimmed = newJerseyNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                                            guard !trimmed.isEmpty else { return }

                                            let normalized = normalizeJersey(trimmed) ?? trimmed

                                            // 1) Apply local change (edit vs add) for instant UI feedback
                                            var editedBatterId: String? = nil
                                            var oldEditedJersey: String? = nil
                                            var addedBatterId: String? = nil
                                            pendingNewBatterActivation = nil
                                            if let editing = editingCell,
                                               let idx = jerseyCells.firstIndex(where: { $0.id == editing.id }) {
                                                editedBatterId = editing.id.uuidString
                                                oldEditedJersey = jerseyCells[idx].jerseyNumber
                                                jerseyCells[idx].jerseyNumber = normalized
                                            } else {
                                                // Add new cell (keep UUID stable across devices by storing batterIds)
                                                let newCell = JerseyCell(jerseyNumber: normalized)
                                                let shouldOfferActivation = !jerseyCells.isEmpty
                                                jerseyCells.append(newCell)
                                                addedBatterId = newCell.id.uuidString

                                                if shouldOfferActivation {
                                                    pendingNewBatterActivation = newCell
                                                }
                                            }

                                            // 2) Persist lineup (single source of truth)
                                            if let liveId = activeLiveId, !liveId.isEmpty {
                                                // LIVE session: mutate the server's current lineup transactionally so a
                                                // concurrent add/edit from the other side of the room isn't clobbered
                                                // by writing back this device's possibly-stale local array.
                                                LiveGameService.shared.mutateLiveLineup(liveId: liveId) { jerseys, batterIds in
                                                    if let batterId = editedBatterId {
                                                        if let idx = batterIds.firstIndex(of: batterId) {
                                                            jerseys[idx] = normalized
                                                        } else {
                                                            jerseys.append(normalized)
                                                            batterIds.append(batterId)
                                                        }
                                                    } else if let batterId = addedBatterId, !batterIds.contains(batterId) {
                                                        jerseys.append(normalized)
                                                        batterIds.append(batterId)
                                                    }
                                                } completion: { result in
                                                    guard case .success(let merged) = result,
                                                          let gameId = selectedGameId,
                                                          let owner = effectiveGameOwnerUserId,
                                                          !owner.isEmpty,
                                                          isOwnerForActiveGame else { return }
                                                    authManager.updateGameLineup(
                                                        ownerUserId: owner,
                                                        gameId: gameId,
                                                        jerseyNumbers: merged.jerseys,
                                                        batterIds: merged.batterIds
                                                    )
                                                }
                                            } else if let gameId = selectedGameId,
                                                      let owner = effectiveGameOwnerUserId,
                                                      !owner.isEmpty {
                                                // Non-live: update owner's game doc
                                                authManager.updateGameLineup(
                                                    ownerUserId: owner,
                                                    gameId: gameId,
                                                    jerseyNumbers: jerseyCells.map { $0.jerseyNumber },
                                                    batterIds: jerseyCells.map { $0.id.uuidString }
                                                )
                                            } else {
                                                debugLog("⚠️ Cannot update lineup: missing activeLiveId (live) or selectedGameId/effectiveGameOwnerUserId (non-live)")
                                            }

                                            if let batterId = editedBatterId,
                                               let oldJersey = oldEditedJersey {
                                                migrateEditedJerseyReferences(
                                                    batterId: batterId,
                                                    oldJersey: oldJersey,
                                                    newJersey: normalized
                                                )
                                            }

                                            // 3) Reset UI state
                                            showAddJerseyPopover = false
                                            jerseyInputFocused = false
                                            newJerseyNumber = ""
                                            editingCell = nil

                                            if pendingNewBatterActivation != nil {
                                                DispatchQueue.main.async {
                                                    showActivateNewBatterPrompt = true
                                                }
                                            }
                                        }
                                        .disabled(newJerseyNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                    }
                                }
                            }

                            Button(action: {
                                editingCell = nil
                                newJerseyNumber = ""
                                if isGame && isOwnerForActiveGame {
                                    // The single source for adding a batter
                                    // - everything else (roster pick, new
                                    // player, team setup) branches from here
                                    // now, not a separate control elsewhere.
                                    showAtBatAddMenu = true
                                } else if jerseyCells.isEmpty {
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
                                "Add a Batter to \(battingTeamDisplayName)",
                                isPresented: $ui.showAtBatAddMenu,
                                titleVisibility: .visible
                            ) {
                                Button("Jersey Number Only (this game)") {
                                    if jerseyCells.isEmpty {
                                        showBulkJerseyPrompt = true
                                    } else {
                                        showAddJerseyPopover = true
                                        jerseyInputFocused = true
                                    }
                                }
                                Button("Add from \(battingTeamDisplayName) Roster") {
                                    if let teamId = currentBattingTeamId {
                                        refreshBattingRoster(teamId: teamId)
                                        showAtBatRosterPickerSheet = true
                                    } else {
                                        promptTeamSetupForBatting()
                                    }
                                }
                                Button("New Player on \(battingTeamDisplayName)") {
                                    if let teamId = currentBattingTeamId {
                                        presentQuickAddPlayer(teamId: teamId) { newPlayer in
                                            self.addBatterFromRoster(newPlayer)
                                        }
                                    } else {
                                        promptTeamSetupForBatting()
                                    }
                                }
                                Button(battingTeamSetupMenuLabel) {
                                    promptTeamSetupForBatting()
                                }
                                Button("Cancel", role: .cancel) { }
                            }
                            .confirmationDialog(
                                "Add multiple jersey numbers?",
                                isPresented: $ui.showBulkJerseyPrompt,
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
                                Button("Add Dummy Lineup") {
                                    dummyLineupCount = ""
                                    showDummyLineupInput = true
                                }
                            } message: {
                                Text("Speak or type the jersey numbers with commas in between (example: 2, 7, 18).")
                            }
                            .alert("Add jersey numbers", isPresented: $ui.showBulkJerseyInput) {
                                TextField("2, 7, 18", text: $ui.bulkJerseyNumbers)
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

                                    if let liveId = activeLiveId, !liveId.isEmpty {
                                        // LIVE session: merge into the server's current lineup transactionally so a
                                        // concurrent add/edit from the other side of the room isn't clobbered.
                                        LiveGameService.shared.mutateLiveLineup(liveId: liveId) { jerseys, batterIds in
                                            let serverExisting = Set(jerseys)
                                            for cell in newCells where !serverExisting.contains(cell.jerseyNumber) {
                                                jerseys.append(cell.jerseyNumber)
                                                batterIds.append(cell.id.uuidString)
                                            }
                                        } completion: { result in
                                            guard case .success(let merged) = result,
                                                  let gameId = selectedGameId,
                                                  let owner = effectiveGameOwnerUserId,
                                                  !owner.isEmpty,
                                                  isOwnerForActiveGame else { return }
                                            authManager.updateGameLineup(
                                                ownerUserId: owner,
                                                gameId: gameId,
                                                jerseyNumbers: merged.jerseys,
                                                batterIds: merged.batterIds
                                            )
                                        }
                                    } else if let gameId = selectedGameId,
                                              let owner = effectiveGameOwnerUserId,
                                              !owner.isEmpty {
                                        authManager.updateGameLineup(
                                            ownerUserId: owner,
                                            gameId: gameId,
                                            jerseyNumbers: jerseyCells.map { $0.jerseyNumber },
                                            batterIds: jerseyCells.map { $0.id.uuidString }
                                        )
                                    } else {
                                        debugLog("⚠️ Cannot update lineup: missing activeLiveId (live) or selectedGameId/effectiveGameOwnerUserId (non-live)")
                                    }

                                    bulkJerseyNumbers = ""
                                }
                            } message: {
                                Text("Speak or type the jersey numbers with commas in between.")
                            }
                            .alert("Add dummy lineup", isPresented: $ui.showDummyLineupInput) {
                                TextField("6", text: $ui.dummyLineupCount)
                                Button("Cancel", role: .cancel) {
                                    dummyLineupCount = ""
                                }
                                Button("Add") {
                                    let trimmed = dummyLineupCount.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard let count = Int(trimmed), count > 0 else {
                                        dummyLineupCount = ""
                                        return
                                    }

                                    jerseyCells = (1...count).map { JerseyCell(jerseyNumber: "\($0)") }
                                    selectedBatterId = nil
                                    selectedBatterJersey = nil
                                    editingCell = nil
                                    showAddJerseyPopover = false
                                    jerseyInputFocused = false
                                    newJerseyNumber = ""

                                    persistLineupFromDetail()

                                    dummyLineupCount = ""
                                }
                            } message: {
                                Text("Enter how many batters to generate, starting at 1.")
                            }
                                }
                                .padding(.vertical,12)
                                .padding(.horizontal, 0)
                            )
                        }
                    )

                    atBatMapAndPinControls
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
            .frame(width: sidebarColumnWidth, height: strikeZoneHeight)
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        needsBatterSelection
                        ? Color.red.opacity(atBatPulse ? 1.0 : 0.01)
                            : Color.clear,
                        lineWidth: 2
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 4)
        )
    }

    /// A fixed section below the At Bat scroll (not an overlay), so the jersey
    /// list never scrolls underneath it. Each button disables itself instead of
    /// the row disappearing, which is what the old "Select a batter" / "Map" /
    /// "Scout" branches did.
    private var atBatMapAndPinControls: some View {
        let selectedCell = jerseyCells.first(where: { $0.id == selectedBatterId })
        let mapAvailable = selectedCell != nil && currentTrackingMode != .scout && !selectedBatterHeatmapEvents.isEmpty
        let pinAvailable = selectedCell != nil

        return VStack(spacing: 1) {
            Button {
                selectedAtBatHeatmapPitch = batterHeatmapPitchStats.first?.pitch ?? ""
                showAtBatHeatmapSheet = true
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(mapAvailable ? Color.orange : Color.secondary)
                    Text("Map")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(mapAvailable ? Color.primary : Color.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(.systemBackground))
            }
            .buttonStyle(.plain)
            .disabled(!mapAvailable)
            .opacity(mapAvailable ? 1.0 : 0.8)
            .accessibilityLabel("Pitch Location Map")

            Button {
                guard let cell = selectedCell else { return }
                Task { await openJerseyDetail(for: cell) }
            } label: {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(pinAvailable ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color(.systemGray5))
            }
            .buttonStyle(.plain)
            .disabled(!pinAvailable)
            .opacity(pinAvailable ? 1.0 : 0.8)
            .accessibilityLabel("Batter Pitch Detail")
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
    }

    // The five strike-zone corner overlays moved to top-level structs near
    // AddGameCard (ZoneOpponentLabel / ZoneResetButton / ZoneUndoButton /
    // ZoneGameStatsButtons / BatterSideOverlay) - see the comment there for
    // why. Don't reintroduce them as computed properties here.

    private func resetPitchSelection() {
        // ✅ 1) Reset local call/result UI
        resetCallAndResultUIState()

        // ✅ 2) Broadcast reset to participant by clearing SHARED pending + resultSelection
        if isGame,
           let gid = selectedGameId,
           let owner = effectiveGameOwnerUserId,
           !owner.isEmpty,
           isOwnerForActiveGame
        {
            if let liveId = activeLiveId, !liveId.isEmpty {
                LiveGameService.shared.updateLiveFields(liveId: liveId, fields: [
                    "pending": FieldValue.delete(),
                    "resultSelection": FieldValue.delete(),
                    "displayCode": FieldValue.delete()
                ])
            } else {
                // Legacy fallback when not connected to a live session.
                authManager.clearPendingPitch(ownerUserId: owner, gameId: gid)
                writeResultSelection(label: nil)
            }
        }
    }

    /// Each of these exists so the `self`-capturing closure (or the
    /// Binding) it builds is materialized in ITS own stack frame, not in
    /// `strikeZoneArea`'s - see the comment at the call site.
    private func makeZoneGameStatsButtons() -> ZoneGameStatsButtons {
        ZoneGameStatsButtons(
            isGame: isGame,
            showStats: $ui.showGameStatsSheet,
            showSummary: $ui.showGameSummarySheet
        )
    }

    private func makeZoneResetButton() -> ZoneResetButton {
        ZoneResetButton(
            blockHeight: zoneCornerButtonBlockHeight,
            onReset: { resetPitchSelection() }
        )
    }

    private func makeZoneUndoButton() -> ZoneUndoButton {
        ZoneUndoButton(
            blockHeight: zoneCornerButtonBlockHeight,
            isDisabled: lastPersistedEventInCurrentMode == nil,
            showConfirm: $ui.showUndoConfirm
        )
    }

    /// Builds `BatterSideOverlay` with this view's current state. Only the
    /// plain values it needs cross the boundary - no part of
    /// PitchTrackerView's type ends up inside the struct's metadata, which
    /// is the whole point of the extraction.
    private func makeBatterSideOverlay(SZwidth: CGFloat, verticalOffset: CGFloat = -20) -> BatterSideOverlay {
        BatterSideOverlay(
            SZwidth: SZwidth,
            verticalOffset: verticalOffset,
            batterSide: batterSide,
            showsScoutInPlayIndicator: currentTrackingMode == .scout && scoutObservedResult == .inPlay,
            onSelect: { side in
                withAnimation { batterSide = side }
                persistBatterSide(side)
                pushBatterSideToActiveGame(side)
            }
        )
    }

    /// Both corner text buttons sit inside a frame of this fixed height
    /// (reserving room for "Undo last pitch" wrapping to 2 lines) so their
    /// top edges land at the same y even though "Reset" is 1 line and
    /// "Undo last pitch" is 2 - a bottom-anchored block sized only to its
    /// own content would otherwise push the taller one higher. Passed into
    /// ZoneResetButton/ZoneUndoButton.
    private var zoneCornerButtonBlockHeight: CGFloat { 36 }

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
        let onResultLocationPicked: (String) -> Void
        let onCatcherLocationTap: () -> Void
        let isEncryptedMode: Bool
        let colorRefreshToken: UUID
        let template: PitchTemplate?
        let canInitiateCall: Bool
        let forceOutlineButtons: Bool
        @State private var resultGlowAngle: Double = 0
        @State private var resultGlowPulse: Bool = false

        private var highlightForResultLocationPick: Bool {
            isRecordingResult && calledPitch != nil && (pendingResultLabel == nil || !canInitiateCall)
        }

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
                    onResultLocationPicked: onResultLocationPicked,
                    onCatcherLocationTap: onCatcherLocationTap,
                    isEncryptedMode: isEncryptedMode,
                    template: template,
                    canInitiateCall: canInitiateCall,
                    forceOutlineButtons: forceOutlineButtons
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
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.cyan, .magenta, .yellow, .lime, .orange]),
                            center: .center,
                            angle: .degrees(resultGlowAngle)
                        ),
                        lineWidth: 2
                    )
                    .blur(radius: 2)
                    .opacity(highlightForResultLocationPick ? 0.9 : 0)
            )
            .shadow(
                color: Color.cyan.opacity(highlightForResultLocationPick ? (resultGlowPulse ? 0.6 : 0.3) : 0),
                radius: highlightForResultLocationPick ? (resultGlowPulse ? 10 : 4) : 6,
                x: 0,
                y: 6
            )
            .shadow(color: .black.opacity(0.7), radius: 6, x: 0, y: 6)
            .onChange(of: highlightForResultLocationPick) { _, isOn in
                guard isOn else {
                    resultGlowPulse = false
                    resultGlowAngle = 0
                    return
                }
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    resultGlowAngle = 360
                }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    resultGlowPulse = true
                }
            }
        }
    }
    
    /// Split out of `strikeZoneArea` for the same stack-frame reason the
    /// overlay factories exist: this call site alone builds ten closures
    /// that capture `self`, and `self` is a struct with hundreds of stored
    /// properties. Keeping them in their own frame is what leaves
    /// `strikeZoneArea` enough stack to assemble the overlays.
    private func makeStrikeZoneCard(SZwidth: CGFloat) -> AnyView {
        AnyView(
            StrikeZoneCard(
                SZwidth: SZwidth,
                strikeZoneHeight: strikeZoneHeight,
                isGame: $ui.isGame,
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
                pendingResultLabel: $ui.pendingResultLabel,
                showResultConfirmation: $ui.showResultConfirmation,
                showConfirmSheet: confirmSheetBinding,
                onResultLocationPicked: { pickedLabel in
                    pendingResultLabel = pickedLabel
                    actualLocationRecorded = pickedLabel
                    resultVisualState = pickedLabel
                    if calledPitch?.pitch.trimmingCharacters(in: .whitespacesAndNewlines) == "Catcher" {
                        let isStrike = pickedLabel.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Strike ")
                        calledPitch = PitchCall(
                            pitch: "Catcher",
                            location: pickedLabel,
                            isStrike: isStrike,
                            codes: calledPitch?.codes ?? []
                        )
                    }
                    pitchResultBannerPhase = .chooseAny
                    expandCalledPitchComposerToLarge()
                    if sessionManager.currentMode == .game, !isOwnerForActiveGame {
                        writeResultSelection(label: pickedLabel)
                    }
                },
                onCatcherLocationTap: {
                    pitchResultBannerPhase = .chooseAny
                    beginCatcherCoachCall()
                },
                isEncryptedMode: {
                    if let t = selectedTemplate {
                        return useEncrypted(for: t)
                    }
                    return false
                }(),
                colorRefreshToken: colorRefreshToken,
                template: selectedTemplate,
                canInitiateCall: canInitiateCall,
                forceOutlineButtons: isDemoMode
            )
        )
    }

    private func strikeZoneArea(width SZwidth: CGFloat) -> AnyView {
        let card = makeStrikeZoneCard(SZwidth: SZwidth)

        // Every overlay is built by its own `make…` method rather than
        // inline here. That is a STACK FRAME requirement, not style:
        // PitchTrackerView is a struct with hundreds of stored properties,
        // and any closure written inline in this function that touches
        // `self` emits an `outlined init with copy of PitchTrackerView` -
        // a full by-value copy of the whole view - into THIS frame. Three
        // such closures inline here overflowed the stack outright
        // (`___chkstk_darwin`). One copy per callee frame is fine; several
        // live at once in one frame is not. Keep new overlays factored the
        // same way, and prefer a @Binding over a closure where the action
        // is just setting state.
        var decoratedCard: AnyView = card
        decoratedCard = AnyView(decoratedCard.overlay(
            ZoneOpponentLabel(opponentName: opponentName),
            alignment: .bottomLeading
        ))
        decoratedCard = AnyView(decoratedCard.overlay(
            makeZoneGameStatsButtons(),
            alignment: .bottomTrailing
        ))
        decoratedCard = AnyView(decoratedCard.overlay(
            makeZoneResetButton(),
            alignment: .bottomLeading
        ))
        decoratedCard = AnyView(decoratedCard.overlay(
            makeZoneUndoButton(),
            alignment: .bottomTrailing
        ))
        let batterOverlay = AnyView(makeBatterSideOverlay(SZwidth: SZwidth, verticalOffset: 90))

        return AnyView(ZStack(alignment: .top) {
            decoratedCard
            batterOverlay
        }
        .frame(width: SZwidth, height: strikeZoneHeight))
    }
    private var codeLinkButton: some View {
        Menu {
            Button {
                if isDemoMode {
                    requireSignInForDemo("Sign in to add pitchers, games, and grid keys.")
                    return
                }
                activeHomeArea = .home
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            
            
            Button {
                if isDemoMode {
                    requireSignInForDemo("Sign in to invite another device or use live sharing.")
                    return
                }
                if !subscriptionManager.isPro {
                    proGateMessage = "Coach + Assistant mode is available in PitchMark Pro."
                    showProGateAlert = true
                    return
                }
                showCodeShareModePicker = true
            } label: {
                Label("Code Link", systemImage: "key.sensor.tag.radiowaves.left.and.right.fill")
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
    }


    private var batterAndModeBar: some View {
        EmptyView()
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
        // Auto-save the current pitch event when the result is confirmed.
        guard newValue != nil else { return }

        // Composer flow owns save/submit now; do not auto-dismiss via legacy paths.
        if calledPitch != nil {
            return
        }

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

        // Build minimal game event for the current tracker session.
        guard let pitchCall = calledPitch, let label = pendingResultLabel else { return }
        let event = PitchEvent(
            id: nil,
            timestamp: Date(),
            pitch: pitchCall.pitch,
            location: label,
            codes: pitchCall.codes,
            isStrike: pitchCall.isStrike,
            isBall: false,
            mode: .game,
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
            opponentJersey: jerseyCells.first(where: { $0.id == selectedBatterId })?.jerseyNumber,
            opponentBatterId: selectedBatterId?.uuidString,
            pitcherId: selectedPitcherId,
            hitterId: selectedHitterId
        )
        let resolvedEventId = UUID().uuidString
        var eventToSave = event
        eventToSave.id = resolvedEventId
        event.logDebugPayload(prefix: "📤 Auto-saving PitchEvent")

        // Persist and update UI state
        authManager.savePitchEvent(eventToSave)
        saveSharedPitcherEventIfAllowed(eventToSave)
        saveSharedHitterEventIfAllowed(eventToSave)
        sessionManager.incrementCount()
        withAnimation(.easeInOut(duration: 0.3)) {
            pitchEvents.append(eventToSave)
        }
        authManager.loadPitchEvents { events in
            self.pitchEvents = events
        }
        if overlayTab == .progress {
            progressRefreshToken = UUID()
        }

        // Prevent sheet from showing and reset UI state (mirror sheet save reset)
        showConfirmSheet = false
        resultVisualState = event.location
        activeCalledPitchId = nil
        isRecordingResult = false
        showConfirmSheet = false
        selectedLocation = ""
        lastTappedPosition = nil
        calledPitch = nil
        resultVisualState = nil
        actualLocationRecorded = nil
        pendingResultLabel = nil
        isStrikeSwinging = false
        isStrikeLooking = false
        isWildPitch = false
        isPassedBall = false
        isBall = false
        isError = false
        selectedOutcome = nil
        selectedDescriptor = nil
    }

    private func buildPitchOnlyEvent() -> PitchEvent? {
        guard let pitchCall = calledPitch else {
            return nil
        }
        let label = pendingResultLabel ?? pitchCall.location
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let resolvedIsStrike = heatmapResultIsInsideStrikeZone(label)

        return PitchEvent(
            id: nil,
            timestamp: Date(),
            pitch: pitchCall.pitch,
            location: label,
            codes: pitchCall.codes,
            isStrike: resolvedIsStrike,
            isBall: !resolvedIsStrike,
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
            pitcherId: effectivePitcherIdForSave,
            hitterId: selectedHitterId
        )
    }

    private func saveScoutEvent() {
        guard let event = buildScoutEvent() else { return }
        savedPlayReviewEvent = event
        savedPlayReviewTitle = "Save Pitch"
        savedPlayReviewSummaryLines = outcomeSummaryLines(for: event)
        savedPlayReviewDraft = SavedPlayReviewDraft(
            title: savedPlayReviewTitle,
            summaryLines: savedPlayReviewSummaryLines,
            event: event
        )
    }

    private func makeSavedPlayReviewCountText(for event: PitchEvent) -> String {
        let countText = (event.atBatCount ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !countText.isEmpty {
            return countText
        }
        let balls = max(0, event.atBatBalls ?? 0)
        let strikes = max(0, event.atBatStrikes ?? 0)
        return "\(balls)-\(strikes)"
    }

    private func refreshSavedPlayCount() {
        guard let event = savedPlayReviewEvent else { return }
        savedPlayReviewCountText = makeSavedPlayReviewCountText(for: event)
        syncCountFromComposer(
            balls: event.atBatBalls ?? 0,
            strikes: event.atBatStrikes ?? 0
        )
    }

    private func commitReviewedSavedPlayEvent(_ event: PitchEvent) {
        savedPlayReviewEvent = event
        persistPitchEvent(event, shouldFinalizeComposer: false)
        finalizeSavedPlayReview()
    }

    private func finalizeSavedPlayReview() {
        let event = savedPlayReviewEvent
        savedPlayReviewDraft = nil
        savedPlayReviewEvent = nil
        savedPlayReviewSummaryLines = []
        savedPlayReviewCountText = ""
        if let event {
            finalizePersistedPitchEvent(event)
        } else {
            resetScoutComposer()
        }
        resetCallAndResultUIState()
    }

    private func buildScoutEvent() -> PitchEvent? {
        guard let observed = scoutObservedResult else { return nil }

        let prior = priorScoutCount()
        let inferredPitch = selectedPitch.isEmpty ? "Catcher" : selectedPitch
        let inferredCodes = pitchCodeAssignments
            .filter { $0.pitch == inferredPitch }
            .map { $0.code }

        let strikeLooking = observed == .calledStrike
        let strikeSwinging = observed == .swingingStrike
        let isFoul = observed == .foul
        let isBallResult = observed == .ball
        let scoutMappedLocation: String = {
            guard let selection = scoutZoneSelection else { return "Scout" }
            let prefix = selection.isStrikeZone ? "Strike" : "Ball"
            return "\(prefix) \(selection.label)"
        }()

        var event = PitchEvent(
            id: nil,
            timestamp: Date(),
            pitch: inferredPitch,
            location: scoutMappedLocation,
            codes: inferredCodes,
            isStrike: strikeLooking || strikeSwinging || isFoul,
            isBall: isBallResult,
            mode: sessionManager.currentMode,
            calledPitch: nil,
            batterSide: batterSide,
            templateId: selectedTemplate?.id.uuidString,
            strikeSwinging: strikeSwinging,
            wildPitch: scoutMiscOutcome == "WP",
            passedBall: scoutMiscOutcome == "PB",
            strikeLooking: strikeLooking,
            outcome: scoutOutcome(for: observed, prior: prior),
            descriptor: scoutPersistedDescriptor,
            errorOnPlay: scoutErrorOnPlay,
            battedBallRegion: observed == .inPlay ? scoutBattedBallRegionName : nil,
            battedBallType: scoutPersistedDescriptor ?? scoutDescriptor,
            battedBallTapX: observed == .inPlay ? scoutBattedBallTapNormalized.map { Double($0.x) } : nil,
            battedBallTapY: observed == .inPlay ? scoutBattedBallTapNormalized.map { Double($0.y) } : nil,
            gameId: selectedGameId,
            opponentJersey: jerseyCells.first(where: { $0.id == selectedBatterId })?.jerseyNumber,
            opponentBatterId: selectedBatterId?.uuidString,
            pitcherId: effectivePitcherIdForSave,
            hitterId: selectedHitterId,
            foulMarker: isFoul ? scoutFoulMarkerSymbol(prior: prior) : nil,
            trackingMode: .scout
        )

        if scoutMiscOutcome == "HBP" {
            event.outcome = "HBP"
        }

        // Scout mode now shares the one rule set with the pitch result sheet.
        // It previously kept the *prior* count on a terminal pitch while the sheet
        // reset to 0-0, so the same at-bat could read differently depending on
        // which screen recorded it.
        let scoutResult = AtBatCountRules.apply(
            AtBatCountRules.PitchFacts(event: event),
            to: AtBatCount(balls: prior.balls, strikes: prior.strikes)
        )
        event.applyCount(scoutResult.count, terminal: scoutResult.terminal)

        return event
    }

    private func priorScoutCount() -> (balls: Int, strikes: Int) {
        return (balls: balls, strikes: strikes)
    }

    private func scoutOutcome(for observed: ScoutObservedResult, prior: (balls: Int, strikes: Int)) -> String? {
        switch observed {
        case .ball:
            return prior.balls >= 3 ? "Walk" : nil
        case .calledStrike:
            return prior.strikes >= 2 ? "ꓘ" : nil
        case .swingingStrike:
            return prior.strikes >= 2 ? "K" : nil
        case .foul:
            return scoutInPlayOutcome ?? "Foul"
        case .inPlay:
            return scoutInPlayOutcome ?? (scoutHitOnPlay ? "Hit" : nil)
        }
    }

    private func scoutFoulMarkerSymbol(prior: (balls: Int, strikes: Int)) -> String {
        return "\(max(1, min(2, prior.strikes + 1))).circle"
    }

    private var scoutPersistedDescriptor: String? {
        let parts = [scoutDescriptor, scoutHitOnPlay ? "Hit" : nil]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }

    private func eventCountsAsHit(_ event: PitchEvent) -> Bool {
        pitchEventCountsAsHit(event)
    }

    private func persistPitchEvent(_ event: PitchEvent, shouldFinalizeComposer: Bool = true) {
        var eventToPersist = event
        let resolvedEventId = {
            let raw = eventToPersist.id?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty == false) ? raw! : UUID().uuidString
        }()
        eventToPersist.id = resolvedEventId
        let fallbackBatterId = selectedBatterId?.uuidString
        let fallbackJersey = jerseyCells.first(where: { $0.id == selectedBatterId })?.jerseyNumber ?? selectedBatterJersey
        if eventToPersist.opponentBatterId == nil {
            eventToPersist.opponentBatterId = fallbackBatterId
        }
        if eventToPersist.opponentJersey == nil {
            eventToPersist.opponentJersey = fallbackJersey
        }
        if eventToPersist.hitterId == nil {
            eventToPersist.hitterId = selectedHitterId
        }
        if let savedBalls = eventToPersist.atBatBalls, let savedStrikes = eventToPersist.atBatStrikes,
           let key = atBatCountKey(batterId: eventToPersist.opponentBatterId, jersey: eventToPersist.opponentJersey) {
            atBatCountCacheByBatter[key] = (balls: savedBalls, strikes: savedStrikes)
            syncCountFromComposer(balls: savedBalls, strikes: savedStrikes)
        }

        var sharedEvent = eventToPersist
        sharedEvent.id = resolvedEventId
        if isGame, let liveId = activeLiveId {
            // ✅ Live: save to shared room
            let uid = authManager.user?.uid ?? ""
            do {
                var eventData = try Firestore.Encoder().encode(eventToPersist)
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
                    .collection("pitchEvents").document(resolvedEventId)
                let liveEventId = liveRef.documentID
                sharedEvent.id = liveEventId

                liveRef.setData(eventData, merge: false) { err in
                    if let err {
                        debugLog("❌ live pitchEvent save failed:", err.localizedDescription)
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
                            debugLog("❌ owner pitchEvent save failed:", err.localizedDescription)
                        }
                    }
                } else {
                    debugLog("⚠️ Owner path unavailable; saved only to liveGames.")
                }

                // clear pending in live doc
                LiveGameService.shared.updateLiveFields(liveId: liveId, fields: [
                    "pending": FieldValue.delete()
                ])
            } catch {
                debugLog("❌ encode event failed:", error)
            }
        } else if isGame, let gid = selectedGameId, let owner = effectiveGameOwnerUserId {
            // Legacy fallback
            authManager.saveGamePitchEvent(ownerUserId: owner, gameId: gid, event: eventToPersist)
            authManager.clearPendingPitch(ownerUserId: owner, gameId: gid)
        } else {
            authManager.savePitchEvent(eventToPersist)
        }

        if !isDemoMode {
            saveSharedPitcherEventIfAllowed(sharedEvent)
            saveSharedHitterEventIfAllowed(sharedEvent)
            writeResultSelection(label: eventToPersist.location)
        }

        sessionManager.incrementCount()
        applyProgressOutcomeAdjustments(for: eventToPersist)
        applyReviewedOutAdvanceIfNeeded(for: eventToPersist)
        if eventToPersist.atBatBalls == nil || eventToPersist.atBatStrikes == nil {
            applyProgressCountAdjustments(for: eventToPersist)
        }

        // ✅ LIVE: do NOT append to local pitchEvents (prevents “saved on participant” feeling).
        // Owner will show cards from live listener; legacy continue using pitchEvents.
        if activeLiveId == nil {
            withAnimation(.easeInOut(duration: 0.3)) {
                pitchEvents.append(eventToPersist)
                if isDemoMode {
                    gamePitchEvents.append(eventToPersist)
                }
            }
            if !isDemoMode {
                authManager.loadPitchEvents { events in
                    self.pitchEvents = events
                }
            }
            if overlayTab == .progress {
                progressRefreshToken = UUID()
            }
        }

        guard shouldFinalizeComposer else { return }
        finalizePersistedPitchEvent(eventToPersist)
    }

    private func finalizePersistedPitchEvent(_ event: PitchEvent) {
        autoAdvanceSelectedBatterIfNeeded(after: event)
        resultVisualState = event.location
        activeCalledPitchId = nil
        isRecordingResult = false
        selectedLocation = ""
        lastTappedPosition = nil
        calledPitch = nil
        resultVisualState = nil
        actualLocationRecorded = nil
        pendingResultLabel = nil
        isStrikeSwinging = false
        isStrikeLooking = false
        isWildPitch = false
        isPassedBall = false
        isBall = false
        isError = false
        selectedOutcome = nil
        selectedDescriptor = nil
    }

    private func autoAdvanceSelectedBatterIfNeeded(after event: PitchEvent) {
        guard shouldAdvanceBatterSelection(after: event) else { return }
        syncCountFromComposer(balls: 0, strikes: 0)
        let savedJersey = event.opponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !savedJersey.isEmpty else { return }
        let cells = visibleJerseyCells
        guard !cells.isEmpty else { return }

        let currentIndex: Int? = {
            if let batterId = event.opponentBatterId,
               let match = cells.firstIndex(where: { $0.id.uuidString == batterId }) {
                return match
            }
            return cells.firstIndex {
                $0.jerseyNumber.trimmingCharacters(in: .whitespacesAndNewlines) == savedJersey
            }
        }()

        guard let currentIndex else { return }

        if currentIndex + 1 < cells.count {
            syncSelectedBatterFromDetail(cells[currentIndex + 1])
        } else {
            presentNextBatterAdjustmentAlert(currentIndex: currentIndex, totalCount: cells.count)
        }
    }

    private func shouldAdvanceBatterSelection(after event: PitchEvent) -> Bool {
        let outcome = (event.outcome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOutcome = outcome.lowercased()
        if normalizedOutcome.contains("foul") {
            return false
        }

        let descriptor = (event.descriptor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let battedBallType = (event.battedBallType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let battedBallRegion = (event.battedBallRegion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !descriptor.isEmpty || !battedBallType.isEmpty || !battedBallRegion.isEmpty {
            let advancementDescriptors: Set<String> = ["Grounder", "Line", "Pop", "Fly", "Bunt"]
            if advancementDescriptors.contains(descriptor) || advancementDescriptors.contains(battedBallType) {
                return true
            }
            if !battedBallRegion.isEmpty && !battedBallRegion.localizedCaseInsensitiveContains("foul") {
                return true
            }
        }

        if normalizedOutcome.contains("walk")
            || normalizedOutcome.contains("hbp")
            || normalizedOutcome.contains("strikeout")
            || normalizedOutcome.contains("strike looking")
            || normalizedOutcome.contains("looking strike")
            || normalizedOutcome.contains("single")
            || normalizedOutcome.contains("double")
            || normalizedOutcome.contains("triple")
            || normalizedOutcome.contains("home run")
            || normalizedOutcome.contains("homer")
            || normalizedOutcome.contains("hr")
            || normalizedOutcome.contains("1b")
            || normalizedOutcome.contains("2b")
            || normalizedOutcome.contains("3b")
            || normalizedOutcome.contains("out")
            || normalizedOutcome == "k"
            || normalizedOutcome == "ꓘ".lowercased() {
            return true
        }
        return (event.atBatCount ?? "").trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Strikeout") == .orderedSame
    }

    private func presentNextBatterAdjustmentAlert(currentIndex: Int, totalCount: Int) {
        nextBatterAdjustmentMessage = "Adjust to next batter if needed [\(currentIndex + 1) of \(totalCount)]"
        showNextBatterAdjustmentAlert = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            showNextBatterAdjustmentAlert = false
        }
    }

    /// Fallback for events that arrive without count fields (older records, or a
    /// participant's event). Uses the same rules as everything else rather than
    /// its own copy of them.
    private func applyProgressCountAdjustments(for event: PitchEvent) {
        let result = AtBatCountRules.apply(
            AtBatCountRules.PitchFacts(event: event),
            to: AtBatCount(balls: balls, strikes: strikes)
        )
        updateCount(result.count)
    }

    private func applyProgressOutcomeAdjustments(for event: PitchEvent) {
        let normalizedOutcome = (event.outcome ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalizedOutcome.contains("walk") {
            let nextWalks = max(0, walks + 1)
            walksBinding.wrappedValue = nextWalks
        }

        if eventCountsAsHit(event) {
            let nextHits = max(0, hits + 1)
            hitsBinding.wrappedValue = nextHits
        }
    }

    private func reviewedEventCountsAsOut(_ event: PitchEvent) -> Bool {
        let normalizedOutcome = (event.outcome ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalizedOutcome.contains("out")
            || normalizedOutcome.contains("strikeout")
            || normalizedOutcome.contains("strike looking")
            || normalizedOutcome.contains("looking strike")
            || normalizedOutcome == "k"
            || normalizedOutcome == "ꓘ".lowercased() {
            return true
        }

        let countText = (event.atBatCount ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if countText.caseInsensitiveCompare("Out") == .orderedSame || countText.caseInsensitiveCompare("Strikeout") == .orderedSame {
            return true
        }

        return false
    }

    private func applyReviewedOutAdvanceIfNeeded(for event: PitchEvent) {
        guard sessionManager.currentMode == .game else { return }
        guard reviewedEventCountsAsOut(event) else { return }

        pendingOutsResetWorkItem?.cancel()
        let nextOuts = min(3, outs + 1)
        updateOuts(nextOuts)

        guard nextOuts >= 3 else { return }

        lastOutResetEventIdentity = event.identity
        lastOutResetPreviousOuts = max(0, nextOuts - 1)
        scheduleOutsResetToZero()
    }

    /// Shared by the pitch-outcome path and the manual out-circle tap so both
    /// clear the circles the same way once outs hits 3, instead of only the
    /// pitch-outcome path resetting and manual taps leaving all three lit.
    private func scheduleOutsResetToZero() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showOutsFlash = true
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.18)) {
                self.updateOuts(0)
                self.showOutsFlash = false
            }
            self.pendingOutsResetWorkItem = nil
        }
        pendingOutsResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    /// Outs used to be device-local: nothing carried them in the live payload,
    /// so the owner's indicator never moved for an out the partner recorded and
    /// the two devices disagreed about the inning for the rest of the game.
    /// `Game` has no `outs` column, so this syncs through the live room only -
    /// outs are inning-scoped and not worth a stored-model migration.
    private func updateOuts(_ next: Int) {
        let clamped = max(0, min(3, next))
        guard outs != clamped else { return }
        outs = clamped
        markLocalProgressChange()
    }

    /// Count changes coming from the pitch composer / result sheet.
    /// Shares the one write path so live games get the same stamping as local ones.
    private func syncCountFromComposer(balls: Int, strikes: Int) {
        updateCount(AtBatCount(balls: balls, strikes: strikes))
    }

    private var lastPersistedEventInCurrentMode: PitchEvent? {
        let sourceEvents = isGame ? gamePitchEvents : pitchEvents
        return sourceEvents
            .filter { event in
                if isGame, let gid = selectedGameId, let evGameId = event.gameId, !evGameId.isEmpty {
                    return evGameId == gid
                }
                return true
            }
            .sorted { $0.timestamp > $1.timestamp }
            .first
    }

    private func undoLastPitch() {
        guard let event = lastPersistedEventInCurrentMode else { return }
        guard let eventId = event.id?.trimmingCharacters(in: .whitespacesAndNewlines), !eventId.isEmpty else { return }

        pendingOutsResetWorkItem?.cancel()
        pendingOutsResetWorkItem = nil
        showOutsFlash = false

        deletePersistedPitchEvent(event)
        removeLocalPitchEvent(withIdentity: event.identity)

        sessionManager.decrementCount()

        let remaining = remainingEvents(afterRemovingIdentity: event.identity)
        if let priorEvent = remaining.first,
           let priorBalls = priorEvent.atBatBalls,
           let priorStrikes = priorEvent.atBatStrikes {
            syncCountFromComposer(balls: priorBalls, strikes: priorStrikes)
            if let key = atBatCountKey(batterId: priorEvent.opponentBatterId, jersey: priorEvent.opponentJersey) {
                atBatCountCacheByBatter[key] = (balls: priorBalls, strikes: priorStrikes)
            }
        } else {
            syncCountFromComposer(balls: 0, strikes: 0)
        }

        if reviewedEventCountsAsOut(event) {
            if lastOutResetEventIdentity == event.identity {
                updateOuts(lastOutResetPreviousOuts ?? 2)
                lastOutResetEventIdentity = nil
                lastOutResetPreviousOuts = nil
            } else {
                updateOuts(max(0, outs - 1))
            }
        }

        if eventCountsAsHit(event) {
            hitsBinding.wrappedValue = max(0, hits - 1)
        }

        let normalizedOutcome = (event.outcome ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedOutcome.contains("walk") {
            walksBinding.wrappedValue = max(0, walks - 1)
        }

        if let batterIdText = event.opponentBatterId,
           let batterUUID = UUID(uuidString: batterIdText),
           let batterCell = jerseyCells.first(where: { $0.id == batterUUID }) {
            syncSelectedBatterFromDetail(batterCell)
        } else if let jersey = event.opponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines), !jersey.isEmpty {
            if let batterCell = jerseyCells.first(where: { $0.jerseyNumber.trimmingCharacters(in: .whitespacesAndNewlines) == jersey }) {
                syncSelectedBatterFromDetail(batterCell)
            }
        }
    }

    private func remainingEvents(afterRemovingIdentity identity: String) -> [PitchEvent] {
        let sourceEvents = isGame ? gamePitchEvents : pitchEvents
        return sourceEvents
            .filter { $0.identity != identity }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func removeLocalPitchEvent(withIdentity identity: String) {
        pitchEvents.removeAll { $0.identity == identity }
        gamePitchEvents.removeAll { $0.identity == identity }
        seededGamePitchEventsForLive.removeAll { $0.identity == identity }
        bufferedSharedPitcherEvents.removeAll { $0.event.identity == identity }
        bufferedSharedHitterEvents.removeAll { $0.event.identity == identity }
    }

    private func deletePersistedPitchEvent(_ event: PitchEvent) {
        guard let eventId = event.id?.trimmingCharacters(in: .whitespacesAndNewlines), !eventId.isEmpty else { return }

        let db = Firestore.firestore()
        var refs: [DocumentReference] = []

        if let liveId = activeLiveId, !liveId.isEmpty {
            refs.append(
                db.collection("liveGames")
                    .document(liveId)
                    .collection("pitchEvents")
                    .document(eventId)
            )
            if let owner = effectiveGameOwnerUserId, !owner.isEmpty,
               let gid = selectedGameId, !gid.isEmpty {
                refs.append(
                    db.collection("users")
                        .document(owner)
                        .collection("games")
                        .document(gid)
                        .collection("pitchEvents")
                        .document(eventId)
                )
            }
        } else if let owner = effectiveGameOwnerUserId, !owner.isEmpty,
                  let gid = selectedGameId, !gid.isEmpty {
            refs.append(
                db.collection("users")
                    .document(owner)
                    .collection("games")
                    .document(gid)
                    .collection("pitchEvents")
                    .document(eventId)
            )
        } else if let uid = authManager.user?.uid {
            refs.append(
                db.collection("users")
                    .document(uid)
                    .collection("pitchEvents")
                    .document(eventId)
            )
        }

        let pitcherId = (event.pitcherId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? event.pitcherId?.trimmingCharacters(in: .whitespacesAndNewlines)
            : selectedPitcherId
        if let pitcherId, !pitcherId.isEmpty {
            refs.append(
                db.collection("pitchers")
                    .document(pitcherId)
                    .collection("pitchEvents")
                    .document(eventId)
            )
        }

        guard !refs.isEmpty else { return }

        // Deleted one copy at a time rather than as a `WriteBatch`. A batch is
        // atomic, and this list spans three different owners' rules: a
        // participant cannot delete from users/{owner}/games/... and a
        // non-owner of the pitcher cannot delete from /pitchers/{id}/... . In
        // a batch either of those denials rejected the whole commit, so Undo
        // rolled back the count, outs and hits locally while every stored copy
        // of the pitch survived - and the live listener put the card straight
        // back. Independent deletes let each copy go on its own permissions.
        for ref in refs {
            ref.delete { error in
                if let error {
                    debugLog("❌ undoLastPitch delete failed for \(ref.path): \(error.localizedDescription)")
                }
            }
        }
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
            debugLog("❌ Failed to decode buffered pitcher events:", error.localizedDescription)
            bufferedSharedPitcherEvents = []
        }
    }

    private func persistBufferedSharedPitcherEvents() {
        do {
            let data = try JSONEncoder().encode(bufferedSharedPitcherEvents)
            try data.write(to: bufferedSharedEventsURL, options: [.atomic])
        } catch {
            debugLog("❌ Failed to persist buffered pitcher events:", error.localizedDescription)
        }
    }

    private func bufferSharedPitcherEvent(pitcherId: String, event: PitchEvent) {
        bufferedSharedPitcherEvents.append(BufferedPitcherEvent(pitcherId: pitcherId, event: event))
        persistBufferedSharedPitcherEvents()
    }

    private func flushBufferedSharedPitcherEvents(reason: String) {
        guard !bufferedSharedPitcherEvents.isEmpty else { return }
        debugLog("📤 Flushing \(bufferedSharedPitcherEvents.count) buffered pitcher events (reason: \(reason))")
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
            debugLog("⚠️ Shared pitcher write not confirmed (owner/shared missing); attempting save to let rules decide.")
        }

        if shouldWriteSharedPitcherEventImmediately {
            authManager.saveSharedPitcherEvent(pitcherId: pitcherId, event: event)
        } else {
            bufferSharedPitcherEvent(pitcherId: pitcherId, event: event)
        }
    }

    // MARK: - Hitter event mirroring (parallels the pitcher pipeline above)

    private var bufferedSharedHitterEventsURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("PitchMark", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("buffered_shared_hitter_events.json")
    }

    private func loadBufferedSharedHitterEvents() {
        let url = bufferedSharedHitterEventsURL
        guard let data = try? Data(contentsOf: url) else {
            bufferedSharedHitterEvents = []
            return
        }
        do {
            bufferedSharedHitterEvents = try JSONDecoder().decode([BufferedHitterEvent].self, from: data)
        } catch {
            debugLog("❌ Failed to decode buffered hitter events:", error.localizedDescription)
            bufferedSharedHitterEvents = []
        }
    }

    private func persistBufferedSharedHitterEvents() {
        do {
            let data = try JSONEncoder().encode(bufferedSharedHitterEvents)
            try data.write(to: bufferedSharedHitterEventsURL, options: [.atomic])
        } catch {
            debugLog("❌ Failed to persist buffered hitter events:", error.localizedDescription)
        }
    }

    private func bufferSharedHitterEvent(hitterId: String, event: PitchEvent) {
        bufferedSharedHitterEvents.append(BufferedHitterEvent(hitterId: hitterId, event: event))
        persistBufferedSharedHitterEvents()
    }

    private func flushBufferedSharedHitterEvents(reason: String) {
        guard !bufferedSharedHitterEvents.isEmpty else { return }
        debugLog("📤 Flushing \(bufferedSharedHitterEvents.count) buffered hitter events (reason: \(reason))")
        for buffered in bufferedSharedHitterEvents {
            authManager.saveSharedHitterEvent(hitterId: buffered.hitterId, event: buffered.event)
        }
        bufferedSharedHitterEvents.removeAll()
        persistBufferedSharedHitterEvents()
    }

    /// No owner/shared pre-check here the way the pitcher version has one -
    /// Hitter has no sharing concept (ownerUid-only rules), and this device
    /// never has a loaded `hitters` list to check against. The write either
    /// matches the rules' ownerUid check or is denied and logged, same
    /// fire-and-forget posture the pitcher path already falls back to when
    /// it can't confirm ownership locally.
    private func saveSharedHitterEventIfAllowed(_ event: PitchEvent) {
        let targetHitterId = event.hitterId ?? selectedHitterId
        guard let hitterId = targetHitterId else { return }

        if shouldWriteSharedPitcherEventImmediately {
            authManager.saveSharedHitterEvent(hitterId: hitterId, event: event)
        } else {
            bufferSharedHitterEvent(hitterId: hitterId, event: event)
        }
    }

    private var baseBody: some View {
        ZStack {
            backgroundView
                .ignoresSafeArea()
            // Always allow scrolling as a fallback, rather than gating it behind a
            // fixed height threshold. mainStack sizes several regions as a fraction
            // of effectiveScreenSize.height, but other chrome around it (header,
            // pitch buttons, At Bat list, count row, score section) has fixed
            // point heights - on a screen shorter than whatever device those
            // fixed heights were tuned against, the fractional regions no longer
            // leave enough room and content bleeds past the safe area with no way
            // to reach it. A ScrollView whose content already fits behaves exactly
            // like a plain stack, so this is a no-op on devices that already fit.
            padPortraitContainer(
                ScrollView(.vertical, showsIndicators: false) {
                    mainStack
                        .padding(.bottom, 12)
                }
            )
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // Attached at the root, where its full-screen overlay can actually
        // receive a tap anywhere. Both of the buttons that set
        // showUndoConfirm (the cards row and the zone's bottom-right
        // corner) used to carry their own copy of this dialog, which meant
        // two dialogs presenting at once, each only tappable inside its own
        // small button's frame.
        .appConfirmationDialog(
            isPresented: $ui.showUndoConfirm,
            title: "Undo Last Pitch?",
            message: "This will remove the last recorded pitch.",
            primaryTitle: "Undo",
            primaryRole: .destructive,
            primaryAction: { undoLastPitch() },
            secondaryTitle: "Cancel"
        )
        .onAppear {
            AppDelegate.setOrientationLock(.portrait)
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
            AppDelegate.setOrientationLock(.landscapeRight)
            forceOrientation(.landscapeRight)
            startDisplaySessionListener()
            startListeningToDisplayState()
            startDisplayHeartbeat(liveId: liveId)
        }
        .onDisappear {
            stopDisplayOnlyListeners()
            AppDelegate.setOrientationLock(.portrait)
            forceOrientation(.portrait)
        }
    }

    private func startListeningToDisplayState() {
        displayStateListener?.remove()
        displayStateListener = nil

        guard let uid = authManager.user?.uid, !uid.isEmpty else {
            debugLog("⚠️ Display state listener missing uid")
            return
        }

        debugLog("🖥️ Display state listener attaching to users/\(uid)/displayState/current")
        let ref = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("displayState")
            .document("current")

        displayStateListener = ref.addSnapshotListener { snap, err in
            if let err {
                debugLog("❌ Display state listener error:", err.localizedDescription)
                return
            }
            guard let data = snap?.data() else {
                debugLog("🖥️ Display state cleared / missing. raw=nil")
                DispatchQueue.main.async {
                    self.displayCodePayload = nil
                }
                return
            }

            if let colorName = data["colorName"] as? String,
               let code = data["code"] as? String,
               !colorName.isEmpty,
               !code.isEmpty {
                debugLog("🖥️ Display state received color=\(colorName) code=\(code)")
                DispatchQueue.main.async {
                    self.showDisplayCode(colorName: colorName, code: code)
                }
            } else {
                debugLog("🖥️ Display state missing fields raw=\(data)")
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
        debugLog("🖥️ Display session listener attaching to activeSession")
        displaySessionListener = ref.addSnapshotListener { snap, err in
            if let err {
                debugLog("⚠️ display session listener error:", err.localizedDescription)
                return
            }
            let data = snap?.data() ?? [:]
            let liveId = data["liveId"] as? String
            let mode = data["mode"] as? String ?? "<nil>"
            let claimedDevice = data["deviceId"] as? String
            debugLog("🖥️ Display session update mode=\(mode) liveId=\(liveId ?? "<nil>")")

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

    /// Publishes which live room this device is showing. It deliberately does
    /// **not** write `deviceId` any more.
    ///
    /// It used to, and that silently re-claimed primary as a side effect of
    /// publishing a liveId: after another device took over, this one would
    /// stamp its own id back onto the document the moment anything called
    /// here, the other device's listener would see a foreign id and raise its
    /// own "Account In Use", and the two would trade primary back and forth -
    /// the reported loop where taking over primary bounced you to Home and
    /// the next game tap bounced you straight back again.
    ///
    /// Claiming primary is `claimPrimarySession`'s job alone, reached only
    /// through the explicit "Take Over Primary" button or through
    /// `ensurePrimarySessionOrPrompt` finding no owner at all.
    private func updateActiveSessionLiveId(_ liveId: String?) {
        guard !isDisplayOnlyMode, !showSessionConflictAlert else { return }
        guard let ref = activeSessionDocRef else { return }
        var payload: [String: Any] = [:]
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
                    debugLog("❌ Auto live session create failed:", err.localizedDescription)
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

    /// Reads `users/{uid}/meta/activeSession` and reports back whether this
    /// device is blocked by another one holding primary.
    ///
    /// **The completion is the whole point.** This is a Firestore read, so it
    /// returns long after the call. Callers used to invoke it and then test
    /// `showSessionConflictAlert` on the very next line, which could never be
    /// true yet - so the boot flow and the resume flow always continued as if
    /// there were no conflict, presented their sheets, and the "Account In
    /// Use" blocker then arrived *underneath* them (it is a root `.overlay`,
    /// and a sheet renders above that). That is the "it asked me to take over
    /// primary from behind the pitcher/grid-key sheet" report.
    ///
    /// Concurrent callers are queued rather than dropped: at launch,
    /// `.onAppear` plus the `isSignedIn` and `uid` onChange handlers can all
    /// land within a frame of each other, and the old `guard
    /// !sessionCheckInProgress else { return }` silently stranded every
    /// caller but the first - which, with a completion, would have hung the
    /// boot flow outright.
    private func ensurePrimarySessionOrPrompt(completion: ((Bool) -> Void)? = nil) {
        guard !isDisplayOnlyMode else { completion?(false); return }
        guard authManager.isSignedIn else { completion?(false); return }
        guard let ref = activeSessionDocRef else { completion?(false); return }

        if let completion { ui.pendingPrimarySessionChecks.append(completion) }
        guard !sessionCheckInProgress else { return }
        sessionCheckInProgress = true

        func finish(_ hasConflict: Bool) {
            sessionCheckInProgress = false
            let waiting = ui.pendingPrimarySessionChecks
            ui.pendingPrimarySessionChecks = []
            for block in waiting { block(hasConflict) }
        }

        ref.getDocument { snap, err in
            if let err {
                debugLog("⚠️ activeSession read failed:", err.localizedDescription)
                finish(false)
                return
            }

            let data = snap?.data() ?? [:]
            let existingDevice = data["deviceId"] as? String
            if existingDevice == nil {
                // Nobody owns the session: claim it quietly and carry on.
                // This must NOT disturb the UI - see claimPrimarySession.
                claimPrimarySession(isExplicitTakeover: false) { finish(false) }
                return
            }

            if existingDevice == deviceSessionId {
                finish(false)
                return
            }

            dismissAllTopLevelSheets()
            showSessionConflictAlert = true
            finish(true)
        }
    }

    /// `isExplicitTakeover` separates the two very different reasons this
    /// runs. Tapping "Take Over Primary" is a deliberate seizure from another
    /// device, and dropping whatever was on screen to land on Home is the
    /// right response. Finding `deviceId` absent at boot or on resume is
    /// routine bookkeeping - nobody owned the session - and doing the same
    /// thing there tore down the pitcher/grid-key sheet mid-selection and
    /// bounced the coach back to Home, repeatedly, every time the app became
    /// active.
    private func claimPrimarySession(isExplicitTakeover: Bool = true, completion: (() -> Void)? = nil) {
        guard let ref = activeSessionDocRef else { completion?(); return }
        let payload: [String: Any] = [
            "deviceId": deviceSessionId,
            "claimedAt": FieldValue.serverTimestamp(),
            "mode": "primary"
        ]
        ref.setData(payload, merge: true) { err in
            if let err {
                debugLog("⚠️ activeSession claim failed:", err.localizedDescription)
                completion?()
                return
            }
            self.isDisplayOnlyMode = false
            self.displayOnlyLiveId = nil
            self.displayOnlyLiveIdStorage = ""
            if isExplicitTakeover {
                self.dismissAllTopLevelSheets()
                self.activeHomeArea = .home
            }
            completion?()
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
                        // Resume the boot flow the conflict interrupted. If
                        // the conflict was raised at launch, nothing after
                        // the session check has run yet - games, templates
                        // and the initial sheet all still owe their turn, and
                        // without this the app sits on an empty Home.
                        claimPrimarySession {
                            // claimPrimarySession already put us on Home.
                            continueBootAfterSessionCheck(forceHome: false)
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Sign Out", role: .destructive) {
                        showSessionConflictAlert = false
                        authManager.signOut()
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
            .alert("Display App Not Installed", isPresented: $ui.showDisplayAppMissingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Install and open Pitchmark Display to use this option.")
            }
        }
    }
    
    private func handleInitialAppear() {
        if isDemoMode {
            configureDemoMode()
            return
        }

        // If we aren't signed in yet, do NOT mark anything as presented.
        // We'll be called again when sign-in completes.
        guard authManager.isSignedIn else {
            debugLog("⏳ handleInitialAppear: not signed in yet — deferring boot flow")
            startupPhase = .ready
            return
        }

        startDisplaySessionListener()
        startListeningToJoinedLiveSessions()
        // Evaluated NOW, not in the completion: it consumes a one-shot
        // defaults flag, and asking after the round trip meant the answer
        // (and the resulting jump to Home) arrived late enough to interrupt
        // whatever the coach had already started doing.
        let forceHomeOnLaunch = shouldForceSettingsOnLaunch()
        // Everything below waits on the answer. Running it first is what put
        // the "Account In Use" blocker behind the boot sheets.
        ensurePrimarySessionOrPrompt { hasConflict in
            guard !hasConflict else { return }
            continueBootAfterSessionCheck(forceHome: forceHomeOnLaunch)
        }
    }

    /// The rest of `handleInitialAppear`, split out so it can run as the
    /// completion of the primary-session check rather than racing it.
    private func continueBootAfterSessionCheck(forceHome: Bool) {
        if forceHome {
            activeHomeArea = .home
        }

        if isDisplayOnlyMode, !displayOnlyLiveIdStorage.isEmpty {
            displayOnlyLiveId = displayOnlyLiveIdStorage
            startupPhase = .ready
            return
        }

        loadBufferedSharedPitcherEvents()
        loadBufferedSharedHitterEvents()

        // If we've already presented the initial sheets once, don't do it again.
        // (But we can still refresh loaders below if you want; keeping it tight here.)
        if hasPresentedInitialSettings {
            // Still ensure we have data if somehow empty
            if templates.isEmpty {
                authManager.loadTemplates { loaded in
                    self.templates = loaded
                    self.didLoadTemplates = true
                    if self.selectedTemplate == nil {
                        let restored = self.restorePersistedTemplateIfPossible(from: loaded)
                        if !restored {
                            self.selectedTemplate = self.visibleTemplates.first ?? loaded.first
                        }
                    }
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
        let currentUid = authManager.user?.uid
        // Never restore a prior user's game/session selection.
        if let restoredOwner = persistedOwnerId,
           let currentUid,
           restoredOwner != currentUid {
            defaults.removeObject(forKey: DefaultsKeys.activeGameId)
            defaults.removeObject(forKey: DefaultsKeys.activeGameOwnerUserId)
            defaults.removeObject(forKey: "activeLiveId")
            defaults.removeObject(forKey: "activeOpponentName")
            selectedGameId = nil
            activeGameOwnerUserId = nil
            activeLiveId = nil
            opponentName = nil
            activeHomeArea = .home
        }
        // ✅ Restore LIVE session if one was active
        var didRestoreLiveSession = false
        if let persistedLiveId = defaults.string(forKey: "activeLiveId"),
           !persistedLiveId.isEmpty {

            didRestoreLiveSession = true
            debugLog("🔁 Restoring live session:", persistedLiveId)

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

        } else if let gid = persistedGameId,
                  persistedOwnerId == nil || persistedOwnerId == currentUid {
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
            debugLog("✅ Loaded templates:", loadedTemplates.count)
            self.templates = loadedTemplates
            self.didLoadTemplates = true
            if self.selectedTemplate == nil {
                let restored = self.restorePersistedTemplateIfPossible(from: loadedTemplates)
                if !restored {
                    self.selectedTemplate = self.visibleTemplates.first ?? loadedTemplates.first
                }
            } else if let current = self.selectedTemplate,
                      self.hiddenTemplateIdSet.contains(current.id.uuidString) {
                self.selectedTemplate = self.visibleTemplates.first ?? loadedTemplates.first
            }
            self.applyPendingLiveTemplateIfPossible()
            if let gameId = self.selectedGameId {
                self.applyStoredSelections(for: gameId)
            }
            self.ensureAutoLiveSessionIfNeeded()
        }

        authManager.loadGames { loadedGames in
            // Fourth load site, same rule as the other three: a straight
            // assignment here drops a game created moments earlier whose
            // write hasn't come back yet. This one runs on every boot and
            // on every re-auth, so it is the one most likely to catch a
            // brand-new game mid-flight.
            self.games = mergePreservingUnsyncedGames(
                loaded: self.mergeLoadedGamesPreservingProgress(loadedGames),
                local: self.games
            )

            // Apply deferred restore (if needed)
            if let gid = self.pendingRestoreGameId,
               let game = loadedGames.first(where: { $0.id == gid }) {

                debugLog("🔁 Applying deferred restore for game:", gid)

                self.opponentName = game.opponent

                if let ids = game.batterIds, ids.count == game.jerseyNumbers.count {
                    self.jerseyCells = zip(ids, game.jerseyNumbers).map { (idStr, num) in
                        JerseyCell(id: UUID(uuidString: idStr) ?? UUID(), jerseyNumber: num)
                    }
                } else {
                    self.jerseyCells = game.jerseyNumbers.map { JerseyCell(jerseyNumber: $0) }
                }

                // Same reason as chooseGame: the cells are back, so their
                // roster links have to come back with them or the At Bat
                // scroll can't tell the two sides apart. Merging, not
                // seeding - this restore can land after the coach has
                // already linked a batter this launch.
                self.mergeHitterLinks(from: game)
                self.loadSideContext(for: game)

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
                if persistedGameId == nil {
                    self.presentInitialSheetIfNeeded()
                }
            }
        }

    }

    private func configureDemoMode() {
        guard !hasPresentedInitialSettings else { return }

        let template = demoTemplate
        let pitcher = demoPitcher
        let game = demoGame
        let batterId = UUID()

        templates = [template]
        pitchers = [pitcher]
        games = [game]
        selectedTemplate = template
        selectedPitches = Set(template.pitches)
        pitchCodeAssignments = template.codeAssignments
        selectedPitch = template.pitches.first ?? ""
        selectedPitcherId = pitcher.id
        selectedGameId = game.id
        opponentName = game.opponent
        activeGameOwnerUserId = Self.demoUserId
        ownerTemplateName = template.name
        isGame = true
        currentTrackingMode = .coach
        sessionManager.switchMode(to: .game)
        jerseyCells = [JerseyCell(id: batterId, jerseyNumber: "1")]
        selectedBatterId = batterId
        selectedBatterJersey = "1"
        startupPhase = .ready
        hasPresentedInitialSettings = true
    }

    private func resetStateForAuthenticatedUserChange(oldUserId: String?, newUserId: String?) {
        guard let oldUserId else { return }
        guard oldUserId != newUserId else { return }

        let defaults = UserDefaults.standard

        gameListener?.remove()
        gameListener = nil
        liveListener?.remove()
        liveListener = nil
        participantsListener?.remove()
        participantsListener = nil
        livePitchEventsListener?.remove()
        livePitchEventsListener = nil
        gamePitchEventsListener?.remove()
        gamePitchEventsListener = nil
        displayListener?.remove()
        displayListener = nil
        displayStateListener?.remove()
        displayStateListener = nil
        displaySessionListener?.remove()
        displaySessionListener = nil
        joinedLiveSessionsListener?.remove()
        joinedLiveSessionsListener = nil
        joinedLiveSessions = []
        stopHeartbeat()

        activeLiveId = nil
        selectedGameId = nil
        opponentName = nil
        activeGameOwnerUserId = nil
        showParticipantOverlay = false

        defaults.removeObject(forKey: DefaultsKeys.activeGameId)
        defaults.removeObject(forKey: DefaultsKeys.activeGameOwnerUserId)
        defaults.removeObject(forKey: "activeLiveId")
        defaults.removeObject(forKey: "activeOpponentName")
        defaults.set("settings", forKey: DefaultsKeys.lastView)

        hasPresentedInitialSettings = false

        if newUserId != nil {
            isGame = false
            sessionManager.switchMode(to: .game)
            activeHomeArea = .home
        }
    }

    @ViewBuilder private var gameSheetView: some View {
        GameSelectionSheet(
            onCreate: { name, date, trackingMode, ourTeamId, opponentTeamId, completion in
                if isDemoMode {
                    requireSignInForDemo("Sign in to create your own games.")
                    return
                }
                var newGame = Game(
                    id: nil,
                    opponent: name,
                    date: date,
                    jerseyNumbers: jerseyCells.map { $0.jerseyNumber },
                    batterIds: jerseyCells.map { $0.id.uuidString },
                    trackingMode: trackingMode
                )
                newGame.teamId = ourTeamId
                newGame.awayTeamId = opponentTeamId
                // Swap the placeholder for a real, openable row as soon as
                // the id exists; only report back again if the backend
                // actually rejects the write.
                authManager.saveGame(
                    newGame,
                    onLocalWrite: { stamped in completion(.success(stamped)) }
                ) { result in
                    if case .failure = result {
                        DispatchQueue.main.async { completion(result) }
                    }
                }
            },
            onChoose: { gameId in
                let ownerUid = isDemoMode ? Self.demoUserId : (authManager.user?.uid ?? "")

                // Deferred to showGameSheet's onDismiss - see
                // pendingGameChoiceGameId's declaration for why.
                pendingGameChoiceGameId = gameId
                pendingGameChoiceOwnerUid = ownerUid
                showGameSheet = false
            },

            onCancel: {
                showGameSheet = false
            },
            codeShareInitialTab: $codeShareInitialTab,
            showCodeShareSheet: $ui.showCodeShareSheet,
            shareCode: $ui.shareCode,
            codeShareSheetID: $codeShareSheetID,
            showCodeShareModePicker: $ui.showCodeShareModePicker,
            isDemoMode: isDemoMode,
            onRequireSignIn: {
                requireSignInForDemo("Sign in to create and manage your own games.")
            },
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

                TextField("Paste invite link", text: $ui.inviteJoinText)
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

            Button("Scan QR Code") {
                openCameraForJoin()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder private var pitchResultSheetView: some View {
        let selectedJersey = jerseyCells.first(where: { $0.id == selectedBatterId })?.jerseyNumber
        let selectedBatterKey = atBatCountKey(batterId: selectedBatterId?.uuidString, jersey: selectedJersey)
        PitchResultSheetView(
            isPresented: $ui.showConfirmSheet,
            isStrikeSwinging: $ui.isStrikeSwinging,
            isStrikeLooking: $ui.isStrikeLooking,
            isWildPitch: $ui.isWildPitch,
            isPassedBall: $ui.isPassedBall,
            isBall: $ui.isBall,
            selectedOutcome: $ui.selectedOutcome,
            selectedDescriptor: $ui.selectedDescriptor,
            isError: $ui.isError,
            isDemoMode: isDemoMode,
            pendingResultLabel: pendingResultLabel,
            pitchCall: calledPitch,
            catcherEstimate: catcherEstimate,
            batterSide: batterSide,
            selectedTemplateId: selectedTemplate?.id.uuidString,
            currentMode: sessionManager.currentMode,
            selectedGameId: selectedGameId,
            selectedOpponentJersey: selectedJersey,
            selectedOpponentBatterId: selectedBatterId?.uuidString,
            allPitchEvents: isGame ? gamePitchEvents : pitchEvents,
            suggestedCountSeed: selectedBatterKey.flatMap { atBatCountCacheByBatter[$0] },
            currentCountSeed: (balls: balls, strikes: strikes),
            onCountChanged: { newBalls, newStrikes in
                syncCountFromComposer(balls: newBalls, strikes: newStrikes)
            },
            lineupBatters: jerseyCells,
            selectedPitcherId: effectivePitcherIdForSave,
            saveAction: { event in
                persistPitchEvent(event)
            },
            template: selectedTemplate,
            pitcherName: pitchers.first(where: { $0.id == selectedPitcherId })?.name,
            onMissingLocation: {
                calledPitchComposerDetent = .fraction(0.28)
            }
        )
    }

    @ViewBuilder private var codeAssignmentSheetView: some View {
        CodeAssignmentSettingsView(
            selectedPitch: $ui.selectedPitch,
            selectedLocation: $ui.selectedLocation,
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
            joinedLiveSessions: $joinedLiveSessions,
            pitchers: $pitchers,
            allPitches: allPitches,
            selectedTemplate: $selectedTemplate,
            codeShareInitialTab: $codeShareInitialTab,
            showCodeShareSheet: $ui.showCodeShareSheet,
            shareCode: $ui.shareCode,
            codeShareSheetID: $codeShareSheetID,
            showCodeShareModePicker: $ui.showCodeShareModePicker,
            onSwitchToArea: { selectHomeArea($0) }
        )
        .environmentObject(authManager)
        .environmentObject(subscriptionManager)
        .dynamicTypeSize(.medium)
    }

    /// Home/Games/Moments/Family are now TabView siblings (see `body`'s
    /// final `TabView(selection: $activeHomeArea)`), so switching areas is
    /// just a selection change - no dismiss-then-reopen choreography needed.
    private func selectHomeArea(_ area: HomeArea) {
        activeHomeArea = area
    }

    @ViewBuilder private var gameStatsSheetView: some View {
        let availablePitchers = pitchersForCurrentGameStats
        let initialPitcher = selectedPitcherForStats.flatMap { selected in
            availablePitchers.first(where: { $0.id == selected.id })
        } ?? availablePitchers.first ?? selectedPitcherForStats

        if let pitcher = initialPitcher,
           let game = currentGame,
           let gameId = game.id {
            PitcherStatsSheetView(
                pitcher: pitcher,
                availablePitchers: availablePitchers,
                games: [game],
                lockToGameId: gameId,
                liveId: activeLiveId,
                ownerUserId: effectiveGameOwnerUserId
            )
            .environmentObject(authManager)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading stats…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .onAppear {
                // Participants don't own the live game, so authManager.loadGames()
                // (scoped to the signed-in user's own games) never contains it —
                // refreshGamesList() would overwrite games[] and drop it, clearing
                // selectedGameId/activeGameOwnerUserId and stranding this spinner.
                // The live game snapshot listener repopulates games[] on its own.
                if isOwnerForActiveGame {
                    refreshGamesList()
                }
                authManager.loadPitchers { loaded in
                    pitchers = loaded
                    if selectedPitcherId == nil, let first = loaded.first {
                        applySelectedPitcher(first)
                    }
                    if let gid = selectedGameId {
                        applyStoredSelections(for: gid)
                    }
                }
            }
        }
    }

    private var gameSummarySourceEvents: [PitchEvent] {
        guard let gameId = selectedGameId else { return [] }
        return gamePitchEvents.filter { event in
            guard let eventGameId = event.gameId else { return false }
            return eventGameId == gameId
        }
        .sorted { $0.timestamp > $1.timestamp }
    }

    private struct GameSummaryPitcherOption: Identifiable {
        let id: String
        let name: String
    }

    private var gameSummaryPitcherOptions: [GameSummaryPitcherOption] {
        let pitcherIds = Set(
            gameSummarySourceEvents.compactMap { event -> String? in
                guard let pitcherId = event.pitcherId?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !pitcherId.isEmpty else { return nil }
                return pitcherId
            }
        )

        return pitcherIds.compactMap { pitcherId in
            guard let pitcher = pitchers.first(where: { $0.id == pitcherId }) else { return nil }
            return GameSummaryPitcherOption(id: pitcherId, name: pitcher.name)
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var gameSummaryPitcherId: String? {
        guard selectedGameSummaryPitcherSelection != Self.allPitchersSummarySelection else { return nil }
        return selectedGameSummaryPitcherSelection
    }

    private var gameSummaryPitcherName: String {
        guard let pitcherId = gameSummaryPitcherId else { return "All Pitchers" }
        return gameSummaryPitcherOptions.first(where: { $0.id == pitcherId })?.name
            ?? selectedPitcherForStats?.name
            ?? "Pitcher"
    }

    private var gameSummaryEvents: [PitchEvent] {
        let source = gameSummarySourceEvents

        guard let pitcherId = gameSummaryPitcherId, !pitcherId.isEmpty else {
            return source
        }

        return source
            .filter { event in
                guard let eventPitcherId = event.pitcherId, !eventPitcherId.isEmpty else { return false }
                return eventPitcherId == pitcherId
            }
    }

    private var summaryStats: PitchStatsSnapshot {
        PitchStatsCalculator.snapshot(for: gameSummaryEvents)
    }

    private var summaryTotalPitches: Int { summaryStats.totalPitches }
    private var summaryStrikePitches: Int { summaryStats.strikePitches }
    private var summaryBallPitches: Int { summaryStats.ballPitches }
    private var summaryHitSpotPitches: Int { summaryStats.hitSpotPitches }
    private var summaryLocationAnalyticsEligibleCount: Int { summaryStats.locationAnalyticsEligibleCount }
    private var summaryFirstPitchStrike: (made: Int, total: Int) { summaryStats.firstPitchStrike }
    private var gameSummaryHasLocationAnalytics: Bool { summaryStats.hasLocationAnalytics }
    private var summaryStrikeLookingCount: Int { summaryStats.strikeLookingCount }
    private var summaryStrikeSwingingCount: Int { summaryStats.strikeSwingingCount }
    private var foulCount: Int { summaryStats.foulCount }
    private var summaryWildPitchCount: Int { summaryStats.wildPitchCount }
    private var summaryPassedBallCount: Int { summaryStats.passedBallCount }
    private var summaryWalkCount: Int {
        if gameSummaryPitcherId == nil {
            return max(0, walks)
        }
        return summaryStats.walkCount
    }
    private var summaryHitCount: Int {
        if gameSummaryPitcherId == nil {
            return max(0, hits)
        }
        return summaryStats.hitCount
    }
    private var summaryPitchBreakdown: [(pitch: String, count: Int)] {
        summaryStats.pitchBreakdown.map { (pitch: $0.name, count: $0.count) }
    }

    private var summaryOutcomeBreakdown: [(name: String, count: Int)] {
        summaryStats.outcomeBreakdown
    }

    private var summaryHeatmapsByPitch: [(pitch: String, events: [PitchEvent])] {
        Dictionary(grouping: gameSummaryEvents.filter(\.supportsLocationAnalytics), by: { $0.pitch.isEmpty ? "-" : $0.pitch })
            .map { key, value in
                (pitch: key, events: value.sorted { $0.timestamp < $1.timestamp })
            }
            .sorted { lhs, rhs in
                if lhs.events.count == rhs.events.count { return lhs.pitch < rhs.pitch }
                return lhs.events.count > rhs.events.count
            }
    }

    private func summaryPercent(_ part: Int, total: Int) -> String {
        guard total > 0 else { return "0%" }
        let value = (Double(part) / Double(total)) * 100.0
        return String(format: "%.0f%%", value.rounded())
    }

    private func initializeGameSummaryPitcherSelection() {
        let preferredPitcherId = selectedPitcherForStats?.id ?? selectedPitcherId
        if let preferredPitcherId,
           gameSummaryPitcherOptions.contains(where: { $0.id == preferredPitcherId }) {
            selectedGameSummaryPitcherSelection = preferredPitcherId
        } else {
            selectedGameSummaryPitcherSelection = Self.allPitchersSummarySelection
        }
    }

    private var summaryShareText: String {
        let pitcher = gameSummaryPitcherName
        let opponent = currentGame?.opponent ?? "Unknown Opponent"
        let gameDate = currentGame?.date.formatted(date: .abbreviated, time: .omitted) ?? "-"

        let pitchBreakdownText: String = {
            if summaryPitchBreakdown.isEmpty { return "None" }
            return summaryPitchBreakdown.map { "\($0.pitch): \($0.count)" }.joined(separator: ", ")
        }()

        let outcomeText: String = {
            if summaryOutcomeBreakdown.isEmpty { return "None" }
            return summaryOutcomeBreakdown.map { "\($0.name): \($0.count)" }.joined(separator: ", ")
        }()
        let hitSpotLine = gameSummaryHasLocationAnalytics
            ? "- Hit Spot: \(summaryHitSpotPitches) of \(summaryLocationAnalyticsEligibleCount) (\(summaryPercent(summaryHitSpotPitches, total: summaryLocationAnalyticsEligibleCount)))"
            : "- Hit Spot: Hidden for Scout Mode events"
        let firstPitchStrikeLine = "- 1st Pitch Strike: \(summaryPercent(summaryFirstPitchStrike.made, total: summaryFirstPitchStrike.total)) (\(summaryFirstPitchStrike.made)/\(summaryFirstPitchStrike.total))"
        let hitSpotDefinition = gameSummaryHasLocationAnalytics
            ? "- Hit Spot % = Location matches / Coach-mode pitches"
            : "- Location-based metrics hidden for Scout Mode events."
        let foulPercentLine = "- Foul % = Foul pitches / Total pitches"

        return """
        PitchMark Game Summary
        Pitcher: \(pitcher)
        Opponent: \(opponent)
        Date: \(gameDate)

        Totals
        - Pitches: \(summaryTotalPitches)
        - Strikes: \(summaryStrikePitches) of \(summaryTotalPitches) (\(summaryPercent(summaryStrikePitches, total: summaryTotalPitches)))
        - Balls: \(summaryBallPitches) of \(summaryTotalPitches) (\(summaryPercent(summaryBallPitches, total: summaryTotalPitches)))
        \(firstPitchStrikeLine)
        \(hitSpotLine)
        - Foul %: \(summaryPercent(foulCount, total: summaryTotalPitches)) (\(foulCount)/\(summaryTotalPitches))

        Events
        - Strike Looking: \(summaryStrikeLookingCount)
        - Strike Swinging: \(summaryStrikeSwingingCount)
        - Foul: \(foulCount)
        - Walks: \(summaryWalkCount)
        - Hits: \(summaryHitCount)
        - Wild Pitches: \(summaryWildPitchCount)
        - Passed Balls: \(summaryPassedBallCount)

        Metric Definitions
        - Strike % = Strikes / Total Pitches
        - Ball % = Balls / Total Pitches
        - 1st Pitch Strike % = Qualified first-pitch strikes / New batter appearances
        \(hitSpotDefinition)
        \(foulPercentLine)

        Pitch Breakdown
        \(pitchBreakdownText)

        Outcome Breakdown
        \(outcomeText)
        """
    }

    @ViewBuilder
    private var gameSummaryContentWithoutHeatmaps: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(gameSummaryPitcherName)
                    .font(.title3.weight(.semibold))
                Text(currentGame?.opponent ?? "Opponent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let date = currentGame?.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ScrollableSelectionMenuButton(
                    title: "Pitcher",
                    items: gameSummaryPitcherOptions,
                    topActions: [
                        SelectionSheetAction(
                            title: "All Pitchers",
                            systemImage: selectedGameSummaryPitcherSelection == Self.allPitchersSummarySelection ? "checkmark" : nil
                        ) {
                            selectedGameSummaryPitcherSelection = Self.allPitchersSummarySelection
                        }
                    ],
                    itemTitle: { $0.name },
                    isSelected: { $0.id == selectedGameSummaryPitcherSelection },
                    onSelect: { option in
                        selectedGameSummaryPitcherSelection = option.id
                    }
                ) {
                    Text(selectedGameSummaryPitcherSelection == Self.allPitchersSummarySelection ? "All Pitchers" : gameSummaryPitcherName)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
            }

            VStack(spacing: 10) {
                summaryMetricRow(title: "Total Pitches", value: "\(summaryTotalPitches)")
                summaryMetricRow(
                    title: "Strike %",
                    value: "\(summaryPercent(summaryStrikePitches, total: summaryTotalPitches)) (\(summaryStrikePitches)/\(summaryTotalPitches))"
                )
                summaryMetricRow(
                    title: "Ball %",
                    value: "\(summaryPercent(summaryBallPitches, total: summaryTotalPitches)) (\(summaryBallPitches)/\(summaryTotalPitches))"
                )
                summaryMetricRow(
                    title: "1st Pitch Strike",
                    value: "\(summaryPercent(summaryFirstPitchStrike.made, total: summaryFirstPitchStrike.total)) (\(summaryFirstPitchStrike.made)/\(summaryFirstPitchStrike.total))"
                )
                summaryMetricRow(
                    title: "Hit Spot %",
                    value: gameSummaryHasLocationAnalytics
                        ? "\(summaryPercent(summaryHitSpotPitches, total: summaryLocationAnalyticsEligibleCount)) (\(summaryHitSpotPitches)/\(summaryLocationAnalyticsEligibleCount))"
                        : "Coach data needed"
                )
                .opacity(gameSummaryHasLocationAnalytics ? 1 : 0.45)
                summaryMetricRow(
                    title: "Foul %",
                    value: "\(summaryPercent(foulCount, total: summaryTotalPitches)) (\(foulCount)/\(summaryTotalPitches))"
                )
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Metric Definitions")
                    .font(.subheadline.weight(.semibold))
                Text("Strike % = Strikes / Total Pitches")
                Text("Ball % = Balls / Total Pitches")
                Text("1st Pitch Strike % = Qualified first-pitch strikes / New batter appearances")
                if gameSummaryHasLocationAnalytics {
                    Text("Hit Spot % = Location matches / Coach-mode pitches")
                } else {
                    Text("Location-based metrics hidden for Scout Mode events.")
                }
                Text("Foul % = Foul pitches / Total pitches")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Events")
                    .font(.headline)
                summaryMetricRow(title: "Strike Looking", value: "\(summaryStrikeLookingCount)")
                summaryMetricRow(title: "Strike Swinging", value: "\(summaryStrikeSwingingCount)")
                summaryMetricRow(title: "Foul", value: "\(foulCount)")
                summaryMetricRow(title: "Walks", value: "\(summaryWalkCount)")
                summaryMetricRow(title: "Hits", value: "\(summaryHitCount)")
                summaryMetricRow(title: "Wild Pitches", value: "\(summaryWildPitchCount)")
                summaryMetricRow(title: "Passed Balls", value: "\(summaryPassedBallCount)")
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Pitch Breakdown")
                    .font(.headline)
                if summaryPitchBreakdown.isEmpty {
                    Text("No pitches recorded.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(summaryPitchBreakdown.enumerated()), id: \.offset) { _, item in
                        summaryMetricRow(title: item.pitch, value: "\(item.count)")
                    }
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Outcome Breakdown")
                    .font(.headline)
                if summaryOutcomeBreakdown.isEmpty {
                    Text("No outcomes recorded.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(summaryOutcomeBreakdown.enumerated()), id: \.offset) { _, item in
                        summaryMetricRow(title: item.name, value: "\(item.count)")
                    }
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private func printableGameSummaryHeatmapPage(for item: (pitch: String, events: [PitchEvent]), pageHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(item.pitch) (\(item.events.count))")
                .font(.title3.weight(.semibold))
            HStack {
                Spacer()
                StrikeZoneHeatmapView(
                    events: item.events,
                    showLegend: false
                )
                .frame(width: 380, height: 312)
                Spacer()
            }
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes:")
                    .font(.headline)
                Rectangle()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(height: 1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: pageHeight, alignment: .top)
    }

    @MainActor
    private func renderedGameSummaryPrintableImage<Content: View>(for content: Content, width: CGFloat) -> UIImage? {
        let printableContent = content
            .padding()
            .frame(width: width)
            .background(Color.white)
        let imageRenderer = ImageRenderer(content: printableContent)
        imageRenderer.scale = 2
        return imageRenderer.uiImage
    }

    @ViewBuilder
    private var gameSummaryContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(gameSummaryPitcherName)
                    .font(.title3.weight(.semibold))
                Text(currentGame?.opponent ?? "Opponent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let date = currentGame?.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ScrollableSelectionMenuButton(
                    title: "Pitcher",
                    items: gameSummaryPitcherOptions,
                    topActions: [
                        SelectionSheetAction(
                            title: "All Pitchers",
                            systemImage: selectedGameSummaryPitcherSelection == Self.allPitchersSummarySelection ? "checkmark" : nil
                        ) {
                            selectedGameSummaryPitcherSelection = Self.allPitchersSummarySelection
                        }
                    ],
                    itemTitle: { $0.name },
                    isSelected: { $0.id == selectedGameSummaryPitcherSelection },
                    onSelect: { option in
                        selectedGameSummaryPitcherSelection = option.id
                    }
                ) {
                    Text(selectedGameSummaryPitcherSelection == Self.allPitchersSummarySelection ? "All Pitchers" : gameSummaryPitcherName)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
            }

            VStack(spacing: 10) {
                summaryMetricRow(title: "Total Pitches", value: "\(summaryTotalPitches)")
                summaryMetricRow(
                    title: "Strike %",
                    value: "\(summaryPercent(summaryStrikePitches, total: summaryTotalPitches)) (\(summaryStrikePitches)/\(summaryTotalPitches))"
                )
                summaryMetricRow(
                    title: "Ball %",
                    value: "\(summaryPercent(summaryBallPitches, total: summaryTotalPitches)) (\(summaryBallPitches)/\(summaryTotalPitches))"
                )
                summaryMetricRow(
                    title: "1st Pitch Strike",
                    value: "\(summaryPercent(summaryFirstPitchStrike.made, total: summaryFirstPitchStrike.total)) (\(summaryFirstPitchStrike.made)/\(summaryFirstPitchStrike.total))"
                )
                summaryMetricRow(
                    title: "Hit Spot %",
                    value: gameSummaryHasLocationAnalytics
                        ? "\(summaryPercent(summaryHitSpotPitches, total: summaryLocationAnalyticsEligibleCount)) (\(summaryHitSpotPitches)/\(summaryLocationAnalyticsEligibleCount))"
                        : "Coach data needed"
                )
                .opacity(gameSummaryHasLocationAnalytics ? 1 : 0.45)
                summaryMetricRow(
                    title: "Foul %",
                    value: "\(summaryPercent(foulCount, total: summaryTotalPitches)) (\(foulCount)/\(summaryTotalPitches))"
                )
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Metric Definitions")
                    .font(.subheadline.weight(.semibold))
                Text("Strike % = Strikes / Total Pitches")
                Text("Ball % = Balls / Total Pitches")
                Text("1st Pitch Strike % = Qualified first-pitch strikes / New batter appearances")
                if gameSummaryHasLocationAnalytics {
                    Text("Hit Spot % = Location matches / Coach-mode pitches")
                } else {
                    Text("Location-based metrics hidden for Scout Mode events.")
                }
                Text("Foul % = Foul pitches / Total pitches")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Events")
                    .font(.headline)
                summaryMetricRow(title: "Strike Looking", value: "\(summaryStrikeLookingCount)")
                summaryMetricRow(title: "Strike Swinging", value: "\(summaryStrikeSwingingCount)")
                summaryMetricRow(title: "Foul", value: "\(foulCount)")
                summaryMetricRow(title: "Walks", value: "\(summaryWalkCount)")
                summaryMetricRow(title: "Hits", value: "\(summaryHitCount)")
                summaryMetricRow(title: "Wild Pitches", value: "\(summaryWildPitchCount)")
                summaryMetricRow(title: "Passed Balls", value: "\(summaryPassedBallCount)")
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Pitch Breakdown")
                    .font(.headline)
                if summaryPitchBreakdown.isEmpty {
                    Text("No pitches recorded.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(summaryPitchBreakdown.enumerated()), id: \.offset) { _, item in
                        summaryMetricRow(title: item.pitch, value: "\(item.count)")
                    }
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Outcome Breakdown")
                    .font(.headline)
                if summaryOutcomeBreakdown.isEmpty {
                    Text("No outcomes recorded.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(summaryOutcomeBreakdown.enumerated()), id: \.offset) { _, item in
                        summaryMetricRow(title: item.name, value: "\(item.count)")
                    }
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text("Heat Maps By Pitch")
                    .font(.headline)
                if !gameSummaryHasLocationAnalytics {
                    Text("Coach data needed for heat maps.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if summaryHeatmapsByPitch.isEmpty {
                    Text("No pitches recorded.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summaryHeatmapsByPitch, id: \.pitch) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                Text("\(item.pitch) (\(item.events.count))")
                                    .font(.subheadline.weight(.semibold))
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.35))
                                    .frame(height: 1)
                            }
                            .padding(.horizontal, 4)
                            .padding(.bottom, 16)

                            StrikeZoneHeatmapView(
                                events: item.events,
                                showLegend: false
                            )
                            .padding(.bottom, 28)
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @MainActor
    private func printGameSummary() {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let contentRect = pageRect.insetBy(dx: 24, dy: 36)
        var printableImages: [UIImage] = []
        if let summaryImage = renderedGameSummaryPrintableImage(for: gameSummaryContentWithoutHeatmaps, width: contentRect.width) {
            printableImages.append(summaryImage)
        }
        for item in summaryHeatmapsByPitch {
            if let heatmapImage = renderedGameSummaryPrintableImage(for: printableGameSummaryHeatmapPage(for: item, pageHeight: contentRect.height), width: contentRect.width) {
                printableImages.append(heatmapImage)
            }
        }
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let pdfData = pdfRenderer.pdfData { context in
            func drawPaginatedImage(_ image: UIImage) {
                guard let cgImage = image.cgImage else { return }
                let scale = image.scale
                let totalHeightPoints = image.size.height
                var offsetYPoints: CGFloat = 0

                while offsetYPoints < totalHeightPoints {
                    context.beginPage()
                    let remainingHeight = totalHeightPoints - offsetYPoints
                    let sliceHeightPoints = min(contentRect.height, remainingHeight)
                    let cropRect = CGRect(
                        x: 0,
                        y: offsetYPoints * scale,
                        width: CGFloat(cgImage.width),
                        height: sliceHeightPoints * scale
                    ).integral

                    if let cropped = cgImage.cropping(to: cropRect) {
                        let sliceImage = UIImage(cgImage: cropped, scale: scale, orientation: .up)
                        sliceImage.draw(
                            in: CGRect(
                                x: contentRect.minX,
                                y: contentRect.minY,
                                width: contentRect.width,
                                height: sliceHeightPoints
                            )
                        )
                    }

                    offsetYPoints += sliceHeightPoints
                }
            }

            for image in printableImages {
                drawPaginatedImage(image)
            }
        }

        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.jobName = "PitchMark Game Summary"
        info.outputType = .general
        controller.printInfo = info
        controller.printingItem = pdfData
        controller.present(animated: true, completionHandler: nil)
    }

    @ViewBuilder private var gameSummarySheetView: some View {
        NavigationStack {
            ScrollView {
                gameSummaryContent
                    .padding()
            }
            .navigationTitle("Game Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        printGameSummary()
                    } label: {
                        Label("Print", systemImage: "printer")
                    }
                    .disabled(summaryTotalPitches == 0)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showGameSummaryShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(summaryTotalPitches == 0)
                }
            }
            .sheet(isPresented: $ui.showGameSummaryShareSheet) {
                ShareSheet(items: [summaryShareText])
                    .fixedAppDynamicType()
            }
            .onAppear {
                initializeGameSummaryPitcherSelection()
            }
        }
    }

    @ViewBuilder
    private func summaryMetricRow(title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func pauseLiveSessionForBackground() {
        guard activeLiveId != nil else { return }
        debugLog("🔌 Scene inactive/background → pausing live presence (no disconnect)")
        stopHeartbeat()
        liveListener?.remove()
        liveListener = nil
        livePitchEventsListener?.remove()
        livePitchEventsListener = nil
        participantsListener?.remove()
        participantsListener = nil
        uiConnected = false
        flushBufferedSharedPitcherEvents(reason: "background")
        flushBufferedSharedHitterEvents(reason: "background")
    }

    private func resumeLiveSessionIfNeeded() {
        // Participant: always verify liveId against owner's active session code on resume.
        // This fixes stale liveId cases that can delay event propagation after wake.
        if isGame && !isOwnerForActiveGame {
            recoverLiveSessionFromOwnerGameIfNeeded()
        }
        if activeLiveId == nil || activeLiveId?.isEmpty == true {
            if let persistedLiveId = UserDefaults.standard.string(forKey: "activeLiveId"), !persistedLiveId.isEmpty {
                activeLiveId = persistedLiveId
            } else {
                recoverLiveSessionFromOwnerGameIfNeeded()
                return
            }
        }
        guard let liveId = activeLiveId, !liveId.isEmpty else { return }
        debugLog("🔌 Scene active → resuming live presence")
        startListeningToActiveGame()
        startListeningToLiveGame(liveId: liveId)
        startListeningToLivePitchEvents(liveId: liveId)
        startListeningToLiveParticipants(liveId: liveId)
        startLivePresenceHeartbeat(liveId: liveId)
        ensureLivePresence(liveId: liveId)
    }

    private func recoverLiveSessionFromOwnerGameIfNeeded() {
        guard isGame else { return }
        guard !isOwnerForActiveGame else { return }

        let defaults = UserDefaults.standard
        let ownerUid = activeGameOwnerUserId ?? defaults.string(forKey: DefaultsKeys.activeGameOwnerUserId)
        let gameId = selectedGameId ?? defaults.string(forKey: DefaultsKeys.activeGameId)
        guard let ownerUid, !ownerUid.isEmpty, let gameId, !gameId.isEmpty else { return }

        Firestore.firestore()
            .collection("users").document(ownerUid)
            .collection("games").document(gameId)
            .getDocument { snap, err in
                if let err {
                    debugLog("❌ recover live: owner game lookup failed:", err.localizedDescription)
                    return
                }
                guard let data = snap?.data(),
                      let code = data["activeSessionCode"] as? String,
                      !code.isEmpty else {
                    return
                }

                Firestore.firestore().collection("joinCodes").document(code).getDocument { codeSnap, codeErr in
                    if let codeErr {
                        debugLog("❌ recover live: joinCode lookup failed:", codeErr.localizedDescription)
                        return
                    }
                    guard let codeData = codeSnap?.data(),
                          let liveId = codeData["liveId"] as? String,
                          !liveId.isEmpty else {
                        return
                    }

                    DispatchQueue.main.async {
                        self.activeGameOwnerUserId = ownerUid
                        self.selectedGameId = gameId

                        let needsSwitch = self.activeLiveId != liveId
                        if needsSwitch {
                            debugLog("🔁 recover live: switching to owner liveId=\(liveId)")
                            self.activeLiveId = liveId
                            defaults.set(liveId, forKey: "activeLiveId")
                            self.updateActiveSessionLiveId(liveId)
                            self.startListeningToLiveGame(liveId: liveId)
                        } else {
                            debugLog("🔁 recover live: liveId already current, refreshing listeners")
                        }

                        self.startListeningToLivePitchEvents(liveId: liveId)
                        self.startListeningToLiveParticipants(liveId: liveId)
                        self.startLivePresenceHeartbeat(liveId: liveId)
                        self.ensureLivePresence(liveId: liveId)
                    }
                }
            }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            clearForceSettingsFlagOnResume()
            // Runs SYNCHRONOUSLY, on purpose. It is a local clock check with
            // nothing to do with session ownership, and it forces
            // activeHomeArea = .home. Behind the session read it landed a
            // round trip late - i.e. after the coach had already tapped into
            // a game - and threw them back to Home. Only the live-session
            // resume below genuinely has to wait for the ownership answer.
            evaluateIdleAndMaybeShowSettings()
            ensurePrimarySessionOrPrompt { hasConflict in
                guard !hasConflict else { return }
                resumeLiveSessionIfNeeded()
            }
        case .inactive, .background:
            markBackgroundTimestamp()
            flushBufferedSharedPitcherEvents(reason: "background")
            flushBufferedSharedHitterEvents(reason: "background")
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
            activeHomeArea = .home
        }
    }

    var body: some View {
        // Forces @Published currentMode's Combine/KeyPath generic metadata
        // to resolve HERE, at the shallowest point in body's own call
        // stack, instead of lazily the first time something deep inside
        // strikeZoneArea's nested chain (confirmSheetBinding, 60+
        // AttributeGraph frames in) reads it - same root cause as
        // undoButtonOverlay's crash (lazy generic metadata instantiation
        // crashing when it first happens deep in a recursive AttributeGraph
        // update), different site: that one was a View's own opaque return
        // type, this one is Published's internal KeyPath machinery, which
        // can't be erased away since it's SDK-synthesized. Metadata caches
        // are process-global once resolved, so paying this cost once here -
        // where the stack is shallow - means the deep call site never has
        // to pay it at all.
        _ = sessionManager.currentMode
        // The strike-zone overlays used to be pre-warmed here too, for the
        // same crash class. They are top-level structs now (see the comment
        // above ZoneOpponentLabel), so they carry none of this view's
        // context in their metadata and need no pre-warm at all.
        let resolvedDisplayLiveId = displayOnlyLiveId ?? (displayOnlyLiveIdStorage.isEmpty ? nil : displayOnlyLiveIdStorage)
        // Same discipline as confirmSheetBinding: locals captured before the
        // closures exist, so neither one implicitly captures `self` and
        // copies the whole view into `body`'s own stack frame.
        let displayOnlyFlag = $isDisplayOnlyMode
        let deviceIsPad = isPad
        let exitDisplayOnly: () -> Void = { exitDisplayOnlyMode() }
        let displayCoverBinding = Binding<Bool>(
            get: { displayOnlyFlag.wrappedValue && !deviceIsPad },
            set: { newValue in if !newValue { exitDisplayOnly() } }
        )
        let displayCoverView: AnyView = {
            if let liveId = resolvedDisplayLiveId {
                return AnyView(displayOnlyBody(liveId: liveId))
            }
            return AnyView(displayOnlyHomeView)
        }()

        let synced = baseBody.withGameSync(
            start: {
                guard !isDemoMode else { return }
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
                if !isDemoMode {
                    handleScenePhaseChange(newValue)
                }
            }
            .onChange(of: pendingResultLabel) { _, newValue in
                handlePendingResultChange(newValue)
            }
            .onChange(of: catcherRealCall?.location) { _, newValue in
                guard newValue != nil else { return }
                catcherEstimateDismissed = false
                catcherEstimate = nil
                catcherEstimateDraftPitch = "Catcher"
                catcherEstimateDraftLocation = nil
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
                syncSelectedPitchWithVisibleOptions()
            }
            .onChange(of: selectedPitch) { _, _ in
                refreshCalledPitchForSelectedPitch()
            }
            .onChange(of: selectedPitcherId) { _, _ in
                if isGame {
                    syncLivePitcherSelectionIfOwner()
                }
            }
            .onChange(of: selectedGameId) { _, newValue in
                guard let gid = newValue else { return }
                gamePitchEvents.removeAll()
                jerseyDetailEvent = nil
                jerseyDetailPayload = nil
                pendingJerseyDetailCell = nil
                showJerseyDetailSheet = false
                didAutoRetryJerseyDetail = false
                applyStoredSelections(for: gid)
                startListeningToGamePitchEvents()
            }
            .onChange(of: currentTrackingMode) { _, newValue in
                if newValue == .scout {
                    resetCallAndResultUIState()
                } else {
                    resetScoutComposer()
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
                    syncSelectedPitchWithVisibleOptions()
                    colorRefreshToken = UUID()
                }
            }
            // `.task(id:)` rather than `.onChange(of:)` on purpose: this
            // runs on appear as well as on change. The key that clears this
            // state is created in the Home tab, and the Games tab doesn't
            // re-evaluate while Home is selected - an onChange here fired
            // unreliably across that gap, leaving the tracker blurred after
            // the first key was made. A task keyed on the count re-runs
            // whenever the tab comes back with a different count than the
            // one it last ran for.
            .task(id: templates.count) {
                adoptFirstTemplateIfNoneSelected()
            }
            .onChange(of: overlayTab) { _, newValue in
                if newValue == .progress {
                    progressRefreshToken = UUID()
                }
            }
            .onChange(of: isDisplayOnlyMode) { _, newValue in
                AppDelegate.setOrientationLock(newValue ? .landscapeRight : .portrait)
                forceOrientation(newValue ? .landscapeRight : .portrait)
                if isPad && newValue {
                    NotificationCenter.default.post(name: .displayOnlyPresentRequested, object: nil)
                }
            }
            .eraseToAnyView()

        let v2 = v1
            .sheet(isPresented: $ui.showGameSheet, onDismiss: {
                refreshGamesList()

                if let gameId = pendingGameChoiceGameId, let ownerUid = pendingGameChoiceOwnerUid {
                    pendingGameChoiceGameId = nil
                    pendingGameChoiceOwnerUid = nil
                    requestGameConfirmation(gameId: gameId, ownerUid: ownerUid)
                    return
                }

                guard !isJoiningSession else { return }

                if sessionManager.currentMode == .game && selectedGameId == nil {
                    sessionManager.switchMode(to: .game)
                    isGame = false
                }
            }) {
                gameSheetView
                    .fixedAppDynamicType()
            }
            .eraseToAnyView()


        let v3 = v2
            .sheet(isPresented: $ui.showCodeShareSheet) {
                codeShareSheetView
                    .fixedAppDynamicType()
            }
            .eraseToAnyView()

        let v4 = v3
            .sheet(isPresented: $ui.showInviteJoinSheet) {
                inviteJoinSheetView
                    .fixedAppDynamicType()
            }
            .sheet(isPresented: $ui.showProPaywall) {
                ProPaywallView(
                    title: "PitchMark Pro",
                    message: "Connect participants, unlock full grid keys, and use the display app with PitchMark Pro.",
                    allowsClose: true
                )
                .fixedAppDynamicType()
            }
            .fullScreenCover(isPresented: $ui.showQRScanner) {
                ZStack(alignment: .bottom) {
                    QRScannerView { scanned in
                        inviteJoinText = scanned
                        inviteJoinError = nil
                        showQRScanner = false
                        joinLiveGameFromInvite()
                    } onCancel: {
                        showQRScanner = false
                    }

                    Button("Paste invite link") {
                        showQRScanner = false
                        showInviteJoinSheet = true
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 24)
                }
                .fixedAppDynamicType()
            }
            .alert("Camera Unavailable", isPresented: $ui.showCameraUnavailableAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("This device doesn’t have a camera available.")
            }
            .appConfirmationDialog(
                isPresented: $ui.showCameraPermissionAlert,
                title: "Camera Access Needed",
                message: "Enable Camera access in Settings to scan the owner’s QR code.",
                primaryTitle: "Open Settings",
                primaryAction: {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                },
                secondaryTitle: "Cancel"
            )
            .onChange(of: activeLiveId) { _, newValue in
                guard let liveId = newValue, !liveId.isEmpty, !isOwnerForActiveGame else { return }
                guard !promptedTrackingModeLiveIds.contains(liveId) else { return }
                showCallingPitchesPrompt = true
            }
            .onChange(of: activeSide) { _, newSide in
                guard let pid = selectedPitcherId else { return }
                let stillValid = (newSide == .away) ? awayPitcherIds.contains(pid) : !awayPitcherIds.contains(pid)
                if !stillValid {
                    selectedPitcherId = nil
                    persistSelectedPitcherId(nil)
                }
                // The At Bat scroll is now side-scoped (visibleJerseyCells)
                // - if the batter selected on the old side isn't linked to
                // the new side's roster, it's about to disappear from the
                // list, so clear and persist that rather than leaving a
                // selection pointing at a hidden cell.
                if let batterId = selectedBatterId,
                   !visibleJerseyCells.contains(where: { $0.id == batterId }) {
                    syncSelectedBatterFromDetail(nil)
                }
                selectedHitterId = nil
            }
            .onChange(of: selectedBatterId) { _, newId in
                selectedHitterId = newId.flatMap { hitterIdByJerseyCellId[$0] }
            }
            .onChange(of: jerseyCells.map { $0.id }) { _, validIds in
                // Deleting a jersey cell happens from several places
                // (the pin-icon detail popover's Delete, JerseyRow's own
                // "Delete Batter?" sheet) and none of them know about this
                // roster-link map, nor should they each have to - pruning
                // here once, keyed off jerseyCells itself changing, catches
                // every existing and future delete path instead of needing
                // each one patched individually. Without this, a deleted
                // roster player stayed permanently excluded from "Add From
                // Team" (atBatRosterPickerCandidates filters out anyone
                // already in hitterIdByJerseyCellId.values) even though
                // they were no longer actually in the lineup - only a full
                // relaunch (which resets this map in chooseGame) cleared it.
                let validSet = Set(validIds)
                let pruned = hitterIdByJerseyCellId.filter { validSet.contains($0.key) }
                guard pruned.count != hitterIdByJerseyCellId.count else { return }
                hitterIdByJerseyCellId = pruned
                // The map is persisted now, so a delete has to reach the
                // stored copy too - otherwise the deleted batter comes back
                // as a link on the next game open and stays excluded from
                // "Add From Team" forever.
                persistHitterLinks()
            }
            .sheet(isPresented: $ui.showSetOpponentSheet, onDismiss: { showChooseBattersStep = false }) {
                // Defaulted to the system's full-size sheet before, which
                // looked odd for a sheet this sparse - medium fits its
                // content, with large still reachable by dragging up for
                // the choose-batters step's longer list.
                setOpponentSheetView
                    .fixedAppDynamicType()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $ui.showSetMyTeamSheet) {
                setMyTeamSheetView
                    .fixedAppDynamicType()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $ui.showQuickAddPlayerSheet) {
                // Same reasoning as setOpponentSheetView above - the old
                // 2-field version looked lost filling the whole screen;
                // medium/large now that Position and Batting Side add more
                // content, matching TeamRosterView's own Add Player form.
                quickAddPlayerSheetView
                    .fixedAppDynamicType()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $ui.showAtBatRosterPickerSheet) {
                atBatRosterPickerSheetView
                    .fixedAppDynamicType()
            }
            .sheet(isPresented: $ui.showGridKeySheet) {
                ScrollableSelectionSheet(
                    title: "Select Template",
                    items: visibleTemplates,
                    topActions: [],
                    itemTitle: { $0.name },
                    isSelected: { $0.id == selectedTemplate?.id },
                    onSelect: { template in
                        applyTemplate(template)
                    }
                )
                .fixedAppDynamicType()
            }
            .appConfirmationDialog(
                isPresented: $ui.showCallingPitchesPrompt,
                title: "Calling Pitches?",
                message: "Are you calling pitches for this game, or just tracking what happens? You can switch anytime with the Coach/Scout control.",
                primaryTitle: "I’m Calling Pitches",
                primaryAction: {
                    currentTrackingMode = .coach
                    if let liveId = activeLiveId { markTrackingModePrompted(forLiveId: liveId) }
                },
                secondaryTitle: "Just Tracking",
                secondaryAction: {
                    currentTrackingMode = .scout
                    if let liveId = activeLiveId { markTrackingModePrompted(forLiveId: liveId) }
                }
            )
            .eraseToAnyView()

        let v4b = v4
            .eraseToAnyView()

        let v6 = v4b
            .eraseToAnyView()

        let v7 = v6
            .sheet(isPresented: $ui.showCodeAssignmentSheet) {
                codeAssignmentSheetView
                    .fixedAppDynamicType()
            }
            .eraseToAnyView()

        // Home/Moments/Family used to be sheets presented from here (with an
        // onDismiss + asyncAfter(0.05) dance to chain one into the next).
        // They're TabView siblings now - see body's final return - so this
        // link is just a pass-through.
        let v8 = v7
            .eraseToAnyView()

        let v8b = v8
            .eraseToAnyView()

        let v9 = v8b
            .sheet(isPresented: $ui.showGameStatsSheet) {
                gameStatsSheetView
                    .fixedAppDynamicType()
            }
            .eraseToAnyView()

        let v9b = v9
            .sheet(isPresented: $ui.showGameSummarySheet) {
                gameSummarySheetView
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .fixedAppDynamicType()
            }
            .sheet(item: $savedPlayReviewDraft) { draft in
                SavedPlayReviewSheetView(
                    title: draft.title,
                    summaryLines: draft.summaryLines,
                    initialEvent: draft.event,
                    onBack: {
                        savedPlayReviewDraft = nil
                    },
                    onSave: { reviewedEvent in
                        commitReviewedSavedPlayEvent(reviewedEvent)
                    }
                )
                .interactiveDismissDisabled(true)
                .fixedAppDynamicType()
            }
            .sheet(isPresented: calledPitchComposerBinding) {
                calledPitchComposerSheetView
                    .presentationDetents(calledPitchComposerDetents, selection: $calledPitchComposerDetent)
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled)
                    .fixedAppDynamicType()
            }
            .eraseToAnyView()

        // Keep alerts + the rest of your observers, then erase one last time
        let gamesTabContent = AnyView(v9b
            .allowsHitTesting(!showSessionConflictAlert)
            .appConfirmationDialog(
                isPresented: $ui.showProGateAlert,
                title: "Upgrade to Pro",
                message: proGateMessage,
                primaryTitle: "Upgrade",
                primaryAction: {
                    showProPaywall = true
                },
                secondaryTitle: "Not Now"
            )
            .appConfirmationDialog(
                isPresented: $ui.showDemoLoginWall,
                title: "Sign In Required",
                message: demoLoginWallMessage,
                primaryTitle: "Sign In",
                primaryAction: {
                    onRequireSignIn()
                },
                secondaryTitle: "Not Now"
            )
            .alert("Select a game first", isPresented: $ui.showSelectGameFirstAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Create or choose a game before generating a partner code.")
            }
            .alert("Code Link", isPresented: $ui.showCodeShareErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(codeShareErrorMessage)
            }
            .alert("Game Not Found", isPresented: $ui.showGameEntryErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(gameEntryErrorMessage)
            }
            .alert("No pitches found", isPresented: $ui.showNoJerseyEventsAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(noJerseyEventsMessage)
            }
            .alert("Adjust to next batter if needed", isPresented: $ui.showNextBatterAdjustmentAlert) {
            } message: {
                Text(nextBatterAdjustmentMessage)
            }
            .alert("Pitch Unavailable", isPresented: $ui.showHeatmapUnavailablePitchAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(heatmapUnavailablePitchMessage)
            }
            .sheet(item: $jerseyDetailPayload) { payload in
                let event = payload.event
                let sourceEvents = isGame ? gamePitchEvents : pitchEvents
                let templateName = templates.first(where: { $0.id.uuidString == event.templateId })?.name ?? "Template"
                let pitcherNameById: [String: String] = {
                    var map: [String: String] = [:]
                    for pitcher in pitchers {
                        if let id = pitcher.id {
                            map[id] = pitcher.name
                        }
                    }
                    if let livePitcher = liveParticipantDisplayPitcher, let id = livePitcher.id {
                        map[id] = livePitcher.name
                    }
                    return map
                }()
                PitchEventDetailPopover(
                    event: event,
                    allEvents: sourceEvents,
                    templateName: templateName,
                    pitcherNameById: pitcherNameById,
                    gameIdFilter: selectedGameId,
                    lineupBatters: jerseyCells,
                    lineupGroups: lineupGroupsForDetail,
                    unlinkedBatterIds: unlinkedBatterIdsForDetail,
                    selectedLineupBatterId: selectedBatterId,
                    onSelectLineupBatter: { cell in
                        syncSelectedBatterFromDetail(cell)
                    },
                    onEditLineupBatter: { cell in
                        editingCell = cell
                        newJerseyNumber = cell.jerseyNumber
                        showAddJerseyPopover = true
                        jerseyDetailPayload = nil
                    },
                    onReorderLineupBatter: { moving, target in
                        reorderBatterFromDetail(moving, to: target)
                    },
                    onCommitLineupOrder: {
                        persistLineupFromDetail()
                    },
                    onDeleteLineupBatter: { cell in
                        deleteBatterFromDetail(cell)
                    },
                    currentCountSeed: (balls: balls, strikes: strikes),
                    onCountChanged: { newBalls, newStrikes in
                        syncCountFromComposer(balls: newBalls, strikes: newStrikes)
                    }
                )
                .padding(.horizontal)
                .padding(.top)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .fixedAppDynamicType()
            }
            .sheet(isPresented: $ui.showAtBatHeatmapSheet, onDismiss: {
                executePendingHeatmapCallIfNeeded()
            }) {
                atBatBatterHeatmapSheetView
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .fixedAppDynamicType()
            }
            .fullScreenCover(isPresented: displayCoverBinding) {
                displayCoverView
                    .fixedAppDynamicType()
            }
            .appConfirmationDialog(
                isPresented: $ui.showActivateNewBatterPrompt,
                title: "Activate New Batter?",
                message: pendingNewBatterActivation.map { "Would you like to activate #\($0.jerseyNumber) now?" } ?? "Would you like to activate the new batter now?",
                primaryTitle: "Activate Batter",
                primaryAction: {
                    if let cell = pendingNewBatterActivation {
                        syncSelectedBatterFromDetail(cell)
                    }
                    pendingNewBatterActivation = nil
                },
                secondaryTitle: "Keep Current Batter",
                secondaryAction: {
                    pendingNewBatterActivation = nil
                }
            )
            .overlay { accountInUseOverlay }
            .onAppear {
                if lastAuthenticatedUserId == nil {
                    lastAuthenticatedUserId = authManager.user?.uid
                }
                handleInitialAppear()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background || newPhase == .inactive {
                    if !isDemoMode {
                        flushProgressToGameIfOwner()
                    }
                }
            }
            .onChange(of: authManager.isSignedIn) { _, newValue in
                let currentUid = authManager.user?.uid
                resetStateForAuthenticatedUserChange(oldUserId: lastAuthenticatedUserId, newUserId: currentUid)
                lastAuthenticatedUserId = currentUid

                if newValue {
                    // ✅ If sign-in/restore completes AFTER first appear,
                    // rerun the boot flow so games/templates load and initial sheets can present.
                    handleInitialAppear()
                }
            }
            .onChange(of: authManager.user?.uid) { oldUid, newUid in
                resetStateForAuthenticatedUserChange(oldUserId: oldUid, newUserId: newUid)
                lastAuthenticatedUserId = newUid
                if newUid != nil {
                    handleInitialAppear()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pitcherSharedUpdated)) { _ in
                authManager.loadPitchers { loaded in
                    self.pitchers = loaded
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .permanentAccountLocalDataWillPurge)) { _ in
                // Never flush these events after their owning account has been
                // permanently deleted. The deletion-only disk purge removes the
                // corresponding JSON file immediately after this notification.
                bufferedSharedPitcherEvents.removeAll()
                bufferedSharedHitterEvents.removeAll()
            }
            .onReceive(NotificationCenter.default.publisher(for: .displayOnlyExitRequested)) { _ in
                if isDisplayOnlyMode {
                    exitDisplayOnlyMode()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .activeGameShouldClose)) { note in
                // Home's "Close Game". Scoped to one game id so a stale
                // post can't pull a different game out from under the
                // tracker; no id means "whatever is open".
                if let wanted = (note.userInfo?["gameId"] as? String),
                   let current = selectedGameId,
                   wanted != current {
                    return
                }
                // Same teardown the in-tracker exit uses - listeners,
                // lineup, defaults - and it tells the host we left, which
                // a deliberate close should do.
                disconnectFromGame(notifyHost: true)
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

                if let type = info["type"] as? String, type == "liveGame" {
                    guard let liveId = info["liveId"] as? String else { return }

                    // 🔴 Clear any stale game UI state before switching
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
                                if let err { debugLog("❌ deferred pending update error:", err.localizedDescription) }
                            }
                            self.deferredPendingPitch = nil
                        } catch {
                            debugLog("❌ encode deferred pending failed:", error)
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
                            if let err { debugLog("❌ deferred displayCode update error:", err.localizedDescription) }
                        }
                        if let uid = self.authManager.user?.uid, !uid.isEmpty {
                            Firestore.firestore()
                                .collection("users")
                                .document(uid)
                                .collection("displayState")
                                .document("current")
                                .setData([
                                    "colorName": deferred.colorName,
                                    "code": deferred.code,
                                    "updatedAt": FieldValue.serverTimestamp()
                                ], merge: true) { err in
                                    if let err {
                                        debugLog("❌ deferred displayState mirror failed:", err.localizedDescription)
                                    } else {
                                        debugLog("✅ deferred displayState mirror wrote code=\(deferred.code)")
                                    }
                                }
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

                    debugLog("✅ Resolver received game:", gid, "owner:", ownerUid)
                    self.resetCallAndResultUIState()
                    self.requestGameConfirmation(gameId: gid, ownerUid: ownerUid)

                    return

                }
            }
            .eraseToAnyView()
        )

        // Home/Games/Moments as real TabView siblings - Games stays
        // permanently mounted (so its live-session listeners, boot-once
        // guard, and scenePhase handling above never tear down) while the
        // other two are reached by selection instead of by sheet. This
        // replaces the old HomeAreaTabBar + onDismiss/asyncAfter(0.05)
        // sheet-chaining hack entirely. Family (Phase 9 of the 2026-09-24
        // direction) was removed 2026-10-16 - its one job, getting a Moment
        // or quick text to a family member, is now covered by Moments'
        // own share action and iOS's share-sheet recents.
        return TabView(selection: $activeHomeArea) {
            gamesTabContent
                .tabItem { Label(HomeArea.games.title, systemImage: HomeArea.games.systemImage) }
                .tag(HomeArea.games)

            settingsSheetView
                .fixedAppDynamicType()
                .tabItem { Label(HomeArea.home.title, systemImage: HomeArea.home.systemImage) }
                .tag(HomeArea.home)

            MomentsLibraryView(onSwitchToArea: { selectHomeArea($0) })
                .fixedAppDynamicType()
                .tabItem { Label(HomeArea.moments.title, systemImage: HomeArea.moments.systemImage) }
                .tag(HomeArea.moments)
        }
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

/// Shared by the header's read-only dots and this panel's large interactive
/// ones so both render outs as squares (distinct from the balls/strikes
/// circles) with a single source of truth for the glyph names.
private enum CountDotShape {
    case circle
    case square
}

private func countDotSystemImageName(filled: Bool, shape: CountDotShape) -> String {
    switch shape {
    case .circle: return filled ? "circle.fill" : "circle"
    case .square: return filled ? "square.fill" : "square"
    }
}

/// White rounded row card that groups one or more `StatStepper`s, matching
/// the flat card style used for the Score / Hits-Walks / Inning rows.
/// Width-bound (not scrolling) so `Spacer`s inside can actually distribute
/// space and center content — every row here was slimmed down (shorter
/// labels, fewer steppers per row) specifically so it fits without scrolling
/// on the narrowest supported phone (iPhone 17).
private struct StatsPanelCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
    }
}

private struct StatDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.15))
            .frame(width: 1, height: 26)
    }
}

private enum StatLabelPosition {
    case leading
    case trailing
}

/// Label + minus/number/plus row used by Score (US/THEM) and Hits/Walks.
/// `labelPosition` lets THEM mirror US — label after the controls instead
/// of before — so the two flank a centered "Score" like a scoreboard.
private struct StatStepper: View {
    let label: String
    @Binding var value: Int
    var floor: Int = 0
    var labelPosition: StatLabelPosition = .leading
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if labelPosition == .leading {
                labelText
            }

            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                if value > floor {
                    value -= 1
                    onChange()
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 24, height: 24)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Text("\(value)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.black)
                .lineLimit(1)
                .frame(minWidth: 24)
                .padding(.vertical, 2)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                value += 1
                onChange()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            if labelPosition == .trailing {
                labelText
            }
        }
        .fixedSize()
    }

    private var labelText: some View {
        Text(label)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.black)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Tappable numbered circle for the Inn. row — filled solid once the
/// current inning has reached it, mirroring the balls/strikes/outs dots'
/// fill-as-you-go pattern but with the number visible inside each circle.
private struct InningCircle: View {
    let number: Int
    let isFilled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isFilled ? Color.white : Color.black)
                .frame(width: 26, height: 26)
                .background(isFilled ? Color.accentColor : Color(.systemGray5))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Trailing "+" circle on the Inn. row for extending manually past inning 7.
private struct InningAddCircle: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.accentColor)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Inning")
    }
}

private struct ProgressGameView: View {
    /// Team names for the Score row, already abbreviated by the caller.
    /// Fall back to "US"/"THEM" when a side has no team linked.
    let homeTeamLabel: String
    let awayTeamLabel: String
    let ownerUserId: String?
    @Binding var balls: Int
    @Binding var strikes: Int
    let outs: Int
    let showOutsFlash: Bool
    let onOutsTapIndex: (Int) -> Void
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
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 6) {
                StatsPanelCard {
                    Spacer(minLength: 0)
                    Text("Inn.")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .fixedSize()
                    ForEach(inningWindow, id: \.self) { number in
                        InningCircle(number: number, isFilled: inning >= number) {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            inning = number
                        }
                    }
                    InningAddCircle {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        inning = max(inning, 7) + 1
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 12)

            HStack(spacing: 0) {
                largeCountEditor(prefix: "B", count: balls, maxCount: 3, filledColor: .red, shape: .circle) { idx in
                    let value = idx + 1
                    balls = (balls == value) ? max(0, value - 1) : value
                    onProgressChange()
                }
                .frame(maxWidth: .infinity)

                largeCountEditor(prefix: "S", count: strikes, maxCount: 2, filledColor: .green, shape: .circle) { idx in
                    let value = idx + 1
                    strikes = (strikes == value) ? max(0, value - 1) : value
                    onProgressChange()
                }
                .frame(maxWidth: .infinity)

                largeCountEditor(prefix: "O", count: outs, maxCount: 3, filledColor: .primary, shape: .square, onTapIndex: onOutsTapIndex)
                    .scaleEffect(showOutsFlash ? 1.08 : 1.0)
                    .shadow(color: showOutsFlash ? Color.red.opacity(0.35) : .clear, radius: showOutsFlash ? 8 : 0, x: 0, y: 0)
                    .animation(.easeInOut(duration: 0.18), value: showOutsFlash)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)

            Divider()

            VStack(spacing: 6) {
                StatsPanelCard {
                    StatStepper(label: homeTeamLabel, value: $us, onChange: onProgressChange)
                    StatDivider()
                    Spacer(minLength: 0)
                    // Was .fixedSize() with 8pt spacers either side. Both
                    // sides of this row are team names now rather than
                    // "US"/"THEM", so the centre caption yields space to them
                    // instead of holding its full width.
                    Text("Score")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .layoutPriority(0)
                    Spacer(minLength: 0)
                    StatDivider()
                    StatStepper(label: awayTeamLabel, value: $them, labelPosition: .trailing, onChange: onProgressChange)
                }
                StatsPanelCard {
                    StatStepper(label: "Hits", value: $hits, onChange: {})
                    StatDivider()
                    Spacer(minLength: 8)
                    StatStepper(label: "Walks", value: $walks, labelPosition: .trailing, onChange: {})
                }
            }
            .padding(.horizontal, 12)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
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

    /// Larger, tappable balls/strikes/outs editor for this revealed panel —
    /// the header's dots are display-only, so this is the only place these
    /// values can be changed.
    /// Inline label-then-dots layout, mirroring the header's compact
    /// B/S/O pattern (single-letter prefix beside the dots, not stacked
    /// above them) but with bigger, tappable dots since this is the only
    /// place balls/strikes/outs can actually be edited.
    private func largeCountEditor(
        prefix: String,
        count: Int,
        maxCount: Int,
        filledColor: Color,
        shape: CountDotShape,
        onTapIndex: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Text(prefix)
                .font(.headline.weight(.bold))
                .foregroundStyle(.black)
                .lineLimit(1)
                .fixedSize()
            HStack(spacing: 6) {
                ForEach(0..<maxCount, id: \.self) { idx in
                    Button {
                        onTapIndex(idx)
                    } label: {
                        Image(systemName: countDotSystemImageName(filled: idx < max(0, min(maxCount, count)), shape: shape))
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(idx < max(0, min(maxCount, count)) ? filledColor : Color.primary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Always exactly 7 numbers wide. Stays pinned to 1...7 while `inning`
    /// is within that range; once "+" pushes `inning` past 7, the window
    /// slides to keep the current inning as the rightmost circle (e.g.
    /// inning 8 shows 2...8) instead of leaving every circle in 1...7
    /// permanently filled with no way to tell which inning it actually is.
    private var inningWindow: ClosedRange<Int> {
        let end = max(inning, 7)
        let start = end - 6
        return start...end
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

private struct ProgressSummaryView: View {
    let events: [PitchEvent]
    let currentMode: PitchMode
    let templates: [PitchTemplate]
    
    @State private var isReset: Bool = false
    
    private func didHitLocation(_ event: PitchEvent) -> Bool {
        return isLocationMatch(event)
    }
    
    private var summaryEvents: [PitchEvent] {
        if isReset { return [] }
        return events
    }

    private var hasLocationAnalytics: Bool {
        summaryEvents.contains(where: \.supportsLocationAnalytics)
    }
    
    private var totalCount: Int { summaryEvents.count }
    private var strikeCount: Int { summaryEvents.filter { inferredPitchResultType(for: $0) == .strike }.count }
    private var ballCount: Int { summaryEvents.filter { inferredPitchResultType(for: $0) == .ball }.count }
    private var hitSpotEligibleCount: Int { summaryEvents.filter(\.supportsLocationAnalytics).count }
    private var foulCount: Int {
        summaryEvents.filter { event in
            let outcome = event.outcome?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return outcome.caseInsensitiveCompare("Foul") == .orderedSame || event.isFoulInferred || event.foulMarker != nil
        }.count
    }
    private var strikeHitSpotEligibleCount: Int {
        summaryEvents.filter { $0.supportsLocationAnalytics && inferredPitchResultType(for: $0) == .strike }.count
    }
    private var ballHitSpotEligibleCount: Int {
        summaryEvents.filter { $0.supportsLocationAnalytics && inferredPitchResultType(for: $0) == .ball }.count
    }
    private var hitSpotCount: Int {
        summaryEvents.filter { ev in
            ev.supportsLocationAnalytics && didHitLocation(ev)
        }.count
    }
    
    private var strikeHitSpotCount: Int {
        summaryEvents.filter { ev in
            ev.supportsLocationAnalytics && inferredPitchResultType(for: ev) == .strike && didHitLocation(ev)
        }.count
    }

    private var ballHitSpotCount: Int {
        summaryEvents.filter { ev in
            ev.supportsLocationAnalytics && inferredPitchResultType(for: ev) == .ball && didHitLocation(ev)
        }.count
    }

    private var firstPitchStrikeCount: Int { sharedFirstPitchStrikeMetrics(for: summaryEvents).made }

    private var firstPitchStrikeOpportunities: Int { sharedFirstPitchStrikeMetrics(for: summaryEvents).total }

    private var firstPitchStrikePercent: String {
        percent(firstPitchStrikeCount, of: max(firstPitchStrikeOpportunities, 1))
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
        for ev in summaryEvents {
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
        debugLog("[Metrics] pitchStats summary:\n\(debugSummary)")
        return mapped.sorted { lhs, rhs in
            if lhs.percent == rhs.percent { return lhs.attempts > rhs.attempts }
            return lhs.percent > rhs.percent
        }
    }
    
    private var pitchRanking: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for ev in summaryEvents {
            debugLog("[Metrics] Ranking consider id=\(ev.id ?? "-") pitch=\(ev.pitch) hasCall=\(ev.calledPitch != nil) didHit=\(didHitLocation(ev))")
            guard ev.calledPitch != nil else { continue }
            guard didHitLocation(ev) else { continue }
            let name = ev.pitch
            guard !name.isEmpty else { continue }
            debugLog("[Metrics]  Increment ranking for \(name)")
            counts[name, default: 0] += 1
        }

        let rankingArray: [(name: String, count: Int)] = counts.map { (key, value) in
            (name: key, count: value)
        }

        let summary = rankingArray.map { "\($0.name): \($0.count)" }.joined(separator: ", ")
        debugLog("[Metrics] pitchRanking counts: \(summary)")

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
                    if hasLocationAnalytics {
                        metricCard(title: "% Hit Spot", value: percent(hitSpotCount, of: max(hitSpotEligibleCount, 1)))
                    }
                }
                .frame(maxWidth: 80)
                
                // Center: Header + Table (constrained and centered)
                VStack(spacing: 8) {
                    Text(hasLocationAnalytics ? "Hit Spot Performance" : "Scout Mode Summary")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if !hasLocationAnalytics {
                                Text("Location-based metrics hidden for Scout Mode events.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else if pitchStats.isEmpty {
                                Text("No data yet.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                ForEach(Array(pitchStats.enumerated()), id: \.offset) { idx, item in
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(
                                            item.pitch == "Catcher"
                                            ? "\(idx + 1). \(item.pitch) — \(item.attempts)"
                                            : "\(idx + 1). \(item.pitch) — \(item.hits)/\(item.attempts) (\(percent(item.hits, of: max(item.attempts, 1))))"
                                        )
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
                    if hasLocationAnalytics {
                        Text("Hit Spot")
                            .font(Font.caption.italic())
                            .padding(.bottom, -4)
                        metricCard(title: "Strike %", value: percent(strikeHitSpotCount, of: max(strikeHitSpotEligibleCount, 1)))
                        metricCard(title: "Ball %", value: percent(ballHitSpotCount, of: max(ballHitSpotEligibleCount, 1)))
                    }
                }
                .frame(maxWidth: 80)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal)
        .offset(y: 20)
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
    @Binding var isReordering: Bool
    let onSelectedBatterChanged: (JerseyCell) -> Void

    @State private var showActionsSheet: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var selectedPulse: Bool = false

    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        let isSelected = selectedBatterId == cell.id

        JerseyCellView(cell: cell)
            .modifier(JiggleEffect(isActive: isReordering))
            .background(isSelected ? Color.blue : Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.white.opacity(0.9) : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundColor(isSelected ? .white : .primary)
            .scaleEffect(isSelected && selectedPulse ? 1.06 : 1.0)
            .shadow(color: isSelected ? Color.blue.opacity(selectedPulse ? 0.6 : 0.2) : .clear,
                    radius: isSelected ? (selectedPulse ? 8 : 3) : 0,
                    x: 0,
                    y: 0)
            .onTapGesture {
                guard !isReordering else { return }
                let wasSelected = selectedBatterId == cell.id
                syncSelection(cell.id)
                if !wasSelected {
                    onSelectedBatterChanged(cell)
                }
            }
            .task(id: isSelected) {
                // Deterministic pulse loop tied to selection state.
                // Task is canceled automatically when selection changes.
                if !isSelected {
                    withTransaction(Transaction(animation: nil)) {
                        selectedPulse = false
                    }
                    return
                }

                withTransaction(Transaction(animation: nil)) {
                    selectedPulse = false
                }

                while !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 0.9)) {
                        selectedPulse.toggle()
                    }
                    try? await Task.sleep(nanoseconds: 900_000_000)
                }

                withTransaction(Transaction(animation: nil)) {
                    selectedPulse = false
                }
            }
            .onDrop(of: [UTType.text], delegate: JerseyDropDelegate(current: cell, items: $jerseyCells, dragging: $draggingJersey))
            .sheet(isPresented: $showActionsSheet) {
                VStack(alignment: .leading, spacing: 12) {
                    
                    Text("Batter #\(cell.jerseyNumber)")
                        .font(.headline)
                        .padding(.bottom, 4)
                        
                    HStack {
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
                        Spacer()
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
                    
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
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
                }
                .padding()
                .presentationDetents([.fraction(0.35), .medium])
                .fixedAppDynamicType()
                .appConfirmationDialog(
                    isPresented: $showDeleteConfirm,
                    title: "Delete Batter?",
                    message: "This will remove this batter from the lineup.",
                    primaryTitle: "Delete",
                    primaryRole: .destructive,
                    primaryAction: {
                        // Close this row's sheet BEFORE removing the row,
                        // and let the dismissal settle before mutating the
                        // lineup. Deleting in the same update as the
                        // teardown removed the presenting row while its
                        // `showActionsSheet` was still true, and that
                        // still-true @State landed on whichever cell
                        // inherited this row's state slot in the ForEach -
                        // so the pin sheet immediately re-presented,
                        // titled with some other batter's number.
                        showActionsSheet = false
                        DispatchQueue.main.async {
                            deleteThisBatter()
                        }
                    },
                    secondaryTitle: "Cancel"
                )
            }
    }

    /// The pin sheet's Delete, run one runloop turn after the sheet has
    /// been dismissed (see the call site). Re-finds the cell by id rather
    /// than trusting an index captured before that hop.
    private func deleteThisBatter() {
            guard let idx = jerseyCells.firstIndex(where: { $0.id == cell.id }) else {
                return
            }

            let removedId = jerseyCells[idx].id
            jerseyCells.remove(at: idx)

            if selectedBatterId == removedId {
                selectedBatterId = nil
            }

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
                debugLog("⚠️ Cannot persist delete: missing activeLiveId (live) or selectedGameId/effectiveGameOwnerUserId (non-live)")
            }
    }

    private func syncSelection(_ nextSelection: UUID?) {
        let selectedCell = nextSelection.flatMap { id in jerseyCells.first(where: { $0.id == id }) }
        selectedBatterId = nextSelection

        guard let gameId = selectedGameId,
              let owner = effectiveGameOwnerUserId,
              !owner.isEmpty
        else {
            debugLog("⚠️ Cannot sync selected batter: missing selectedGameId or effectiveGameOwnerUserId")
            return
        }

        if let liveId = activeLiveId, !liveId.isEmpty {
            var fields: [String: Any] = [:]
            if let nextSelection {
                fields["selectedBatterId"] = nextSelection.uuidString
                if let jersey = selectedCell?.jerseyNumber {
                    fields["selectedBatterJersey"] = jersey
                } else {
                    fields["selectedBatterJersey"] = FieldValue.delete()
                }
            } else {
                fields["selectedBatterId"] = FieldValue.delete()
                fields["selectedBatterJersey"] = FieldValue.delete()
            }
            LiveGameService.shared.updateLiveFields(liveId: liveId, fields: fields)
            return
        }

        authManager.updateGameSelectedBatter(
            ownerUserId: owner,
            gameId: gameId,
            selectedBatterId: nextSelection?.uuidString,
            selectedBatterJersey: selectedCell?.jerseyNumber
        )
    }


    private func selectJersey(_ cell: JerseyCell) {
        // ✅ Optimistic UI
        selectedBatterId = cell.id

        guard let gid = selectedGameId,
              let owner = effectiveGameOwnerUserId,
              !owner.isEmpty
        else {
            debugLog("⚠️ selectJersey: missing gameId/owner")
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

private struct ScoutColorKey: Hashable {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8
}

private func scoutColorKey(from color: UIColor) -> ScoutColorKey {
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return ScoutColorKey(
        r: UInt8((r * 255.0).rounded()),
        g: UInt8((g * 255.0).rounded()),
        b: UInt8((b * 255.0).rounded()),
        a: UInt8((a * 255.0).rounded())
    )
}

private extension UIImage {
    func scoutPixelColor(at point: CGPoint) -> UIColor? {
        guard let cgImage = self.cgImage else { return nil }
        guard Int(point.x) >= 0, Int(point.y) >= 0, Int(point.x) < cgImage.width, Int(point.y) < cgImage.height else { return nil }
        guard let dataProvider = cgImage.dataProvider, let data = dataProvider.data else { return nil }
        let ptr = CFDataGetBytePtr(data)
        let bytesPerPixel = 4
        let bytesPerRow = cgImage.bytesPerRow
        let offset = Int(point.y) * bytesPerRow + Int(point.x) * bytesPerPixel
        let r = ptr![offset]
        let g = ptr![offset + 1]
        let b = ptr![offset + 2]
        let a = ptr![offset + 3]
        return UIColor(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: CGFloat(a) / 255.0
        )
    }
}

private struct ScoutFieldMapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedOutcome: String?
    @Binding var battedBallRegionName: String?
    @Binding var battedBallTapNormalized: CGPoint?
    let isDemoMode: Bool

    private let colorMapImage: UIImage? = UIImage(named: "colorMap")
    private var displayImageName: String {
        "FieldImage2"
    }
    private let colorMapping: [ScoutColorKey: (label: String, outcome: String?)] = [
        ScoutColorKey(r: 0xE6, g: 0x19, b: 0x4B, a: 0xFF): ("Left Field HR", "HR"),
        ScoutColorKey(r: 0x91, g: 0x1E, b: 0xB4, a: 0xFF): ("Foul Left", nil),
        ScoutColorKey(r: 0xDC, g: 0xBE, b: 0xFF, a: 0xFF): ("Deep Center", nil),
        ScoutColorKey(r: 0xBF, g: 0xEF, b: 0x45, a: 0xFF): ("Deep Left", nil),
        ScoutColorKey(r: 0x4E, g: 0x51, b: 0x2E, a: 0xFF): ("Deep Right", nil),
        ScoutColorKey(r: 0x42, g: 0xD4, b: 0xF4, a: 0xFF): ("Shallow Left", nil),
        ScoutColorKey(r: 0xF7, g: 0x81, b: 0xBF, a: 0xFF): ("Shallow Center", nil),
        ScoutColorKey(r: 0x00, g: 0x00, b: 0x75, a: 0xFF): ("Shallow Right", nil),
        ScoutColorKey(r: 0x80, g: 0x80, b: 0x00, a: 0xFF): ("3B area", nil),
        ScoutColorKey(r: 0xFF, g: 0xD8, b: 0xB1, a: 0xFF): ("SS area", nil),
        ScoutColorKey(r: 0xFF, g: 0xE1, b: 0x19, a: 0xFF): ("2B area", nil),
        ScoutColorKey(r: 0xAA, g: 0x6E, b: 0x28, a: 0xFF): ("1B area", nil),
        ScoutColorKey(r: 0xFA, g: 0xBE, b: 0x28, a: 0xFF): ("Front of 3B", nil),
        ScoutColorKey(r: 0x00, g: 0x80, b: 0x80, a: 0xFF): ("Front of catcher", nil),
        ScoutColorKey(r: 0xE6, g: 0xBE, b: 0xFF, a: 0xFF): ("Front of 1B", nil),
        ScoutColorKey(r: 0x80, g: 0x00, b: 0x00, a: 0xFF): ("Pitcher", nil),
        ScoutColorKey(r: 0xF0, g: 0x32, b: 0xE6, a: 0xFF): ("Foul Right", nil),
        ScoutColorKey(r: 0xF5, g: 0x82, b: 0x31, a: 0xFF): ("Foul Left field", nil),
        ScoutColorKey(r: 0xD2, g: 0xF5, b: 0x3C, a: 0xFF): ("Foul Right field", nil),
        ScoutColorKey(r: 0x46, g: 0xF0, b: 0xF0, a: 0xFF): ("Foul behind", nil),
        ScoutColorKey(r: 0x3C, g: 0xB4, b: 0x4B, a: 0xFF): ("Center Field HR", "HR"),
        ScoutColorKey(r: 0x00, g: 0x82, b: 0xC8, a: 0xFF): ("Right Field HR", "HR")
    ]

    private func handleTap(at location: CGPoint, in imageRect: CGRect) {
        guard imageRect.contains(location) else { return }

        let nx = (location.x - imageRect.minX) / imageRect.width
        let ny = (location.y - imageRect.minY) / imageRect.height

        if let img = colorMapImage, let cg = img.cgImage {
            let px = max(0, min(CGFloat(cg.width - 1), nx * CGFloat(cg.width)))
            let py = max(0, min(CGFloat(cg.height - 1), ny * CGFloat(cg.height)))
            if let uiColor = img.scoutPixelColor(at: CGPoint(x: floor(px), y: floor(py))) {
                let key = scoutColorKey(from: uiColor)
                if let mapped = colorMapping[key] {
                    battedBallRegionName = mapped.label
                    battedBallTapNormalized = CGPoint(x: max(0, min(1, nx)), y: max(0, min(1, ny)))
                    if let outcome = mapped.outcome {
                        selectedOutcome = outcome
                    }
                    return
                }
            }
        }

        battedBallRegionName = colorMapImage == nil ? "No color map" : "Unmapped"
        battedBallTapNormalized = CGPoint(x: max(0, min(1, nx)), y: max(0, min(1, ny)))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let availableWidth = proxy.size.width
                let availableHeight = proxy.size.height
                let displayImage = UIImage(named: displayImageName) ?? UIImage(named: "FieldImage")
                let aspect: CGFloat = {
                    if let img = colorMapImage ?? displayImage {
                        return img.size.width / max(img.size.height, 1)
                    }
                    return 1
                }()
                let widthFitW = availableWidth * 1.18
                let widthFitH = widthFitW / max(aspect, 0.001)
                let heightFitH = availableHeight * 1.18
                let heightFitW = heightFitH * aspect
                let finalSize: CGSize = widthFitH >= availableHeight
                    ? CGSize(width: widthFitW, height: widthFitH)
                    : CGSize(width: heightFitW, height: heightFitH)
                let imageRect = CGRect(
                    x: (availableWidth - finalSize.width) / 2,
                    y: -120 + (availableHeight * 0.03),
                    width: finalSize.width,
                    height: finalSize.height
                )

                ZStack {
                    if let displayImage {
                        Image(uiImage: displayImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: imageRect.width, height: imageRect.height)
                            .position(x: imageRect.midX, y: imageRect.midY)
                            .shadow(radius: 10)
                            .allowsHitTesting(false)
                    }

                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { value in
                                    handleTap(at: value.location, in: imageRect)
                                }
                        )

                    if let normalized = battedBallTapNormalized {
                        let point = CGPoint(
                            x: imageRect.minX + (normalized.x * imageRect.width),
                            y: imageRect.minY + (normalized.y * imageRect.height)
                        )
                        Circle()
                            .fill(Color.red)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .position(x: point.x, y: point.y)

                        if let battedBallRegionName, !battedBallRegionName.isEmpty {
                            Text(battedBallRegionName)
                                .font(.headline)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Capsule())
                                .position(
                                    x: min(max(point.x, 70), proxy.size.width - 70),
                                    y: min(point.y + 28, proxy.size.height - 24)
                                )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Ball in Play Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        battedBallRegionName = nil
                        battedBallTapNormalized = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
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

    private var canChangeCodeOrder: Bool {
        template != nil
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
                Picker("", selection: $pitchFirst) {
                    Text("Pitch 1st")
                        .tag(true)

                    Text("Location 1st")
                        .tag(false)
                }
                .controlSize(.mini)
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(!canChangeCodeOrder)
                .opacity(canChangeCodeOrder ? 1 : 0.55)
                .accessibilityHint(canChangeCodeOrder ? "Changes how pitch and location code pairs are ordered." : "Code order selection is unavailable until a grid key is selected.")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .padding(.horizontal, 22)
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
    @State private var previousOrientationLockForCodeDisplay: UIInterfaceOrientationMask? = nil
    @Binding var pitchResultBannerPhase: PitchTrackerView.PitchResultBannerPhase
    @State private var codeDisplayOverlayPayload: CodeDisplayOverlayPayload?
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
    let onDeferDisplayCode: ((String, String) -> Void)?
    
    /// Call length is 4 (Advanced: C1C2|C3C4) or 3 (Normal: C1C2|Cloc). Pitch is always the leading
    /// 2 characters; the remainder is the location. `pitchFirst == false` swaps the two groups.
    private var expectedCodeLength: Int {
        template?.codeMode == .normal ? 3 : 4
    }

    private func normalizeCode(_ code: String) -> String {
        let cleaned = code.uppercased().filter { $0.isNumber || ($0.isLetter && $0.isASCII) }
        let expectedLength = expectedCodeLength
        let base = String(cleaned.prefix(expectedLength))
        guard !pitchFirst, base.count == expectedLength else { return base }
        let start = base.startIndex
        let mid = base.index(start, offsetBy: 2)
        let pitchPart = base[start..<mid]
        let locationPart = base[mid..<base.endIndex]
        return String(locationPart + pitchPart)
    }

    private func displayCode(_ code: String) -> String {
        let normalized = normalizeCode(code)
        let expectedLength = expectedCodeLength
        guard normalized.count == expectedLength else { return normalized }
        let firstSegmentLength = pitchFirst ? 2 : (expectedLength - 2)
        let start = normalized.startIndex
        let mid = normalized.index(start, offsetBy: firstSegmentLength)
        let firstPart = normalized[start..<mid]
        let secondPart = normalized[mid..<normalized.endIndex]
        return "\(firstPart)·\(secondPart)"
    }

    private var selectedDisplayedCode: String? {
        guard let tappedCode else { return nil }
        return displayCode(tappedCode)
    }

    private func broadcastDisplayCode(colorName: String, code: String) {
        guard let uid = Auth.auth().currentUser?.uid else {
            debugLog("⚠️ broadcastDisplayCode skipped (missing uid) color=\(colorName) code=\(code)")
            return
        }
        debugLog("📤 broadcastDisplayCode user=\(uid) color=\(colorName) code=\(code)")
        Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("displayState")
            .document("current")
            .setData([
                "colorName": colorName,
                "code": code,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true) { err in
                if let err {
                    debugLog("❌ broadcastDisplayCode displayState write failed:", err.localizedDescription)
                } else {
                    debugLog("✅ broadcastDisplayCode displayState wrote code=\(code)")
                }
            }
    }

    private func clearDisplayCode() {
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

    private func beginCodeDisplayOrientationUnlock() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        guard previousOrientationLockForCodeDisplay == nil else { return }
        let currentLock = AppDelegate.orientationLock

        // Only widen the lock when this flow is actually constrained to portrait.
        guard currentLock == .portrait else { return }

        previousOrientationLockForCodeDisplay = currentLock
        AppDelegate.setOrientationLock(.allButUpsideDown)
    }

    private func endCodeDisplayOrientationUnlock() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        guard let previousLock = previousOrientationLockForCodeDisplay else { return }

        previousOrientationLockForCodeDisplay = nil
        AppDelegate.setOrientationLock(previousLock)
    }

    var body: some View {
        let displayLocation = call.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixedDisplayLocation = "\(call.type) \(displayLocation)"
        let assignments = pitchCodeAssignments.filter {
              $0.pitch == call.pitch &&
              [displayLocation, prefixedDisplayLocation].contains($0.location.trimmingCharacters(in: .whitespacesAndNewlines))
          }

          // In encrypted mode, prefer the generated codes already carried on the call.
          // In classic mode, show assigned codes (deciphered via template when present).
          let displayCodes: [String] = {
              if isEncryptedMode {
                  return call.codes
              } else if !call.codes.isEmpty {
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
        let isCatcherCall = call.pitch.trimmingCharacters(in: .whitespacesAndNewlines) == "Catcher"
        let bannerShowsTapResult: Bool =
            isCatcherCall ||
            (tappedCode != nil) ||
            autoPitchOnlyEnabled
        let bannerText: String = {
            guard bannerShowsTapResult else { return "Code" }
            switch pitchResultBannerPhase {
            case .code:
                return "Code"
            case .tapLocation:
                return "Tap Location"
            case .chooseAny:
                return "Choose any"
            }
        }()
        
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Called Pitch")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(call.pitch)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    PitchResultBanner(
                        isRecording: bannerShowsTapResult,
                        text: bannerText,
                        callColor: callColor
                    )
                }
                
                // Assigned codes as chips
                if !displayCodes.isEmpty {
                    
                    //  Show codes ======================
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(displayCodes, id: \.self) { code in
                                let shown = displayCode(code)
                                Button {
                                    // Haptic feedback + trigger recording
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()
                                    tappedCode = code
                                    isRecordingResult = true
                                    pitchResultBannerPhase = .tapLocation
                                } label: {
                                    ZStack {
                                        // Base chip background
                                        Capsule()
                                            .fill(callColor.opacity(0.85))
                                        
                                        // Highlight overlay when tapped
                                        let isSelected = tappedCode == code

                                        if isSelected {
                                            Capsule()
                                                .fill(.white)
                                                .stroke(Color.black.opacity(0.9), lineWidth: 2)
                                                .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 0)
                                                .transition(.opacity)
                                        }

                                        Text(shown)
                                            .font(.title3.weight(.semibold))
                                            .foregroundColor(isSelected ? callColor.opacity(0.85) : .white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                    }
                                    .frame(height: 32)
                                    .animation(.easeInOut(duration: 0.15), value: tappedCode)
                                }
                                .buttonStyle(.plain) // preserve chip styling
                                .accessibilityLabel("Record for code \(shown)")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                    }
                    .frame(height: 42)
                    .contentMargins(.horizontal, 8, for: .scrollContent)
                    
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
                    
                } else {
                    if !isEncryptedMode {
                        Text("No assigned calls for this pitch/location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
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
        .fullScreenCover(item: $codeDisplayOverlayPayload, onDismiss: {
            endCodeDisplayOrientationUnlock()
        }) { payload in
            CodeDisplayOverlayView(
                colorName: payload.colorName,
                code: payload.code,
                onClose: {
                    codeDisplayOverlayPayload = nil
                    clearDisplayCode()
                }
            )
            .onAppear {
                beginCodeDisplayOrientationUnlock()
            }
            .fixedAppDynamicType()
        }
        .onChange(of: tappedCode) { _, newValue in
            if newValue == nil {
                codeDisplayOverlayPayload = nil
                clearDisplayCode()
                endCodeDisplayOrientationUnlock()
                pitchResultBannerPhase = .code
            }
        }
        .onChange(of: isRecordingResult) { _, newValue in
            if !newValue {
                pitchResultBannerPhase = .code
            }
        }
        .onChange(of: bannerShowsTapResult) { _, newValue in
            if newValue, pitchResultBannerPhase == .code {
                pitchResultBannerPhase = .tapLocation
            } else if !newValue {
                pitchResultBannerPhase = .code
            }
        }
        .onAppear {
            if bannerShowsTapResult, pitchResultBannerPhase == .code {
                pitchResultBannerPhase = .tapLocation
            }
        }
        
    }
}

struct PitchResultBanner: View {
    let isRecording: Bool
    let text: String
    let callColor: Color

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill")
                    .font(.caption.bold())

                if isRecording {
                    BlendedStrokeCircle(lineWidth: 3, size: 24)
                }

                Text(text)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
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
        .accessibilityLabel(isRecording ? text : "Code")
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
            .fixedAppDynamicType()
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
        debugLog("🧩 Generate tapped | gameId=\(gameId) isGame=\(isGame)")
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
                    debugLog("✅ Generated code=\(tuple.code) liveId=\(tuple.liveId)")
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
                    debugLog("❌ Generate failed:", err.localizedDescription)
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

/// Folds locally-known games that a fresh load doesn't contain back into
/// that load, instead of letting the load replace the list outright.
///
/// Every `loadGames` result is a point-in-time read that races any write
/// this device just made: a game created seconds ago may not be in it yet,
/// and a still-saving placeholder (id == nil) can never be in it at all.
/// Three separate call sites were each assigning `games = loaded` straight
/// through, so whichever one ran first made a brand-new game disappear -
/// including by simply leaving and re-opening the Games sheet.
///
/// A placeholder is dropped only once its real counterpart has landed,
/// matched on opponent + day the same way AddGameCard's own completion
/// matches it, so this never leaves a duplicate behind. Deletions are
/// unaffected: every delete path removes the row from `games` directly, so
/// a deleted game isn't in `local` to be revived.
fileprivate func mergePreservingUnsyncedGames(loaded: [Game], local: [Game]) -> [Game] {
    var merged = loaded
    let loadedIds = Set(loaded.compactMap { $0.id })
    for game in local {
        if let id = game.id {
            if !loadedIds.contains(id) {
                merged.append(game)
            }
        } else {
            let alreadyLanded = merged.contains {
                $0.opponent == game.opponent && Calendar.current.isDate($0.date, inSameDayAs: game.date)
            }
            if !alreadyLanded {
                merged.append(game)
            }
        }
    }
    return merged
}

struct GameSelectionSheet: View {
    // The completion fires with the real saved Game (real id included) once
    // the Firestore write actually confirms - see AddGameCard's onSave
    // below for why this replaced a fragile reload-and-match-by-name-date
    // approach.
    // Carries the Result, not just the saved Game. The success-only
    // version meant a failed write did nothing at all: the optimistic
    // placeholder row sat at "Saving..." forever, permanently disabled
    // (so untappable) with no error anywhere, and was then silently
    // dropped by the next games reload.
    /// Carries both sides' team ids (nil when a side wasn't picked, or the
    /// account has no teams yet) alongside the opponent name/date/mode.
    var onCreate: (String, Date, TrackingMode, String?, String?, @escaping (Result<Game, Error>) -> Void) -> Void
    var onChoose: (String) -> Void
    var onCancel: () -> Void
    @Binding var codeShareInitialTab: Int
    @Binding var showCodeShareSheet: Bool
    @Binding var shareCode: String
    @Binding var codeShareSheetID: UUID
    @Binding var showCodeShareModePicker: Bool
    var isDemoMode: Bool = false
    var onRequireSignIn: () -> Void = {}
    @Binding var games: [Game]
    @State private var showAddGamePopover: Bool = false
    @State private var newOpponentName: String = ""
    @State private var newGameDate: Date = Date()
    @State private var newGameTrackingMode: TrackingMode = .coach
    @State private var newGameTeamId: String? = nil
    @State private var newGameOpponentTeamId: String? = nil
    /// Loaded once when the add-game card is opened; this sheet is the boot
    /// picker and has no other reason to know about teams.
    @State private var myTeamsForNewGame: [Team] = []

    @State private var createGameError: String? = nil
    @State private var pendingDeleteGameId: String? = nil
    @State private var pendingDeleteGameName: String = ""
    @State private var showDeleteGameConfirm: Bool = false
    @State private var showFinalDeleteGameConfirm: Bool = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager

    private var activeGames: [Game] {
        games
            .filter { !$0.isArchived }
            .sorted(by: { $0.date > $1.date })
    }

    private var archivedGames: [Game] {
        games
            .filter { $0.isArchived }
            .sorted(by: { $0.date > $1.date })
    }

    @ViewBuilder
    private func gameRow(for game: Game) -> some View {
        // A row with no id yet is a just-created placeholder still waiting
        // on its real id from Firestore (see AddGameCard's onSave) - tapping
        // it used to reload everything and guess which game you meant by
        // matching opponent name + date, which could resolve to the wrong
        // game (e.g. a same-named game you'd just deleted, mid-cascade) or
        // nothing at all, and either way silently failed to enter anything.
        // Disabling the row for that brief window instead is honest about
        // what's happening and never guesses.
        let isStillSaving = (game.id ?? "").isEmpty
        HStack {
            Button(action: {
                guard let gid = game.id, !gid.isEmpty else { return }
                onChoose(gid)
                dismiss()
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(game.opponent)
                            .font(.headline)
                        if isStillSaving {
                            Label("Saving…", systemImage: "icloud.and.arrow.up")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(Self.formatter.string(from: game.date))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if game.isArchived {
                            Label("Archived", systemImage: "archivebox")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .disabled(isStillSaving)
            .opacity(isStillSaving ? 0.6 : 1.0)

            Spacer(minLength: 12)

            Menu {
                if game.isArchived {
                    Button {
                        if isDemoMode {
                            onRequireSignIn()
                            return
                        }
                        guard let id = game.id, !id.isEmpty else { return }
                        authManager.unarchiveGame(gameId: id)
                        if let idx = games.firstIndex(where: { $0.id == id }) {
                            games[idx].archivedAt = nil
                        }
                    } label: {
                        Label("Unarchive Game", systemImage: "archivebox")
                    }
                } else {
                    Button {
                        if isDemoMode {
                            onRequireSignIn()
                            return
                        }
                        guard let id = game.id, !id.isEmpty else { return }
                        authManager.archiveGame(gameId: id)
                        if let idx = games.firstIndex(where: { $0.id == id }) {
                            games[idx].archivedAt = Date()
                        }
                    } label: {
                        Label("Archive Game", systemImage: "archivebox")
                    }
                }

                Button(role: .destructive) {
                    if isDemoMode {
                        onRequireSignIn()
                        return
                    }
                    guard let id = game.id, !id.isEmpty else { return }
                    pendingDeleteGameId = id
                    pendingDeleteGameName = game.opponent
                    showDeleteGameConfirm = true
                } label: {
                    Label("Delete Game…", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let createGameError {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(createGameError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                        Spacer(minLength: 8)
                        Button("Dismiss") { self.createGameError = nil }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.plain)
                    }
                }

                if activeGames.isEmpty, archivedGames.isEmpty {
                    Text("No games yet. Tap “New Game” to create one.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                } else {
                    if !activeGames.isEmpty {
                        Section("Games") {
                            ForEach(activeGames) { game in
                                gameRow(for: game)
                            }
                        }
                    }

                    if !archivedGames.isEmpty {
                        Section("Archived Games") {
                            ForEach(archivedGames) { game in
                                gameRow(for: game)
                            }
                        }
                    }
                }
            }
            .refreshable {
                authManager.loadGames { loaded in
                    self.games = mergePreservingUnsyncedGames(loaded: loaded, local: self.games)
                }
            }
            .onAppear {
                // Defends against a stale list after a delete elsewhere in
                // the app (this sheet otherwise only reflects whatever
                // games[] the parent happened to pass in when presenting
                // it) - a real symptom report was entering a DIFFERENT,
                // already-existing game also failing right after deleting
                // one, consistent with acting on a stale snapshot.
                //
                // Merged rather than assigned: this fires every time the
                // sheet is re-opened, so a straight assignment deleted a
                // game created moments earlier whose write hadn't landed.
                authManager.loadGames { loaded in
                    self.games = mergePreservingUnsyncedGames(loaded: loaded, local: self.games)
                }
            }
            .navigationTitle("Games")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Spacer()
                        Button {
                            if isDemoMode {
                                onRequireSignIn()
                                return
                            }
                            newGameTeamId = nil
                            newGameOpponentTeamId = nil
                            authManager.loadMyTeams { teams, _ in
                                myTeamsForNewGame = teams.map { $0.team }
                                // A coach with exactly one team shouldn't
                                // have to pick it every game.
                                if myTeamsForNewGame.count == 1 {
                                    newGameTeamId = myTeamsForNewGame.first?.id
                                }
                            }
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
        .appConfirmationDialog(
            isPresented: $showDeleteGameConfirm,
            title: "Delete Game?",
            message: pendingDeleteGameName.isEmpty
                ? "This will remove the game and its lineup."
                : "This will remove \"\(pendingDeleteGameName)\" and its lineup.",
            primaryTitle: "Continue",
            primaryRole: .destructive,
            primaryAction: {
                showFinalDeleteGameConfirm = true
            },
            secondaryTitle: "Cancel",
            secondaryAction: {
                pendingDeleteGameId = nil
                pendingDeleteGameName = ""
            }
        )
        .appConfirmationDialog(
            isPresented: $showFinalDeleteGameConfirm,
            title: "Delete Game and Stats?",
            message: pendingDeleteGameName.isEmpty
                ? "This will permanently delete the game, all pitch events for that game, and pitcher stats linked to it. This cannot be undone."
                : "This will permanently delete \"\(pendingDeleteGameName)\", all pitch events for that game, and pitcher stats linked to it. This cannot be undone.",
            primaryTitle: "Delete Everything",
            primaryRole: .destructive,
            primaryAction: {
                if let id = pendingDeleteGameId {
                    if let idx = games.firstIndex(where: { $0.id == id }) {
                        games.remove(at: idx)
                    }
                    authManager.deleteGameCascade(gameId: id) { result in
                        if case .failure(let error) = result {
                            debugLog("❌ deleteGameCascade failed:", error.localizedDescription)
                        }
                    }
                    NotificationCenter.default.post(name: .gameOrSessionDeleted, object: nil, userInfo: ["type": "game", "gameId": id])
                }
                pendingDeleteGameId = nil
                pendingDeleteGameName = ""
            },
            secondaryTitle: "Cancel",
            secondaryAction: {
                pendingDeleteGameId = nil
                pendingDeleteGameName = ""
            }
        )
        .overlay(
            Group {
                if showAddGamePopover {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .onTapGesture { showAddGamePopover = false }
                        
                        // The card grew two team pickers and an inline
                        // create-team form, so it can now be taller than
                        // the screen. Unconditionally scrollable rather
                        // than gated on a height threshold - the same
                        // mistake the tracker's own ScrollView fallback
                        // already made once (see CLAUDE.md).
                        ScrollView {
                        AddGameCard(
                            opponentName: $newOpponentName,
                            gameDate: $newGameDate,
                            trackingMode: $newGameTrackingMode,
                            myTeams: myTeamsForNewGame,
                            ourTeamId: $newGameTeamId,
                            opponentTeamId: $newGameOpponentTeamId,
                            onCreateTeam: { name, designation, completion in
                                authManager.createTeam(name: name, designation: designation) { result in
                                    switch result {
                                    case .success(let team):
                                        myTeamsForNewGame.append(team)
                                        completion(team)
                                    case .failure(let error):
                                        debugLog("❌ createTeam from AddGameCard failed:", error.localizedDescription)
                                        completion(nil)
                                    }
                                }
                            },
                            onCancel: { showAddGamePopover = false },
                            onSave: {
                                let name = newOpponentName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !name.isEmpty else { return }
                                var item = Game(opponent: name, date: newGameDate, jerseyNumbers: [], trackingMode: newGameTrackingMode)
                                item.teamId = newGameTeamId
                                item.awayTeamId = newGameOpponentTeamId
                                games.append(item)
                                showAddGamePopover = false
                                // Keep the game selection sheet open; do not dismiss here.
                                let placeholderDate = newGameDate
                                // Remembers the id handed back by the local
                                // write, so a rejection arriving afterwards can
                                // still find the row - by then it is no longer
                                // the id-less placeholder this started as.
                                var stampedId: String? = nil
                                onCreate(name, placeholderDate, newGameTrackingMode, newGameTeamId, newGameOpponentTeamId) { result in
                                    let rowIndex = games.firstIndex(where: { candidate in
                                        if let stampedId, candidate.id == stampedId { return true }
                                        return candidate.id == nil
                                            && candidate.opponent == name
                                            && Calendar.current.isDate(candidate.date, inSameDayAs: placeholderDate)
                                    })
                                    switch result {
                                    case .success(let saved):
                                        // Swap the placeholder for the real,
                                        // id-stamped game so the row becomes
                                        // openable - the tap handler no longer
                                        // has to guess by matching name/date.
                                        stampedId = saved.id
                                        if let rowIndex {
                                            games[rowIndex] = saved
                                        } else {
                                            games.append(saved)
                                        }
                                        createGameError = nil
                                    case .failure(let error):
                                        // Backend actually rejected it, so the
                                        // game does not exist. Take the row back
                                        // out rather than leaving one that opens
                                        // into nothing, and say why.
                                        if let rowIndex {
                                            games.remove(at: rowIndex)
                                        }
                                        createGameError = "Couldn't save \"\(name)\": \(error.localizedDescription)"
                                        debugLog("❌ create game failed:", error.localizedDescription)
                                    }
                                }
                            }
                        )
                        .frame(maxWidth: 360)
                        .padding()
                        }
                        .scrollBounceBehavior(.basedOnSize)
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

// MARK: - Strike zone corner overlays
//
// These five were computed properties / a method on PitchTrackerView, and
// between them they crashed on launch EIGHT times with the same runtime
// metadata signature (`swift_getTypeByMangledName` → `resolveOpaqueType` →
// `_findExtendedTypeContextDescriptor` → `buildDescriptorPath`), each fix
// just moving the crash to whichever sibling was next to be resolved.
//
// Erasing to AnyView after every modifier, and pre-warming at the top of
// `body`, both failed as general cures - `batterSideOverlay` was already
// fully erased to AnyView and crashed anyway. The reason: the runtime isn't
// struggling with chain *length*, it's walking the enclosing type's
// descriptor path, and the enclosing type is a 14,500-line view with an
// enormous generic/opaque context. Every `some View` member declared in
// there inherits that context.
//
// Extracting them to top-level structs removes the context entirely: each
// body is now a small concrete type resolved in its own shallow descriptor
// path, with nothing of PitchTrackerView in its mangled name. This is the
// same shape `StrikeZoneCard` (the card these decorate) already had - and
// that one never crashed, which is the clue that mattered.
//
// Keep new strike-zone decorations as structs here. Do not move them back
// to computed properties on PitchTrackerView.

// MARK: - "Still needs picking" flashes
//
// These replaced the pitcher/grid-key confirmation sheet that used to gate
// game entry (see `requestGameConfirmation`). Entering a game no longer
// asks; the tracker flashes for whichever of the two is missing.
//
// Each owns its own `@State` pulse, and that is the whole point of them
// being structs. A pulse driven from `PitchTrackerView`'s own state
// invalidates all ~15k lines of that view on every tick - which is exactly
// what `atBatPulse` does, listed in CLAUDE.md as a real performance defect.
// Confined here, each tick redraws one small concrete view. Same reasoning
// as the strike-zone decorations below; don't fold these back into
// computed properties on PitchTrackerView.

/// The shared pulse timing, so the two badges can't drift apart.
private enum MissingSelectionPulse {
    static let fade: Double = 0.7
    /// Must outlast `fade`, or toggles pile up on each other mid-animation.
    static let tick: UInt64 = 750_000_000
    static let dimmed: Double = 0.3
}

/// Flashes in the pitcher button while the active game has no pitcher
/// selected.
struct MissingPitcherBadge: View {
    var size: CGFloat = 44
    @State private var pulse = false

    var body: some View {
        Image(systemName: "person.crop.circle.badge.plus")
            .font(.system(size: size * 0.62, weight: .semibold))
            .foregroundStyle(Color.red)
            .frame(width: size, height: size)
            .opacity(pulse ? 1.0 : MissingSelectionPulse.dimmed)
            .task {
                pulse = false
                while !Task.isCancelled {
                    withAnimation(.easeInOut(duration: MissingSelectionPulse.fade)) {
                        pulse.toggle()
                    }
                    try? await Task.sleep(nanoseconds: MissingSelectionPulse.tick)
                }
            }
            .accessibilityLabel("No pitcher selected. Tap to choose one.")
    }
}

/// The pitcher button's avatar slot: the portrait, or the flash. One struct
/// for the branch so it doesn't add another `_ConditionalContent` layer to
/// `PitchTrackerView`'s opaque context.
struct PitcherAvatarOrMissingBadge: View {
    let pitcher: Pitcher?
    let needsSelection: Bool
    var size: CGFloat = 44

    var body: some View {
        if needsSelection {
            MissingPitcherBadge(size: size)
        } else {
            PitcherAvatarView(pitcher: pitcher, size: size)
        }
    }
}

/// The top bar's Key capsule contents: the current key's name and version
/// pill, or a flashing `key.slash` when this game has no key of its own.
struct TopBarKeyLabel: View {
    let prefix: String
    let name: String
    let versionLabel: String
    let showVersion: Bool
    let needsKey: Bool

    @State private var pulse = false

    var body: some View {
        if needsKey {
            HStack(spacing: 5) {
                Image(systemName: "key.slash")
                    .font(.subheadline.weight(.bold))
                Text("Key")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.red)
            .opacity(pulse ? 1.0 : MissingSelectionPulse.dimmed)
            .task {
                pulse = false
                while !Task.isCancelled {
                    withAnimation(.easeInOut(duration: MissingSelectionPulse.fade)) {
                        pulse.toggle()
                    }
                    try? await Task.sleep(nanoseconds: MissingSelectionPulse.tick)
                }
            }
            .accessibilityLabel("No grid key chosen for this game. Tap to choose one.")
        } else {
            HStack(spacing: 6) {
                Text(prefix + name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .foregroundStyle(Color.accentColor)
                if showVersion && !versionLabel.isEmpty {
                    Text(versionLabel)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .foregroundStyle(Color.gray)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Capsule())
                        .accessibilityLabel("Template version \(versionLabel)")
                }
            }
        }
    }
}

/// Why the tracker is blurred, and the one button that fixes it. Shown over
/// the content section when the account has no code grid key at all - that
/// state blurs the section *and* turns off its hit-testing, so without this
/// the coach is looking at a dead screen whose only explanation is a dimmed
/// "Select a template" capsule over a menu item that's disabled.
///
/// Deliberately not a "dismiss" affordance: there is nothing to dismiss to.
/// The Home tab underneath is still live, so this is a shortcut to the fix
/// rather than the only escape.
struct NoCodeGridKeyBlocker: View {
    /// Keys exist, they're just all archived - a local hide, so the fix is
    /// to unarchive one rather than build another from scratch.
    let allArchived: Bool
    let onOpenKeys: () -> Void

    private var title: String {
        allArchived ? "No Active Code Grid Key" : "No Code Grid Key Yet"
    }

    private var message: String {
        allArchived
        ? "All of your keys are archived. Unarchive one, or make a new key."
        : "The tracker needs a key before it can call or record a pitch."
    }

    private var actionTitle: String {
        allArchived ? "Open Code Grid Keys" : "Create a Key"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.slash")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.red)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onOpenKeys) {
                Label(actionTitle, systemImage: "key.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.pitchMarkActiveGray))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(22)
        .frame(maxWidth: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 6)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
    }
}

/// The "vs. opponent" bubble at the zone's bottom edge.
private struct ZoneOpponentLabel: View {
    let opponentName: String?

    var body: some View {
        Text("vs. \(opponentName ?? "Game")")
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.primary)
            .frame(maxWidth: 130, alignment: .center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
    }
}

/// Bottom-left corner: text-only Reset, sized to the shared corner block
/// height so it lines up with Undo on the opposite corner.
private struct ZoneResetButton: View {
    let blockHeight: CGFloat
    let onReset: () -> Void

    var body: some View {
        Button(action: onReset) {
            Text("Reset")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.red)
                .padding(6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reset pitch selection")
        .frame(height: blockHeight, alignment: .top)
        .offset(y: -115)
    }
}

/// Bottom-right corner, mirroring `ZoneResetButton`.
/// The confirm dialog lives at baseBody's root, not in here - see the note
/// at its attachment site.
private struct ZoneUndoButton: View {
    let blockHeight: CGFloat
    let isDisabled: Bool
    @Binding var showConfirm: Bool

    var body: some View {
        Button {
            showConfirm = true
        } label: {
            Text("Undo last pitch")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 70)
                .fixedSize(horizontal: false, vertical: true)
                .padding(6)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel("Undo Last Pitch")
        .frame(height: blockHeight, alignment: .top)
        .offset(y: -115)
    }
}

/// Bottom-right: the game stats / game summary pair. Renders nothing
/// outside game mode.
/// Takes bindings, not closures, deliberately: a closure written inline in
/// `strikeZoneArea` captures `self`, and `self` is a struct with hundreds of
/// stored properties, so each one costs a full by-value copy of
/// PitchTrackerView on that function's stack frame. A Binding captures only
/// the @State box. See the stack-frame note on `strikeZoneArea`.
private struct ZoneGameStatsButtons: View {
    let isGame: Bool
    @Binding var showStats: Bool
    @Binding var showSummary: Bool

    var body: some View {
        if isGame {
            HStack(spacing: 8) {
                Button(action: { showStats = true }) {
                    Image(systemName: "chart.bar")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Game Stats")

                Button(action: { showSummary = true }) {
                    Image(systemName: "doc.text")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Game Summary")
            }
        }
    }
}

/// Left/right batter icons flanking the zone, plus scout mode's in-play
/// chevron under the left one.
private struct BatterSideOverlay: View {
    let SZwidth: CGFloat
    var verticalOffset: CGFloat = -20
    let batterSide: BatterSide
    let showsScoutInPlayIndicator: Bool
    let onSelect: (BatterSide) -> Void

    private let iconSize: CGFloat = 36

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    onSelect(.left)
                } label: {
                    Image("rightBatterIcon")
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: iconSize, height: iconSize)
                        .foregroundColor(batterSide == .left ? .primary : .gray.opacity(0.4))
                }
                .buttonStyle(.plain)

                if showsScoutInPlayIndicator {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.green)
                        .frame(width: iconSize, alignment: .center)
                        .offset(y: 80)
                }
            }

            Spacer()

            Button {
                onSelect(.right)
            } label: {
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
        .offset(y: verticalOffset)
    }
}

struct GameItem: Identifiable {
    let id = UUID()
    var opponent: String
    var date: Date
}


/// Both sides of the game are picked here now. Opponent used to be a free
/// text field, which meant every opponent was a throwaway string and their
/// roster had to be built later from inside the tracker; it's a Team like
/// ours is, with the same picker and an inline "New Team" escape hatch for
/// an opponent you haven't met yet.
///
/// `opponentName` is still the binding the callers save onto `Game.opponent`
/// - it's kept in sync with the chosen team's name rather than replaced, so
/// every existing read of `game.opponent` (row titles, live-session labels,
/// delete confirmations) keeps working untouched.
struct AddGameCard: View {
    @Binding var opponentName: String
    @Binding var gameDate: Date
    @Binding var trackingMode: TrackingMode
    /// Every team the signed-in user is on - the candidate pool for BOTH
    /// sides. Can legitimately be empty on a brand-new account, in which
    /// case both pickers offer only "New Team…".
    var myTeams: [Team] = []
    @Binding var ourTeamId: String?
    @Binding var opponentTeamId: String?
    /// Creates a Team and hands it back, or nil on failure. The card has no
    /// Firestore access of its own; the presenting view owns the write.
    var onCreateTeam: (String, TeamDesignation, @escaping (Team?) -> Void) -> Void
    var onCancel: () -> Void
    var onSave: () -> Void

    /// Which side's "New Team…" is currently expanded, if either. One at a
    /// time: the inline form is tall, and two open at once would push Save
    /// off the bottom of the card.
    private enum NewTeamTarget { case ours, opponent }
    @State private var newTeamTarget: NewTeamTarget? = nil
    @State private var newTeamName: String = ""
    @State private var newTeamDesignation = TeamDesignationDraft()
    @State private var isCreatingTeam = false
    @State private var createTeamError: String? = nil

    private func team(_ id: String?) -> Team? {
        guard let id else { return nil }
        return myTeams.first(where: { $0.id == id })
    }

    /// A team can't be both sides of the same game.
    private func candidates(excluding excludedId: String?) -> [Team] {
        myTeams.filter { $0.id != excludedId || excludedId == nil }
    }

    private var canSave: Bool {
        !opponentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && newTeamTarget == nil
            && !isCreatingTeam
    }

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

            teamPickerRow(
                title: "Our team",
                selectedId: ourTeamId,
                options: candidates(excluding: opponentTeamId),
                onSelect: { ourTeamId = $0 },
                onClear: { ourTeamId = nil },
                onAddNew: { beginNewTeam(.ours) }
            )

            teamPickerRow(
                title: "Opponent",
                selectedId: opponentTeamId,
                options: candidates(excluding: ourTeamId),
                onSelect: { id in
                    opponentTeamId = id
                    // Keep Game.opponent in step with the chosen team.
                    opponentName = team(id)?.name ?? opponentName
                },
                onClear: {
                    opponentTeamId = nil
                    opponentName = ""
                },
                onAddNew: { beginNewTeam(.opponent) }
            )

            if newTeamTarget != nil {
                newTeamInlineForm
            }

            DatePicker("Date & Time", selection: $gameDate, displayedComponents: [.date, .hourAndMinute])

            Picker("Tracking", selection: $trackingMode) {
                ForEach(TrackingMode.allCases, id: \.rawValue) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 10)
    }

    private func beginNewTeam(_ target: NewTeamTarget) {
        newTeamName = ""
        newTeamDesignation.reset()
        createTeamError = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            newTeamTarget = target
        }
    }

    private func cancelNewTeam() {
        withAnimation(.easeInOut(duration: 0.2)) {
            newTeamTarget = nil
        }
        newTeamName = ""
        newTeamDesignation.reset()
        createTeamError = nil
    }

    private func commitNewTeam() {
        let name = newTeamName.trimmingCharacters(in: .whitespaces)
        guard let target = newTeamTarget,
              !name.isEmpty,
              let designation = newTeamDesignation.designation,
              !isCreatingTeam
        else { return }

        isCreatingTeam = true
        createTeamError = nil
        onCreateTeam(name, designation) { created in
            isCreatingTeam = false
            guard let created, let id = created.id else {
                createTeamError = "Couldn't create \"\(name)\". Try again."
                return
            }
            switch target {
            case .ours:
                ourTeamId = id
            case .opponent:
                opponentTeamId = id
                opponentName = created.name
            }
            cancelNewTeam()
        }
    }

    @ViewBuilder
    private var newTeamInlineForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(newTeamTarget == .ours ? "New Team (ours)" : "New Opponent Team")
                .font(.subheadline.weight(.semibold))

            TextField("Team name", text: $newTeamName)
                .textFieldStyle(.roundedBorder)

            TeamDesignationForm(draft: $newTeamDesignation, showsTitle: false)

            if let createTeamError {
                Text(createTeamError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { cancelNewTeam() }
                Button(isCreatingTeam ? "Creating…" : "Create Team") { commitNewTeam() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        newTeamName.trimmingCharacters(in: .whitespaces).isEmpty
                            || !newTeamDesignation.isComplete
                            || isCreatingTeam
                    )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
        )
    }

    private func teamPickerRow(
        title: String,
        selectedId: String?,
        options: [Team],
        onSelect: @escaping (String?) -> Void,
        onClear: @escaping () -> Void,
        onAddNew: @escaping () -> Void
    ) -> some View {
        let selected = team(selectedId)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                Menu {
                    ForEach(options, id: \.id) { option in
                        Button {
                            onSelect(option.id)
                        } label: {
                            Text(option.displayNameWithDesignation)
                        }
                    }
                    Divider()
                    Button {
                        onAddNew()
                    } label: {
                        Label("New Team…", systemImage: "plus.circle")
                    }
                    if selectedId != nil {
                        Button("Clear", action: onClear)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selected?.name ?? "Select")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected == nil ? Color.secondary : Color.primary)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(selected == nil ? Color(.systemGray6) : Color.pitchMarkActiveGray.opacity(0.12))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(selected == nil ? Color(.systemGray4) : Color.pitchMarkActiveGray.opacity(0.45), lineWidth: 1)
                    )
                    .contentShape(Capsule(style: .continuous))
                }
                Spacer(minLength: 0)
            }

            if let designation = selected?.designation {
                Text(designation.inlineText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 90)
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

extension View {
    func erasedToAnyView() -> AnyView {
        AnyView(self)
    }
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
