//
//  BaseRunnerRules.swift
//  PitchMark
//
//  Single source of truth for where the batter ended up on a ball in play
//  and what they're credited with - the same role AtBatCount.swift plays for
//  balls/strikes. Imports only Foundation so it can be verified by compiling
//  it alongside a standalone assertion script.
//
//  The core distinction: *credit* and *base reached* are separate facts.
//  A clean double and a single + error both end with the batter on 2nd, but
//  only one of them is a double. The UI asks where the batter ended up, then
//  asks how only when the answer isn't implied.
//
//  Phase 1 records the batter only. `RunnerMove` is shaped for phase 2
//  (runners already on base), when `moves` gains one entry per runner.
//
//  Compiled into the Display target too (PitchEvent references BasePlay) -
//  it is listed in that target's membershipExceptions.
//

import Foundation

/// Bases are numbered 0 = home (batter, before the play), 1-3, 4 = scored.
enum Base {
    static let home = 0
    static let first = 1
    static let second = 2
    static let third = 3
    static let scored = 4

    static func name(_ base: Int) -> String {
        switch base {
        case first: return "1st"
        case second: return "2nd"
        case third: return "3rd"
        case scored: return "Home"
        default: return "Home"
        }
    }
}

/// What the batter is credited with in the scorebook.
enum BatterCredit: String, Codable, CaseIterable {
    case single = "1B"
    case double = "2B"
    case triple = "3B"
    case homeRun = "HR"
    case reachedOnError = "ROE"

    /// The base this hit is worth, or nil for ROE (which earns no bases).
    var hitBase: Int? {
        switch self {
        case .single: return Base.first
        case .double: return Base.second
        case .triple: return Base.third
        case .homeRun: return Base.scored
        case .reachedOnError: return nil
        }
    }

    var isHit: Bool { hitBase != nil }

    static func hit(forBase base: Int) -> BatterCredit? {
        switch base {
        case Base.first: return .single
        case Base.second: return .double
        case Base.third: return .triple
        case Base.scored: return .homeRun
        default: return nil
        }
    }
}

/// Why a runner went further than the credited hit carried them.
enum ExtraBasesReason: String, Codable, CaseIterable {
    case error = "E"
    case onThrow = "throw"

    var label: String {
        switch self {
        case .error: return "Error"
        case .onThrow: return "Throw"
        }
    }
}

/// One runner's movement on a play. Phase 1 writes only the batter's.
/// A named-field struct on purpose: Firestore cannot store nested arrays.
struct RunnerMove: Codable, Hashable {
    /// "batter" for the batter; phase 2 uses the runner's batter id / jersey.
    var runner: String
    var from: Int
    var to: Int
    /// Raw `ExtraBasesReason`, set only when the runner went past what the
    /// hit itself carried them.
    var extraBasesOn: String?

    static let batterKey = "batter"
}

/// Everything recorded about who ended up where on a play.
struct BasePlay: Codable, Hashable {
    /// Raw `BatterCredit`.
    var batterCredit: String
    var moves: [RunnerMove]

    var credit: BatterCredit? { BatterCredit(rawValue: batterCredit) }

    var batterMove: RunnerMove? {
        moves.first { $0.runner == RunnerMove.batterKey }
    }
}

enum BaseRunnerRules {

    /// Credits that are possible for a batter who ended on `reached`: any hit
    /// worth no more than that base, or reached on error.
    static func creditOptions(reached: Int) -> [BatterCredit] {
        let hits = BatterCredit.allCases.filter { credit in
            guard let base = credit.hitBase else { return false }
            return base <= reached
        }
        return hits + [.reachedOnError]
    }

    /// The common case needs no question: ending on 2nd means a double.
    static func defaultCredit(reached: Int) -> BatterCredit {
        BatterCredit.hit(forBase: reached) ?? .single
    }

    /// A hit worth fewer bases than the batter took has to say how the rest
    /// happened. ROE doesn't - the error is the whole explanation.
    static func needsExtraBasesReason(credit: BatterCredit, reached: Int) -> Bool {
        guard let base = credit.hitBase else { return false }
        return base < reached
    }

    /// True when the play is complete enough to save.
    static func isComplete(credit: BatterCredit, reached: Int, extraBasesOn: ExtraBasesReason?) -> Bool {
        guard creditOptions(reached: reached).contains(credit) else { return false }
        if needsExtraBasesReason(credit: credit, reached: reached) {
            return extraBasesOn != nil
        }
        return true
    }

    static func makePlay(credit: BatterCredit, reached: Int, extraBasesOn: ExtraBasesReason?) -> BasePlay {
        let reason = needsExtraBasesReason(credit: credit, reached: reached) ? extraBasesOn : nil
        return BasePlay(
            batterCredit: credit.rawValue,
            moves: [RunnerMove(runner: RunnerMove.batterKey, from: Base.home, to: reached, extraBasesOn: reason?.rawValue)]
        )
    }

    /// The legacy `outcome` string written alongside the play. ROE stays
    /// "1B" + `errorOnPlay`, which is how reached-on-error was always stored,
    /// so the count rules and older app builds keep reading it correctly.
    static func outcome(for credit: BatterCredit) -> String {
        credit == .reachedOnError ? BatterCredit.single.rawValue : credit.rawValue
    }

    /// `errorOnPlay` for the saved event: an error put the batter on base or
    /// moved them up.
    static func errorOnPlay(credit: BatterCredit, extraBasesOn: ExtraBasesReason?) -> Bool {
        credit == .reachedOnError || extraBasesOn == .error
    }

    /// Stats rule. Before BasePlay, any error on a hit meant reached on error.
    /// With a play recorded, only an explicit ROE credit does - a single that
    /// took 2nd on an error is still a single.
    static func isReachedOnError(errorOnPlay: Bool, play: BasePlay?) -> Bool {
        guard errorOnPlay else { return false }
        guard let play, let credit = play.credit else { return true }
        return credit == .reachedOnError
    }

    /// The play, if it still agrees with the event's outcome and error flag.
    /// Every place that rebuilds a PitchEvent (review sheet, pitch editor)
    /// carries the play through this, so an edit that turns the hit into an
    /// out - or toggles the error - drops a play that no longer describes it
    /// instead of leaving the stats reading a stale one.
    static func playIfConsistent(_ play: BasePlay?, outcome: String?, errorOnPlay: Bool) -> BasePlay? {
        guard let play, let credit = play.credit else { return nil }
        let trimmed = (outcome ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed == self.outcome(for: credit) else { return nil }
        let reason = play.batterMove?.extraBasesOn.flatMap(ExtraBasesReason.init(rawValue:))
        guard errorOnPlay == self.errorOnPlay(credit: credit, extraBasesOn: reason) else { return nil }
        return play
    }

    /// Short scorebook-style text, e.g. "Safe at 2nd — 1B + E".
    static func summary(for play: BasePlay) -> String? {
        guard let credit = play.credit, let move = play.batterMove else { return nil }
        let creditText = credit == .reachedOnError ? "Reached on error" : credit.rawValue
        var text = credit == .homeRun && move.to == Base.scored && move.extraBasesOn == nil
            ? "Home run"
            : "Safe at \(Base.name(move.to)) — \(creditText)"
        if let raw = move.extraBasesOn, let reason = ExtraBasesReason(rawValue: raw) {
            text += reason == .error ? " + E" : " + throw"
        }
        return text
    }
}
