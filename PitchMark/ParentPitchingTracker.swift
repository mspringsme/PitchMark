//
//  ParentPitchingTracker.swift
//  PitchMark
//
//  Phase 4 of the 2026-09-24 Coach/Parent/Family direction: a real
//  Parent/Pitching tracker. Reuses StrikeZoneView/PitchButton/
//  CatcherEstimateView/PitchResultSheetView/AtBatCountRules, and
//  deliberately mirrors the Coach tracker's "Catcher" flow specifically
//  (tap the location first, no forced pitch-type choice, optional pitch
//  guess afterward) - that's the flow that fits a parent who's just
//  watching, not calling pitches. Kept as its own independent view: no
//  shared UserDefaults keys, no LiveGameService, nothing that could
//  collide with the Coach's running PitchTrackerView instance - the
//  direction doc is explicit that Parent use is autonomous, not connected
//  to the coach. Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this UI.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

/// A simple default pitch set for a parent who isn't using a coach's Code
/// Grid Key template. Built entirely in memory, the same way
/// `PitchTrackerView.configureDemoMode()`'s `demoTemplate` is - no
/// Firestore round trip needed. `codeAssignments` is intentionally empty:
/// it only feeds the encrypted-code sheet, which this tracker never uses
/// (`isEncryptedMode: false` below). Only used as `pitchOptions` for the
/// post-tap pitch-type guess, per the Catcher flow.
private func defaultParentPitchTemplate() -> PitchTemplate {
    PitchTemplate(
        id: UUID(),
        name: "Parent Default",
        pitches: ["Fastball", "Changeup", "Curveball", "Other"],
        codeAssignments: []
    )
}

struct ParentPitchingTrackerView: View {
    let player: TeamPlayer
    let teamId: String

    @EnvironmentObject var authManager: AuthManager

    private let template = defaultParentPitchTemplate()

    @State private var lastTappedPosition: CGPoint? = nil
    @State private var calledPitch: PitchCall? = nil
    @State private var showResultSheet = false
    @State private var pendingResultLabel: String? = nil
    @State private var isGameConstant = true

    // Catcher-flow estimate step, shown right after the location tap and
    // before the result sheet - see CatcherEstimateView / catcherRealCall /
    // beginCatcherCoachCall in PitchTrackerView.swift for the pattern this
    // mirrors.
    @State private var showCatcherEstimate = false
    @State private var catcherEstimate: PitchCall? = nil
    @State private var catcherEstimateDraftPitch: String = "Catcher"
    @State private var catcherEstimateDraftLocation: String? = nil

    @State private var isStrikeSwinging = false
    @State private var isStrikeLooking = false
    @State private var isWildPitch = false
    @State private var isPassedBall = false
    @State private var isBall = false
    @State private var selectedOutcome: String? = nil
    @State private var selectedDescriptor: String? = nil
    @State private var isError = false

    @State private var count: AtBatCount = .start
    @State private var sessionEvents: [PitchEvent] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Count: \(count.displayText)")
                    .font(.headline)
                Spacer()
                Text("\(sessionEvents.count) pitch\(sessionEvents.count == 1 ? "" : "es") this session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Tap where the pitch went.")
                .font(.caption)
                .foregroundStyle(.secondary)

            StrikeZoneView(
                width: 300,
                height: 260,
                isGame: $isGameConstant,
                batterSide: .right,
                lastTappedPosition: lastTappedPosition,
                setLastTapped: { lastTappedPosition = $0 },
                calledPitch: calledPitch,
                setCalledPitch: { newCall in
                    calledPitch = newCall
                    showCatcherEstimate = (newCall != nil)
                },
                selectedPitches: Set(template.pitches),
                gameIsActive: true,
                // Always empty, same as beginCatcherCoachCall() - this is
                // what makes PitchButtonView build a "Catcher" placeholder
                // call straight from the tap, instead of requiring a
                // pitch-type be chosen first.
                selectedPitch: "",
                pitchCodeAssignments: template.codeAssignments,
                isRecordingResult: false,
                setIsRecordingResult: { _ in },
                setActualLocation: { _ in },
                actualLocationRecorded: nil,
                setSelectedPitch: { _ in },
                resultVisualState: nil,
                setResultVisualState: { _ in },
                pendingResultLabel: $pendingResultLabel,
                showResultConfirmation: .constant(false),
                showConfirmSheet: .constant(false),
                onResultLocationPicked: { _ in },
                onCatcherLocationTap: { },
                isEncryptedMode: false,
                template: template,
                canInitiateCall: true,
                forceOutlineButtons: false
            )
            .frame(maxWidth: .infinity, alignment: .center)

