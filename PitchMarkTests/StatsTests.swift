//
//  StatsTests.swift
//  PitchMarkTests
//
//  Batch 6 (approved 2026-11-01): the stats math. Expected values come from
//  the approved rules, including the user's two choices: pitcher strikeouts
//  and walks count the way the hitter's line does, and percentages round.
//

import XCTest
@testable import PitchMark

private func at(_ seconds: TimeInterval) -> Date { Fixture.t0.addingTimeInterval(seconds) }

/// A pitch with just the fields a stats rule reads.
private func pitch(
    id: String = UUID().uuidString,
    time: TimeInterval = 0,
    location: String = "Ball Up",
    isStrike: Bool = false,
    isBall: Bool? = nil,
    swinging: Bool = false,
    looking: Bool = false,
    outcome: String? = nil,
    descriptor: String? = nil,
    errorOnPlay: Bool = false,
    play: BasePlay? = nil,
    balls: Int? = nil,
    strikes: Int? = nil,
    gameId: String? = "game-1",
    jersey: String? = "9",
    batterId: String? = nil
) -> PitchEvent {
    var event = PitchEvent(
        id: id, timestamp: at(time), pitch: "Fastball", location: location, codes: [],
        isStrike: isStrike, isBall: isBall, mode: .game, calledPitch: nil, batterSide: .right,
        templateId: nil, strikeSwinging: swinging, wildPitch: false, passedBall: false,
        strikeLooking: looking, outcome: outcome, descriptor: descriptor, errorOnPlay: errorOnPlay,
        battedBallRegion: nil, battedBallType: nil, battedBallTapX: nil, battedBallTapY: nil,
        gameId: gameId, opponentJersey: jersey, opponentBatterId: batterId ?? jersey.map { "cell-\($0)" },
        pitcherId: "pitcher-1"
    )
    event.play = play
    event.atBatBalls = balls
    event.atBatStrikes = strikes
    return event
}

/// A coach-mode pitch with a call, for hit-spot and heatmap rules.
private func called(_ calledLocation: String, thrown location: String, pitch name: String = "Fastball",
                    calledPitch: String = "Fastball", side: BatterSide = .right) -> PitchEvent {
    var event = pitch(location: location, isStrike: location.hasPrefix("Strike"))
    event = PitchEvent(
        id: event.id, timestamp: event.timestamp, pitch: name, location: location, codes: [],
        isStrike: event.isStrike, isBall: !event.isStrike, mode: .game,
        calledPitch: PitchCall(pitch: calledPitch, location: calledLocation,
                               isStrike: calledLocation.hasPrefix("Strike"), codes: []),
        batterSide: side, templateId: nil, strikeSwinging: false, wildPitch: false, passedBall: false,
        strikeLooking: false, outcome: nil, descriptor: nil, errorOnPlay: false,
        battedBallRegion: nil, battedBallType: nil, battedBallTapX: nil, battedBallTapY: nil,
        gameId: "game-1", opponentJersey: "9", opponentBatterId: "cell-9", pitcherId: "pitcher-1"
    )
    event.trackingMode = .coach
    return event
}

@MainActor
final class PitchResultTypeTests: XCTestCase {
    // MARK: Rules 1-4: strike or ball

    func testSwingsFoulsAndBallsInPlayAreStrikes() {
        XCTAssertEqual(inferredPitchResultType(for: pitch(isBall: true, swinging: true)), .strike)
        XCTAssertEqual(inferredPitchResultType(for: pitch(isBall: true, looking: true)), .strike)
        XCTAssertEqual(inferredPitchResultType(for: pitch(isBall: true, outcome: "Foul")), .strike)
        XCTAssertEqual(inferredPitchResultType(for: pitch(isBall: true, outcome: "1B")), .strike)
        XCTAssertEqual(inferredPitchResultType(for: pitch(isBall: true, outcome: "Out")), .strike)
        XCTAssertEqual(inferredPitchResultType(for: pitch(isBall: true, descriptor: "Ground")), .strike)
    }

    func testMarkedBallIsABall() {
        XCTAssertEqual(inferredPitchResultType(for: pitch(location: "Strike Middle", isStrike: true, isBall: true)), .ball)
    }

    func testOtherwiseTheLocationDecides() {
        XCTAssertEqual(inferredPitchResultType(for: pitch(location: "Strike Middle", isStrike: false)), .strike)
        XCTAssertEqual(inferredPitchResultType(for: pitch(location: "Ball Up", isStrike: false)), .ball)
    }

    func testHitByPitchIsABall() {
        XCTAssertEqual(inferredPitchResultType(for: pitch(location: "Strike Middle", isStrike: true,
                                                          outcome: "HBP", descriptor: "Hit By Pitch")), .ball)
    }

    // MARK: Rule 5 + rounding

