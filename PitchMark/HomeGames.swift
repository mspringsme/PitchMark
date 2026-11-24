//
//  HomeGames.swift
//  PitchMark
//
//  Home's Games list, the New Game form's details and My Teams vs
//  Opponents (2026-11-24, user's calls):
//  - Games + offers Game, Tournament or Pitching Practice Session. A Game
//    asks for everything (type, teams, time, arrive by, where, field,
//    notes); for one of your teams it also goes on the team schedule.
//  - One Games list: tracked games and scheduled ones (team games, tourney
//    games) together - upcoming first, soonest first, then past. A third
//    line names the tourney, or the type. Tapping an upcoming game opens
//    its card (Start Tracking, Edit); a tracked game replaces its entry.
//  - Teams split into My Teams and Opponents, worked out from how each
//    team is used; the coach can move one, and that wins.
//
//  Plain rules here, kept out of SettingsView so they can be tested.
//

import Foundation
import FirebaseFirestore
import Combine

// MARK: - The Games list

enum HomeGameList {
    /// One row on Home's Games list.
    enum Item: Identifiable, Equatable {
        /// A game this user is tracking (or has made), with the schedule
        /// entry it came from, if any.
        case tracked(Game, entry: TeamSchedule.Entry?)
        /// A scheduled game nobody here has started tracking yet.
        case scheduled(TeamSchedule.Entry)

        var id: String {
            switch self {
            case .tracked(let game, _): return "g-" + (game.id ?? "")
            case .scheduled(let entry): return "s-" + entry.id
            }
        }

        var date: Date {
            switch self {
            case .tracked(let game, _): return game.date
            case .scheduled(let entry): return entry.time
            }
        }

        var canceled: Bool {
            switch self {
            case .tracked(_, let entry): return entry?.canceled ?? false
            case .scheduled(let entry): return entry.canceled
            }
        }

        /// The third line: the tourney's name, or a Friendly / Scrimmage.
        /// A plain Game needs none.
        var detail: String? {
            switch self {
            case .tracked(let game, let entry):
                if case .tourney(_, let name)? = entry?.source { return name }
                if case .sharedTourney(_, let name)? = entry?.source { return name }
                if let kind = game.kind, kind != .game { return kind.title }
                return nil
            case .scheduled(let entry):
                if case .tourney(_, let name) = entry.source { return name }
                if case .sharedTourney(_, let name) = entry.source { return name }
                return entry.label == GameKind.game.title ? nil : entry.label
            }
        }

        static func == (lhs: Item, rhs: Item) -> Bool { lhs.id == rhs.id && lhs.date == rhs.date }
    }

    /// Tracked and scheduled games together, a tracked one once (it
    /// replaces the entry it was tracked from): upcoming (from the start
    /// of today) soonest first, then past most recent first.
    static func items(tracked: [Game], scheduled: [TeamSchedule.Entry], now: Date,
                      calendar: Calendar = .current) -> (upcoming: [Item], past: [Item]) {
        let entriesById = Dictionary(scheduled.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let trackedItems = tracked.map { game in
            Item.tracked(game, entry: game.scheduledGameId.flatMap { entriesById[$0] })
        }
        let scheduledItems = TeamSchedule.calendarEntries(scheduled, trackedGames: tracked).map(Item.scheduled)
        let all = trackedItems + scheduledItems
        let today = calendar.startOfDay(for: now)
        let upcoming = all.filter { $0.date >= today }.sorted { $0.date < $1.date }
        let past = all.filter { $0.date < today }.sorted { $0.date > $1.date }
        return (upcoming, past)
    }

    /// Whether a tap opens the game's card instead of the tracker: every
    /// scheduled game, and a tracked game that hasn't started yet.
    static func opensCard(_ item: Item, now: Date) -> Bool {
        switch item {
        case .scheduled: return true
        case .tracked(let game, _): return game.date > now
        }
    }
}

// MARK: - The New Game form

/// What the New Game form asks beyond teams, opponent and time.
struct NewGameDetails: Equatable {
    var arriveAt: Date? = nil
    var venue: TourneyPlace = TourneyPlace()
    var field: String = ""
    var notes: String = ""
}

enum NewGamePlan {
    /// The game the form makes, and - for one of your teams you schedule
    /// for - the matching team-schedule entry (same details, linked by
    /// `scheduledGameId`) so the team's members see it.
    static func make(opponent: String, date: Date, ourTeamId: String?, opponentTeamId: String?,
                     kind: GameKind, trackingMode: TrackingMode, details: NewGameDetails,
                     schedulesForTeam: Bool, entryId: String = UUID().uuidString) -> (game: Game, entry: TeamScheduledGame?) {
        var game = Game(id: nil, opponent: opponent, date: date, jerseyNumbers: [], trackingMode: trackingMode)
        game.teamId = ourTeamId
        game.awayTeamId = opponentTeamId
        game.kind = kind == .game ? nil : kind
        apply(details, to: &game)

        guard let ourTeamId, schedulesForTeam else { return (game, nil) }
        var entry = TeamScheduledGame(id: entryId, teamId: ourTeamId, kind: kind, time: date,
                                      arriveAt: details.arriveAt, opponent: opponent)
        entry.venue = details.venue
        entry.field = details.field
        entry.notes = details.notes
        game.scheduledGameId = entryId
        return (game, entry)
    }

