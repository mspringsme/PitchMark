//
//  FieldingTests.swift
//  PitchMarkTests
//
//  Fielding stats by position (approved 2026-11-03): putouts, assists,
//  errors, chances, fielding %, double plays and innings, credited to
//  whoever held the position on the pitch's own copy of the defense.
//

import XCTest
import FirebaseFirestore
@testable import PitchMark

private let defense: [DefenseSlot] = [
    DefenseSlot(position: "P", batterId: "c-p", hitterId: "h-pitcher", label: "#10"),
    DefenseSlot(position: "C", batterId: "c-c", hitterId: "h-catcher", label: "#2"),
    DefenseSlot(position: "1B", batterId: "c-1b", hitterId: "h-first", label: "#3"),
    DefenseSlot(position: "2B", batterId: "c-2b", hitterId: "h-second", label: "#4"),
    DefenseSlot(position: "SS", batterId: "c-ss", hitterId: "h-short", label: "#6"),
    DefenseSlot(position: "CF", batterId: "c-cf", hitterId: "h-center", label: "#8")
]

/// A batter out on a ball in play, bases empty.
private func groundOut(_ positions: [String], defense: [DefenseSlot]? = defense, gameId: String = "game-1",
                       timestamp: Date = Fixture.t0) -> PitchEvent {
    var event = Fixture.pitch(timestamp: timestamp, isStrike: true, outcome: "Out", balls: 0, strikes: 0)
    event.gameId = gameId
    event.fieldingOuts = [FieldingOut(runner: FieldingPlay.batterKey, positions: positions)]
    event.defense = defense
    event.fieldingTeamId = "team-us"
    return event
}

private func strikeout(defense: [DefenseSlot]? = defense) -> PitchEvent {
    var event = Fixture.pitch(isStrike: true, strikeSwinging: true, outcome: "K", balls: 0, strikes: 0)
    event.defense = defense
    return event
}

/// Runner on 1st, batter grounds into a double play: 6-4 at 2nd, 4-3 at 1st.
private func doublePlay() -> PitchEvent {
    let play = BaseRunnerRules.makePlay(
        credit: .out, reached: Base.out, extraBasesOn: nil,
        runnerMoves: [RunnerMove(runner: "r1", from: 1, to: Base.out, extraBasesOn: nil)]
    )
    var event = Fixture.pitch(isStrike: true, outcome: "Out", balls: 0, strikes: 0,
                              play: play, basesBefore: BaseOccupancy(first: Fixture.r1))
    event.fieldingOuts = [
        FieldingOut(runner: "1", positions: ["SS", "2B"]),
        FieldingOut(runner: FieldingPlay.batterKey, positions: ["2B", "1B"])
    ]
    event.defense = defense
    return event
}

/// Reached on error, charged to `errors`.
private func reachedOnError(_ errors: [String]) -> PitchEvent {
    let play = BaseRunnerRules.makePlay(credit: .reachedOnError, reached: Base.first, extraBasesOn: nil)
    var event = Fixture.pitch(isStrike: true, outcome: "1B", balls: 0, strikes: 0, play: play)
    event.errorOnPlay = true
    event.errorPositions = errors
    event.defense = defense
    return event
}

private func line(_ events: [PitchEvent], _ hitterId: String, at position: String? = nil) -> FieldingCounts {
    FieldingLedger(events: events).total(hitterIds: [hitterId], position: position)
}

final class FieldingCreditTests: XCTestCase {
    /// Rule 1
    func testOneFielderOutIsAPutoutOnly() {
        let counts = line([groundOut(["CF"])], "h-center")
        XCTAssertEqual(counts.putouts, 1)
        XCTAssertEqual(counts.assists, 0)
    }

    /// Rule 2
    func testLastFielderGetsThePutoutTheRestAssists() {
        let events = [groundOut(["SS", "1B"])]
        XCTAssertEqual(line(events, "h-first").putouts, 1)
        XCTAssertEqual(line(events, "h-first").assists, 0)
        XCTAssertEqual(line(events, "h-short").assists, 1)
        XCTAssertEqual(line(events, "h-short").putouts, 0)
    }

