//
//  UndoAndOutsTests.swift
//  PitchMarkTests
//
//  Batch 1 (approved 2026-10-31), rules 11-16: outs from a pitch's outcome
//  (pitches with no bases-diamond play), the third-out reset, and what undo
//  puts back - the count and the outs.
//

import XCTest
@testable import PitchMark

@MainActor
final class UndoAndOutsTests: XCTestCase {
    private typealias F = Fixture

    /// A saved pitch whose count was stamped by applyCount, as the sheet does.
    private func saved(_ id: String, at seconds: TimeInterval, outcome: String? = nil, isBall: Bool = false,
                       isStrike: Bool = false, strikeSwinging: Bool = false,
                       count: AtBatCount, terminal: AtBatTerminal? = nil) -> PitchEvent {
        var pitch = F.pitch(id: id, timestamp: F.t0.addingTimeInterval(seconds), isStrike: isStrike,
                            isBall: isBall, strikeSwinging: strikeSwinging, outcome: outcome)
        pitch.applyCount(count, terminal: terminal)
        return pitch
    }

    // MARK: Outs (rules 11-12)

    /// Rule 11: K, ꓘ and Out each add one out.
    func testStrikeoutsAndOutsAddOneOut() {
        let k = saved("k", at: 0, outcome: "K", isStrike: true, strikeSwinging: true, count: .start, terminal: .strikeout)
        let lookingK = saved("kl", at: 1, outcome: "ꓘ", isStrike: true, count: .start, terminal: .strikeout)
        let out = saved("out", at: 2, outcome: "Out", isStrike: true, count: .start, terminal: .out)
        // A third strike with no outcome typed is labelled "Strikeout" by applyCount.
        let unlabeledK = saved("k3", at: 3, isStrike: true, strikeSwinging: true, count: .start, terminal: .strikeout)
        for pitch in [k, lookingK, out, unlabeledK] {
            XCTAssertEqual(GameProgress.outsMade(by: pitch), 1, pitch.id ?? "")
        }
    }

    /// Rule 11 for pitches saved before the count was stored (no
    /// `atBatCount` label): the outcome alone still makes the out.
    func testOutcomeAloneMakesTheOutOnOlderPitches() {
        for outcome in ["K", "ꓘ", "Out"] {
            let pitch = F.pitch(isStrike: true, outcome: outcome)
            XCTAssertNil(pitch.atBatCount)
            XCTAssertEqual(GameProgress.outsMade(by: pitch), 1, outcome)
        }
    }

    /// Rule 11: nothing else makes an out.
    func testOtherResultsMakeNoOuts() {
        let pitches = [
            saved("walk", at: 0, outcome: "Walk", isBall: true, count: .start, terminal: .walk),
            saved("ball4", at: 1, isBall: true, count: .start, terminal: .walk),
            saved("hbp", at: 2, outcome: "HBP", count: .start, terminal: .hitByPitch),
            saved("single", at: 3, outcome: "1B", isStrike: true, count: .start, terminal: .hit),
            saved("hr", at: 4, outcome: "HR", isStrike: true, count: .start, terminal: .hit),
            saved("ball", at: 5, isBall: true, count: AtBatCount(balls: 1, strikes: 0)),
            saved("strike", at: 6, isStrike: true, strikeSwinging: true, count: AtBatCount(balls: 1, strikes: 1)),
            saved("foul", at: 7, outcome: "Foul", isStrike: true, count: AtBatCount(balls: 1, strikes: 2)),
        ]
        for pitch in pitches {
            XCTAssertEqual(GameProgress.outsMade(by: pitch), 0, pitch.id ?? "")
        }
    }

    /// Rule 11 through the scoreboard.
    func testApplyingAnOutPitch() {
        var game = GameProgress(outs: 1)
        game.applyPitch(saved("out", at: 0, outcome: "Out", isStrike: true, count: .start, terminal: .out))
        XCTAssertEqual(game.outs, 2)
        game.applyPitch(saved("ball", at: 1, isBall: true, count: AtBatCount(balls: 1, strikes: 0)))
        XCTAssertEqual(game.outs, 2)
    }

