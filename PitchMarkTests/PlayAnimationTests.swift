//
//  PlayAnimationTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-25 (play animation in the feed card):
//  - a pitch's hit location, ball type and runner moves reach the feed;
//    a foul or no tap carries no location
//  - runners follow the base paths corner to corner; an out stops partway;
//    a scored runner ends at home
//  - the ball starts at home, ends on the tapped spot, and is back on the
//    ground at the end
//  - a walk with no saved play still sends the batter to 1st; balls,
//    strikes and fouls don't animate
//  (The allowed fields still matching the rules is GameFeedTests'
//  testTheAllowedFieldsMatchTheRules.)
//

import XCTest
@testable import PitchMark

final class PlayAnimationTests: XCTestCase {

    private func pitch(outcome: String? = "1B", descriptor: String? = "Line, Hit", type: String? = "Field",
                       tap: (Double, Double)? = (0.5, 0.36), moves: [RunnerMove] = []) -> PitchEvent {
        var event = PitchEvent(
            id: "e1", timestamp: Date(), pitch: "Rise", location: "Strike Up", codes: [],
            isStrike: true, isBall: false, mode: .game, calledPitch: nil, batterSide: .right,
            templateId: nil, strikeSwinging: false, wildPitch: false, passedBall: false,
            strikeLooking: false, outcome: outcome, descriptor: descriptor, errorOnPlay: false,
            battedBallRegion: "Shallow Center", battedBallType: type,
            battedBallTapX: tap?.0, battedBallTapY: tap?.1,
            gameId: "g1", opponentJersey: "26", opponentBatterId: nil, pitcherId: "p1"
        )
        event.atBatBalls = 0
        event.atBatStrikes = 0
        if !moves.isEmpty { event.play = BasePlay(batterCredit: "1B", moves: moves) }
        return event
    }

    private func feedEvent(_ p: PitchEvent) -> GameFeedEvent {
        GameFeedRules.event(from: p, id: "e1", inning: 1, half: nil, batterName: "Smith", showLastNames: false)
    }

    // MARK: Data reaches the feed

    func testHitLocationTypeAndMovesReachTheFeed() {
        let e = feedEvent(pitch(moves: [RunnerMove(runner: RunnerMove.batterKey, from: 0, to: 1),
                                        RunnerMove(runner: "r2", from: 2, to: Base.scored)]))
        XCTAssertEqual(e.spotX, 0.5)
        XCTAssertEqual(e.spotY, 0.36)
        XCTAssertEqual(e.ballType, "line")
        XCTAssertEqual(e.moves, [FeedMove(from: 0, to: 1), FeedMove(from: 2, to: 4)])
        let data = e.firestoreData
        XCTAssertEqual(data["ballType"] as? String, "line")
        XCTAssertEqual((data["moves"] as? [[String: Int]])?.count, 2)
        XCTAssertTrue(Set(data.keys).isSubset(of: GameFeedEvent.allowedKeys))
    }

    func testAFoulOrNoTapHasNoLocation() {
        XCTAssertNil(feedEvent(pitch(outcome: "Foul", type: "Foul")).spotX)
        XCTAssertNil(feedEvent(pitch(tap: nil)).spotX)
    }

    func testAHomeRunIsHrAndLocationsAreRounded() {
        let e = feedEvent(pitch(outcome: "HR", descriptor: "Fly, Hit", type: "HR", tap: (0.123456, 1.4)))
        XCTAssertEqual(e.ballType, "hr")
        XCTAssertEqual(e.spotX, 0.123)
        XCTAssertEqual(e.spotY, 1.0, "kept on the picture")
    }

    func testMovesFromTheFeedAreChecked() {
        XCTAssertNotNil(FeedMove(data: ["f": 1, "t": 4]))
        XCTAssertNil(FeedMove(data: ["f": 5, "t": 1]), "no such base")
        XCTAssertNil(FeedMove(data: ["f": 1, "t": 9]))
    }

    // MARK: Runners

    private func event(kind: String, spot: (Double, Double)? = nil, type: String? = nil, moves: [FeedMove] = []) -> GameFeedEvent {
        GameFeedEvent(id: "x", at: Date(), inning: 1, half: nil, batter: "Smith", kind: kind, text: "",
                      runs: 0, spotX: spot?.0, spotY: spot?.1, ballType: type, moves: moves)
    }

    func testRunnersFollowTheBasePaths() {
        let route = PlayAnimationPlan.waypoints(from: Base.first, to: Base.scored)
        XCTAssertEqual(route, [PlayAnimationPlan.point(1), PlayAnimationPlan.point(2),
                               PlayAnimationPlan.point(3), PlayAnimationPlan.point(Base.home)],
                       "1st to home goes by 2nd and 3rd, never across the diamond")
        XCTAssertEqual(PlayAnimationPlan.waypoints(from: Base.second, to: Base.second), [PlayAnimationPlan.point(2)], "stays")
    }

