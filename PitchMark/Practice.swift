//
//  Practice.swift
//  PitchMark
//
//  Practice sessions (2026-11-20). From the New Game card: check Practice,
//  pick the player (required - anyone) and the pitches to work on, and the
//  tracker opens a pitch-calling screen with no at-bat view, scrolling or
//  game menus. Only the chosen pitches appear as chips for the session.
//
//  Revised 2026-11-20 (user's calls): there's no batter - the pitcher throws
//  to a catcher or a net - so a pitch is two taps: the target, then where it
//  went, and it saves on the second tap (Undo Last fixes a wrong tap). No
//  key is involved at all: no codes, no greyed spots, any pitch anywhere.
//  What's measured is accuracy against the target (PracticeGrid,
//  PracticeSummary).
//
//  Kept apart from games (user's call): a session is
//  users/{uid}/practiceSessions/{id}, its pitches its own pitchEvents
//  collection (PracticeRules paths). Nothing is written to a game, to the
//  pitcher's career record (pitchers/{pid}/pitchEvents) or to
//  users/{uid}/pitchEvents, so game and career stats never include practice.
//  It's reviewed separately: Home's Practice list → PracticeReviewView.
//  With no one signed in (demo, UI tests) sessions stay in memory.
//
//  Plain rules first, for unit tests; then the store and the screens.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Model

struct PracticeSession: Identifiable, Equatable, Hashable {
    var id: String
    var pitcherId: String
    var pitcherName: String
    var templateId: String?
    /// The pitches chosen for this session, in the key's order.
    var pitches: [String]
    var startedAt: Date
    var endedAt: Date?
    /// Archived sessions are hidden from Home's list until restored
    /// (2026-11-20). Deleting is separate and removes everything.
    var archivedAt: Date? = nil

    /// Every session is labeled so it can never be read as a game.
    static let label = "Practice"

    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "label": Self.label,
            "pitcherId": pitcherId,
            "pitcherName": pitcherName,
            "pitches": pitches,
            "startedAt": Timestamp(date: startedAt)
        ]
        data["templateId"] = templateId ?? NSNull()
        data["endedAt"] = endedAt.map { Timestamp(date: $0) } ?? NSNull()
        data["archivedAt"] = archivedAt.map { Timestamp(date: $0) } ?? NSNull()
        return data
    }

    init(id: String = UUID().uuidString, pitcherId: String, pitcherName: String, templateId: String?,
         pitches: [String], startedAt: Date = Date(), endedAt: Date? = nil) {
        self.id = id
        self.pitcherId = pitcherId
        self.pitcherName = pitcherName
        self.templateId = templateId
        self.pitches = pitches
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    init?(id: String, data: [String: Any]) {
        guard data["label"] as? String == Self.label,
              let pitcherId = data["pitcherId"] as? String else { return nil }
        self.init(id: id, pitcherId: pitcherId,
                  pitcherName: data["pitcherName"] as? String ?? "",
                  templateId: data["templateId"] as? String,
                  pitches: data["pitches"] as? [String] ?? [],
                  startedAt: (data["startedAt"] as? Timestamp)?.dateValue() ?? Date(),
                  endedAt: (data["endedAt"] as? Timestamp)?.dateValue())
        archivedAt = (data["archivedAt"] as? Timestamp)?.dateValue()
    }
}

// MARK: - Rules

enum PracticeRules {
    /// A player must be chosen (anyone - not only pitchers), and at least
    /// one pitch.
    static func canStart(pitcherId: String?, pitches: Set<String>) -> Bool {
        guard let pitcherId, !pitcherId.isEmpty else { return false }
        return !pitches.isEmpty
    }

    /// Every pitch a session can use: all the app's pitch types. No key is
    /// linked in practice (user's call, 2026-11-20).
    static func availablePitches() -> [String] {
        allPitches
    }

    /// The checked pitches, in the list's order - the only chips this session.
    static func sessionPitches(available: [String], chosen: Set<String>) -> [String] {
        available.filter { chosen.contains($0) }
    }

