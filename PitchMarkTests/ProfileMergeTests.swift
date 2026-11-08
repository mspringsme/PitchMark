//
//  ProfileMergeTests.swift
//  PitchMarkTests
//
//  Batch 7 (approved 2026-11-01): Link Profiles, Merge Duplicates, the
//  cleanup after them, and the player archive's names. Expected values come
//  from the approved rules list, not from running the code.
//

import XCTest
@testable import PitchMark

private enum M {
    static let me = "coach-1"
    static let other = "coach-2"
    static func day(_ n: Double) -> Date { Date(timeIntervalSince1970: 1_000_000 + n * 86_400) }

    static func team(_ id: String, by uid: String = me) -> Team {
        Team(id: id, name: id, createdByUid: uid, createdAt: day(0))
    }

    static func row(
        _ id: String,
        name: String = "Kenzie",
        team: Team,
        player: String? = nil,
        pitcher: String? = nil,
        hitter: String? = nil,
        jersey: String? = nil,
        age: Double = 10
    ) -> PlayerRosterEntry {
        let tp = TeamPlayer(
            id: id,
            name: name,
            jerseyNumber: jersey,
            pitcherId: pitcher,
            playerId: player,
            hitterId: hitter,
            createdByUid: team.createdByUid,
            createdAt: day(age)
        )
        return PlayerRosterEntry(teamPlayer: tp, team: team)
    }

    static func pitcher(_ id: String, name: String = "Kenzie", owner: String = me, age: Double = 10) -> Pitcher {
        Pitcher(id: id, name: name, templateId: nil, ownerUid: owner, sharedWith: [], claimedByUid: nil, createdAt: day(age))
    }

    static func player(
        _ id: String,
        name: String = "Kenzie",
        owner: String = me,
        pitcher: String? = nil,
        hitter: String? = nil,
        linkedPitchers: [String]? = nil,
        linkedHitters: [String]? = nil,
        age: Double = 10
    ) -> Player {
        Player(
            id: id, name: name, ownerUid: owner, pitcherId: pitcher, hitterId: hitter,
            createdAt: day(age), linkedPitcherIds: linkedPitchers, linkedHitterIds: linkedHitters
        )
    }

    static func profile(
        _ entries: [PlayerRosterEntry] = [],
        pitchers: [Pitcher] = [],
        players: [Player] = []
    ) -> PlayerProfile {
        PlayerProfile(
            id: entries.first?.id ?? pitchers.first?.id ?? UUID().uuidString,
            entries: entries, pitchers: pitchers, players: players
        )
    }

    static func tp(player: String? = nil, pitcher: String? = nil, hitter: String? = nil) -> TeamPlayer {
        TeamPlayer(id: UUID().uuidString, name: "x", pitcherId: pitcher, playerId: player, hitterId: hitter, createdByUid: me)
    }

    struct Boom: Error {}
}

// MARK: - Who counts as one player (rules 1-3)

