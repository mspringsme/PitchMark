//
//  CountTests.swift
//  PitchMarkTests
//
//  Batch 1 (approved 2026-10-31), rules 1-10 and 17-20: how a pitch
//  changes the count, what a saved pitch records, the per-batter seed, and
//  the result sheet's derived count.
//

import XCTest
@testable import PitchMark

private typealias Facts = AtBatCountRules.PitchFacts

private func count(_ balls: Int, _ strikes: Int) -> AtBatCount {
    AtBatCount(balls: balls, strikes: strikes)
}

@MainActor
final class CountRulesTests: XCTestCase {
    private func apply(_ facts: Facts, to prior: AtBatCount) -> (count: AtBatCount, terminal: AtBatTerminal?) {
        AtBatCountRules.apply(facts, to: prior)
    }

    /// Rule 1.
    func testBallAddsABall() {
        XCTAssertEqual(apply(Facts(isBall: true), to: count(0, 0)).count, count(1, 0))
        XCTAssertEqual(apply(Facts(isBall: true), to: count(2, 1)).count, count(3, 1))
        XCTAssertNil(apply(Facts(isBall: true), to: count(2, 1)).terminal)
    }

    /// Rule 2.
    func testFourthBallIsAWalk() {
        for strikes in 0...2 {
            let result = apply(Facts(isBall: true), to: count(3, strikes))
            XCTAssertEqual(result.terminal, .walk, "3-\(strikes)")
            XCTAssertEqual(result.count, .start)
        }
    }

    /// Rule 3: swinging, looking, or in the zone with nothing else marked.
    func testStrikesAddAStrike() {
        XCTAssertEqual(apply(Facts(strikeSwinging: true), to: count(1, 0)).count, count(1, 1))
        XCTAssertEqual(apply(Facts(strikeLooking: true), to: count(1, 1)).count, count(1, 2))
        XCTAssertEqual(apply(Facts(locationInStrikeZone: true), to: count(0, 0)).count, count(0, 1))
    }

    /// Rule 4.
    func testThirdStrikeIsAStrikeout() {
        for balls in 0...3 {
            for facts in [Facts(strikeSwinging: true), Facts(strikeLooking: true), Facts(locationInStrikeZone: true)] {
                let result = apply(facts, to: count(balls, 2))
                XCTAssertEqual(result.terminal, .strikeout, "\(balls)-2 \(facts)")
                XCTAssertEqual(result.count, .start)
            }
        }
    }

    /// Rule 5.
    func testFoulIsAStrikeOnlyBelowTwoStrikes() {
        XCTAssertEqual(apply(Facts(isFoul: true), to: count(0, 0)).count, count(0, 1))
        XCTAssertEqual(apply(Facts(isFoul: true), to: count(2, 1)).count, count(2, 2))
        var twoStrikes = count(1, 2)
        for _ in 0..<5 {
            let result = apply(Facts(isFoul: true), to: twoStrikes)
            XCTAssertNil(result.terminal, "a foul never ends the at-bat")
            twoStrikes = result.count
        }
        XCTAssertEqual(twoStrikes, count(1, 2))
        XCTAssertEqual(apply(Facts(outcome: "Foul"), to: count(0, 1)).count, count(0, 2), "Foul as an outcome counts too")
    }

    /// Rule 6: recorded results end the at-bat at any count.
    func testRecordedResultsEndTheAtBat() {
        let cases: [(Facts, AtBatTerminal)] = [
            (Facts(isHitBatter: true), .hitByPitch),
            (Facts(outcome: "HBP"), .hitByPitch),
            (Facts(outcome: "Walk"), .walk),
            (Facts(outcome: "K"), .strikeout),
            (Facts(outcome: "ꓘ"), .strikeout),
            (Facts(outcome: "Out"), .out),
            (Facts(outcome: "1B"), .hit),
            (Facts(outcome: "2B"), .hit),
            (Facts(outcome: "3B"), .hit),
            (Facts(outcome: "HR"), .hit),
            (Facts(outcome: "Hit"), .hit),
        ]
        for prior in [count(0, 0), count(1, 1), count(3, 2)] {
            for (facts, terminal) in cases {
                let result = apply(facts, to: prior)
                XCTAssertEqual(result.terminal, terminal, "\(facts.outcome ?? "HBP flag") at \(prior.displayText)")
                XCTAssertEqual(result.count, .start)
            }
        }
    }