    /// The chips during the session: exactly its pitches, no Catcher chip -
    /// whether or not they're on a key.
    static func chipOptions(session: PracticeSession) -> [String] {
        session.pitches
    }

    /// Practice never shows codes - it isn't linked to any key.
    static let showsCodes = false

    /// Home's list: active sessions, and the archived ones behind Show
    /// Archived - each newest first.
    static func partition(_ sessions: [PracticeSession]) -> (active: [PracticeSession], archived: [PracticeSession]) {
        let sorted = sessions.sorted { $0.startedAt > $1.startedAt }
        return (sorted.filter { $0.archivedAt == nil }, sorted.filter { $0.archivedAt != nil })
    }

    /// Everything a delete removes: every pitch, then the session itself
    /// last, so a delete that stops part way never leaves pitches with no
    /// session to find them by.
    static func deletePaths(uid: String, sessionId: String, eventIds: [String]) -> [String] {
        eventIds.map { eventsPath(uid: uid, sessionId: sessionId) + "/" + $0 }
            + [sessionPath(uid: uid, sessionId: sessionId)]
    }

    static func sessionPath(uid: String, sessionId: String) -> String {
        "users/\(uid)/practiceSessions/\(sessionId)"
    }

    /// Where a practice pitch is saved - never a game, the pitcher's career
    /// record or users/{uid}/pitchEvents.
    static func eventsPath(uid: String, sessionId: String) -> String {
        sessionPath(uid: uid, sessionId: sessionId) + "/pitchEvents"
    }

    /// A practice pitch: the pitch, the target (`call`), and where it went
    /// (`actualLabel`, a full zone label like "Ball Up & In"). No batter, no
    /// result, no game.
    static func event(call: PitchCall, actualLabel: String, session: PracticeSession,
                      batterSide: BatterSide, now: Date = Date()) -> PitchEvent {
        let inZone = PracticeGrid.isStrikeLabel(actualLabel)
        var event = PitchEvent(
            id: UUID().uuidString, timestamp: now, pitch: call.pitch, location: actualLabel, codes: [],
            isStrike: inZone, isBall: !inZone, mode: .game, calledPitch: call,
            batterSide: batterSide, templateId: nil,
            strikeSwinging: false, wildPitch: false, passedBall: false,
            strikeLooking: false, outcome: nil, descriptor: nil,
            errorOnPlay: false, battedBallRegion: nil, battedBallType: nil, battedBallTapX: nil, battedBallTapY: nil,
            gameId: nil, opponentJersey: nil, opponentBatterId: nil, pitcherId: session.pitcherId
        )
        event.trackingMode = .coach
        return event
    }

    /// The target's full label ("Strike Up & In") from the call.
    static func targetLabel(_ call: PitchCall) -> String {
        "\(call.isStrike ? "Strike" : "Ball") \(call.location.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

// MARK: - Zone geometry

/// Every spot on the zone as a cell of a 5 x 5 grid: the strike zone is the
/// middle 3 x 3, the ball spots the ring around it. Rows run top (0) to
/// bottom (4); columns run Out (0) to In (4), as the spots are labeled.
enum PracticeGrid {
    struct Cell: Equatable, Hashable {
        var row: Int
        var col: Int
    }

    static func isStrikeLabel(_ label: String) -> Bool {
        label.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Strike")
    }

    static func cell(_ label: String) -> Cell? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let isStrike = trimmed.hasPrefix("Strike ")
        guard isStrike || trimmed.hasPrefix("Ball ") else { return nil }
        let spot = String(trimmed.dropFirst(isStrike ? 7 : 5)).trimmingCharacters(in: .whitespaces)
        let vertical: Int
        let rest: String
        if spot.hasPrefix("Up") {
            vertical = -1; rest = String(spot.dropFirst(2))
        } else if spot.hasPrefix("↓") {
            vertical = 1; rest = String(spot.dropFirst(1))
        } else {
            vertical = 0; rest = spot
        }
        let side = rest.replacingOccurrences(of: "&", with: "").trimmingCharacters(in: .whitespaces)
        let horizontal: Int
        switch side {
        case "Out": horizontal = -1
        case "In": horizontal = 1
        case "", "Middle": horizontal = 0
        default: return nil
        }
        if isStrike {
            return Cell(row: 2 + vertical, col: 2 + horizontal)
        }
        // A ball spot sits on the ring, past the zone's edge.
        guard vertical != 0 || horizontal != 0 else { return nil }
        return Cell(row: 2 + vertical * 2, col: 2 + horizontal * 2)
    }

    /// Spots apart (a diagonal neighbor is one away).
    static func distance(_ a: Cell, _ b: Cell) -> Int {
        max(abs(a.row - b.row), abs(a.col - b.col))
    }

    struct Miss: Equatable {
        var high = false
        var low = false
        var inside = false
        var outside = false
    }

    /// Which way the pitch missed the target (it can be two ways at once).
    static func miss(target: Cell, actual: Cell) -> Miss {
        Miss(high: actual.row < target.row, low: actual.row > target.row,
             inside: actual.col > target.col, outside: actual.col < target.col)
    }
}

// MARK: - Summary (the review's numbers)

/// Accuracy against the target, per pitch type and for the session
/// (user's picks, 2026-11-20): thrown, on target, within one spot, in the
/// zone, which way the misses went, and accuracy by target spot.
struct PracticeSummary: Equatable {
    struct Stats: Equatable {
        var thrown = 0
        var onTarget = 0
        var withinOne = 0
        var inZone = 0
        var misses = 0
        var missedHigh = 0
        var missedLow = 0
        var missedIn = 0
        var missedOut = 0

