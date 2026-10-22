//
//  TrackerUIState.swift
//  PitchMark
//
//  Step 1 of shrinking PitchTrackerView (2026-10-21).
//
//  PitchTrackerView declared 267 `@State` properties, which made the struct a
//  ~3.2 KB value. SwiftUI copies a view's value all over the render path, and
//  every one of those copies is a `outlined init with copy of
//  PitchTrackerView` of that size on the stack - the app was overflowing the
//  main thread's stack intermittently (EXC_BAD_ACCESS code=2 at the guard
//  page). `State<T>` costs roughly `sizeof(T) + 8`, so the cheap-looking
//  flags dominated the total.
//
//  These 153 pure-presentation properties (sheet/alert flags, text-entry
//  strings, selected-id optionals) now live here, in a class, which is heap
//  allocated - PitchTrackerView holds one 8-byte reference to it instead of
//  153 inline boxes.
//
//  No behaviour change is intended: `@State` on PitchTrackerView already
//  invalidated the whole of PitchTrackerView on every change, and a single
//  @Published object does exactly the same, so invalidation granularity is
//  unchanged.
//
//  PitchTrackerView keeps a same-named forwarding computed property for each
//  of these, so the ~1050 plain `foo` reads/writes across the file needed no
//  edit at all; only the 94 `$foo` binding sites became `$ui.foo`.
//
//  Deliberately NOT in the "Pitchmark Display" target's membershipExceptions -
//  PitchTrackerView isn't either.
//

import SwiftUI
import Combine

final class TrackerUIState: ObservableObject {
    /// Callers waiting on the in-flight `ensurePrimarySessionOrPrompt` read.
    /// Deliberately NOT @Published - it is plumbing, not view state, and
    /// publishing it would invalidate the whole tracker on every check.
    var pendingPrimarySessionChecks: [(Bool) -> Void] = []

