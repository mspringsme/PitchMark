//
//  PlayDraft.swift
//  PitchMark
//
//  The pitch result sheet's bases-diamond answers, and the rules that turn
//  them into a `BasePlay` (or say why they can't). Pulled out of
//  PitchResultSheetView (2026-10-31) so it can be unit tested; the sheet
//  builds one from its @State and reads the results.
//
//  Compiled into the Display target too (PitchResultsSheetView is), so it is
//  listed in that target's membershipExceptions.
//

import Foundation

struct PlayDraft: Equatable {
    /// Who was on base before this pitch.
    var basesBefore: BaseOccupancy = .empty
    var batterReachedBase: Int? = nil
    var batterCredit: BatterCredit? = nil
    var batterExtraBasesOn: ExtraBasesReason? = nil
    /// Where each runner ended up, keyed by start base; no entry = stayed.
    var runnerDestinations: [Int: Int] = [:]
    /// The sheet's selected outcome ("Out", "1B"...).
    var selectedOutcome: String? = nil
    var isWildPitch: Bool = false
    var isPassedBall: Bool = false

    /// Batter put out on the ball in play (not safe on a fielder's choice,
    /// which also stores "Out").
    var isBatterOutOnPlay: Bool {
        selectedOutcome == "Out" && batterReachedBase == nil
    }

    /// Wild pitch / passed ball with runners on and no ball in play: the
    /// diamond moves runners only.
    var runnersOnlyReason: ExtraBasesReason? {
        guard !basesBefore.isEmpty, batterReachedBase == nil, !isBatterOutOnPlay else { return nil }
        if isWildPitch { return .wildPitch }
        if isPassedBall { return .passedBall }
        return nil
    }

    /// Why the batter's and runners' end bases can't all be true, if so.
    /// Save is blocked while this is non-nil.
    var conflict: String? {
        guard !basesBefore.isEmpty else { return nil }
        let runners = basesBefore.occupiedBases.map { (from: $0, to: runnerDestinations[$0] ?? $0) }
        if let reached = batterReachedBase {
            return BaseRunnerRules.conflict([(from: Base.home, to: reached)] + runners)
        }
        if isBatterOutOnPlay {
            return BaseRunnerRules.conflict([(from: Base.home, to: Base.out)] + runners)
        }
        if runnersOnlyReason != nil {
            return BaseRunnerRules.conflict(runners)
        }
        return nil
    }

    /// The play these answers describe, or nil while unanswered/incomplete
    /// (or when nothing moved on a wild pitch).
    var play: BasePlay? {
        let runnerMoves = BaseRunnerRules.runnerMoves(before: basesBefore, destinations: runnerDestinations)
        if let reached = batterReachedBase, let credit = batterCredit {
            guard BaseRunnerRules.isComplete(credit: credit, reached: reached, extraBasesOn: batterExtraBasesOn)
            else { return nil }
            return BaseRunnerRules.makePlay(credit: credit, reached: reached, extraBasesOn: batterExtraBasesOn,
                                            runnerMoves: runnerMoves)
        }
        // Batter out with runners on: still a play, so the runners' moves
        // and outs (double play, sac fly) are recorded.
        if isBatterOutOnPlay && !basesBefore.isEmpty {
            return BaseRunnerRules.makePlay(credit: .out, reached: Base.out, extraBasesOn: nil,
                                            runnerMoves: runnerMoves)
        }
        if let reason = runnersOnlyReason {
            return BaseRunnerRules.runnersOnlyPlay(before: basesBefore, destinations: runnerDestinations, reason: reason)
        }
        return nil
    }

    /// The batter's base changed: runners start from the minimum it forces.
    mutating func batterBaseChanged() {
        runnerDestinations = BaseRunnerRules.defaultDestinations(before: basesBefore, batterTo: batterReachedBase)
    }

    /// Who a fielder's choice puts out: the lead forced runner (bases
    /// loaded: the runner from 3rd), or the lead runner when nobody was
    /// forced. nil with nobody on.
    var fieldersChoiceRunner: Int? {
        let occupied = basesBefore.occupiedBases
        var forced: Int? = nil
        var base = Base.first
        while occupied.contains(base) {
            forced = base
            base += 1
        }
        return forced ?? occupied.max()
    }

    /// The credit changed from `old`. Picking a fielder's choice means the
    /// defense got someone else, so that runner (`fieldersChoiceRunner`)
    /// goes out unless the user already put a runner out. Leaving it
    /// sends that runner back to where the batter's base put them.
    mutating func batterCreditChanged(from old: BatterCredit?) {
        guard let runner = fieldersChoiceRunner else { return }
        if batterCredit == .fieldersChoice {
            guard !runnerDestinations.values.contains(Base.out) else { return }
            runnerDestinations[runner] = Base.out
        } else if old == .fieldersChoice, runnerDestinations[runner] == Base.out {
            runnerDestinations[runner] = BaseRunnerRules.defaultDestinations(before: basesBefore, batterTo: batterReachedBase)[runner]
        }
    }

    /// Wild Pitch or Passed Ball toggled. Returns true to open the bases
    /// diamond, false to close it, nil to leave it - and turning both off
    /// puts every runner back where they started.
    mutating func wildPitchOrPassedBallChanged() -> Bool? {
        guard !basesBefore.isEmpty, batterReachedBase == nil, !isBatterOutOnPlay else { return nil }
        if isWildPitch || isPassedBall { return true }
        runnerDestinations = [:]
        return false
    }
}