    /// Rule 3
    func testRundownGivesOneAssistEach() {
        let events = [groundOut(["SS", "2B", "SS", "2B", "SS"])]
        XCTAssertEqual(line(events, "h-short").assists, 1)
        XCTAssertEqual(line(events, "h-short").putouts, 1)
        XCTAssertEqual(line(events, "h-second").assists, 1)
    }

    /// Rule 4
    func testDoublePlayCreditsAndCountsForEveryone() {
        let events = [doublePlay()]
        XCTAssertEqual(line(events, "h-short"), FieldingCounts(putouts: 0, assists: 1, errors: 0, doublePlays: 1, outsPlayed: 2))
        XCTAssertEqual(line(events, "h-second").putouts, 1)
        XCTAssertEqual(line(events, "h-second").assists, 1)
        XCTAssertEqual(line(events, "h-second").doublePlays, 1)
        XCTAssertEqual(line(events, "h-first").putouts, 1)
        XCTAssertEqual(line(events, "h-first").doublePlays, 1)
        // Fielders who weren't in on it don't get the DP.
        XCTAssertEqual(line(events, "h-center").doublePlays, 0)
    }

    func testSingleOutIsNotADoublePlay() {
        XCTAssertEqual(line([groundOut(["SS", "1B"])], "h-short").doublePlays, 0)
    }

    /// Rule 5
    func testStrikeoutIsTheCatchersPutout() {
        XCTAssertEqual(line([strikeout()], "h-catcher").putouts, 1)
        XCTAssertEqual(line([strikeout()], "h-pitcher").putouts, 0)
    }

    func testStrikeoutWithNoCatcherCreditsNobody() {
        let noCatcher = defense.filter { $0.position != "C" }
        let ledger = FieldingLedger(events: [strikeout(defense: noCatcher)])
        for slot in noCatcher {
            XCTAssertEqual(ledger.total(hitterIds: [slot.hitterId!]).putouts, 0, slot.position)
        }
        // Still the team's putout at C (rule 8).
        XCTAssertEqual(ledger.teamTotal(position: "C").putouts, 1)
    }

    func testStrikeoutBatterIsNeverAskedAbout() {
        XCTAssertTrue(FieldingPlay.outSlots(for: strikeout()).isEmpty)
        XCTAssertEqual(FieldingPlay.outSlots(play: nil, batterOutOnPlay: true, isStrikeout: false).map(\.runner), ["batter"])
    }

    /// Rule 6
    func testErrorIsChargedToThePosition() {
        let events = [reachedOnError(["SS"])]
        XCTAssertEqual(line(events, "h-short").errors, 1)
        XCTAssertEqual(line(events, "h-first").errors, 0)
    }

    func testErrorsWithoutAnErrorOnThePlayAreDropped() {
        var event = groundOut(["SS", "1B"])
        event.errorPositions = ["SS"]
        XCTAssertEqual(line([event], "h-short").errors, 0)
    }

    /// Rule 7
    func testCreditFollowsThePitchsDefenseNotTodays() {
        // Inning 1: #6 at SS. Inning 2: #6 moved to CF, #8 to SS.
        let early = groundOut(["SS", "1B"])
        var moved = defense.filter { !["SS", "CF"].contains($0.position) }
        moved.append(DefenseSlot(position: "SS", batterId: "c-cf", hitterId: "h-center", label: "#8"))
        moved.append(DefenseSlot(position: "CF", batterId: "c-ss", hitterId: "h-short", label: "#6"))
        let late = groundOut(["SS", "1B"], defense: moved)

        let ledger = FieldingLedger(events: [early, late])
        XCTAssertEqual(ledger.total(hitterIds: ["h-short"], position: "SS").assists, 1)
        XCTAssertEqual(ledger.total(hitterIds: ["h-center"], position: "SS").assists, 1)
        XCTAssertEqual(ledger.total(hitterIds: ["h-short"], position: "CF").assists, 0)
    }

    func testDefenseCopyIsTheFieldingTeamsPositions() {
        let a = UUID(), b = UUID(), c = UUID()
        let slots = FieldingPlay.defense(
            cells: [(batterId: a, hitterId: "h-a", label: "#1"),
                    (batterId: b, hitterId: "h-b", label: "#2"),
                    (batterId: c, hitterId: nil, label: "#3")],
            positions: [a: "SS", b: "DH", c: "P"]
        )
        // DH doesn't field; scorebook order.
        XCTAssertEqual(slots.map(\.position), ["P", "SS"])
        XCTAssertEqual(slots.last?.hitterId, "h-a")
        XCTAssertNil(slots.first?.hitterId)
    }

