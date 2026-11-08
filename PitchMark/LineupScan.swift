//
//  LineupScan.swift
//  PitchMark
//
//  Scan Opponent Lineup (2026-11-06): the plain rules behind reading a
//  screenshot of a lineup, matching it to the opponent's roster and
//  adding it to a game. No Vision or Firestore here - the reader
//  (LineupScanReader) hands in text lines, the sheet and Home carry out
//  what these decide. Rules approved by the user 2026-11-06; see TESTING.md.
//

import Foundation
import SwiftUI

// MARK: - Reading

/// One piece of text the reader found: normalized to the image, origin
/// top-left (y grows down), so rows sort top to bottom.
struct LineupScanText: Equatable {
    var text: String
    var minX: Double
    var midY: Double
    var height: Double
    var confidence: Double

    init(_ text: String, x: Double, y: Double, height: Double = 0.02, confidence: Double = 1) {
        self.text = text
        self.minX = x
        self.midY = y
        self.height = height
        self.confidence = confidence
    }
}

/// One batter read off the image(s).
struct LineupScanRow: Equatable, Identifiable {
    var id = UUID()
    /// Batting order, when the image numbered its rows (rule 2).
    var order: Int?
    var jersey: String?
    /// The name as written, nil when only a number was read.
    var name: String?
    /// "Check this" (rule 6).
    var needsCheck = false
    /// The jersey was written with "#" (rule 12 reads the image's style).
    var jerseyMarked = false
    /// Looks like a batter, so the review starts with it kept (rule 12).
    /// Everything else waits under "Other text found".
    var likelyBatter = true

    /// What gets saved: the name, or "#12" for a number only (rule 5).
    var savedName: String {
        if let name, !name.isEmpty { return name }
        return NumberOnlyName.name(forJersey: jersey ?? "")
    }

    static func == (a: LineupScanRow, b: LineupScanRow) -> Bool {
        a.order == b.order && a.jersey == b.jersey && a.name == b.name && a.needsCheck == b.needsCheck
            && a.jerseyMarked == b.jerseyMarked && a.likelyBatter == b.likelyBatter
    }
}

enum LineupScanParser {
    /// Below this the reader wasn't sure (rule 6).
    static let confidenceFloor = 0.5

    /// Positions and batting side are recognised and thrown away (rule 3),
    /// so "SS" never ends up in a name.
    static let positionTokens: Set<String> = [
        "P", "C", "1B", "2B", "3B", "SS", "LF", "CF", "RF", "OF", "DH", "EH", "EP", "UT", "UTIL", "IF", "INF"
    ]
    static let sideTokens: Set<String> = [
        "L", "R", "S", "B", "(L)", "(R)", "(S)", "(B)", "L/L", "L/R", "R/L", "R/R", "S/R", "S/L", "B/R", "B/L"
    ]
    /// Header words (rule 4), compared lowercased without punctuation.
    static let headerWords: Set<String> = [
        "lineup", "line", "up", "batting", "order", "name", "names", "player", "players", "pos", "position",
        "positions", "no", "num", "number", "jersey", "bats", "throws", "bt", "avg", "starters", "starter",
        "bench", "team", "roster", "home", "away", "vs", "lineups"
    ]

    /// Summary rows (rule 10): a TEAM / TOTALS line is never a batter.
    static let summaryWords: Set<String> = ["team", "totals", "total"]

    /// One image's text into batters (rules 1-12).
    static func parse(_ texts: [LineupScanText]) -> [LineupScanRow] {
        let lines = groupIntoLines(texts)
        let tokenized = lines.map { line -> (tokens: [String], confidence: Double) in
            let tokens = line.flatMap { splitTokens($0.text) }
            return (tokens, line.map(\.confidence).min() ?? 1)
        }

        // Rule 2: a single plain number is the batting order only when the
        // rows' leading numbers run 1, 2, 3... down the image.
        let leading = tokenized.compactMap { line -> Int? in
            guard let first = line.tokens.first else { return nil }
            return plainNumber(first)
        }
        let numbered = isCountingSequence(leading)

        var rows: [LineupScanRow] = []
        for line in tokenized {
            guard var row = parseLine(line.tokens, numbered: numbered) else { continue }
            if line.confidence < confidenceFloor { row.needsCheck = true }
            rows.append(row)
        }
        return flagRepeatedJerseys(markLikelyBatters(rows))
    }

