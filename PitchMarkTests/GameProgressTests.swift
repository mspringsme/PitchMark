//
//  GameProgressTests.swift
//  PitchMarkTests
//
//  Phase 3 rules 1-9, 12-14 and 17-20 (the list approved 2026-10-31):
//  steals, caught stealing, pickoffs, advances, pinch runners, the third
//  out, wild pitch / passed ball on the pitch, and undo.
//
//  "Batting team" is the side not pitching: with Home pitching, runs go to
//  the Away score.
//

import XCTest
@testable import PitchMark

@MainActor
final class GameProgressTests: XCTestCase {
    private typealias F = Fixture

    private func progress(
        _ bases: BaseOccupancy,
        outs: Int = 0,
        home: Int = 0,
        away: Int = 0,
        pitching: GameProgress.Side = .home
    ) -> GameProgress {
        GameProgress(bases: bases, outs: outs, homeScore: home, awayScore: away, pitchingSide: pitching)
    }

    @discardableResult
    private func record(
        _ kind: RunnerEventKind,
        from: Int,
        on game: inout GameProgress,
        substitute: BaseRunner? = nil,
        id: String = "event-1",
        at timestamp: Date = Fixture.t0
    ) -> RunnerEvent? {
        game.recordRunnerEvent(kind, from: from, substitute: substitute, id: id, timestamp: timestamp, context: F.context)
    }

    // MARK: Steals (rules 1-4)

    /// Rule 1: a runner on 1st steals - 2nd occupied, 1st empty, no outs, no runs.
    func testStealSecondMovesRunnerOnly() {
        var game = progress(BaseOccupancy(first: F.r1), outs: 1, home: 2, away: 3)
        let event = record(.stolenBase, from: 1, on: &game)
        XCTAssertNotNil(event)
        XCTAssertEqual(game.bases, BaseOccupancy(second: F.r1))
        XCTAssertEqual(game.outs, 1)
        XCTAssertEqual(game.homeScore, 2)
        XCTAssertEqual(game.awayScore, 3)
    }

    /// Rule 2: no steal into an occupied base; once the lead runner goes,
    /// the trail runner can.
    func testStealNeedsTheNextBaseEmpty() {
        var game = progress(BaseOccupancy(first: F.r1, second: F.r2))
        XCTAssertNil(record(.stolenBase, from: 1, on: &game), "2nd is taken")
        XCTAssertEqual(game.bases, BaseOccupancy(first: F.r1, second: F.r2), "a refused steal changes nothing")

        XCTAssertNotNil(record(.stolenBase, from: 2, on: &game, id: "lead"))
        XCTAssertEqual(game.bases, BaseOccupancy(first: F.r1, third: F.r2))

        XCTAssertNotNil(record(.stolenBase, from: 1, on: &game, id: "trail"))
        XCTAssertEqual(game.bases, BaseOccupancy(second: F.r1, third: F.r2))
    }

    /// Rule 3: steal of home scores for the batting team, and is always allowed.
    func testStealHomeScoresForTheBattingTeam() {
        var homePitching = progress(BaseOccupancy(first: F.r1, second: F.r2, third: F.r3), home: 0, away: 0, pitching: .home)
        XCTAssertNotNil(record(.stolenBase, from: 3, on: &homePitching))
        XCTAssertEqual(homePitching.bases, BaseOccupancy(first: F.r1, second: F.r2))
        XCTAssertEqual(homePitching.awayScore, 1, "Home pitching: Away is batting")
        XCTAssertEqual(homePitching.homeScore, 0)
        XCTAssertEqual(homePitching.outs, 0)

        var awayPitching = progress(BaseOccupancy(third: F.r3), home: 4, away: 0, pitching: .away)
        XCTAssertNotNil(record(.stolenBase, from: 3, on: &awayPitching))
        XCTAssertEqual(awayPitching.homeScore, 5, "Away pitching: Home is batting")
        XCTAssertEqual(awayPitching.awayScore, 0)
    }

