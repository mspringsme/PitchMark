//
//  CardLinesTests.swift
//  PitchMarkTests
//
//  Rules 57-60 (approved 2026-11-05): the pitch card's result box says
//  each thing once, so a typical play fits its 2-3 lines.
//

import XCTest
@testable import PitchMark

final class CardLinesTests: XCTestCase {
    private typealias F = Fixture

    private func play(_ credit: BatterCredit, to base: Int, on reason: ExtraBasesReason? = nil,
                      runners: [RunnerMove] = []) -> BasePlay {
        BasePlay(batterCredit: credit.rawValue,
                 moves: [RunnerMove(runner: RunnerMove.batterKey, from: Base.home, to: base,
                                    extraBasesOn: reason?.rawValue)] + runners)
    }

    private func scored(from base: Int) -> RunnerMove {
        RunnerMove(runner: "r\(base)", from: base, to: Base.scored, extraBasesOn: nil)
    }

    /// Rule 57: the screenshot's double - two lines, nothing repeated.
    func testScreenshotDoubleIsTwoLines() {
        var event = F.pitch(isStrike: true, outcome: "2B", play: play(.double, to: Base.second))
        event.descriptor = "Line, Hit"
        event.battedBallRegion = "Deep Right"
        XCTAssertEqual(outcomeSummaryLines(for: event), ["2B", "Line · Deep Right"])

        // The stored outcome ("1B") differs from the play line; still not repeated.
        var extra = F.pitch(isStrike: true, outcome: "1B", play: play(.single, to: Base.second, on: .error))
        extra.errorOnPlay = true
        XCTAssertEqual(outcomeSummaryLines(for: extra), ["1B + E · Safe at 2nd"])
    }

    /// Rule 58: "Safe at" only when the credit doesn't say the base.
    func testCardSummary() {
        XCTAssertEqual(BaseRunnerRules.cardSummary(for: play(.single, to: Base.second, on: .error,
                                                             runners: [scored(from: 3)])),
                       "1B + E · Safe at 2nd · 1 run")
        XCTAssertEqual(BaseRunnerRules.cardSummary(for: play(.reachedOnError, to: Base.first)), "ROE · Safe at 1st")
        XCTAssertEqual(BaseRunnerRules.cardSummary(for: play(.homeRun, to: Base.scored,
                                                             runners: [scored(from: 1), scored(from: 2)])),
                       "HR · 3 runs")
        XCTAssertEqual(BaseRunnerRules.cardSummary(for: play(.homeRun, to: Base.scored)), "HR")
        XCTAssertEqual(BaseRunnerRules.cardSummary(for: play(.double, to: Base.second)), "2B")
        XCTAssertEqual(BaseRunnerRules.cardSummary(for: play(.single, to: Base.third, on: .onThrow)),
                       "1B + throw · Safe at 3rd")
    }

    /// Rule 59: an out with a runner on says "Out" once and keeps 6-3.
    func testOutWithRunnerSaysOutOnce() {
        var event = F.pitch(isStrike: true, outcome: "Out",
                            play: play(.out, to: Base.out, runners: [RunnerMove(runner: "r1", from: 1, to: Base.second, extraBasesOn: nil)]),
                            basesBefore: BaseOccupancy(first: F.r1))
        event.fieldingOuts = [FieldingOut(runner: FieldingPlay.batterKey, positions: ["SS", "1B"])]
        let lines = outcomeSummaryLines(for: event)
        XCTAssertEqual(lines.filter { $0.lowercased().hasPrefix("out") }.count, 1, "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("6-3") }, "\(lines)")

        // A fielder's choice is stored as "Out" - the card says FC, not Out.
        let fc = F.pitch(isStrike: true, outcome: "Out",
                         play: play(.fieldersChoice, to: Base.first,
                                    runners: [RunnerMove(runner: "r1", from: 1, to: Base.out, extraBasesOn: nil)]),
                         basesBefore: BaseOccupancy(first: F.r1))
        XCTAssertEqual(outcomeSummaryLines(for: fc), ["FC · Safe at 1st · runner out"])
    }

    /// Rule 60: a pitch with no play still shows its result.
    func testOldPitchKeepsItsOutcome() {
        var event = F.pitch(isStrike: true, outcome: "1B")
        event.battedBallRegion = "Left"
        XCTAssertEqual(outcomeSummaryLines(for: event), ["1B", "Left"])
    }
}
