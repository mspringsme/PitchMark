//
//  TrackerKeysTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-21 (items 7 and 8): every pitcher starts on No Key in a
//  game - at the start and whenever the pitching changes - so a previous
//  pitcher's key never carries over; a reminder offers the pitcher's own
//  key. With No Key the chips are every pitch type (Unknown too in Track
//  Game, to guess the other team's pitch).
//

import XCTest
@testable import PitchMark

final class TrackerKeysTests: XCTestCase {

    func testAPitcherChangeResetsTheKey() {
        XCTAssertTrue(TrackerKeyRules.resetsKey(isGame: true, previousPitcherId: "hadley", newPitcherId: "lockport"))
        XCTAssertTrue(TrackerKeyRules.resetsKey(isGame: true, previousPitcherId: nil, newPitcherId: "cassie"),
                      "the first pitcher of a game")
        XCTAssertFalse(TrackerKeyRules.resetsKey(isGame: true, previousPitcherId: "cassie", newPitcherId: "cassie"),
                       "re-picking the same pitcher keeps her key")
        XCTAssertFalse(TrackerKeyRules.resetsKey(isGame: false, previousPitcherId: "a", newPitcherId: "b"),
                       "outside a game nothing changes")
    }

    func testNoKeyOffersEveryPitchType() {
        XCTAssertEqual(TrackerKeyRules.noKeyChips(mode: .scout), allPitches + ["Unknown"], "guess the opponent's pitch")
        XCTAssertEqual(TrackerKeyRules.noKeyChips(mode: .coach), [""] + allPitches, "Catcher chip first when calling")
    }

    func testTheReminderOffersThePitchersOwnKey() {
        let own = TrackerKeyRules.reminder(pitcherName: "Cassie", ownKey: ("k1", "Cassie Key"))
        XCTAssertEqual(own.title, "No key for Cassie")
        XCTAssertEqual(own.ownKeyId, "k1")
        XCTAssertTrue(own.message.contains("Use Cassie Key"))
        let none = TrackerKeyRules.reminder(pitcherName: "Lockport #12", ownKey: nil)
        XCTAssertNil(none.ownKeyId)
        XCTAssertTrue(none.message.contains("Choose a key"))
    }
}
