//
//  HomeAddPlayerSheet.swift
//  PitchMark
//
//  Home's Players "+" (2026-11-05): the same player details as the roster
//  and in-game forms - team, name or number only, jersey, positions,
//  batting side - instead of the old name-only "New Pitcher" sheet.
//
//  Jersey, positions and batting side live on a team's roster row, so
//  they need a team. "No team" still makes a bare player record from just
//  a name, as the old sheet did.
//

import SwiftUI

struct HomeAddPlayerSheet: View {
    /// Teams this account can add players to (the teams it created).
    let teams: [Team]
    /// Adds to `teamId`'s roster; completion carries an error message.
    let onAddToTeam: (_ teamId: String, _ name: String, _ jersey: String?, _ positions: [FieldPosition]?,
                      _ battingSide: BattingSide?, _ completion: @escaping (String?) -> Void) -> Void
    /// A player with no team: just a name.
    let onAddWithoutTeam: (_ name: String) -> Void
    let onCancel: () -> Void

    /// nil = no team.
    @State private var teamId: String?
    @State private var name = ""
    @State private var jersey = ""
    @State private var numberOnly = false
    @State private var positions: Set<FieldPosition> = []
    @State private var battingSide: BattingSide? = nil
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    init(
        teams: [Team],
        onAddToTeam: @escaping (_ teamId: String, _ name: String, _ jersey: String?, _ positions: [FieldPosition]?,
                                _ battingSide: BattingSide?, _ completion: @escaping (String?) -> Void) -> Void,
        onAddWithoutTeam: @escaping (_ name: String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let sorted = teams.sorted(by: Team.listOrder)
        self.teams = sorted
        self.onAddToTeam = onAddToTeam
        self.onAddWithoutTeam = onAddWithoutTeam
        self.onCancel = onCancel
        _teamId = State(initialValue: HomeAddPlayer.defaultTeamId(sorted))
    }

    private var savedName: String? {
        HomeAddPlayer.savedName(typed: name, jersey: jersey, numberOnly: numberOnly, hasTeam: teamId != nil)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Team", selection: $teamId) {
                        ForEach(teams, id: \.id) { team in
                            Text(TeamFilterChips.label(for: team)).tag(team.id)
                        }
                        Text("No team").tag(String?.none)
                    }
                    .accessibilityIdentifier("addPlayer.team")
                } header: {
                    Text("Team")
                } footer: {
                    if teamId == nil {
                        Text("Jersey number, positions and batting side are kept on a team's roster. Add them to a team later from the roster screen.")
                    }
                }

                Section {
                    if teamId != nil {
                        Toggle("Number only (no name)", isOn: $numberOnly)
                            .accessibilityIdentifier("player.numberOnly")
                    }
                    if !numberOnly || teamId == nil {
                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.words)
                    }
                } header: {
                    Text("Name")
                }

                if teamId != nil {
                    Section {
                        TextField("Jersey #", text: $jersey)
                            .keyboardType(.numberPad)
                        PositionToggleRow(selected: $positions)
                        Picker("Batting Side", selection: $battingSide) {
                            Text("Not Set").tag(BattingSide?.none)
                            ForEach(BattingSide.allCases, id: \.self) { side in
                                Text(side.displayName).tag(BattingSide?.some(side))
                            }
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("On This Team")
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Add Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", action: save)
                        .disabled(isSaving || savedName == nil)
                }
            }
        }
    }

    private func save() {
        guard let savedName else { return }
        guard let teamId else {
            onAddWithoutTeam(savedName)
            return
        }
        let trimmedJersey = jersey.trimmingCharacters(in: .whitespaces)
        isSaving = true
        errorMessage = nil
        onAddToTeam(teamId, savedName, trimmedJersey.isEmpty ? nil : trimmedJersey,
                    positions.isEmpty ? nil : Array(positions), battingSide) { error in
            isSaving = false
            errorMessage = error
        }
    }
}

/// The form's rules, apart from the view so they can be tested.
enum HomeAddPlayer {
    /// The first team in list order, or no team when there are none.
    static func defaultTeamId(_ teams: [Team]) -> String? {
        teams.sorted(by: Team.listOrder).first?.id
    }

    /// Number only needs a team - the number is kept on its roster.
    static func savedName(typed: String, jersey: String, numberOnly: Bool, hasTeam: Bool) -> String? {
        NumberOnlyName.savedName(typed: typed, jersey: jersey, numberOnly: numberOnly && hasTeam)
    }
}
