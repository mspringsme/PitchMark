//
//  GameTimelineTests.swift
//  PitchMarkTests
//
//  Item 5 (2026-11-21): base-running events between pitches show as their
//  own cards, in time order with the pitches, carrying the board when they
//  happened.
//

import XCTest
@testable import PitchMark

final class GameTimelineTests: XCTestCase {
    private func runner(_ id: String, at seconds: TimeInterval) -> RunnerEvent {
        RunnerEvent(id: id, timestamp: Date(timeIntervalSince1970: seconds), kind: RunnerEventKind.stolenBase.rawValue,
                    from: 1, to: 2, runner: BaseRunner(id: "r", label: "#7"), basesBefore: .empty)
    }

    private func pitch(_ id: String, at seconds: TimeInterval) -> PitchEvent {
        PitchEvent(
            id: id, timestamp: Date(timeIntervalSince1970: seconds), pitch: "Rise", location: "Strike Up", codes: [],
            isStrike: true, isBall: false, mode: .game, calledPitch: nil, batterSide: .right,
            templateId: nil, strikeSwinging: false, wildPitch: false, passedBall: false,
            strikeLooking: false, outcome: nil, descriptor: nil, errorOnPlay: false,
            battedBallRegion: nil, battedBallType: nil, battedBallTapX: nil, battedBallTapY: nil,
            gameId: "g1", opponentJersey: nil, opponentBatterId: nil, pitcherId: "p1"
        )
    }

    func testRunnerEventsSitBetweenThePitchesNewestFirst() {
        let early = pitch("e1", at: 100)
        let late = pitch("e2", at: 300)
        let steal = runner("s1", at: 200)
        let items = GameTimeline.merged(pitches: [early, late], runners: [steal])
        XCTAssertEqual(items.map(\.timestamp.timeIntervalSince1970), [300, 200, 100])
        guard case .runner(let middle) = items[1] else { return XCTFail("the steal is between the pitches") }
        XCTAssertEqual(middle.id, "s1")
    }

    func testARunnerEventSeenTwiceShowsOnce() {
        let steal = runner("s1", at: 200)
        XCTAssertEqual(GameTimeline.merged(pitches: [], runners: [steal, steal]).count, 1,
                       "the local copy and the saved copy are one event")
    }

    func testTheCardCarriesTheBoard() {
        var steal = runner("s1", at: 200)
        XCTAssertEqual(steal.cardText, "#7 steals 2nd", "older events have no board")
        steal.balls = 2; steal.strikes = 1; steal.outsBefore = 1; steal.batterJersey = "3"
        XCTAssertEqual(steal.cardText, "#7 steals 2nd · 2-1 · 1 out · #3 batting")
    }
}