            if !sessionEvents.isEmpty {
                recentPitchesList
            }
        }
        .sheet(isPresented: $showCatcherEstimate, onDismiss: presentResultSheetIfPending) {
            if let call = calledPitch {
                CatcherEstimateView(
                    resultCall: call,
                    batterSide: .right,
                    pitchOptions: ["Catcher"] + template.pitches,
                    draftPitch: $catcherEstimateDraftPitch,
                    draftLocation: $catcherEstimateDraftLocation,
                    onReset: {
                        catcherEstimateDraftPitch = "Catcher"
                        catcherEstimateDraftLocation = nil
                    },
                    onSkip: {
                        catcherEstimate = nil
                        showCatcherEstimate = false
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
                        showCatcherEstimate = false
                    }
                )
                .padding()
            }
        }
        .sheet(isPresented: $showResultSheet) {
            PitchResultSheetView(
                isPresented: $showResultSheet,
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
                catcherEstimate: catcherEstimate,
                batterSide: .right,
                selectedTemplateId: template.id.uuidString,
                currentMode: .game,
                selectedGameId: nil,
                selectedOpponentJersey: nil,
                selectedOpponentBatterId: nil,
                allPitchEvents: sessionEvents,
                suggestedCountSeed: nil,
                currentCountSeed: (balls: count.balls, strikes: count.strikes),
                onCountChanged: { _, _ in },
                lineupBatters: [],
                selectedPitcherId: nil,
                saveAction: { event in
                    savePitch(event)
                },
                template: template,
                pitcherName: player.name
            )
        }
    }

    /// The catcher-estimate step always hands off to the result sheet next,
    /// whether the parent filled in a guess or skipped it - same
    /// dismiss-then-present idiom already used elsewhere in this codebase
    /// (SettingsView.rejoinLiveSession, HomeAreaTabBar's cross-sheet
    /// switching) rather than presenting a second sheet while the first is
    /// still tearing down.
    private func presentResultSheetIfPending() {
        guard calledPitch != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            showResultSheet = true
        }
    }

    @ViewBuilder
    private var recentPitchesList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This session")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(sessionEvents.suffix(5).reversed(), id: \.id) { event in
                Text("\(event.pitch) — \(event.location)\(event.atBatCount.map { " (\($0))" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func savePitch(_ event: PitchEvent) {
        var event = event
        let facts = AtBatCountRules.PitchFacts(event: event)
        let (newCount, terminal) = AtBatCountRules.apply(facts, to: count)
        event.applyCount(newCount, terminal: terminal)
        count = terminal == nil ? newCount : .start

        sessionEvents.append(event)
        authManager.saveTeamPlayerPitchEvent(teamId: teamId, playerId: player.id ?? "", event: event) { _ in }

        calledPitch = nil
        lastTappedPosition = nil
        pendingResultLabel = nil
        catcherEstimate = nil
        catcherEstimateDraftPitch = "Catcher"
        catcherEstimateDraftLocation = nil
        isStrikeSwinging = false
        isStrikeLooking = false
        isWildPitch = false
        isPassedBall = false
        isBall = false
        selectedOutcome = nil
        selectedDescriptor = nil
        isError = false
    }
}

// MARK: - AuthManager persistence

extension AuthManager {
    /// A parent's private pitch log for one child on one team. Kept separate
    /// from `savePitchEvent`'s flat `users/{uid}/pitchEvents` (already used
    /// by PitchTrackerView's own "no game selected" fallback) so the two
    /// don't get silently mixed together. Covered by the existing
    /// `/users/{userId}/{docPath=**}` catch-all rule - no new Firestore
    /// rules needed.
    func saveTeamPlayerPitchEvent(teamId: String, playerId: String, event: PitchEvent, completion: @escaping (Error?) -> Void) {
        guard let user = user, !playerId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        let resolvedId = {
            let raw = event.id?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty == false) ? raw! : UUID().uuidString
        }()

        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("teamPlayerPitchEvents").document(playerId)
            .collection("events").document(resolvedId)

        do {
            try ref.setData(from: event) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }

    func loadTeamPlayerPitchEvents(teamId: String, playerId: String, completion: @escaping ([PitchEvent]) -> Void) {
        guard let user = user, !playerId.isEmpty else {
            completion([])
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("teamPlayerPitchEvents").document(playerId)
            .collection("events")
            .order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                let events: [PitchEvent] = snapshot?.documents.compactMap { doc in
                    PitchEvent.decodeFirestoreDocument(doc)
                } ?? []
                completion(events)
            }
    }
}
