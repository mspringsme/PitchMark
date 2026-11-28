//
//  GameFeed.swift
//  PitchMark
//
//  Game feeds (clip brief section 2b, phase 4): an approved off-site
//  follower - a grandparent in another state - follows a game as it
//  happens. One game, many feeds: the official feed (the coach's game) and
//  personal feeds (a parent scoring on their own). Each feed has a title
//  ("Coach", "Mrs. Jones") and its own sharing settings.
//
//  HIGH RISK: followers see outcomes only - ball, strike, hit, out, run -
//  never pitch calls, codes, keys or the catcher's estimate. A feed event
//  is built here from a pitch by copying only the fields on
//  `GameFeedEvent.allowedKeys`; nothing reads a PitchEvent wholesale, and
//  the rules refuse any other key. Followers never read /liveGames or a
//  game's pitches.
//
//  Plain model and rules here. Stored at `gameFeeds/{feedId}` with
//  `events/{eventId}` and `followers/{uid}` (rules: GAME FEEDS).
//  PitchMark only - not in the Display target.
//

import Foundation

enum GameFeedKind: String, Codable {
    /// The coach's game (and the linked helper's pitches through it).
    /// Drives the headline score and inning.
    case official
    /// A parent scoring on their own. Never changes the official score.
    case personal
}

/// Who may follow a feed (set by its scorer).
enum GameFeedAudience: String, Codable, CaseIterable {
    case nobody
    /// People the scorer approved one by one.
    case approved
    /// Everyone on the team (any role, Follower included).
    case team
}

/// What a feed shares.
enum GameFeedScope: String, Codable, CaseIterable {
    case everything
    /// Only the scorer's own players' at-bats.
    case myPlayers
}

/// One update a follower sees.
struct GameFeedEvent: Equatable, Identifiable {
    /// The pitch's id, so an edit or a delete reaches the same event.
    var id: String
    /// When it happened (the pitch's own time), so late syncs line up.
    var at: Date
    var inning: Int
    /// "top"/"bottom" when known.
    var half: String?
    /// First name or "#12" - see `GameFeedRules.displayName`.
    var batter: String
    /// "26", or nil when the batter has no number.
    var jersey: String? = nil
    /// ball, strike, foul, inPlay, walk, strikeout, hbp, hit, out
    var kind: String
    /// "Ball 2-1", "Strikeout", "2B · 1 run".
    var text: String
    var runs: Int
    /// The card's result lines ("1B", "Line · Shallow Left") - from
    /// `outcomeSummaryLines`, which reads result fields only.
    var detail: [String] = []
    /// The board right after this play (user, 2026-11-24): who was batting,
    /// the score, the outs.
    var batting: String? = nil
    var ourScore: Int? = nil
    var theirScore: Int? = nil
    var outs: Int? = nil
    /// For the play animation (2026-11-25): where the ball went (0 to 1
    /// across and down the result sheet's field picture, the same space as
    /// the bag positions), how it was hit, and who moved base to base.
    var spotX: Double? = nil
    var spotY: Double? = nil
    /// grounder, line, fly, pop, bunt, hr
    var ballType: String? = nil
    var moves: [FeedMove] = []

    /// The only fields a feed event may carry. The rules allow exactly
    /// these; adding one means changing both.
    static let allowedKeys: Set<String> = ["at", "inning", "half", "batter", "jersey", "kind", "text", "runs", "detail",
                                           "batting", "ourScore", "theirScore", "outs",
                                           "spotX", "spotY", "ballType", "moves", "updatedAt"]

    /// "Smith #26", "#26" for a number-only player, or just the name.
    var batterLabel: String {
        guard let jersey, !jersey.isEmpty else { return batter }
        let tag = "#\(jersey)"
        // A number-only player ("#23", or a bare "23") shows it once.
        return batter == tag || batter == jersey || batter.hasPrefix("#") ? tag : "\(batter) \(tag)"
    }

    /// The card's header word: Hit, Out, Ball, Strike, Foul, Walk...
    var kindLabel: String {
        switch kind {
        case "hit": return "Hit"
        case "out": return "Out"
        case "ball": return "Ball"
        case "strike": return "Strike"
        case "foul": return "Foul"
        case "walk": return "Walk"
        case "strikeout": return "Strikeout"
        case "hbp": return "Hit by Pitch"
        case "run": return "Run"
        default: return "In Play"
        }
    }

