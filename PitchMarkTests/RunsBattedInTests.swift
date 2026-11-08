//
//  RunsBattedInTests.swift
//  PitchMarkTests
//
//  RBI rules 35-40 and runs-scored rules 41-43 (approved 2026-11-05):
//  both come from the play saved on each pitch.
//

import XCTest
@testable import PitchMark

@MainActor
final class RunsBattedInTests: XCTestCase {
    private typealias F = Fixture

    private func move(_ runner: BaseRunner, from: Int, to: Int, on reason: ExtraBasesReason? = nil) -> RunnerMove {
        RunnerMove(runner: runner.id, from: from, to: to, extraBasesOn: reason?.rawValue)
    }

    private func pitch(_ credit: BatterCredit, batterTo: Int, outcome: String? = nil,
                       runners: [RunnerMove] = [], before: BaseOccupancy = .empty,
                       hitterId: String? = "hitter-9", batterReason: ExtraBasesReason? = nil) -> PitchEvent {
        let play = BasePlay(batterCredit: credit.rawValue,
                            moves: [RunnerMove(runner: RunnerMove.batterKey, from: Base.home, to: batterTo,
                                               extraBasesOn: batterReason?.rawValue)] + runners)
        return F.pitch(isStrike: true, outcome: outcome ?? BaseRunnerRules.outcome(for: credit),
                       hitterId: hitterId, play: play, basesBefore: before)
    }

    private func rbi(_ event: PitchEvent) -> Int { HittingStatLine.runsBattedIn(for: event) }

    /// Rule 35: every run scoring on a hit is an RBI, the batter's own on a home run.
    func testRunsOnAHitAreRBIs() {
        let single = pitch(.single, batterTo: Base.first,
                           runners: [move(F.r3, from: 3, to: Base.scored), move(F.r2, from: 2, to: Base.scored)],
                           before: BaseOccupancy(second: F.r2, third: F.r3))
        XCTAssertEqual(rbi(single), 2)

        let grandSlam = pitch(.homeRun, batterTo: Base.scored,
                              runners: [move(F.r1, from: 1, to: Base.scored), move(F.r2, from: 2, to: Base.scored),
                                        move(F.r3, from: 3, to: Base.scored)],
                              before: BaseOccupancy(first: F.r1, second: F.r2, third: F.r3))
        XCTAssertEqual(rbi(grandSlam), 4)

        let solo = pitch(.homeRun, batterTo: Base.scored)
        XCTAssertEqual(rbi(solo), 1)

        let line = HittingStatLine(events: [single, grandSlam, solo])
        XCTAssertEqual(line.runsBattedIn, 7)
    }

    /// Rule 36: a walk or HBP with the bases loaded drives in one; with a
    /// base open it drives in none.
    func testBasesLoadedWalkAndHitByPitch() {
        let loaded = BaseOccupancy(first: F.r1, second: F.r2, third: F.r3)
        let walk = BaseRunnerRules.awardedFirstPlay(credit: .walk, before: loaded)
        var event = F.pitch(isBall: true, outcome: "Walk", play: walk, basesBefore: loaded)
        XCTAssertEqual(rbi(event), 1)

        let hbp = BaseRunnerRules.awardedFirstPlay(credit: .hitByPitch, before: loaded)
        event = F.pitch(isBall: true, outcome: "HBP", play: hbp, basesBefore: loaded)
        XCTAssertEqual(rbi(event), 1)

        let open = BaseOccupancy(first: F.r1, third: F.r3)
        let openWalk = BaseRunnerRules.awardedFirstPlay(credit: .walk, before: open)
        event = F.pitch(isBall: true, outcome: "Walk", play: openWalk, basesBefore: open)
        XCTAssertEqual(rbi(event), 0, "the runner on 3rd wasn't forced")
    }

    /// Rule 37: a run on a groundout, sac fly or fielder's choice is an RBI.
    func testRunOnAnOutIsAnRBI() {
        let sacFly = pitch(.out, batterTo: Base.out, runners: [move(F.r3, from: 3, to: Base.scored)],
                           before: BaseOccupancy(third: F.r3))
        XCTAssertEqual(rbi(sacFly), 1)

        let fc = pitch(.fieldersChoice, batterTo: Base.first,
                       runners: [move(F.r1, from: 1, to: Base.out), move(F.r3, from: 3, to: Base.scored)],
                       before: BaseOccupancy(first: F.r1, third: F.r3))
        XCTAssertEqual(rbi(fc), 1)
    }