    func testPercentagesRoundToTheNearestWholeNumber() {
        XCTAssertEqual(statPercent(2, of: 3), 67, "cut off this was 66")
        XCTAssertEqual(statPercent(1, of: 3), 33)
        XCTAssertEqual(statPercent(1, of: 8), 13, "12.5 rounds up")
        XCTAssertEqual(statPercent(3, of: 3), 100)
        XCTAssertEqual(statPercent(0, of: 0), 0, "nothing to divide by")
    }

    func testStrikeAndBallShareOfEveryPitch() {
        let events = [pitch(swinging: true), pitch(isBall: true), pitch(outcome: "Foul")]
        let stats = PitchStatsCalculator.snapshot(for: events)
        XCTAssertEqual(stats.totalPitches, 3)
        XCTAssertEqual(stats.strikePitches, 2)
        XCTAssertEqual(stats.ballPitches, 1)
        XCTAssertEqual(statPercent(stats.strikePitches, of: stats.totalPitches), 67)
        XCTAssertEqual(statPercent(stats.ballPitches, of: stats.totalPitches), 33)
    }
}

@MainActor
final class PitcherStatsTests: XCTestCase {
    // MARK: Rule 6: hits

    func testCreditedHits() {
        XCTAssertTrue(pitchEventIsCreditedHit(pitch(outcome: "2B")))
        XCTAssertTrue(pitchEventIsCreditedHit(pitch(descriptor: "Line Drive, Hit")))
        XCTAssertFalse(pitchEventIsCreditedHit(pitch(outcome: "1B", errorOnPlay: true)),
                       "an old error with no play recorded is reached on error")
        XCTAssertFalse(pitchEventIsCreditedHit(pitch(outcome: "1B", errorOnPlay: true,
                                                     play: BasePlay(batterCredit: "ROE", moves: []))))
        XCTAssertTrue(pitchEventIsCreditedHit(pitch(outcome: "1B", errorOnPlay: true,
                                                    play: BasePlay(batterCredit: "1B", moves: []))),
                      "an error that only added bases leaves the hit")
        for nonHit in ["Out", "K", "Walk", "HBP"] {
            XCTAssertFalse(pitchEventIsCreditedHit(pitch(outcome: nonHit, descriptor: "Hit")), nonHit)
        }
    }

    // MARK: Rule 7: strikeouts and walks, however recorded

    func testStrikeoutsCountWithOrWithoutTheLabel() {
        let labelledSwinging = pitch(swinging: true, outcome: "K", balls: 0, strikes: 0)
        let labelledLooking = pitch(looking: true, outcome: "ꓘ", balls: 0, strikes: 0)
        let unlabelledSwinging = pitch(swinging: true, balls: 0, strikes: 0)
        let unlabelledLooking = pitch(looking: true, balls: 0, strikes: 0)
        let strikeTwo = pitch(swinging: true, balls: 1, strikes: 2)

        XCTAssertTrue(PitchStatsCalculator.isStrikeoutSwinging(labelledSwinging))
        XCTAssertTrue(PitchStatsCalculator.isStrikeoutSwinging(unlabelledSwinging))
        XCTAssertTrue(PitchStatsCalculator.isStrikeoutLooking(labelledLooking))
        XCTAssertTrue(PitchStatsCalculator.isStrikeoutLooking(unlabelledLooking))
        XCTAssertFalse(PitchStatsCalculator.isStrikeoutLooking(labelledSwinging))
        XCTAssertFalse(PitchStatsCalculator.isStrikeoutSwinging(labelledLooking))
        XCTAssertFalse(PitchStatsCalculator.isStrikeout(strikeTwo))
    }

    func testWalksCountWithOrWithoutTheLabel() {
        let events = [
            pitch(isBall: true, outcome: "Walk", balls: 0, strikes: 0),
            pitch(isBall: true, balls: 0, strikes: 0),
            pitch(isBall: true, outcome: "BB"),
            pitch(isBall: true, balls: 3, strikes: 1)
        ]
        XCTAssertEqual(PitchStatsCalculator.snapshot(for: events).walkCount, 3)
    }

    /// The pitcher's and the hitter's lines agree on the same pitches.
    func testPitcherAndHitterAgree() {
        let events = [
            pitch(swinging: true, balls: 0, strikes: 0),
            pitch(looking: true, outcome: "ꓘ", balls: 0, strikes: 0),
            pitch(isBall: true, balls: 0, strikes: 0),
            pitch(isBall: true, outcome: "Walk", balls: 0, strikes: 0)
        ]
        let hitter = HittingStatLine(events: events)
        XCTAssertEqual(events.filter(PitchStatsCalculator.isStrikeout).count, hitter.strikeouts)
        XCTAssertEqual(PitchStatsCalculator.snapshot(for: events).walkCount, hitter.walks)
    }