        var onTargetPercent: Int { PracticeSummary.percent(onTarget, of: thrown) }
        var withinOnePercent: Int { PracticeSummary.percent(withinOne, of: thrown) }
        var zonePercent: Int { PracticeSummary.percent(inZone, of: thrown) }

        /// The direction the misses went most ("high"), with its count; nil
        /// with no misses. Ties go high, low, in, out.
        var mostCommonMiss: (direction: String, count: Int)? {
            let options = [("high", missedHigh), ("low", missedLow), ("in", missedIn), ("out", missedOut)]
            guard let best = options.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
            return options.first { $0.1 == best.1 }.map { ($0.0, $0.1) }
        }

        mutating func add(target: PracticeGrid.Cell?, actual: PracticeGrid.Cell?, actualLabel: String) {
            thrown += 1
            if PracticeGrid.isStrikeLabel(actualLabel) { inZone += 1 }
            guard let target, let actual else { return }
            let distance = PracticeGrid.distance(target, actual)
            if distance == 0 { onTarget += 1 }
            if distance <= 1 { withinOne += 1 }
            guard distance > 0 else { return }
            misses += 1
            let miss = PracticeGrid.miss(target: target, actual: actual)
            if miss.high { missedHigh += 1 }
            if miss.low { missedLow += 1 }
            if miss.inside { missedIn += 1 }
            if miss.outside { missedOut += 1 }
        }
    }

    struct PitchLine: Equatable, Identifiable {
        var pitch: String
        var stats: Stats
        var byTarget: [TargetLine]
        var id: String { pitch }
    }

    struct TargetLine: Equatable, Identifiable {
        var target: String
        var thrown: Int
        var onTarget: Int
        var id: String { target }
        var onTargetPercent: Int { PracticeSummary.percent(onTarget, of: thrown) }
    }

    var overall: Stats
    var pitches: [PitchLine]
    var byTarget: [TargetLine]

    static func percent(_ part: Int, of whole: Int) -> Int {
        whole > 0 ? Int((Double(part) / Double(whole) * 100).rounded()) : 0
    }