    /// Rule 12: the third out shows 3, then resets to 0.
    func testThirdOutShowsThreeThenResets() {
        var game = GameProgress(outs: 2)
        game.applyPitch(saved("k", at: 0, outcome: "K", isStrike: true, strikeSwinging: true, count: .start, terminal: .strikeout))
        XCTAssertEqual(game.outs, 3)
        game.completeThirdOut()
        XCTAssertEqual(game.outs, 0)
    }

    // MARK: Undo (rules 13-16)

    /// Rule 13: the count goes back to what the pitch before left.
    func testUndoRestoresThePreviousPitchesCount() {
        let first = saved("p1", at: 0, isBall: true, count: AtBatCount(balls: 1, strikes: 0))
        let second = saved("p2", at: 1, isStrike: true, strikeSwinging: true, count: AtBatCount(balls: 1, strikes: 1))
        // Undo the third pitch: what's left, newest first.
        XCTAssertEqual(GameProgress.countAfterUndo(remainingNewestFirst: [second, first]), AtBatCount(balls: 1, strikes: 1))
    }

    /// Rule 13: no pitches left - 0-0.
    func testUndoTheOnlyPitchGivesZeroZero() {
        XCTAssertEqual(GameProgress.countAfterUndo(remainingNewestFirst: []), .start)
    }

    /// Rule 14: undoing ball four at 3-2 puts the count back to 3-2.
    func testUndoAWalkRestoresTheFullCount() {
        let atBat = [
            saved("p1", at: 0, isBall: true, count: AtBatCount(balls: 1, strikes: 0)),
            saved("p2", at: 1, isBall: true, count: AtBatCount(balls: 2, strikes: 0)),
            saved("p3", at: 2, isBall: true, count: AtBatCount(balls: 3, strikes: 0)),
            saved("p4", at: 3, isStrike: true, strikeSwinging: true, count: AtBatCount(balls: 3, strikes: 1)),
            saved("p5", at: 4, outcome: "Foul", isStrike: true, count: AtBatCount(balls: 3, strikes: 2)),
        ]
        // p6 (ball four) undone.
        let remaining = atBat.sorted { $0.timestamp > $1.timestamp }
        XCTAssertEqual(GameProgress.countAfterUndo(remainingNewestFirst: remaining), AtBatCount(balls: 3, strikes: 2))
    }

    /// Rule 14: undoing the first pitch of a new batter goes back to the
    /// previous batter's ending pitch - stored 0-0.
    func testUndoAfterAnAtBatEndedGivesZeroZero() {
        let walk = saved("walk", at: 0, isBall: true, count: .start, terminal: .walk)
        XCTAssertEqual(GameProgress.countAfterUndo(remainingNewestFirst: [walk]), .start)
    }

    /// Rule 15: undoing a strikeout or out takes the out back.
    func testUndoTakesTheOutBack() {
        var game = GameProgress(outs: 1)
        let k = saved("k", at: 0, outcome: "K", isStrike: true, strikeSwinging: true, count: .start, terminal: .strikeout)
        game.applyPitch(k)
        XCTAssertEqual(game.outs, 2)
        game.undoPitch(k)
        XCTAssertEqual(game.outs, 1)

        let out = saved("out", at: 1, outcome: "Out", isStrike: true, count: .start, terminal: .out)
        game.applyPitch(out)
        game.undoPitch(out)
        XCTAssertEqual(game.outs, 1)
    }

    /// Undoing a pitch that made no out leaves the outs alone.
    func testUndoAPitchWithNoOutKeepsTheOuts() {
        var game = GameProgress(outs: 2)
        let ball = saved("ball", at: 0, isBall: true, count: AtBatCount(balls: 1, strikes: 0))
        game.applyPitch(ball)
        game.undoPitch(ball)
        XCTAssertEqual(game.outs, 2)
    }

    /// Rule 16: undoing the third out after the board reset puts 2 outs back.
    func testUndoTheThirdOutAfterTheReset() {
        var game = GameProgress(outs: 2)
        let k = saved("k3", at: 0, outcome: "K", isStrike: true, strikeSwinging: true, count: .start, terminal: .strikeout)
        game.applyPitch(k)
        game.completeThirdOut()
        XCTAssertEqual(game.outs, 0)
        game.undoPitch(k)
        XCTAssertEqual(game.outs, 2)
    }
}