    /// Rule 38: no RBI for a run on an error, wild pitch or passed ball -
    /// reached on error drives in nobody, and a runner tagged E/WP/PB
    /// doesn't count.
    func testNoRBIForErrorsWildPitchesAndPassedBalls() {
        let roe = pitch(.reachedOnError, batterTo: Base.first, outcome: "1B",
                        runners: [move(F.r3, from: 3, to: Base.scored)], before: BaseOccupancy(third: F.r3))
        XCTAssertEqual(rbi(roe), 0)

        let tagged = pitch(.single, batterTo: Base.first,
                           runners: [move(F.r3, from: 3, to: Base.scored),
                                     move(F.r2, from: 2, to: Base.scored, on: .error)],
                           before: BaseOccupancy(second: F.r2, third: F.r3))
        XCTAssertEqual(rbi(tagged), 1, "only the clean run")

        let wildPitch = BaseRunnerRules.runnersOnlyPlay(before: BaseOccupancy(third: F.r3),
                                                         destinations: [3: Base.scored], reason: .wildPitch)
        let event = F.pitch(isBall: true, wildPitch: true, play: wildPitch, basesBefore: BaseOccupancy(third: F.r3))
        XCTAssertEqual(rbi(event), 0)

        let insideTheParkOnAnError = pitch(.single, batterTo: Base.scored, batterReason: .error)
        XCTAssertEqual(rbi(insideTheParkOnAnError), 0, "the batter scoring on an error isn't an RBI")
    }

    /// Rule 39: no RBI on a play that made two or more outs.
    func testNoRBIOnADoublePlay() {
        let doublePlay = pitch(.out, batterTo: Base.out,
                               runners: [move(F.r1, from: 1, to: Base.out), move(F.r3, from: 3, to: Base.scored)],
                               before: BaseOccupancy(first: F.r1, third: F.r3))
        XCTAssertEqual(rbi(doublePlay), 0)
    }

    /// Rule 40: running between pitches (a steal of home) is a run but no
    /// RBI; a pitch from before the runner system counts only a home run.
    func testStealOfHomeAndOldPitches() {
        var line = HittingStatLine()
        line.recordRunning([RunnerEvent(id: "s", timestamp: F.t0, kind: RunnerEventKind.stolenBase.rawValue,
                                        from: 3, to: Base.scored, runner: F.r3,
                                        basesBefore: BaseOccupancy(third: F.r3), hitterId: F.r3.hitterId)])
        XCTAssertEqual(line.runs, 1)
        XCTAssertEqual(line.runsBattedIn, 0)

        XCTAssertEqual(rbi(F.pitch(isStrike: true, outcome: "1B")), 0, "no play: who scored isn't known")
        XCTAssertEqual(rbi(F.pitch(isStrike: true, outcome: "HR")), 1, "an old home run drove in the batter")
    }

    /// Rule 41: the batter scores a run on their own home run, not on a single.
    func testBatterScoresOnAHomeRun() {
        let line = HittingStatLine(events: [pitch(.homeRun, batterTo: Base.scored),
                                            pitch(.single, batterTo: Base.first)])
        XCTAssertEqual(line.runs, 1)
    }

    /// Rule 42: a runner who scores on someone else's pitch gets the run -
    /// matched by their hitter id, each pitch once - and the batter's
    /// own moves on those pitches aren't counted again.
    func testRunnerScoresOnAnotherBattersPitch() {
        let single = pitch(.single, batterTo: Base.first,
                           runners: [move(F.r3, from: 3, to: Base.scored), move(F.r1, from: 1, to: Base.second)],
                           before: BaseOccupancy(first: F.r1, third: F.r3), hitterId: "hitter-9")
        let homer = pitch(.homeRun, batterTo: Base.scored, hitterId: "hitter-3")

        var line = HittingStatLine()
        line.recordRunsScored(onPitches: [single, single, homer], hitterIds: ["hitter-3"])
        XCTAssertEqual(line.runs, 1, "the single's run once; the homer is counted from their own pitches")

        var other = HittingStatLine()
        other.recordRunsScored(onPitches: [single], hitterIds: ["hitter-1"])
        XCTAssertEqual(other.runs, 0, "the runner who only reached 2nd")
    }

    /// Rule 43: a runner added by hand has no hitter, so their run goes to nobody.
    func testUnlinkedRunnerCreditsNobody() {
        let single = pitch(.single, batterTo: Base.first, runners: [move(F.unlinked, from: 3, to: Base.scored)],
                           before: BaseOccupancy(third: F.unlinked))
        var line = HittingStatLine()
        line.recordRunsScored(onPitches: [single], hitterIds: ["hitter-9", ""])
        XCTAssertEqual(line.runs, 0)
        XCTAssertEqual(HittingStatLine.runsBattedIn(for: single), 1, "the batter still gets the RBI")
    }
}
