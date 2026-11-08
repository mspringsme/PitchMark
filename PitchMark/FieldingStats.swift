//
//  FieldingStats.swift
//  PitchMark
//
//  Putouts, assists, errors, total chances, fielding % and double plays,
//  plus innings at each position, built from the fielding saved on each
//  pitch (FieldingPlay.swift, 2026-11-03).
//
//  How credit is given:
//  - Each out: the last fielder gets the putout; every other fielder who
//    handled it gets one assist (at most one each, even in a rundown).
//  - A strikeout is the catcher's putout, nothing tapped.
//  - Each error position: one error.
//  - A pitch that made two or more outs is a double play for every fielder
//    with a putout or assist on it.
//  - Innings: the outs made while a player held a position, / 3.
//  Credit goes to whoever held the position on that pitch's own copy of
//  the defense. A pitch without one (saved before this) adds nothing.
//

import Foundation

struct FieldingCounts: Equatable {
    var putouts = 0
    var assists = 0
    var errors = 0
    var doublePlays = 0
    /// Outs made while in the field here - innings are this / 3.
    var outsPlayed = 0

    var totalChances: Int { putouts + assists + errors }

    /// (PO + A) / TC, a whole percent; nil with no chances.
    var fieldingPercent: Int? {
        totalChances > 0 ? statPercent(putouts + assists, of: totalChances) : nil
    }

    var fieldingPercentText: String {
        fieldingPercent.map { "\($0)%" } ?? "—"
    }

    /// Baseball's thirds: 14 outs is "4.2".
    var inningsText: String {
        "\(outsPlayed / 3).\(outsPlayed % 3)"
    }

    static func + (lhs: FieldingCounts, rhs: FieldingCounts) -> FieldingCounts {
        FieldingCounts(
            putouts: lhs.putouts + rhs.putouts,
            assists: lhs.assists + rhs.assists,
            errors: lhs.errors + rhs.errors,
            doublePlays: lhs.doublePlays + rhs.doublePlays,
            outsPlayed: lhs.outsPlayed + rhs.outsPlayed
        )
    }
}

/// Every pitch's fielding, by who (Hitter id, nil when nobody held the
/// spot) and where.
struct FieldingLedger: Equatable {
    struct Key: Hashable {
        let hitterId: String?
        let position: String
    }

    private(set) var counts: [Key: FieldingCounts] = [:]

    init(events: [PitchEvent]) {
        for event in events {
            record(event)
        }
    }

    /// One pitch's credit, by position. Empty without a copy of the defense.
    static func credits(for event: PitchEvent) -> [String: FieldingCounts] {
        guard event.defense != nil else { return [:] }
        var result: [String: FieldingCounts] = [:]

        if event.atBatEnd == .strikeout {
            result["C", default: FieldingCounts()].putouts += 1
        }
        for out in FieldingPlay.consistentOuts(event.fieldingOuts, for: event) ?? [] {
            guard let putout = out.positions.last else { continue }
            result[putout, default: FieldingCounts()].putouts += 1
            for position in Set(out.positions.dropLast()) {
                result[position, default: FieldingCounts()].assists += 1
            }
        }
        for position in FieldingPlay.consistentErrors(event.errorPositions, for: event) ?? [] {
            result[position, default: FieldingCounts()].errors += 1
        }
        if GameProgress.outsMade(by: event) >= 2 {
            for (position, counts) in result where counts.putouts + counts.assists > 0 {
                result[position]?.doublePlays = 1
            }
        }
        return result
    }

    private mutating func record(_ event: PitchEvent) {
        guard let defense = event.defense else { return }
        let holder = Dictionary(defense.map { ($0.position, $0.hitterId) }, uniquingKeysWith: { first, _ in first })

        for (position, credit) in Self.credits(for: event) {
            let key = Key(hitterId: holder[position] ?? nil, position: position)
            counts[key] = (counts[key] ?? FieldingCounts()) + credit
        }
        let outs = GameProgress.outsMade(by: event)
        guard outs > 0 else { return }
        for slot in defense {
            let key = Key(hitterId: slot.hitterId, position: slot.position)
            counts[key, default: FieldingCounts()].outsPlayed += outs
        }
    }

    /// A player's line at each position they played (any of `hitterIds` -
    /// linked records are one person).
    func byPosition(hitterIds: Set<String>) -> [String: FieldingCounts] {
        var result: [String: FieldingCounts] = [:]
        for (key, value) in counts {
            guard let id = key.hitterId, hitterIds.contains(id) else { continue }
            result[key.position] = (result[key.position] ?? FieldingCounts()) + value
        }
        return result
    }

    /// A player's line, at one position or (nil) all of them.
    func total(hitterIds: Set<String>, position: String? = nil) -> FieldingCounts {
        byPosition(hitterIds: hitterIds)
            .filter { position == nil || $0.key == position }
            .values
            .reduce(FieldingCounts(), +)
    }

    /// The team's line at one position or (nil) all of them - players or
    /// not, so a spot nobody held still counts here.
    func teamTotal(position: String? = nil) -> FieldingCounts {
        counts
            .filter { position == nil || $0.key.position == position }
            .values
            .reduce(FieldingCounts(), +)
    }
}

extension FieldingLedger {
    /// Fielding pitches for `teamIds`' side, or (empty) any side. A pitch
    /// without `fieldingTeamId` can't be placed on a team.
    static func events(_ events: [PitchEvent], fieldingFor teamIds: Set<String>) -> [PitchEvent] {
        guard !teamIds.isEmpty else { return events }
        return events.filter { event in
            guard let id = event.fieldingTeamId else { return false }
            return teamIds.contains(id)
        }
    }
}
