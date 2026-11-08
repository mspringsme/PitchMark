//
//  HittingStatLine.swift
//  PitchMark
//
//  A batter's traditional line (PA, AB, H, 2B/3B/HR, BB, HBP, K, AVG, OBP)
//  computed from the pitches they saw. Deliberately small - a starting point
//  for a fuller hitting-stats system, not the system itself.
//
//  How an at-bat's end is found, without replaying a game or reading the
//  display label (`atBatCount` is display-only, see CLAUDE.md):
//
//  - An explicit outcome (K/ꓘ, Walk, HBP, Out, 1B/2B/3B/HR/Hit) is classified
//    by `AtBatCountRules.effect`, the same rule the count itself uses.
//  - A third strike or fourth ball usually carries no outcome. But
//    `applyCount` - the only writer of the numeric count - stamps every
//    terminal pitch 0-0, and a plain strike or ball can't otherwise *leave*
//    the count at 0-0. So a strike/ball stored at 0-0 ended the at-bat.
//
//  - The pitch sheet's "Hit" tag is saved in `descriptor`, not `outcome`
//    (outcome stays nil unless Out/1B/... was also picked), so with no
//    explicit outcome a "Hit" descriptor token is read as a hit - matching
//    what the sheet's own count preview did with it. Without this, the
//    tagged pitch (forced to a strike, stored 0-0) read as a strikeout.
//
//  - A hit with an error on the play is reached-on-error, not a hit (same
//    rule as `pitchEventIsCreditedHit`): an at-bat, no hit, its own ROE
//    column, and not on base for OBP.
//
//  Not modelled yet: sacrifices, catcher's interference.
//

import Foundation

struct HittingStatLine: Equatable {
    var plateAppearances = 0
    var atBats = 0
    var hits = 0
    var doubles = 0
    var triples = 0
    var homeRuns = 0
    var walks = 0
    var hitByPitch = 0
    var strikeouts = 0
    var reachedOnError = 0
    /// Between-pitch running (RunnerEvent), counted separately from the
    /// plate appearances above.
    var stolenBases = 0
    var caughtStealing = 0
    var pickedOff = 0
    /// Runs this player scored - as the batter (a home run) or as a runner
    /// on someone else's pitch or between pitches.
    var runs = 0
    /// Runs batted in (`HittingStatLine.runsBattedIn(for:)`).
    var runsBattedIn = 0

    /// Hits recorded with a specific base (1B/2B/3B/HR) vs. the generic
    /// "Hit" tag. Total bases - and so SLG - is only meaningful when every
    /// hit says which.
    var unspecifiedHits = 0

    var singles: Int { hits - doubles - triples - homeRuns - unspecifiedHits }

    var average: Double? {
        atBats > 0 ? Double(hits) / Double(atBats) : nil
    }

    /// (H + BB + HBP) / PA - sacrifice flies aren't tracked, so PA stands in
    /// for AB + BB + HBP + SF.
    var onBase: Double? {
        plateAppearances > 0 ? Double(hits + walks + hitByPitch) / Double(plateAppearances) : nil
    }

    var slugging: Double? {
        guard atBats > 0, unspecifiedHits == 0 else { return nil }
        let totalBases = singles + 2 * doubles + 3 * triples + 4 * homeRuns
        return Double(totalBases) / Double(atBats)
    }

    /// ".333" - baseball's rate format; "1.000" at the top end, "—" with no
    /// denominator.
    static func formatRate(_ value: Double?) -> String {
        guard let value else { return "—" }
        let text = String(format: "%.3f", value)
        return text.hasPrefix("0") ? String(text.dropFirst()) : text
    }

    /// How (if at all) the at-bat ended on this pitch - the shared rule in
    /// `AtBatCountRules.endOfAtBat`, which pitcher stats use too.
    static func terminal(
        facts: AtBatCountRules.PitchFacts,
        storedBalls: Int?,
        storedStrikes: Int?,
        descriptor: String? = nil
    ) -> AtBatTerminal? {
        AtBatCountRules.endOfAtBat(facts: facts, storedBalls: storedBalls,
                                   storedStrikes: storedStrikes, descriptor: descriptor)
    }

    static func hasHitTag(_ descriptor: String?) -> Bool {
        AtBatCountRules.hasHitTag(descriptor)
    }

