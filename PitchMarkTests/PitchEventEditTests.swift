//
//  PitchEventEditTests.swift
//  PitchMarkTests
//
//  Batch 5 (approved 2026-11-01): editing a saved pitch and the review step.
//  Rules 1-3 and 9-11; the copies each change reaches (rules 4-8) are in
//  EventCopiesTests.
//

import XCTest
@testable import PitchMark

private func at(_ seconds: TimeInterval) -> Date { Fixture.t0.addingTimeInterval(seconds) }

/// A saved pitch carrying everything the edit sheet doesn't answer.
private func savedPitch() -> PitchEvent {
    var event = Fixture.pitch(id: "ev1", timestamp: at(10), isBall: true, balls: 2, strikes: 1,
                              hitterId: "hitter-9", basesBefore: BaseOccupancy(first: Fixture.r1))
    event.trackingMode = .scout
    event.catcherEstimate = PitchCall(pitch: "Curveball", location: "Ball Low", isStrike: false, codes: [])
    event.createdByUid = "partner"
    event.ballMarker = "2.circle"
    event.atBatCount = "2-1"
    return event
}

/// What the edit sheet hands back: a fresh pitch with the new result and
/// none of the fields it doesn't own.
private func sheetResult(strikeSwinging: Bool = true, balls: Int? = 1, strikes: Int? = 2) -> PitchEvent {
    var event = PitchEvent(
        id: nil, timestamp: Date(), pitch: "Slider", location: "Strike Low", codes: ["S"],
        isStrike: true, isBall: false, mode: .game, calledPitch: nil, batterSide: .right,
        templateId: nil, strikeSwinging: strikeSwinging, wildPitch: false, passedBall: false,
        strikeLooking: false, outcome: nil, descriptor: nil, errorOnPlay: false,
        battedBallRegion: nil, battedBallType: nil, battedBallTapX: nil, battedBallTapY: nil,
        gameId: "game-1", opponentJersey: "9", opponentBatterId: "cell-9", pitcherId: "pitcher-1"
    )
    event.strikeSwingingMarker = "2.circle"
    event.atBatBalls = balls
    event.atBatStrikes = strikes
    event.atBatCount = balls.map { "\($0)-\(strikes ?? 0)" }
    return event
}

@MainActor
final class PitchEventEditTests: XCTestCase {
    // MARK: Rules 1-2: an edit changes only what the sheet answers

    func testEditReplacesTheResult() {
        let updated = PitchEventEdit.applying(sheetResult(), to: savedPitch())
        XCTAssertEqual(updated.pitch, "Slider")
        XCTAssertEqual(updated.location, "Strike Low")
        XCTAssertEqual(updated.codes, ["S"])
        XCTAssertTrue(updated.isStrike)
        XCTAssertEqual(updated.isBall, false)
        XCTAssertTrue(updated.strikeSwinging)
        XCTAssertEqual(updated.strikeSwingingMarker, "2.circle")
        XCTAssertNil(updated.ballMarker, "the old ball marker goes with the old result")
    }

    func testEditKeepsEverythingTheSheetDoesNotAnswer() {
        let original = savedPitch()
        let updated = PitchEventEdit.applying(sheetResult(), to: original)
        XCTAssertEqual(updated.id, "ev1")
        XCTAssertEqual(updated.timestamp, original.timestamp)
        XCTAssertEqual(updated.trackingMode, .scout, "a scout pitch must not turn into a coach pitch")
        XCTAssertEqual(updated.catcherEstimate?.pitch, "Curveball")
        XCTAssertEqual(updated.hitterId, "hitter-9")
        XCTAssertEqual(updated.createdByUid, "partner")
        XCTAssertEqual(updated.pitcherId, "pitcher-1")
        XCTAssertEqual(updated.gameId, "game-1")
        XCTAssertEqual(updated.opponentJersey, "9")
        XCTAssertEqual(updated.opponentBatterId, "cell-9")
        XCTAssertEqual(updated.basesBefore, original.basesBefore)
    }