    init(events: [PitchEvent], pitchOrder: [String] = []) {
        func target(_ event: PitchEvent) -> String? {
            event.calledPitch.map(PracticeRules.targetLabel)
        }
        func add(_ event: PitchEvent, to stats: inout Stats) {
            stats.add(target: target(event).flatMap(PracticeGrid.cell),
                      actual: PracticeGrid.cell(event.location),
                      actualLabel: event.location)
        }
        func targets(_ events: [PitchEvent]) -> [TargetLine] {
            var lines: [String: TargetLine] = [:]
            for event in events {
                guard let label = target(event), let t = PracticeGrid.cell(label) else { continue }
                var line = lines[label] ?? TargetLine(target: label, thrown: 0, onTarget: 0)
                line.thrown += 1
                if let a = PracticeGrid.cell(event.location), PracticeGrid.distance(t, a) == 0 { line.onTarget += 1 }
                lines[label] = line
            }
            return lines.values.sorted { $0.thrown == $1.thrown ? $0.target < $1.target : $0.thrown > $1.thrown }
        }

        var overall = Stats()
        for event in events { add(event, to: &overall) }
        self.overall = overall
        let grouped = Dictionary(grouping: events, by: { $0.pitch })
        let order = pitchOrder + grouped.keys.filter { !pitchOrder.contains($0) }.sorted()
        pitches = order.compactMap { pitch in
            guard let group = grouped[pitch], !group.isEmpty else { return nil }
            var stats = Stats()
            for event in group { add(event, to: &stats) }
            return PitchLine(pitch: pitch, stats: stats, byTarget: targets(group))
        }
        byTarget = targets(events)
    }
}

// MARK: - Running log and suggestion (2026-11-20)

enum PracticeLog {
    /// "high, in" / "on target" - how one pitch landed against its target.
    static func describe(_ event: PitchEvent) -> String {
        guard let call = event.calledPitch,
              let target = PracticeGrid.cell(PracticeRules.targetLabel(call)),
              let actual = PracticeGrid.cell(event.location) else { return "" }
        guard PracticeGrid.distance(target, actual) > 0 else { return "on target" }
        let miss = PracticeGrid.miss(target: target, actual: actual)
        return [miss.high ? "high" : nil, miss.low ? "low" : nil, miss.inside ? "in" : nil, miss.outside ? "out" : nil]
            .compactMap { $0 }.joined(separator: ", ")
    }

    /// The latest pitches, newest first.
    static func recent(_ events: [PitchEvent], limit: Int = 5) -> [String] {
        events.suffix(limit).reversed().map { event in
            let target = event.calledPitch.map(PracticeRules.targetLabel) ?? "?"
            return "\(event.pitch) → \(target), went \(event.location) (\(describe(event)))"
        }
    }
}

/// What to practice more, from this session's own numbers (user's
/// thresholds: 5 of a pitch, 3 at a spot).
enum PracticeSuggestion {
    static let minPerPitch = 5
    static let minPerSpot = 3
    /// A miss direction counts as a pattern at this share of the misses.
    static let patternShare = 0.6
    /// Every pitch at or above this on-target % is a strong session.
    static let strongPercent = 60

    static func lines(_ summary: PracticeSummary) -> [String] {
        let judged = summary.pitches.filter { $0.stats.thrown >= minPerPitch }
        guard !judged.isEmpty else {
            return ["Throw \(minPerPitch) of each pitch for a suggestion."]
        }
        if judged.count == summary.pitches.count,
           judged.allSatisfy({ $0.stats.onTargetPercent >= strongPercent }) {
            return ["Strong session. Try more corners and ball spots."]
        }
        // Weakest pitch; a tie goes to the one thrown more.
        let weakest = judged.min { a, b in
            a.stats.onTargetPercent == b.stats.onTargetPercent
                ? a.stats.thrown > b.stats.thrown
                : a.stats.onTargetPercent < b.stats.onTargetPercent
        }!
        var lines = ["Work on the \(weakest.pitch): \(weakest.stats.onTarget) of \(weakest.stats.thrown) on target (\(weakest.stats.onTargetPercent)%)."]
        if let miss = weakest.stats.mostCommonMiss, weakest.stats.misses > 0,
           Double(miss.count) / Double(weakest.stats.misses) >= patternShare {
            lines.append("Most of its misses go \(miss.direction) (\(miss.count) of \(weakest.stats.misses)).")
        }
        let spots = summary.byTarget.filter { $0.thrown >= minPerSpot }
        if let hardest = spots.min(by: { a, b in
            a.onTargetPercent == b.onTargetPercent ? a.thrown > b.thrown : a.onTargetPercent < b.onTargetPercent
        }), hardest.onTargetPercent < 100 {
            lines.append("Hardest spot: \(hardest.target), \(hardest.onTarget) of \(hardest.thrown).")
        }
        return lines
    }
}

/// The running log under the zone: the session's numbers, each pitch,
/// what to practice more, and the latest pitches - updated as each pitch
/// saves.
struct PracticeLiveLog: View {
    let session: PracticeSession
    @ObservedObject private var store = PracticeStore.shared

