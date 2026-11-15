//
//  HomePlayerEditSheet.swift
//  PitchMark
//
//  Edit on Home's Players list (2026-11-14). It opens the same Player
//  Details editor the roster and the lineup sheet use - jersey, positions
//  and batting side are a team's, so a player on more than one of your
//  teams picks the team first (user's call). The list and the editor are
//  one sheet that swaps its content, not a sheet presenting a sheet.
//  A player on none of your teams (a bare Home + pitcher, or only on
//  another coach's team) keeps the name-only editor.
//

import SwiftUI

extension PlayerDirectory {
    /// The roster rows behind a Players row that this account may edit -
    /// rows on teams it created (the players rule is creator-only).
    /// Matched on the same ids `PlayerLinks.profiles` groups by.
    static func editableEntries(
        for row: PlayerDirectoryRow,
        in entries: [PlayerRosterEntry],
        uid: String?
    ) -> [PlayerRosterEntry] {
        guard let uid else { return [] }
        let pitcherIds = Set(row.pitcherIds + [row.pitcherId].compactMap { $0 })
        let hitterIds = Set(row.hitterIds + [row.hitterId].compactMap { $0 })
        return entries
            .filter { entry in
                let tp = entry.teamPlayer
                guard entry.team.createdByUid == uid, tp.id != nil, entry.team.id != nil else { return false }
                if let id = tp.playerId, id == row.playerId { return true }
                if let id = tp.pitcherId, pitcherIds.contains(id) { return true }
                if let id = tp.hitterId, hitterIds.contains(id) { return true }
                return false
            }
            .sorted {
                // Newest team first - most likely the one being edited.
                if $0.team.createdAt != $1.team.createdAt { return $0.team.createdAt > $1.team.createdAt }
                return $0.team.name.localizedCompare($1.team.name) == .orderedAscending
            }
    }
}

/// Which editor Home's Edit opens for a Players row (2026-11-14, user's
/// calls). Apart from the view so it can be tested.
enum HomePlayerEditRoute: Equatable {
    /// Every team they're on is another coach's: no Edit, a locked line.
    case locked
    /// Player Details on one of my teams (a team list first if several).
    case playerDetails([String])
    /// On no team: name + Add to Team.
    case addToTeam
    /// On a team of mine but no roster row of theirs matched: name only.
    case nameOnly

    static func route(for row: PlayerDirectoryRow, entries: [PlayerRosterEntry], uid: String?) -> HomePlayerEditRoute {
        if row.isOnlyOnOtherCoachesTeams(uid: uid) { return .locked }
        let editable = PlayerDirectory.editableEntries(for: row, in: entries, uid: uid)
        if !editable.isEmpty { return .playerDetails(editable.map(\.id)) }
        return row.teams.isEmpty ? .addToTeam : .nameOnly
    }
}

/// Home's two pitcher listeners (owned, shared in). Each snapshot replaces
/// its own source, so a deleted Pitcher drops out - one shared upsert-only
/// map kept Merge Duplicates' cleaned-up duplicate listed (2026-11-14).
struct LivePitcherSources {
    enum Source { case owned, shared }

    private(set) var owned: [String: Pitcher] = [:]
    private(set) var shared: [String: Pitcher] = [:]

    mutating func apply(_ pitchers: [Pitcher], from source: Source) {
        var map: [String: Pitcher] = [:]
        for pitcher in pitchers {
            if let id = pitcher.id { map[id] = pitcher }
        }
        switch source {
        case .owned: owned = map
        case .shared: shared = map
        }
    }

    /// Owned wins where a pitcher is in both.
    var all: [Pitcher] {
        Array(shared.merging(owned) { _, owned in owned }.values)
    }
}

/// What Home's Edit opens: the player's editable roster rows, plus every
/// team they're on (for Player Details' "Also On").
struct HomePlayerEditTarget: Identifiable {
    let id = UUID()
    let name: String
    let entries: [PlayerRosterEntry]
    let allTeams: [Team]
}

struct HomePlayerEditSheet: View {
    let target: HomePlayerEditTarget
    let onClose: () -> Void
    /// After any save; the caller reloads its roster rows.
    let onSaved: () -> Void

    @EnvironmentObject var authManager: AuthManager
    @State private var chosen: PlayerRosterEntry?

    init(target: HomePlayerEditTarget, onClose: @escaping () -> Void, onSaved: @escaping () -> Void) {
        self.target = target
        self.onClose = onClose
        self.onSaved = onSaved
        _chosen = State(initialValue: target.entries.count == 1 ? target.entries[0] : nil)
    }

    var body: some View {
        if let entry = chosen {
            PlayerDetailsSheet(
                player: entry.teamPlayer,
                teamId: entry.team.id ?? "",
                teamName: entry.team.name,
                otherTeams: target.allTeams.filter { $0.id != entry.team.id },
                onCancel: {
                    // Back to the list when there was one to pick from.
                    if target.entries.count > 1 { chosen = nil } else { onClose() }
                },
                onSaved: { _, renamed in
                    onSaved()
                    if !renamed { onClose() }
                }
            )
        } else {
            teamList
        }
    }

    private var teamList: some View {
        NavigationView {
            List {
                Section {
                    ForEach(target.entries) { entry in
                        Button {
                            chosen = entry
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.team.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    TeamDesignationBadge(designation: entry.team.designation, alignment: .leading)
                                }
                                Spacer(minLength: 8)
                                if let jersey = entry.teamPlayer.jerseyNumber, !jersey.isEmpty {
                                    Text("#\(jersey)")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("homePlayerEdit.team.\(entry.team.name)")
                    }
                } header: {
                    Text("Which team?")
                } footer: {
                    Text("Jersey number, positions and batting side are set separately on each team. The name changes on every team.")
                }
            }
            .navigationTitle(target.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onClose() }
                }
            }
        }
    }
}