final class PlayerProfileTests: XCTestCase {
    func testRecordsSharingAnIdAreOnePlayerThroughAChain() {
        let reds = M.team("reds"), blues = M.team("blues")
        // Row on Reds names pitcher p1; row on Blues names identity pl1;
        // Player pl1 names p1 - so all three are one kid.
        let a = M.row("a", team: reds, pitcher: "p1")
        let b = M.row("b", team: blues, player: "pl1")
        let identity = M.player("pl1", pitcher: "p1")
        let profiles = PlayerLinks.profiles(rosterEntries: [a, b], pitchers: [], players: [identity])
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].entries.count, 2)
    }

    func testAPlayersExtraHistoriesJoinItsProfile() {
        let reds = M.team("reds")
        let row = M.row("a", team: reds, player: "pl1")
        let identity = M.player("pl1", pitcher: "p1", linkedPitchers: ["p9"])
        let oldPitcher = M.pitcher("p9")
        let profiles = PlayerLinks.profiles(rosterEntries: [row], pitchers: [oldPitcher], players: [identity])
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].pitchers.map(\.id), ["p9"])
    }

    func testDifferentIdsStaySeparateEvenWithTheSameName() {
        let reds = M.team("reds")
        let profiles = PlayerLinks.profiles(
            rosterEntries: [M.row("a", team: reds, pitcher: "p1"), M.row("b", team: reds, pitcher: "p2")],
            pitchers: [], players: []
        )
        XCTAssertEqual(profiles.count, 2)
    }

    func testAPlayerRecordWithNothingBehindItIsNotShown() {
        let profiles = PlayerLinks.profiles(rosterEntries: [], pitchers: [], players: [M.player("pl1", pitcher: "p1")])
        XCTAssertTrue(profiles.isEmpty)
    }

    func testAlphabeticalThenOldestFirstByOldestPiece() {
        let reds = M.team("reds")
        // Two Kenzies: the second's row is newer, but her Pitcher is the
        // oldest piece of either, so she lists first.
        let newer = M.row("a", name: "Kenzie", team: reds, pitcher: "p1", age: 5)
        let olderByPitcher = M.row("b", name: "Kenzie", team: reds, pitcher: "p2", age: 8)
        let p2 = M.pitcher("p2", age: 1)
        let ava = M.row("c", name: "ava", team: reds, pitcher: "p3", age: 9)
        let profiles = PlayerLinks.profiles(rosterEntries: [newer, olderByPitcher, ava], pitchers: [p2], players: [])
        XCTAssertEqual(profiles.map { $0.entries.first?.teamPlayer.id }, ["c", "b", "a"])
        XCTAssertEqual(profiles[1].createdAt, M.day(1))
    }
}

// MARK: - Combining (rules 4-5)

final class CombinePlanTests: XCTestCase {
    private let reds = M.team("reds")

    func testTheOldestIsKeptWhateverTheOrder() {
        let old = M.profile([M.row("a", team: reds, pitcher: "p1", age: 1)])
        let young = M.profile([M.row("b", team: reds, pitcher: "p2", age: 5)])
        for order in [[old, young], [young, old]] {
            guard case .success(let plan) = PlayerLinks.combinePlan(order, currentUid: M.me) else {
                return XCTFail("should combine")
            }
            XCTAssertEqual(plan.keep.id, old.id)
            XCTAssertEqual(plan.fold.map(\.id), [young.id])
        }
    }

    func testOneProfileThatIsntFullyYoursBecomesTheKeptOne() {
        let theirs = M.team("theirs", by: M.other)
        let old = M.profile([M.row("a", team: reds, pitcher: "p1", age: 1)])
        let locked = M.profile([M.row("b", team: theirs, pitcher: "p2", age: 5)])
        guard case .success(let plan) = PlayerLinks.combinePlan([old, locked], currentUid: M.me) else {
            return XCTFail("should combine")
        }
        XCTAssertEqual(plan.keep.id, locked.id)
        XCTAssertEqual(plan.fold.map(\.id), [old.id])
    }

    func testAnotherCoachsPitcherMakesAProfileNotFullyYours() {
        let mine = M.profile([M.row("a", team: reds, pitcher: "p1", age: 5)])
        let sharedIn = M.profile(pitchers: [M.pitcher("p2", owner: M.other, age: 9)])
        guard case .success(let plan) = PlayerLinks.combinePlan([mine, sharedIn], currentUid: M.me) else {
            return XCTFail("should combine")
        }
        XCTAssertEqual(plan.keep.id, sharedIn.id)
    }

    func testTwoThatArentYoursAreRefusedByName() {
        let theirs = M.team("theirs", by: M.other)
        let one = M.profile([M.row("a", name: "Ava", team: theirs, pitcher: "p1", age: 1)])
        let two = M.profile([M.row("b", name: "Bea", team: theirs, pitcher: "p2", age: 2)])
        let mine = M.profile([M.row("c", team: reds, pitcher: "p3", age: 3)])
        guard case .failure(.notEditable(let names)) = PlayerLinks.combinePlan([mine, two, one], currentUid: M.me) else {
            return XCTFail("should refuse")
        }
        XCTAssertEqual(names, ["Ava (theirs)", "Bea (theirs)"])
    }