    private var events: [PitchEvent] { store.liveEvents[session.id] ?? [] }
    private var summary: PracticeSummary { PracticeSummary(events: events, pitchOrder: session.pitches) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if events.isEmpty {
                    Text("Your running log shows here after the first pitch.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    let overall = summary.overall
                    Text("\(overall.thrown) thrown · \(overall.onTargetPercent)% on target · \(overall.withinOnePercent)% within one · \(overall.zonePercent)% in zone")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("practiceLog.session")

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(summary.pitches) { line in
                            let miss = line.stats.mostCommonMiss.map { " · misses \($0.direction)" } ?? ""
                            Text("\(line.pitch) · \(line.stats.thrown) · \(line.stats.onTargetPercent)% on target\(miss)")
                                .font(.footnote)
                                .accessibilityIdentifier("practiceLog.pitch.\(line.pitch)")
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Practice more", systemImage: "lightbulb")
                            .font(.footnote.weight(.semibold))
                        ForEach(PracticeSuggestion.lines(summary), id: \.self) { line in
                            Text(line).font(.footnote)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("practiceLog.suggestion")

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Latest").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(Array(PracticeLog.recent(events).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("practiceLog.latest")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            // Room to scroll the last lines clear of the floating tab bar.
            .padding(.bottom, 110)
        }
        .accessibilityIdentifier("practiceLog")
    }
}

// MARK: - Store

@MainActor
final class PracticeStore: ObservableObject {
    static let shared = PracticeStore()

    @Published private(set) var sessions: [PracticeSession] = []
    /// The pitches saved on this phone per session, in order - the running
    /// log reads these, and signed out (demo) they're all there is.
    @Published private(set) var liveEvents: [String: [PitchEvent]] = [:]
    private var listener: ListenerRegistration? = nil
    private var uid: String? = nil
    private let currentUid: () -> String?

    /// `currentUid` is injectable so tests run signed out, in memory.
    init(currentUid: @escaping () -> String? = { Auth.auth().currentUser?.uid }) {
        self.currentUid = currentUid
    }

    private var signedInUid: String? { currentUid() }

    private static func sessions(_ uid: String) -> CollectionReference {
        Firestore.firestore().collection("users").document(uid).collection("practiceSessions")
    }

    func start() {
        let uid = signedInUid
        guard uid != self.uid || listener == nil else { return }
        listener?.remove()
        listener = nil
        self.uid = uid
        guard let uid else { return }
        listener = Self.sessions(uid).order(by: "startedAt", descending: true).limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, _ in
                let loaded = (snapshot?.documents ?? []).compactMap { PracticeSession(id: $0.documentID, data: $0.data()) }
                Task { @MainActor in self?.sessions = loaded }
            }
    }

    func create(_ session: PracticeSession) {
        sessions.insert(session, at: 0)
        guard let uid = signedInUid else { return }
        Firestore.firestore().document(PracticeRules.sessionPath(uid: uid, sessionId: session.id))
            .setData(session.firestoreData)
    }

    func end(_ session: PracticeSession) {
        var ended = session
        ended.endedAt = Date()
        if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = ended }
        guard let uid = signedInUid else { return }
        Firestore.firestore().document(PracticeRules.sessionPath(uid: uid, sessionId: session.id))
            .updateData(["endedAt": Timestamp(date: ended.endedAt ?? Date())])
    }

    /// The session's pitches saved on this phone, newest last - what Undo
    /// Last takes back.
    private var savedIds: [String: [String]] = [:]

    func save(_ event: PitchEvent, in session: PracticeSession) {
        liveEvents[session.id, default: []].append(event)
        if let id = event.id { savedIds[session.id, default: []].append(id) }
        guard let uid = signedInUid, let id = event.id else { return }
        let ref = Firestore.firestore().collection(PracticeRules.eventsPath(uid: uid, sessionId: session.id)).document(id)
        try? ref.setData(from: event)
    }

    /// Archive hides a session from Home's list; Restore brings it back. Its
    /// pitches are kept either way.
    func setArchived(_ archived: Bool, _ session: PracticeSession) {
        let date: Date? = archived ? Date() : nil
        if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index].archivedAt = date }
        guard let uid = signedInUid else { return }
        Firestore.firestore().document(PracticeRules.sessionPath(uid: uid, sessionId: session.id))
            .updateData(["archivedAt": date.map { Timestamp(date: $0) } ?? NSNull()])
    }

