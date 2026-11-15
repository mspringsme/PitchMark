//
//  HomePlayersTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-14: Home's Players list - which editor Edit opens, the
//  "Another coach's team" lock, the pitcher listeners dropping a deleted
//  record (Merge Duplicates), and team short names.
//

import XCTest
@testable import PitchMark

private enum H {
    static let me = "coach-1"
    static let other = "coach-2"
    static func day(_ n: Double) -> Date { Date(timeIntervalSince1970: 1_000_000 + n * 86_400) }

    static func team(_ id: String, by uid: String = me, age: Double = 0) -> Team {
        Team(id: id, name: id, createdByUid: uid, createdAt: day(age))
    }

    static func entry(_ id: String, team: Team, player: String? = nil, pitcher: String? = nil,
                      hitter: String? = nil, positions: [FieldPosition]? = nil) -> PlayerRosterEntry {
        let tp = TeamPlayer(
            id: id, name: "Kenzie", jerseyNumber: nil, pitcherId: pitcher, playerId: player,
            hitterId: hitter, positions: positions, createdByUid: team.createdByUid, createdAt: day(5)
        )
        return PlayerRosterEntry(teamPlayer: tp, team: team)
    }

    static func pitcher(_ id: String, name: String = "Kenzie", owner: String = me) -> Pitcher {
        Pitcher(id: id, name: name, templateId: nil, ownerUid: owner, sharedWith: [], claimedByUid: nil, createdAt: day(1))
    }

    static func player(_ id: String, pitcher: String, linked: [String] = []) -> Player {
        Player(id: id, name: "Kenzie", ownerUid: me, pitcherId: pitcher, hitterId: nil,
               createdAt: day(1), linkedPitcherIds: linked)
    }

    /// The one Players row these records make, as Home builds it.
    static func row(_ entries: [PlayerRosterEntry], pitchers: [Pitcher] = [], players: [Player] = []) -> PlayerDirectoryRow {
        let rows = PlayerDirectory.rows(rosterEntries: entries, pitchers: pitchers, players: players)
        XCTAssertEqual(rows.count, 1, "one person")
        return rows[0]
    }
}

final class HomePlayersTests: XCTestCase {

    // MARK: Which editor Edit opens

    func testAPlayerOnOneOfMyTeamsOpensPlayerDetailsForThatRow() {
        let reds = H.team("Reds")
        let e = H.entry("r1", team: reds, player: "pl1", pitcher: "p1")
        let row = H.row([e], pitchers: [H.pitcher("p1")])
        XCTAssertEqual(HomePlayerEditRoute.route(for: row, entries: [e], uid: H.me), .playerDetails([e.id]))
    }

    func testAPlayerOnTwoOfMyTeamsListsBothNewestTeamFirst() {
        let old = H.team("Reds 2025", age: 0)
        let new = H.team("Reds 2026", age: 300)
        let a = H.entry("r1", team: old, player: "pl1", pitcher: "p1")
        let b = H.entry("r2", team: new, player: "pl1", pitcher: "p1")
        let row = H.row([a, b], pitchers: [H.pitcher("p1")])
        XCTAssertEqual(HomePlayerEditRoute.route(for: row, entries: [a, b], uid: H.me), .playerDetails([b.id, a.id]))
    }

    func testAPlayerOnNoTeamGetsNamePlusAddToTeam() {
        let row = H.row([], pitchers: [H.pitcher("p1")])
        XCTAssertTrue(row.teams.isEmpty)
        XCTAssertEqual(HomePlayerEditRoute.route(for: row, entries: [], uid: H.me), .addToTeam)
        XCTAssertFalse(row.isOnlyOnOtherCoachesTeams(uid: H.me), "no team is not another coach's")
    }

    func testAPlayerOnlyOnAnotherCoachsTeamIsLocked() {
        let theirs = H.team("Hawks", by: H.other)
        let e = H.entry("r1", team: theirs, player: "pl1", pitcher: "p1")
        let row = H.row([e], pitchers: [H.pitcher("p1", owner: H.other)])
        XCTAssertTrue(row.isOnlyOnOtherCoachesTeams(uid: H.me), "badge shows")
        XCTAssertEqual(HomePlayerEditRoute.route(for: row, entries: [e], uid: H.me), .locked)
        XCTAssertTrue(PlayerDirectory.editableEntries(for: row, in: [e], uid: H.me).isEmpty)
    }