    @Published var didAutoDismissCodeSheetForLiveId: String? = nil
    @Published var uiConnected: Bool = false
    @Published var showCodeAssignmentSheet: Bool = false
    @Published var pitcherName: String = ""
    @Published var lastObservedPendingCallId: String? = nil
    @Published var selectedCode: String = ""
    @Published var selectedPitch: String = ""
    @Published var selectedLocation: String = ""
    @Published var gameIsActive: Bool = false
    @Published var showProfile: Bool = false
    @Published var showProfileSheet: Bool = false
    @Published var showSignOutConfirmation: Bool = false
    @Published var showTemplateEditor: Bool = false
    @Published var showInviteJoinSheet: Bool = false
    @Published var inviteJoinText: String = ""
    @Published var inviteJoinError: String? = nil
    @Published var showProPaywall: Bool = false
    @Published var showProGateAlert: Bool = false
    @Published var proGateMessage: String = ""
    @Published var showDemoLoginWall: Bool = false
    @Published var demoLoginWallMessage: String = "Sign in to save your own teams, pitchers, and grid keys."
    @Published var showCameraPicker: Bool = false
    @Published var showCameraUnavailableAlert: Bool = false
    @Published var showCameraPermissionAlert: Bool = false
    @Published var showQRScanner: Bool = false
    @Published var showGridKeySheet: Bool = false
    @Published var showCallingPitchesPrompt: Bool = false
    @Published var selectedPitcherId: String? = nil
    @Published var showSetOpponentSheet: Bool = false
    @Published var newOpponentTeamName: String = ""
    @Published var activeAwayTeamName: String = ""
    @Published var newAwayPitcherName: String = ""
    @Published var activeHomeTeamName: String = ""
    @Published var showSetMyTeamSheet: Bool = false
    @Published var newMyTeamName: String = ""
    @Published var showChooseBattersStep: Bool = false
    @Published var teamSetupShouldFlipSide: Bool = true
    @Published var showQuickAddPlayerSheet: Bool = false
    @Published var quickAddPlayerName: String = ""
    @Published var quickAddPlayerJersey: String = ""
    @Published var quickAddTeamId: String? = nil
    @Published var selectedHitterId: String? = nil
    @Published var showAtBatAddMenu: Bool = false
    @Published var showAtBatRosterPickerSheet: Bool = false
    @Published var isRecordingResult: Bool = false
    @Published var activeCalledPitchId: String? = nil
    @Published var actualLocationRecorded: String? = nil
    @Published var resultVisualState: String? = nil
    @Published var pendingResultLabel: String? = nil
    @Published var catcherEstimateDismissed: Bool = true
    @Published var catcherEstimateDraftPitch: String = "Catcher"
    @Published var catcherEstimateDraftLocation: String? = nil
    @Published var autoPitchOnlyEnabled: Bool = false
    @Published var showResultConfirmation: Bool = false
    @Published var joinedSessionDetailsSyncedForLiveId: String? = nil
    @Published var showPitchResults: Bool = false
    @Published var showCardsFullScreenSheet: Bool = false
    @Published var cardsEditTargetEventID: String? = nil
    @Published var showConfirmSheet: Bool = false
    @Published var showUndoConfirm: Bool = false
    @Published var isStrikeSwinging: Bool = false
    @Published var isStrikeLooking: Bool = false
    @Published var isWildPitch: Bool = false
    @Published var isPassedBall: Bool = false
    @Published var isBall: Bool = false
    @Published var isCalledPitchViewVisible: Bool = false
    @Published var shouldBlurBackground: Bool = false
    @Published var isGame: Bool = false
    @Published var selectedOutcome: String? = nil
    @Published var selectedDescriptor: String? = nil
    @Published var isError: Bool = false
    @Published var showGameSheet: Bool = false
    @Published var showGameStatsSheet: Bool = false
    @Published var showGameSummarySheet: Bool = false
    @Published var showGameSummaryShareSheet: Bool = false
    @Published var opponentName: String? = nil
    @Published var selectedGameId: String? = nil
    @Published var showParticipantOverlay: Bool = false
    @Published var ownerTemplateName: String? = nil
    @Published var showAddJerseyPopover: Bool = false
    @Published var newJerseyNumber: String = ""
    @Published var showBulkJerseyPrompt: Bool = false
    @Published var showBulkJerseyInput: Bool = false
    @Published var bulkJerseyNumbers: String = ""
    @Published var showDummyLineupInput: Bool = false
    @Published var dummyLineupCount: String = ""
    @Published var showActivateNewBatterPrompt: Bool = false
    @Published var selectedBatterJersey: String? = nil
    @Published var showJerseyDetailSheet: Bool = false
    @Published var showNoJerseyEventsAlert: Bool = false
    @Published var noJerseyEventsMessage: String = ""
    @Published var showNextBatterAdjustmentAlert: Bool = false
    @Published var nextBatterAdjustmentMessage: String = "Adjust to next batter if needed"
    @Published var didAutoRetryJerseyDetail: Bool = false
    @Published var atBatPulse: Bool = false
    @Published var showAtBatHeatmapSheet: Bool = false
    @Published var selectedAtBatHeatmapPitch: String = ""
    @Published var showAllPitchesHeatmapPitchPicker: Bool = false
    @Published var showHeatmapUnavailablePitchAlert: Bool = false
    @Published var heatmapUnavailablePitchMessage: String = ""
    @Published var scoutInPlayOutcome: String? = nil
    @Published var scoutHitOnPlay: Bool = false
    @Published var scoutDescriptor: String? = nil
    @Published var scoutErrorOnPlay: Bool = false
    @Published var scoutMiscOutcome: String? = nil
    @Published var showScoutFieldMap: Bool = false
    @Published var scoutBattedBallRegionName: String? = nil
    @Published var savedPlayReviewTitle: String = "Saved Play"
    @Published var savedPlayReviewCountText: String = ""
    @Published var showResetConfirm: Bool = false
    @Published var isReorderingMode: Bool = false
    @Published var hasPresentedInitialSettings: Bool = false
    @Published var lastAuthenticatedUserId: String? = nil
    @Published var showTemplateChangeWarning: Bool = false
    @Published var pendingGameChoiceGameId: String? = nil
    @Published var pendingGameChoiceOwnerUid: String? = nil
    @Published var pendingConfirmationPitcherId: String? = nil
    @Published var isSelecting: Bool = false
    @Published var pitchFirst: Bool = true
    @Published var showCodeShareSheet: Bool = false
    @Published var showCodeShareModePicker: Bool = false
    @Published var inviteSheetDismissArmed: Bool = false
    @Published var showSelectGameFirstAlert: Bool = false
    @Published var showCodeShareErrorAlert: Bool = false
    @Published var codeShareErrorMessage: String = ""
    @Published var showGameEntryErrorAlert: Bool = false
    @Published var gameEntryErrorMessage: String = ""
    @Published var shareCode: String = ""
    @Published var displayOnlyLiveId: String? = nil
    @Published var showSessionConflictAlert: Bool = false
    @Published var showDisplayAppMissingAlert: Bool = false
    @Published var sessionCheckInProgress: Bool = false
    @Published var autoLiveCreateInProgress: Bool = false
    @Published var didAutoCreateLiveSessionForGameId: String? = nil
    @Published var activeGameOwnerUserId: String? = nil
    @Published var progressRevisionRoomId: String? = nil
    @Published var progressPublishScheduled: Bool = false
    @Published var lastObservedResultSelectionId: String? = nil
    @Published var isRestoringState: Bool = false
    @Published var showOutsFlash: Bool = false
    @Published var isJoiningSession: Bool = false
    @Published var pendingRestoreGameId: String? = nil
    @Published var pendingLiveTemplateId: String? = nil
    @Published var pendingLiveTemplateName: String? = nil
    @Published var liveTemplateOverrideLocked: Bool = false
    @Published var lastOutResetEventIdentity: String? = nil
    @Published var activeLiveId: String? = nil
    @Published var livePitcherId: String? = nil
    @Published var livePitcherName: String? = nil
    @Published var didHydrateLineupFromLive: Bool = false
    @Published var didSeedOwnerGameEventsForLive: Bool = false
    @Published var didSeedLivePitchEventsFromOwnerGame: Bool = false
    @Published var liveSessionRenewalInFlight: Bool = false
}
