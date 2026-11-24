//
//  HomeGamesTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-24 (unit): Home's unified Games list, My Teams vs
//  Opponents, the New Game form's game and team-schedule entry, and Start
//  Tracking from a scheduled game.
//

import XCTest
@testable import PitchMark

final class HomeGamesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func game(_ id: String, at offset: TimeInterval, kind: GameKind? = nil, scheduled: String? = nil) -> Game {
        var g = Game(id: id, opponent: "Hawks", date: now.addingTimeInterval(offset), jerseyNumbers: [])
        g.kind = kind
        g.scheduledGameId = scheduled
        return g
    }

    private func tourney(gameAt offset: TimeInterval) -> Tourney {
        var t = Tourney()
        t.name = "Summer Slam"
        t.teamId = "reds"
        t.games = [TourneyGame(time: now.addingTimeInterval(offset), opponent: "Lions")]
        return t
    }

    // U1
    func testTheListMergesTrackedAndScheduledGames() {
        let slam = tourney(gameAt: 2 * day)
        var canceled = TeamScheduledGame(teamId: "reds", kind: .friendly, time: now.addingTimeInterval(day), opponent: "Storm")
        canceled.canceled = true
        let scheduled = TeamSchedule.entries(tourneys: [slam], singles: [canceled])
        let tracked = [game("past", at: -day), game("scrim", at: 3 * day, kind: .scrimmage),
                       game("fromSlam", at: 2 * day, scheduled: slam.games[0].id)]
        let parts = HomeGameList.items(tracked: tracked, scheduled: scheduled, now: now)

        XCTAssertEqual(parts.upcoming.map { $0.date.timeIntervalSince(now) }, [day, 2 * day, 3 * day], "soonest first")
        XCTAssertEqual(parts.past.map(\.id), ["g-past"])
        XCTAssertEqual(parts.upcoming.count, 3, "the tracked tourney game shows once, not twice")
        XCTAssertEqual(parts.upcoming[1].detail, "Summer Slam", "a tourney game names its tourney")
        XCTAssertEqual(parts.upcoming[2].detail, "Scrimmage")
        XCTAssertEqual(parts.upcoming[0].detail, "Friendly")
        XCTAssertTrue(parts.upcoming[0].canceled)
        XCTAssertNil(HomeGameList.Item.tracked(game("plain", at: day), entry: nil).detail, "a plain Game needs no third line")
    }

    // Approved 2026-11-24: a followed (shared-link) tourney's games list too.
    func testAFollowedTourneysGamesAreListed() {
        var classic = Tourney()
        classic.name = "Fall Classic"
        classic.games = [TourneyGame(time: now.addingTimeInterval(day), opponent: "Bears")]
        let entries = TeamSchedule.entries(tourneys: [], singles: [], followed: [classic])
        let parts = HomeGameList.items(tracked: [], scheduled: entries, now: now)
        XCTAssertEqual(parts.upcoming.count, 1)
        XCTAssertEqual(parts.upcoming[0].detail, "Fall Classic", "with the tourney's name")
    }

    func testAGameSeenAsTeamAndSharedIsListedOnce() {
        let slam = tourney(gameAt: day)
        var sharedCopy = slam
        sharedCopy.id = "share1"
        let entries = TeamSchedule.entries(tourneys: [slam], singles: [], followed: [sharedCopy])
        XCTAssertEqual(entries.count, 1)
        guard case .tourney = entries[0].source else { return XCTFail("the team copy wins") }
    }

    func testAnUpcomingGameOpensItsCard() {
        XCTAssertTrue(HomeGameList.opensCard(.tracked(game("g", at: day), entry: nil), now: now))
        XCTAssertFalse(HomeGameList.opensCard(.tracked(game("g", at: -60), entry: nil), now: now), "under way: the tracker")
        let entry = TeamSchedule.entries(tourneys: [tourney(gameAt: -day)], singles: [])[0]
        XCTAssertTrue(HomeGameList.opensCard(.scheduled(entry), now: now))
    }

    // U2
    func testMyTeamsAndOpponents() {
        var played = game("1", at: 0)
        played.teamId = "reds"
        played.awayTeamId = "hawks"
        let games: [Game] = [played]
        func side(_ id: String, mine: Set<String> = [], opp: Set<String> = [], made: Set<String> = []) -> TeamSides.Side {
            TeamSides.side(teamId: id, movedToMine: mine, movedToOpponents: opp, madeAsOpponent: made, games: games)
        }
        XCTAssertEqual(side("reds"), .mine, "picked as Our team")
        XCTAssertEqual(side("hawks"), .opponent, "only ever an opponent")
        XCTAssertEqual(side("storm", made: ["storm"]), .opponent, "made from the Opponent picker")
        XCTAssertEqual(side("storm"), .mine, "made from Teams +")
        XCTAssertEqual(side("hawks", mine: ["hawks"]), .mine, "the coach's move wins")
        XCTAssertEqual(side("reds", opp: ["reds"]), .opponent, "the coach's move wins")
    }

    // U3
    func testTheFormMakesTheGameAndTheTeamEntry() {
        var details = NewGameDetails(arriveAt: now.addingTimeInterval(-3600), field: "7", notes: "Away jerseys")
        details.venue = TourneyPlace(name: "Riverside Park", address: "1 River Rd", latitude: 1, longitude: 2)
        let plan = NewGamePlan.make(opponent: "Storm", date: now, ourTeamId: "reds", opponentTeamId: "storm",
                                    kind: .scrimmage, trackingMode: .scout, details: details,
                                    schedulesForTeam: true, entryId: "e1")
        XCTAssertEqual(plan.game.teamId, "reds")
        XCTAssertEqual(plan.game.awayTeamId, "storm")
        XCTAssertEqual(plan.game.kind, .scrimmage)
        XCTAssertEqual(plan.game.trackingMode, .scout)
        XCTAssertEqual(plan.game.field, "7")
        XCTAssertEqual(plan.game.venueName, "Riverside Park")
        XCTAssertEqual(plan.game.scheduledGameId, "e1", "linked, so it lists once")
        XCTAssertEqual(plan.entry?.id, "e1")
        XCTAssertEqual(plan.entry?.teamId, "reds")
        XCTAssertEqual(plan.entry?.kind, .scrimmage)
        XCTAssertEqual(plan.entry?.time, now)
        XCTAssertEqual(plan.entry?.venue.name, "Riverside Park")
        XCTAssertEqual(plan.entry?.notes, "Away jerseys")
        XCTAssertEqual(NewGamePlan.details(of: plan.game), details, "the card reads the same details back")

        let noTeam = NewGamePlan.make(opponent: "Storm", date: now, ourTeamId: nil, opponentTeamId: nil, kind: .game,
                                      trackingMode: .coach, details: details, schedulesForTeam: true)
        XCTAssertNil(noTeam.entry, "no team: the game only")
        XCTAssertNil(noTeam.game.kind, "a Game is stored as before")
        let notMine = NewGamePlan.make(opponent: "Storm", date: now, ourTeamId: "reds", opponentTeamId: nil, kind: .game,
                                       trackingMode: .coach, details: details, schedulesForTeam: false)
        XCTAssertNil(notMine.entry, "not a team you schedule for")
        XCTAssertNil(notMine.game.scheduledGameId)
    }

    // U4
    func testStartTrackingFillsInTheGame() {
        var single = TeamScheduledGame(teamId: "reds", kind: .friendly, time: now, arriveAt: now.addingTimeInterval(-1800),
                                       opponent: " Storm ")
        single.field = "3"
        single.venue = TourneyPlace(name: "Riverside Park")
        let entry = TeamSchedule.entries(tourneys: [], singles: [single])[0]
        let game = NewGamePlan.game(from: entry, kind: .friendly)
        XCTAssertEqual(game.teamId, "reds")
        XCTAssertEqual(game.opponent, "Storm")
        XCTAssertEqual(game.date, now)
        XCTAssertEqual(game.kind, .friendly)
        XCTAssertEqual(game.scheduledGameId, single.id)
        XCTAssertEqual(game.field, "3")
        XCTAssertEqual(game.venueName, "Riverside Park")
        XCTAssertEqual(game.arriveAt, now.addingTimeInterval(-1800))
    }
}