    func testOneProfileIsNothingToCombine() {
        let one = M.profile([M.row("a", team: reds, pitcher: "p1")])
        guard case .failure(.needsTwo) = PlayerLinks.combinePlan([one], currentUid: M.me) else {
            return XCTFail("should need two")
        }
    }
}

// MARK: - Roster rows and records (rules 6-9)

final class ProfileMergeRowTests: XCTestCase {
    private let reds = M.team("reds"), blues = M.team("blues"), greens = M.team("greens")

    private func steps(_ mode: AuthManager.ProfileCombineMode, keep: PlayerProfile, fold: [PlayerProfile]) -> [String] {
        ProfileMerge.rowSteps(keep: keep, fold: fold, mode: mode).map {
            "\($0.action == .remove ? "remove" : "repoint") \($0.entry.teamPlayer.id ?? "")"
        }
    }

    func testMergeRemovesTheExtraRowOnASharedTeamAndRepointsTheRest() {
        let keep = M.profile([M.row("k1", team: reds, pitcher: "p1")])
        let dup = M.profile([M.row("d1", team: reds, pitcher: "p2"), M.row("d2", team: blues, pitcher: "p2")])
        XCTAssertEqual(steps(.mergeDuplicate, keep: keep, fold: [dup]), ["remove d1", "repoint d2"])
    }

    func testLinkKeepsEveryRow() {
        let keep = M.profile([M.row("k1", team: reds, pitcher: "p1")])
        let dup = M.profile([M.row("d1", team: reds, pitcher: "p2"), M.row("d2", team: blues, pitcher: "p2")])
        XCTAssertEqual(steps(.link, keep: keep, fold: [dup]), ["repoint d1", "repoint d2"])
    }

    func testAMovedRowCoversItsTeamForTheRowsAfterIt() {
        let keep = M.profile([M.row("k1", team: reds, pitcher: "p1")])
        let dup1 = M.profile([M.row("d1", team: greens, pitcher: "p2")])
        let dup2 = M.profile([M.row("d2", team: greens, pitcher: "p3")])
        XCTAssertEqual(steps(.mergeDuplicate, keep: keep, fold: [dup1, dup2]), ["repoint d1", "remove d2"])
    }

    func testARepointedRowTakesTheKeptIdAndNameAndOnlyEmptyRecordsMove() {
        let canonical = M.player("pl1", name: "Kenzie Smith", pitcher: "p1", hitter: "h1")
        let dup = TeamPlayer(id: "d1", name: "Kenz", pitcherId: "p2", playerId: "pl2", hitterId: "h2", createdByUid: M.me)

        let bothEmpty = ProfileMerge.repoint(dup, onto: canonical, keptPitcherId: nil, keptHitterId: nil)
        XCTAssertEqual(bothEmpty, .init(playerId: "pl1", name: "Kenzie Smith", pitcherId: "p1", hitterId: "h1"))

        let pitchingHasHistory = ProfileMerge.repoint(dup, onto: canonical, keptPitcherId: "p2", keptHitterId: nil)
        XCTAssertEqual(pitchingHasHistory, .init(playerId: "pl1", name: "Kenzie Smith", pitcherId: nil, hitterId: "h1"))
        XCTAssertNil(pitchingHasHistory?.data["pitcherId"], "a record with history stays on the row")
        XCTAssertEqual(pitchingHasHistory?.data["playerId"] as? String, "pl1")

        let hittingHasHistory = ProfileMerge.repoint(dup, onto: canonical, keptPitcherId: nil, keptHitterId: "h2")
        XCTAssertEqual(hittingHasHistory?.hitterId, nil)
        XCTAssertEqual(hittingHasHistory?.pitcherId, "p1")
    }

    func testOnlyTheDuplicatesOwnRecordsNeedAHistoryCheck() {
        let canonical = M.player("pl1", pitcher: "p1", hitter: "h1")
        let sameRecords = ProfileMerge.recordsToCheck(on: M.tp(pitcher: "p1", hitter: "h1"), canonical: canonical)
        XCTAssertNil(sameRecords.pitcherId)
        XCTAssertNil(sameRecords.hitterId)
        let ownRecords = ProfileMerge.recordsToCheck(on: M.tp(pitcher: "p2", hitter: "h2"), canonical: canonical)
        XCTAssertEqual(ownRecords.pitcherId, "p2")
        XCTAssertEqual(ownRecords.hitterId, "h2")
    }