    /// Rule 4: the saved steal record.
    func testStealRecordFields() throws {
        var game = progress(BaseOccupancy(first: F.r1, third: F.r3))
        let event = try XCTUnwrap(record(.stolenBase, from: 1, on: &game, id: "sb-1", at: F.t0))
        XCTAssertEqual(event.id, "sb-1")
        XCTAssertEqual(event.kind, "SB")
        XCTAssertEqual(event.from, 1)
        XCTAssertEqual(event.to, 2)
        XCTAssertEqual(event.runner, F.r1)
        XCTAssertEqual(event.hitterId, "hitter-1")
        XCTAssertEqual(event.basesBefore, BaseOccupancy(first: F.r1, third: F.r3))
        XCTAssertEqual(event.gameId, "game-1")
        XCTAssertEqual(event.pitcherId, "pitcher-1")
        XCTAssertEqual(event.inning, 4)
        XCTAssertEqual(event.createdByUid, "coach-1")
        XCTAssertEqual(event.timestamp, F.t0)
        XCTAssertNil(event.replaced)
    }

    // MARK: Caught stealing / picked off (rules 5-7)

    /// Rule 5: caught stealing - runner off, one out, no run, others stay.
    func testCaughtStealing() throws {
        var game = progress(BaseOccupancy(first: F.r1, third: F.r3), outs: 0, away: 2)
        let event = try XCTUnwrap(record(.caughtStealing, from: 1, on: &game))
        XCTAssertEqual(game.bases, BaseOccupancy(third: F.r3))
        XCTAssertEqual(game.outs, 1)
        XCTAssertEqual(game.awayScore, 2)
        XCTAssertEqual(event.kind, "CS")
        XCTAssertEqual(event.to, Base.out)
    }

    /// Rule 6: picked off - same effect, kind PO.
    func testPickedOff() throws {
        var game = progress(BaseOccupancy(second: F.r2, third: F.r3), outs: 1)
        let event = try XCTUnwrap(record(.pickedOff, from: 3, on: &game))
        XCTAssertEqual(game.bases, BaseOccupancy(second: F.r2))
        XCTAssertEqual(game.outs, 2)
        XCTAssertEqual(event.kind, "PO")
        XCTAssertEqual(event.to, Base.out)
    }

    /// Rule 7: a caught stealing for the third out - outs hit 3, then the
    /// reset leaves 0 outs and empty bases.
    func testThirdOutOnCaughtStealingClearsTheBases() {
        var game = progress(BaseOccupancy(first: F.r1, second: F.r2), outs: 2)
        record(.caughtStealing, from: 2, on: &game, id: "cs-3rd")
        XCTAssertEqual(game.outs, 3)
        XCTAssertEqual(game.lastThirdOut, GameProgress.ThirdOut(identity: "cs-3rd", previousOuts: 2))

        game.completeThirdOut()
        XCTAssertEqual(game.outs, 0)
        XCTAssertEqual(game.bases, .empty)
    }

    /// Rule 7, pickoff version.
    func testThirdOutOnPickoffClearsTheBases() {
        var game = progress(BaseOccupancy(first: F.r1, third: F.r3), outs: 2)
        record(.pickedOff, from: 1, on: &game)
        XCTAssertEqual(game.outs, 3)
        game.completeThirdOut()
        XCTAssertEqual(game.outs, 0)
        XCTAssertEqual(game.bases, .empty)
    }

    // MARK: Advance / pinch runner (rules 8-9)

    /// Rule 8: an advance moves like a steal (and scores from 3rd) but is
    /// recorded as ADV.
    func testAdvanceMovesLikeASteal() throws {
        var game = progress(BaseOccupancy(first: F.r1, third: F.r3))
        let fromThird = try XCTUnwrap(record(.advanced, from: 3, on: &game, id: "adv-1"))
        XCTAssertEqual(fromThird.kind, "ADV")
        XCTAssertEqual(game.bases, BaseOccupancy(first: F.r1))
        XCTAssertEqual(game.awayScore, 1)
        XCTAssertNotNil(record(.advanced, from: 1, on: &game, id: "adv-2"))
        XCTAssertEqual(game.bases, BaseOccupancy(second: F.r1))
        XCTAssertEqual(game.outs, 0)
    }

