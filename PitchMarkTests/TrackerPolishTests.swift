//
//  TrackerPolishTests.swift
//  PitchMarkTests
//
//  2026-11-02 requests: remembering the pitching side, pitcher and batter
//  per game; the At Bat header's short team name; sharing a Moment.
//

import XCTest
@testable import PitchMark

final class TrackerSelectionMemoryTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "TrackerSelectionMemoryTests")
        defaults.removePersistentDomain(forName: "TrackerSelectionMemoryTests")
    }

    func testANewGameStartsWithUsPitchingAndNobodyRemembered() {
        let memory = TrackerSelectionMemory.load(gameId: "g1", defaults: defaults)
        XCTAssertEqual(memory.side, .home)
        XCTAssertNil(memory.pitcherId(for: .home))
        XCTAssertNil(memory.batterId(for: .away))
    }

    func testTheSidePitcherAndBatterComeBack() {
        let batter = UUID()
        TrackerSelectionMemory.update(gameId: "g1", defaults: defaults) {
            $0.setPitchingSide(.away)
            $0.setPitcher("their-ace", for: .away)
            $0.setBatter(batter, for: .away)
        }
        let memory = TrackerSelectionMemory.load(gameId: "g1", defaults: defaults)
        XCTAssertEqual(memory.side, .away)
        XCTAssertEqual(memory.pitcherId(for: .away), "their-ace")
        XCTAssertEqual(memory.batterId(for: .away), batter)
    }

    func testEachSideKeepsItsOwnPitcherAndBatter() {
        let ours = UUID(), theirs = UUID()
        TrackerSelectionMemory.update(gameId: "g1", defaults: defaults) {
            $0.setPitcher("our-ace", for: .home)
            $0.setBatter(theirs, for: .home)   // we pitch, they bat
            $0.setPitcher("their-ace", for: .away)
            $0.setBatter(ours, for: .away)
        }
        let memory = TrackerSelectionMemory.load(gameId: "g1", defaults: defaults)
        XCTAssertEqual(memory.pitcherId(for: .home), "our-ace")
        XCTAssertEqual(memory.pitcherId(for: .away), "their-ace")
        XCTAssertEqual(memory.batterId(for: .home), theirs)
        XCTAssertEqual(memory.batterId(for: .away), ours)
    }

    func testGamesDontShareMemory() {
        TrackerSelectionMemory.update(gameId: "g1", defaults: defaults) { $0.setPitchingSide(.away) }
        XCTAssertEqual(TrackerSelectionMemory.load(gameId: "g2", defaults: defaults).side, .home)
    }

    func testClearingTheBatterIsRemembered() {
        TrackerSelectionMemory.update(gameId: "g1", defaults: defaults) { $0.setBatter(UUID(), for: .home) }
        TrackerSelectionMemory.update(gameId: "g1", defaults: defaults) { $0.setBatter(nil, for: .home) }
        XCTAssertNil(TrackerSelectionMemory.load(gameId: "g1", defaults: defaults).batterId(for: .home))
    }
}

final class AtBatHeaderTests: XCTestCase {
    func testTeamNamesFitSevenCharacters() {
        XCTAssertEqual(PitchTrackerView.abbreviatedTeamName("Reds", maxLength: 7), "Reds")
        XCTAssertEqual(PitchTrackerView.abbreviatedTeamName("Lady Thunder Gold", maxLength: 7), "LTG")
        XCTAssertEqual(PitchTrackerView.abbreviatedTeamName("Firecrackers", maxLength: 7), "Firecra")
        for name in ["Reds", "Lady Thunder Gold", "Firecrackers", "A B C D E F G H I"] {
            XCTAssertLessThanOrEqual(PitchTrackerView.abbreviatedTeamName(name, maxLength: 7).count, 7, name)
        }
    }
}

final class MomentShareTests: XCTestCase {
    func testFileNamesComeFromTheTitle() {
        XCTAssertEqual(MomentShare.fileStem(for: "Juju's Double"), "Juju's Double")
        XCTAssertEqual(MomentShare.fileStem(for: "6/14 vs Reds: walk-off"), "6 14 vs Reds walk-off")
        XCTAssertEqual(MomentShare.fileStem(for: "   "), "Moment")
    }