    /// Delete removes the session and every one of its pitches, for good -
    /// the pitches first, the session last (PracticeRules.deletePaths).
    func delete(_ session: PracticeSession) {
        sessions.removeAll { $0.id == session.id }
        liveEvents[session.id] = nil
        savedIds[session.id] = nil
        guard let uid = signedInUid else { return }
        let db = Firestore.firestore()
        db.collection(PracticeRules.eventsPath(uid: uid, sessionId: session.id)).getDocuments { snapshot, _ in
            let ids = (snapshot?.documents ?? []).map(\.documentID)
            let paths = PracticeRules.deletePaths(uid: uid, sessionId: session.id, eventIds: ids)
            // Batches of at most 450 writes; the session is in the last.
            let chunks = stride(from: 0, to: paths.count, by: 450).map { Array(paths[$0..<min($0 + 450, paths.count)]) }
            func commit(_ index: Int) {
                guard index < chunks.count else { return }
                let batch = db.batch()
                chunks[index].forEach { batch.deleteDocument(db.document($0)) }
                batch.commit { error in if error == nil { commit(index + 1) } }
            }
            commit(0)
        }
    }

    /// Undo Last: removes the session's most recent pitch. False when
    /// there's nothing to take back.
    @discardableResult
    func removeLast(in session: PracticeSession) -> Bool {
        guard let id = savedIds[session.id]?.popLast() else { return false }
        liveEvents[session.id]?.removeAll { $0.id == id }
        if let uid = signedInUid {
            Firestore.firestore().collection(PracticeRules.eventsPath(uid: uid, sessionId: session.id))
                .document(id).delete()
        }
        return true
    }

    func loadEvents(for session: PracticeSession, completion: @escaping ([PitchEvent]) -> Void) {
        guard let uid = signedInUid else {
            completion(liveEvents[session.id] ?? [])
            return
        }
        Firestore.firestore().collection(PracticeRules.eventsPath(uid: uid, sessionId: session.id))
            .order(by: "timestamp").getDocuments { snapshot, _ in
                let events = (snapshot?.documents ?? []).compactMap { PitchEvent.decodeFirestoreDocument($0) }
                DispatchQueue.main.async { completion(events) }
            }
    }
}

// MARK: - Setup (player + pitches)

/// Opened from the New Game card's Practice option. The player comes from
/// the shared player list (PlayerPickerButton - Pitchers first, All a tap
/// away; anyone may practice). Then every pitch type, unchecked - the
/// coach checks the ones this session works on.
struct PracticeSetupView: View {
    let rows: [PlayerDirectoryRow]
    let teams: [Team]
    var archivedPitcherIds: Set<String> = []
    let templates: [PitchTemplate]
    let onStart: (PracticeSession) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var player: PlayerDirectoryRow? = nil
    @State private var chosen: Set<String> = []

    private var playerPitcherId: String? { player.flatMap { $0.pitcherId ?? $0.id } }
    private var available: [String] { PracticeRules.availablePitches() }

