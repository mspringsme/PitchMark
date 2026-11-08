//
//  LineupScanTests.swift
//  PitchMarkTests
//
//  Scan Opponent Lineup (rules approved 2026-11-06). Reading R1-R7,
//  matching M1-M5, adding A1-A5. Expected values come from the approved
//  list, not from running the code.
//

import XCTest
@testable import PitchMark

final class LineupScanTests: XCTestCase {

    // MARK: Helpers

    /// One screen row: each piece left to right at the same height.
    private func line(_ y: Double, _ pieces: String..., confidence: Double = 0.95) -> [LineupScanText] {
        pieces.enumerated().map { LineupScanText($0.element, x: 0.1 + Double($0.offset) * 0.2, y: y, confidence: confidence) }
    }

    private func image(_ lines: [LineupScanText]...) -> [LineupScanText] { lines.flatMap { $0 } }

    private func rows(_ texts: [LineupScanText]) -> [LineupScanRow] { LineupScanParser.parse(texts) }

    // MARK: Reading

    /// R1: rows by height, top to bottom; words left to right - even
    /// when the reader hands them over shuffled.
    func testRowsTopToBottomWordsLeftToRight() {
        let texts = [
            LineupScanText("Smith", x: 0.5, y: 0.31),
            LineupScanText("#7", x: 0.1, y: 0.40),
            LineupScanText("Jake", x: 0.3, y: 0.30),
            LineupScanText("#12", x: 0.1, y: 0.30),
            LineupScanText("Lee", x: 0.3, y: 0.40),
        ]
        let parsed = rows(texts)
        XCTAssertEqual(parsed.map(\.jersey), ["12", "7"])
        XCTAssertEqual(parsed.map(\.name), ["Jake Smith", "Lee"])
    }

    /// R2: "#" is the jersey; two plain numbers are order then jersey;
    /// one plain number is the order only when rows count 1, 2, 3.
    func testJerseyVersusBattingOrder() {
        let hashAndOrder = rows(image(line(0.1, "1", "#12", "Jake Smith"), line(0.2, "2", "#4", "Ann Lee")))
        XCTAssertEqual(hashAndOrder.map(\.order), [1, 2])
        XCTAssertEqual(hashAndOrder.map(\.jersey), ["12", "4"])

        let twoPlain = rows(image(line(0.1, "1", "12", "Jake Smith"), line(0.2, "2", "4", "Ann Lee")))
        XCTAssertEqual(twoPlain.map(\.order), [1, 2])
        XCTAssertEqual(twoPlain.map(\.jersey), ["12", "4"])

        let counting = rows(image(line(0.1, "1", "Jake Smith"), line(0.2, "2", "Ann Lee"), line(0.3, "3", "Bo Diaz")))
        XCTAssertEqual(counting.map(\.order), [1, 2, 3])
        XCTAssertEqual(counting.map(\.jersey), [nil, nil, nil])

        let notCounting = rows(image(line(0.1, "12", "Jake Smith"), line(0.2, "4", "Ann Lee"), line(0.3, "23", "Bo Diaz")))
        XCTAssertEqual(notCounting.map(\.order), [nil, nil, nil])
        XCTAssertEqual(notCounting.map(\.jersey), ["12", "4", "23"])

        let twoConsecutiveJerseys = rows(image(line(0.1, "7", "Jake Smith"), line(0.2, "8", "Ann Lee")))
        XCTAssertEqual(twoConsecutiveJerseys.map(\.jersey), ["7", "8"], "two consecutive jerseys aren't a batting order")

        let secondScreenshot = rows(image(line(0.1, "10", "Jake Smith"), line(0.2, "11", "Ann Lee"), line(0.3, "12", "Bo Diaz")))
        XCTAssertEqual(secondScreenshot.map(\.order), [10, 11, 12], "a second screenshot counts on from 10")
    }

    /// R3: positions and batting side are thrown away, never part of a name.
    func testPositionsAndSidesAreDropped() {
        let parsed = rows(image(
            line(0.1, "1", "#12", "Jake Smith", "SS", "R/R"),
            line(0.2, "2", "#4", "Ann Lee", "CF", "(L)"),
            line(0.3, "3", "#9", "Cy Young", "P", "DH")
        ))
        XCTAssertEqual(parsed.map(\.name), ["Jake Smith", "Ann Lee", "Cy Young"])
    }

