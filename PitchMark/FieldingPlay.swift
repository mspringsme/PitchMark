//
//  FieldingPlay.swift
//  PitchMark
//
//  Who fielded a pitch's outs and errors, and who was playing where when it
//  was thrown (2026-11-03). Saved on the PitchEvent; the stats built from it
//  are in FieldingStats.swift.
//
//  - `fieldingOuts`: one entry per out the defense made on the play, the
//    fielders who handled it in order ("6-3" is ["SS", "1B"]). The last one
//    made the putout; the others get an assist. A strikeout's out is the
//    catcher's and is never asked.
//  - `errorPositions`: who made the error(s) on the play (E6 = ["SS"]).
//  - `defense`: the fielding team's positions at that pitch. The game only
//    stores where everyone is now (`Game.fieldPositionByBatterId`), so this
//    copy is what keeps a mid-game position change from moving old credit.
//
//  Compiled into the Display target too (PitchEvent and the result sheet
//  are), so it is listed in that target's membershipExceptions.
//

import Foundation

struct FieldingOut: Codable, Hashable {
    /// `FieldingPlay.batterKey` for the batter, else the base the runner
    /// started from ("1", "2", "3").
    var runner: String
    /// Fielders who handled the ball, in order. The last made the putout.
    var positions: [String]
}

/// One fielder's spot on a pitch's copy of the defense.
struct DefenseSlot: Codable, Hashable {
    var position: String
    /// The lineup cell (`JerseyCell.id`).
    var batterId: String
    /// The player's Hitter record - who fielding credit goes to.
    var hitterId: String?
    /// "#12", for showing the slot without a roster.
    var label: String
}

enum FieldingPlay {
    static let batterKey = "batter"

    /// The nine who field, in scorebook number order (P = 1 ... RF = 9). DH
    /// doesn't field.
    static let positions = ["P", "C", "1B", "2B", "3B", "SS", "LF", "CF", "RF"]

    static func number(_ position: String) -> Int? {
        positions.firstIndex(of: position).map { $0 + 1 }
    }

    /// An out on the play the sheet asks about.
    struct OutSlot: Hashable {
        let runner: String
        let label: String
    }

    /// The outs a play's fielders can be credited with: each runner (or the
    /// batter) the play put out, or the batter alone on a plain out with
    /// nobody on. A strikeout's batter is the catcher's automatically.
    static func outSlots(play: BasePlay?, batterOutOnPlay: Bool, isStrikeout: Bool) -> [OutSlot] {
        if let play {
            return play.moves
                .filter { $0.to == Base.out }
                .sorted { $0.from > $1.from }
                .compactMap { move in
                    if move.runner == RunnerMove.batterKey {
                        return isStrikeout ? nil : OutSlot(runner: batterKey, label: "Batter")
                    }
                    return OutSlot(runner: String(move.from), label: "Runner from \(Base.name(move.from))")
                }
        }
        if batterOutOnPlay && !isStrikeout {
            return [OutSlot(runner: batterKey, label: "Batter")]
        }
        return []
    }

    /// The outs of a saved pitch, by the same rule.
    static func outSlots(for event: PitchEvent) -> [OutSlot] {
        let outcome = (event.outcome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return outSlots(
            play: event.play,
            batterOutOnPlay: outcome.caseInsensitiveCompare("Out") == .orderedSame,
            isStrikeout: event.atBatEnd == .strikeout
        )
    }

    /// Whether the play had an error to charge: the Error button, or a
    /// runner who took an extra base on one.
    static func hasError(errorOnPlay: Bool, play: BasePlay?) -> Bool {
        errorOnPlay || (play?.moves.contains { $0.extraBasesOn == ExtraBasesReason.error.rawValue } ?? false)
    }

    /// The fielders for `slots`, in slot order, dropping unknown positions
    /// and outs nobody was entered for. nil when nothing is left.
    static func outs(_ answers: [String: [String]], slots: [OutSlot]) -> [FieldingOut]? {
        let outs = slots.compactMap { slot -> FieldingOut? in
            let fielders = (answers[slot.runner] ?? []).filter { positions.contains($0) }
            return fielders.isEmpty ? nil : FieldingOut(runner: slot.runner, positions: fielders)
        }
        return outs.isEmpty ? nil : outs
    }

    /// Saved outs that still match the play (an edit can change it).
    static func consistentOuts(_ outs: [FieldingOut]?, for event: PitchEvent) -> [FieldingOut]? {
        let answers = Dictionary((outs ?? []).map { ($0.runner, $0.positions) }, uniquingKeysWith: { first, _ in first })
        return self.outs(answers, slots: outSlots(for: event))
    }

    static func consistentErrors(_ errors: [String]?, for event: PitchEvent) -> [String]? {
        guard hasError(errorOnPlay: event.errorOnPlay, play: event.play) else { return nil }
        let kept = (errors ?? []).filter { positions.contains($0) }
        return kept.isEmpty ? nil : kept
    }

    /// The fielding team's copy of the defense: every cell holding a
    /// fielding position, in scorebook order.
    static func defense(
        cells: [(batterId: UUID, hitterId: String?, label: String)],
        positions positionByBatterId: [UUID: String]
    ) -> [DefenseSlot] {
        cells.compactMap { cell -> DefenseSlot? in
            guard let position = positionByBatterId[cell.batterId], positions.contains(position) else { return nil }
            let hitterId = cell.hitterId?.trimmingCharacters(in: .whitespacesAndNewlines)
            return DefenseSlot(
                position: position,
                batterId: cell.batterId.uuidString,
                hitterId: (hitterId?.isEmpty == false) ? hitterId : nil,
                label: cell.label
            )
        }
        .sorted { (number($0.position) ?? 99) < (number($1.position) ?? 99) }
    }

    /// Scorebook text for one out: "6-3", or "F8" / "3U" for one fielder
    /// (a fly, pop or liner is caught; anything else is unassisted).
    static func notation(_ out: FieldingOut, descriptor: String?) -> String {
        let numbers = out.positions.compactMap(number).map(String.init)
        guard numbers.count == 1, let only = numbers.first else { return numbers.joined(separator: "-") }
        let caught = ["fly", "pop", "line"].contains { descriptor?.lowercased().contains($0) == true }
        return caught ? "F\(only)" : "\(only)U"
    }

    /// The card line for a pitch's fielding: "6-3", "6-4, 4-3", "E6".
    static func summary(outs: [FieldingOut]?, errors: [String]?, descriptor: String?) -> String? {
        var parts = (outs ?? []).map { notation($0, descriptor: descriptor) }
        parts += (errors ?? []).compactMap(number).map { "E\($0)" }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
