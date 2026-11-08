//
//  StatsEventFilter.swift
//  PitchMark
//
//  Which recorded events a stats screen counts: one focused game, or every
//  game minus the archived ones this viewer left out, narrowed by date range
//  and team. Shared by pitches and runner events (steals) so both always
//  agree. Pulled out of HitterStatsView (2026-10-31) to be unit tested.
//

import Foundation

struct StatsEventFilter: Equatable {
    /// Set for "This Game": only that game counts, and the other filters
    /// don't apply.
    var focusGameId: String? = nil
    /// Archived games this viewer removed from stats.
    var excludedGameIds: Set<String> = []
    var dateRange: ClosedRange<Date>? = nil
    /// Games of the selected teams; nil = every team.
    var teamGameIds: Set<String>? = nil

    func includes(gameId rawGameId: String?, timestamp: Date) -> Bool {
        if let focusGameId {
            return rawGameId == focusGameId
        }
        let trimmed = rawGameId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let gameId: String? = trimmed.isEmpty ? nil : trimmed
        // An event with no game (practice) can't be in an archived game.
        if let gameId, excludedGameIds.contains(gameId) { return false }
        if let dateRange, !dateRange.contains(timestamp) { return false }
        if let teamGameIds {
            guard let gameId else { return false }
            return teamGameIds.contains(gameId)
        }
        return true
    }

    func pitches(_ events: [PitchEvent]) -> [PitchEvent] {
        events.filter { includes(gameId: $0.gameId, timestamp: $0.timestamp) }
    }

    func runnerEvents(_ events: [RunnerEvent]) -> [RunnerEvent] {
        events.filter { includes(gameId: $0.gameId, timestamp: $0.timestamp) }
    }
}

extension HittingStatLine {
    /// The full line: plate appearances from pitches, running from runner
    /// events. Both lists must already be this hitter's, filtered.
    init(events: [PitchEvent], runnerEvents: [RunnerEvent]) {
        self.init(events: events)
        recordRunning(runnerEvents)
    }
}
