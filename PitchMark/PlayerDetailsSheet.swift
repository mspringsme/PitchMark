//
//  PlayerDetailsSheet.swift
//  PitchMark
//
//  The one Player Details editor: a team roster entry's name, jersey,
//  positions and batting side. Shared by TeamRosterView (tap a player) and
//  the game screen's lineup sheet (the pencil), so both edit a player the
//  same way and can't drift apart.
//
//  Labelled by reach, because the two behave differently: the name is the
//  *person's* and changes on every team (`propagatePlayerRename`); jersey,
//  positions and batting side are this roster's alone. Cross-team links are
//  shown, not edited, here - that all lives in Link Profiles.
//

import SwiftUI

struct PlayerDetailsSheet<NameAccessory: View>: View {
    let player: TeamPlayer
    let teamId: String
    let teamName: String
    /// The other teams this person is on, for the "Also On" section.
    let otherTeams: [Team]
    /// Trailing content on the name row - TeamRosterView's stats buttons.
    let nameAccessory: NameAccessory
    let onCancel: () -> Void
    /// After a successful save. `renamed` is true once the cross-team rename
    /// has also finished, so callers reloading names see the new one.
    let onSaved: (_ updated: TeamPlayer, _ renamed: Bool) -> Void

    @EnvironmentObject var authManager: AuthManager

    @State private var name: String
    @State private var jersey: String
    @State private var positions: Set<FieldPosition>
    @State private var battingSide: BattingSide?
    @State private var errorMessage: String? = nil
    @State private var isSaving = false

    init(
        player: TeamPlayer,
        teamId: String,
        teamName: String,
        otherTeams: [Team],
        @ViewBuilder nameAccessory: () -> NameAccessory,
        onCancel: @escaping () -> Void,
        onSaved: @escaping (_ updated: TeamPlayer, _ renamed: Bool) -> Void
    ) {
        self.player = player
        self.teamId = teamId
        self.teamName = teamName
        self.otherTeams = otherTeams
        self.nameAccessory = nameAccessory()
        self.onCancel = onCancel
        self.onSaved = onSaved
        _name = State(initialValue: player.name)
        _jersey = State(initialValue: player.jerseyNumber ?? "")
        _positions = State(initialValue: Set(player.positions ?? []))
        _battingSide = State(initialValue: player.battingSide)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack(spacing: 8) {
                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.words)
                        nameAccessory
                    }
                } header: {
                    Text("Name")
                } footer: {
                    Text(otherTeams.isEmpty
                         ? "Renaming also updates their stats."
                         : "Changes on every team they're on.")
                }

                Section {
                    TextField("Jersey #", text: $jersey)
                    PositionToggleRow(selected: $positions)
                    Picker("Batting Side", selection: $battingSide) {
                        Text("Not Set").tag(BattingSide?.none)
                        ForEach(BattingSide.allCases, id: \.self) { side in
                            Text(side.displayName).tag(BattingSide?.some(side))
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("On \(teamName) Only")
                } footer: {
                    Text("Jersey number, positions and batting side are set separately on each team.")
                }

                Section {
                    if otherTeams.isEmpty {
                        Text("Only on \(teamName).")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(otherTeams, id: \.id) { team in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(team.name)
                                    .font(.subheadline.weight(.semibold))
                                TeamDesignationBadge(designation: team.designation, alignment: .leading)
                            }
                        }
                    }
                } header: {
                    Text(otherTeams.isEmpty ? "Other Teams" : "Also On")
                } footer: {
                    Text("To link a player across teams, merge a duplicate or delete a player everywhere, use Link Profiles on Home.")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Player Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        guard let rowId = player.id else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedJersey = jersey.trimmingCharacters(in: .whitespaces)
        isSaving = true
        errorMessage = nil
        authManager.updateTeamPlayer(
            teamId: teamId,
            playerId: rowId,
            name: trimmedName,
            jerseyNumber: trimmedJersey.isEmpty ? nil : trimmedJersey,
            positions: positions.isEmpty ? nil : Array(positions),
            battingSide: battingSide
        ) { result in
            isSaving = false
            switch result {
            case .success:
                var updated = player
                updated.name = trimmedName
                updated.jerseyNumber = trimmedJersey.isEmpty ? nil : trimmedJersey
                updated.positions = positions.isEmpty ? nil : Array(positions)
                updated.battingSide = battingSide
                onSaved(updated, false)
                // Positions and batting side stay team-local on purpose
                // (see TeamPlayer in Team.swift), but a *name* does not: the
                // Pitcher/Hitter/Player docs and this kid's rows on other
                // teams all show it, so they move together.
                if trimmedName != player.name {
                    authManager.propagatePlayerRename(
                        name: trimmedName,
                        pitcherId: player.pitcherId,
                        playerId: player.playerId,
                        hitterId: player.hitterId
                    ) {
                        onSaved(updated, true)
                    }
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension PlayerDetailsSheet where NameAccessory == EmptyView {
    init(
        player: TeamPlayer,
        teamId: String,
        teamName: String,
        otherTeams: [Team],
        onCancel: @escaping () -> Void,
        onSaved: @escaping (_ updated: TeamPlayer, _ renamed: Bool) -> Void
    ) {
        self.init(
            player: player,
            teamId: teamId,
            teamName: teamName,
            otherTeams: otherTeams,
            nameAccessory: { EmptyView() },
            onCancel: onCancel,
            onSaved: onSaved
        )
    }
}

/// Capsule multi-select for FieldPosition, same visual language as the
/// Teams filter row in PitcherStatsSheetView and the Us/Them control in
/// PitchTrackerView (Color.pitchMarkActiveGray when selected).
struct PositionToggleRow: View {
    @Binding var selected: Set<FieldPosition>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(FieldPosition.allCases, id: \.self) { position in
                    let isSelected = selected.contains(position)
                    Button(position.rawValue) {
                        if isSelected {
                            selected.remove(position)
                        } else {
                            selected.insert(position)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(Capsule().fill(isSelected ? Color.pitchMarkActiveGray : Color(.systemGray6)))
                }
            }
        }
    }
}
