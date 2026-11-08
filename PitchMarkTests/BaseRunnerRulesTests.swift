//
//  BaseRunnerRulesTests.swift
//  PitchMarkTests
//
//  The rules in BaseRunnerRules.swift, ported from the standalone assertion
//  script they were first verified with (109 checks). Expected values are
//  scorebook rules - a single + error is still a single, a walk forces only
//  runners who have to move, and so on.
//

import XCTest
@testable import PitchMark

private let a = BaseRunner(id: "a", label: "#1")
private let b = BaseRunner(id: "b", label: "#2")
private let c = BaseRunner(id: "c", label: "#3")
private let bat = BaseRunner(id: "bat", label: "#9")
private let loaded = BaseOccupancy(first: a, second: b, third: c)
private let onFirst = BaseOccupancy(first: a)
private let firstAndThird = BaseOccupancy(first: a, third: c)
private let onSecond = BaseOccupancy(second: b)

private func ev(_ kind: RunnerEventKind, from: Int, before: BaseOccupancy, sub: BaseRunner? = nil) -> RunnerEvent {
    RunnerEvent(id: "x", timestamp: Date(timeIntervalSince1970: 0), kind: kind.rawValue, from: from,
                to: BaseRunnerRules.destination(for: kind, from: from),
                runner: sub ?? before[from]!, replaced: sub == nil ? nil : before[from], basesBefore: before)
}

@MainActor
final class BaseRunnerRulesTests: XCTestCase {
    private func check(_ condition: Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(condition, message, file: file, line: line)
    }