    /// The sheet stamps the count; when it somehow doesn't, the saved one stays.
    func testEditTakesTheSheetsCountOrKeepsTheSavedOne() {
        let counted = PitchEventEdit.applying(sheetResult(balls: 1, strikes: 2), to: savedPitch())
        XCTAssertEqual(counted.atBatBalls, 1)
        XCTAssertEqual(counted.atBatStrikes, 2)
        XCTAssertEqual(counted.atBatCount, "1-2")

        let uncounted = PitchEventEdit.applying(sheetResult(balls: nil, strikes: nil), to: savedPitch())
        XCTAssertEqual(uncounted.atBatBalls, 2)
        XCTAssertEqual(uncounted.atBatStrikes, 1)
        XCTAssertEqual(uncounted.atBatCount, "2-1")
    }

    // MARK: Rule 3: the edited pitch's count starts from the pitch before it

    func testCountStartsFromThePreviousPitchToThatBatter() {
        let first = Fixture.pitch(id: "p1", timestamp: at(1), isBall: true, balls: 1, strikes: 0)
        let second = Fixture.pitch(id: "p2", timestamp: at(2), isStrike: true, balls: 1, strikes: 1)
        let edited = Fixture.pitch(id: "p3", timestamp: at(3), isBall: true, balls: 2, strikes: 1)
        let later = Fixture.pitch(id: "p4", timestamp: at(4), isBall: true, balls: 3, strikes: 1)
        let otherBatter = Fixture.pitch(id: "x", timestamp: at(2.5), isBall: true, balls: 3, strikes: 2, jersey: "12")
        var otherGame = Fixture.pitch(id: "y", timestamp: at(2.6), balls: 3, strikes: 0)
        otherGame.gameId = "game-2"

        let seed = PitchEventEdit.countBefore(edited, in: [later, edited, otherBatter, second, first, otherGame])
        XCTAssertEqual(seed, AtBatCount(balls: 1, strikes: 1), "not the edited pitch's own count, not a later one")
    }

    /// The lineup slot is the batter; a jersey number can change or be
    /// shared, so it only stands in when no slot was recorded.
    func testTheBatterIsTheLineupSlotNotTheJersey() {
        var renumbered = Fixture.pitch(id: "p1", timestamp: at(1), isBall: true, balls: 1, strikes: 0, jersey: "99")
        renumbered.opponentBatterId = "cell-9"
        var sameJerseyOtherSlot = Fixture.pitch(id: "p2", timestamp: at(2), isBall: true, balls: 3, strikes: 0)
        sameJerseyOtherSlot.opponentBatterId = "cell-other"
        let edited = Fixture.pitch(id: "p3", timestamp: at(3), isStrike: true, balls: 1, strikes: 1)
        XCTAssertEqual(PitchEventEdit.countBefore(edited, in: [renumbered, sameJerseyOtherSlot, edited]),
                       AtBatCount(balls: 1, strikes: 0))
    }

    func testFirstPitchOfAnAtBatStartsAtZero() {
        let walk = Fixture.pitch(id: "p1", timestamp: at(1), isBall: true, outcome: "Walk", balls: 0, strikes: 0)
        let next = Fixture.pitch(id: "p2", timestamp: at(2), isStrike: true, balls: 0, strikes: 1)
        XCTAssertEqual(PitchEventEdit.countBefore(next, in: [walk, next]), .start, "after an at-bat ended")
        XCTAssertEqual(PitchEventEdit.countBefore(walk, in: [walk, next]), .start, "nothing before it")
    }

    func testWithNoBatterThePreviousPitchInTheGameStandsIn() {
        var before = Fixture.pitch(id: "p1", timestamp: at(1), isBall: true, balls: 1, strikes: 0, jersey: "")
        before.opponentBatterId = nil
        var edited = Fixture.pitch(id: "p2", timestamp: at(2), isBall: true, balls: 2, strikes: 0, jersey: "")
        edited.opponentBatterId = nil
        XCTAssertEqual(PitchEventEdit.countBefore(edited, in: [before, edited]), AtBatCount(balls: 1, strikes: 0))
    }

    /// The edit sheet opens at that count, ahead of the batter's latest pitch.
    func testEditSeedBeatsEveryOtherSource() {
        let seed = CountDraft.seed(editedPitchSeed: AtBatCount(balls: 1, strikes: 1),
                                   lastSavedPitchCount: (3, 2), liveCount: (2, 2), rememberedCount: (0, 1))
        XCTAssertEqual(seed, AtBatCount(balls: 1, strikes: 1))
        let normal = CountDraft.seed(lastSavedPitchCount: (3, 2), liveCount: (2, 2), rememberedCount: (0, 1))
        XCTAssertEqual(normal, AtBatCount(balls: 3, strikes: 2), "a new pitch still seeds as before")
    }

