//
//  GameProgress.swift
//  PitchMark
//
//  The runner-dependent part of the live scoreboard - bases, outs, and the
//  two scores - and every rule for how a saved game pitch or a between-pitch
//  runner event changes it, and how undo takes it back.
//
//  Pulled out of PitchTrackerView (2026-10-31) so it can be unit tested.
//  The tracker builds one of these from its state (`gameProgress`), calls a
//  mutating method, and writes the differences back through its normal
//  persistence paths (`commitGameProgress`) - so the live-room publish,
//  the owner's Game document and LocalProgressSnapshot are untouched.
//
//  Hits/walks counters and the count (balls/strikes) are NOT here: they
//  have their own writers and rules (AtBatCount.swift).
//
//  PitchMark target only (PitchEvent's stats helpers aren't in Display).
//

import Foundation

struct GameProgress: Equatable {
    enum Side: Equatable { case home, away }

    /// The event that made the third out, so undoing it can put back the
    /// outs from before it even after the board has reset to 0.
    struct ThirdOut: Equatable {
        var identity: String
        var previousOuts: Int?
    }

    var bases: BaseOccupancy = .empty
    var outs: Int = 0
    /// `us` on the tracker - the Home team's runs.
    var homeScore: Int = 0
    /// `them` on the tracker - the Away team's runs.
    var awayScore: Int = 0
    /// Who is pitching (`activeSide`). The other side is batting and gets
    /// the runs.
    var pitchingSide: Side = .home
    var lastThirdOut: ThirdOut? = nil

    /// The batting team's runs.
    var battingScore: Int {
        get { pitchingSide == .home ? awayScore : homeScore }
        set {
            if pitchingSide == .home { awayScore = newValue } else { homeScore = newValue }
        }
    }

    // MARK: - Outs

    /// Adds outs; the third out is remembered so undo can restore what was
    /// there before. The board stays at 3 until `completeThirdOut`.
    mutating func addOuts(_ made: Int, identity: String) {
        guard made > 0 else { return }
        let previousOuts = outs
        outs = min(3, outs + made)
        if outs >= 3 {
            lastThirdOut = ThirdOut(identity: identity, previousOuts: previousOuts)
        }
    }

    /// Takes back outs added for the event with `identity`.
    mutating func removeOuts(_ made: Int, identity: String) {
        guard made > 0 else { return }
        if let third = lastThirdOut, third.identity == identity {
            outs = third.previousOuts ?? max(0, 3 - made)
            lastThirdOut = nil
        } else {
            outs = max(0, outs - made)
        }
    }

    /// The side is retired: outs back to 0 and nobody stays on base. The
    /// tracker runs this after the short third-out flash.
    mutating func completeThirdOut() {
        outs = 0
        bases = .empty
    }

    // MARK: - Pitches

