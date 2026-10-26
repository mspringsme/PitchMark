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

    /// How (if at all) the at-bat ended on this pitch. `storedBalls` /
    /// `storedStrikes` are the pitch's own saved count - nil on events
    /// written before the count was stored, where only an explicit outcome
    /// can be read.
    static func terminal(
        facts: AtBatCountRules.PitchFacts,
        storedBalls: Int?,
        storedStrikes: Int?,
        descriptor: String? = nil
    ) -> AtBatTerminal? {
        let storedAtStart = storedBalls == 0 && storedStrikes == 0
        let hasOutcome = !(facts.outcome ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasOutcome, hasHitTag(descriptor) {
            return .hit
        }
        switch AtBatCountRules.effect(for: facts) {
        case .endsAtBat(let terminal):
            return terminal
        case .strike:
            return storedAtStart ? .strikeout : nil
        case .ball:
            return storedAtStart ? .walk : nil
        case .foul, .noChange:
            return nil
        }
    }

    /// `descriptor` is a comma-joined tag list, e.g. "Line Drive, Hit".
    static func hasHitTag(_ descriptor: String?) -> Bool {
        (descriptor ?? "")
            .split(separator: ",")
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("hit") == .orderedSame }
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

// MARK: - PitchEvent

extension HittingStatLine {
    init(events: [PitchEvent]) {
        self.init()
        for event in events {
            guard let terminal = Self.terminal(
                facts: AtBatCountRules.PitchFacts(event: event),
                storedBalls: event.atBatBalls,
                storedStrikes: event.atBatStrikes,
                descriptor: event.descriptor
            ) else { continue }
            record(terminal, outcome: event.outcome, errorOnPlay: event.errorOnPlay)
        }
    }
}