    func testWhatARepointedRowLeavesBehindNeverIncludesAKeptRecord() {
        let canonical = M.player("pl1", pitcher: "p1", hitter: "h1")
        let dup = M.tp(player: "pl2", pitcher: "p2", hitter: "h2")
        XCTAssertEqual(
            ProfileMerge.leftBehind(by: dup, canonical: canonical, keptPitcherId: "p2", keptHitterId: nil),
            .init(playerId: "pl2", pitcherId: nil, hitterId: "h2")
        )
        XCTAssertEqual(
            ProfileMerge.leftBehind(by: M.tp(player: "pl1", pitcher: "p2"), canonical: canonical, keptPitcherId: nil, keptHitterId: nil),
            .init(playerId: nil, pitcherId: "p2", hitterId: nil),
            "the kept identity is never left behind"
        )
    }

    func testEveryFoldedRecordIsConsideredForTheKeptPlayersHistories() {
        let canonical = M.player("pl1", pitcher: "p1", hitter: "h1", linkedPitchers: ["p8"])
        let dup = M.profile(
            [M.row("d1", team: blues, player: "pl2", pitcher: "p2", hitter: "h2")],
            pitchers: [M.pitcher("p9")],
            players: [M.player("pl2", pitcher: "p2", hitter: "h2", linkedPitchers: ["p8", "p7"], linkedHitters: ["h7"])]
        )
        let records = ProfileMerge.foldedRecords([dup], canonical: canonical)
        XCTAssertEqual(Set(records.pitcherIds), ["p2", "p7", "p9"], "p8 is already the kept player's")
        XCTAssertEqual(Set(records.hitterIds), ["h2", "h7"])
        XCTAssertEqual(records.playerIds, ["pl2"])
    }

    func testANewTeamGetsARowForTheKeptPlayerWithABlankJersey() {
        let canonical = M.player("pl1", name: "Kenzie", pitcher: "p1", hitter: "h1")
        let row = ProfileMerge.newRosterRow(for: canonical, rowId: "r9", jerseyNumber: nil, createdByUid: M.me, createdAt: M.day(3))
        XCTAssertEqual(row.id, "r9")
        XCTAssertEqual(row.playerId, "pl1")
        XCTAssertEqual(row.pitcherId, "p1")
        XCTAssertEqual(row.hitterId, "h1")
        XCTAssertEqual(row.name, "Kenzie")
        XCTAssertNil(row.jerseyNumber)
    }
}

// MARK: - Cleanup (rules 10-13)

final class ProfileMergeCleanupTests: XCTestCase {
    private let canonical = M.player("pl1", pitcher: "p1", hitter: "h1", linkedPitchers: ["p8"], linkedHitters: ["h8"])
    private let all = ProfileMerge.Candidates(playerId: "pl2", pitcherId: "p2", hitterId: "h2")

    func testOnlyWhatNoRowReferencesIsDeleted() {
        let reads: [Result<[TeamPlayer], Error>] = [
            .success([M.tp(player: "pl1", pitcher: "p1", hitter: "h1")]),
            .success([M.tp(player: "pl2", pitcher: "p1", hitter: "h1")]),
        ]
        XCTAssertEqual(
            ProfileMerge.unreferenced(all, canonical: canonical, rosterReads: reads),
            .init(playerId: nil, pitcherId: "p2", hitterId: "h2"),
            "pl2 is still on another team's row"
        )
    }

    func testOneUnreadableRosterMeansNothingIsDeleted() {
        let reads: [Result<[TeamPlayer], Error>] = [
            .success([M.tp(player: "pl1", pitcher: "p1", hitter: "h1")]),
            .failure(M.Boom()),
        ]
        XCTAssertNil(ProfileMerge.unreferenced(all, canonical: canonical, rosterReads: reads))
    }