    func testOnlyFilesOnThisDeviceAreShared() {
        let photo1 = localMomentPhotoURL(momentId: "m1", index: 1)!
        let files = MomentShare.sourceFiles(momentId: "m1", photoCount: 3) { $0 == photo1 }
        XCTAssertEqual(files, [photo1])
        XCTAssertTrue(MomentShare.sourceFiles(momentId: "m1", photoCount: 3) { _ in false }.isEmpty)
    }
}

// 2026-11-02 bug: batters added from the roster showed "Not on roster"
// while the same kids sat on the bench.
final class LineupLinkPruneTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()

    func testABatterThatBlinksOutKeepsTheirRosterLink() {
        let links = [a: "h-maci", b: "h-ella", c: "h-juju"]
        // A stale live snapshot shows only the first batter...
        let blink = LineupLinkPrune.apply(links: links, parked: [:], cellIds: [a])
        XCTAssertEqual(blink.links, [a: "h-maci"])
        // ...then the next one brings the others back, links and all.
        let back = LineupLinkPrune.apply(links: blink.links, parked: blink.parked, cellIds: [a, b, c])
        XCTAssertEqual(back.links, links)
        XCTAssertTrue(back.parked.isEmpty)
    }

    func testARemovedBatterLosesTheirLink() {
        let result = LineupLinkPrune.apply(links: [a: "h1", b: "h2"], parked: [:], cellIds: [a])
        XCTAssertEqual(result.links, [a: "h1"])
    }

    func testANewLinkIsNotOverwrittenByAParkedOne() {
        let result = LineupLinkPrune.apply(links: [a: "new"], parked: [a: "old"], cellIds: [a])
        XCTAssertEqual(result.links, [a: "new"])
    }
}

// 2026-11-02: a team with no players yet gets a blank At Bat scroll.
final class SideScopeTests: XCTestCase {
    private let a = UUID(), b = UUID(), typed = UUID()
    private func row(_ hitter: String) -> TeamPlayer {
        TeamPlayer(id: hitter, name: hitter, hitterId: hitter, createdByUid: "c")
    }

    func testALoadedEmptyRosterHasNoBatters() {
        XCTAssertEqual(SideScope.battingHitterIds(teamId: "empty", roster: [], rosterLoaded: true), [])
        let cells = [JerseyCell(id: a, jerseyNumber: "1"), JerseyCell(id: b, jerseyNumber: "2")]
        let shown = SideScope.visibleCells(cells, links: [a: "h-maci", b: "h-ella"], battingHitterIds: [])
        XCTAssertTrue(shown.isEmpty, "the other team's batters don't show for an empty team")
    }

    func testARosterStillLoadingShowsEveryone() {
        XCTAssertNil(SideScope.battingHitterIds(teamId: "t", roster: [], rosterLoaded: false))
        XCTAssertNil(SideScope.battingHitterIds(teamId: nil, roster: [], rosterLoaded: true), "no team set")
    }

    func testEachTeamShowsItsOwnBattersAndTypedNumbers() {
        let ids = SideScope.battingHitterIds(teamId: "t", roster: [row("h-maci")], rosterLoaded: true)
        let cells = [JerseyCell(id: a, jerseyNumber: "1"), JerseyCell(id: b, jerseyNumber: "2"), JerseyCell(id: typed, jerseyNumber: "44")]
        let shown = SideScope.visibleCells(cells, links: [a: "h-maci", b: "h-ella"], battingHitterIds: ids)
        XCTAssertEqual(shown.map(\.id), [a, typed])
    }

    func testAPitcherBelongsToOneSide() {
        let away: Set<String> = ["their-ace"]
        XCTAssertTrue(SideScope.pitcher("their-ace", belongsTo: .away, awayPitcherIds: away))
        XCTAssertFalse(SideScope.pitcher("their-ace", belongsTo: .home, awayPitcherIds: away))
        XCTAssertTrue(SideScope.pitcher("our-ace", belongsTo: .home, awayPitcherIds: away))
        XCTAssertFalse(SideScope.pitcher("our-ace", belongsTo: .away, awayPitcherIds: []), "an empty team has no pitcher")
    }
}