    /// "Hawks Batting · 2 outs · Reds 3 – Hawks 2".
    func situationLine(ourName: String, theirName: String) -> String? {
        var parts: [String] = []
        if let batting, !batting.isEmpty { parts.append("\(batting) Batting") }
        if let outs { parts.append("\(outs) out\(outs == 1 ? "" : "s")") }
        if let ourScore, let theirScore { parts.append("\(ourName) \(ourScore) – \(theirName) \(theirScore)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "1 Out", "2 Outs" - the stacked board in a play row.
    var outsLabel: String? {
        outs.map { "\($0) Out\($0 == 1 ? "" : "s")" }
    }

    /// A play shows the card's lines; a ball or strike shows its count.
    var showsPlayLines: Bool {
        !detail.isEmpty && !["ball", "strike", "foul"].contains(kind)
    }

    /// The card's runner icon: the batter reached on a hit.
    var batterRan: Bool {
        let first = (detail.first ?? "").uppercased()
        return ["1B", "2B", "3B", "HR"].contains { first.hasPrefix($0) }
    }

    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "at": at, "inning": inning, "batter": batter, "kind": kind, "text": text, "runs": runs
        ]
        if let half { data["half"] = half }
        if let jersey, !jersey.isEmpty { data["jersey"] = jersey }
        if !detail.isEmpty { data["detail"] = detail }
        if let batting, !batting.isEmpty { data["batting"] = batting }
        if let ourScore { data["ourScore"] = ourScore }
        if let theirScore { data["theirScore"] = theirScore }
        if let outs { data["outs"] = outs }
        if let spotX, let spotY { data["spotX"] = spotX; data["spotY"] = spotY }
        if let ballType { data["ballType"] = ballType }
        if !moves.isEmpty { data["moves"] = moves.map(\.firestoreData) }
        return data
    }
}

/// One runner's move on a play, as the feed carries it: bases only.
struct FeedMove: Equatable, Hashable {
    /// 0 home (the batter), 1-3 the base they started on.
    var from: Int
    /// 1-3 a base, 4 scored, -1 out.
    var to: Int

    var firestoreData: [String: Int] { ["f": from, "t": to] }

    init(from: Int, to: Int) {
        self.from = from
        self.to = to
    }

    init?(data: [String: Any]) {
        guard let f = data["f"] as? Int, let t = data["t"] as? Int,
              (0...3).contains(f), [-1, 1, 2, 3, 4].contains(t) else { return nil }
        from = f
        to = t
    }
}

enum GameFeedRules {
    /// Followers per feed and feeds per game (brief: cap listeners).
    static let maxFollowersPerFeed = 30
    static let maxFeedsPerGame = 8

