//
//  PracticeTests.swift
//  PitchMarkTests
//
//  Practice sessions. Approved 2026-11-20, revised the same day at the
//  user's request (no batter, no key, accuracy against the target):
//  T7 practice pitches save only under practiceSessions/{id}/pitchEvents -
//     never a game, the pitcher's career record or users/{uid}/pitchEvents;
//     a pitch is its target + where it went, with no result
//  T8 a session can't start without a player (anyone) and a pitch
//  T9 every pitch type is offered; only the checked ones are chips; no key,
//     so never codes
//  T10 the accuracy stats come from the spots' geometry: on target, within
//      one, in the zone, miss direction, accuracy by target - per pitch and
//      for the session
//  (R8 is rules-tests/tests/practice.test.mjs; T11 is PracticeUITests.)
//

import XCTest
import FirebaseFirestore
@testable import PitchMark

final class PracticeTests: XCTestCase {

    private let session = PracticeSession(id: "s1", pitcherId: "p1", pitcherName: "Ava", templateId: nil,
                                          pitches: ["4 Seam", "Screw"])

    private func call(_ pitch: String, _ target: String) -> PitchCall {
        let isStrike = target.hasPrefix("Strike ")
        let spot = String(target.dropFirst(isStrike ? 7 : 5))
        return PitchCall(pitch: pitch, location: spot, isStrike: isStrike, codes: [])
    }

    private func pitch(_ name: String, target: String, went: String) -> PitchEvent {
        PracticeRules.event(call: call(name, target), actualLabel: went, session: session, batterSide: .right)
    }

    // MARK: T7

    func testPracticePitchesSaveOnlyUnderTheSession() {
        let path = PracticeRules.eventsPath(uid: "coach", sessionId: "s1")
        XCTAssertEqual(path, "users/coach/practiceSessions/s1/pitchEvents")
        XCTAssertFalse(path.contains("/games/"), "never a game")
        XCTAssertFalse(path.hasPrefix("pitchers/"), "never the pitcher's career record")
        XCTAssertNotEqual(path, "users/coach/pitchEvents", "never the plain pitch list")
    }

    func testAPracticePitchIsATargetAndWhereItWent() {
        let event = pitch("Screw", target: "Strike Up", went: "Ball Up & In")
        XCTAssertNil(event.gameId)
        XCTAssertNil(event.opponentBatterId)
        XCTAssertNil(event.hitterId)
        XCTAssertNil(event.templateId, "no key")
        XCTAssertEqual(event.codes, [], "no codes")
        XCTAssertNil(event.outcome, "no swinging/looking/foul/ball - there's no batter")
        XCTAssertEqual(event.strikeSwinging, false)
        XCTAssertEqual(event.strikeLooking, false)
        XCTAssertEqual(event.location, "Ball Up & In")
        XCTAssertEqual(PracticeRules.targetLabel(event.calledPitch!), "Strike Up")
        XCTAssertEqual(event.isBall, true, "landed out of the zone")
        XCTAssertEqual(event.pitcherId, "p1")
    }

    func testASessionIsLabeledPractice() {
        let data = session.firestoreData
        XCTAssertEqual(data["label"] as? String, "Practice")
        XCTAssertEqual(PracticeSession(id: "s1", data: data)?.pitches, ["4 Seam", "Screw"])
        var game = data
        game["label"] = "Game"
        XCTAssertNil(PracticeSession(id: "s1", data: game))
    }

    // MARK: T8

    func testAPlayerAndAPitchAreRequired() {
        XCTAssertFalse(PracticeRules.canStart(pitcherId: nil, pitches: ["4 Seam"]))
        XCTAssertFalse(PracticeRules.canStart(pitcherId: "", pitches: ["4 Seam"]))
        XCTAssertFalse(PracticeRules.canStart(pitcherId: "p1", pitches: []))
        XCTAssertTrue(PracticeRules.canStart(pitcherId: "p1", pitches: ["4 Seam"]))
    }

    // MARK: T9

    func testEveryPitchTypeAndOnlyTheCheckedAreChips() {
        XCTAssertEqual(PracticeRules.availablePitches(), allPitches)
        XCTAssertEqual(PracticeRules.sessionPitches(available: allPitches, chosen: ["Screw", "4 Seam"]), ["4 Seam", "Screw"])
        XCTAssertEqual(PracticeRules.chipOptions(session: session), ["4 Seam", "Screw"])
        XCTAssertFalse(PracticeRules.showsCodes, "practice isn't linked to a key")
    }

    // MARK: T10 geometry