    /// Rule 12: which rows start kept. A batter has a jersey - a "#" one
    /// when most of this image's jerseys are written that way - and a name,
    /// unless the image is mostly numbers only. An image with no jerseys
    /// at all keeps its named rows only when they're numbered 1, 2, 3.
    static func markLikelyBatters(_ rows: [LineupScanRow]) -> [LineupScanRow] {
        let withJersey = rows.filter { $0.jersey != nil }
        let marked = withJersey.filter(\.jerseyMarked).count
        let hashStyle = marked >= 2 && marked * 2 >= withJersey.count
        let named = withJersey.filter { $0.name != nil }.count
        let numberOnlyStyle = withJersey.count - named > named
        return rows.map { row in
            var row = row
            if withJersey.isEmpty {
                row.likelyBatter = row.name != nil && row.order != nil
            } else {
                row.likelyBatter = row.jersey != nil
                    && (!hashStyle || row.jerseyMarked)
                    && (row.name != nil || numberOnlyStyle)
            }
            return row
        }
    }

    /// Several images, in the order they were picked (rule 7). An
    /// overlap repeated on the next screenshot is dropped; the same order
    /// number on a different player keeps both, flagged.
    static func merge(_ images: [[LineupScanRow]]) -> [LineupScanRow] {
        var merged: [LineupScanRow] = []
        for image in images {
            for row in image {
                if merged.contains(where: { sameBatter($0, row) }) { continue }
                if row.likelyBatter, let order = row.order,
                   let clash = merged.firstIndex(where: { $0.likelyBatter && $0.order == order }) {
                    merged[clash].needsCheck = true
                    var flagged = row
                    flagged.needsCheck = true
                    merged.append(flagged)
                    continue
                }
                merged.append(row)
            }
        }
        // Kept rows in batting order when they all have one (stable: equal
        // orders keep their pick order); other text keeps its read order.
        var batters = merged.filter(\.likelyBatter)
        let others = merged.filter { !$0.likelyBatter }
        if !batters.isEmpty, batters.allSatisfy({ $0.order != nil }) {
            batters = batters.enumerated()
                .sorted { ($0.element.order!, $0.offset) < ($1.element.order!, $1.offset) }
                .map(\.element)
        }
        return flagRepeatedJerseys(batters + others)
    }

    // MARK: Pieces