    /// Rule 7.
    func testConflictingSignals() {
        let hbpOverBall = apply(Facts(isBall: true, isHitBatter: true), to: count(1, 1))
        XCTAssertEqual(hbpOverBall.terminal, .hitByPitch)
        let hbpOverStrike = apply(Facts(strikeSwinging: true, isHitBatter: true), to: count(1, 2))
        XCTAssertEqual(hbpOverStrike.terminal, .hitByPitch, "HBP, not a strikeout")

        let ballInZone = apply(Facts(isBall: true, locationInStrikeZone: true), to: count(0, 0))
        XCTAssertEqual(ballInZone.count, count(1, 0))
        XCTAssertNil(ballInZone.terminal)
    }

    /// Rule 8.
    func testPitchOutsideZoneWithNothingMarkedChangesNothing() {
        let result = apply(Facts(), to: count(2, 1))
        XCTAssertEqual(result.count, count(2, 1))
        XCTAssertNil(result.terminal)
    }

    /// Rule 9.
    func testReplayingAnAtBat() {
        let atBat = [Facts(isBall: true), Facts(strikeSwinging: true), Facts(isFoul: true), Facts(isFoul: true), Facts(isBall: true)]
        XCTAssertEqual(AtBatCountRules.reduce(atBat), count(2, 2))
    }

    /// Counts can't be impossible.
    func testCountIsClamped() {
        XCTAssertEqual(AtBatCount(balls: 7, strikes: -2), count(3, 0))
    }
}

@MainActor
final class SavedCountTests: XCTestCase {
    /// Rule 10: a pitch that ended the at-bat stores 0-0 and how it ended.
    func testTerminalPitchStoresResetCountAndLabel() {
        let labels: [AtBatTerminal: String] = [
            .walk: "Ball 4", .strikeout: "Strikeout", .hitByPitch: "HBP", .out: "Out", .hit: "Hit"
        ]
        for (terminal, label) in labels {
            var pitch = Fixture.pitch()
            pitch.applyCount(count(3, 2), terminal: terminal)
            XCTAssertEqual(pitch.atBatBalls, 0, label)
            XCTAssertEqual(pitch.atBatStrikes, 0, label)
            XCTAssertEqual(pitch.atBatCount, label)
        }
    }

    /// Rule 10: any other pitch stores its count, and the label matches it.
    func testNonTerminalPitchStoresItsCount() {
        var pitch = Fixture.pitch()
        pitch.applyCount(count(2, 1), terminal: nil)
        XCTAssertEqual(pitch.atBatBalls, 2)
        XCTAssertEqual(pitch.atBatStrikes, 1)
        XCTAssertEqual(pitch.atBatCount, "2-1")
    }
}

@MainActor
final class CountDraftTests: XCTestCase {
    /// Rule 17: the next pitch for a batter starts from their own last saved
    /// pitch, even when the live count belongs to someone else.
    func testSeedPrefersTheBattersOwnLastPitch() {
        let seed = CountDraft.seed(lastSavedPitchCount: (balls: 2, strikes: 1),
                                   liveCount: (balls: 0, strikes: 2),
                                   rememberedCount: (balls: 1, strikes: 1))
        XCTAssertEqual(seed, count(2, 1))
    }

