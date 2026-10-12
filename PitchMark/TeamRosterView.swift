//
//  TeamRosterView.swift
//  PitchMark
//
//  Replaces ParentGameShellView (removed as part of the Coach/Parent
//  unification - see CLAUDE.md). A team row on Home now opens pure roster
//  management only; there is no Pitching/Batting tracking entry point here
//  anymore. Tracking always happens inside PitchTrackerView itself, reached
//  either as the game's owner or as a live-session participant via a join
//  code - never through a team row.
//

import SwiftUI

struct TeamEntrySelection: Identifiable {
    let team: Team
    let membership: TeamMembership
    var id: String { team.id ?? UUID().uuidString }
}

struct TeamRosterView: View {
    let selection: TeamEntrySelection

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var players: [TeamPlayer] = []
    @State private var newPlayerName: String = ""
    @State private var newPlayerJersey: String = ""

    private var isCoach: Bool { selection.membership.roles.contains(.coach) }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    rosterSection

                    if isCoach {
                        addPlayerSection
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal)
            }
            .navigationTitle(selection.team.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            refreshPlayers()
        }
    }

    @ViewBuilder
    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Roster")
                .font(.headline)

            if players.isEmpty {
                Text(isCoach ? "No players yet - add your first one below." : "No players on this roster yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(players, id: \.id) { player in
                        HStack {
                            Text(player.name)
                                .font(.subheadline.weight(.semibold))
                            if let jersey = player.jerseyNumber, !jersey.isEmpty {
                                Text("#\(jersey)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var addPlayerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add Player")
                .font(.headline)
            HStack {
                TextField("Name", text: $newPlayerName)
                    .textFieldStyle(.roundedBorder)
                TextField("Jersey #", text: $newPlayerJersey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Button("Add") {
                    addPlayer()
                }
                .disabled(newPlayerName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func refreshPlayers() {
        guard let teamId = selection.team.id else { return }
        authManager.loadTeamPlayers(teamId: teamId) { loaded in
            players = loaded
        }
    }

    private func addPlayer() {
        guard let teamId = selection.team.id else { return }
        let name = newPlayerName.trimmingCharacters(in: .whitespaces)
        let jersey = newPlayerJersey.trimmingCharacters(in: .whitespaces)
        authManager.addTeamPlayer(teamId: teamId, name: name, jerseyNumber: jersey.isEmpty ? nil : jersey, pitcherId: nil) { result in
            if case .success = result {
                newPlayerName = ""
                newPlayerJersey = ""
                refreshPlayers()
            }
        }
    }
}
