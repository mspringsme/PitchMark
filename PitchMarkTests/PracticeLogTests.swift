//
//  PracticeLogTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-20 (practice running log, suggestion, archive/delete):
//  P1 the log's numbers are the review's (PracticeSummary); the latest
//     pitches are newest first with how each missed
//  P2 the suggestion rules: none under the minimums (5 of a pitch, 3 at a
//     spot), weakest pitch (tie → thrown more), a miss pattern only at 60%+,
//     hardest spot, strong session
//  P3 archive hides a session from the active list, Restore brings it
//     back, its pitches stay
//  P4 delete removes the session and every one of its pitches - pitches
//     first, the session last
//

import XCTest
@testable import PitchMark

@MainActor
final class PracticeLogTests: XCTestCase {

    private let session = PracticeSession(id: "s1", pitcherId: "p1", pitcherName: "Ava", templateId: nil,
                                          pitches: ["4 Seam", "Screw"])

    private func pitch(_ name: String, target: String, went: String) -> PitchEvent {
        let isStrike = target.hasPrefix("Strike ")
        let call = PitchCall(pitch: name, location: String(target.dropFirst(isStrike ? 7 : 5)), isStrike: isStrike, codes: [])
        return PracticeRules.event(call: call, actualLabel: went, session: session, batterSide: .right)
    }

    private func repeated(_ count: Int, _ name: String, target: String, went: String) -> [PitchEvent] {
        (0..<count).map { _ in pitch(name, target: target, went: went) }
    }

    // MARK: P1

    func testTheLatestPitchesAreNewestFirstWithTheirMiss() {
        let events = [
            pitch("4 Seam", target: "Strike Up", went: "Strike Up"),
            pitch("Screw", target: "Strike Middle", went: "Ball Up & In"),
            pitch("4 Seam", target: "Strike ↓", went: "Strike ↓ & Out")
        ]
        XCTAssertEqual(PracticeLog.recent(events), [
            "4 Seam → Strike ↓, went Strike ↓ & Out (out)",
            "Screw → Strike Middle, went Ball Up & In (high, in)",
            "4 Seam → Strike Up, went Strike Up (on target)"
        ])
        XCTAssertEqual(PracticeLog.recent(repeated(8, "Screw", target: "Strike Up", went: "Strike Up")).count, 5, "the last five")
    }

    func testEachPitchsMostCommonMiss() {
        let events = repeated(3, "Screw", target: "Strike Middle", went: "Strike Up")
            + repeated(1, "Screw", target: "Strike Middle", went: "Strike In")
        let stats = PracticeSummary(events: events).pitches[0].stats
        XCTAssertEqual(stats.mostCommonMiss?.direction, "high")
        XCTAssertEqual(stats.mostCommonMiss?.count, 3)
        XCTAssertNil(PracticeSummary(events: repeated(2, "4 Seam", target: "Strike Up", went: "Strike Up"))
            .pitches[0].stats.mostCommonMiss, "no misses, no direction")
    }

    // MARK: P2

    func testNoSuggestionUntilFiveOfAPitch() {
        let events = repeated(4, "Screw", target: "Strike Up", went: "Ball Up")
        XCTAssertEqual(PracticeSuggestion.lines(PracticeSummary(events: events)), ["Throw 5 of each pitch for a suggestion."])
    }

    func testTheWeakestPitchItsPatternAndTheHardestSpot() {
        let events = repeated(5, "4 Seam", target: "Strike Up", went: "Strike Up")              // 100%
            + repeated(1, "Screw", target: "Strike ↓ & Out", went: "Strike ↓ & Out")           // on
            + repeated(4, "Screw", target: "Strike ↓ & Out", went: "Strike Out")               // misses high
        let lines = PracticeSuggestion.lines(PracticeSummary(events: events, pitchOrder: ["4 Seam", "Screw"]))
        XCTAssertEqual(lines, [
            "Work on the Screw: 1 of 5 on target (20%).",
            "Most of its misses go high (4 of 4).",
            "Hardest spot: Strike ↓ & Out, 1 of 5."
        ])
    }