    /// Phase 1: the batter's credit vs the base they reached.
    func testBatterCreditAndBaseReached() throws {

        // Credit options
        check(BaseRunnerRules.creditOptions(reached: 1) == [.single, .reachedOnError], "1st options")
        check(BaseRunnerRules.creditOptions(reached: 2) == [.single, .double, .reachedOnError], "2nd options")
        check(BaseRunnerRules.creditOptions(reached: 3) == [.single, .double, .triple, .reachedOnError], "3rd options")
        check(BaseRunnerRules.creditOptions(reached: 4) == [.single, .double, .triple, .homeRun, .reachedOnError], "home options")

        // Defaults = clean hit
        check(BaseRunnerRules.defaultCredit(reached: 1) == .single, "default 1")
        check(BaseRunnerRules.defaultCredit(reached: 2) == .double, "default 2")
        check(BaseRunnerRules.defaultCredit(reached: 3) == .triple, "default 3")
        check(BaseRunnerRules.defaultCredit(reached: 4) == .homeRun, "default 4")

        // Extra-bases question only when hit < reached
        check(!BaseRunnerRules.needsExtraBasesReason(credit: .double, reached: 2), "clean double no q")
        check(BaseRunnerRules.needsExtraBasesReason(credit: .single, reached: 2), "1B to 2nd needs q")
        check(!BaseRunnerRules.needsExtraBasesReason(credit: .reachedOnError, reached: 2), "ROE no q")
        check(BaseRunnerRules.needsExtraBasesReason(credit: .triple, reached: 4), "3B scoring needs q")

        // Completeness
        check(BaseRunnerRules.isComplete(credit: .double, reached: 2, extraBasesOn: nil), "clean double complete")
        check(!BaseRunnerRules.isComplete(credit: .single, reached: 2, extraBasesOn: nil), "1B to 2nd incomplete w/o reason")
        check(BaseRunnerRules.isComplete(credit: .single, reached: 2, extraBasesOn: .error), "1B+E complete")
        check(!BaseRunnerRules.isComplete(credit: .triple, reached: 2, extraBasesOn: nil), "triple at 2nd invalid")
        check(!BaseRunnerRules.isComplete(credit: .homeRun, reached: 3, extraBasesOn: nil), "HR at 3rd invalid")

        // The user's example: double vs single + error
        let cleanDouble = BaseRunnerRules.makePlay(credit: .double, reached: 2, extraBasesOn: nil)
        let singlePlusE = BaseRunnerRules.makePlay(credit: .single, reached: 2, extraBasesOn: .error)
        let singlePlusThrow = BaseRunnerRules.makePlay(credit: .single, reached: 2, extraBasesOn: .onThrow)
        let roe = BaseRunnerRules.makePlay(credit: .reachedOnError, reached: 1, extraBasesOn: nil)

        check(BaseRunnerRules.outcome(for: .double) == "2B", "double outcome")
        check(BaseRunnerRules.outcome(for: .single) == "1B", "single outcome")
        check(BaseRunnerRules.outcome(for: .reachedOnError) == "1B", "ROE legacy outcome")

        check(!BaseRunnerRules.errorOnPlay(credit: .double, extraBasesOn: nil), "clean double no error")
        check(BaseRunnerRules.errorOnPlay(credit: .single, extraBasesOn: .error), "1B+E error flag")
        check(!BaseRunnerRules.errorOnPlay(credit: .single, extraBasesOn: .onThrow), "1B+throw no error")
        check(BaseRunnerRules.errorOnPlay(credit: .reachedOnError, extraBasesOn: nil), "ROE error flag")

        // Stats: single + E stays a hit; ROE does not; legacy error stays ROE
        check(!BaseRunnerRules.isReachedOnError(errorOnPlay: true, play: singlePlusE), "1B+E is a hit")
        check(BaseRunnerRules.isReachedOnError(errorOnPlay: true, play: roe), "ROE is ROE")
        check(BaseRunnerRules.isReachedOnError(errorOnPlay: true, play: nil), "legacy error = ROE")
        check(!BaseRunnerRules.isReachedOnError(errorOnPlay: false, play: nil), "no error no ROE")
        check(!BaseRunnerRules.isReachedOnError(errorOnPlay: false, play: cleanDouble), "clean double not ROE")

        // Reason is dropped when not needed
        let stray = BaseRunnerRules.makePlay(credit: .double, reached: 2, extraBasesOn: .error)
        check(stray.batterMove?.extraBasesOn == nil, "unneeded reason dropped")
        check(singlePlusE.batterMove?.extraBasesOn == "E", "reason kept")
        check(singlePlusE.batterMove?.to == 2 && singlePlusE.batterMove?.from == 0, "batter move")

        // Summaries
        check(BaseRunnerRules.summary(for: cleanDouble) == "Safe at 2nd — 2B", "summary double: \(BaseRunnerRules.summary(for: cleanDouble) ?? "nil")")
        check(BaseRunnerRules.summary(for: singlePlusE) == "Safe at 2nd — 1B + E", "summary 1B+E")
        check(BaseRunnerRules.summary(for: singlePlusThrow) == "Safe at 2nd — 1B + throw", "summary throw")
        check(BaseRunnerRules.summary(for: roe) == "Safe at 1st — Reached on error", "summary ROE")
        check(BaseRunnerRules.summary(for: BaseRunnerRules.makePlay(credit: .homeRun, reached: 4, extraBasesOn: nil)) == "Home run", "summary HR")

        // Codable round trip (what Firestore sees)
        let data = try JSONEncoder().encode(singlePlusE)
        let back = try JSONDecoder().decode(BasePlay.self, from: data)
        check(back == singlePlusE, "codable round trip")

        // Consistency guard used by every PitchEvent rebuild site
        check(BaseRunnerRules.playIfConsistent(singlePlusE, outcome: "1B", errorOnPlay: true) == singlePlusE, "consistent kept")
        check(BaseRunnerRules.playIfConsistent(singlePlusE, outcome: "Out", errorOnPlay: true) == nil, "edited to out drops")
        check(BaseRunnerRules.playIfConsistent(singlePlusE, outcome: "1B", errorOnPlay: false) == nil, "error untoggled drops")
        check(BaseRunnerRules.playIfConsistent(cleanDouble, outcome: " 2b ", errorOnPlay: false) == cleanDouble, "case/space tolerant")
        check(BaseRunnerRules.playIfConsistent(roe, outcome: "1B", errorOnPlay: true) == roe, "ROE kept")
        check(BaseRunnerRules.playIfConsistent(nil, outcome: "1B", errorOnPlay: false) == nil, "nil stays nil")
    }