    /// Rule 1: text at the same height is one row; rows top to bottom,
    /// words left to right.
    static func groupIntoLines(_ texts: [LineupScanText]) -> [[LineupScanText]] {
        let sorted = texts
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.midY < $1.midY }
        var lines: [[LineupScanText]] = []
        var lineMid = 0.0
        var lineHeight = 0.0
        for text in sorted {
            if let _ = lines.last, abs(text.midY - lineMid) <= max(lineHeight, text.height) * 0.6 {
                lines[lines.count - 1].append(text)
                let line = lines[lines.count - 1]
                lineMid = line.map(\.midY).reduce(0, +) / Double(line.count)
                lineHeight = line.map(\.height).max() ?? text.height
            } else {
                lines.append([text])
                lineMid = text.midY
                lineHeight = text.height
            }
        }
        return lines.map { $0.sorted { $0.minX < $1.minX } }
    }

    /// Rule 8: "#" comes off whatever it's stuck to ("Hanew...#12").
    static func splitTokens(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).flatMap { word -> [String] in
            let word = String(word)
            guard let hash = word.firstIndex(of: "#"), hash != word.startIndex else { return [word] }
            return [String(word[..<hash]), String(word[hash...])]
        }
    }

    static func parseLine(_ tokens: [String], numbered: Bool) -> LineupScanRow? {
        // Rule 10: "TB: A McCalla 2, ..." / "SB: E Stephens" are summary lines.
        if let first = tokens.first, first.hasSuffix(":"), first.contains(where: { $0.isLetter }) { return nil }

        var hashJersey: String?
        var before: [String] = []   // numbers before the name: order / jersey
        var after: [String] = []    // numbers after it: stat columns (rule 9)
        var leadingPlain = false
        var nameWords: [String] = []
        var sawSummaryWord = false

        for (index, raw) in tokens.enumerated() {
            let token = raw.trimmingCharacters(in: CharacterSet(charactersIn: ",;:|"))
            if token.isEmpty { continue }
            let nameStarted = !nameWords.isEmpty
            if let jersey = hashNumber(token) {
                if hashJersey == nil { hashJersey = jersey }
                continue
            }
            if let number = plainNumberText(token) {
                if nameStarted {
                    after.append(number)
                } else {
                    if index == 0 { leadingPlain = true }
                    before.append(number)
                }
                continue
            }
            // A stat column's 0 read as the letter O.
            if nameStarted, token == "O" || token == "o" {
                after.append("0")
                continue
            }
            let upper = token.uppercased()
            // Rule 3: "(C)", "(1B)" always go; a bare position or side goes
            // too, except a single letter before the name - that's an
            // initial ("L Laxton", "C Suda").
            if token.hasPrefix("("), token.hasSuffix(")") {
                let inner = String(upper.dropFirst().dropLast())
                if positionTokens.contains(inner) || sideTokens.contains(inner) || sideTokens.contains(upper) { continue }
            }
            if positionTokens.contains(upper) || sideTokens.contains(upper) {
                if token.count > 1 { continue }
                if token == upper, nameStarted { continue }
            }
            if token == "#" { continue }
            let bare = token.lowercased().filter { $0.isLetter }
            if summaryWords.contains(bare) { sawSummaryWord = true; continue }
            if headerWords.contains(bare) { continue }
            guard token.contains(where: { $0.isLetter }) else { continue }
            nameWords.append(raw.trimmingCharacters(in: CharacterSet(charactersIn: ";:|")))
        }

        // Rule 10: a TEAM / TOTALS row.
        if sawSummaryWord && nameWords.isEmpty { return nil }

        var order: Int?
        var jersey = hashJersey
        if hashJersey != nil {
            // "#" marks the jersey, so a plain number before the name is the order.
            if let first = before.first, leadingPlain || numbered { order = Int(first) }
        } else if before.count >= 2 {
            order = Int(before[0])
            jersey = before[1]
        } else if let only = before.first {
            if numbered && leadingPlain {
                order = Int(only)
            } else {
                jersey = only
            }
        } else if after.count == 1 {
            // Rule 9's exception: "Jake Smith 12" on a lineup without "#".
            jersey = after[0]
        }

        var name = nameWords.joined(separator: " ")
        while name.hasSuffix(",") { name.removeLast() }
        name = name.trimmingCharacters(in: .whitespaces)
        // Rule 11: a name the app cut short.
        let truncated = name.contains("...") || name.contains("…")
        if name.hasSuffix("...") {
            name = String(name.dropLast(3))
        } else if name.hasSuffix("…") {
            name = String(name.dropLast())
        }
        name = name.trimmingCharacters(in: .whitespaces)
        let hasName = !name.isEmpty
        // Rule 5: no jersey and no name is not a batter (headers, totals).
        guard hasName || jersey != nil else { return nil }
        return LineupScanRow(
            order: order,
            jersey: jersey,
            name: hasName ? name : nil,
            needsCheck: truncated && !name.isEmpty,
            jerseyMarked: hashJersey != nil
        )
    }

    /// Rule 6: a jersey on more than one kept row needs a look - junk
    /// text can't flag real players.
    static func flagRepeatedJerseys(_ rows: [LineupScanRow]) -> [LineupScanRow] {
        var counts: [String: Int] = [:]
        for row in rows where row.likelyBatter { if let j = row.jersey { counts[j, default: 0] += 1 } }
        return rows.map { row in
            var row = row
            if row.likelyBatter, let j = row.jersey, (counts[j] ?? 0) > 1 { row.needsCheck = true }
            return row
        }
    }

    /// 1, 2, 3... (or 10, 11, 12 on a second screenshot). Two in a row
    /// is enough only when they start at 1, so two jerseys that happen to
    /// be consecutive don't turn into batting order.
    static func isCountingSequence(_ numbers: [Int]) -> Bool {
        guard numbers.count >= 2, let first = numbers.first else { return false }
        guard first == 1 || numbers.count >= 3 else { return false }
        return numbers.enumerated().allSatisfy { $0.element == first + $0.offset }
    }

    static func sameBatter(_ a: LineupScanRow, _ b: LineupScanRow) -> Bool {
        let aName = LineupNames.normalized(a.name)
        let bName = LineupNames.normalized(b.name)
        if let ao = a.order, let bo = b.order, ao != bo { return false }
        return a.jersey == b.jersey && aName == bName && (a.jersey != nil || aName != nil)
    }

    private static func hashNumber(_ token: String) -> String? {
        guard token.hasPrefix("#") else { return nil }
        let digits = token.dropFirst().trimmingCharacters(in: CharacterSet(charactersIn: ".,)"))
        guard (1...3).contains(digits.count), digits.allSatisfy(\.isNumber) else { return nil }
        return digits
    }

    private static func plainNumberText(_ token: String) -> String? {
        let digits = token.trimmingCharacters(in: CharacterSet(charactersIn: ".()"))
        guard (1...2).contains(digits.count), digits.allSatisfy(\.isNumber) else { return nil }
        return digits
    }

    private static func plainNumber(_ token: String) -> Int? {
        plainNumberText(token).flatMap(Int.init)
    }
}