    /// Start Tracking on a scheduled game: a game with its teams, opponent,
    /// time, type and details, linked back to the entry.
    static func game(from entry: TeamSchedule.Entry, kind: GameKind, trackingMode: TrackingMode = .coach) -> Game {
        var game = Game(id: nil, opponent: entry.opponent.trimmingCharacters(in: .whitespacesAndNewlines),
                        date: entry.time, jerseyNumbers: [], trackingMode: trackingMode)
        game.teamId = entry.teamId ?? entry.game.ourTeamId
        game.awayTeamId = entry.game.opponentTeamId
        game.kind = kind == .game ? nil : kind
        game.scheduledGameId = entry.id
        let details = NewGameDetails(arriveAt: entry.game.arriveAt, venue: entry.venue,
                                     field: entry.game.field, notes: "")
        apply(details, to: &game)
        return game
    }

    private static func apply(_ details: NewGameDetails, to game: inout Game) {
        game.arriveAt = details.arriveAt
        let name = details.venue.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = details.venue.address.trimmingCharacters(in: .whitespacesAndNewlines)
        game.venueName = name.isEmpty ? nil : name
        game.venueAddress = address.isEmpty ? nil : address
        game.venueLatitude = details.venue.latitude
        game.venueLongitude = details.venue.longitude
        let field = details.field.trimmingCharacters(in: .whitespacesAndNewlines)
        game.field = field.isEmpty ? nil : field
        let notes = details.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        game.notes = notes.isEmpty ? nil : notes
    }

    /// A tracked game's details back in the form's shape (its card, Edit).
    static func details(of game: Game) -> NewGameDetails {
        NewGameDetails(arriveAt: game.arriveAt,
                       venue: TourneyPlace(name: game.venueName ?? "", address: game.venueAddress ?? "",
                                           latitude: game.venueLatitude, longitude: game.venueLongitude),
                       field: game.field ?? "", notes: game.notes ?? "")
    }
}

// MARK: - My Teams vs Opponents

enum TeamSides {
    enum Side: String { case mine, opponent }

    /// Which group a team is in. The coach's own move wins; otherwise a
    /// team picked as Our team in any game is theirs; one made from the
    /// Opponent picker, or only ever used as an opponent, is an opponent;
    /// anything else (a team made from Teams +) is theirs.
    static func side(teamId: String, movedToMine: Set<String>, movedToOpponents: Set<String>,
                     madeAsOpponent: Set<String>, games: [Game]) -> Side {
        if movedToMine.contains(teamId) { return .mine }
        if movedToOpponents.contains(teamId) { return .opponent }
        if games.contains(where: { $0.teamId == teamId }) { return .mine }
        if madeAsOpponent.contains(teamId) { return .opponent }
        if games.contains(where: { $0.awayTeamId == teamId }) { return .opponent }
        return .mine
    }
}

/// The coach's own My Teams / Opponents settings, at
/// `users/{uid}/meta/teamSides` (the meta rule): teams they moved, and
/// teams made from the Opponent picker.
@MainActor
final class TeamSidesStore: ObservableObject {
    static let shared = TeamSidesStore()

    @Published private(set) var movedToMine: Set<String> = []
    @Published private(set) var movedToOpponents: Set<String> = []
    @Published private(set) var madeAsOpponent: Set<String> = []

    private var listener: ListenerRegistration? = nil
    private var uid: String? = nil

    func start(uid: String?) {
        guard uid != self.uid else { return }
        listener?.remove()
        listener = nil
        self.uid = uid
        movedToMine = []
        movedToOpponents = []
        madeAsOpponent = []
        guard let uid, !uid.isEmpty else { return }
        listener = ref(uid).addSnapshotListener { [weak self] snapshot, _ in
            let data = snapshot?.data() ?? [:]
            Task { @MainActor in
                self?.movedToMine = Set(data["movedToMine"] as? [String] ?? [])
                self?.movedToOpponents = Set(data["movedToOpponents"] as? [String] ?? [])
                self?.madeAsOpponent = Set(data["madeAsOpponent"] as? [String] ?? [])
            }
        }
    }

    func side(of teamId: String, games: [Game]) -> TeamSides.Side {
        TeamSides.side(teamId: teamId, movedToMine: movedToMine, movedToOpponents: movedToOpponents,
                       madeAsOpponent: madeAsOpponent, games: games)
    }

    /// Moves a team to My Teams or Opponents.
    func move(_ teamId: String, to side: TeamSides.Side) {
        if side == .mine {
            movedToMine.insert(teamId)
            movedToOpponents.remove(teamId)
        } else {
            movedToOpponents.insert(teamId)
            movedToMine.remove(teamId)
        }
        write([
            "movedToMine": side == .mine ? FieldValue.arrayUnion([teamId]) : FieldValue.arrayRemove([teamId]),
            "movedToOpponents": side == .opponent ? FieldValue.arrayUnion([teamId]) : FieldValue.arrayRemove([teamId])
        ])
    }

    /// A team made from the Opponent picker starts under Opponents.
    func markMadeAsOpponent(_ teamId: String) {
        madeAsOpponent.insert(teamId)
        write(["madeAsOpponent": FieldValue.arrayUnion([teamId])])
    }

    private func write(_ fields: [String: Any]) {
        guard let uid else { return }
        ref(uid).setData(fields, merge: true)
    }

    private func ref(_ uid: String) -> DocumentReference {
        Firestore.firestore().collection("users").document(uid).collection("meta").document("teamSides")
    }
}