    /// Rule 8
    func testUnheldPositionCountsForTheTeamOnly() {
        let events = [groundOut(["3B", "1B"])]  // nobody at 3B
        let ledger = FieldingLedger(events: events)
        XCTAssertEqual(ledger.teamTotal(position: "3B").assists, 1)
        XCTAssertEqual(ledger.teamTotal().assists, 1)
        XCTAssertEqual(ledger.teamTotal().putouts, 1)
        XCTAssertTrue(defense.allSatisfy { ledger.total(hitterIds: [$0.hitterId!], position: "3B").totalChances == 0 })
    }

    func testTeamEventsAreItsOwnFieldingPitches() {
        var theirs = groundOut(["SS", "1B"])
        theirs.fieldingTeamId = "team-them"
        let ours = groundOut(["SS", "1B"])
        let kept = FieldingLedger.events([ours, theirs], fieldingFor: ["team-us"])
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.fieldingTeamId, "team-us")
    }

    /// Rule 9
    func testChancesAndFieldingPercent() {
        let counts = FieldingCounts(putouts: 5, assists: 2, errors: 1)
        XCTAssertEqual(counts.totalChances, 8)
        XCTAssertEqual(counts.fieldingPercent, 88)          // 87.5 rounds up
        XCTAssertEqual(counts.fieldingPercentText, "88%")
        XCTAssertNil(FieldingCounts().fieldingPercent)
        XCTAssertEqual(FieldingCounts().fieldingPercentText, "—")
        XCTAssertEqual(FieldingCounts(putouts: 3).fieldingPercentText, "100%")
    }

    /// Rule 10
    func testInningsAreOutsWhileThereInThirds() {
        let events = (0..<14).map { groundOut(["CF"], timestamp: Fixture.t0.addingTimeInterval(Double($0))) }
        let counts = line(events, "h-short")
        XCTAssertEqual(counts.outsPlayed, 14)
        XCTAssertEqual(counts.inningsText, "4.2")
        XCTAssertEqual(line([doublePlay()], "h-pitcher").inningsText, "0.2")
        // A pitch with no out adds no time.
        let ball = { () -> PitchEvent in
            var e = Fixture.pitch(isBall: true, balls: 1, strikes: 0); e.defense = defense; return e
        }()
        XCTAssertEqual(line([ball], "h-short").outsPlayed, 0)
    }

    /// Rule 11
    func testPitchesWithoutADefenseCopyAddNothing() {
        let old = groundOut(["SS", "1B"], defense: nil)
        let ledger = FieldingLedger(events: [old, strikeout(defense: nil)])
        XCTAssertEqual(ledger.teamTotal(), FieldingCounts())
    }

    /// Rule 12
    func testStatsFiltersApplyToFielding() {
        let kept = groundOut(["SS", "1B"], gameId: "game-1")
        let archived = groundOut(["SS", "1B"], gameId: "game-archived")
        let old = groundOut(["SS", "1B"], gameId: "game-old", timestamp: Date(timeIntervalSince1970: 0))
        let filter = StatsEventFilter(
            excludedGameIds: ["game-archived"],
            dateRange: Date(timeIntervalSince1970: 500)...Date(timeIntervalSince1970: 5_000)
        )
        let ledger = FieldingLedger(events: filter.pitches([kept, archived, old]))
        XCTAssertEqual(ledger.total(hitterIds: ["h-short"]).assists, 1)
        let thisGame = StatsEventFilter(focusGameId: "game-old")
        XCTAssertEqual(FieldingLedger(events: thisGame.pitches([kept, archived, old])).total(hitterIds: ["h-short"]).assists, 1)
    }

    func testLinkedRecordsReadAsOnePlayer() {
        var other = defense
        other[4] = DefenseSlot(position: "SS", batterId: "c-ss", hitterId: "h-short-old", label: "#6")
        let ledger = FieldingLedger(events: [groundOut(["SS", "1B"]), groundOut(["SS", "1B"], defense: other)])
        XCTAssertEqual(ledger.total(hitterIds: ["h-short", "h-short-old"]).assists, 2)
    }
}