// MARK: - Names

enum LineupNames {
    /// Lowercased letters and spaces; nil for no name or a number only.
    static func normalized(_ name: String?) -> String? {
        guard let name, NumberOnlyName.number(in: name) == nil else { return nil }
        let cleaned = name.lowercased()
            .map { $0.isLetter || $0 == " " || $0 == "," ? $0 : " " }
        let words = String(cleaned).split(separator: " ").map(String.init)
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// (first, last), reading "Smith, J." as last-first.
    static func parts(_ name: String?) -> (first: String?, last: String)? {
        guard let normalized = normalized(name) else { return nil }
        if let comma = normalized.firstIndex(of: ",") {
            let last = normalized[..<comma].trimmingCharacters(in: .whitespaces)
            let first = normalized[normalized.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            guard !last.isEmpty else { return nil }
            return (first.isEmpty ? nil : first, last.replacingOccurrences(of: ",", with: ""))
        }
        let words = normalized.split(separator: " ").map(String.init)
        guard let last = words.last else { return nil }
        return (words.count > 1 ? words[0] : nil, last)
    }

    /// Two names are the same person when the last names match and the
    /// first names (or initials) don't contradict each other. A missing
    /// name never disagrees.
    static func agree(_ a: String?, _ b: String?) -> Bool {
        guard let pa = parts(a), let pb = parts(b) else { return true }
        guard pa.last == pb.last else { return false }
        guard let fa = pa.first, let fb = pb.first else { return true }
        return fa.first == fb.first
    }

    /// Both names present and the same person.
    static func sameName(_ a: String?, _ b: String?) -> Bool {
        parts(a) != nil && parts(b) != nil && agree(a, b)
    }
}

// MARK: - Matching the opponent's roster

struct LineupRosterEntry: Equatable {
    var rowId: String
    var name: String
    var jersey: String?
    var archived: Bool = false
}

struct LineupMatch: Equatable {
    /// The roster row this batter is (nil = a new player).
    var rowId: String?
    /// Offered as a one-tap match when it couldn't be decided (rule 2).
    var suggestedRowId: String?
    var needsCheck: Bool
}

enum LineupRosterMatch {
    /// Rules 1-5. Jersey matches are settled first, so a name match
    /// can't take a player a later row matches by jersey.
    static func match(_ rows: [LineupScanRow], roster: [LineupRosterEntry]) -> [LineupMatch] {
        // Rule 5: removed players are never matched.
        let active = roster.filter { !$0.archived }
        var taken: Set<String> = []
        var results = Array(repeating: LineupMatch(rowId: nil, suggestedRowId: nil, needsCheck: false), count: rows.count)
        var settled = Array(repeating: false, count: rows.count)

        // Pass 1: same jersey.
        for (i, row) in rows.enumerated() {
            guard let jersey = clean(row.jersey) else { continue }
            let sameJersey = active.filter { clean($0.jersey) == jersey && !taken.contains($0.rowId) }
            guard !sameJersey.isEmpty else { continue }
            settled[i] = true
            let agreeing = sameJersey.filter { LineupNames.agree(row.name, $0.name) }
            if agreeing.count == 1 {
                results[i] = LineupMatch(rowId: agreeing[0].rowId, suggestedRowId: nil, needsCheck: row.needsCheck)
                taken.insert(agreeing[0].rowId)
            } else if agreeing.isEmpty, sameJersey.count == 1 {
                // Rule 2: same jersey, different name.
                results[i] = LineupMatch(rowId: nil, suggestedRowId: sameJersey[0].rowId, needsCheck: true)
            } else {
                // Rule 4: more than one could be them.
                results[i] = LineupMatch(rowId: nil, suggestedRowId: nil, needsCheck: true)
            }
        }

        // Pass 2: name only (rule 3).
        for (i, row) in rows.enumerated() where !settled[i] {
            guard LineupNames.parts(row.name) != nil else {
                results[i] = LineupMatch(rowId: nil, suggestedRowId: nil, needsCheck: row.needsCheck)
                continue
            }
            let byName = active.filter { LineupNames.sameName(row.name, $0.name) && !taken.contains($0.rowId) }
            if byName.count == 1 {
                let entry = byName[0]
                let jerseyDiffers = clean(row.jersey) != nil && clean(entry.jersey) != nil && clean(row.jersey) != clean(entry.jersey)
                results[i] = LineupMatch(rowId: entry.rowId, suggestedRowId: nil, needsCheck: row.needsCheck || jerseyDiffers)
                taken.insert(entry.rowId)
            } else if byName.count > 1 {
                results[i] = LineupMatch(rowId: nil, suggestedRowId: nil, needsCheck: true)
            } else {
                results[i] = LineupMatch(rowId: nil, suggestedRowId: nil, needsCheck: row.needsCheck)
            }
        }
        return results
    }

    private static func clean(_ jersey: String?) -> String? {
        guard let j = jersey?.trimmingCharacters(in: .whitespaces), !j.isEmpty else { return nil }
        return j
    }
}

// MARK: - Adding to the game

/// A reviewed batter, as the coach left it on the review screen.
struct LineupScanDecision: Equatable {
    var name: String
    var jersey: String?
    /// The existing roster player (rowId + hitterId), or nil for new.
    var existingRowId: String?
    var existingHitterId: String?
}

/// What Add to Game does, before anything is written.
struct LineupScanPlan: Equatable {
    /// One per new player: roster row to create, in batting order.
    var newPlayers: [LineupScanDecision]
    /// The lineup to append, in batting order. `.existing` carries the
    /// hitter id; `.new` is an index into `newPlayers`.
    var lineup: [Entry]

    enum Entry: Equatable {
        case existing(hitterId: String, display: String)
        case new(index: Int, display: String)
    }

    /// Rules for adding (1-2): matched players reuse their record, new
    /// ones get a row; the lineup only adds, skipping anyone already in
    /// this game and anyone listed twice.
    static func make(_ decisions: [LineupScanDecision], alreadyInLineup: Set<String>) -> LineupScanPlan {
        var newPlayers: [LineupScanDecision] = []
        var lineup: [Entry] = []
        var seenHitters = alreadyInLineup
        var seenRows: Set<String> = []
        for decision in decisions {
            if let rowId = decision.existingRowId {
                guard !seenRows.contains(rowId) else { continue }
                seenRows.insert(rowId)
                guard let hitterId = decision.existingHitterId, !hitterId.isEmpty else { continue }
                guard !seenHitters.contains(hitterId) else { continue }
                seenHitters.insert(hitterId)
                lineup.append(.existing(hitterId: hitterId, display: display(name: decision.name, jersey: decision.jersey)))
            } else {
                newPlayers.append(decision)
                lineup.append(.new(index: newPlayers.count - 1, display: display(name: decision.name, jersey: decision.jersey)))
            }
        }
        return LineupScanPlan(newPlayers: newPlayers, lineup: lineup)
    }

    /// Same label the tracker gives a roster player's lineup cell
    /// (`lineupDisplayNumber`): the jersey, else the name's first two letters.
    static func display(name: String, jersey: String?) -> String {
        if let jersey = jersey?.trimmingCharacters(in: .whitespaces), !jersey.isEmpty { return jersey }
        return String(name.prefix(2)).uppercased()
    }
}

/// Where Add to Game's writes go (adding rules 3-5).
enum LineupScanRoute: Equatable {
    /// Straight to the saved game; `closeFirst` when it's open on this
    /// device with no live room (closing is quiet - the user never sees it).
    case savedGame(closeFirst: Bool)
    /// Through the live room, from whichever phone scanned. The owner's
    /// phone also writes the same spots to the saved game, so a room that
    /// outlives the open game can't put an older lineup back over it.
    case liveRoom(alsoSavedGame: Bool)

    static func decide(isOwner: Bool, openInTracker: Bool, liveRoomOpen: Bool) -> LineupScanRoute {
        if !isOwner { return .liveRoom(alsoSavedGame: false) }
        if liveRoomOpen { return .liveRoom(alsoSavedGame: true) }
        return .savedGame(closeFirst: openInTracker)
    }
}

/// Lineup links (lineup spot -> hitter) carried in the live room, so a
/// partner's Bench / Put In Game / scan reaches the owner's saved game
/// (adding rule 5). Only the owner's phone writes the saved game.
enum LiveLineupLinks {
    static let field = "hitterIdByBatterId"

    /// The owner's links after a room snapshot: the room's entry wins
    /// for a spot it names, ours stand for the rest. Nil when nothing
    /// changes, so the owner doesn't write the same map back.
    static func ownerMerge(local: [String: String], room: [String: String]?) -> [String: String]? {
        guard let room, !room.isEmpty else { return nil }
        var merged = local
        for (spot, hitter) in room where !hitter.isEmpty { merged[spot] = hitter }
        return merged == local ? nil : merged
    }

    /// Whether this device writes links into the saved game.
    static func writesSavedGame(isOwner: Bool) -> Bool { isOwner }

    /// This game's field positions in the room (whole map - one player
    /// per position, so a change can move someone off a position).
    static let positionsField = "fieldPositionByBatterId"

    /// The positions the game should now have from a room snapshot: the
    /// room's map when it has one and it differs; nil = nothing to do. A
    /// room that never carried positions never clears the game's.
    static func positionsFromRoom(game: [String: String]?, room: [String: String]?) -> [String: String]? {
        guard let room else { return nil }
        return room == (game ?? [:]) ? nil : room
    }

    /// A8: what an empty room gets from the game - lineup plus the links
    /// for its own spots - or nil when the room already has a lineup (a
    /// partner's add that landed first is never overwritten) or the game
    /// has none worth copying.
    static func seedForEmptyRoom(roomJerseys: [String], gameJerseys: [String], gameIds: [String], gameLinks: [String: String]?) -> [String: Any]? {
        guard roomJerseys.isEmpty, !gameJerseys.isEmpty, gameIds.count == gameJerseys.count else { return nil }
        var update: [String: Any] = ["jerseyNumbers": gameJerseys, "batterIds": gameIds]
        for (spot, hitter) in gameLinks ?? [:] where gameIds.contains(spot) && !hitter.isEmpty {
            update["\(field).\(spot)"] = hitter
        }
        return update
    }

    /// What the coach's phone publishes when the room is missing it: the
    /// game's own map, so partners start with what the coach has.
    static func needsPublishing(game: [String: String]?, room: [String: String]?) -> [String: String]? {
        guard room == nil, let game, !game.isEmpty else { return nil }
        return game
    }
}

// MARK: - The review's Keep list (rule 12)

enum LineupReviewChoice: Equatable {
    /// "Same player" / a match the coach kept.
    case player(String)
    /// "Not them".
    case new
}

struct LineupReviewItem: Identifiable, Equatable {
    let id: UUID
    /// Where it was read (pick order, then top to bottom).
    let readIndex: Int
    var jersey: String
    var name: String
    var readCheck: Bool
    var keep: Bool
    var choice: LineupReviewChoice? = nil
}

/// The review screen's rows: the lineup (kept, in batting order) and
/// "Other text found" (not kept, in read order). Ticking a row puts it
/// into the lineup where it was read; unticking sends it back.
struct LineupReviewList: Equatable {
    private(set) var items: [LineupReviewItem]

    init(rows: [LineupScanRow]) {
        items = rows.enumerated().map { index, row in
            LineupReviewItem(id: row.id, readIndex: index, jersey: row.jersey ?? "", name: row.name ?? "",
                             readCheck: row.needsCheck, keep: row.likelyBatter)
        }
        items = kept + others
    }

    var kept: [LineupReviewItem] { items.filter(\.keep) }
    var others: [LineupReviewItem] { items.filter { !$0.keep }.sorted { $0.readIndex < $1.readIndex } }

    func item(_ id: UUID) -> LineupReviewItem? { items.first(where: { $0.id == id }) }

    mutating func update(_ item: LineupReviewItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    mutating func setKeep(_ id: UUID, _ keep: Bool) {
        guard var item = item(id), item.keep != keep else { return }
        item.keep = keep
        var lineup = kept.filter { $0.id != id }
        if keep {
            let at = lineup.firstIndex(where: { $0.readIndex > item.readIndex }) ?? lineup.count
            lineup.insert(item, at: at)
            items = lineup + others.filter { $0.id != id }
        } else {
            items = lineup + (others + [item]).sorted { $0.readIndex < $1.readIndex }
        }
    }

    mutating func moveKept(fromOffsets source: IndexSet, toOffset destination: Int) {
        var lineup = kept
        lineup.move(fromOffsets: source, toOffset: destination)
        items = lineup + others
    }

    mutating func deleteKept(atOffsets offsets: IndexSet) {
        let gone = Set(offsets.map { kept[$0].id })
        items.removeAll { gone.contains($0.id) }
    }

    /// Add Batter: a blank kept row at the end of the lineup.
    mutating func addBlank() {
        let next = (items.map(\.readIndex).max() ?? -1) + 1
        items = kept + [LineupReviewItem(id: UUID(), readIndex: next, jersey: "", name: "", readCheck: false, keep: true)] + others
    }
}
