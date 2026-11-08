//
//  SideScope.swift
//  PitchMark
//
//  Which batters and which pitchers belong to the side that's up, for the
//  At Bat scroll, the lineup sheet and the pitcher button.
//
//  A team whose roster *loaded* and is empty has no batters: its At Bat
//  scroll is blank until players are added (2026-11-02). Before, an empty
//  roster read as "still loading" and the scroll fell back to showing
//  everyone, so switching to that team changed nothing. A roster that
//  hasn't loaded (or failed to) still shows everything - blanking a real
//  lineup on a slow read is worse.
//

import Foundation

enum SideScope {
    /// Hitter ids of the batting team, or nil for "don't filter".
    static func battingHitterIds(teamId: String?, roster: [TeamPlayer], rosterLoaded: Bool) -> Set<String>? {
        guard teamId != nil else { return nil }
        let ids = Set(roster.compactMap { $0.hitterId })
        if ids.isEmpty && !rosterLoaded { return nil }
        return ids
    }

    /// The lineup cells to show. A cell with no roster link (a typed-in
    /// jersey number) always shows; a linked one only for its own team.
    static func visibleCells(_ cells: [JerseyCell], links: [UUID: String], battingHitterIds: Set<String>?) -> [JerseyCell] {
        guard let battingHitterIds else { return cells }
        return cells.filter { cell in
            guard let hitterId = links[cell.id] else { return true }
            return battingHitterIds.contains(hitterId)
        }
    }

    /// Away pitchers are the away roster's; everyone else pitches for us.
    static func pitcher(_ pitcherId: String, belongsTo side: GameSide, awayPitcherIds: Set<String>) -> Bool {
        side == .away ? awayPitcherIds.contains(pitcherId) : !awayPitcherIds.contains(pitcherId)
    }
}