final class FieldingSavedPitchTests: XCTestCase {
    /// Rule 13
    func testEditKeepsFieldersAndDefenseItDoesNotChange() {
        let original = groundOut(["SS", "1B"])
        var edited = original
        edited.fieldingOuts = nil  // the sheet gave no answer
        edited.defense = nil
        let updated = PitchEventEdit.applying(edited, to: original)
        XCTAssertEqual(updated.fieldingOuts, original.fieldingOuts)
        XCTAssertEqual(updated.defense, defense)
    }

    func testEditCanChangeOrClearTheFielders() {
        let original = groundOut(["SS", "1B"])
        var edited = original
        edited.fieldingOuts = [FieldingOut(runner: FieldingPlay.batterKey, positions: ["2B", "1B"])]
        XCTAssertEqual(PitchEventEdit.applying(edited, to: original).fieldingOuts?.first?.positions, ["2B", "1B"])
        edited.fieldingOuts = []
        XCTAssertNil(PitchEventEdit.applying(edited, to: original).fieldingOuts)
    }

    func testEditToANonOutDropsTheOuts() {
        let original = groundOut(["SS", "1B"])
        var edited = original
        edited.outcome = "1B"
        XCTAssertNil(PitchEventEdit.applying(edited, to: original).fieldingOuts)
    }

    func testReviewStepKeepsFieldingAndDefense() {
        let base = groundOut(["SS", "1B"])
        let reviewed = buildSavedPlayReviewedEvent(
            from: base, balls: 0, strikes: 0, isStrike: true, isBall: false,
            strikeLooking: false, strikeSwinging: false, wildPitch: false, passedBall: false,
            countsAsWalk: false, countsAsHit: false
        )
        XCTAssertEqual(reviewed.fieldingOuts, base.fieldingOuts)
        XCTAssertEqual(reviewed.defense, defense)
        XCTAssertEqual(reviewed.fieldingTeamId, "team-us")
    }

    func testCardShowsTheScorebookNotation() {
        XCTAssertEqual(FieldingPlay.summary(outs: groundOut(["SS", "1B"]).fieldingOuts, errors: nil, descriptor: "Grounder"), "6-3")
        XCTAssertEqual(FieldingPlay.summary(outs: groundOut(["CF"]).fieldingOuts, errors: nil, descriptor: "Fly"), "F8")
        XCTAssertEqual(FieldingPlay.summary(outs: groundOut(["1B"]).fieldingOuts, errors: nil, descriptor: "Grounder"), "3U")
        XCTAssertEqual(FieldingPlay.summary(outs: doublePlay().fieldingOuts, errors: ["SS"], descriptor: nil), "6-4, 4-3, E6")
    }

    /// Rule 14
    func testFieldingSurvivesFirestore() throws {
        var event = doublePlay()
        event.errorPositions = ["2B"]
        event.fieldingTeamId = "team-us"
        let data = try Firestore.Encoder().encode(event)
        XCTAssertNotNil(data["fieldingOuts"] as? [[String: Any]], "array of maps, never nested arrays")

        let decoded = try Firestore.Decoder().decode(PitchEvent.self, from: data, in: Firestore.firestore().document("t/ev1"))
        XCTAssertEqual(decoded.fieldingOuts, event.fieldingOuts)
        XCTAssertEqual(decoded.errorPositions, ["2B"])
        XCTAssertEqual(decoded.defense, defense)
        XCTAssertEqual(decoded.fieldingTeamId, "team-us")

        let legacy = try XCTUnwrap(PitchEvent(legacyData: data, documentId: "ev1"))
        XCTAssertEqual(legacy.fieldingOuts, event.fieldingOuts)
        XCTAssertEqual(legacy.defense, defense)
    }

    func testOlderDocumentsWithoutFieldingStillLoad() throws {
        var data = try Firestore.Encoder().encode(Fixture.pitch(outcome: "Out"))
        for key in ["fieldingOuts", "errorPositions", "defense", "fieldingTeamId"] {
            data.removeValue(forKey: key)
        }
        let decoded = try Firestore.Decoder().decode(PitchEvent.self, from: data, in: Firestore.firestore().document("t/ev1"))
        XCTAssertNil(decoded.fieldingOuts)
        XCTAssertNil(decoded.defense)
    }
}