    /// Rule 9: a pinch runner takes the same base; nothing else changes.
    func testPinchRunner() throws {
        var game = progress(BaseOccupancy(first: F.r1, second: F.r2), outs: 1, home: 1, away: 2)
        let event = try XCTUnwrap(record(.substitution, from: 1, on: &game, substitute: F.pinch))
        XCTAssertEqual(game.bases, BaseOccupancy(first: F.pinch, second: F.r2))
        XCTAssertEqual(game.outs, 1)
        XCTAssertEqual(game.homeScore, 1)
        XCTAssertEqual(game.awayScore, 2)
        XCTAssertEqual(event.kind, "SUB")
        XCTAssertEqual(event.runner, F.pinch)
        XCTAssertEqual(event.replaced, F.r1)
        XCTAssertEqual(event.hitterId, "hitter-22", "credited to the runner coming in")
    }

    /// Rule 9: a pinch runner needs someone named.
    func testPinchRunnerWithoutSubstituteIsRefused() {
        var game = progress(BaseOccupancy(first: F.r1))
        XCTAssertNil(record(.substitution, from: 1, on: &game))
        XCTAssertEqual(game.bases, BaseOccupancy(first: F.r1))
    }

    /// No runner on the base, no event.
    func testRunnerEventOnEmptyBaseIsRefused() {
        var game = progress(BaseOccupancy(first: F.r1))
        for kind in RunnerEventKind.allCases {
            XCTAssertNil(record(kind, from: 2, on: &game, substitute: F.pinch), "\(kind) from an empty base")
        }
        XCTAssertEqual(game, progress(BaseOccupancy(first: F.r1)))
    }

    // MARK: Wild pitch / passed ball on the pitch (rules 10, 12-14)

    /// Rule 10: WP with runners on 2nd and 3rd, both move up one: only 3rd
    /// occupied, one run, no out, batter not on base.
    func testWildPitchAdvancesRunnersAndScores() throws {
        let before = BaseOccupancy(second: F.r2, third: F.r3)
        let play = try XCTUnwrap(BaseRunnerRules.runnersOnlyPlay(before: before, destinations: [2: 3, 3: 4], reason: .wildPitch))
        var pitch = F.pitch(isBall: true, wildPitch: true, balls: 1, strikes: 0, play: play)
        GameProgress.stampBasePlay(on: &pitch, bases: before)

        var game = progress(before, outs: 1)
        game.applyPitch(pitch)
        XCTAssertEqual(game.bases, BaseOccupancy(third: F.r2))
        XCTAssertEqual(game.awayScore, 1)
        XCTAssertEqual(game.outs, 1)
        XCTAssertNil(pitch.play?.batterMove, "the batter isn't put on base")
    }

    /// Rule 10, passed ball - same mechanics, tagged PB.
    func testPassedBallAdvanceIsTaggedPB() throws {
        let before = BaseOccupancy(first: F.r1)
        let play = try XCTUnwrap(BaseRunnerRules.runnersOnlyPlay(before: before, destinations: [1: 2], reason: .passedBall))
        XCTAssertEqual(play.moves.first?.extraBasesOn, "PB")
        var game = progress(before)
        game.applyPitch(F.pitch(isStrike: true, passedBall: true, balls: 0, strikes: 1, play: play, basesBefore: before))
        XCTAssertEqual(game.bases, BaseOccupancy(second: F.r1))
    }

    /// Rule 12: a wild pitch on strike three - the batter's out counts on
    /// top of the runner moves.
    func testWildPitchOnStrikeThreeStillCountsTheStrikeout() throws {
        let before = BaseOccupancy(first: F.r1)
        let play = try XCTUnwrap(BaseRunnerRules.runnersOnlyPlay(before: before, destinations: [1: 2], reason: .wildPitch))
        let pitch = F.pitch(isStrike: true, strikeSwinging: true, wildPitch: true, outcome: "K",
                            balls: 0, strikes: 0, play: play, basesBefore: before)
        XCTAssertEqual(GameProgress.outsMade(by: pitch), 1)

        var game = progress(before, outs: 0)
        game.applyPitch(pitch)
        XCTAssertEqual(game.outs, 1)
        XCTAssertEqual(game.bases, BaseOccupancy(second: F.r1))
    }

