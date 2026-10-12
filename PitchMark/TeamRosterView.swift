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
//  Coach-only edit/delete added for both the team itself and its players -
//  tap a player row to edit it, swipe to delete it (deliberately two
//  different gestures, so delete is never one accidental tap away, same
//  reasoning AssetLibraryView already uses). Adding a player here links a
//  real Pitcher doc (addTeamPlayerWithLinkedPitcher) so this roster
//  actually feeds the pitcher picker in games, not just a name list.
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
    @State private var addPlayerErrorMessage: String? = nil

    @State private var teamName: String = ""

    @State private var editingPlayer: TeamPlayer? = nil
    @State private var editPlayerName: String = ""
    @State private var editPlayerJersey: String = ""
    @State private var editPlayerErrorMessage: String? = nil

    @State private var playerPendingDelete: TeamPlayer? = nil
    @State private var showDeletePlayerDialog = false

    @State private var showTeamActionsDialog = false
    @State private var isRenamingTeam = false
    @State private var renameTeamText: String = ""
    @State private var showDeleteTeamDialog = false
    @State private var showCantDeleteTeamDialog = false

    private var isCoach: Bool { selection.membership.roles.contains(.coach) }

    var body: some View {
        NavigationView {
            List {
                Section("Roster") {
                    if players.isEmpty {
                        Text(isCoach ? "No players yet - add your first one below." : "No players on this roster yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(players, id: \.id) { player in
                            playerRow(player)
                        }
                    }
                }

                if isCoach {
                    Section("Add Player") {
                        TextField("Name", text: $newPlayerName)
                        TextField("Jersey #", text: $newPlayerJersey)
                        Button("Add") {
                            addPlayer()
                        }
                        .disabled(newPlayerName.trimmingCharacters(in: .whitespaces).isEmpty)

                        if let addPlayerErrorMessage {
                            Text(addPlayerErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(teamName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isCoach {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showTeamActionsDialog = true
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            teamName = selection.team.name
            refreshPlayers()
        }
        .confirmationDialog(
            teamName,
            isPresented: $showTeamActionsDialog,
            titleVisibility: .visible
        ) {
            Button("Rename Team") {
                renameTeamText = teamName
                isRenamingTeam = true
            }
            Button("Delete Team", role: .destructive) {
                if players.isEmpty {
                    showDeleteTeamDialog = true
                } else {
                    showCantDeleteTeamDialog = true
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog(
            "Remove all players from the roster before deleting the team.",
            isPresented: $showCantDeleteTeamDialog,
            titleVisibility: .visible
        ) {
            Button("OK") { }
        }
        .appConfirmationDialog(
            isPresented: $showDeleteTeamDialog,
            title: "Delete \(teamName)?",
            message: "This can't be undone.",
            primaryTitle: "Delete",
            primaryRole: .destructive,
            primaryAction: { deleteTeam() },
            secondaryTitle: "Cancel"
        )
        .appConfirmationDialog(
            isPresented: $showDeletePlayerDialog,
            title: "Delete \(playerPendingDelete?.name ?? "this player")?",
            message: "This removes them from the roster. Any linked pitcher and its pitch history stay intact.",
            primaryTitle: "Delete",
            primaryRole: .destructive,
            primaryAction: { deletePendingPlayer() },
            secondaryTitle: "Cancel",
            secondaryAction: { playerPendingDelete = nil }
        )
        .sheet(isPresented: $isRenamingTeam) {
            renameTeamSheet
        }
        .sheet(item: $editingPlayer) { player in
            editPlayerSheet(player)
        }
    }

    @ViewBuilder
    private func playerRow(_ player: TeamPlayer) -> some View {
        let label = HStack {
            Text(player.name)
                .font(.subheadline.weight(.semibold))
            if let jersey = player.jerseyNumber, !jersey.isEmpty {
                Text("#\(jersey)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }

        if isCoach {
            Button {
                editingPlayer = player
                editPlayerName = player.name
                editPlayerJersey = player.jerseyNumber ?? ""
                editPlayerErrorMessage = nil
            } label: {
                label.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    playerPendingDelete = player
                    showDeletePlayerDialog = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } else {
            label
        }
    }

    private var renameTeamSheet: some View {
        NavigationView {
            Form {
                TextField("Team name", text: $renameTeamText)
            }
            .navigationTitle("Rename Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isRenamingTeam = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        renameTeam()
                    }
                    .disabled(renameTeamText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func editPlayerSheet(_ player: TeamPlayer) -> some View {
        NavigationView {
            Form {
                TextField("Name", text: $editPlayerName)
                TextField("Jersey #", text: $editPlayerJersey)

                if let editPlayerErrorMessage {
                    Text(editPlayerErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Edit Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        editingPlayer = nil
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveEditedPlayer(player)
                    }
                    .disabled(editPlayerName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
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
        addPlayerErrorMessage = nil
        authManager.addTeamPlayerWithLinkedPitcher(teamId: teamId, name: name, jerseyNumber: jersey.isEmpty ? nil : jersey) { result in
            switch result {
            case .success:
                newPlayerName = ""
                newPlayerJersey = ""
                refreshPlayers()
            case .failure(let error):
                addPlayerErrorMessage = error.localizedDescription
            }
        }
    }

    private func saveEditedPlayer(_ player: TeamPlayer) {
        guard let teamId = selection.team.id, let playerId = player.id else { return }
        let name = editPlayerName.trimmingCharacters(in: .whitespaces)
        let jersey = editPlayerJersey.trimmingCharacters(in: .whitespaces)
        authManager.updateTeamPlayer(teamId: teamId, playerId: playerId, name: name, jerseyNumber: jersey.isEmpty ? nil : jersey) { result in
            switch result {
            case .success:
                editingPlayer = nil
                refreshPlayers()
            case .failure(let error):
                editPlayerErrorMessage = error.localizedDescription
            }
        }
    }

    private func deletePendingPlayer() {
        guard let teamId = selection.team.id, let playerId = playerPendingDelete?.id else { return }
        authManager.deleteTeamPlayer(teamId: teamId, playerId: playerId) { result in
            if case .success = result {
                playerPendingDelete = nil
                refreshPlayers()
            }
        }
    }

    private func renameTeam() {
        guard let teamId = selection.team.id else { return }
        let name = renameTeamText.trimmingCharacters(in: .whitespaces)
        authManager.updateTeam(teamId: teamId, name: name) { result in
            if case .success = result {
                teamName = name
                isRenamingTeam = false
            }
        }
    }

    private func deleteTeam() {
        guard let teamId = selection.team.id else { return }
        authManager.deleteTeam(teamId: teamId) { result in
            if case .success = result {
                dismiss()
            }
        }
    }
}
