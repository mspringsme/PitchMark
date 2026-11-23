//
//  HalfInningMemoryTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-21 (item 4, user's call: always ask): each batting
//  team's half-inning is kept when it stops batting; coming back to bat
//  mid-half-inning asks Keep or Reset; a clean board (e.g. after a third
//  out) starts fresh with no question.
//

import XCTest
@testable import PitchMark

final class HalfInningMemoryTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "halfInningTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    func testAskOnlyWhenTheTeamWasMidHalfInning() {
        XCTAssertEqual(HalfInningMemory.plan(saved: nil), .fresh, "never batted")
        XCTAssertEqual(HalfInningMemory.plan(saved: .fresh), .fresh, "ended clean - a third out resets the board")
        var mid = HalfInningState()
        mid.strikes = 2
        XCTAssertEqual(HalfInningMemory.plan(saved: mid), .ask(mid))
    }

    func testTheSummaryReadsLikeTheBoard() {
        var state = HalfInningState(balls: 1, strikes: 2, outs: 1)
        state.bases.first = BaseRunner(id: "r1", label: "#7")
        XCTAssertEqual(state.summary, "runner on 1st · 1-2 · 1 out")
        state.bases.third = BaseRunner(id: "r2", label: "#3")
        state.outs = 2
        XCTAssertEqual(state.summary, "runners on 1st, 3rd · 1-2 · 2 outs")
        state.bases.second = BaseRunner(id: "r3", label: "#9")
        XCTAssertEqual(state.summary, "bases loaded · 1-2 · 2 outs")
        XCTAssertEqual(HalfInningState.fresh.summary, "bases empty · 0-0 · 0 outs")
    }

    func testEachTeamsHalfInningIsKeptPerGame() {
        let store = defaults()
        var hawks = HalfInningState(balls: 3, strikes: 1, outs: 2)
        hawks.bases.second = BaseRunner(id: "r1", label: "#12", hitterId: "h12")
        HalfInningMemory.save(hawks, gameId: "g1", batting: .away, defaults: store)
        XCTAssertEqual(HalfInningMemory.load(gameId: "g1", batting: .away, defaults: store), hawks, "runner and all")
        XCTAssertNil(HalfInningMemory.load(gameId: "g1", batting: .home, defaults: store), "the other team's is separate")
        XCTAssertNil(HalfInningMemory.load(gameId: "g2", batting: .away, defaults: store), "another game's is separate")
    }
}
