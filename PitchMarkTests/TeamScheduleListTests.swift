//
//  TeamScheduleListTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-24 (unit): the Team Schedule merges tourney and single
//  games by date, folds past games, keeps canceled marked and each type's
//  label; the calendar's day marks and a tracked game replacing its
//  scheduled entry; the stats rule for Friendlies and Scrimmages.
//

import XCTest
@testable import PitchMark

final class TeamScheduleListTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func tourney(gamesAt offsets: [TimeInterval], canceledFirst: Bool = false) -> Tourney {
        var t = Tourney()
        t.name = "Summer Slam"
        t.teamId = "reds"
        t.games = offsets.map { TourneyGame(time: now.addingTimeInterval($0), opponent: "Hawks") }
        if canceledFirst { t.games[0].canceled = true }
        return t
    }

    func testTourneyAndSingleGamesMergeByDate() {
        let single = TeamScheduledGame(teamId: "reds", kind: .scrimmage, time: now.addingTimeInterval(2 * day),
                                       opponent: "Storm")
        let entries = TeamSchedule.entries(tourneys: [tourney(gamesAt: [3 * day, day])], singles: [single])
        XCTAssertEqual(entries.map { $0.time.timeIntervalSince(now) }, [day, 2 * day, 3 * day])
        XCTAssertEqual(entries.map(\.label), ["Summer Slam", "Scrimmage", "Summer Slam"],
                       "a tourney game says its tourney; a single game its type")
        XCTAssertEqual(entries[1].title, "vs Storm")
        XCTAssertEqual(entries[1].game.kind, .scrimmage, "Track carries the type")
    }

    func testArchivedTourneysAreLeftOut() {
        var t = tourney(gamesAt: [day])
        t.archivedAt = now
        XCTAssertTrue(TeamSchedule.entries(tourneys: [t], singles: []).isEmpty)
    }

    func testPastGamesFoldBelowAndCanceledStayMarked() {
        var single = TeamScheduledGame(teamId: "reds", time: now.addingTimeInterval(day))
        single.canceled = true
        let entries = TeamSchedule.entries(tourneys: [tourney(gamesAt: [-2 * day, -day, 2 * day])], singles: [single])
        let parts = TeamSchedule.split(entries, now: now)
        XCTAssertEqual(parts.upcoming.map { $0.time.timeIntervalSince(now) }, [day, 2 * day], "soonest first")
        XCTAssertEqual(parts.past.map { $0.time.timeIntervalSince(now) }, [-day, -2 * day], "most recent first")
        XCTAssertTrue(parts.upcoming[0].canceled, "a canceled game stays, marked")
    }

    func testATrackedGameReplacesItsScheduledEntry() {
        let entries = TeamSchedule.entries(tourneys: [tourney(gamesAt: [day, 2 * day])], singles: [])
        var tracked = Game(id: "g1", opponent: "Hawks", date: now.addingTimeInterval(day), jerseyNumbers: [])
        tracked.scheduledGameId = entries[0].id
        let shown = TeamSchedule.calendarEntries(entries, trackedGames: [tracked])
        XCTAssertEqual(shown.map(\.id), [entries[1].id])

        let marks = TeamSchedule.dayMarks(tracked: [tracked], scheduled: shown)
        let cal = Calendar.current
        XCTAssertEqual(marks[cal.startOfDay(for: now.addingTimeInterval(day))], .init(tracked: 1, scheduled: 0))
        XCTAssertEqual(marks[cal.startOfDay(for: now.addingTimeInterval(2 * day))], .init(tracked: 0, scheduled: 1))
    }

    func testFriendliesAndScrimmagesAskAndCanBeLeftOut() {
        XCTAssertFalse(GameKind.game.asksAboutStats)
        XCTAssertTrue(GameKind.friendly.asksAboutStats)
        XCTAssertTrue(GameKind.scrimmage.asksAboutStats)
        XCTAssertFalse(TeamSchedule.asksAboutStats(nil), "an older game is a Game")

        var game = Game(id: "g1", opponent: "Hawks", date: now, jerseyNumbers: [])
        XCTAssertTrue(game.countsInStats(includedArchivedIds: []))
        game.kind = .scrimmage
        game.leftOutOfStats = true
        XCTAssertFalse(game.countsInStats(includedArchivedIds: []), "left out when tracking began")
        game.leftOutOfStats = nil
        XCTAssertTrue(game.countsInStats(includedArchivedIds: []), "counted")
    }

    func testASingleGameIsSavedAndRead() {
        var g = TeamScheduledGame(teamId: "reds", kind: .friendly, time: now, arriveAt: now.addingTimeInterval(-3600),
                                  opponent: "Storm")
        g.field = "7"
        g.canceled = true
        g.venue = TourneyPlace(name: "Riverside Park", address: "1 River Rd")
        let back = TeamScheduledGame(id: g.id, firestoreData: g.firestoreData)
        XCTAssertEqual(back, g)
        XCTAssertNil(TeamScheduledGame(id: "x", firestoreData: ["kind": "game"]), "no team or time, no game")
    }

    @MainActor
    func testTheStoreKeepsEachTeamsSchedule() {
        let store = TourneyStore(inMemory: true)
        store.startTeams([.init(id: "reds", name: "Reds", canEdit: true), .init(id: "hawks", name: "Hawks", canEdit: false)])
        store.saveTeamGame(TeamScheduledGame(teamId: "reds", kind: .scrimmage, time: now, opponent: "Storm"))
        store.saveTeamGame(TeamScheduledGame(teamId: "hawks", time: now, opponent: "Reds"))
        XCTAssertEqual(store.schedule(teamId: "reds").map(\.label), ["Scrimmage"])
        XCTAssertEqual(store.allScheduled.count, 2, "the calendar sees every team")
        XCTAssertTrue(store.canEditTeam("reds"))
        XCTAssertFalse(store.canEditTeam("hawks"))
        store.deleteTeamGame(store.teamGames.first { $0.teamId == "reds" }!)
        XCTAssertTrue(store.schedule(teamId: "reds").isEmpty)
    }
}