    /// Whether the pitch's outcome put the batter out (K, ꓘ, Out...).
    static func batterIsOut(_ event: PitchEvent) -> Bool {
        let normalizedOutcome = (event.outcome ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalizedOutcome.contains("out")
            || normalizedOutcome.contains("strikeout")
            || normalizedOutcome.contains("strike looking")
            || normalizedOutcome.contains("looking strike")
            || normalizedOutcome == "k"
            || normalizedOutcome == "ꓘ".lowercased() {
            return true
        }

        let countText = (event.atBatCount ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return countText.caseInsensitiveCompare("Out") == .orderedSame
            || countText.caseInsensitiveCompare("Strikeout") == .orderedSame
    }

    /// Outs a pitch made. A recorded play knows exactly (a double play is
    /// two, a fielder's choice is the runner, not the safe batter); without
    /// one, an out outcome is the batter's one out. A WP/PB play has no
    /// batter move, so a strikeout on that pitch still owes the batter's out.
    static func outsMade(by event: PitchEvent) -> Int {
        let batterOut = batterIsOut(event) ? 1 : 0
        guard let play = event.play else { return batterOut }
        return play.isRunnersOnly ? play.outs + batterOut : play.outs
    }

    /// The batter as a runner, so they keep their name on the bases.
    static func baseRunner(for event: PitchEvent) -> BaseRunner {
        let jersey = event.opponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let batterId = event.opponentBatterId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hitterId = event.hitterId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return BaseRunner(
            id: batterId.isEmpty ? jersey : batterId,
            label: jersey.isEmpty ? "B" : "#\(jersey)",
            hitterId: hitterId.isEmpty ? nil : hitterId
        )
    }

    /// Stamps who was on base onto a game pitch about to be saved, and gives
    /// a walk or hit-by-pitch its forced advances - those never visit the
    /// bases diamond, so nothing else would record them. A runners-only
    /// (WP/PB) play can still be ball four, and is merged rather than lost.
    static func stampBasePlay(on event: inout PitchEvent, bases: BaseOccupancy) {
        event.basesBefore = bases
        guard event.play == nil || event.play?.isRunnersOnly == true else { return }
        let terminal = HittingStatLine.terminal(
            facts: AtBatCountRules.PitchFacts(event: event),
            storedBalls: event.atBatBalls,
            storedStrikes: event.atBatStrikes,
            descriptor: event.descriptor
        )
        switch terminal {
        case .walk?:
            event.play = BaseRunnerRules.awardedFirstPlay(credit: .walk, before: bases, existing: event.play)
        case .hitByPitch?:
            event.play = BaseRunnerRules.awardedFirstPlay(credit: .hitByPitch, before: bases, existing: event.play)
        default:
            break
        }
    }

    /// A saved game pitch: its outs, then its runners and runs.
    mutating func applyPitch(_ event: PitchEvent) {
        addOuts(Self.outsMade(by: event), identity: event.identity)
        guard let play = event.play else { return }
        let result = BaseRunnerRules.resolve(play, before: event.basesBefore ?? bases, batter: Self.baseRunner(for: event))
        bases = result.after
        battingScore += result.runs
    }

    /// Undo of a saved pitch. The bases go back only when the pitch moved
    /// runners - undoing a plain strike must not wipe a runner added by hand
    /// since.
    mutating func undoPitch(_ event: PitchEvent) {
        removeOuts(Self.outsMade(by: event), identity: event.identity)
        guard let before = event.basesBefore, let play = event.play else { return }
        let runs = BaseRunnerRules.resolve(play, before: before, batter: Self.baseRunner(for: event)).runs
        battingScore = max(0, battingScore - runs)
        bases = before
    }

    // MARK: - The count after undo

    /// After undoing a pitch the count goes back to what the pitch before it
    /// left - its stored count, which `applyCount` already reset to 0-0 if
    /// that pitch ended an at-bat. No pitches left (or none with a stored
    /// count) means 0-0. `remainingNewestFirst` is the game's pitches with
    /// the undone one removed, newest first.
    static func countAfterUndo(remainingNewestFirst: [PitchEvent]) -> AtBatCount {
        guard let prior = remainingNewestFirst.first,
              let balls = prior.atBatBalls,
              let strikes = prior.atBatStrikes
        else { return .start }
        return AtBatCount(balls: balls, strikes: strikes)
    }

    /// The key a batter's in-progress count is remembered under: their
    /// lineup id, else their jersey.
    static func batterKey(batterId: String?, jersey: String?) -> String? {
        if let batterId, !batterId.isEmpty { return "id:\(batterId)" }
        let trimmed = jersey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : "jersey:\(trimmed)"
    }

    // MARK: - Between pitches

    /// Who/where/when a runner event is recorded, beyond the runner itself.
    struct RunnerEventContext: Equatable {
        var gameId: String?
        var pitcherId: String?
        var createdByUid: String?
        var inning: Int?
    }

    /// A steal, caught stealing, pickoff, advance or pinch runner. Returns
    /// the record to save, or nil when it can't happen (no runner there,
    /// next base taken, or a pinch runner with nobody named).
    mutating func recordRunnerEvent(
        _ kind: RunnerEventKind,
        from: Int,
        substitute: BaseRunner? = nil,
        id: String,
        timestamp: Date,
        context: RunnerEventContext
    ) -> RunnerEvent? {
        guard BaseRunnerRules.isAllowed(kind, from: from, bases: bases),
              let current = bases[from]
        else { return nil }
        if kind == .substitution && substitute == nil { return nil }
        let runner = kind == .substitution ? substitute! : current
        let event = RunnerEvent(
            id: id,
            timestamp: timestamp,
            kind: kind.rawValue,
            from: from,
            to: BaseRunnerRules.destination(for: kind, from: from),
            runner: runner,
            replaced: kind == .substitution ? current : nil,
            basesBefore: bases,
            gameId: context.gameId,
            pitcherId: context.pitcherId,
            hitterId: runner.hitterId,
            createdByUid: context.createdByUid,
            inning: context.inning
        )
        let result = BaseRunnerRules.apply(event)
        bases = result.after
        battingScore += result.runs
        addOuts(result.outs, identity: event.id)
        return event
    }

    mutating func undoRunnerEvent(_ event: RunnerEvent) {
        let result = BaseRunnerRules.apply(event)
        bases = event.basesBefore
        battingScore = max(0, battingScore - result.runs)
        removeOuts(result.outs, identity: event.id)
    }

    /// What the undo button reverses first: the newest runner event recorded
    /// on this device, if it came after the last pitch. Otherwise nil, and
    /// undo removes the pitch.
    static func runnerEventToUndo(sessionRunnerEvents: [RunnerEvent], lastPitchTimestamp: Date?) -> RunnerEvent? {
        guard let last = sessionRunnerEvents.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
        if let lastPitchTimestamp, lastPitchTimestamp > last.timestamp { return nil }
        return last
    }
}