    /// R3: a lowercase single letter or an initial with a dot is kept.
    func testInitialsAreNotPositions() {
        let parsed = rows(image(line(0.1, "#12", "C.", "Smith"), line(0.2, "#4", "Smith,", "R.")))
        XCTAssertEqual(parsed.map(\.name), ["C. Smith", "Smith, R."])
    }

    /// R4: header words are ignored; a header-only row isn't a batter.
    func testHeaderWordsIgnored() {
        let parsed = rows(image(
            line(0.05, "Batting Order"),
            line(0.08, "#", "Name", "Pos"),
            line(0.1, "1", "#12", "Jake Smith", "SS")
        ))
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.name, "Jake Smith")
    }

    /// R5: no jersey and no name is dropped; a jersey alone saves "#12".
    func testNumberOnlyAndEmptyRows() {
        let parsed = rows(image(line(0.1, "#12"), line(0.2, "SS", "R/R"), line(0.3, "#4", "Ann Lee")))
        XCTAssertEqual(parsed.count, 2)
        XCTAssertNil(parsed[0].name)
        XCTAssertEqual(parsed[0].savedName, "#12")
        XCTAssertEqual(parsed[1].savedName, "Ann Lee")
    }

    /// R6: "Check this" when the reader was unsure or a jersey repeats.
    func testCheckThis() {
        let parsed = rows(image(
            line(0.1, "#12", "Jake Smith"),
            line(0.2, "#4", "Ann Lee", confidence: 0.3),
            line(0.3, "#12", "Bo Diaz"),
            line(0.4, "#9", "Cy Young")
        ))
        XCTAssertEqual(parsed.map(\.needsCheck), [true, true, true, false])
    }

    /// R7: screenshots merge in pick order, overlaps drop, a clash on
    /// the same batting order keeps both, flagged.
    func testMergeScreenshots() {
        let first = rows(image(
            line(0.1, "1", "#12", "Jake Smith"), line(0.2, "2", "#4", "Ann Lee"), line(0.3, "3", "#9", "Cy Young")
        ))
        let second = rows(image(
            line(0.1, "3", "#9", "Cy Young"), line(0.2, "4", "#5", "Bo Diaz"), line(0.3, "5", "#6", "Al Ruiz")
        ))
        let merged = LineupScanParser.merge([first, second])
        XCTAssertEqual(merged.map(\.order), [1, 2, 3, 4, 5], "the repeated #3 is dropped")
        XCTAssertEqual(merged.map(\.jersey), ["12", "4", "9", "5", "6"])
        XCTAssertFalse(merged.contains(where: \.needsCheck))

        let clash = rows(image(line(0.1, "2", "#22", "Dee Park"), line(0.2, "3", "#9", "Cy Young")))
        let clashed = LineupScanParser.merge([first, clash])
        XCTAssertEqual(clashed.map(\.order), [1, 2, 2, 3])
        XCTAssertEqual(clashed.map(\.jersey), ["12", "4", "22", "9"])
        XCTAssertEqual(clashed.map(\.needsCheck), [false, true, true, false])

        let unnumberedA = rows(image(line(0.1, "#12", "Jake Smith"), line(0.2, "#4", "Ann Lee")))
        let unnumberedB = rows(image(line(0.1, "#4", "Ann Lee"), line(0.2, "#5", "Bo Diaz")))
        XCTAssertEqual(LineupScanParser.merge([unnumberedA, unnumberedB]).map(\.jersey), ["12", "4", "5"],
                       "without batting order, pick order stands and the overlap drops")
    }

    // MARK: Real screenshots (rules approved 2026-11-06, second list)

    /// R3: "(C)", "(1B)" always go; a single letter before the name is an
    /// initial ("L Laxton", "C Suda"), after it a position.
    func testParenthesizedPositionsAndInitials() {
        let parsed = rows(image(
            line(0.1, "L Laxton #23 (SS)"), line(0.2, "C Suda #11 (3B)"), line(0.3, "Jake Smith C", "#5")
        ))
        XCTAssertEqual(parsed.map(\.name), ["L Laxton", "C Suda", "Jake Smith"])
        XCTAssertEqual(parsed.map(\.jersey), ["23", "11", "5"])
    }

    /// R8: "#" comes off text it's stuck to.
    func testHashSplitsOff() {
        let parsed = rows(image(line(0.1, "T Hanew...#12 (C)"), line(0.2, "A Adriea...#1 (2B)")))
        XCTAssertEqual(parsed.map(\.jersey), ["12", "1"])
        XCTAssertEqual(parsed.map(\.jerseyMarked), [true, true])
    }

    /// R9: numbers right of the name are stat columns (a 0 read as "O"
    /// too); one number after the name is the jersey only without "#".
    func testStatColumnsIgnored() {
        let boxScore = rows(image(
            line(0.1, "A McCalla #3 (1B)", "2", "1", "2", "O", "0", "O"),
            line(0.2, "E Claahsen #13 (P)", "2", "O", "1", "0", "0", "O")
        ))
        XCTAssertEqual(boxScore.map(\.jersey), ["3", "13"])
        XCTAssertEqual(boxScore.map(\.order), [nil, nil])
        XCTAssertEqual(boxScore.map(\.name), ["A McCalla", "E Claahsen"])

        let trailingJersey = rows(image(line(0.1, "Jake Smith", "12"), line(0.2, "Ann Lee", "4")))
        XCTAssertEqual(trailingJersey.map(\.jersey), ["12", "4"])

        let twoTrailing = rows(image(line(0.1, "Jake Smith", "2", "1")))
        XCTAssertEqual(twoTrailing.first?.jersey, nil, "two numbers after the name are stats")
    }

    /// R10: "TB: ..." / "SB: ..." lines and the TEAM row are dropped.
    func testSummaryLinesDropped() {
        let parsed = rows(image(
            line(0.1, "A McCalla #3 (1B)"),
            line(0.2, "TEAM", "22 4", "6", "0", "2", "5"),
            line(0.3, "TB: A McCalla 2, A Barratt 1, E Claahsen 1"),
            line(0.4, "SB: E Stephens")
        ))
        XCTAssertEqual(parsed.map(\.name), ["A McCalla"])
    }

    /// R11: a name cut short loses its "..." and is flagged.
    func testTruncatedNames() {
        let parsed = rows(image(
            line(0.1, "T Hanew...#12 (C)"), line(0.2, "E Steph...s #7 (CF)"), line(0.3, "A McCalla #3 (1B)")
        ))
        XCTAssertEqual(parsed.map(\.name), ["T Hanew", "E Steph...s", "A McCalla"])
        XCTAssertEqual(parsed.map(\.needsCheck), [true, true, false])
    }

    /// R12: what starts kept. "#" style: only "#" jerseys with a name;
    /// number-only lineups keep numbers alone; no jerseys at all keeps
    /// numbered names.
    func testLikelyBatters() {
        let hashStyle = rows(image(
            line(0.05, "Sat, Oct 24"),
            line(0.1, "REDS 16U-ALVAREZ"),
            line(0.2, "T Hanew...#12 (C)"), line(0.3, "E Steph...s #7 (CF)"), line(0.4, "A McCalla #3 (1B)"),
            line(0.5, "#9")
        ))
        XCTAssertEqual(hashStyle.map(\.likelyBatter), [false, false, true, true, true, false])

        let numbersOnly = rows(image(line(0.1, "#12"), line(0.2, "#4"), line(0.3, "#9 Cy Young"), line(0.4, "Replay GameStream")))
        XCTAssertEqual(numbersOnly.map(\.likelyBatter), [true, true, true, false])

        let namesOnly = rows(image(line(0.1, "1", "Jake Smith"), line(0.2, "2", "Ann Lee"), line(0.3, "Box Score")))
        XCTAssertEqual(namesOnly.map(\.likelyBatter), [true, true, false])
    }

    /// R6: a repeated jersey is flagged only among kept rows.
    func testRepeatedJerseyOnlyAmongKept() {
        let parsed = rows(image(
            line(0.05, "Sat, Oct", "4"),
            line(0.2, "G Trela #4 (RF)"), line(0.3, "A McCalla #3 (1B)")
        ))
        XCTAssertEqual(parsed.map(\.likelyBatter), [false, true, true])
        XCTAssertEqual(parsed.map(\.needsCheck), [false, false, false])
    }

    /// R12: the review list - kept rows are the lineup, ticking a row puts
    /// it back where it was read, unticking sends it to the others.
    func testReviewKeepList() {
        func row(_ name: String, keep: Bool) -> LineupScanRow {
            LineupScanRow(order: nil, jersey: "1", name: name, likelyBatter: keep)
        }
        let scanned = [row("Junk", keep: false), row("A", keep: true), row("Other", keep: false), row("B", keep: true), row("C", keep: true)]
        var list = LineupReviewList(rows: scanned)
        XCTAssertEqual(list.kept.map(\.name), ["A", "B", "C"])
        XCTAssertEqual(list.others.map(\.name), ["Junk", "Other"])

        list.setKeep(scanned[2].id, true)
        XCTAssertEqual(list.kept.map(\.name), ["A", "Other", "B", "C"], "joins where it was read")

        list.setKeep(scanned[1].id, false)
        XCTAssertEqual(list.kept.map(\.name), ["Other", "B", "C"])
        XCTAssertEqual(list.others.map(\.name), ["Junk", "A"], "others stay in read order")

        list.moveKept(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(list.kept.map(\.name), ["C", "Other", "B"])
        list.deleteKept(atOffsets: IndexSet(integer: 1))
        XCTAssertEqual(list.kept.map(\.name), ["C", "B"])
        list.addBlank()
        XCTAssertEqual(list.kept.map(\.name), ["C", "B", ""])
        XCTAssertEqual(list.others.map(\.name), ["Junk", "A"])
    }

    // MARK: Matching

    private let roster = [
        LineupRosterEntry(rowId: "r12", name: "Jake Smith", jersey: "12"),
        LineupRosterEntry(rowId: "r4", name: "Ann Lee", jersey: "4"),
        LineupRosterEntry(rowId: "r9", name: "Cy Young", jersey: "9"),
        LineupRosterEntry(rowId: "r5", name: "Bo Diaz", jersey: "5"),
        LineupRosterEntry(rowId: "r30", name: "Sam Ortiz", jersey: "30"),
        LineupRosterEntry(rowId: "r31", name: "Max Ortiz", jersey: "31"),
        LineupRosterEntry(rowId: "rOld", name: "Old Kid", jersey: "44", archived: true),
    ]

    private func scanned(_ jersey: String?, _ name: String?, check: Bool = false) -> LineupScanRow {
        LineupScanRow(order: nil, jersey: jersey, name: name, needsCheck: check)
    }

    /// M1: same jersey and the names agree (or one has no name).
    func testJerseyAndNameMatch() {
        let results = LineupRosterMatch.match([
            scanned("12", "Jake Smith"), scanned("4", "A. Lee"), scanned("9", nil), scanned("5", "Diaz, B.")
        ], roster: roster)
        XCTAssertEqual(results.map(\.rowId), ["r12", "r4", "r9", "r5"])
        XCTAssertFalse(results.contains(where: \.needsCheck))
    }

    /// M2: same jersey, different name: not matched, flagged, offered.
    func testJerseyMatchNameDiffers() {
        let result = LineupRosterMatch.match([scanned("12", "Tom Brown")], roster: roster)[0]
        XCTAssertNil(result.rowId)
        XCTAssertEqual(result.suggestedRowId, "r12")
        XCTAssertTrue(result.needsCheck)
    }

    /// M3: no jersey match, exactly one name match: matched; flagged
    /// when the jersey differs.
    func testNameOnlyMatch() {
        let results = LineupRosterMatch.match([scanned(nil, "Cy Young"), scanned("99", "Ann Lee")], roster: roster)
        XCTAssertEqual(results[0].rowId, "r9")
        XCTAssertFalse(results[0].needsCheck)
        XCTAssertEqual(results[1].rowId, "r4")
        XCTAssertTrue(results[1].needsCheck, "roster says #4")
    }

    /// M4: two possible players: never guesses.
    func testTwoCandidatesNoGuess() {
        let result = LineupRosterMatch.match([scanned(nil, "Ortiz")], roster: roster)[0]
        XCTAssertNil(result.rowId)
        XCTAssertTrue(result.needsCheck)
    }

    /// M4 (no candidates at all): a new player, nothing to check.
    func testNewPlayer() {
        let result = LineupRosterMatch.match([scanned("77", "New Kid")], roster: roster)[0]
        XCTAssertNil(result.rowId)
        XCTAssertNil(result.suggestedRowId)
        XCTAssertFalse(result.needsCheck)
    }

    /// M5: each roster player is matched at most once, a jersey match
    /// beating an earlier name-only one; removed players never match.
    func testEachPlayerOnceAndNoArchived() {
        let results = LineupRosterMatch.match([
            scanned(nil, "Jake Smith"),   // name only - but #12 below takes him by jersey
            scanned("12", "Jake Smith"),
            scanned("44", "Old Kid"),
        ], roster: roster)
        XCTAssertNil(results[0].rowId)
        XCTAssertEqual(results[1].rowId, "r12")
        XCTAssertNil(results[2].rowId, "an archived roster row is never matched")
    }

    /// An unsure read stays "Check this" even when it matched.
    func testUnsureReadStaysFlagged() {
        let result = LineupRosterMatch.match([scanned("12", "Jake Smith", check: true)], roster: roster)[0]
        XCTAssertEqual(result.rowId, "r12")
        XCTAssertTrue(result.needsCheck)
    }

    // MARK: Adding

    /// A1-A2: matched reuse, new get a row; the lineup only adds,
    /// skipping anyone already in the game or listed twice.
    func testPlan() {
        let plan = LineupScanPlan.make([
            LineupScanDecision(name: "Jake Smith", jersey: "12", existingRowId: "r12", existingHitterId: "h12"),
            LineupScanDecision(name: "New Kid", jersey: "77"),
            LineupScanDecision(name: "Ann Lee", jersey: "4", existingRowId: "r4", existingHitterId: "h4"),
            LineupScanDecision(name: "Jake Smith", jersey: "12", existingRowId: "r12", existingHitterId: "h12"),
            LineupScanDecision(name: "Al Ruiz", jersey: nil),
        ], alreadyInLineup: ["h4"])
        XCTAssertEqual(plan.newPlayers.map(\.name), ["New Kid", "Al Ruiz"])
        XCTAssertEqual(plan.lineup, [
            .existing(hitterId: "h12", display: "12"),
            .new(index: 0, display: "77"),
            .new(index: 1, display: "AL"),
        ])
    }

    /// A3-A4: which way the writes go. A room that's open takes the
    /// lineup even when the game isn't on screen, and the owner also
    /// writes the saved game.
    func testRoute() {
        XCTAssertEqual(LineupScanRoute.decide(isOwner: true, openInTracker: false, liveRoomOpen: false), .savedGame(closeFirst: false))
        XCTAssertEqual(LineupScanRoute.decide(isOwner: true, openInTracker: true, liveRoomOpen: false), .savedGame(closeFirst: true))
        XCTAssertEqual(LineupScanRoute.decide(isOwner: true, openInTracker: true, liveRoomOpen: true), .liveRoom(alsoSavedGame: true))
        XCTAssertEqual(LineupScanRoute.decide(isOwner: true, openInTracker: false, liveRoomOpen: true), .liveRoom(alsoSavedGame: true))
        XCTAssertEqual(LineupScanRoute.decide(isOwner: false, openInTracker: true, liveRoomOpen: true), .liveRoom(alsoSavedGame: false))
        XCTAssertEqual(LineupScanRoute.decide(isOwner: false, openInTracker: false, liveRoomOpen: true), .liveRoom(alsoSavedGame: false))
    }

    /// A5: links from the room reach the owner; only the owner saves them.
    func testLiveLineupLinks() {
        XCTAssertEqual(LiveLineupLinks.ownerMerge(local: ["a": "h1"], room: ["b": "h2"]), ["a": "h1", "b": "h2"])
        XCTAssertEqual(LiveLineupLinks.ownerMerge(local: ["a": "h1"], room: ["a": "h9"]), ["a": "h9"], "the room's link wins for its spot")
        XCTAssertNil(LiveLineupLinks.ownerMerge(local: ["a": "h1"], room: ["a": "h1"]), "nothing new, nothing written")
        XCTAssertNil(LiveLineupLinks.ownerMerge(local: ["a": "h1"], room: nil))
        XCTAssertTrue(LiveLineupLinks.writesSavedGame(isOwner: true))
        XCTAssertFalse(LiveLineupLinks.writesSavedGame(isOwner: false))
    }

    // MARK: Partner controls through the room (A6-A8, approved 2026-11-06)

    /// A6: the room's positions reach the game when they differ; a room
    /// that never carried positions never clears the game's.
    func testPositionsFromRoom() {
        XCTAssertEqual(LiveLineupLinks.positionsFromRoom(game: ["a": "SS"], room: ["a": "CF"]), ["a": "CF"])
        XCTAssertEqual(LiveLineupLinks.positionsFromRoom(game: nil, room: ["a": "CF"]), ["a": "CF"])
        XCTAssertEqual(LiveLineupLinks.positionsFromRoom(game: ["a": "SS"], room: [:]), [:], "an emptied room map clears them")
        XCTAssertNil(LiveLineupLinks.positionsFromRoom(game: ["a": "SS"], room: ["a": "SS"]), "nothing new, nothing written")
        XCTAssertNil(LiveLineupLinks.positionsFromRoom(game: ["a": "SS"], room: nil), "no room map never clears the game's")
    }

    /// A7: the coach's phone fills in what the room is missing, only then.
    func testCoachPublishesWhatTheRoomIsMissing() {
        XCTAssertEqual(LiveLineupLinks.needsPublishing(game: ["a": "SS"], room: nil), ["a": "SS"])
        XCTAssertNil(LiveLineupLinks.needsPublishing(game: ["a": "SS"], room: ["a": "CF"]), "the room's own map stands")
        XCTAssertNil(LiveLineupLinks.needsPublishing(game: ["a": "SS"], room: [:]))
        XCTAssertNil(LiveLineupLinks.needsPublishing(game: [:], room: nil))
        XCTAssertNil(LiveLineupLinks.needsPublishing(game: nil, room: nil))
    }

    /// A8: an empty room gets the game's lineup and its own spots' links;
    /// a room with a lineup is never overwritten.
    func testSeedForEmptyRoom() {
        let seed = LiveLineupLinks.seedForEmptyRoom(
            roomJerseys: [], gameJerseys: ["12", "4"], gameIds: ["a", "b"], gameLinks: ["a": "h12", "b": "h4", "gone": "hX"]
        )
        XCTAssertEqual(seed?["jerseyNumbers"] as? [String], ["12", "4"])
        XCTAssertEqual(seed?["batterIds"] as? [String], ["a", "b"])
        XCTAssertEqual(seed?["hitterIdByBatterId.a"] as? String, "h12")
        XCTAssertEqual(seed?["hitterIdByBatterId.b"] as? String, "h4")
        XCTAssertNil(seed?["hitterIdByBatterId.gone"], "a stale link for a removed spot isn't copied")
        XCTAssertNil(LiveLineupLinks.seedForEmptyRoom(roomJerseys: ["7"], gameJerseys: ["12"], gameIds: ["a"], gameLinks: nil),
                     "a room with a lineup keeps it")
        XCTAssertNil(LiveLineupLinks.seedForEmptyRoom(roomJerseys: [], gameJerseys: [], gameIds: [], gameLinks: nil))
        XCTAssertNil(LiveLineupLinks.seedForEmptyRoom(roomJerseys: [], gameJerseys: ["12", "4"], gameIds: ["a"], gameLinks: nil),
                     "ids out of step with jerseys aren't copied")
    }
}