// MARK: - No team

/// What Home's Edit opens for a player on none of your teams (2026-11-14,
/// user's call): the name, plus a Team picker. Leaving it on No team is a
/// plain rename. Picking a team shows the roster fields, and Save puts
/// them on that roster around their existing records
/// (`adoptAndLinkPlayer`), so their pitching history comes along.
struct HomeNoTeamPlayerEditTarget: Identifiable {
    let id = UUID()
    let pitcher: Pitcher
    /// Their `Player` doc, when they already have one (a merge or link can
    /// leave a player with an identity but no roster row).
    let playerId: String?
    let hitterId: String?
}

struct HomeNoTeamPlayerEditSheet: View {
    let target: HomeNoTeamPlayerEditTarget
    /// Teams this account created - the only rosters it can add to.
    let teams: [Team]
    let onClose: () -> Void
    let onSaved: () -> Void

    @EnvironmentObject var authManager: AuthManager

    /// nil = no team, the default: Edit shouldn't add anyone anywhere
    /// unless a team is picked.
    @State private var teamId: String? = nil
    @State private var name: String
    @State private var jersey = ""
    @State private var numberOnly = false
    @State private var positions: Set<FieldPosition> = []
    @State private var battingSide: BattingSide? = nil
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    init(
        target: HomeNoTeamPlayerEditTarget,
        teams: [Team],
        onClose: @escaping () -> Void,
        onSaved: @escaping () -> Void
    ) {
        self.target = target
        self.teams = teams.sorted(by: Team.listOrder)
        self.onClose = onClose
        self.onSaved = onSaved
        _name = State(initialValue: target.pitcher.name)
    }

    private var savedName: String? {
        HomeAddPlayer.savedName(typed: name, jersey: jersey, numberOnly: numberOnly, hasTeam: teamId != nil)
    }

    var body: some View {
        NavigationView {
            Form {
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
                } footer: {
                    Text("Renaming also updates their stats.")
                }

                Section {
                    Picker("Team", selection: $teamId) {
                        Text("No team").tag(String?.none)
                        ForEach(teams, id: \.id) { team in
                            Text(TeamFilterChips.label(for: team)).tag(team.id)
                        }
                    }
                    .accessibilityIdentifier("editPlayer.team")
                } header: {
                    Text("Add to Team")
                } footer: {
                    if teams.isEmpty {
                        Text("Create a team on Home to add them to a roster.")
                    } else if teamId == nil {
                        Text("Jersey number, positions and batting side are kept on a team's roster. Pick a team to set them.")
                    } else {
                        Text("Their tracked pitches come with them.")
                    }
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
            .navigationTitle("Edit Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onClose)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                        .disabled(isSaving || savedName == nil)
                }
            }
        }
    }

    private func save() {
        guard let savedName, let pitcherId = target.pitcher.id else { return }
        let renamed = savedName != target.pitcher.name
        guard let teamId else {
            guard renamed else { onClose(); return }
            isSaving = true
            authManager.updatePitcher(id: pitcherId, name: savedName, templateId: target.pitcher.templateId) { _ in
                authManager.propagatePlayerRename(
                    name: savedName, pitcherId: pitcherId, playerId: target.playerId, hitterId: target.hitterId
                ) {
                    onSaved()
                }
                isSaving = false
                onClose()
            }
            return
        }

        let trimmedJersey = jersey.trimmingCharacters(in: .whitespaces)
        let jerseyValue = trimmedJersey.isEmpty ? nil : trimmedJersey
        let positionsValue = positions.isEmpty ? nil : Array(positions)
        isSaving = true
        errorMessage = nil

        func finish(_ result: Result<TeamPlayer, Error>) {
            switch result {
            case .failure(let error):
                isSaving = false
                errorMessage = "Couldn't add them to the team: \(error.localizedDescription)"
            case .success(let row):
                // The row already carries the new name; this reaches the
                // Pitcher/Hitter/Player docs.
                if renamed {
                    authManager.propagatePlayerRename(
                        name: savedName, pitcherId: pitcherId, playerId: row.playerId, hitterId: row.hitterId
                    ) {
                        onSaved()
                    }
                }
                onSaved()
                isSaving = false
                onClose()
            }
        }

        func adopt() {
            authManager.adoptAndLinkPlayer(
                teamId: teamId,
                name: savedName,
                pitcherId: pitcherId,
                hitterId: target.hitterId,
                positions: positionsValue,
                battingSide: battingSide,
                jerseyNumber: jerseyValue,
                completion: finish
            )
        }

        if let playerId = target.playerId {
            // Already has an identity - link it rather than mint a second.
            authManager.loadPlayer(id: playerId) { player in
                guard var player else {
                    adopt()
                    return
                }
                player.name = savedName
                authManager.addTeamPlayerLinkingPlayer(teamId: teamId, player: player, jerseyNumber: jerseyValue) { result in
                    guard case .success(let row) = result, let rowId = row.id else { finish(result); return }
                    // A linked row starts from the Player's own positions;
                    // this team's are the ones just picked.
                    authManager.updateTeamPlayer(
                        teamId: teamId,
                        playerId: rowId,
                        name: savedName,
                        jerseyNumber: jerseyValue,
                        positions: positionsValue,
                        battingSide: battingSide
                    ) { update in
                        switch update {
                        case .success:
                            var updated = row
                            updated.positions = positionsValue
                            updated.battingSide = battingSide
                            finish(.success(updated))
                        case .failure(let error):
                            finish(.failure(error))
                        }
                    }
                }
            }
        } else {
            adopt()
        }

    }
}
