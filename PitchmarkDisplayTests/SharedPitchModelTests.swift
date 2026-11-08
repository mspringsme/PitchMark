//
//  SharedPitchModelTests.swift
//  PitchmarkDisplayTests
//
//  The Display app compiles the shared pitch model (CalledPitchRecord.swift,
//  BaseRunnerRules.swift, PlayDraft.swift). These check it reads pitches
//  written by a PitchMark build with runners - and still reads older
//  pitches without them.
//

import XCTest
@testable import Pitchmark_Display

@MainActor
final class SharedPitchModelTests: XCTestCase {
    private func baseData() -> [String: Any] {
        [
            "timestamp": Date(timeIntervalSince1970: 1_000),
            "pitch": "4 Seam",
            "location": "Strike Middle",
            "isStrike": true,
            "mode": "game"
        ]
    }

    func testDecodesPlayAndBasesBefore() throws {
        var data = baseData()
        data["outcome"] = "1B"
        data["play"] = [
            "batterCredit": "1B",
            "moves": [
                ["runner": "batter", "from": 0, "to": 1],
                ["runner": "cell-2", "from": 2, "to": 4]
            ]
        ]
        data["basesBefore"] = ["second": ["id": "cell-2", "label": "#2", "hitterId": "h2"]]

        let event = try XCTUnwrap(PitchEvent(legacyData: data, documentId: "p1"))
        let play = try XCTUnwrap(event.play)
        XCTAssertEqual(play.credit, .single)
        XCTAssertEqual(play.batterMove?.to, 1)
        XCTAssertEqual(play.runs, 1, "the runner from 2nd scored")
        XCTAssertEqual(event.basesBefore, BaseOccupancy(second: BaseRunner(id: "cell-2", label: "#2", hitterId: "h2")))
        XCTAssertEqual(BaseRunnerRules.summary(for: play), "Safe at 1st — 1B · 1 run")
    }

    func testDecodesRunnersOnlyWildPitchPlay() throws {
        var data = baseData()
        data["wildPitch"] = true
        data["play"] = [
            "batterCredit": "",
            "moves": [["runner": "cell-3", "from": 3, "to": 4, "extraBasesOn": "WP"]]
        ]
        let event = try XCTUnwrap(PitchEvent(legacyData: data, documentId: "p2"))
        let play = try XCTUnwrap(event.play)
        XCTAssertTrue(play.isRunnersOnly)
        XCTAssertEqual(BaseRunnerRules.summary(for: play), "Wild pitch · 1 run")
    }

    func testOlderPitchWithoutRunnersStillDecodes() throws {
        let event = try XCTUnwrap(PitchEvent(legacyData: baseData(), documentId: "p3"))
        XCTAssertNil(event.play)
        XCTAssertNil(event.basesBefore)
        XCTAssertEqual(event.pitch, "4 Seam")
        XCTAssertEqual(event.location, "Strike Middle")
    }

    /// A runner written before hitterId existed still reads.
    func testRunnerWithoutHitterIdDecodes() throws {
        var data = baseData()
        data["basesBefore"] = ["first": ["id": "", "label": "R"]]
        let event = try XCTUnwrap(PitchEvent(legacyData: data, documentId: "p4"))
        XCTAssertEqual(event.basesBefore?.first, .manual)
    }
}