    /// Phase 2: runners already on base on a ball in play, walk or HBP.
    func testRunnersOnBallsInPlayAndWalks() throws {
        check(BaseRunnerRules.creditOptions(reached: 1, runnersOn: true) == [.single, .fieldersChoice, .reachedOnError], "FC offered with runners")

        // Defaults
        check(BaseRunnerRules.defaultDestinations(before: onFirst, batterTo: 1) == [1: 2], "single pushes R1 to 2nd")
        check(BaseRunnerRules.defaultDestinations(before: onFirst, batterTo: 2) == [1: 3], "double pushes R1 to 3rd")
        check(BaseRunnerRules.defaultDestinations(before: onSecond, batterTo: 1) == [2: 2], "single leaves R2")
        check(BaseRunnerRules.defaultDestinations(before: firstAndThird, batterTo: 1) == [1: 2, 3: 3], "walk 1st+3rd: R3 not forced")
        check(BaseRunnerRules.defaultDestinations(before: loaded, batterTo: 1) == [1: 2, 2: 3, 3: 4], "walk loaded forces run")
        check(BaseRunnerRules.defaultDestinations(before: loaded, batterTo: 4) == [1: 4, 2: 4, 3: 4], "grand slam")
        check(BaseRunnerRules.defaultDestinations(before: loaded, batterTo: nil) == [1: 1, 2: 2, 3: 3], "batter out: nobody moves")
        check(BaseRunnerRules.defaultDestinations(before: loaded, batterTo: Base.out) == [1: 1, 2: 2, 3: 3], "batter out (-1): nobody moves")

        // Walk with bases loaded: run scores, bases stay loaded with batter on 1st
        let walkLoaded = BaseRunnerRules.awardedFirstPlay(credit: .walk, before: loaded)
        let rWalk = BaseRunnerRules.resolve(walkLoaded, before: loaded, batter: bat)
        check(rWalk.runs == 1 && rWalk.outs == 0, "walk loaded: 1 run")
        check(rWalk.after == BaseOccupancy(first: bat, second: a, third: b), "walk loaded: after")
        check(BaseRunnerRules.outcome(for: .walk) == "Walk", "walk outcome")
        check(BaseRunnerRules.playIfConsistent(walkLoaded, outcome: "Walk", errorOnPlay: false) == walkLoaded, "walk play consistent")
        check(BaseRunnerRules.summary(for: walkLoaded) == "Walk · 1 run", "walk summary: \(BaseRunnerRules.summary(for: walkLoaded) ?? "nil")")

        // Walk, empty bases: batter to 1st
        let walkEmpty = BaseRunnerRules.awardedFirstPlay(credit: .walk, before: .empty)
        check(BaseRunnerRules.resolve(walkEmpty, before: .empty, batter: bat).after == BaseOccupancy(first: bat), "walk empty")

        // HBP
        let hbp = BaseRunnerRules.awardedFirstPlay(credit: .hitByPitch, before: onFirst)
        check(BaseRunnerRules.resolve(hbp, before: onFirst, batter: bat).after == BaseOccupancy(first: bat, second: a), "HBP forces")
        check(BaseRunnerRules.playIfConsistent(hbp, outcome: "HBP", errorOnPlay: false) == hbp, "HBP consistent")

        // Single, R2 scores (user moved them)
        let singleScore = BaseRunnerRules.makePlay(credit: .single, reached: 1, extraBasesOn: nil,
            runnerMoves: [RunnerMove(runner: "b", from: 2, to: 4, extraBasesOn: nil)])
        let rSingle = BaseRunnerRules.resolve(singleScore, before: onSecond, batter: bat)
        check(rSingle.runs == 1 && rSingle.after == BaseOccupancy(first: bat), "RBI single")
        check(BaseRunnerRules.summary(for: singleScore) == "Safe at 1st — 1B · 1 run", "RBI single summary")

        // Fielder's choice: R1 out at 2nd, batter safe at 1st
        let fc = BaseRunnerRules.makePlay(credit: .fieldersChoice, reached: 1, extraBasesOn: nil,
            runnerMoves: [RunnerMove(runner: "a", from: 1, to: Base.out, extraBasesOn: nil)])
        let rFC = BaseRunnerRules.resolve(fc, before: onFirst, batter: bat)
        check(rFC.outs == 1 && rFC.runs == 0 && rFC.after == BaseOccupancy(first: bat), "FC")
        check(BaseRunnerRules.outcome(for: .fieldersChoice) == "Out", "FC legacy outcome")
        check(BaseRunnerRules.playIfConsistent(fc, outcome: "Out", errorOnPlay: false) == fc, "FC consistent with Out")
        check(!BaseRunnerRules.isReachedOnError(errorOnPlay: false, play: fc), "FC not ROE")
        check(BaseRunnerRules.summary(for: fc) == "Safe at 1st — Fielder's choice · runner out", "FC summary")
        check(fc.outs == 1, "FC outs")
        check(BaseRunnerRules.isComplete(credit: .fieldersChoice, reached: 1, extraBasesOn: nil), "FC complete")

        // Double play: batter out, R1 out
        let dp = BaseRunnerRules.makePlay(credit: .out, reached: Base.out, extraBasesOn: nil,
            runnerMoves: [RunnerMove(runner: "a", from: 1, to: Base.out, extraBasesOn: nil)])
        let rDP = BaseRunnerRules.resolve(dp, before: onFirst, batter: bat)
        check(rDP.outs == 2 && rDP.after == .empty, "double play")
        check(dp.outs == 2, "DP play.outs")
        check(BaseRunnerRules.playIfConsistent(dp, outcome: "Out", errorOnPlay: false) == dp, "DP consistent")

        // Sac fly: batter out, R3 scores
        let sac = BaseRunnerRules.makePlay(credit: .out, reached: Base.out, extraBasesOn: nil,
            runnerMoves: [RunnerMove(runner: "c", from: 3, to: 4, extraBasesOn: nil)])
        let rSac = BaseRunnerRules.resolve(sac, before: firstAndThird, batter: bat)
        check(rSac.outs == 1 && rSac.runs == 1 && rSac.after == BaseOccupancy(first: a), "sac fly, R1 holds")
        check(BaseRunnerRules.summary(for: sac) == "Out · 1 run", "sac summary")

        // Grand slam
        let slamMoves = BaseRunnerRules.runnerMoves(before: loaded, destinations: BaseRunnerRules.defaultDestinations(before: loaded, batterTo: 4))
        let slam = BaseRunnerRules.makePlay(credit: .homeRun, reached: 4, extraBasesOn: nil, runnerMoves: slamMoves)
        let rSlam = BaseRunnerRules.resolve(slam, before: loaded, batter: bat)
        check(rSlam.runs == 4 && rSlam.after == .empty, "grand slam runs")
        check(BaseRunnerRules.summary(for: slam) == "Home run · 4 runs", "slam summary: \(BaseRunnerRules.summary(for: slam) ?? "nil")")

        // runnerMoves omits stays
        check(BaseRunnerRules.runnerMoves(before: firstAndThird, destinations: [1: 2, 3: 3]) == [RunnerMove(runner: "a", from: 1, to: 2, extraBasesOn: nil)], "stays omitted")

        // Conflicts
        check(BaseRunnerRules.conflict([(0, 1), (1, 2)]) == nil, "single + R1 to 2nd ok")
        check(BaseRunnerRules.conflict([(0, 1), (1, 1)]) != nil, "two on 1st")
        check(BaseRunnerRules.conflict([(0, 1), (1, 3), (2, 2)]) != nil, "R1 passes R2")
        check(BaseRunnerRules.conflict([(0, 4), (1, 4), (2, 4), (3, 4)]) == nil, "everyone scores ok")
        check(BaseRunnerRules.conflict([(0, 1), (2, 1)]) != nil, "runner backwards")
        check(BaseRunnerRules.conflict([(0, Base.out), (1, Base.out), (2, 2)]) == nil, "outs ignored")
        check(BaseRunnerRules.conflict([(0, 2), (1, Base.out)]) == nil, "R1 out, batter to 2nd ok")
        check(BaseRunnerRules.conflict([(0, 3), (2, 2)]) != nil, "batter passes R2")

        // Codable round trip of occupancy (live room / snapshot)
        let occData = try JSONEncoder().encode(loaded)
        check(try JSONDecoder().decode(BaseOccupancy.self, from: occData) == loaded, "occupancy round trip")
        check(try JSONDecoder().decode(BaseOccupancy.self, from: "{}".data(using: .utf8)!) == .empty, "empty map decodes")
    }