    // MARK: Rule 8

    func testWildPitchesAndPassedBallsComeFromTheirFlags() {
        var wild = pitch(isBall: true)
        wild.wildPitch = true
        var passed = pitch(isBall: true)
        passed.passedBall = true
        let stats = PitchStatsCalculator.snapshot(for: [wild, passed, pitch(isBall: true)])
        XCTAssertEqual(stats.wildPitchCount, 1)
        XCTAssertEqual(stats.passedBallCount, 1)
    }

    // MARK: Rules 9-10: first-pitch strike

    func testEachPlateAppearanceCountsOnce() {
        let events = [
            pitch(time: 1, swinging: true, jersey: "9"),           // PA 1, strike
            pitch(time: 2, isBall: true, jersey: "9"),
            pitch(time: 3, isBall: true, jersey: "12"),            // PA 2, ball
            pitch(time: 4, outcome: "1B", jersey: "12"),
            pitch(time: 5, isBall: true, outcome: "1B", jersey: "4") // PA 3, in play = strike
        ]
        let fps = sharedFirstPitchStrikeMetrics(for: events)
        XCTAssertEqual(fps.total, 3)
        XCTAssertEqual(fps.made, 2)
    }

    func testANewGameStartsANewPlateAppearance() {
        let events = [
            pitch(time: 1, swinging: true, gameId: "game-1", jersey: "9"),
            pitch(time: 2, swinging: true, gameId: "game-2", jersey: "9")
        ]
        XCTAssertEqual(sharedFirstPitchStrikeMetrics(for: events).total, 2,
                       "the same jersey leading off the next game is a new batter")
    }

    func testTheSameBatterAgainAfterAnAtBatEndsIsANewPlateAppearance() {
        let events = [
            pitch(time: 1, isBall: true, outcome: "Walk", balls: 0, strikes: 0, jersey: "9"),
            pitch(time: 2, swinging: true, balls: 0, strikes: 1, jersey: "9")
        ]
        let fps = sharedFirstPitchStrikeMetrics(for: events)
        XCTAssertEqual(fps.total, 2)
        XCTAssertEqual(fps.made, 1)
    }

    func testPitchesWithNoBatterAreSkipped() {
        let events = [pitch(time: 1, swinging: true, jersey: nil, batterId: nil)]
        XCTAssertEqual(sharedFirstPitchStrikeMetrics(for: events).total, 0)
    }

    // MARK: Rules 11-12: hit spot

    func testOnlyCoachPitchesWithACallAndLocationAreEligible() {
        XCTAssertTrue(called("Strike Middle", thrown: "Strike Middle").supportsLocationAnalytics)
        var scout = called("Strike Middle", thrown: "Strike Middle")
        scout.trackingMode = .scout
        XCTAssertFalse(scout.supportsLocationAnalytics)
        XCTAssertFalse(called("Strike Middle", thrown: "Strike Middle", pitch: "Catcher").supportsLocationAnalytics)
        XCTAssertFalse(pitch().supportsLocationAnalytics, "no call")
    }

    func testHitSpotNeedsPitchZoneAndStrikeOrBallToMatch() {
        XCTAssertTrue(isLocationMatch(called("Strike Up & In", thrown: "Strike Up & In")))
        XCTAssertTrue(isLocationMatch(called("Strike Up & In", thrown: "Strike Up & In", side: .left)))
        XCTAssertTrue(isLocationMatch(called("Strike Up & In", thrown: "Strike Up and In")), "same zone, other spelling")
        XCTAssertFalse(isLocationMatch(called("Strike Up & In", thrown: "Strike Up & Out")))
        XCTAssertFalse(isLocationMatch(called("Strike Up & In", thrown: "Ball Up & In")))
        XCTAssertFalse(isLocationMatch(called("Strike Middle", thrown: "Strike Middle", pitch: "Curveball")))
    }
}

@MainActor
final class HittingStatLineTests: XCTestCase {
    // MARK: Rule 13

    func testPlateAppearancesAndAtBats() {
        let line = HittingStatLine(events: [
            pitch(isBall: true, outcome: "Walk", balls: 0, strikes: 0),
            pitch(outcome: "HBP"),
            pitch(swinging: true, outcome: "K", balls: 0, strikes: 0),
            pitch(outcome: "Out"),
            pitch(outcome: "Out", play: BasePlay(batterCredit: "FC", moves: [])),
            pitch(outcome: "2B"),
            pitch(outcome: "1B", errorOnPlay: true, play: BasePlay(batterCredit: "ROE", moves: []))
        ])
        XCTAssertEqual(line.plateAppearances, 7)
        XCTAssertEqual(line.atBats, 5, "walk and HBP aren't at-bats")
        XCTAssertEqual(line.hits, 1)
        XCTAssertEqual(line.doubles, 1)
        XCTAssertEqual(line.walks, 1)
        XCTAssertEqual(line.hitByPitch, 1)
        XCTAssertEqual(line.strikeouts, 1)
        XCTAssertEqual(line.reachedOnError, 1)
    }