    /// Rule 12: and a runner thrown out on that pitch is a second out.
    func testWildPitchStrikeoutWithRunnerOutIsTwoOuts() throws {
        let before = BaseOccupancy(first: F.r1)
        let play = try XCTUnwrap(BaseRunnerRules.runnersOnlyPlay(before: before, destinations: [1: Base.out], reason: .wildPitch))
        let pitch = F.pitch(isStrike: true, strikeSwinging: true, wildPitch: true, outcome: "K",
                            balls: 0, strikes: 0, play: play, basesBefore: before)
        XCTAssertEqual(GameProgress.outsMade(by: pitch), 2)
    }

    /// Rule 13: ball four on a wild pitch that took the runner from 2nd to
    /// 3rd - batter on 1st, runner keeps 3rd.
    func testBallFourOnWildPitchKeepsTheFurtherBase() throws {
        let before = BaseOccupancy(second: F.r2)
        let wp = try XCTUnwrap(BaseRunnerRules.runnersOnlyPlay(before: before, destinations: [2: 3], reason: .wildPitch))
        // Ball four: stored 0-0 by applyCount, no explicit Walk outcome.
        var pitch = F.pitch(isBall: true, wildPitch: true, balls: 0, strikes: 0, jersey: "9", play: wp)
        GameProgress.stampBasePlay(on: &pitch, bases: before)
        XCTAssertEqual(pitch.play?.credit, .walk)

        var game = progress(before)
        game.applyPitch(pitch)
        let batter = BaseRunner(id: "cell-9", label: "#9", hitterId: "hitter-9")
        XCTAssertEqual(game.bases, BaseOccupancy(first: batter, third: F.r2))
        XCTAssertEqual(game.outs, 0)
        XCTAssertEqual(game.awayScore, 0)
    }

    /// Rule 14: ball four, runner on 1st not moved on the WP - the force
    /// still sends them to 2nd.
    func testBallFourForcesAnUnmovedRunner() {
        let before = BaseOccupancy(first: F.r1)
        var pitch = F.pitch(isBall: true, wildPitch: true, balls: 0, strikes: 0, jersey: "9")
        GameProgress.stampBasePlay(on: &pitch, bases: before)
        var game = progress(before)
        game.applyPitch(pitch)
        let batter = BaseRunner(id: "cell-9", label: "#9", hitterId: "hitter-9")
        XCTAssertEqual(game.bases, BaseOccupancy(first: batter, second: F.r1))
    }

    /// A plain ball that isn't ball four leaves the bases alone.
    func testNonTerminalBallDoesNotMoveRunners() {
        let before = BaseOccupancy(first: F.r1)
        var pitch = F.pitch(isBall: true, balls: 2, strikes: 1)
        GameProgress.stampBasePlay(on: &pitch, bases: before)
        XCTAssertNil(pitch.play)
        XCTAssertEqual(pitch.basesBefore, before)
        var game = progress(before)
        game.applyPitch(pitch)
        XCTAssertEqual(game.bases, before)
    }

    // MARK: Undo (rules 17-20)

    /// Rule 17: undo right after a steal.
    func testUndoSteal() throws {
        let start = progress(BaseOccupancy(first: F.r1), outs: 1, home: 2, away: 3)
        var game = start
        let event = try XCTUnwrap(record(.stolenBase, from: 1, on: &game))
        game.undoRunnerEvent(event)
        XCTAssertEqual(game.bases, start.bases)
        XCTAssertEqual(game.outs, 1)
        XCTAssertEqual(game.homeScore, 2)
        XCTAssertEqual(game.awayScore, 3)
    }

