//
//  LineupFieldPositions.swift
//  PitchMark
//
//  The gear sheet's batting-order arrows and in-game field positions
//  (2026-11-03). Arrows replaced drag-to-reorder; each lineup row's
//  position button sets where that player is on the field this game.
//
//  Positions are this game's, stored on the Game as
//  `fieldPositionByBatterId` (cell UUID string -> abbreviation) - not the
//  roster's `TeamPlayer.positions`, which says what a player can play.
//  Plain strings because the sheet is compiled into the Display target,
//  which doesn't have `FieldPosition`.
//

import Foundation

enum LineupFieldPositions {
    /// The nine on the field, then the designated hitter.
    static let choices = ["P", "C", "1B", "2B", "3B", "SS", "LF", "CF", "RF", "DH"]

    /// Gives `cellId` `position` (nil clears it). One player per position
    /// per team: anyone else on `teamCellIds` holding it loses it. The
    /// other team's cells are never touched.
    static func assign(
        _ position: String?,
        to cellId: UUID,
        in map: [UUID: String],
        teamCellIds: Set<UUID>
    ) -> [UUID: String] {
        var result = map
        if let position {
            for (id, held) in map where held == position && id != cellId && teamCellIds.contains(id) {
                result[id] = nil
            }
            result[cellId] = position
        } else {
            result[cellId] = nil
        }
        return result
    }

    /// The stored map, keyed by cell. Unknown keys and values are dropped.
    static func decode(_ stored: [String: String]?) -> [UUID: String] {
        var result: [UUID: String] = [:]
        for (key, value) in stored ?? [:] {
            guard let id = UUID(uuidString: key), choices.contains(value) else { continue }
            result[id] = value
        }
        return result
    }

    static func encode(_ map: [UUID: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: map.map { ($0.key.uuidString, $0.value) })
    }
}

enum LineupOrder {
    enum Direction { case up, down }

    /// The batter `cellId` would swap places with, moving one spot within
    /// its own team's order (`teamCells`, in batting order). nil at either
    /// end, or when the cell isn't on that team.
    static func neighbor(of cellId: UUID, in teamCells: [JerseyCell], direction: Direction) -> JerseyCell? {
        guard let index = teamCells.firstIndex(where: { $0.id == cellId }) else { return nil }
        let target = direction == .up ? index - 1 : index + 1
        guard teamCells.indices.contains(target) else { return nil }
        return teamCells[target]
    }
}