    /// Phase 3: between-pitch runner events and WP/PB advances.
    func testRunnerEventsAndWildPitches() throws {
        let sb = BaseRunnerRules.apply(ev(.stolenBase, from: 1, before: onFirst))
        check(sb.after == BaseOccupancy(second: a) && sb.runs == 0 && sb.outs == 0, "steal 2nd")
        let sbHome = BaseRunnerRules.apply(ev(.stolenBase, from: 3, before: firstAndThird))
        check(sbHome.after == BaseOccupancy(first: a) && sbHome.runs == 1, "steal home")
        let cs = BaseRunnerRules.apply(ev(.caughtStealing, from: 1, before: firstAndThird))
        check(cs.after == BaseOccupancy(third: c) && cs.outs == 1, "caught stealing")
        let po = BaseRunnerRules.apply(ev(.pickedOff, from: 3, before: firstAndThird))
        check(po.after == BaseOccupancy(first: a) && po.outs == 1, "picked off")
        let pinch = BaseRunner(id: "p", label: "#22", hitterId: "h22")
        let sub = BaseRunnerRules.apply(ev(.substitution, from: 1, before: onFirst, sub: pinch))
        check(sub.after == BaseOccupancy(first: pinch) && sub.runs == 0 && sub.outs == 0, "pinch runner")
        check(ev(.substitution, from: 1, before: onFirst, sub: pinch).summary == "#22 runs for #1 at 1st", "sub summary")
        check(ev(.stolenBase, from: 3, before: firstAndThird).summary == "#3 steals home", "steal home summary")

        check(BaseRunnerRules.isAllowed(.stolenBase, from: 1, bases: onFirst), "can steal 2nd")
        check(!BaseRunnerRules.isAllowed(.stolenBase, from: 1, bases: loaded), "can't steal occupied 2nd")
        check(BaseRunnerRules.isAllowed(.stolenBase, from: 3, bases: loaded), "can steal home")
        check(!BaseRunnerRules.isAllowed(.caughtStealing, from: 2, bases: onFirst), "no runner, no event")

        // WP: runner on 2nd to 3rd, runner on 3rd scores
        let wp = BaseRunnerRules.runnersOnlyPlay(before: BaseOccupancy(second: b, third: c), destinations: [2: 3, 3: 4], reason: .wildPitch)!
        check(wp.isRunnersOnly && wp.runs == 1 && wp.outs == 0, "WP play")
        let rWP = BaseRunnerRules.resolve(wp, before: BaseOccupancy(second: b, third: c), batter: bat)
        check(rWP.after == BaseOccupancy(third: b) && rWP.runs == 1, "WP resolve leaves batter off")
        check(BaseRunnerRules.summary(for: wp) == "Wild pitch · 1 run", "WP summary: \(BaseRunnerRules.summary(for: wp) ?? "nil")")
        check(BaseRunnerRules.playIfConsistent(wp, outcome: nil, errorOnPlay: false) == wp, "WP kept on a plain ball")
        check(BaseRunnerRules.playIfConsistent(wp, outcome: "K", errorOnPlay: false) == wp, "WP kept on a strikeout")
        check(BaseRunnerRules.runnersOnlyPlay(before: onFirst, destinations: [:], reason: .passedBall) == nil, "no moves, no play")

        // Ball four on a wild pitch: runner on 2nd takes 3rd on the WP (not forced), batter to 1st
        let wp2 = BaseRunnerRules.runnersOnlyPlay(before: onSecond, destinations: [2: 3], reason: .wildPitch)!
        let walkWP = BaseRunnerRules.awardedFirstPlay(credit: .walk, before: onSecond, existing: wp2)
        check(BaseRunnerRules.resolve(walkWP, before: onSecond, batter: bat).after == BaseOccupancy(first: bat, third: b), "walk + WP keeps WP advance")
        // Ball four with R1 who the WP play left at 1st: force still pushes them
        let walkForce = BaseRunnerRules.awardedFirstPlay(credit: .walk, before: onFirst, existing: nil)
        check(BaseRunnerRules.resolve(walkForce, before: onFirst, batter: bat).after == BaseOccupancy(first: bat, second: a), "walk forces")

        // RunnerEvent round trip + BaseRunner without hitterId decodes
        let evData = try JSONEncoder().encode(ev(.substitution, from: 1, before: onFirst, sub: pinch))
        check((try? JSONDecoder().decode(RunnerEvent.self, from: evData)) != nil, "runner event round trip")
        check(try JSONDecoder().decode(BaseRunner.self, from: ##"{"id":"a","label":"#1"}"##.data(using: .utf8)!) == a, "legacy runner decodes")
    }
}