    /// Rule 18: undo a steal of home takes the run back off.
    func testUndoStealOfHomeRemovesTheRun() throws {
        var game = progress(BaseOccupancy(third: F.r3), away: 5)
        let event = try XCTUnwrap(record(.stolenBase, from: 3, on: &game))
        XCTAssertEqual(game.awayScore, 6)
        game.undoRunnerEvent(event)
        XCTAssertEqual(game.awayScore, 5)
        XCTAssertEqual(game.bases, BaseOccupancy(third: F.r3))
    }

    /// Rule 19: undo a caught stealing that made the third out, after the
    /// board already reset - outs back to 2, bases restored.
    func testUndoThirdOutCaughtStealingAfterReset() throws {
        let before = BaseOccupancy(first: F.r1, second: F.r2)
        var game = progress(before, outs: 2)
        let event = try XCTUnwrap(record(.caughtStealing, from: 2, on: &game, id: "cs-3rd"))
        game.completeThirdOut()
        XCTAssertEqual(game.outs, 0)

        game.undoRunnerEvent(event)
        XCTAssertEqual(game.outs, 2)
        XCTAssertEqual(game.bases, before)
        XCTAssertNil(game.lastThirdOut)
    }

    /// Undo of a pinch runner puts the original runner back.
    func testUndoPinchRunner() throws {
        var game = progress(BaseOccupancy(first: F.r1))
        let event = try XCTUnwrap(record(.substitution, from: 1, on: &game, substitute: F.pinch))
        game.undoRunnerEvent(event)
        XCTAssertEqual(game.bases, BaseOccupancy(first: F.r1))
    }

    /// Rule 20: a pitch after the steal is what undo removes.
    func testUndoTargetsTheNewerOfStealAndPitch() {
        let steal = RunnerEvent(id: "sb", timestamp: F.t0, kind: "SB", from: 1, to: 2, runner: F.r1,
                                basesBefore: BaseOccupancy(first: F.r1))
        XCTAssertEqual(
            GameProgress.runnerEventToUndo(sessionRunnerEvents: [steal], lastPitchTimestamp: F.t0.addingTimeInterval(5)),
            nil, "pitch came after the steal"
        )
        XCTAssertEqual(
            GameProgress.runnerEventToUndo(sessionRunnerEvents: [steal], lastPitchTimestamp: F.t0.addingTimeInterval(-5)),
            steal, "steal came after the pitch"
        )
        XCTAssertEqual(GameProgress.runnerEventToUndo(sessionRunnerEvents: [steal], lastPitchTimestamp: nil), steal)
        XCTAssertNil(GameProgress.runnerEventToUndo(sessionRunnerEvents: [], lastPitchTimestamp: F.t0))
    }

    /// Rule 20: undo of that later pitch leaves the steal's bases alone
    /// when the pitch moved nobody.
    func testUndoPlainPitchAfterStealKeepsTheSteal() throws {
        var game = progress(BaseOccupancy(first: F.r1))
        try XCTUnwrap(record(.stolenBase, from: 1, on: &game))
        var pitch = F.pitch(isStrike: true, balls: 0, strikes: 1)
        GameProgress.stampBasePlay(on: &pitch, bases: game.bases)
        game.applyPitch(pitch)
        game.undoPitch(pitch)
        XCTAssertEqual(game.bases, BaseOccupancy(second: F.r1))
    }

    /// Undo of a WP pitch restores the runners and takes back its run.
    func testUndoWildPitchRestoresRunnersAndRun() throws {
        let before = BaseOccupancy(second: F.r2, third: F.r3)
        let play = try XCTUnwrap(BaseRunnerRules.runnersOnlyPlay(before: before, destinations: [2: 3, 3: 4], reason: .wildPitch))
        var pitch = F.pitch(isBall: true, wildPitch: true, balls: 1, strikes: 0, play: play)
        GameProgress.stampBasePlay(on: &pitch, bases: before)
        var game = progress(before, away: 2)
        game.applyPitch(pitch)
        game.undoPitch(pitch)
        XCTAssertEqual(game.bases, before)
        XCTAssertEqual(game.awayScore, 2)
        XCTAssertEqual(game.outs, 0)
    }
}
