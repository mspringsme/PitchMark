//
//  GameFeedTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-24 (clip brief phase 4, game feeds):
//  - HIGH RISK: a feed event never carries pitch calls, codes, keys or the
//    catcher's estimate; its fields are exactly the allowed list, and the
//    allowed list matches the rules. Broken on purpose to prove it.
//  - outcome text for each result
//  - names: first name, #jersey for a number-only player, full name only
//    with last names on
//  - "only my players" scope; merged timeline order; edits and undos make
//    the right writes and deletes
//  - 2026-11-24 (user): the batter's number, and the card's result lines
//    ("1B", "Line · Shallow Left") - still nothing about the call
//

import XCTest
@testable import PitchMark

final class GameFeedTests: XCTestCase {

    private func pitch(outcome: String? = nil, isBall: Bool = false, swinging: Bool = false,
                       balls: Int? = nil, strikes: Int? = nil, jersey: String? = "12",
                       hitterId: String? = nil) -> PitchEvent {
        var event = PitchEvent(
            id: "e1", timestamp: Date(timeIntervalSince1970: 1_800_000_000), pitch: "Rise", location: "Strike Up",
            codes: ["4", "1", "2"], isStrike: !isBall, isBall: isBall, mode: .game,
            calledPitch: PitchCall(pitch: "Rise", location: "Strike Up", isStrike: true, codes: ["412"]),
            batterSide: .right, templateId: "key-1", strikeSwinging: swinging, wildPitch: false, passedBall: false,
            strikeLooking: false, outcome: outcome, descriptor: nil, errorOnPlay: false,
            battedBallRegion: nil, battedBallType: nil, battedBallTapX: nil, battedBallTapY: nil,
            gameId: "g1", opponentJersey: jersey, opponentBatterId: nil, pitcherId: "p1"
        )
        event.atBatBalls = balls
        event.atBatStrikes = strikes
        event.hitterId = hitterId
        event.catcherEstimate = PitchCall(pitch: "Curve", location: "Ball In", isStrike: false, codes: [])
        return event
    }

    private func feedEvent(_ p: PitchEvent, name: String? = "Juju Smith", lastNames: Bool = false) -> GameFeedEvent {
        GameFeedRules.event(from: p, id: "e1", inning: 3, half: "top", batterName: name, showLastNames: lastNames)
    }

    // MARK: High risk - outcomes only

    func testAFeedEventCarriesOnlyTheAllowedFields() {
        let data = feedEvent(pitch(outcome: "1B")).firestoreData
        XCTAssertTrue(Set(data.keys).isSubset(of: GameFeedEvent.allowedKeys), "\(data.keys)")
        for forbidden in ["pitch", "location", "codes", "calledPitch", "templateId", "catcherEstimate", "mode", "pitcherId"] {
            XCTAssertNil(data[forbidden], forbidden)
            XCTAssertFalse(GameFeedEvent.allowedKeys.contains(forbidden), forbidden)
        }
        let text = data.values.map { "\($0)" }.joined(separator: " ")
        for secret in ["Rise", "Strike Up", "412", "key-1", "Curve", "Ball In"] {
            XCTAssertFalse(text.contains(secret), "\(secret) leaked into \(text)")
        }
    }

