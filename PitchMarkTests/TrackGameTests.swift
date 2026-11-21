//
//  TrackGameTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-20 (Track Game uses the Call Pitches screen):
//  T3 in Track Game a zone tap goes straight to the result step, never the
//     code step; in Call Pitches the code step is still required
//  T4 hit by pitch saves on its own and counts as a ball
//  T6 an Unknown pitch saves with no type and stays out of per-pitch stats
//  (T5 is the UI test, TrackGameUITests.)
//

import XCTest
@testable import PitchMark

final class TrackGameTests: XCTestCase {

    // MARK: T3

    func testTrackGameSkipsTheCodeStep() {
        XCTAssertEqual(PitchEntryFlow.stepAfterZoneTap(mode: .scout), .recordResult)
        XCTAssertFalse(PitchEntryFlow.showsCodePanel(.scout))
        XCTAssertFalse(PitchEntryFlow.announcesCall(.scout), "a tracked pitch is never sent to the Display")
    }

    func testCallPitchesStillSignalsACode() {
        XCTAssertEqual(PitchEntryFlow.stepAfterZoneTap(mode: .coach), .signalCode)
        XCTAssertTrue(PitchEntryFlow.showsCodePanel(.coach))
        XCTAssertTrue(PitchEntryFlow.announcesCall(.coach))
    }

    func testTrackGameHasUnknownAndCallPitchesHasCatcher() {
        XCTAssertEqual(PitchEntryFlow.chipOptions(["4 Seam", "Change"], mode: .scout), ["4 Seam", "Change", "Unknown"])
        XCTAssertEqual(PitchEntryFlow.chipOptions(["4 Seam", "Change"], mode: .coach), ["", "4 Seam", "Change"])
    }

    // MARK: T4

    private func gate(hitBatter: Bool = false, ball: Bool = false, outcome: String? = nil,
                      unfinished: Bool = false, conflict: Bool = false) -> Bool {
        PitchResultSaveGate.canSave(strikeSwinging: false, strikeLooking: false, foul: false, ball: ball,
                                    hitTag: false, hitBatter: hitBatter, outcome: outcome,
                                    batterPlayUnfinished: unfinished, hasRunnerConflict: conflict)
    }

    func testHitByPitchSavesOnItsOwn() {
        XCTAssertTrue(gate(hitBatter: true), "HBP alone")
        XCTAssertFalse(gate(), "nothing picked")
        XCTAssertFalse(gate(hitBatter: true, conflict: true), "a runner conflict still blocks it")
        XCTAssertTrue(gate(ball: true))
        XCTAssertTrue(gate(outcome: "Out"))
        XCTAssertFalse(gate(outcome: "Walk"), "a tag alone isn't a result")
        XCTAssertFalse(gate(outcome: "1B", unfinished: true), "a placed batter must finish the how")
        XCTAssertTrue(gate(outcome: "1B"))
    }

    private func event(pitch: String = "Fastball", outcome: String? = nil, isStrike: Bool = false,
                       isBall: Bool = false, mode: TrackingMode = .scout) -> PitchEvent {
        var event = PitchEvent(
            id: UUID().uuidString, timestamp: Date(), pitch: pitch, location: "Ball Up", codes: [],
            isStrike: isStrike, isBall: isBall, mode: .game, calledPitch: nil, batterSide: .right,
            templateId: nil, strikeSwinging: false, wildPitch: false, passedBall: false,
            strikeLooking: false, outcome: outcome, descriptor: nil, errorOnPlay: false,
            battedBallRegion: nil, battedBallType: nil, battedBallTapX: nil, battedBallTapY: nil,
            gameId: "game-1", opponentJersey: "9", opponentBatterId: "cell-9", pitcherId: "pitcher-1"
        )
        event.trackingMode = mode
        return event
    }

    func testHitByPitchCountsAsABall() {
        XCTAssertEqual(inferredPitchResultType(for: event(outcome: "HBP")), .ball)
    }

    // MARK: T6

    func testUnknownStaysOutOfPerPitchStatsButCountsAsAPitch() {
        let events = [event(pitch: "Fastball", isStrike: true), event(pitch: "Unknown", isBall: true),
                      event(pitch: "Unknown", isStrike: true), event(pitch: "Curve", isBall: true)]
        let snapshot = PitchStatsCalculator.snapshot(for: events)
        XCTAssertEqual(Set(snapshot.pitchBreakdown.map { $0.name }), ["Fastball", "Curve"])
        XCTAssertEqual(snapshot.totalPitches, 4, "Unknown pitches still count as pitches")
        XCTAssertFalse(event(pitch: "Unknown").hasKnownPitchType)
        XCTAssertFalse(event(pitch: " ").hasKnownPitchType)
        XCTAssertTrue(event(pitch: "Fastball").hasKnownPitchType)
        XCTAssertFalse(HeatmapSelection.pitchTypes(events.map { var e = $0; e.trackingMode = .coach; e.calledPitch = PitchCall(pitch: e.pitch, location: "Ball Up", isStrike: false, codes: []); return e }).contains("Unknown"))
    }

    func testATrackedPitchNeverCountsTowardHittingTheSpot() {
        var tracked = event()
        tracked.calledPitch = PitchCall(pitch: "Fastball", location: "Ball Up", isStrike: false, codes: [])
        XCTAssertFalse(tracked.supportsLocationAnalytics, "Track Game has no called spot")
    }
}
