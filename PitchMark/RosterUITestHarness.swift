//
//  RosterUITestHarness.swift
//  PitchMark
//
//  `-UITestRoster` (2026-11-21): a team roster on its own, in memory, for
//  UI tests of its sections (Team Sponsors, Team Trading Cards). Nothing is
//  written - no one is signed in.
//

import SwiftUI

struct RosterUITestHarness: View {
    @EnvironmentObject var authManager: AuthManager

    private var selection: TeamEntrySelection {
        var team = Team(name: "Lightning", createdByUid: "uitest-coach")
        team.id = "uitest-team"
        let membership = TeamMembership(uid: "uitest-coach", roles: [.coach], addedByUid: "uitest-coach")
        return TeamEntrySelection(team: team, membership: membership)
    }

    var body: some View {
        TeamRosterView(selection: selection)
            .environmentObject(authManager)
    }
}