    /// Rule 17: with no saved pitch for the batter, the live count, then the
    /// per-batter memory, then 0-0.
    func testSeedFallbacks() {
        XCTAssertEqual(CountDraft.seed(lastSavedPitchCount: nil, liveCount: (1, 2), rememberedCount: (3, 0)), count(1, 2))
        XCTAssertEqual(CountDraft.seed(lastSavedPitchCount: nil, liveCount: nil, rememberedCount: (3, 0)), count(3, 0))
        XCTAssertEqual(CountDraft.seed(lastSavedPitchCount: nil, liveCount: nil, rememberedCount: nil), .start)
        XCTAssertEqual(CountDraft.seed(lastSavedPitchCount: (balls: nil, strikes: nil), liveCount: (1, 1), rememberedCount: nil),
                       count(1, 1), "a saved pitch with no stored count is skipped")
    }

    /// Rule 17: switching batters and back - the per-batter key is stable.
    func testBatterKey() {
        XCTAssertEqual(GameProgress.batterKey(batterId: "cell-1", jersey: "7"), "id:cell-1")
        XCTAssertEqual(GameProgress.batterKey(batterId: nil, jersey: " 7 "), "jersey:7")
        XCTAssertNil(GameProgress.batterKey(batterId: "", jersey: ""))
    }

    /// Rule 18: the shown count is seed + current selection; changing the
    /// selection replaces it rather than stacking.
    func testSelectionReplacesRatherThanStacks() {
        var draft = CountDraft()
        draft.open(seed: count(1, 1))
        XCTAssertEqual(draft.resolved(Facts(isBall: true)), count(2, 1))
        XCTAssertEqual(draft.resolved(Facts(strikeSwinging: true)), count(1, 2))
        XCTAssertEqual(draft.resolved(Facts(isBall: true)), count(2, 1))
        XCTAssertEqual(draft.resolved(Facts()), count(1, 1), "nothing selected = the seed")
    }

    /// Rule 19: a hand correction replaces the count outright, isn't run
    /// through the pitch rules again, and infers no at-bat ending.
    func testHandCorrectionReplacesTheCount() {
        var draft = CountDraft()
        draft.open(seed: count(1, 1))
        draft.tapBall(3, facts: Facts(isBall: true))
        XCTAssertEqual(draft.resolved(Facts(isBall: true)), count(3, 1), "set to 3 balls, not 3 + this ball")
        XCTAssertNil(draft.terminal(Facts(isBall: true)), "a corrected 3-1 + ball is not inferred as a walk")
        draft.tapStrike(2, facts: Facts(isBall: true))
        XCTAssertEqual(draft.resolved(Facts()), count(3, 2))
        draft.tapStrike(2, facts: Facts())
        XCTAssertEqual(draft.resolved(Facts()), count(3, 1), "tapping the filled value steps down by one")
    }

    /// Rule 19: Refresh goes back to 0-0 with no correction.
    func testRefreshResetsToStart() {
        var draft = CountDraft()
        draft.open(seed: count(2, 2))
        draft.tapBall(1, facts: Facts())
        draft.resetToStart()
        XCTAssertEqual(draft.resolved(Facts()), .start)
        XCTAssertNil(draft.manualOverride)
    }

    /// Rule 20: the count is published while the sheet is open; tearing it
    /// down - when the shown count falls back to the stale pre-pitch seed -
    /// publishes nothing.
    func testClosingTheSheetDoesNotPublishTheStaleSeed() {
        var draft = CountDraft()
        XCTAssertFalse(draft.shouldPublish(isPresented: true), "not seeded yet")
        draft.open(seed: count(0, 0))
        XCTAssertTrue(draft.shouldPublish(isPresented: true))
        XCTAssertEqual(draft.resolved(Facts(isBall: true)), count(1, 0), "this is what gets published and saved")

        // Save, then teardown: isPresented goes false and selections clear.
        XCTAssertFalse(draft.shouldPublish(isPresented: false))
        draft.close()
        XCTAssertFalse(draft.shouldPublish(isPresented: true), "closed draft never publishes")
        XCTAssertEqual(draft.resolved(Facts()), count(0, 0), "the stale value that must not go out")
    }
}
