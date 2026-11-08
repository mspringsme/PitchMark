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
//  Phase 2 adds runners already on base: `BaseOccupancy` is who is on
//  which base between pitches, and a play's `moves` carry one entry per
//  runner who moved or was put out (a runner with no move stayed put).
//  `resolve` turns before + play into after, runs and outs.
//
//  Compiled into the Display target too (PitchEvent references BasePlay) -
//  it is listed in that target's membershipExceptions.
//

import Foundation

/// Bases are numbered 0 = home (batter, before the play), 1-3, 4 = scored,
/// and -1 = put out on the play.
enum Base {
    static let out = -1
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
        case out: return "Out"
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
    /// Safe because the defense put a runner out instead.
    case fieldersChoice = "FC"
    /// Batter put out on a ball in play. Only recorded as a play when
    /// runners were on, so their moves (and outs) have somewhere to live.
    case out = "OUT"
    case walk = "BB"
    case hitByPitch = "HBP"

    /// The base this hit is worth, or nil for ROE (which earns no bases).
    var hitBase: Int? {
        switch self {
        case .single: return Base.first
        case .double: return Base.second
        case .triple: return Base.third
        case .homeRun: return Base.scored
        case .reachedOnError, .fieldersChoice, .out, .walk, .hitByPitch: return nil
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

/// Why a runner went further than the credited hit carried them - or, for
/// WP/PB, why runners moved on a pitch that wasn't put in play.
enum ExtraBasesReason: String, Codable, CaseIterable {
    case error = "E"
    case onThrow = "throw"
    case wildPitch = "WP"
    case passedBall = "PB"

    /// The two a batter-runner can be asked about on the bases diamond.
    static let batterChoices: [ExtraBasesReason] = [.error, .onThrow]

    var label: String {
        switch self {
        case .error: return "Error"
        case .onThrow: return "Throw"
        case .wildPitch: return "Wild pitch"
        case .passedBall: return "Passed ball"
        }
    }
}

/// One runner's movement on a play.
/// A named-field struct on purpose: Firestore cannot store nested arrays.
struct RunnerMove: Codable, Hashable {
    /// "batter" for the batter; a runner's `BaseRunner.id` otherwise. Only
    /// a record - `from` is what identifies the runner, since the bases
    /// hold at most one runner each.
    var runner: String
    var from: Int
    /// 1-3, `Base.scored`, or `Base.out`.
    var to: Int
    /// Raw `ExtraBasesReason`, set only when the runner went past what the
    /// hit itself carried them.
    var extraBasesOn: String?

    static let batterKey = "batter"
}

/// Someone on base: the batter id (or jersey) they batted as, plus what to
/// draw on their token. Runners added by hand on the tracker have no id.
struct BaseRunner: Codable, Hashable {
    var id: String
    var label: String
    /// The runner's Hitter record, when their lineup cell is linked to one -
    /// what steals and caught stealing are credited to.
    var hitterId: String? = nil

    static let manual = BaseRunner(id: "", label: "R")
}

/// Who is on which base between pitches. Named fields rather than an array
/// so it stores in Firestore and the live room as a plain map.
struct BaseOccupancy: Codable, Hashable {
    var first: BaseRunner? = nil
    var second: BaseRunner? = nil
    var third: BaseRunner? = nil

    static let empty = BaseOccupancy()

    subscript(base: Int) -> BaseRunner? {
        get {
            switch base {
            case Base.first: return first
            case Base.second: return second
            case Base.third: return third
            default: return nil
            }
        }
        set {
            switch base {
            case Base.first: first = newValue
            case Base.second: second = newValue
            case Base.third: third = newValue
            default: break
            }
        }
    }

    var occupiedBases: [Int] { [Base.first, Base.second, Base.third].filter { self[$0] != nil } }
    var isEmpty: Bool { occupiedBases.isEmpty }
}

/// What a play did to the bases.
struct PlayResult: Equatable {
    var after: BaseOccupancy
    var runs: Int
    var outs: Int
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

    /// Runners moved on a pitch the batter didn't put in play (wild pitch,
    /// passed ball) - there is no batter result to credit.
    var isRunnersOnly: Bool { batterMove == nil }

    /// Moves of runners who were already on base.
    var runnerMoves: [RunnerMove] {
        moves.filter { $0.runner != RunnerMove.batterKey }
    }

    /// Outs made on the play, the batter's included.
    var outs: Int { moves.filter { $0.to == Base.out }.count }

    /// Runs scored on the play, the batter's included.
    var runs: Int { moves.filter { $0.to == Base.scored }.count }
}

enum BaseRunnerRules {

    /// Credits that are possible for a batter who ended on `reached`: any hit
    /// worth no more than that base, a fielder's choice when there were
    /// runners to choose, or reached on error.
    static func creditOptions(reached: Int, runnersOn: Bool = false) -> [BatterCredit] {
        let hits = BatterCredit.allCases.filter { credit in
            guard let base = credit.hitBase else { return false }
            return base <= reached
        }
        return hits + (runnersOn ? [.fieldersChoice] : []) + [.reachedOnError]
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
        guard creditOptions(reached: reached, runnersOn: true).contains(credit) else { return false }
        if needsExtraBasesReason(credit: credit, reached: reached) {
            return extraBasesOn != nil
        }
        return true
    }

    static func makePlay(
        credit: BatterCredit,
        reached: Int,
        extraBasesOn: ExtraBasesReason?,
        runnerMoves: [RunnerMove] = []
    ) -> BasePlay {
        let reason = needsExtraBasesReason(credit: credit, reached: reached) ? extraBasesOn : nil
        return BasePlay(
            batterCredit: credit.rawValue,
            moves: [RunnerMove(runner: RunnerMove.batterKey, from: Base.home, to: reached, extraBasesOn: reason?.rawValue)]
                + runnerMoves
        )
    }

    /// The legacy `outcome` string written alongside the play, so the count
    /// rules and older app builds keep reading it correctly. ROE stays "1B" +
    /// `errorOnPlay`, which is how reached-on-error was always stored; a
    /// fielder's choice is an at-bat with no hit, which is what "Out" means
    /// to everything that predates the play (the outs it adds come from the
    /// play, not from the outcome, once a play is present).
    static func outcome(for credit: BatterCredit) -> String {
        switch credit {
        case .reachedOnError: return BatterCredit.single.rawValue
        case .fieldersChoice, .out: return "Out"
        case .walk: return "Walk"
        case .hitByPitch: return "HBP"
        case .single, .double, .triple, .homeRun: return credit.rawValue
        }
    }

    // MARK: - Runners

    /// Where every runner goes by default once the batter's base is known:
    /// nowhere, unless the batter (or a runner behind them) needs their base.
    /// That is exactly the force rule for a walk, and the minimum anyone moves
    /// on a hit - a double pushes a runner on 1st to 3rd, not home. The user
    /// moves anyone further from there. Keyed by the base each runner started on.
    static func defaultDestinations(before: BaseOccupancy, batterTo: Int?) -> [Int: Int] {
        var behind = max(Base.home, batterTo ?? Base.home)
        var result: [Int: Int] = [:]
        for base in before.occupiedBases {
            let dest = behind >= Base.scored ? Base.scored : max(base, behind + 1)
            result[base] = min(dest, Base.scored)
            behind = result[base]!
        }
        return result
    }

    /// The moves worth recording: runners who went somewhere. Stayed-put
    /// runners are implied by having no move.
    static func runnerMoves(before: BaseOccupancy, destinations: [Int: Int]) -> [RunnerMove] {
        before.occupiedBases.compactMap { base in
            guard let runner = before[base], let dest = destinations[base], dest != base else { return nil }
            return RunnerMove(runner: runner.id, from: base, to: dest, extraBasesOn: nil)
        }
    }

    /// Why a set of end positions is impossible, or nil when it's fine.
    /// `positions` is (start, end) for everyone on the play, the batter as
    /// start 0; an end of `Base.out` takes that runner off the bases.
    static func conflict(_ positions: [(from: Int, to: Int)]) -> String? {
        for p in positions where p.to != Base.out && p.to < max(p.from, Base.first) {
            return p.from == Base.home ? "The batter has to reach a base" : "Runners can't go back a base"
        }
        // Lead runner first: everyone behind must end strictly behind them,
        // except that any number of runners can score.
        let onBases = positions.filter { $0.to != Base.out }.sorted { $0.from > $1.from }
        for (lead, trail) in zip(onBases, onBases.dropFirst()) {
            if lead.to == Base.scored && trail.to == Base.scored { continue }
            if trail.to == lead.to { return "Two runners can't end on \(Base.name(lead.to))" }
            if trail.to > lead.to { return "A runner can't pass the runner ahead" }
        }
        return nil
    }

    /// The bases after a play, plus what it scored and cost. A runner with no
    /// move stayed where they were; a batter with no move never reached.
    static func resolve(_ play: BasePlay, before: BaseOccupancy, batter: BaseRunner) -> PlayResult {
        var after = BaseOccupancy.empty
        var runs = 0
        var outs = 0
        func land(_ runner: BaseRunner, at dest: Int) {
            switch dest {
            case Base.scored: runs += 1
            case Base.out: outs += 1
            case Base.first...Base.third: after[dest] = runner
            default: break
            }
        }
        // Lead runners first, so a (conflicting) trailing runner can't be
        // overwritten by one who was ahead of them.
        for base in before.occupiedBases.reversed() {
            guard let runner = before[base] else { continue }
            let move = play.runnerMoves.first { $0.from == base }
            land(runner, at: move?.to ?? base)
        }
        if let move = play.batterMove {
            land(batter, at: move.to)
        }
        return PlayResult(after: after, runs: runs, outs: outs)
    }

    /// Walk / hit by pitch: the batter takes 1st and only forced runners move.
    /// `existing` is a runners-only play already recorded on the same pitch
    /// (ball four that was also a wild pitch): its runners keep whichever is
    /// further, their WP/PB advance or the force.
    static func awardedFirstPlay(credit: BatterCredit, before: BaseOccupancy, existing: BasePlay? = nil) -> BasePlay {
        let forced = defaultDestinations(before: before, batterTo: Base.first)
        let moves: [RunnerMove] = before.occupiedBases.compactMap { base in
            guard let runner = before[base] else { return nil }
            let recorded = existing?.runnerMoves.first { $0.from == base }
            let forcedTo = forced[base] ?? base
            if let recorded, recorded.to == Base.out || recorded.to >= forcedTo {
                return recorded
            }
            return forcedTo == base ? nil : RunnerMove(runner: runner.id, from: base, to: forcedTo, extraBasesOn: nil)
        }
        return makePlay(credit: credit, reached: Base.first, extraBasesOn: nil, runnerMoves: moves)
    }

    /// Runners moving on a pitch not put in play, each tagged with why.
    static func runnersOnlyPlay(before: BaseOccupancy, destinations: [Int: Int], reason: ExtraBasesReason) -> BasePlay? {
        let moves = runnerMoves(before: before, destinations: destinations).map { move -> RunnerMove in
            var tagged = move
            if move.to != Base.out { tagged.extraBasesOn = reason.rawValue }
            return tagged
        }
        return moves.isEmpty ? nil : BasePlay(batterCredit: "", moves: moves)
    }

    // MARK: - Between pitches

    /// Where a runner-event kind takes the runner from `from`. Steals and
    /// advances are one base; anything further is a second event.
    static func destination(for kind: RunnerEventKind, from: Int) -> Int {
        switch kind {
        case .stolenBase, .advanced: return min(from + 1, Base.scored)
        case .caughtStealing, .pickedOff: return Base.out
        case .substitution: return from
        }
    }

    /// Whether `kind` can happen to the runner on `from` right now. Moving
    /// up needs the next base clear (home always is) - a double steal is the
    /// lead runner first, then the trail runner.
    static func isAllowed(_ kind: RunnerEventKind, from: Int, bases: BaseOccupancy) -> Bool {
        guard bases[from] != nil else { return false }
        switch kind {
        case .stolenBase, .advanced:
            let next = from + 1
            return next == Base.scored || bases[next] == nil
        case .caughtStealing, .pickedOff, .substitution:
            return true
        }
    }

    /// The bases after a between-pitch event, plus runs and outs it made.
    static func apply(_ event: RunnerEvent) -> PlayResult {
        var after = event.basesBefore
        guard let kind = event.kindValue, let runner = after[event.from] else {
            return PlayResult(after: after, runs: 0, outs: 0)
        }
        if kind == .substitution {
            after[event.from] = event.runner
            return PlayResult(after: after, runs: 0, outs: 0)
        }
        after[event.from] = nil
        switch event.to {
        case Base.scored: return PlayResult(after: after, runs: 1, outs: 0)
        case Base.out: return PlayResult(after: after, runs: 0, outs: 1)
        default:
            after[event.to] = runner
            return PlayResult(after: after, runs: 0, outs: 0)
        }
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
        guard let play else { return nil }
        // A WP/PB advance doesn't depend on what the batter did.
        if play.isRunnersOnly { return play }
        guard let credit = play.credit else { return nil }
        let trimmed = (outcome ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed == self.outcome(for: credit).uppercased() else { return nil }
        let reason = play.batterMove?.extraBasesOn.flatMap(ExtraBasesReason.init(rawValue:))
        guard errorOnPlay == self.errorOnPlay(credit: credit, extraBasesOn: reason) else { return nil }
        return play
    }

    /// The pitch card's one-line version (2026-11-05, user's call: no
    /// repeats in the card's small result box). Leads with the credit, so
    /// the card draws its runner icon: "2B", "1B + E · Safe at 2nd · 1 run",
    /// "HR · 3 runs", "FC · Safe at 1st · runner out". "Safe at" only when
    /// the credit doesn't already say the base.
    static func cardSummary(for play: BasePlay) -> String? {
        guard !play.isRunnersOnly, let credit = play.credit, let move = play.batterMove else {
            return summary(for: play)
        }
        switch credit {
        case .out, .walk, .hitByPitch:
            return summary(for: play)
        default:
            break
        }
        let reason = move.extraBasesOn.flatMap(ExtraBasesReason.init(rawValue:))
        var text = credit.rawValue
        if let reason {
            text += reason == .error ? " + E" : " + \(reason.label.lowercased())"
        }
        if credit.hitBase != move.to || reason != nil {
            text += " · Safe at \(Base.name(move.to))"
        }
        let soloHomeRun = credit == .homeRun && play.runnerMoves.isEmpty
        if play.runs > 0 && !soloHomeRun {
            text += play.runs == 1 ? " · 1 run" : " · \(play.runs) runs"
        }
        let runnerOuts = play.runnerMoves.filter { $0.to == Base.out }.count
        if runnerOuts > 0 {
            text += runnerOuts == 1 ? " · runner out" : " · \(runnerOuts) runners out"
        }
        return text
    }

    /// Short scorebook-style text, e.g. "Safe at 2nd — 1B + E · 1 run".
    static func summary(for play: BasePlay) -> String? {
        if play.isRunnersOnly {
            let reasons = Set(play.moves.compactMap { $0.extraBasesOn.flatMap(ExtraBasesReason.init(rawValue:)) })
            var text = reasons.count == 1 ? reasons.first!.label : "Runners moved"
            if play.runs > 0 { text += play.runs == 1 ? " · 1 run" : " · \(play.runs) runs" }
            if play.outs > 0 { text += play.outs == 1 ? " · runner out" : " · \(play.outs) runners out" }
            return text
        }
        guard let credit = play.credit, let move = play.batterMove else { return nil }
        var text: String
        switch credit {
        case .out: text = "Out"
        case .walk: text = "Walk"
        case .hitByPitch: text = "Hit by pitch"
        case .homeRun where move.to == Base.scored && move.extraBasesOn == nil: text = "Home run"
        default:
            let creditText: String
            switch credit {
            case .reachedOnError: creditText = "Reached on error"
            case .fieldersChoice: creditText = "Fielder's choice"
            default: creditText = credit.rawValue
            }
            text = "Safe at \(Base.name(move.to)) — \(creditText)"
        }
        if let raw = move.extraBasesOn, let reason = ExtraBasesReason(rawValue: raw) {
            text += reason == .error ? " + E" : " + \(reason.label.lowercased())"
        }
        // A solo home run already says its one run.
        let soloHomeRun = credit == .homeRun && play.runnerMoves.isEmpty
        if play.runs > 0 && !soloHomeRun {
            text += play.runs == 1 ? " · 1 run" : " · \(play.runs) runs"
        }
        let runnerOuts = play.runnerMoves.filter { $0.to == Base.out }.count
        if runnerOuts > 0 {
            text += runnerOuts == 1 ? " · runner out" : " · \(runnerOuts) runners out"
        }
        return text
    }
}


// MARK: - Between-pitch runner events

/// Something a runner did between pitches. Each one is stored as its own
/// record (liveGames/{id}/runnerEvents, the owner's game, and the runner's
/// /hitters copy) so steals count in stats.
enum RunnerEventKind: String, Codable, CaseIterable {
    case stolenBase = "SB"
    case caughtStealing = "CS"
    case pickedOff = "PO"
    /// Balk, defensive indifference... a base with no stat attached.
    case advanced = "ADV"
    /// Pinch runner.
    case substitution = "SUB"

    var title: String {
        switch self {
        case .stolenBase: return "Steal"
        case .caughtStealing: return "Caught Stealing"
        case .pickedOff: return "Picked Off"
        case .advanced: return "Advance"
        case .substitution: return "Pinch Runner"
        }
    }
}

struct RunnerEvent: Codable, Hashable {
    var id: String
    var timestamp: Date
    /// Raw `RunnerEventKind`.
    var kind: String
    var from: Int
    /// 1-3, `Base.scored`, or `Base.out`; equal to `from` for a substitution.
    var to: Int
    /// Who did it - for a substitution, the runner coming in.
    var runner: BaseRunner
    /// Substitution only: who left.
    var replaced: BaseRunner? = nil
    /// The bases before, so undo restores them exactly.
    var basesBefore: BaseOccupancy
    var gameId: String? = nil
    var pitcherId: String? = nil
    /// `runner.hitterId`, at the top level so the hitter copy can be found.
    var hitterId: String? = nil
    var createdByUid: String? = nil
    var inning: Int? = nil

    var kindValue: RunnerEventKind? { RunnerEventKind(rawValue: kind) }

    var summary: String {
        guard let kindValue else { return "Runner" }
        switch kindValue {
        case .substitution:
            return "\(runner.label) runs for \(replaced?.label ?? "runner") at \(Base.name(from))"
        case .caughtStealing, .pickedOff:
            return "\(runner.label) \(kindValue.title.lowercased()) at \(Base.name(from))"
        case .stolenBase:
            return to == Base.scored ? "\(runner.label) steals home" : "\(runner.label) steals \(Base.name(to))"
        case .advanced:
            return to == Base.scored ? "\(runner.label) scores" : "\(runner.label) to \(Base.name(to))"
        }
    }
}
