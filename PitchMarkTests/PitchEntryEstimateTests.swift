//
//  PitchEntryEstimateTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-21 (follow-up to items 7-9): the estimate step in Track
//  Game and for Catcher calls, chip deselect / clear, and No Key surviving
//  automatic key restores.
//

import XCTest
@testable import PitchMark

final class PitchEntryEstimateTests: XCTestCase {
    // (1) A Track Game tap with no chip, or a Catcher pick carried over,
    // records Unknown - never a hidden Catcher call.
    func testTrackGameNeverRecordsACatcherCall() {
        XCTAssertEqual(PitchEntryFlow.trackedPitch(chip: ""), PitchEvent.unknownPitch)
        XCTAssertEqual(PitchEntryFlow.trackedPitch(chip: "Catcher"), PitchEvent.unknownPitch)
        XCTAssertEqual(PitchEntryFlow.trackedPitch(chip: " Curve "), "Curve")
    }

    // (2) The estimate shows for every Track Game pitch and a Catcher call,
    // never for another Call Pitches pitch.
    func testWhenTheEstimateShows() {
        XCTAssertTrue(PitchEntryFlow.showsEstimate(mode: .scout, callPitch: "Curve"))
        XCTAssertTrue(PitchEntryFlow.showsEstimate(mode: .scout, callPitch: PitchEvent.unknownPitch))
        XCTAssertTrue(PitchEntryFlow.showsEstimate(mode: .coach, callPitch: "Catcher"))
        XCTAssertFalse(PitchEntryFlow.showsEstimate(mode: .coach, callPitch: "Curve"))
    }

    // (3) Done needs a spot for the catcher's estimate, not in Track Game.
    func testDoneNeedsASpotOnlyForTheCatcher() {
        XCTAssertFalse(PitchEntryFlow.estimateCanFinish(mode: .coach, draftLocation: nil))
        XCTAssertTrue(PitchEntryFlow.estimateCanFinish(mode: .coach, draftLocation: "Strike Up"))
        XCTAssertTrue(PitchEntryFlow.estimateCanFinish(mode: .scout, draftLocation: nil))
    }

    // (4) Tapping the picked chip deselects it.
    func testTappingThePickedChipDeselectsIt() {
        XCTAssertEqual(PitchEntryFlow.chipAfterTap(current: "Curve", tapped: "Curve"), "")
        XCTAssertEqual(PitchEntryFlow.chipAfterTap(current: "Curve", tapped: "Drop"), "Drop")
        XCTAssertEqual(PitchEntryFlow.chipAfterTap(current: "", tapped: "Drop"), "Drop")
    }

    // (5) Track Game clears the chip after each pitch; Call Pitches keeps it.
    func testTrackGameStartsEachPitchWithNoChip() {
        XCTAssertEqual(PitchEntryFlow.chipAfterSave(current: "Curve", mode: .scout), "")
        XCTAssertEqual(PitchEntryFlow.chipAfterSave(current: "Curve", mode: .coach), "Curve")
    }

    // (6) No "Strike Strike Middle".
    func testASpotLosesItsStrikeOrBallWord() {
        XCTAssertEqual(PitchEntryFlow.bareLocation("Strike Middle"), "Middle")
        XCTAssertEqual(PitchEntryFlow.bareLocation("Ball Up & In"), "Up & In")
        XCTAssertEqual(PitchEntryFlow.bareLocation("Middle"), "Middle")
    }

    // (10) No Key survives the game's key being put back on reload.
    func testAnAutomaticRestoreKeepsNoKey() {
        XCTAssertFalse(TrackerKeyRules.applyingKeyEndsNoKey(pickedByUser: false, isGame: true, isOwner: true),
                       "the coach's own game: a restore leaves No Key alone")
        XCTAssertTrue(TrackerKeyRules.applyingKeyEndsNoKey(pickedByUser: true, isGame: true, isOwner: true),
                      "picking a key ends it")
        XCTAssertTrue(TrackerKeyRules.applyingKeyEndsNoKey(pickedByUser: false, isGame: true, isOwner: false),
                      "a live partner follows the coach's key")
        XCTAssertTrue(TrackerKeyRules.gameStartsOnNoKey(isOwner: true))
        XCTAssertFalse(TrackerKeyRules.gameStartsOnNoKey(isOwner: false))
    }

    // Track Game never uses a key; Call Pitches keeps the coach's choice.
    func testTrackGameUsesNoKey() {
        XCTAssertTrue(TrackerKeyRules.keyIsOff(noKey: false, mode: .scout))
        XCTAssertFalse(TrackerKeyRules.keyIsOff(noKey: false, mode: .coach), "the key comes back")
        XCTAssertTrue(TrackerKeyRules.keyIsOff(noKey: true, mode: .coach))
        XCTAssertFalse(TrackerKeyRules.showsKeyReminder(mode: .scout))
        XCTAssertTrue(TrackerKeyRules.showsKeyReminder(mode: .coach))
    }
}
