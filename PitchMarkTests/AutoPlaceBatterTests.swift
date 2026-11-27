//
//  AutoPlaceBatterTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-25 (a hit nobody placed):
//  1 the batter goes to 1st only with Hit or Safe AND a fair ball - not on
//    a foul, not when already placed, not on an out
//  3 bases loaded: the runner from 3rd scores, the others move up one
//  4 with Error on, the batter reached on error, not a single
//  6 a runner who held their base reaches the feed as staying put, and the
//    animation draws them on that base
//  (2 and 5 are UI tests: AutoPlaceBatterUITests.)
//

import XCTest
@testable import PitchMark

final class AutoPlaceBatterTests: XCTestCase {

    // MARK: 1 when it fills in

    func testOnlyASafeCallOnAFairBallPlacesTheBatter() {
        XCTAssertTrue(PlayDraft.impliesBatterOnFirst(safeSaid: true, fairBallTapped: true, batterPlaced: false, batterOut: false))
        XCTAssertFalse(PlayDraft.impliesBatterOnFirst(safeSaid: false, fairBallTapped: true, batterPlaced: false, batterOut: false),
                       "a ball type and a tap alone don't say safe")
        XCTAssertFalse(PlayDraft.impliesBatterOnFirst(safeSaid: true, fairBallTapped: false, batterPlaced: false, batterOut: false),
                       "no fair ball (a foul, or no tap)")
        XCTAssertFalse(PlayDraft.impliesBatterOnFirst(safeSaid: true, fairBallTapped: true, batterPlaced: true, batterOut: false),
                       "already on a base")
        XCTAssertFalse(PlayDraft.impliesBatterOnFirst(safeSaid: true, fairBallTapped: true, batterPlaced: false, batterOut: true),
                       "an out")
    }

    // MARK: 3 forced runners

    func testBasesLoadedEveryoneMovesUpOneAndTheRunnerFromThirdScores() {
        let loaded = BaseOccupancy(first: BaseRunner(id: "a", label: "#1"),
                                   second: BaseRunner(id: "b", label: "#2"),
                                   third: BaseRunner(id: "c", label: "#3"))
        var draft = PlayDraft(basesBefore: loaded, batterReachedBase: Base.first,
                              batterCredit: PlayDraft.impliedFirstBaseCredit(isError: false))
        draft.batterBaseChanged()
        XCTAssertEqual(draft.runnerDestinations[Base.first], Base.second)
        XCTAssertEqual(draft.runnerDestinations[Base.second], Base.third)
        XCTAssertEqual(draft.runnerDestinations[Base.third], Base.scored)
        XCTAssertEqual(draft.play?.runs, 1)
    }

    func testARunnerWhoIsNotForcedStays() {
        let onSecond = BaseOccupancy(second: BaseRunner(id: "b", label: "#2"))
        var draft = PlayDraft(basesBefore: onSecond, batterReachedBase: Base.first, batterCredit: .single)
        draft.batterBaseChanged()
        XCTAssertNotEqual(draft.runnerDestinations[Base.second], Base.third, "nobody pushes the runner on 2nd")
    }

    // MARK: 4 error

    func testErrorOnMeansReachedOnError() {
        XCTAssertEqual(PlayDraft.impliedFirstBaseCredit(isError: false), .single)
        XCTAssertEqual(PlayDraft.impliedFirstBaseCredit(isError: true), .reachedOnError)
    }

    // MARK: 6 runners who held

    func testARunnerWhoHeldIsInTheFeedAndDrawnOnTheirBase() {
        var pitch = PitchEvent(
            id: "e1", timestamp: Date(), pitch: "Rise", location: "Strike Up", codes: [],
            isStrike: true, isBall: false, mode: .game, calledPitch: nil, batterSide: .right,
            templateId: nil, strikeSwinging: false, wildPitch: false, passedBall: false,
            strikeLooking: false, outcome: "1B", descriptor: "Line, Hit", errorOnPlay: false,
            battedBallRegion: "Deep Right", battedBallType: "Field", battedBallTapX: 0.7, battedBallTapY: 0.3,
            gameId: "g1", opponentJersey: "1", opponentBatterId: nil, pitcherId: "p1"
        )
        pitch.atBatBalls = 0
        pitch.atBatStrikes = 0
        // #26 on 2nd holds; the batter singles.
        pitch.basesBefore = BaseOccupancy(second: BaseRunner(id: "r26", label: "#26"))
        pitch.play = BasePlay(batterCredit: "1B", moves: [RunnerMove(runner: RunnerMove.batterKey, from: 0, to: 1)])
        let event = GameFeedRules.event(from: pitch, id: "e1", inning: 1, half: nil, batterName: nil, showLastNames: false)
        XCTAssertEqual(event.moves, [FeedMove(from: 0, to: 1), FeedMove(from: 2, to: 2)])

        let plan = PlayAnimationPlan.make(for: event)!
        let held = plan.runners.first { $0.from == Base.second }
        XCTAssertNotNil(held, "the runner on 2nd is drawn")
        XCTAssertEqual(plan.runnerPosition(held!, at: plan.duration), PlayAnimationPlan.point(Base.second), "and stays on 2nd")
    }
}