    /// Later pitches keep their labels, and only the game's latest pitch may
    /// move the tracker's count.
    func testOnlyTheLatestPitchMovesTheTrackerCount() {
        let older = Fixture.pitch(id: "p1", timestamp: at(1))
        let latest = Fixture.pitch(id: "p2", timestamp: at(2), jersey: "12")
        var otherGame = Fixture.pitch(id: "p3", timestamp: at(3))
        otherGame.gameId = "game-2"
        let events = [older, latest, otherGame]
        XCTAssertFalse(PitchEventEdit.editMovesTrackerCount(older, in: events))
        XCTAssertTrue(PitchEventEdit.editMovesTrackerCount(latest, in: events))
    }

    // MARK: Rule 9: walks and strikeouts on review keep their label

    private func review(_ base: PitchEvent, balls: Int, strikes: Int, isBall: Bool = false, isStrike: Bool = false,
                        swinging: Bool = false, walk: Bool = false) -> PitchEvent {
        buildSavedPlayReviewedEvent(from: base, balls: balls, strikes: strikes, isStrike: isStrike, isBall: isBall,
                                    strikeLooking: false, strikeSwinging: swinging, wildPitch: false,
                                    passedBall: false, countsAsWalk: walk, countsAsHit: false)
    }

    func testReviewedWalkIsBallFourAndResets() {
        var ball4 = Fixture.pitch(id: "p1", isBall: true, outcome: "Walk")
        ball4.applyCount(.start, terminal: .walk)
        let reviewed = review(ball4, balls: 0, strikes: 0, isBall: true, walk: true)
        XCTAssertEqual(reviewed.atBatCount, "Ball 4")
        XCTAssertEqual(reviewed.atBatBalls, 0)
        XCTAssertEqual(reviewed.atBatStrikes, 0)
    }

    func testReviewedStrikeoutIsLabelledStrikeout() {
        var strike3 = Fixture.pitch(id: "p1", isStrike: true, strikeSwinging: true, outcome: "K")
        strike3.applyCount(.start, terminal: .strikeout)
        let reviewed = review(strike3, balls: 0, strikes: 0, isStrike: true, swinging: true)
        XCTAssertEqual(reviewed.atBatCount, "Strikeout")
        XCTAssertEqual(reviewed.atBatBalls, 0)
        XCTAssertEqual(reviewed.atBatStrikes, 0)
    }

    func testReviewedOrdinaryPitchKeepsTheReviewCount() {
        let ball = Fixture.pitch(id: "p1", isBall: true, balls: 2, strikes: 1)
        let reviewed = review(ball, balls: 3, strikes: 1, isBall: true)
        XCTAssertEqual(reviewed.atBatBalls, 3)
        XCTAssertEqual(reviewed.atBatStrikes, 1)
        XCTAssertEqual(reviewed.atBatCount, "3-1")
    }

    // MARK: Rule 10: review keeps what it doesn't change

    func testReviewKeepsEverythingItDoesNotChange() {
        let original = savedPitch()
        let reviewed = review(original, balls: 2, strikes: 1, isBall: true)
        XCTAssertEqual(reviewed.id, original.id)
        XCTAssertEqual(reviewed.timestamp, original.timestamp)
        XCTAssertEqual(reviewed.trackingMode, .scout)
        XCTAssertEqual(reviewed.catcherEstimate?.pitch, "Curveball")
        XCTAssertEqual(reviewed.hitterId, "hitter-9")
        XCTAssertEqual(reviewed.createdByUid, "partner")
        XCTAssertEqual(reviewed.pitcherId, "pitcher-1")
        XCTAssertEqual(reviewed.ballMarker, "2.circle")
        XCTAssertEqual(reviewed.basesBefore, original.basesBefore)
    }

    // MARK: Rule 11: a scout pitch put in play opens as a strike

    func testScoutPitchInPlayStartsAsAStrike() {
        var inPlay = Fixture.pitch(id: "p1", isBall: true)
        inPlay.trackingMode = .scout
        inPlay.battedBallRegion = "Left Field"
        XCTAssertTrue(PitchEventEdit.reviewStartsAsStrike(inPlay))

        var scoutBall = Fixture.pitch(id: "p2", isBall: true)
        scoutBall.trackingMode = .scout
        XCTAssertFalse(PitchEventEdit.reviewStartsAsStrike(scoutBall))
    }
}
