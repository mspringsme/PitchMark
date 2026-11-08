//
//  TestFixtures.swift
//  PitchMarkTests
//
//  Runners and pitches shared by the Phase 3 tests.
//

import Foundation
@testable import PitchMark

enum Fixture {
    static let r1 = BaseRunner(id: "cell-1", label: "#1", hitterId: "hitter-1")
    static let r2 = BaseRunner(id: "cell-2", label: "#2", hitterId: "hitter-2")
    static let r3 = BaseRunner(id: "cell-3", label: "#3", hitterId: "hitter-3")
    static let pinch = BaseRunner(id: "cell-22", label: "#22", hitterId: "hitter-22")
    static let unlinked = BaseRunner(id: "", label: "#44")

    static let context = GameProgress.RunnerEventContext(
        gameId: "game-1",
        pitcherId: "pitcher-1",
        createdByUid: "coach-1",
        inning: 4
    )

    static let t0 = Date(timeIntervalSince1970: 1_000)

    /// A game pitch as the tracker saves it. `balls`/`strikes` are the
    /// stored count - 0-0 on the pitch that ended an at-bat (applyCount).
    static func pitch(
        id: String = UUID().uuidString,
        timestamp: Date = t0,
        isStrike: Bool = false,
        isBall: Bool = false,
        strikeSwinging: Bool = false,
        wildPitch: Bool = false,
        passedBall: Bool = false,
        outcome: String? = nil,
        balls: Int? = nil,
        strikes: Int? = nil,
        jersey: String = "9",
        hitterId: String? = "hitter-9",
        play: BasePlay? = nil,
        basesBefore: BaseOccupancy? = nil
    ) -> PitchEvent {
        var event = PitchEvent(
            id: id,
            timestamp: timestamp,
            pitch: "Fastball",
            location: isStrike ? "Strike Middle" : "Ball Up",
            codes: [],
            isStrike: isStrike,
            isBall: isBall,
            mode: .game,
            calledPitch: nil,
            batterSide: .right,
            templateId: nil,
            strikeSwinging: strikeSwinging,
            wildPitch: wildPitch,
            passedBall: passedBall,
            strikeLooking: false,
            outcome: outcome,
            descriptor: nil,
            errorOnPlay: false,
            battedBallRegion: nil,
            battedBallType: nil,
            battedBallTapX: nil,
            battedBallTapY: nil,
            gameId: "game-1",
            opponentJersey: jersey,
            opponentBatterId: "cell-\(jersey)",
            pitcherId: "pitcher-1"
        )
        event.hitterId = hitterId
        event.atBatBalls = balls
        event.atBatStrikes = strikes
        event.play = play
        event.basesBefore = basesBefore
        return event
    }
}
