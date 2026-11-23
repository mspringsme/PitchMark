//
//  KeyMemoryTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-22 (item 2): each pitcher's key choice is remembered
//  for the game, so the No Key pop-up doesn't come back every half inning.
//

import XCTest
@testable import PitchMark

final class KeyMemoryTests: XCTestCase {
    typealias Rules = TrackerKeyRules

    // (1) Back after a side switch (the switch clears the pitcher, so there
    // is no previous one): the remembered choice comes back, no pop-up.
    func testAPitcherBackFromASideSwitchKeepsTheirChoice() {
        XCTAssertEqual(Rules.planForPitcher(previousPitcherId: nil, newPitcherId: "cassie",
                                            remembered: .noKey, rememberedKeyExists: false),
                       .restore(.noKey))
        XCTAssertEqual(Rules.planForPitcher(previousPitcherId: nil, newPitcherId: "cassie",
                                            remembered: .key("k1"), rememberedKeyExists: true),
                       .restore(.key("k1")))
    }

    // (2) First time in: asked. A remembered key that's gone counts as none.
    func testANewPitcherIsAsked() {
        XCTAssertEqual(Rules.planForPitcher(previousPitcherId: "cassie", newPitcherId: "kenzie",
                                            remembered: nil, rememberedKeyExists: false), .ask)
        XCTAssertEqual(Rules.planForPitcher(previousPitcherId: nil, newPitcherId: "kenzie",
                                            remembered: .key("deleted"), rememberedKeyExists: false), .ask)
        XCTAssertEqual(Rules.planForPitcher(previousPitcherId: "kenzie", newPitcherId: "kenzie",
                                            remembered: nil, rememberedKeyExists: false), .keep,
                       "picking the same pitcher again changes nothing")
    }

    // (3) A pitching change on the same side forgets the replaced pitcher;
    // a side switch forgets no one.
    func testAReplacedPitchersChoiceIsForgotten() {
        XCTAssertEqual(Rules.replacedPitcher(previousPitcherId: "cassie", newPitcherId: "kenzie", sameSide: true), "cassie")
        XCTAssertNil(Rules.replacedPitcher(previousPitcherId: "cassie", newPitcherId: "hawks1", sameSide: false))
        XCTAssertNil(Rules.replacedPitcher(previousPitcherId: nil, newPitcherId: "kenzie", sameSide: true))
    }

    // (4) The stored form round-trips, and a choice can be changed or cleared.
    func testChoicesAreKeptPerPitcherAndCanChange() {
        XCTAssertEqual(Rules.KeyChoice(stored: Rules.KeyChoice.noKey.stored), .noKey)
        XCTAssertEqual(Rules.KeyChoice(stored: Rules.KeyChoice.key("k1").stored), .key("k1"))
        XCTAssertNil(Rules.KeyChoice(stored: nil))
        XCTAssertNil(Rules.KeyChoice(stored: "key:"))

        var memory = TrackerSelectionMemory()
        memory.setKeyChoice("nokey", for: "cassie")
        memory.setKeyChoice("key:k1", for: "kenzie")
        memory.setKeyChoice("key:k2", for: "cassie")
        XCTAssertEqual(memory.keyChoice(for: "cassie"), "key:k2", "the latest pick wins")
        XCTAssertEqual(memory.keyChoice(for: "kenzie"), "key:k1")
        memory.setKeyChoice(nil, for: "kenzie")
        XCTAssertNil(memory.keyChoice(for: "kenzie"))
    }

    func testOlderMemoriesStillLoad() throws {
        let old = #"{"pitchingSide":"home","sides":{"home":{"pitcherId":"cassie"}}}"#
        let memory = try JSONDecoder().decode(TrackerSelectionMemory.self, from: Data(old.utf8))
        XCTAssertEqual(memory.pitcherId(for: .home), "cassie")
        XCTAssertNil(memory.keyChoice(for: "cassie"))
    }
}