    // MARK: Rule 14

    func testRates() {
        let line = HittingStatLine(events: [
            pitch(outcome: "1B"), pitch(outcome: "HR"), pitch(outcome: "Out"), pitch(outcome: "Out"),
            pitch(isBall: true, outcome: "Walk"),
            pitch(outcome: "1B", errorOnPlay: true)
        ])
        // AB 5 (1B, HR, Out, Out, ROE), H 2, PA 6, BB 1, TB 1 + 4 = 5
        XCTAssertEqual(line.average!, 2.0 / 5.0, accuracy: 1e-9)
        XCTAssertEqual(line.onBase!, 3.0 / 6.0, accuracy: 1e-9, "ROE isn't on base")
        XCTAssertEqual(line.slugging!, 5.0 / 5.0, accuracy: 1e-9)
        XCTAssertEqual(HittingStatLine.formatRate(line.average), ".400")
        XCTAssertEqual(HittingStatLine.formatRate(1.0), "1.000")
    }

    func testRatesWithNothingToDivideBy() {
        let line = HittingStatLine(events: [])
        XCTAssertNil(line.average)
        XCTAssertNil(line.onBase)
        XCTAssertNil(line.slugging)
        XCTAssertEqual(HittingStatLine.formatRate(line.average), "—")
    }

    func testSluggingOnlyWhenEveryHitSaysWhichBase() {
        let line = HittingStatLine(events: [pitch(outcome: "1B"), pitch(descriptor: "Hit")])
        XCTAssertEqual(line.hits, 2)
        XCTAssertNil(line.slugging)
    }

    // MARK: Rule 15

    func testAtBatEndsWithNoOutcome() {
        XCTAssertEqual(pitch(swinging: true, balls: 0, strikes: 0).atBatEnd, .strikeout)
        XCTAssertEqual(pitch(isBall: true, balls: 0, strikes: 0).atBatEnd, .walk)
        XCTAssertEqual(pitch(descriptor: "Fly, Hit", balls: 0, strikes: 0).atBatEnd, .hit)
        XCTAssertNil(pitch(swinging: true, balls: 0, strikes: 1).atBatEnd)
        XCTAssertNil(pitch(swinging: true).atBatEnd, "no stored count: only an outcome can say")
        XCTAssertNil(pitch(outcome: "Foul", balls: 0, strikes: 0).atBatEnd)
    }
}

@MainActor
final class StatsScopeTests: XCTestCase {
    // MARK: Rule 16

    func testArchivedGamesCountOnlyWhenKept() {
        var open = Game(opponent: "Open", date: Fixture.t0, jerseyNumbers: [])
        open.id = "g1"
        var archived = Game(opponent: "Old", date: Fixture.t0, jerseyNumbers: [])
        archived.id = "g2"
        archived.archivedAt = Fixture.t0

        XCTAssertTrue(open.countsInStats(includedArchivedIds: []))
        XCTAssertFalse(archived.countsInStats(includedArchivedIds: []))
        XCTAssertTrue(archived.countsInStats(includedArchivedIds: ["g2"]))
        XCTAssertFalse(archived.countsInStats(includedArchivedIds: ["g1"]))
    }

    // MARK: Rule 17

    func testHeatmapTrimsPitchNamesAndSplitsByZone() {
        let fastball = called("Strike Middle", thrown: "Strike Middle")
        let spaced = called("Ball Up", thrown: "Ball Up", pitch: "Fastball ", calledPitch: "Fastball ")
        let legacyInZone = called("Middle", thrown: "Middle")
        let curve = called("Strike Down", thrown: "Strike Down", pitch: "Curveball", calledPitch: "Curveball")
        var scout = called("Strike Middle", thrown: "Strike Middle")
        scout.trackingMode = .scout
        let events = [fastball, spaced, legacyInZone, curve, scout]

        XCTAssertEqual(HeatmapSelection.pitchTypes(events), ["Curveball", "Fastball"])
        XCTAssertEqual(HeatmapSelection.counts(events)["Fastball"], 3)
        XCTAssertEqual(HeatmapSelection.events(events, pitch: "Fastball", zone: .all).count, 3,
                       "the untrimmed name stays in its own map; the scout pitch never shows")
        XCTAssertEqual(HeatmapSelection.events(events, pitch: "Fastball", zone: .strikes).count, 2)
        XCTAssertEqual(HeatmapSelection.events(events, pitch: "Fastball", zone: .balls).count, 1)
    }
}