    func testAnOutStopsPartwayAndAScoreEndsAtHome() {
        let plan = PlayAnimationPlan.make(for: event(kind: "hit", spot: (0.5, 0.36), type: "line",
                                                     moves: [FeedMove(from: 0, to: -1), FeedMove(from: 2, to: 4)]))!
        let out = plan.runners.first { $0.isOut }!
        let end = plan.runnerPosition(out, at: plan.duration)
        let home = PlayAnimationPlan.home, first = PlayAnimationPlan.point(1)
        XCTAssertGreaterThan(end.x, home.x, "left home")
        XCTAssertLessThan(end.x, first.x, "but not all the way to 1st")
        let scorer = plan.runners.first { $0.scored }!
        XCTAssertEqual(plan.runnerPosition(scorer, at: plan.duration), home)
        XCTAssertEqual(plan.runnerPosition(scorer, at: 0), PlayAnimationPlan.point(2), "waits on 2nd until the runners go")
    }

    func testEveryRunnerRunsAtTheSameSpeedAndNobodyCatchesUp() {
        // A homer with a runner on 3rd: the batter goes four bases, the
        // runner one. Same time per base, so the batter takes four times
        // as long and never reaches the runner ahead.
        let plan = PlayAnimationPlan.make(for: event(kind: "hit", spot: (0.2, 0.1), type: "hr",
                                                     moves: [FeedMove(from: 0, to: 4), FeedMove(from: 3, to: 4)]))!
        let batter = plan.runners.first { $0.isBatter }!, runner = plan.runners.first { !$0.isBatter }!
        XCTAssertEqual(PlayAnimationPlan.runTime(batter), 4 * PlayAnimationPlan.runTime(runner), accuracy: 0.05)
        XCTAssertEqual(PlayAnimationPlan.bases(runner), 1, accuracy: 0.05)
        // Halfway through the runner's trip, the batter has gone about a
        // quarter of his - the same distance.
        let t = plan.runnersStart + PlayAnimationPlan.runTime(runner) / 2
        let runnerGone = PlayAnimationPlan.runFraction(t - plan.runnersStart, total: PlayAnimationPlan.runTime(runner)) * 1
        let batterGone = PlayAnimationPlan.runFraction(t - plan.runnersStart, total: PlayAnimationPlan.runTime(batter)) * 4
        XCTAssertGreaterThanOrEqual(runnerGone, batterGone - 0.001, "the runner ahead stays ahead")
    }

    func testARunStartsAndEndsSlowly() {
        let total = 1.5
        let early = PlayAnimationPlan.runFraction(0.1, total: total)
        let middle = PlayAnimationPlan.runFraction(0.8, total: total) - PlayAnimationPlan.runFraction(0.7, total: total)
        let late = 1 - PlayAnimationPlan.runFraction(total - 0.1, total: total)
        XCTAssertLessThan(early, middle, "slow out of the base")
        XCTAssertLessThan(late, middle, "slow into the base")
        XCTAssertEqual(PlayAnimationPlan.runFraction(total, total: total), 1, accuracy: 0.0001)
    }

    // MARK: Ball

    func testTheBallGoesFromHomeToTheSpotAndLands() {
        for type in ["line", "fly", "grounder", "pop", "bunt", "hr"] {
            let plan = PlayAnimationPlan.make(for: event(kind: "hit", spot: (0.7, 0.3), type: type))!
            let start = plan.ballState(at: 0)!, end = plan.ballState(at: plan.ball!.duration)!
            XCTAssertEqual(start.ground, PlayAnimationPlan.home, type)
            XCTAssertEqual(end.ground.x, 0.7, accuracy: 0.0001, type)
            XCTAssertEqual(end.ground.y, 0.3, accuracy: 0.0001, type)
            XCTAssertEqual(end.lift, 0, accuracy: 0.0001, "\(type) back on the ground")
        }
        let fly = PlayAnimationPlan.make(for: event(kind: "out", spot: (0.7, 0.3), type: "fly"))!
        let line = PlayAnimationPlan.make(for: event(kind: "hit", spot: (0.7, 0.3), type: "line"))!
        XCTAssertGreaterThan(fly.ballState(at: fly.ball!.duration / 2)!.lift,
                             line.ballState(at: line.ball!.duration / 2)!.lift, "a fly ball goes higher than a liner")
    }

    // MARK: What animates

    func testAWalkWithNoPlayStillSendsTheBatterToFirst() {
        let plan = PlayAnimationPlan.make(for: event(kind: "walk"))!
        XCTAssertEqual(plan.runners.map(\.to), [Base.first])
        XCTAssertNil(plan.ball)
    }

    func testBallsStrikesAndFoulsDontAnimate() {
        for kind in ["ball", "strike", "foul"] {
            XCTAssertNil(PlayAnimationPlan.make(for: event(kind: kind)), kind)
        }
        XCTAssertTrue(PlayAnimationPlan.make(for: event(kind: "strikeout"))!.strikeout)
    }
}
