//
//  PlayDraftTests.swift
//  PitchMarkTests
//
//  Phase 3 rules 10, 11, 15 and 16 as the pitch result sheet sees them:
//  the bases diamond on a wild pitch / passed ball, and what blocks Save.
//

import XCTest
@testable import PitchMark

@MainActor
final class PlayDraftTests: XCTestCase {
    private typealias F = Fixture
    private let twoAndThree = BaseOccupancy(second: Fixture.r2, third: Fixture.r3)

    /// Turning Wild Pitch on with runners aboard opens the runners-only diamond.
    func testWildPitchWithRunnersOpensRunnersOnlyDiamond() {
        var draft = PlayDraft(basesBefore: twoAndThree, isWildPitch: true)
        XCTAssertEqual(draft.wildPitchOrPassedBallChanged(), true)
        XCTAssertEqual(draft.runnersOnlyReason, .wildPitch)
    }

    /// With nobody on, Wild Pitch has nothing to move - the diamond stays shut.
    func testWildPitchWithEmptyBasesDoesNothing() {
        var draft = PlayDraft(basesBefore: .empty, isWildPitch: true)
        XCTAssertNil(draft.wildPitchOrPassedBallChanged())
        XCTAssertNil(draft.runnersOnlyReason)
        XCTAssertNil(draft.play)
    }

    /// Rule 10: the play saved with the pitch.
    func testWildPitchPlayMovesRunnersNotBatter() throws {
        let draft = PlayDraft(basesBefore: twoAndThree, runnerDestinations: [2: 3, 3: 4], isWildPitch: true)
        let play = try XCTUnwrap(draft.play)
        XCTAssertNil(play.batterMove)
        XCTAssertEqual(play.runs, 1)
        XCTAssertEqual(play.outs, 0)
        XCTAssertEqual(Set(play.moves.map(\.extraBasesOn)), ["WP"])
        XCTAssertNil(draft.conflict)
    }

    /// Passed ball takes precedence only when Wild Pitch is off.
    func testPassedBallReason() {
        let draft = PlayDraft(basesBefore: twoAndThree, runnerDestinations: [3: 4], isPassedBall: true)
        XCTAssertEqual(draft.runnersOnlyReason, .passedBall)
        XCTAssertEqual(draft.play?.moves.first?.extraBasesOn, "PB")
    }

    /// Rule 11: Wild Pitch on but nobody moved - no runner play is saved.
    func testWildPitchWithNoMovesSavesNoPlay() {
        let draft = PlayDraft(basesBefore: twoAndThree, runnerDestinations: [:], isWildPitch: true)
        XCTAssertNil(draft.play)
        let stayedPut = PlayDraft(basesBefore: twoAndThree, runnerDestinations: [2: 2, 3: 3], isWildPitch: true)
        XCTAssertNil(stayedPut.play, "moving a runner back to their own base is staying")
    }

    /// Rule 15: Save is blocked for a backward move, two on one base, or a pass.
    func testConflictsBlockSave() {
        let backward = PlayDraft(basesBefore: twoAndThree, runnerDestinations: [3: 2, 2: 1], isWildPitch: true)
        XCTAssertNotNil(backward.conflict, "runner going back a base")

        let shared = PlayDraft(basesBefore: twoAndThree, runnerDestinations: [2: 3], isWildPitch: true)
        XCTAssertNotNil(shared.conflict, "2nd moved to 3rd while 3rd stayed: two runners on 3rd")

        let passed = PlayDraft(basesBefore: BaseOccupancy(first: F.r1, second: F.r2),
                               runnerDestinations: [1: 3], isWildPitch: true)
        XCTAssertNotNil(passed.conflict, "runner from 1st passes the runner on 2nd")

        let fine = PlayDraft(basesBefore: twoAndThree, runnerDestinations: [2: 3, 3: 4], isWildPitch: true)
        XCTAssertNil(fine.conflict)
    }

    /// Rule 15 on a ball in play too: batter to 2nd while the runner on 2nd stays.
    func testConflictWithBatterPlaced() {
        let draft = PlayDraft(basesBefore: BaseOccupancy(second: F.r2), batterReachedBase: 2,
                              batterCredit: .double, runnerDestinations: [2: 2], selectedOutcome: "2B")
        XCTAssertNotNil(draft.conflict)
    }

    /// Rule 16: turning Wild Pitch off puts every runner back.
    func testTurningWildPitchOffResetsRunners() {
        var draft = PlayDraft(basesBefore: twoAndThree, runnerDestinations: [2: 3, 3: 4], isWildPitch: true)
        draft.isWildPitch = false
        XCTAssertEqual(draft.wildPitchOrPassedBallChanged(), false)
        XCTAssertEqual(draft.runnerDestinations, [:])
        XCTAssertNil(draft.play)
    }

    /// With the batter placed on a ball in play, the diamond isn't
    /// runners-only even if Wild Pitch is on.
    func testBallInPlayOverridesRunnersOnlyMode() {
        let draft = PlayDraft(basesBefore: twoAndThree, batterReachedBase: 1, batterCredit: .single,
                              runnerDestinations: [2: 2, 3: 4], selectedOutcome: "1B", isWildPitch: true)
        XCTAssertNil(draft.runnersOnlyReason)
        XCTAssertEqual(draft.play?.credit, .single)
        XCTAssertEqual(draft.play?.runs, 1)
    }
}