    var body: some View {
        NavigationStack {
            Form {
                Section("Player") {
                    PlayerPickerButton(
                        title: "Practice Player",
                        rows: rows,
                        teams: teams,
                        archivedPitcherIds: archivedPitcherIds,
                        initialScope: .pitchers,
                        isSelected: { $0.id == player?.id },
                        onSelect: { player = $0 }
                    ) {
                        HStack {
                            Text(player?.name ?? "Choose Player")
                                .foregroundStyle(player == nil ? Color.secondary : Color.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("practice.player")
                }

                Section {
                    ForEach(available, id: \.self) { pitch in
                        Button {
                            if chosen.contains(pitch) { chosen.remove(pitch) } else { chosen.insert(pitch) }
                        } label: {
                            HStack {
                                Image(systemName: chosen.contains(pitch) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(chosen.contains(pitch) ? Color.pitchMarkActiveGray : .secondary)
                                Text(pitch).foregroundStyle(.primary)
                            }
                        }
                        .tint(.primary)
                        .accessibilityIdentifier("practice.pitch.\(pitch)")
                        .accessibilityValue(chosen.contains(pitch) ? "On" : "Off")
                    }
                } header: {
                    Text("Pitches to practice")
                } footer: {
                    Text("Check the pitches for this session - only these appear as chips.")
                }
            }
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { start() }
                        .disabled(!PracticeRules.canStart(pitcherId: playerPitcherId, pitches: chosen))
                        .accessibilityIdentifier("practice.start")
                }
            }
        }
    }

    private func start() {
        guard let player, let id = playerPitcherId, PracticeRules.canStart(pitcherId: id, pitches: chosen) else { return }
        let session = PracticeSession(pitcherId: id, pitcherName: player.name, templateId: nil,
                                      pitches: PracticeRules.sessionPitches(available: available, chosen: chosen))
        PracticeStore.shared.create(session)
        onStart(session)
        dismiss()
    }
}

// MARK: - Tracker pieces

/// The practice tracker's header: who, how many, what to tap next, Undo
/// Last and End.
struct PracticeHeader: View {
    let session: PracticeSession
    let pitchCount: Int
    /// "Tap the target" / "Target: Strike Up - now tap where it went".
    let prompt: String
    let onUndo: () -> Void
    let onEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Practice · \(session.pitcherName)")
                        .font(.headline)
                        .accessibilityIdentifier("practice.title")
                    Text("\(pitchCount) pitch\(pitchCount == 1 ? "" : "es")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("practice.count")
                }
                Spacer()
                Button("Undo Last", action: onUndo)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .disabled(pitchCount == 0)
                    .accessibilityIdentifier("practice.undo")
                Button("End", action: onEnd)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("practice.end")
            }
            Text(prompt)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("practice.prompt")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Review

/// One session's accuracy: overall, each pitch (with its misses and its
/// targets), and accuracy by target spot.
struct PracticeReviewView: View {
    let session: PracticeSession
    @State private var events: [PitchEvent] = []
    @State private var loaded = false

    private var summary: PracticeSummary { PracticeSummary(events: events, pitchOrder: session.pitches) }

    var body: some View {
        List {
            Section {
                LabeledContent("Pitcher", value: session.pitcherName)
                LabeledContent("Date", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
            }
            if summary.overall.thrown > 0 {
                Section("Session") {
                    statRows(summary.overall, identifierPrefix: "practiceReview")
                }
                Section("Practice more") {
                    ForEach(PracticeSuggestion.lines(summary), id: \.self) { Text($0).font(.subheadline) }
                }
                ForEach(summary.pitches) { line in
                    Section(line.pitch) {
                        statRows(line.stats, identifierPrefix: "practiceReview.\(line.pitch)")
                        ForEach(line.byTarget) { target in
                            LabeledContent("Target \(target.target)",
                                           value: "\(target.onTarget)/\(target.thrown) · \(target.onTargetPercent)%")
                                .font(.caption)
                        }
                    }
                }
                Section("Accuracy by target") {
                    ForEach(summary.byTarget) { target in
                        LabeledContent(target.target, value: "\(target.onTargetPercent)% of \(target.thrown)")
                    }
                }
            } else if loaded {
                Text("No pitches recorded in this session.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Practice")
        .onAppear {
            PracticeStore.shared.loadEvents(for: session) { loadedEvents in
                events = loadedEvents
                loaded = true
            }
        }
    }

    @ViewBuilder
    private func statRows(_ stats: PracticeSummary.Stats, identifierPrefix: String) -> some View {
        LabeledContent("Thrown", value: "\(stats.thrown)")
            .accessibilityIdentifier("\(identifierPrefix).total")
        LabeledContent("On target", value: "\(stats.onTargetPercent)%")
            .accessibilityIdentifier("\(identifierPrefix).onTarget")
        LabeledContent("Within one spot", value: "\(stats.withinOnePercent)%")
        LabeledContent("In the zone", value: "\(stats.zonePercent)%")
        if stats.misses > 0 {
            LabeledContent("Misses", value: "\(stats.missedHigh) high · \(stats.missedLow) low · \(stats.missedIn) in · \(stats.missedOut) out")
                .font(.caption)
        }
    }
}

/// Home's Practice list, under the games. Its own struct so Home's type
/// doesn't grow (CLAUDE.md, Home's depth limit). Each row's ⋯ archives or
/// deletes; the delete confirmation is Home's (`practiceDeleteDialog` at
/// Home's root - a dialog on a small subview only takes taps inside it).
struct HomePracticeList: View {
    var onDelete: (PracticeSession) -> Void = { _ in }
    @ObservedObject private var store = PracticeStore.shared
    @State private var showArchived = false

    var body: some View {
        let lists = PracticeRules.partition(store.sessions)
        VStack(alignment: .leading, spacing: 6) {
            if !store.sessions.isEmpty {
                Text("Practice")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                    .accessibilityIdentifier("home.practiceHeader")
                ForEach(lists.active.prefix(10)) { session in
                    row(session, archived: false)
                }
                if !lists.archived.isEmpty {
                    Button(showArchived ? "Hide Archived" : "Show Archived (\(lists.archived.count))") {
                        showArchived.toggle()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("home.practice.showArchived")
                    if showArchived {
                        ForEach(lists.archived) { session in
                            row(session, archived: true)
                        }
                    }
                }
            }
        }
        .onAppear { store.start() }
    }

    private func row(_ session: PracticeSession, archived: Bool) -> some View {
        HStack {
            NavigationLink {
                PracticeReviewView(session: session)
            } label: {
                HStack {
                    Image(systemName: "figure.baseball").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Practice · \(session.pitcherName)").font(.subheadline.weight(.semibold))
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .opacity(archived ? 0.6 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.practice.\(session.pitcherName)")

            Menu {
                if archived {
                    Button("Restore") { store.setArchived(false, session) }
                } else {
                    Button("Archive") { store.setArchived(true, session) }
                }
                Button("Delete…", role: .destructive) { onDelete(session) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("home.practice.menu.\(session.pitcherName)")
        }
    }
}

extension View {
    /// Home's confirmation before a practice session is deleted for good.
    func practiceDeleteDialog(pending: Binding<PracticeSession?>, onConfirm: @escaping (PracticeSession) -> Void) -> some View {
        let current = pending.wrappedValue
        return appConfirmationDialog(
            isPresented: Binding(
                get: { pending.wrappedValue != nil },
                set: { if !$0 { pending.wrappedValue = nil } }
            ),
            title: "Delete this practice session?",
            message: "\(current?.pitcherName ?? "This") practice and all its pitches are removed for good. Archive keeps them instead.",
            primaryTitle: "Delete",
            primaryRole: .destructive,
            primaryAction: { if let current { onConfirm(current) } },
            secondaryTitle: "Cancel"
        )
    }
}

/// Home's practice setup sheet, as one modifier so Home's view type barely
/// grows. Attached to the Practice list, which is always on screen - the
/// New Game card closes when practice starts, and a sheet on it would go too.
struct PracticeSetupPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let rows: [PlayerDirectoryRow]
    let teams: [Team]
    let archivedPitcherIds: Set<String>
    let templates: [PitchTemplate]
    let onStart: (PracticeSession) -> Void

    func body(content: Content) -> some View {
        content.appSheet(isPresented: $isPresented, chrome: .handle) {
            PracticeSetupView(rows: rows, teams: teams, archivedPitcherIds: archivedPitcherIds,
                              templates: templates, onStart: onStart)
                .fixedAppDynamicType()
        }
    }
}