    func testEverySpotHasItsPlaceOnTheGrid() {
        XCTAssertEqual(PracticeGrid.cell("Strike Middle"), .init(row: 2, col: 2))
        XCTAssertEqual(PracticeGrid.cell("Strike Up & Out"), .init(row: 1, col: 1))
        XCTAssertEqual(PracticeGrid.cell("Strike ↓ & In"), .init(row: 3, col: 3))
        XCTAssertEqual(PracticeGrid.cell("Strike Out"), .init(row: 2, col: 1))
        XCTAssertEqual(PracticeGrid.cell("Ball Up"), .init(row: 0, col: 2))
        XCTAssertEqual(PracticeGrid.cell("Ball Up & In"), .init(row: 0, col: 4))
        XCTAssertEqual(PracticeGrid.cell("Ball ↓ & Out"), .init(row: 4, col: 0))
        XCTAssertEqual(PracticeGrid.cell("Ball In"), .init(row: 2, col: 4))
        XCTAssertNil(PracticeGrid.cell("Catcher"))
        // Every one of the 17 spots is distinct.
        let labels = ["Up & Out", "Up", "Up & In", "Out", "Middle", "In", "↓ & Out", "↓", "↓ & In"].map { "Strike \($0)" }
            + ["Up & Out", "Up", "Up & In", "Out", "In", "↓ & Out", "↓", "↓ & In"].map { "Ball \($0)" }
        XCTAssertEqual(Set(labels.compactMap(PracticeGrid.cell)).count, 17)
    }

    func testDistanceAndMissDirection() {
        let middle = PracticeGrid.cell("Strike Middle")!
        XCTAssertEqual(PracticeGrid.distance(middle, PracticeGrid.cell("Strike Up & In")!), 1, "diagonal neighbor")
        XCTAssertEqual(PracticeGrid.distance(PracticeGrid.cell("Strike Up")!, PracticeGrid.cell("Ball Up")!), 1, "just out of the zone")
        XCTAssertEqual(PracticeGrid.distance(middle, PracticeGrid.cell("Ball ↓")!), 2)
        let miss = PracticeGrid.miss(target: middle, actual: PracticeGrid.cell("Ball Up & In")!)
        XCTAssertEqual(miss, .init(high: true, low: false, inside: true, outside: false))
    }

    // MARK: T10 stats

    func testTheAccuracyStatsPerPitchAndForTheSession() {
        let events = [
            pitch("4 Seam", target: "Strike Up", went: "Strike Up"),          // on target
            pitch("4 Seam", target: "Strike Up", went: "Ball Up"),            // one away, missed high, out of zone
            pitch("4 Seam", target: "Strike ↓ & In", went: "Strike Middle"),  // one away, missed high + outside
            pitch("Screw", target: "Ball ↓ & In", went: "Strike Middle")      // two away, missed high + outside
        ]
        let summary = PracticeSummary(events: events, pitchOrder: session.pitches)

        XCTAssertEqual(summary.overall.thrown, 4)
        XCTAssertEqual(summary.overall.onTarget, 1)
        XCTAssertEqual(summary.overall.onTargetPercent, 25)
        XCTAssertEqual(summary.overall.withinOne, 3)
        XCTAssertEqual(summary.overall.withinOnePercent, 75)
        XCTAssertEqual(summary.overall.inZone, 3)
        XCTAssertEqual(summary.overall.zonePercent, 75)
        XCTAssertEqual(summary.overall.misses, 3)
        XCTAssertEqual(summary.overall.missedHigh, 3)
        XCTAssertEqual(summary.overall.missedLow, 0)
        XCTAssertEqual(summary.overall.missedOut, 2)
        XCTAssertEqual(summary.overall.missedIn, 0)

        XCTAssertEqual(summary.pitches.map(\.pitch), ["4 Seam", "Screw"])
        let fourSeam = summary.pitches[0]
        XCTAssertEqual(fourSeam.stats.thrown, 3)
        XCTAssertEqual(fourSeam.stats.onTargetPercent, 33)
        XCTAssertEqual(fourSeam.byTarget.first?.target, "Strike Up")
        XCTAssertEqual(fourSeam.byTarget.first?.thrown, 2)
        XCTAssertEqual(fourSeam.byTarget.first?.onTargetPercent, 50)

        XCTAssertEqual(summary.byTarget.first { $0.target == "Strike Up" }?.onTarget, 1)
        XCTAssertEqual(summary.byTarget.first { $0.target == "Ball ↓ & In" }?.onTargetPercent, 0)
        XCTAssertEqual(PracticeSummary(events: []).overall.onTargetPercent, 0, "an empty session reads 0")
    }
}
