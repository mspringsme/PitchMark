//
//  LineupPlayerSheets.swift
//  PitchMark
//
//  The two sheets the game screen's lineup (gear) sheet opens on top of
//  itself: Player Details for a roster player, and Hitting Stats.
//
//  A top-level ViewModifier rather than more `.sheet`s inside
//  PitchTrackerView on purpose - that view sits right at the stack limit
//  (CLAUDE.md, the `___chkstk_darwin` entry), and every presentation
//  modifier added to its body grows the frame that overflows. Here the
//  tracker contributes one modifier call and two plain values.
//
//  Applied to the lineup sheet's own content, not to the tracker: a sheet
//  can only be presented from inside the sheet already on screen.
//

import SwiftUI

/// A roster player to edit from the lineup sheet.
struct LineupEditTarget: Identifiable {
    var id: String { player.id ?? player.name }
    let player: TeamPlayer
    let teamId: String
    let teamName: String
    /// The other teams this person is on, for Player Details' "Also On".
    var otherTeams: [Team] = []
}

/// A player whose hitting stats the lineup sheet should show.
struct LineupStatsTarget: Identifiable {
    var id: String { hitterId }
    let hitterId: String
    let name: String
}

struct LineupPlayerSheets: ViewModifier {
    @Binding var editTarget: LineupEditTarget?
    @Binding var statsTarget: LineupStatsTarget?
    let games: [Game]
    /// The open game, for Hitting Stats' This Game view.
    let currentGameId: String?
    let onPlayerSaved: (_ teamId: String, _ updated: TeamPlayer) -> Void

    @EnvironmentObject var authManager: AuthManager

    func body(content: Content) -> some View {
        content
            .sheet(item: $editTarget) { target in
                PlayerDetailsSheet(
                    player: target.player,
                    teamId: target.teamId,
                    teamName: target.teamName,
                    otherTeams: target.otherTeams,
                    onCancel: { editTarget = nil },
                    onSaved: { updated, renamed in
                        if !renamed {
                            editTarget = nil
                        }
                        onPlayerSaved(target.teamId, updated)
                    }
                )
                .environmentObject(authManager)
                .fixedAppDynamicType()
            }
            .sheet(item: $statsTarget) { target in
                // HitterStatsView only reads the id (to load events) and the
                // name (for its header), so no fetch is needed to build one.
                HitterStatsView(
                    hitter: Hitter(id: target.hitterId, name: target.name, ownerUid: ""),
                    combinedHitterIds: [target.hitterId],
                    games: games,
                    teams: [],
                    focusGameId: currentGameId
                )
                .environmentObject(authManager)
                .fixedAppDynamicType()
            }
    }
}