    mutating func record(_ terminal: AtBatTerminal, outcome: String?, errorOnPlay: Bool = false) {
        plateAppearances += 1
        if terminal == .hit, errorOnPlay {
            atBats += 1
            reachedOnError += 1
            return
        }
        switch terminal {
        case .walk:
            walks += 1
        case .hitByPitch:
            hitByPitch += 1
        case .strikeout:
            atBats += 1
            strikeouts += 1
        case .out:
            atBats += 1
        case .hit:
            atBats += 1
            hits += 1
            switch (outcome ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
            case "1B": break
            case "2B": doubles += 1
            case "3B": triples += 1
            case "HR": homeRuns += 1
            default: unspecifiedHits += 1
            }
        }
    }
}

// MARK: - RunnerEvent

extension HittingStatLine {
    /// Adds this runner's steals, caught stealing and pickoffs. The caller
    /// passes only events for the hitter whose line this is.
    mutating func recordRunning(_ events: [RunnerEvent]) {
        for event in events {
            switch event.kindValue {
            case .stolenBase?: stolenBases += 1
            case .caughtStealing?: caughtStealing += 1
            case .pickedOff?: pickedOff += 1
            default: break
            }
            // Stealing home or scoring between pitches is a run, never an RBI.
            if event.to == Base.scored,
               event.kindValue == .stolenBase || event.kindValue == .advanced {
                runs += 1
            }
        }
    }
}

// MARK: - PitchEvent

extension HittingStatLine {
    init(events: [PitchEvent]) {
        self.init()
        for event in events {
            guard let terminal = event.atBatEnd else { continue }
            // A single that took 2nd on an error is still a single; only an
            // explicit reached-on-error (or a legacy error with no play
            // recorded) is ROE. See BaseRunnerRules.isReachedOnError.
            record(
                terminal,
                outcome: event.outcome,
                errorOnPlay: BaseRunnerRules.isReachedOnError(errorOnPlay: event.errorOnPlay, play: event.play)
            )
            runsBattedIn += Self.runsBattedIn(for: event)
            if Self.batterScored(event) { runs += 1 }
        }
    }

    /// RBIs on the batter's own pitch (rules approved 2026-11-05): every run
    /// a hit, walk, hit-by-pitch or out drove in - the batter's own on a
    /// home run. None on reached-on-error, on a play that made two or more
    /// outs, or for a runner who scored on an error, wild pitch or passed
    /// ball. Which runner an error moved isn't recorded on a hit, so their
    /// runs count. Pitches from before the runner system have no play; a
    /// home run is the only one whose RBI is known without it.
    static func runsBattedIn(for event: PitchEvent) -> Int {
        guard let play = event.play else {
            return isHomeRunOutcome(event.outcome) && event.atBatEnd == .hit ? 1 : 0
        }
        guard let credit = play.credit, !play.isRunnersOnly,
              credit != .reachedOnError, play.outs < 2 else { return 0 }
        let drivenIn = play.runnerMoves.filter { move in
            guard move.to == Base.scored else { return false }
            guard let raw = move.extraBasesOn, let reason = ExtraBasesReason(rawValue: raw) else { return true }
            return reason == .onThrow
        }.count
        let batterHomer = credit == .homeRun && play.batterMove?.to == Base.scored
            && play.batterMove?.extraBasesOn == nil
        return drivenIn + (batterHomer ? 1 : 0)
    }

    /// The batter came all the way around on their own pitch.
    static func batterScored(_ event: PitchEvent) -> Bool {
        guard let play = event.play else {
            return isHomeRunOutcome(event.outcome) && event.atBatEnd == .hit
        }
        return play.batterMove?.to == Base.scored
    }

    private static func isHomeRunOutcome(_ outcome: String?) -> Bool {
        (outcome ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == BatterCredit.homeRun.rawValue
    }

    /// Runs scored as a runner on other batters' pitches: `gameEvents` are
    /// every pitch of the games (already filtered), and a runner is this
    /// player when their token carries one of `hitterIds`. Runners added
    /// by hand have no hitter, so their runs go to nobody.
    mutating func recordRunsScored(onPitches gameEvents: [PitchEvent], hitterIds: Set<String>) {
        guard !hitterIds.isEmpty else { return }
        var seen = Set<String>()
        for event in gameEvents {
            guard let play = event.play, let before = event.basesBefore else { continue }
            guard seen.insert(event.identity).inserted else { continue }
            for move in play.runnerMoves where move.to == Base.scored {
                if let hitterId = before[move.from]?.hitterId, hitterIds.contains(hitterId) {
                    runs += 1
                }
            }
        }
    }
}
