//
//  FieldersChoiceTests.swift
//  PitchMarkTests
//
//  Fielder's choice outs and the fielding key (rules 16-21 and 23,
//  approved 2026-11-04). Picking FC on the bases diamond puts the lead
//  forced runner out, so the Fielded by row asks who got them ("6-4").
//

import XCTest
@testable import PitchMark

private let defense: [DefenseSlot] = [
    DefenseSlot(position: "2B", batterId: "c-2b", hitterId: "h-second", label: "#4"),
    DefenseSlot(position: "SS", batterId: "c-ss", hitterId: "h-short", label: "#6")
]

/// Batter safe at 1st, credit picked, as the sheet's onChange applies it.
private func fieldersChoice(_ bases: BaseOccupancy, destinations: [Int: Int]? = nil) -> PlayDraft {
    var draft = PlayDraft(basesBefore: bases, batterReachedBase: Base.first, batterCredit: .single)
    draft.batterBaseChanged()
    if let destinations {
        draft.runnerDestinations.merge(destinations) { _, new in new }
    }
    draft.batterCredit = .fieldersChoice
    draft.batterCreditChanged(from: .single)
    return draft
}

/// A saved FC: runner from 1st out at 2nd by `positions`, batter safe at 1st.
private func savedFieldersChoice(_ positions: [String]) -> PitchEvent {
    let draft = fieldersChoice(BaseOccupancy(first: Fixture.r1))
    var event = Fixture.pitch(isStrike: true, outcome: BaseRunnerRules.outcome(for: .fieldersChoice),
                              balls: 0, strikes: 0, play: draft.play,
                              basesBefore: BaseOccupancy(first: Fixture.r1))
    event.fieldingOuts = [FieldingOut(runner: "1", positions: positions)]
    event.defense = defense
    return event
}

final class FieldersChoiceTests: XCTestCase {
    /// Rule 16
    func testFieldersChoiceWithARunnerOnFirstPutsThemOut() throws {
        let draft = fieldersChoice(BaseOccupancy(first: Fixture.r1))
        XCTAssertEqual(draft.runnerDestinations[1], Base.out)
        let play = try XCTUnwrap(draft.play)
        XCTAssertEqual(play.batterCredit, BatterCredit.fieldersChoice.rawValue)
        XCTAssertEqual(play.outs, 1)
        let slots = FieldingPlay.outSlots(play: play, batterOutOnPlay: draft.isBatterOutOnPlay, isStrikeout: false)
        XCTAssertEqual(slots.map(\.runner), ["1"])
        XCTAssertEqual(slots.map(\.label), ["Runner from 1st"])
        XCTAssertNil(draft.conflict)
    }

    /// Rule 17
    func testFieldersChoiceTakesTheLeadForcedRunner() {
        let loaded = fieldersChoice(BaseOccupancy(first: Fixture.r1, second: Fixture.r2, third: Fixture.r3))
        XCTAssertEqual(loaded.runnerDestinations, [1: 2, 2: 3, 3: Base.out])
        XCTAssertNil(loaded.conflict)

        let firstAndSecond = fieldersChoice(BaseOccupancy(first: Fixture.r1, second: Fixture.r2))
        XCTAssertEqual(firstAndSecond.runnerDestinations[2], Base.out)
        XCTAssertEqual(firstAndSecond.runnerDestinations[1], 2)

        let secondOnly = fieldersChoice(BaseOccupancy(second: Fixture.r2))
        XCTAssertEqual(secondOnly.runnerDestinations[2], Base.out, "nobody forced: the lead runner")

        let firstAndThird = fieldersChoice(BaseOccupancy(first: Fixture.r1, third: Fixture.r3))
        XCTAssertEqual(firstAndThird.runnerDestinations[1], Base.out, "the runner on 3rd isn't forced")
        XCTAssertEqual(firstAndThird.runnerDestinations[3], 3)
    }

    /// Rule 18
    func testFieldersChoiceKeepsAnOutAlreadyEntered() {
        let draft = fieldersChoice(BaseOccupancy(first: Fixture.r1, second: Fixture.r2), destinations: [1: Base.out])
        XCTAssertEqual(draft.runnerDestinations[1], Base.out)
        XCTAssertEqual(draft.runnerDestinations[2], 3, "no second out added")
        XCTAssertEqual(draft.play?.outs, 1)
    }

    /// Rule 19
    func testLeavingFieldersChoiceSendsTheRunnerBack() {
        var draft = fieldersChoice(BaseOccupancy(first: Fixture.r1, second: Fixture.r2))
        draft.runnerDestinations[1] = 3 // a move the user made stays
        draft.batterCredit = .single
        draft.batterCreditChanged(from: .fieldersChoice)
        XCTAssertEqual(draft.runnerDestinations[2], 3, "back to the base the batter forced them to")
        XCTAssertNotEqual(draft.runnerDestinations[1], Base.out)
        XCTAssertEqual(draft.play?.outs, 0)
    }

    /// Rule 20
    func testSixFourFieldersChoiceCredits() {
        let event = savedFieldersChoice(["SS", "2B"])
        XCTAssertEqual(FieldingPlay.consistentOuts(event.fieldingOuts, for: event)?.count, 1, "kept on save")
        let ledger = FieldingLedger(events: [event])
        let short = ledger.total(hitterIds: ["h-short"])
        let second = ledger.total(hitterIds: ["h-second"])
        XCTAssertEqual([short.putouts, short.assists], [0, 1])
        XCTAssertEqual([second.putouts, second.assists], [1, 0])
        XCTAssertEqual(short.doublePlays + second.doublePlays, 0)
        XCTAssertEqual(GameProgress.outsMade(by: event), 1)
        XCTAssertEqual(short.outsPlayed, 1)
        XCTAssertNil(FieldingPlay.outSlots(for: event).first { $0.runner == FieldingPlay.batterKey },
                     "the batter is safe, not asked about")
        XCTAssertEqual(FieldingPlay.summary(outs: event.fieldingOuts ?? [], errors: [], descriptor: "Ground ball"), "6-4")
    }

    /// Rule 23
    func testUnassistedFieldersChoice() {
        let event = savedFieldersChoice(["SS"])
        let short = FieldingLedger(events: [event]).total(hitterIds: ["h-short"])
        XCTAssertEqual([short.putouts, short.assists], [1, 0])
        XCTAssertEqual(FieldingPlay.summary(outs: event.fieldingOuts ?? [], errors: [], descriptor: "Ground ball"), "6U")
    }

    /// Rule 21
    func testKeyExplainsEveryColumn() {
        XCTAssertEqual(FieldingStatsKey.entries.map(\.abbreviation), FieldingCountsRow.headers)
        XCTAssertTrue(FieldingStatsKey.entries.allSatisfy { !$0.meaning.isEmpty })
    }
}