    /// Child privacy: first name only, or "#12" when there's no name,
    /// unless the scorer turned last names on.
    static func displayName(_ full: String?, jersey: String?, showLastNames: Bool) -> String {
        let name = (full ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let number = (jersey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let jerseyLabel = number.isEmpty ? "" : "#\(number.hasPrefix("#") ? String(number.dropFirst()) : number)"
        if name.isEmpty || name.hasPrefix("#") { return jerseyLabel.isEmpty ? "Batter" : jerseyLabel }
        if showLastNames { return name }
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    /// The outcome of a pitch in plain words, from the same rules every
    /// stats screen uses. Nothing about what was called or thrown.
    static func outcome(of pitch: PitchEvent) -> (kind: String, text: String, runs: Int) {
        let runs = pitch.play?.runs ?? 0
        let runText = runs == 0 ? "" : " · \(runs) run\(runs == 1 ? "" : "s")"
        if let end = pitch.atBatEnd {
            switch end {
            case .walk: return ("walk", "Walk" + runText, runs)
            case .strikeout: return ("strikeout", "Strikeout" + strikeKind(pitch), runs)
            case .hitByPitch: return ("hbp", "Hit by pitch" + runText, runs)
            case .hit:
                let label = pitch.play.flatMap { BaseRunnerRules.cardSummary(for: $0) } ?? "Hit"
                return ("hit", label + (label.contains("run") ? "" : runText), runs)
            case .out:
                let label = pitch.play.flatMap { BaseRunnerRules.cardSummary(for: $0) } ?? "Out"
                return ("out", label + (label.contains("run") ? "" : runText), runs)
            }
        }
        let count = pitch.atBatBalls.flatMap { b in pitch.atBatStrikes.map { "\(b)-\($0)" } }
        let countText = count.map { " \($0)" } ?? ""
        if pitch.play != nil && runs > 0 {
            // Runners only (wild pitch, passed ball).
            return ("run", "Runner scores" + runText, runs)
        }
        switch inferredPitchResultType(for: pitch) {
        case .ball: return ("ball", "Ball" + countText, runs)
        case .strike:
            let isFoul = (pitch.outcome ?? "").localizedCaseInsensitiveContains("foul")
            if isFoul { return ("foul", "Foul" + countText, runs) }
            return ("strike", "Strike" + strikeKind(pitch) + countText, runs)
        default:
            return ("inPlay", "In play", runs)
        }
    }

    /// A pitch as a feed event. `inning`/`half` come from the scorer's
    /// screen when the pitch was saved (a pitch doesn't store them).
    /// The board as it stood after a play.
    struct Situation: Equatable {
        var inning: Int
        var half: String? = nil
        var batting: String? = nil
        var ourScore: Int? = nil
        var theirScore: Int? = nil
        var outs: Int? = nil

    }

    /// Outs a pitch itself made: the play's outs (batter and runners), or
    /// one for a strikeout or an out with no play recorded.
    static func outsMade(by pitch: PitchEvent) -> Int {
        if let play = pitch.play { return play.outs }
        switch pitch.atBatEnd {
        case .strikeout?, .out?: return 1
        default: return 0
        }
    }

    /// Each pitch's board, from the board as it stood when the scorer's
    /// phone first saw that pitch (`seen`, in time order) - never changed
    /// later. The board can lag the pitch, so within a half (same inning
    /// and batting side) a pitch's outs and score are at least the previous
    /// pitch's plus what this pitch made. Outs stop at 3.
    /// Before 2026-11-24 the newest pitch kept taking the board, and the
    /// board moves a moment BEFORE the next pitch arrives - so a strike
    /// showed the out made on the pitch after it.
    static func boards(_ seen: [(id: String, situation: Situation, outsMade: Int, runs: Int)],
                       ourName: String) -> [String: Situation] {
        var result: [String: Situation] = [:]
        var previous: Situation? = nil
        for item in seen {
            var s = item.situation
            if let p = previous, p.inning == s.inning, p.batting == s.batting {
                s.outs = min(3, max(s.outs ?? 0, (p.outs ?? 0) + item.outsMade))
                if item.runs > 0 {
                    let battingIsUs = (s.batting ?? "") == ourName
                    if battingIsUs {
                        s.ourScore = max(s.ourScore ?? 0, (p.ourScore ?? 0) + item.runs)
                    } else {
                        s.theirScore = max(s.theirScore ?? 0, (p.theirScore ?? 0) + item.runs)
                    }
                }
            }
            result[item.id] = s
            previous = s
        }
        return result
    }

    static func event(from pitch: PitchEvent, id: String, inning: Int, half: String?,
                      batterName: String?, showLastNames: Bool) -> GameFeedEvent {
        event(from: pitch, id: id, situation: Situation(inning: inning, half: half),
              batterName: batterName, showLastNames: showLastNames)
    }

    static func event(from pitch: PitchEvent, id: String, situation: Situation,
                      batterName: String?, showLastNames: Bool) -> GameFeedEvent {
        let inning = situation.inning, half = situation.half
        let result = outcome(of: pitch)
        let number = (pitch.opponentJersey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return GameFeedEvent(
            id: id, at: pitch.timestamp, inning: inning, half: half,
            batter: displayName(batterName, jersey: pitch.opponentJersey, showLastNames: showLastNames),
            jersey: number.isEmpty ? nil : String(number.prefix(4)),
            kind: result.kind, text: result.text, runs: result.runs,
            detail: playLines(for: pitch),
            batting: situation.batting.map { String($0.prefix(40)) },
            ourScore: situation.ourScore, theirScore: situation.theirScore, outs: situation.outs,
            spotX: spot(for: pitch)?.x, spotY: spot(for: pitch)?.y,
            ballType: ballType(of: pitch),
            moves: moves(of: pitch)
        )
    }

    /// " – Swinging" / " – Looking" when the scorer said which (user,
    /// 2026-11-27), else nothing.
    static func strikeKind(_ pitch: PitchEvent) -> String {
        if pitch.strikeSwinging { return " – Swinging" }
        if pitch.strikeLooking { return " – Looking" }
        return ""
    }

    /// A card line as text. The pitch card draws a leading "3.circle" or
    /// "f.circle" as a count icon; the feed has no icon, so it's dropped
    /// (user, 2026-11-27: the feed showed "3.circle Strike — Swinging"
    /// under Strikeout, and "4.circle Ball" under a walk).
    static func cleanLine(_ line: String) -> String {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first, first.hasSuffix(".circle") else { return line }
        return parts.count > 1 ? String(parts[1]) : ""
    }

    static let maxDetailLines = 3
    static let maxMoves = 4

    /// Where the ball went, rounded - only for a ball in play (fair or
    /// over the fence). A foul or no tap has none.
    static func spot(for pitch: PitchEvent) -> (x: Double, y: Double)? {
        guard let x = pitch.battedBallTapX, let y = pitch.battedBallTapY,
              ["Field", "HR"].contains(pitch.battedBallType ?? "") else { return nil }
        func clean(_ v: Double) -> Double { (min(1, max(0, v)) * 1000).rounded() / 1000 }
        return (clean(x), clean(y))
    }

    /// How it was hit, from the result sheet's ball-type buttons (they're
    /// saved in the descriptor, "Line, Hit"); a ball over the fence is hr.
    static func ballType(of pitch: PitchEvent) -> String? {
        if pitch.battedBallType == "HR" { return "hr" }
        let tags = (pitch.descriptor ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let known = ["grounder", "line", "fly", "pop", "bunt"]
        return tags.first { known.contains($0) }
    }

    /// Who moved where on the play (batter from home), bases only - no
    /// names or ids. 1-3 bases, 4 scored, -1 out. Runners who stayed put
    /// are listed too, from == to, so the animation draws everyone who was
    /// on base (2026-11-25, user: a runner holding 2nd vanished).
    static func moves(of pitch: PitchEvent) -> [FeedMove] {
        var result = (pitch.play?.moves ?? []).map { FeedMove(from: $0.from, to: $0.to) }
        for base in pitch.basesBefore?.occupiedBases ?? [] where !result.contains(where: { $0.from == base }) {
            result.append(FeedMove(from: base, to: base))
        }
        return Array(result.sorted { $0.from < $1.from }.prefix(maxMoves))
    }

    /// The card's result box lines, capped: what was hit, how it was
    /// fielded, ball type and where it went. `outcomeSummaryLines` never
    /// reads the called pitch, its location, codes, key or estimate.
    static func playLines(for pitch: PitchEvent) -> [String] {
        outcomeSummaryLines(for: pitch)
            .map(cleanLine)
            .filter { !$0.isEmpty }
            .map { String($0.prefix(60)) }
            .prefix(maxDetailLines)
            .map { $0 }
    }

    /// Whether a feed shares this pitch: everything, or only at-bats of the
    /// scorer's own players (matched by Hitter id).
    static func shares(_ pitch: PitchEvent, scope: GameFeedScope, myHitterIds: Set<String>) -> Bool {
        switch scope {
        case .everything: return true
        case .myPlayers: return pitch.hitterId.map(myHitterIds.contains) ?? false
        }
    }

    /// Merged timeline: by when it happened, not when it arrived; ties by id
    /// so the order never flickers.
    static func merged(_ feeds: [(title: String, events: [GameFeedEvent])]) -> [TimelineItem] {
        var items: [TimelineItem] = []
        for feed in feeds {
            for event in feed.events { items.append(TimelineItem(feedTitle: feed.title, event: event)) }
        }
        return items.sorted(by: TimelineItem.happenedBefore)
    }

    struct TimelineItem: Equatable {
        var feedTitle: String
        var event: GameFeedEvent

        static func happenedBefore(_ a: TimelineItem, _ b: TimelineItem) -> Bool {
            if a.event.at != b.event.at { return a.event.at < b.event.at }
            if a.event.id != b.event.id { return a.event.id < b.event.id }
            return a.feedTitle < b.feedTitle
        }
    }

    /// What changed between what's on the feed and the game's pitches now:
    /// events to write (new or different) and ids to delete (undone).
    /// Most plays one sync may delete. An undo takes back one pitch; more
    /// at once is a glitch (a list reloading), never a reason to empty a feed.
    static let maxDeletesPerSync = 3

    /// HIGH RISK (2026-11-24, user: the feed cleared on the follower's phone
    /// when the scorer's phone turned off). A play is deleted only when it
    /// was in the last sync's list (`lastWantedIds`, this session) and has
    /// gone from this one - an undo. Never with an empty list, never a play
    /// from an earlier session, never more than `maxDeletesPerSync`.
    static func diff(current: [String: GameFeedEvent], wanted: [GameFeedEvent],
                     lastWantedIds: Set<String>? = nil) -> (write: [GameFeedEvent], delete: [String]) {
        let wantedIds = Set(wanted.map(\.id))
        let write = wanted.filter { current[$0.id] != $0 }
        guard !wanted.isEmpty, let lastWantedIds else { return (write, []) }
        let delete = current.keys.filter { lastWantedIds.contains($0) && !wantedIds.contains($0) }.sorted()
        return (write, delete.count > maxDeletesPerSync ? [] : delete)
    }

    /// The plays that made an out, for the red text (user, 2026-11-24): an
    /// out or strikeout, or the outs going up within the half (a runner
    /// out on a fielder's choice, a double play). `events` in time order.
    static func outPlays(_ events: [GameFeedEvent]) -> Set<String> {
        var result: Set<String> = []
        var previous: GameFeedEvent? = nil
        for e in events.sorted(by: { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }) {
            if e.kind == "out" || e.kind == "strikeout" {
                result.insert(e.id)
            } else if let p = previous, let outs = e.outs, let before = p.outs,
                      p.inning == e.inning, p.batting == e.batting, outs > before {
                result.insert(e.id)
            }
            previous = e
        }
        return result
    }
}