    func testAMissPatternOnlyAtSixtyPercent() {
        let events = repeated(1, "Screw", target: "Strike Middle", went: "Strike Middle")
            + repeated(2, "Screw", target: "Strike Middle", went: "Strike Up")
            + repeated(2, "Screw", target: "Strike Middle", went: "Strike ↓")
        let lines = PracticeSuggestion.lines(PracticeSummary(events: events))
        XCTAssertFalse(lines.contains { $0.hasPrefix("Most of its misses") }, "2 high, 2 low isn't a pattern")
    }

    func testATieGoesToThePitchThrownMore() {
        let events = repeated(5, "4 Seam", target: "Strike Up", went: "Ball Up")
            + repeated(6, "Screw", target: "Strike Up", went: "Ball Up")
        let lines = PracticeSuggestion.lines(PracticeSummary(events: events, pitchOrder: ["4 Seam", "Screw"]))
        XCTAssertEqual(lines.first, "Work on the Screw: 0 of 6 on target (0%).")
    }

    func testAStrongSession() {
        let events = repeated(5, "4 Seam", target: "Strike Up", went: "Strike Up")
            + repeated(3, "Screw", target: "Strike In", went: "Strike In")
            + repeated(2, "Screw", target: "Strike In", went: "Ball In")
        XCTAssertEqual(PracticeSuggestion.lines(PracticeSummary(events: events)),
                       ["Strong session. Try more corners and ball spots."])
    }

    // MARK: P3

    func testArchiveHidesAndRestoreReturnsKeepingThePitches() {
        let store = PracticeStore(currentUid: { nil })
        let older = PracticeSession(id: "s0", pitcherId: "p1", pitcherName: "Ava", templateId: nil, pitches: ["Screw"],
                                    startedAt: Date(timeIntervalSince1970: 0))
        store.create(older)
        store.create(session)
        store.save(pitch("Screw", target: "Strike Up", went: "Strike Up"), in: session)

        store.setArchived(true, session)
        var lists = PracticeRules.partition(store.sessions)
        XCTAssertEqual(lists.active.map(\.id), ["s0"])
        XCTAssertEqual(lists.archived.map(\.id), ["s1"])
        XCTAssertEqual(store.liveEvents["s1"]?.count, 1, "archiving keeps the pitches")

        store.setArchived(false, session)
        lists = PracticeRules.partition(store.sessions)
        XCTAssertEqual(lists.active.map(\.id), ["s1", "s0"], "newest first")
        XCTAssertTrue(lists.archived.isEmpty)
    }

    func testArchivedSurvivesASaveAndLoad() {
        var archived = session
        archived.archivedAt = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(PracticeSession(id: "s1", data: archived.firestoreData)?.archivedAt, archived.archivedAt)
        XCTAssertNil(PracticeSession(id: "s1", data: session.firestoreData)?.archivedAt)
    }

    // MARK: P4

    func testDeleteRemovesTheSessionAndEveryPitch() {
        let store = PracticeStore(currentUid: { nil })
        store.create(session)
        store.save(pitch("Screw", target: "Strike Up", went: "Strike Up"), in: session)
        store.save(pitch("Screw", target: "Strike Up", went: "Ball Up"), in: session)
        store.delete(session)
        XCTAssertFalse(store.sessions.contains { $0.id == "s1" })
        XCTAssertNil(store.liveEvents["s1"])
        XCTAssertFalse(store.removeLast(in: session), "nothing left to undo")
    }

    func testDeleteRemovesThePitchesBeforeTheSession() {
        let paths = PracticeRules.deletePaths(uid: "coach", sessionId: "s1", eventIds: ["e1", "e2"])
        XCTAssertEqual(paths, [
            "users/coach/practiceSessions/s1/pitchEvents/e1",
            "users/coach/practiceSessions/s1/pitchEvents/e2",
            "users/coach/practiceSessions/s1"
        ])
    }
}
