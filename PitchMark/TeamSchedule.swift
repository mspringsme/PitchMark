//
//  TeamSchedule.swift
//  PitchMark
//
//  A team's schedule (2026-11-24, user's calls): single games (Game,
//  Friendly or Scrimmage) stored with the team at `teams/{id}/games`, and
//  one Team Schedule list that merges them with the team's tourney games -
//  upcoming by date, canceled ones marked, past ones folded away. The coach
//  and their Schedulers add and edit; every member sees it live. Home's
//  calendar shows scheduled games too, until one is tracked.
//
//  Plain model and rules here; the screens are in TeamScheduleViews.swift.
//

import Foundation
import FirebaseFirestore

/// One game on a team's schedule that isn't in a tourney.
struct TeamScheduledGame: Identifiable, Equatable {
    var id: String = UUID().uuidString
    var teamId: String
    var kind: GameKind = .game
    var time: Date
    /// When the team should be there (optional).
    var arriveAt: Date? = nil
    var opponent: String = ""
    /// Where it's played - searched like a tourney venue, so Directions work.
    var venue: TourneyPlace = TourneyPlace()
    var field: String = ""
    var notes: String = ""
    /// Called off: stays on the schedule marked Canceled.
    var canceled: Bool = false

    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "teamId": teamId, "kind": kind.rawValue, "time": Timestamp(date: time),
            "opponent": opponent, "venue": venue.firestoreData, "field": field,
            "notes": notes, "canceled": canceled
        ]
        data["arriveAt"] = arriveAt.map { Timestamp(date: $0) } ?? NSNull()
        return data
    }

    init(id: String = UUID().uuidString, teamId: String, kind: GameKind = .game, time: Date,
         arriveAt: Date? = nil, opponent: String = "") {
        self.id = id
        self.teamId = teamId
        self.kind = kind
        self.time = time
        self.arriveAt = arriveAt
        self.opponent = opponent
    }

    init?(id: String, firestoreData data: [String: Any]) {
        guard let teamId = data["teamId"] as? String, let time = (data["time"] as? Timestamp)?.dateValue() else { return nil }
        self.id = id
        self.teamId = teamId
        kind = GameKind(rawValue: data["kind"] as? String ?? "") ?? .game
        self.time = time
        arriveAt = (data["arriveAt"] as? Timestamp)?.dateValue()
        opponent = data["opponent"] as? String ?? ""
        venue = (data["venue"] as? [String: Any]).map(TourneyPlace.init(firestoreData:)) ?? TourneyPlace()
        field = data["field"] as? String ?? ""
        notes = data["notes"] as? String ?? ""
        canceled = data["canceled"] as? Bool ?? false
    }

    /// The same game in a tourney game's shape, for the game card and Track.
    var asTourneyGame: TourneyGame {
        var game = TourneyGame(id: id, time: time, arriveAt: arriveAt, field: field, opponent: opponent,
                               ourTeamId: teamId)
        game.canceled = canceled
        game.kind = kind
        return game
    }
}

/// The plain rules behind the Team Schedule and the calendar.
enum TeamSchedule {
    /// One line on the schedule.
    struct Entry: Identifiable, Equatable {
        enum Source: Equatable {
            case tourney(tourneyId: String, name: String)
            case single
        }

        var id: String          // the tourney game's or single game's id
        var teamId: String?
        var time: Date
        var opponent: String
        var label: String       // the tourney's name, or Game / Friendly / Scrimmage
        var canceled: Bool
        var source: Source
        var game: TourneyGame   // for the game card and Track
        var venue: TourneyPlace

        var title: String {
            let o = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
            return o.isEmpty ? label : "vs \(o)"
        }
    }

    /// Every game on the team's schedule, by date (earliest first): the
    /// team's tourney games and its single games. Archived tourneys are
    /// left out.
    static func entries(tourneys: [Tourney], singles: [TeamScheduledGame]) -> [Entry] {
        let fromTourneys = tourneys.filter { !$0.isArchived }.flatMap { tourney in
            tourney.games.map { game in
                Entry(id: game.id, teamId: tourney.teamId, time: game.time, opponent: game.opponent,
                      label: tourney.displayName, canceled: game.canceled,
                      source: .tourney(tourneyId: tourney.id, name: tourney.displayName),
                      game: game, venue: tourney.venue)
            }
        }
        let fromSingles = singles.map { single in
            Entry(id: single.id, teamId: single.teamId, time: single.time, opponent: single.opponent,
                  label: single.kind.title, canceled: single.canceled, source: .single,
                  game: single.asTourneyGame, venue: single.venue)
        }
        return (fromTourneys + fromSingles).sorted { $0.time < $1.time }
    }

    /// Upcoming (from the start of today, soonest first) and past (most
    /// recent first) - past ones are folded away below.
    static func split(_ entries: [Entry], now: Date, calendar: Calendar = .current) -> (upcoming: [Entry], past: [Entry]) {
        let today = calendar.startOfDay(for: now)
        let upcoming = entries.filter { $0.time >= today }.sorted { $0.time < $1.time }
        let past = entries.filter { $0.time < today }.sorted { $0.time > $1.time }
        return (upcoming, past)
    }

    /// The scheduled games Home's calendar still shows: once a game has
    /// been tracked from an entry, the tracked game takes its place.
    static func calendarEntries(_ entries: [Entry], trackedGames: [Game]) -> [Entry] {
        let tracked = Set(trackedGames.compactMap(\.scheduledGameId))
        var seen = Set<String>()
        return entries.filter { !tracked.contains($0.id) && seen.insert($0.id).inserted }
    }

    /// What a day on the calendar shows: tracked games (filled dot) and
    /// scheduled ones (outlined).
    struct DayMarks: Equatable {
        var tracked = 0
        var scheduled = 0
    }

    static func dayMarks(tracked: [Game], scheduled: [Entry], calendar: Calendar = .current) -> [Date: DayMarks] {
        var marks: [Date: DayMarks] = [:]
        for game in tracked { marks[calendar.startOfDay(for: game.date), default: DayMarks()].tracked += 1 }
        for entry in scheduled { marks[calendar.startOfDay(for: entry.time), default: DayMarks()].scheduled += 1 }
        return marks
    }

    /// Whether starting to track this game asks about stats.
    static func asksAboutStats(_ kind: GameKind?) -> Bool { (kind ?? .game).asksAboutStats }
}