    func testNoTeamsOrNoRowsMeansNothingIsDeleted() {
        XCTAssertNil(ProfileMerge.unreferenced(all, canonical: canonical, rosterReads: []))
        XCTAssertNil(ProfileMerge.unreferenced(all, canonical: canonical, rosterReads: [.success([]), .success([])]))
    }

    func testTheKeptPlayersOwnRecordsAreNeverDeleted() {
        let own = ProfileMerge.Candidates(playerId: "pl1", pitcherId: "p8", hitterId: "h1")
        XCTAssertTrue(ProfileMerge.excludingKept(own, canonical: canonical).isEmpty)
        XCTAssertNil(ProfileMerge.unreferenced(own, canonical: canonical, rosterReads: [.success([M.tp(player: "x")])]))
        XCTAssertEqual(
            ProfileMerge.excludingKept(.init(playerId: "pl2", pitcherId: "p1", hitterId: "h8"), canonical: canonical),
            .init(playerId: "pl2", pitcherId: nil, hitterId: nil)
        )
    }

    func testHistoryIsPitchesOrRunnerEventsAndAFailedCheckCountsAsHistory() {
        XCTAssertFalse(ProfileMerge.hasHistory([.success(false), .success(false)]))
        XCTAssertTrue(ProfileMerge.hasHistory([.success(false), .success(true)]), "a pinch runner's steals")
        XCTAssertTrue(ProfileMerge.hasHistory([.success(true), .success(false)]))
        XCTAssertTrue(ProfileMerge.hasHistory([.success(false), .failure(M.Boom())]))
    }

    func testAHittersHistoryIncludesItsRunnerEvents() {
        XCTAssertEqual(ProfileMerge.historyPaths(hitterId: "h2"), ["hitters/h2/pitchEvents", "hitters/h2/runnerEvents"])
        XCTAssertEqual(ProfileMerge.historyPaths(pitcherId: "p2"), ["pitchers/p2/pitchEvents"])
    }

    func testAPlayerRecordsLinkedHistoriesMoveBeforeItGoes() {
        let dup = M.player("pl2", pitcher: "p2", hitter: "h2", linkedPitchers: ["p8", "p7"], linkedHitters: ["h7"])
        let links = ProfileMerge.linksToMove(from: dup, onto: canonical)
        XCTAssertEqual(links.pitcherIds, ["p7"], "p8 is already the kept player's")
        XCTAssertEqual(links.hitterIds, ["h7"])

        let bare = ProfileMerge.linksToMove(from: M.player("pl3", pitcher: "p3"), onto: canonical)
        XCTAssertTrue(bare.pitcherIds.isEmpty && bare.hitterIds.isEmpty)
    }
}

// MARK: - Open game and archive (rules 14-16)

final class ProfileArchiveTests: XCTestCase {
    private let reds = M.team("reds"), blues = M.team("blues")

    func testPlayersOnTheOpenGamesTeamsAreLocked() {
        let onReds = M.profile([M.row("a", name: "Ava", team: reds, pitcher: "p1")])
        let onBlues = M.profile([M.row("b", name: "Bea", team: blues, pitcher: "p2")])
        let noTeam = M.profile(pitchers: [M.pitcher("p3")])
        let locked = ProfileMerge.lockedByOpenGame([onReds, onBlues, noTeam], openGameTeamIds: ["blues", "away"])
        XCTAssertEqual(locked.map(\.id), [onBlues.id])
        XCTAssertTrue(ProfileMerge.lockedByOpenGame([onReds, onBlues], openGameTeamIds: []).isEmpty)
    }

    func testTheLockMessageNamesTheAction() {
        XCTAssertTrue(OpenGameLock.message(for: "Ava").hasSuffix("then archive."))
        XCTAssertTrue(OpenGameLock.message(for: "Ava, Bea", plural: true, then: "merge").hasSuffix("are on a team in the game that's open right now. Close the game first, then merge."))
    }

