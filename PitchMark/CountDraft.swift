//
//  CountDraft.swift
//  PitchMark
//
//  The pitch result sheet's count: the count before this pitch (the seed),
//  an optional hand correction, and when a change may be published to the
//  tracker. The count shown is always *derived* - seed + current selection
//  through AtBatCountRules - never accumulated, so changing a selection
//  replaces its effect instead of stacking it.
//
//  Pulled out of PitchResultSheetView (2026-10-31) so it can be unit tested.
//  Compiled into the Display target too (PitchResultsSheetView is), so it is
//  listed in that target's membershipExceptions.
//

import Foundation

struct CountDraft: Equatable {
    /// The count before this pitch.
    var seed: AtBatCount = .start
    /// Set only when the user taps the count circles by hand. Kept apart from
    /// the seed so the pitch rules never add the pitch on top a second time.
    var manualOverride: AtBatCount? = nil
    /// True once seeded for the current presentation of the sheet.
    private(set) var isSeeded = false

    /// Where the next pitch's count starts, best source first: when editing a
    /// saved pitch, the count it was thrown at; else the active batter's last
    /// saved pitch (its stored count is already the reset 0-0 after an at-bat
    /// ended), else the tracker's live count, else the per-batter memory,
    /// else 0-0.
    static func seed(
        editedPitchSeed: AtBatCount? = nil,
        lastSavedPitchCount: (balls: Int?, strikes: Int?)?,
        liveCount: (balls: Int, strikes: Int)?,
        rememberedCount: (balls: Int, strikes: Int)?
    ) -> AtBatCount {
        if let editedPitchSeed { return editedPitchSeed }
        if let saved = lastSavedPitchCount, let balls = saved.balls, let strikes = saved.strikes {
            return AtBatCount(balls: balls, strikes: strikes)
        }
        let fallback = liveCount ?? rememberedCount ?? (0, 0)
        return AtBatCount(balls: fallback.balls, strikes: fallback.strikes)
    }

    /// The sheet opened: start from `seed` with no correction.
    mutating func open(seed: AtBatCount) {
        self.seed = seed
        manualOverride = nil
        isSeeded = true
    }

    /// The sheet closed (or is about to re-seed).
    mutating func close() {
        manualOverride = nil
        isSeeded = false
    }

    /// The Refresh button: back to 0-0, no correction.
    mutating func resetToStart() {
        seed = .start
        manualOverride = nil
    }

    /// The count shown in the sheet and written onto the saved pitch.
    func resolved(_ facts: AtBatCountRules.PitchFacts) -> AtBatCount {
        manualOverride ?? AtBatCountRules.apply(facts, to: seed).count
    }

    /// How the at-bat ended on this pitch, if it did. A hand-corrected count
    /// is the user stating the result directly, so nothing is inferred.
    func terminal(_ facts: AtBatCountRules.PitchFacts) -> AtBatTerminal? {
        guard manualOverride == nil else { return nil }
        return AtBatCountRules.apply(facts, to: seed).terminal
    }

    /// A ball circle tapped by hand: tapping the filled value steps down by
    /// one, any other value sets it.
    mutating func tapBall(_ value: Int, facts: AtBatCountRules.PitchFacts) {
        let current = resolved(facts)
        let next = current.balls == value ? max(0, value - 1) : value
        manualOverride = AtBatCount(balls: next, strikes: current.strikes)
    }

    mutating func tapStrike(_ value: Int, facts: AtBatCountRules.PitchFacts) {
        let current = resolved(facts)
        let next = current.strikes == value ? max(0, value - 1) : value
        manualOverride = AtBatCount(balls: current.balls, strikes: next)
    }

    /// Whether a change to the shown count goes out to the tracker. Only
    /// while the sheet is open and seeded: tearing it down clears the
    /// selection, the shown count falls back to the pre-pitch seed, and
    /// publishing that would overwrite the count the save just committed.
    func shouldPublish(isPresented: Bool) -> Bool {
        isPresented && isSeeded
    }
}
