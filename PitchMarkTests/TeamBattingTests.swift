//
//  TeamBattingTests.swift
//  PitchMarkTests
//
//  Team batting rules 44-47 (approved 2026-11-05): which pitches are a
//  team's at-bats, and what each row of the team table adds up.
//

import XCTest
@testable import PitchMark

@MainActor
final class TeamBattingTests: XCTestCase {
    private typealias F = Fixture

    /// Game "game-1": Bombers at home, Sharks away.
    private var games: [Game] {
        var game = Game(opponent: "Sharks", date: F.t0, jerseyNumbers: [])
        game.id = "game-1"
        game.teamId = "bombers"
        game.awayTeamId = "sharks"
        var other = Game(opponent: "Jets", date: F.t0, jerseyNumbers: [])
        other.id = "game-2"
        other.teamId = "bombers"
        return [game, other]
    }

    private func pitch(_ id: String, fielding: String?, game: String = "game-1", hitterId: String? = "hitter-9",
                       outcome: String = "1B", play: BasePlay? = nil, before: BaseOccupancy? = nil) -> PitchEvent {
        var event = F.pitch(id: id, isStrike: true, outcome: outcome, hitterId: hitterId, play: play, basesBefore: before)
        event.gameId = game
        event.fieldingTeamId = fielding
        return event
    }

    private func ids(_ events: [PitchEvent]) -> Set<String> { Set(events.compactMap(\.id)) }

    /// Rule 44: fielded by one team = the other team's at-bat; a pitch
    /// against an opponent with no team counts for nobody.
    func testTheTeamNotFieldingIsBatting() {
        let events = [
            pitch("sharks-pitching", fielding: "sharks"),
            pitch("bombers-pitching", fielding: "bombers"),
            pitch("jets-unknown", fielding: "bombers", game: "game-2")
        ]
        XCTAssertEqual(ids(TeamBatting.battingEvents(events, teamId: "bombers", games: games, rosterHitterIds: [])),
                       ["sharks-pitching"])
        XCTAssertEqual(ids(TeamBatting.battingEvents(events, teamId: "sharks", games: games, rosterHitterIds: [])),
                       ["bombers-pitching"])
    }

    /// Rule 45: no fielding team stamped - counts only for a linked roster batter.
    func testOldPitchCountsByItsBatter() {
        let events = [
            pitch("ours", fielding: nil, hitterId: "hitter-9"),
            pitch("theirs", fielding: nil, hitterId: "hitter-77"),
            pitch("jersey-only", fielding: nil, hitterId: nil)
        ]
        XCTAssertEqual(ids(TeamBatting.battingEvents(events, teamId: "bombers", games: games,
                                                     rosterHitterIds: ["hitter-9"])), ["ours"])
    }

    /// Rule 46: a player's row is their at-bats plus runs scored on
    /// teammates' pitches; running from other teams' games is left out.
    func testPlayerRow() {
        let teammateSingle = pitch(
            "single", fielding: "sharks", hitterId: "hitter-2",
            play: BasePlay(batterCredit: "1B", moves: [
                RunnerMove(runner: RunnerMove.batterKey, from: Base.home, to: Base.first, extraBasesOn: nil),
                RunnerMove(runner: F.r3.id, from: 3, to: Base.scored, extraBasesOn: nil)
            ]),
            before: BaseOccupancy(third: F.r3)
        )
        let ownAtBat = pitch("own", fielding: "sharks", hitterId: "hitter-3", outcome: "Out")
        let steal = { (id: String, game: String) in
            RunnerEvent(id: id, timestamp: F.t0, kind: RunnerEventKind.stolenBase.rawValue, from: 1, to: 2,
                        runner: F.r3, basesBefore: BaseOccupancy(first: F.r3), gameId: game, hitterId: "hitter-3")
        }
        let running = TeamBatting.runnerEvents([steal("here", "game-1"), steal("elsewhere", "game-other")], games: games)
        XCTAssertEqual(running.map(\.id), ["here"])

        let line = TeamBatting.playerLine(hitterId: "hitter-3", battingEvents: [teammateSingle, ownAtBat],
                                          runnerEvents: running)
        XCTAssertEqual(line.plateAppearances, 1)
        XCTAssertEqual(line.atBats, 1)
        XCTAssertEqual(line.hits, 0, "the teammate's single isn't theirs")
        XCTAssertEqual(line.runs, 1)
        XCTAssertEqual(line.stolenBases, 1)
    }

    /// Rule 47: the Team row has jersey-only batters too, and every run
    /// scored on the team's pitches, linked runner or not.
    func testTeamRow() {
        let jerseyOnlyHomer = pitch(
            "homer", fielding: "sharks", hitterId: nil, outcome: "HR",
            play: BasePlay(batterCredit: "HR", moves: [
                RunnerMove(runner: RunnerMove.batterKey, from: Base.home, to: Base.scored, extraBasesOn: nil),
                RunnerMove(runner: F.unlinked.id, from: 2, to: Base.scored, extraBasesOn: nil)
            ]),
            before: BaseOccupancy(second: F.unlinked)
        )
        let linkedOut = pitch("out", fielding: "sharks", hitterId: "hitter-9", outcome: "Out")
        let line = TeamBatting.teamLine(battingEvents: [jerseyOnlyHomer, linkedOut], runnerEvents: [])
        XCTAssertEqual(line.plateAppearances, 2)
        XCTAssertEqual(line.homeRuns, 1, "jersey-only batter counted")
        XCTAssertEqual(line.runs, 2)
        XCTAssertEqual(line.runsBattedIn, 2)
    }
}
