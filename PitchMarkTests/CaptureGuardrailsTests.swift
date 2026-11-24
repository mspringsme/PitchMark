//
//  CaptureGuardrailsTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-24 (clip brief, phase 2 guardrails):
//  1 flags: no doc = only interim sharing on; release-gated features stay
//    off even when the doc says true (HIGH RISK, broken on purpose); the
//    kill switch turns off feeds and alerts, not interim sharing
//  2 capture rules: window edges, refusal order, 7-day wait, 25th clip ok
//    and 26th refused
//  4 the Swift limits match functions/src/guardrails.ts
//

import XCTest
@testable import PitchMark

final class CaptureGuardrailsTests: XCTestCase {

    // MARK: 1 flags

    func testNoFlagsDocLeavesOnlyInterimSharingOn() {
        let flags = AppFeatureFlags(raw: nil)
        for feature in AppFeature.allCases {
            XCTAssertEqual(flags.isOn(feature), feature == .interimClipSharing, "\(feature)")
        }
    }

    func testReleaseGatedFeaturesStayOffEvenWhenTheDocSaysTrue() {
        var raw: [String: Any] = [:]
        for feature in AppFeature.allCases { raw[feature.rawValue] = true }
        let flags = AppFeatureFlags(raw: raw)
        XCTAssertFalse(AppFeatureFlags.releaseGateCleared)
        for feature in [AppFeature.cloudClips, .fullGameVideo, .viewerPass, .contentSafety] {
            XCTAssertFalse(flags.isOn(feature), "\(feature) must stay off until the release gate")
        }
        XCTAssertTrue(flags.isOn(.gameFeeds))
        XCTAssertTrue(flags.isOn(.followAlerts))
        XCTAssertTrue(flags.isOn(.interimClipSharing))
    }

    func testKillSwitchStopsFeedsAndAlertsButNotInterimSharing() {
        let flags = AppFeatureFlags(raw: ["gameFeeds": true, "followAlerts": true, "killSwitch": true])
        XCTAssertTrue(flags.killSwitchTripped)
        XCTAssertFalse(flags.isOn(.gameFeeds))
        XCTAssertFalse(flags.isOn(.followAlerts))
        XCTAssertTrue(flags.isOn(.interimClipSharing))
    }

    func testDocCanTurnInterimSharingOff() {
        XCTAssertFalse(AppFeatureFlags(raw: ["interimClipSharing": false]).isOn(.interimClipSharing))
        XCTAssertFalse(AppFeatureFlags(raw: ["interimClipSharing": false, "killSwitch": true]).isOn(.interimClipSharing))
    }

    func testUngatedFeaturesNeedAnExplicitTrue() {
        let flags = AppFeatureFlags(raw: ["gameFeeds": "yes"])
        XCTAssertFalse(flags.isOn(.gameFeeds))
        XCTAssertFalse(flags.isOn(.followAlerts))
    }

    // MARK: 2 capture rules

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testCaptureWindowEdges() {
        XCTAssertNotNil(CaptureGate.gameInWindow(starts: [start], now: start.addingTimeInterval(-30 * 60)))
        XCTAssertNil(CaptureGate.gameInWindow(starts: [start], now: start.addingTimeInterval(-30 * 60 - 1)))
        XCTAssertNotNil(CaptureGate.gameInWindow(starts: [start], now: start.addingTimeInterval(4 * 3600)))
        XCTAssertNil(CaptureGate.gameInWindow(starts: [start], now: start.addingTimeInterval(4 * 3600 + 1)))
        XCTAssertNil(CaptureGate.gameInWindow(starts: [], now: start))
    }

    func testCaptureWindowPicksTheNearestGame() {
        let second = start.addingTimeInterval(2 * 3600)
        let now = start.addingTimeInterval(110 * 60)
        XCTAssertEqual(CaptureGate.gameInWindow(starts: [start, second], now: now), second)
    }

