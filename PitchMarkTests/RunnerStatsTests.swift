//
//  RunnerStatsTests.swift
//  PitchMarkTests
//
//  Phase 3 rules 21-23: SB/CS/PO on the hitting line, the stats filters,
//  and where runner records are saved (RunnerEventStore paths).
//

import XCTest
@testable import PitchMark

@MainActor
final class RunnerStatsTests: XCTestCase {
    private typealias F = Fixture

    private func event(_ kind: RunnerEventKind, id: String = UUID().uuidString, game: String? = "game-1",
                       at timestamp: Date = Fixture.t0, runner: BaseRunner = Fixture.r1) -> RunnerEvent {
        RunnerEvent(id: id, timestamp: timestamp, kind: kind.rawValue, from: 1,
                    to: BaseRunnerRules.destination(for: kind, from: 1), runner: runner,
                    basesBefore: BaseOccupancy(first: runner), gameId: game, hitterId: runner.hitterId)
    }

    /// Rule 21: SB, CS and PO each count their own kind; ADV and SUB count nothing.
    func testRunningCounts() {
        var line = HittingStatLine()
        line.recordRunning([
            event(.stolenBase), event(.stolenBase), event(.stolenBase),
            event(.caughtStealing),
            event(.pickedOff), event(.pickedOff),
            event(.advanced), event(.substitution)
        ])
        XCTAssertEqual(line.stolenBases, 3)
        XCTAssertEqual(line.caughtStealing, 1)
        XCTAssertEqual(line.pickedOff, 2)
        XCTAssertEqual(line.plateAppearances, 0, "running isn't a plate appearance")
        XCTAssertEqual(line.atBats, 0)
    }

    /// Rule 22: the same filters as the rest of Hitting Stats.
    func testFiltersApplyToRunnerEvents() {
        let inGame = event(.stolenBase, game: "game-1", at: F.t0)
        let archived = event(.stolenBase, game: "game-archived", at: F.t0)
        let otherTeam = event(.stolenBase, game: "game-other-team", at: F.t0)
        let old = event(.stolenBase, game: "game-1", at: F.t0.addingTimeInterval(-90 * 86_400))
        let all = [inGame, archived, otherTeam, old]

        XCTAssertEqual(StatsEventFilter(excludedGameIds: ["game-archived"]).runnerEvents(all).map(\.id).sorted(),
                       [inGame.id, otherTeam.id, old.id].sorted(), "archived game left out")

        let recent = StatsEventFilter(dateRange: F.t0.addingTimeInterval(-7 * 86_400)...F.t0)
        XCTAssertEqual(Set(recent.runnerEvents(all).map(\.id)), [inGame.id, archived.id, otherTeam.id])

        let team = StatsEventFilter(teamGameIds: ["game-1"])
        XCTAssertEqual(Set(team.runnerEvents(all).map(\.id)), [inGame.id, old.id])

        let thisGame = StatsEventFilter(focusGameId: "game-1", excludedGameIds: ["game-1"], teamGameIds: [])
        XCTAssertEqual(Set(thisGame.runnerEvents(all).map(\.id)), [inGame.id, old.id],
                       "This Game ignores the other filters")
    }

    /// Rule 22: pitches and runner events go through the same filter, so the
    /// line's PA and SB always describe the same games.
    func testPitchesAndRunningShareTheFilter() {
        let filter = StatsEventFilter(excludedGameIds: ["game-archived"])
        let keptPitch = F.pitch(isBall: true, balls: 0, strikes: 0)            // ball four in game-1
        var droppedPitch = F.pitch(isBall: true, balls: 0, strikes: 0)
        droppedPitch.gameId = "game-archived"
        let line = HittingStatLine(
            events: filter.pitches([keptPitch, droppedPitch]),
            runnerEvents: filter.runnerEvents([event(.stolenBase, game: "game-1"), event(.stolenBase, game: "game-archived")])
        )
        XCTAssertEqual(line.walks, 1)
        XCTAssertEqual(line.stolenBases, 1)
    }

    /// Rule 23 (and rule 4's storage): where a record is written.
    func testSavePathsOffline() {
        let linked = event(.stolenBase, id: "sb-1")
        XCTAssertEqual(
            RunnerEventStore.savePaths(for: linked, liveId: nil, ownerUid: "owner", gameId: "game-1"),
            ["users/owner/games/game-1/runnerEvents/sb-1", "hitters/hitter-1/runnerEvents/sb-1"]
        )
        let unlinked = event(.stolenBase, id: "sb-2", runner: F.unlinked)
        XCTAssertEqual(
            RunnerEventStore.savePaths(for: unlinked, liveId: nil, ownerUid: "owner", gameId: "game-1"),
            ["users/owner/games/game-1/runnerEvents/sb-2"],
            "no linked player: no player copy"
        )
    }

    /// In a live room the device writes the room and the owner's game; the
    /// owner's listener writes the player copy.
    func testSavePathsLive() {
        let linked = event(.caughtStealing, id: "cs-1")
        XCTAssertEqual(
            RunnerEventStore.savePaths(for: linked, liveId: "live-1", ownerUid: "owner", gameId: "game-1"),
            ["liveGames/live-1/runnerEvents/cs-1", "users/owner/games/game-1/runnerEvents/cs-1"]
        )
    }

    /// Undo tries every copy, the player's included.
    func testDeletePaths() {
        let linked = event(.stolenBase, id: "sb-3")
        XCTAssertEqual(
            RunnerEventStore.deletePaths(for: linked, liveId: "live-1", ownerUid: "owner", gameId: "game-1"),
            ["liveGames/live-1/runnerEvents/sb-3", "users/owner/games/game-1/runnerEvents/sb-3",
             "hitters/hitter-1/runnerEvents/sb-3"]
        )
    }

    /// The saved fields: Codable form plus the room id the partner-create
    /// rule checks; and they decode back to the same event.
    func testSavedDataRoundTrips() throws {
        let original = event(.pickedOff, id: "po-1")
        let live = try XCTUnwrap(RunnerEventStore.savedData(for: original, liveId: "live-1"))
        XCTAssertEqual(live["liveId"] as? String, "live-1")
        XCTAssertEqual(live["kind"] as? String, "PO")
        XCTAssertEqual(live["hitterId"] as? String, "hitter-1")
        XCTAssertEqual(RunnerEventStore.decode(live), original)

        let offline = try XCTUnwrap(RunnerEventStore.savedData(for: original, liveId: nil))
        XCTAssertNil(offline["liveId"])
    }
}