    func testArchiveNamesEveryRowCarryingTheRecordOnceIgnoringCase() {
        let names = ArchiveScope.names(
            hiddenBy: ["p1"],
            rosterEntries: [
                M.row("a", name: "Maci", team: reds, pitcher: "p1"),
                M.row("b", name: "maci ", team: blues, pitcher: "p1"),
                M.row("c", name: "Colbie", team: blues, pitcher: "p1"),
                M.row("d", name: "Ella", team: blues, pitcher: "p9"),
            ],
            pitchers: [M.pitcher("p1", name: "Old Name")]
        )
        XCTAssertEqual(names, ["Maci", "Colbie"], "the Pitcher's own name only counts when no row carries it")
    }

    func testArchiveNamesAPitcherNoRowCarries() {
        let names = ArchiveScope.names(hiddenBy: ["p5"], rosterEntries: [], pitchers: [M.pitcher("p5", name: "Ella")])
        XCTAssertEqual(names, ["Ella"])
    }

    func testArchiveSentence() {
        XCTAssertEqual(ArchiveScope.sentence([]), "")
        XCTAssertEqual(ArchiveScope.sentence(["A"]), "A")
        XCTAssertEqual(ArchiveScope.sentence(["A", "B"]), "A and B")
        XCTAssertEqual(ArchiveScope.sentence(["A", "B", "C"]), "A, B and C")
    }
}

// MARK: - Names (2026-11-02, approved: Home showed "Jug" for Juju)

final class PlayerNameTests: XCTestCase {
    private let reds = M.team("reds")

    func testHomeShowsTheOldestRosterRowsNameNotALeftoverRecord() {
        // Juju's real data: her old record still says "Jug" and sorts first.
        let row = M.row("r1", name: "Juju", team: reds, player: "pl1", pitcher: "p2")
        let identity = M.player("pl1", name: "Juju", pitcher: "p2", linkedPitchers: ["p1"])
        let profiles = PlayerLinks.profiles(
            rosterEntries: [row],
            pitchers: [M.pitcher("p1", name: "Jug", age: 1), M.pitcher("p2", name: "Juju", age: 3)],
            players: [identity]
        )
        XCTAssertEqual(profiles.map(\.name), ["Juju"])
        let rows = PlayerDirectory.rows(rosterEntries: [row], pitchers: [M.pitcher("p1", name: "Jug"), M.pitcher("p2", name: "Juju")], players: [identity])
        XCTAssertEqual(rows.map(\.name), ["Juju"])
    }

    func testTheRosterRowBeatsItsPitcherRecord() {
        let row = M.row("r1", name: "Foxes", team: reds, player: "pl1", pitcher: "p1")
        let profile = PlayerLinks.profiles(rosterEntries: [row], pitchers: [M.pitcher("p1", name: "Hawks P2")], players: [])
        XCTAssertEqual(profile.map(\.name), ["Foxes"])
    }

    func testTheOldestRowNamesTheKid() {
        let blues = M.team("blues")
        let old = M.row("r1", name: "Kenzie", team: reds, pitcher: "p1", age: 1)
        let new = M.row("r2", name: "Kenz", team: blues, pitcher: "p1", age: 5)
        XCTAssertEqual(PlayerLinks.profiles(rosterEntries: [new, old], pitchers: [], players: []).map(\.name), ["Kenzie"])
    }

    func testAKidWithNoRosterRowGoesByThePitcherRecord() {
        let profile = PlayerLinks.profiles(rosterEntries: [], pitchers: [M.pitcher("p1", name: "Ella")], players: [])
        XCTAssertEqual(profile.map(\.name), ["Ella"])
    }

    func testARenameReachesEveryLinkedRecord() {
        let identity = M.player("pl1", pitcher: "p2", hitter: "h2", linkedPitchers: ["p1"], linkedHitters: ["h1"])
        let targets = PlayerLinks.renameTargets(pitcherId: "p2", hitterId: "h2", player: identity)
        XCTAssertEqual(targets.pitcherIds, ["p2", "p1"])
        XCTAssertEqual(targets.hitterIds, ["h2", "h1"])

        let noIdentity = PlayerLinks.renameTargets(pitcherId: "p9", hitterId: nil, player: nil)
        XCTAssertEqual(noIdentity.pitcherIds, ["p9"])
        XCTAssertTrue(noIdentity.hitterIds.isEmpty)
    }
}
