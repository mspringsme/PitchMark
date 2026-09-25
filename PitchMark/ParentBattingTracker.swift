//
//  ParentBattingTracker.swift
//  PitchMark
//
//  Phase 5 of the 2026-09-24 Coach/Parent/Family direction: record what the
//  opposing pitcher threw to my child while batting. Same tap/estimate/save
//  flow as ParentPitchingTracker.swift (Phase 4) - reused deliberately
//  rather than refactored into a shared component yet; see the Phase 5 plan
//  for why. The opposing pitcher is identified by a plain typed name, not a
//  new entity - a parent doesn't need to register the other team's pitcher
//  anywhere for this to be useful. Deliberately kept out of the Pitchmark
//  Display target's membershipExceptions; Display has no use for this UI.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

private func defaultParentPitchTemplate() -> PitchTemplate {
    PitchTemplate(
        id: UUID(),
        name: "Parent Default",
        pitches: ["Fastball", "Changeup", "Curveball", "Other"],
        codeAssignments: []
    )
}

struct ParentBattingTrackerView: View {
    let player: TeamPlayer
    let teamId: String

    @EnvironmentObject var authManager: AuthManager

    private let template = defaultParentPitchTemplate()

    @State private var opposingPitcherName: String = ""
    @State private var confirmedPitcherName: String? = nil
    @State private var previousEventCount: Int? = nil
    @State private var batterSide: BatterSide = .right

    @State private var lastTappedPosition: CGPoint? = nil
    @State private var calledPitch: PitchCall? = nil
    @State private var showResultSheet = false
    @State private var pendingResultLabel: String? = nil
    @State private var isGameConstant = true

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
            opposingPitcherField

            if confirmedPitcherName != nil {
                HStack {
                    Text("Count: \(count.displayText)")
                        .font(.headline)
                    Spacer()
                    Text("\(sessionEvents.count) pitch\(sessionEvents.count == 1 ? "" : "es") this session")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let previousEventCount, previousEventCount > 0 {
                    Text("\(previousEventCount) pitch\(previousEventCount == 1 ? "" : "es") recorded vs \(confirmedPitcherName ?? "") previously")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Batter Side", selection: $batterSide) {
                    ForEach(BatterSide.allCases) { side in
                        Text(side.rawValue.capitalized).tag(side)
                    }
                }
                .pickerStyle(.segmented)

                Text("Tap where the pitch went.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                StrikeZoneView(
                    width: 300,
                    height: 260,
                    isGame: $isGameConstant,
                    batterSide: batterSide,
                    lastTappedPosition: lastTappedPosition,
                    setLastTapped: { lastTappedPosition = $0 },
                    calledPitch: calledPitch,
                    setCalledPitch: { newCall in
                        calledPitch = newCall
                        showCatcherEstimate = (newCall != nil)
                    },
                    selectedPitches: Set(template.pitches),
                    gameIsActive: true,
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
            } else {
                Text("Enter the opposing pitcher's name to start recording.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showCatcherEstimate, onDismiss: presentResultSheetIfPending) {
            if let call = calledPitch {
                CatcherEstimateView(
                    resultCall: call,
                    batterSide: batterSide,
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
                batterSide: batterSide,
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
                pitcherName: confirmedPitcherName
            )
        }
    }

    @ViewBuilder
    private var opposingPitcherField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Opposing Pitcher")
                .font(.headline)
            HStack {
                TextField("Pitcher's name", text: $opposingPitcherName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(confirmedPitcherName != nil)
                if confirmedPitcherName == nil {
                    Button("Start") {
                        confirmPitcherName()
                    }
                    .disabled(opposingPitcherName.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    Button("Change") {
                        confirmedPitcherName = nil
                        previousEventCount = nil
                        opposingPitcherName = ""
                    }
                }
            }
        }
    }

    private func confirmPitcherName() {
        let name = opposingPitcherName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        confirmedPitcherName = name
        authManager.loadOpposingPitcherEvents(teamId: teamId, playerId: player.id ?? "", opposingPitcherName: name) { events in
            previousEventCount = events.count
        }
    }

    /// Same dismiss-then-present idiom used throughout this codebase for
    /// chaining one sheet into the next (SettingsView.rejoinLiveSession,
    /// HomeAreaTabBar, ParentPitchingTracker's identical flow).
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
        guard let pitcherName = confirmedPitcherName else { return }
        var event = event
        let facts = AtBatCountRules.PitchFacts(event: event)
        let (newCount, terminal) = AtBatCountRules.apply(facts, to: count)
        event.applyCount(newCount, terminal: terminal)
        count = terminal == nil ? newCount : .start

        sessionEvents.append(event)
        authManager.saveOpposingPitcherEvent(
            teamId: teamId,
            playerId: player.id ?? "",
            opposingPitcherName: pitcherName,
            event: event
        ) { _ in }

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
    /// Grouped by opposing-pitcher name in the path itself, so "previous
    /// at-bats vs this pitcher" falls out of the path with no extra model -
    /// no formal opponent entity, just a plain typed name. Covered by the
    /// existing `/users/{userId}/{docPath=**}` catch-all rule.
    func saveOpposingPitcherEvent(teamId: String, playerId: String, opposingPitcherName: String, event: PitchEvent, completion: @escaping (Error?) -> Void) {
        guard let user = user, !playerId.isEmpty, !opposingPitcherName.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        let resolvedId = {
            let raw = event.id?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty == false) ? raw! : UUID().uuidString
        }()

        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("teamPlayerBattingEvents").document(playerId)
            .collection("pitchers").document(opposingPitcherName)
            .collection("events").document(resolvedId)

        do {
            try ref.setData(from: event) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }

    func loadOpposingPitcherEvents(teamId: String, playerId: String, opposingPitcherName: String, completion: @escaping ([PitchEvent]) -> Void) {
        guard let user = user, !playerId.isEmpty, !opposingPitcherName.isEmpty else {
            completion([])
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("teamPlayerBattingEvents").document(playerId)
            .collection("pitchers").document(opposingPitcherName)
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