    private func context(_ change: (inout CaptureGate.Context) -> Void = { _ in }) -> CaptureGate.Context {
        var c = CaptureGate.Context(
            feature: .gameFeeds,
            flags: AppFeatureFlags(raw: ["gameFeeds": true]),
            isApprovedMember: true,
            scoredGamesWithLineup: 1,
            accountCreatedAt: start.addingTimeInterval(-8 * 86_400),
            gameStarts: [start],
            clipsThisGame: 0,
            secondsThisGame: 0,
            now: start
        )
        change(&c)
        return c
    }

    func testEverythingInPlaceIsAllowed() {
        XCTAssertNil(CaptureGate.check(context()))
    }

    func testRefusalOrder() {
        let all = context {
            $0.flags = AppFeatureFlags(raw: nil)
            $0.isApprovedMember = false
            $0.scoredGamesWithLineup = 0
            $0.accountCreatedAt = nil
            $0.gameStarts = []
            $0.clipsThisGame = 99
        }
        XCTAssertEqual(CaptureGate.check(all), .featureOff)
        var c = all; c.flags = AppFeatureFlags(raw: ["gameFeeds": true])
        XCTAssertEqual(CaptureGate.check(c), .notApprovedMember)
        c.isApprovedMember = true
        XCTAssertEqual(CaptureGate.check(c), .teamNotUnlocked)
        c.scoredGamesWithLineup = 1
        XCTAssertEqual(CaptureGate.check(c), .accountInProbation)
        c.accountCreatedAt = start.addingTimeInterval(-8 * 86_400)
        XCTAssertEqual(CaptureGate.check(c), .noGameNow)
        c.gameStarts = [start]
        XCTAssertEqual(CaptureGate.check(c), .quotaReached)
    }

    func testGatedFeatureIsRefusedEvenWithEverythingElseInPlace() {
        let c = context { $0.feature = .cloudClips; $0.flags = AppFeatureFlags(raw: ["cloudClips": true]) }
        XCTAssertEqual(CaptureGate.check(c), .featureOff)
    }

    func testSevenDayWait() {
        XCTAssertTrue(CaptureGate.accountPastProbation(createdAt: start.addingTimeInterval(-7 * 86_400), now: start))
        XCTAssertFalse(CaptureGate.accountPastProbation(createdAt: start.addingTimeInterval(-7 * 86_400 + 1), now: start))
        XCTAssertFalse(CaptureGate.accountPastProbation(createdAt: nil, now: start))
    }

    func testTwentyFifthClipAllowedTwentySixthRefused() {
        XCTAssertNil(CaptureGate.check(context { $0.clipsThisGame = 24 }))
        XCTAssertEqual(CaptureGate.check(context { $0.clipsThisGame = 25 }), .quotaReached)
        XCTAssertNil(CaptureGate.check(context { $0.secondsThisGame = 599 }))
        XCTAssertEqual(CaptureGate.check(context { $0.secondsThisGame = 600 }), .quotaReached)
    }

    // MARK: 4 limits match the server

    func testLimitsMatchTheServer() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let ts = try String(contentsOf: root.appendingPathComponent("functions/src/guardrails.ts"), encoding: .utf8)
        XCTAssertTrue(ts.contains("maxClipSeconds: \(Int(CaptureLimits.maxClipSeconds)),"))
        XCTAssertTrue(ts.contains("perPersonPerGameClips: \(CaptureLimits.perPersonPerGameClips),"))
        XCTAssertTrue(ts.contains("perPersonPerGameSeconds: \(Int(CaptureLimits.perPersonPerGameSeconds / 60)) * 60,"))
        XCTAssertTrue(ts.contains("export const releaseGateCleared = \(AppFeatureFlags.releaseGateCleared);"))
        for feature in AppFeature.allCases where feature.isBehindReleaseGate {
            XCTAssertTrue(ts.contains("\"\(feature.rawValue)\""), "\(feature) is gated on the server too")
        }
    }
}