    func testTheAllowedFieldsMatchTheRules() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let rules = try String(contentsOf: root.appendingPathComponent("firestore.rules"), encoding: .utf8)
        let quoted = GameFeedEvent.allowedKeys.sorted().map { "\"\($0)\"" }
        let rulesLine = rules.components(separatedBy: "\n").first { line in
            line.contains("request.resource.data.keys().hasOnly([\"at\"")
        }
        let line = try XCTUnwrap(rulesLine, "the events rule lists its fields")
        for key in quoted { XCTAssertTrue(line.contains(key), "rules allow \(key)") }
        XCTAssertEqual(line.components(separatedBy: "\"").count / 2, quoted.count, "and no others")
    }

    // MARK: Outcome text

    func testOutcomeText() {
        XCTAssertEqual(GameFeedRules.outcome(of: pitch(isBall: true, balls: 2, strikes: 1)).text, "Ball 2-1")
        XCTAssertEqual(GameFeedRules.outcome(of: pitch(swinging: true, balls: 0, strikes: 1)).kind, "strike")
        XCTAssertEqual(GameFeedRules.outcome(of: pitch(outcome: "Foul", balls: 1, strikes: 2)).text, "Foul 1-2")
        XCTAssertEqual(GameFeedRules.outcome(of: pitch(outcome: "Walk", balls: 0, strikes: 0)).text, "Walk")
        XCTAssertEqual(GameFeedRules.outcome(of: pitch(outcome: "K", balls: 0, strikes: 0)).text, "Strikeout")
        XCTAssertEqual(GameFeedRules.outcome(of: pitch(outcome: "HBP", balls: 0, strikes: 0)).kind, "hbp")
        XCTAssertEqual(GameFeedRules.outcome(of: pitch(outcome: "1B", balls: 0, strikes: 0)).kind, "hit")
        XCTAssertEqual(GameFeedRules.outcome(of: pitch(outcome: "Out", balls: 0, strikes: 0)).text, "Out")
    }

    func testRunsAreCounted() {
        var p = pitch(outcome: "2B", balls: 0, strikes: 0)
        p.play = BasePlay(batterCredit: "2B", moves: [
            RunnerMove(runner: RunnerMove.batterKey, from: 0, to: 2),
            RunnerMove(runner: "r1", from: 1, to: Base.scored)
        ])
        let result = GameFeedRules.outcome(of: p)
        XCTAssertEqual(result.runs, 1)
        XCTAssertTrue(result.text.contains("1 run"), result.text)
    }

    // MARK: Number and card lines

    func testAHitCarriesTheNumberAndTheCardLines() {
        var p = pitch(outcome: "1B", balls: 0, strikes: 0, jersey: "26")
        p.battedBallType = "Line"
        p.descriptor = "Line"
        p.battedBallRegion = "Shallow Left"
        p.play = BasePlay(batterCredit: "1B", moves: [RunnerMove(runner: RunnerMove.batterKey, from: 0, to: 1)])
        let e = feedEvent(p, name: "Kenzie Smith", lastNames: true)
        XCTAssertEqual(e.jersey, "26")
        XCTAssertEqual(e.batterLabel, "Kenzie Smith #26")
        XCTAssertEqual(e.kindLabel, "Hit")
        XCTAssertEqual(e.detail.first, "1B")
        XCTAssertTrue(e.detail.contains("Line · Shallow Left"), "\(e.detail)")
        XCTAssertTrue(e.batterRan)
        XCTAssertTrue(e.showsPlayLines)
        XCTAssertLessThanOrEqual(e.detail.count, GameFeedRules.maxDetailLines)
        let data = e.firestoreData
        XCTAssertEqual(data["jersey"] as? String, "26")
        XCTAssertEqual(data["detail"] as? [String], e.detail)
    }

    func testANumberOnlyPlayerShowsTheNumberOnce() {
        let e = feedEvent(pitch(isBall: true, balls: 1, strikes: 0, jersey: "#7"), name: "#7")
        XCTAssertEqual(e.jersey, "7")
        XCTAssertEqual(e.batterLabel, "#7")
        XCTAssertFalse(e.showsPlayLines, "a ball shows its count")
        XCTAssertEqual(e.text, "Ball 1-0")
    }

    // MARK: Batting team, score, outs

    func testEachPlayCarriesTheBoardAfterIt() {
        let situation = GameFeedRules.Situation(inning: 3, batting: "Hawks", ourScore: 3, theirScore: 2, outs: 2)
        let e = GameFeedRules.event(from: pitch(outcome: "Out", balls: 0, strikes: 0), id: "e1", situation: situation,
                                    batterName: "Juju", showLastNames: false)
        XCTAssertEqual(e.situationLine(ourName: "Reds", theirName: "Hawks"), "Hawks Batting · 2 outs · Reds 3 – Hawks 2")
        XCTAssertEqual(e.outsLabel, "2 Outs")
        var one = e; one.outs = 1
        XCTAssertEqual(one.outsLabel, "1 Out")
        XCTAssertEqual(e.firestoreData["outs"] as? Int, 2)
        XCTAssertEqual(e.firestoreData["batting"] as? String, "Hawks")
        XCTAssertTrue(Set(e.firestoreData.keys).isSubset(of: GameFeedEvent.allowedKeys))
    }

    private typealias Seen = (id: String, situation: GameFeedRules.Situation, outsMade: Int, runs: Int)

    private func board(_ inning: Int = 1, _ batting: String = "Hawks", outs: Int, us: Int = 0, them: Int = 0) -> GameFeedRules.Situation {
        GameFeedRules.Situation(inning: inning, batting: batting, ourScore: us, theirScore: them, outs: outs)
    }

    func testAnOutShowsOnlyOnThePitchThatMadeIt() {
        // The user's report: Smith's strike (1 out) then his bunt out. The
        // board says 2 outs by the time the bunt arrives - the strike keeps 1.
        let seen: [Seen] = [
            ("strike", board(outs: 1), 0, 0),
            ("bunt", board(outs: 2), 1, 0)
        ]
        let boards = GameFeedRules.boards(seen, ourName: "Reds")
        XCTAssertEqual(boards["strike"]?.outs, 1)
        XCTAssertEqual(boards["bunt"]?.outs, 2)
    }

    func testABoardThatLagsThePitchIsCorrected() {
        // Seen before the board moved: still counts the pitch's own out and runs.
        let seen: [Seen] = [
            ("ball", board(outs: 1, them: 2), 0, 0),
            ("double", board(outs: 1, them: 2), 0, 1),
            ("flyout", board(outs: 1, them: 3), 1, 0)
        ]
        let boards = GameFeedRules.boards(seen, ourName: "Reds")
        XCTAssertEqual(boards["double"]?.theirScore, 3, "the run on the double")
        XCTAssertEqual(boards["flyout"]?.outs, 2)
        XCTAssertEqual(boards["ball"]?.outs, 1)
    }

    func testAThirdOutStaysThreeAndANewHalfStartsOver() {
        let seen: [Seen] = [
            ("k", board(outs: 3), 1, 0),
            ("next", board(1, "Reds", outs: 0), 0, 0)
        ]
        let boards = GameFeedRules.boards(seen, ourName: "Reds")
        XCTAssertEqual(boards["k"]?.outs, 3)
        XCTAssertEqual(boards["next"]?.outs, 0, "a new half isn't floored by the last one")
        let capped = GameFeedRules.boards([("a", board(outs: 3), 0, 0), ("b", board(outs: 3), 1, 0)], ourName: "Reds")
        XCTAssertEqual(capped["b"]?.outs, 3, "never past 3")
    }

    func testOutsMadeByAPitch() {
        XCTAssertEqual(GameFeedRules.outsMade(by: pitch(outcome: "K", balls: 0, strikes: 0)), 1)
        XCTAssertEqual(GameFeedRules.outsMade(by: pitch(outcome: "Out", balls: 0, strikes: 0)), 1)
        XCTAssertEqual(GameFeedRules.outsMade(by: pitch(swinging: true, balls: 0, strikes: 1)), 0)
        var dp = pitch(outcome: "Out", balls: 0, strikes: 0)
        dp.play = BasePlay(batterCredit: "OUT", moves: [
            RunnerMove(runner: RunnerMove.batterKey, from: 0, to: Base.out),
            RunnerMove(runner: "r1", from: 1, to: Base.out)
        ])
        XCTAssertEqual(GameFeedRules.outsMade(by: dp), 2, "a double play")
    }

    func testANumberOnlyNameShowsTheNumberOnce() {
        var e = feedEvent(pitch(isBall: true, jersey: "23"), name: "23")
        e.batter = "23"
        XCTAssertEqual(e.batterLabel, "#23")
    }

    // MARK: Names

    func testNames() {
        XCTAssertEqual(GameFeedRules.displayName("Juju Smith", jersey: "12", showLastNames: false), "Juju")
        XCTAssertEqual(GameFeedRules.displayName("Juju Smith", jersey: "12", showLastNames: true), "Juju Smith")
        XCTAssertEqual(GameFeedRules.displayName("#12", jersey: "12", showLastNames: false), "#12", "number-only player")
        XCTAssertEqual(GameFeedRules.displayName(nil, jersey: "7", showLastNames: false), "#7")
        XCTAssertEqual(GameFeedRules.displayName(" ", jersey: nil, showLastNames: true), "Batter")
        XCTAssertEqual(feedEvent(pitch(isBall: true)).batter, "Juju")
    }

    // MARK: Scope, order, diff

    func testOnlyMyPlayers() {
        let mine = pitch(hitterId: "h1"), theirs = pitch(hitterId: "h2"), unlinked = pitch()
        XCTAssertTrue(GameFeedRules.shares(theirs, scope: .everything, myHitterIds: ["h1"]))
        XCTAssertTrue(GameFeedRules.shares(mine, scope: .myPlayers, myHitterIds: ["h1"]))
        XCTAssertFalse(GameFeedRules.shares(theirs, scope: .myPlayers, myHitterIds: ["h1"]))
        XCTAssertFalse(GameFeedRules.shares(unlinked, scope: .myPlayers, myHitterIds: ["h1"]))
    }

    private func event(_ id: String, at seconds: TimeInterval, text: String = "Ball") -> GameFeedEvent {
        GameFeedEvent(id: id, at: Date(timeIntervalSince1970: seconds), inning: 1, half: nil,
                      batter: "Juju", kind: "ball", text: text, runs: 0)
    }

    func testMergedTimelineIsByWhenItHappened() {
        let merged = GameFeedRules.merged([
            (title: "Coach", events: [event("b", at: 20), event("a", at: 10)]),
            (title: "Mrs. Jones", events: [event("c", at: 15), event("a2", at: 20)])
        ])
        XCTAssertEqual(merged.map(\.event.id), ["a", "c", "a2", "b"], "time first, then id on a tie")
        XCTAssertEqual(merged.map(\.feedTitle), ["Coach", "Mrs. Jones", "Mrs. Jones", "Coach"])
    }

    func testEditsAndUndosMakeTheRightWrites() {
        let current = ["a": event("a", at: 1), "b": event("b", at: 2), "gone": event("gone", at: 3)]
        let wanted = [event("a", at: 1), event("b", at: 2, text: "Strike"), event("new", at: 4)]
        let diff = GameFeedRules.diff(current: current, wanted: wanted)
        XCTAssertEqual(diff.write.map(\.id), ["b", "new"], "the edit and the new pitch; unchanged ones aren't rewritten")
        XCTAssertEqual(diff.delete, ["gone"], "the undone pitch")
    }
}