    func testOnMyTeamAndAnotherCoachsOnlyMyRowIsEditableAndItIsNotLocked() {
        let mine = H.team("Reds")
        let theirs = H.team("Hawks", by: H.other)
        let a = H.entry("r1", team: mine, player: "pl1", pitcher: "p1")
        let b = H.entry("r2", team: theirs, player: "pl1", pitcher: "p1")
        let row = H.row([a, b], pitchers: [H.pitcher("p1")])
        XCTAssertFalse(row.isOnlyOnOtherCoachesTeams(uid: H.me))
        XCTAssertEqual(HomePlayerEditRoute.route(for: row, entries: [a, b], uid: H.me), .playerDetails([a.id]))
    }

    func testARowLeftOnAMergedPlayersSecondPitcherRecordStillMatches() {
        // Merge kept p2 (it had pitches): its row points at p2, and the kept
        // Player links it. Both rows are this person's.
        let reds = H.team("Reds", age: 0)
        let blues = H.team("Blues", age: 10)
        let a = H.entry("r1", team: reds, player: "pl1", pitcher: "p1")
        let b = H.entry("r2", team: blues, pitcher: "p2")
        let row = H.row([a, b], pitchers: [H.pitcher("p1"), H.pitcher("p2")],
                        players: [H.player("pl1", pitcher: "p1", linked: ["p2"])])
        let ids = Set(PlayerDirectory.editableEntries(for: row, in: [a, b], uid: H.me).map(\.id))
        XCTAssertEqual(ids, [a.id, b.id])
    }

    func testNoSignedInCoachCanEditNothing() {
        let e = H.entry("r1", team: H.team("Reds"), player: "pl1", pitcher: "p1")
        let row = H.row([e], pitchers: [H.pitcher("p1")])
        XCTAssertTrue(PlayerDirectory.editableEntries(for: row, in: [e], uid: nil).isEmpty)
    }

    // MARK: Pitcher listeners (Merge Duplicates' leftover row)

    func testAPitcherDeletedFromMyRecordsLeavesTheList() {
        var sources = LivePitcherSources()
        sources.apply([H.pitcher("p1"), H.pitcher("p2")], from: .owned)
        XCTAssertEqual(Set(sources.all.compactMap(\.id)), ["p1", "p2"])
        // The merge's cleanup deleted p2; the next snapshot no longer has it.
        sources.apply([H.pitcher("p1")], from: .owned)
        XCTAssertEqual(sources.all.compactMap(\.id), ["p1"])

        // And the merged person is one row again.
        let rows = PlayerDirectory.rows(rosterEntries: [], pitchers: sources.all, players: [])
        XCTAssertEqual(rows.count, 1)
    }

    func testOneListenersSnapshotNeverDropsTheOthersPitchers() {
        var sources = LivePitcherSources()
        sources.apply([H.pitcher("mine")], from: .owned)
        sources.apply([H.pitcher("shared", owner: H.other)], from: .shared)
        sources.apply([], from: .shared)   // sharing revoked
        XCTAssertEqual(sources.all.compactMap(\.id), ["mine"])
    }

    func testMyOwnCopyWinsWhenAPitcherIsInBothLists() {
        var sources = LivePitcherSources()
        sources.apply([H.pitcher("p1", name: "Shared Name", owner: H.other)], from: .shared)
        sources.apply([H.pitcher("p1", name: "My Name")], from: .owned)
        XCTAssertEqual(sources.all.map(\.name), ["My Name"])
    }

    // MARK: Team short names

    func testANameThatLeadsWithItsShortFormKeepsIt() {
        XCTAssertEqual(PitchTrackerView.abbreviatedTeamName("MHJ Fastpitch", maxLength: 7), "MHJ")
        XCTAssertEqual(PitchTrackerView.abbreviatedTeamName("MHJ Fastpitch", maxLength: 10), "MHJ")
        XCTAssertEqual(PitchTrackerView.abbreviatedTeamName("Lady Thunder Gold", maxLength: 7), "LTG", "ordinary words still use initials")
        XCTAssertEqual(PitchTrackerView.abbreviatedTeamName("A Team Of Many Words", maxLength: 7), "ATOMW", "a one-letter word isn't a short form")
    }
}
