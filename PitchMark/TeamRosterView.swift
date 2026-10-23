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
//  Owner-only (the team's actual creator, see isTeamOwner below) edit/delete
//  added for both the team itself and its players - tap a player row for
//  View Stats/Edit, swipe to delete it (deliberately separate from tap, so
//  delete is never one accidental tap away, same reasoning AssetLibraryView
//  already uses).
//
//  Adding a player creates a real cross-team `Player` (Player.swift) with
//  both a linked Pitcher and a linked Hitter, always - no role designation
//  to pick, since a kid might pitch, bat, or both over a season. A player
//  created before this existed gets backfilled with whichever is missing
//  the moment the roster loads (ensureTeamPlayerHasPitcherAndHitter),
//  silently - no edit action required. "Link Existing Player" is the
//  cross-team mechanism itself - pick one of your own Players from any team
//  instead of creating a new one, so the same kid's stats (via View Stats
//  on their row) span every team they're linked from, filterable per-team/
//  combined/career-wide.
//

import SwiftUI
import FirebaseAuth

struct TeamEntrySelection: Identifiable {
    let team: Team
    let membership: TeamMembership
    var id: String { team.id ?? UUID().uuidString }
}

struct TeamRosterView: View {
    let selection: TeamEntrySelection
    /// True when this team is one of the two sides of the game currently
    /// open in the Games tab. Deleting it out from under a live tracking
    /// session would strand that game's roster mid-game.
    var isInActiveGame: Bool = false
    /// Lets the presenting list drop the row immediately. Without it the
    /// only signal was a `loadMyTeams` reload on dismiss, which races the
    /// delete it is meant to reflect - so the deleted team stayed on
    /// screen until some later interaction happened to reload after the
    /// write had propagated.
    var onDeleted: ((String) -> Void)? = nil

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var players: [TeamPlayer] = []
    @State private var newPlayerName: String = ""
    @State private var newPlayerJersey: String = ""
    @State private var newPlayerPositions: Set<FieldPosition> = []
    @State private var newPlayerBattingSide: BattingSide? = nil
    @State private var addPlayerErrorMessage: String? = nil
    @State private var showLinkPlayerSheet = false
    @State private var myPlayers: [Player] = []
    // Cross-team roster rows + their teams, so "Link Existing Player" can
    // render the same Players rows Home does (PlayerDirectory.swift).
    @State private var rosterEntries: [PlayerRosterEntry] = []
    @State private var directoryTeams: [Team] = []

    // For the "View Stats" actions - PitcherStatsSheetView/HitterStatsView
    // need the actual Pitcher/Hitter objects and the owner's full
    // games/teams list, not just ids.
    @State private var myPitchers: [Pitcher] = []
    @State private var myHitters: [Hitter] = []
    @State private var myGames: [Game] = []
    @State private var myTeams: [(team: Team, membership: TeamMembership)] = []
    @State private var statsPitcher: Pitcher? = nil
    @State private var statsHitter: Hitter? = nil

    @State private var playerActionTarget: TeamPlayer? = nil
    @State private var showPlayerActionsDialog = false

    @State private var teamName: String = ""
    /// Mirrors `teamName`: the sheet's own copy, so an edit shows up here
    /// without waiting for the presenting list to reload.
    @State private var teamDesignation: TeamDesignation? = nil
    @State private var editTeamDesignation = TeamDesignationDraft()

    @State private var editingPlayer: TeamPlayer? = nil
    @State private var editPlayerName: String = ""
    @State private var editPlayerJersey: String = ""
    @State private var editPlayerPositions: Set<FieldPosition> = []
    @State private var editPlayerBattingSide: BattingSide? = nil
    @State private var editPlayerErrorMessage: String? = nil

    @State private var playerPendingDelete: TeamPlayer? = nil
    @State private var showDeletePlayerDialog = false

    @State private var showTeamActionsDialog = false
    @State private var isRenamingTeam = false
    @State private var renameTeamText: String = ""
    @State private var showDeleteTeamDialog = false
    @State private var showCantDeleteTeamDialog = false
    @State private var showCantDeleteActiveTeamDialog = false
    @State private var showLeaveTeamDialog = false

    /// Management rights (add/edit/delete) are gated on actually being the
    /// team's creator - matching exactly what firestore.rules enforces
    /// (`isTeamCreator()`, which never looks at TeamRole at all) - not on
    /// the `TeamRole` stored in this membership doc. Gating on role instead
    /// was a real bug: a team you created can still show "Parent" on your
    /// own membership (stale/leftover from earlier testing), which made a
    /// team you own and could otherwise fully manage look read-only with no
    /// way to edit or delete it.
    private var isTeamOwner: Bool {
        guard let uid = authManager.user?.uid else { return false }
        return selection.team.createdByUid == uid
    }

    var body: some View {
        NavigationView {
            List {
                Section("Roster") {
                    if players.isEmpty {
                        Text(isTeamOwner ? "No players yet - add your first one below." : "No players on this roster yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(players, id: \.id) { player in
                            playerRow(player)
                        }
                    }
                }

                if isTeamOwner {
                    Section("Add Player") {
                        TextField("Name", text: $newPlayerName)
                        TextField("Jersey #", text: $newPlayerJersey)

                        positionToggleRow(selected: $newPlayerPositions)

                        Picker("Batting Side", selection: $newPlayerBattingSide) {
                            Text("Not Set").tag(BattingSide?.none)
                            ForEach(BattingSide.allCases, id: \.self) { side in
                                Text(side.displayName).tag(BattingSide?.some(side))
                            }
                        }
                        .pickerStyle(.segmented)

                        Button("Add") {
                            addPlayer()
                        }
                        .disabled(newPlayerName.trimmingCharacters(in: .whitespaces).isEmpty)

                        if let addPlayerErrorMessage {
                            Text(addPlayerErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Button("Link Existing Player…") {
                            showLinkPlayerSheet = true
                        }
                    }
                }
            }
            .navigationTitle(teamName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isTeamOwner {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showTeamActionsDialog = true
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                } else {
                    // The only action available to a member who isn't the
                    // creator - everything else (add/edit/delete players,
                    // rename/delete the team) is owner-only, matching what
                    // firestore.rules actually permits them to do.
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Leave Team", role: .destructive) {
                            showLeaveTeamDialog = true
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
            teamDesignation = selection.team.designation
            refreshPlayers()
            authManager.loadMyPlayers { myPlayers = $0 }
            authManager.loadPitchers { myPitchers = $0 }
            authManager.loadHitters { myHitters = $0 }
            authManager.loadGames { myGames = $0 }
            refreshPlayerDirectory()
        }
        .confirmationDialog(
            teamName,
            isPresented: $showTeamActionsDialog,
            titleVisibility: .visible
        ) {
            Button("Edit Team") {
                renameTeamText = teamName
                editTeamDesignation = TeamDesignationDraft(teamDesignation)
                isRenamingTeam = true
            }
            Button("Delete Team", role: .destructive) {
                if isInActiveGame {
                    showCantDeleteActiveTeamDialog = true
                } else if players.isEmpty {
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
        .confirmationDialog(
            "This team is in the game you have open. On Home, open that game's ••• menu and tap \"Close Game\" first, then come back here.",
            isPresented: $showCantDeleteActiveTeamDialog,
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
        .appConfirmationDialog(
            isPresented: $showLeaveTeamDialog,
            title: "Leave \(teamName)?",
            message: "You'll stop seeing this team on your Home screen. The team itself, its roster, and its other members are unaffected.",
            primaryTitle: "Leave",
            primaryRole: .destructive,
            primaryAction: { leaveTeam() },
            secondaryTitle: "Cancel"
        )
        .confirmationDialog(
            playerActionTarget?.name ?? "Player",
            isPresented: $showPlayerActionsDialog,
            titleVisibility: .visible
        ) {
            if let player = playerActionTarget {
                if player.pitcherId != nil {
                    Button("View Pitching Stats") {
                        statsPitcher = myPitchers.first(where: { $0.id == player.pitcherId })
                    }
                }
                if player.hitterId != nil {
                    Button("View Hitting Stats") {
                        statsHitter = myHitters.first(where: { $0.id == player.hitterId })
                    }
                }
                Button("Edit") {
                    editingPlayer = player
                    editPlayerName = player.name
                    editPlayerJersey = player.jerseyNumber ?? ""
                    editPlayerPositions = Set(player.positions ?? [])
                    editPlayerBattingSide = player.battingSide
                    editPlayerErrorMessage = nil
                }
            }
            Button("Cancel", role: .cancel) { playerActionTarget = nil }
        }
        .sheet(isPresented: $isRenamingTeam) {
            renameTeamSheet
        }
        .sheet(item: $editingPlayer) { player in
            editPlayerSheet(player)
        }
        .sheet(isPresented: $showLinkPlayerSheet) {
            linkExistingPlayerSheet
                .fixedAppDynamicType()
        }
        .sheet(item: $statsPitcher) { pitcher in
            PitcherStatsSheetView(
                pitcher: pitcher,
                games: myGames,
                teams: myTeams.map { $0.team }
            )
            .environmentObject(authManager)
            .fixedAppDynamicType()
        }
        .sheet(item: $statsHitter) { hitter in
            HitterStatsView(
                hitter: hitter,
                games: myGames,
                teams: myTeams.map { $0.team }
            )
            .environmentObject(authManager)
            .fixedAppDynamicType()
        }
    }

    /// Capsule multi-select for FieldPosition, same visual language as the
    /// Teams filter row in PitcherStatsSheetView and the Us/Them control in
    /// PitchTrackerView (Color.pitchMarkActiveGray when selected).
    private func positionToggleRow(selected: Binding<Set<FieldPosition>>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(FieldPosition.allCases, id: \.self) { position in
                    let isSelected = selected.wrappedValue.contains(position)
                    Button(position.rawValue) {
                        if isSelected {
                            selected.wrappedValue.remove(position)
                        } else {
                            selected.wrappedValue.insert(position)
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

    /// "SS, 3B · R" style caption - only rendered when there's something to
    /// show, so a roster with no positions/batting-side set yet looks
    /// exactly like it did before this feature.
    @ViewBuilder
    private func playerSecondaryCaption(_ player: TeamPlayer) -> some View {
        let positionsText = (player.positions ?? []).map { $0.rawValue }.joined(separator: ", ")
        let sideText = player.battingSide?.displayName
        let parts = [positionsText.isEmpty ? nil : positionsText, sideText.map { "\($0.prefix(1))" }].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func playerRow(_ player: TeamPlayer) -> some View {
        let label = VStack(alignment: .leading, spacing: 2) {
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
            playerSecondaryCaption(player)
        }

        if isTeamOwner {
            Button {
                playerActionTarget = player
                showPlayerActionsDialog = true
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

    /// Renames and re-designates in one pass. The designation half is the
    /// only way to stamp a team created before designations existed, so Save
    /// stays enabled on the name alone - demanding all four here would leave
    /// a legacy team unrenameable until its coach filled them in.
    private var renameTeamSheet: some View {
        NavigationView {
            Form {
                Section("Name") {
                    TextField("Team name", text: $renameTeamText)
                }
                Section("Designation") {
                    TeamDesignationForm(draft: $editTeamDesignation, showsTitle: false)
                }
            }
            .navigationTitle("Edit Team")
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

    /// Everyone Home's Players list shows, minus whoever is already on this
    /// roster. Built from the identical inputs Home uses (every team's
    /// roster rows + every Pitcher doc), because scoping this to *owned
    /// `Player` docs* silently dropped two whole groups that Home lists: a
    /// roster row created before `Player` existed (`playerId == nil`) and a
    /// Pitcher created straight from Home's + (no roster row at all).
    /// `linkPlayerRow` mints the missing identity for those on selection.
    private var linkCandidateRows: [PlayerDirectoryRow] {
        let linkedPlayerIds = Set(players.compactMap { $0.playerId })
        let linkedPitcherIds = Set(players.compactMap { $0.pitcherId })
        let linkedRowIds = Set(players.compactMap { $0.id })

        var rows = PlayerDirectory.rows(rosterEntries: rosterEntries, pitchers: myPitchers)
            .filter { row in
                if let playerId = row.playerId, linkedPlayerIds.contains(playerId) { return false }
                if let pitcherId = row.pitcherId, linkedPitcherIds.contains(pitcherId) { return false }
                // Catches a row so old it has neither link - its directory
                // key is then the TeamPlayer id itself.
                return !linkedRowIds.contains(row.id)
            }

        // A Player whose only roster entry was deleted, and whose Pitcher
        // was archived out of `myPitchers`, has no row above but is still
        // perfectly linkable - carry it in from the Player doc.
        // Dedupe on the pitcher too, or a roster row that has no playerId
        // and a Player doc pointing at that same pitcher list the one kid
        // twice.
        let covered = Set(rows.compactMap { $0.playerId })
        let coveredPitchers = Set(rows.compactMap { $0.pitcherId })
        for player in myPlayers {
            guard let id = player.id,
                  !covered.contains(id),
                  !linkedPlayerIds.contains(id),
                  !(player.pitcherId.map { coveredPitchers.contains($0) } ?? false) else { continue }
            rows.append(
                PlayerDirectoryRow(
                    id: id,
                    name: player.name,
                    jersey: nil,
                    pitcher: player.pitcherId.flatMap { pid in myPitchers.first(where: { $0.id == pid }) },
                    pitcherId: player.pitcherId,
                    playerId: id,
                    hitterId: player.hitterId,
                    teams: [],
                    positions: Set(player.positions ?? []),
                    isStandalonePitcher: false
                )
            )
        }

        return rows.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Two link paths, same tap: an existing canonical `Player` links
    /// directly; anyone without one gets that identity minted around their
    /// existing Pitcher/Hitter first, so their career stats carry over
    /// instead of starting from scratch on new documents.
    private func linkPlayerRow(_ row: PlayerDirectoryRow) {
        if let playerId = row.playerId,
           let player = myPlayers.first(where: { $0.id == playerId }) {
            linkExistingPlayer(player)
            return
        }

        guard let teamId = selection.team.id else { return }
        let jersey = newPlayerJersey.trimmingCharacters(in: .whitespaces)
        authManager.adoptAndLinkPlayer(
            teamId: teamId,
            name: row.name,
            pitcherId: row.pitcherId,
            hitterId: row.hitterId,
            positions: row.positions.isEmpty ? nil : Array(row.positions),
            jerseyNumber: jersey.isEmpty ? nil : jersey
        ) { result in
            switch result {
            case .success:
                newPlayerJersey = ""
                showLinkPlayerSheet = false
                refreshPlayers()
                refreshPlayerDirectory()
                authManager.loadMyPlayers { myPlayers = $0 }
                authManager.loadPitchers { myPitchers = $0 }
                authManager.loadHitters { myHitters = $0 }
            case .failure(let error):
                addPlayerErrorMessage = error.localizedDescription
            }
        }
    }

    /// The actual cross-team mechanism: pick one of the signed-in user's own
    /// Players (from any team) instead of creating a new one, so the same
    /// kid's stats span both rosters. Deliberately explicit, no name
    /// matching/auto-linking.
    private var linkExistingPlayerSheet: some View {
        PlayerPickerSheet(
            title: "Link Existing Player",
            rows: linkCandidateRows,
            teams: directoryTeams,
            emptyMessage: "No other players to link yet - players you add (with \"Add\" above) on any team show up here afterward.",
            // Linking has nothing to do with pitching: a catcher with no P
            // on their positions must not be hidden behind the toggle.
            initialScope: .all,
            onSelect: { row in
                linkPlayerRow(row)
            }
        )
    }

    private func editPlayerSheet(_ player: TeamPlayer) -> some View {
        NavigationView {
            Form {
                TextField("Name", text: $editPlayerName)
                TextField("Jersey #", text: $editPlayerJersey)

                Section("Positions") {
                    positionToggleRow(selected: $editPlayerPositions)
                }

                Section("Batting Side") {
                    Picker("Batting Side", selection: $editPlayerBattingSide) {
                        Text("Not Set").tag(BattingSide?.none)
                        ForEach(BattingSide.allCases, id: \.self) { side in
                            Text(side.displayName).tag(BattingSide?.some(side))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

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

    /// `myTeams` (memberships included - the stats sheets need them) plus
    /// every team's roster, which is what the link picker's rows are built
    /// from.
    private func refreshPlayerDirectory() {
        authManager.loadMyTeams { teams, _ in
            myTeams = teams
            let justTeams = teams.map { $0.team }
            directoryTeams = justTeams
            authManager.loadPlayerRosterEntries(for: justTeams) { entries in
                rosterEntries = entries
            }
        }
    }

    private func refreshPlayers() {
        guard let teamId = selection.team.id else { return }
        authManager.loadTeamPlayers(teamId: teamId) { loaded in
            players = loaded
            // Self-healing backfill for anyone created before every player
            // always got both links - silent, no designation step needed.
            for player in loaded where player.pitcherId == nil || player.hitterId == nil {
                authManager.ensureTeamPlayerHasPitcherAndHitter(teamId: teamId, teamPlayer: player) { updated in
                    if let idx = players.firstIndex(where: { $0.id == updated.id }) {
                        players[idx] = updated
                    }
                }
            }
        }
    }

    private func addPlayer() {
        guard let teamId = selection.team.id else { return }
        let name = newPlayerName.trimmingCharacters(in: .whitespaces)
        let jersey = newPlayerJersey.trimmingCharacters(in: .whitespaces)
        addPlayerErrorMessage = nil
        authManager.addTeamPlayerCreatingNewPlayer(
            teamId: teamId,
            name: name,
            jerseyNumber: jersey.isEmpty ? nil : jersey,
            positions: newPlayerPositions.isEmpty ? nil : Array(newPlayerPositions),
            battingSide: newPlayerBattingSide
        ) { result in
            switch result {
            case .success:
                newPlayerName = ""
                newPlayerJersey = ""
                newPlayerPositions = []
                newPlayerBattingSide = nil
                refreshPlayers()
                refreshPlayerDirectory()
                authManager.loadMyPlayers { myPlayers = $0 }
                authManager.loadPitchers { myPitchers = $0 }
                authManager.loadHitters { myHitters = $0 }
            case .failure(let error):
                addPlayerErrorMessage = error.localizedDescription
            }
        }
    }

    private func linkExistingPlayer(_ player: Player) {
        guard let teamId = selection.team.id else { return }
        let jersey = newPlayerJersey.trimmingCharacters(in: .whitespaces)
        authManager.addTeamPlayerLinkingPlayer(
            teamId: teamId,
            player: player,
            jerseyNumber: jersey.isEmpty ? nil : jersey
        ) { result in
            if case .success = result {
                newPlayerJersey = ""
                showLinkPlayerSheet = false
                refreshPlayers()
                refreshPlayerDirectory()
            }
        }
    }

    private func saveEditedPlayer(_ player: TeamPlayer) {
        guard let teamId = selection.team.id, let playerId = player.id else { return }
        let name = editPlayerName.trimmingCharacters(in: .whitespaces)
        let jersey = editPlayerJersey.trimmingCharacters(in: .whitespaces)
        authManager.updateTeamPlayer(
            teamId: teamId,
            playerId: playerId,
            name: name,
            jerseyNumber: jersey.isEmpty ? nil : jersey,
            positions: editPlayerPositions.isEmpty ? nil : Array(editPlayerPositions),
            battingSide: editPlayerBattingSide
        ) { result in
            switch result {
            case .success:
                editingPlayer = nil
                refreshPlayers()
                // Positions and batting side stay team-local on purpose
                // (see TeamPlayer in Team.swift), but a *name* does not: the
                // Pitcher/Hitter/Player docs and this kid's rows on other
                // teams all show it, so they move together.
                if name != player.name {
                    authManager.propagatePlayerRename(
                        name: name,
                        pitcherId: player.pitcherId,
                        playerId: player.playerId,
                        hitterId: player.hitterId
                    ) {
                        refreshPlayerDirectory()
                        authManager.loadMyPlayers { myPlayers = $0 }
                        authManager.loadPitchers { myPitchers = $0 }
                        authManager.loadHitters { myHitters = $0 }
                    }
                }
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
        authManager.updateTeam(teamId: teamId, name: name, designation: editTeamDesignation.designation) { result in
            if case .success = result {
                teamName = name
                teamDesignation = editTeamDesignation.designation ?? teamDesignation
                isRenamingTeam = false
            }
        }
    }

    private func deleteTeam() {
        guard let teamId = selection.team.id else { return }
        authManager.deleteTeam(teamId: teamId) { result in
            switch result {
            case .success:
                // Tell the presenting list before dismissing: its own
                // onDismiss reload is a fresh Firestore read that can
                // easily still return this team, which is why a deleted
                // team used to linger until some unrelated interaction
                // reloaded late enough to miss it.
                onDeleted?(teamId)
                dismiss()
            case .failure(let error):
                debugLog("❌ deleteTeam failed:", error.localizedDescription)
            }
        }
    }

    private func leaveTeam() {
        guard let teamId = selection.team.id else { return }
        authManager.leaveTeam(teamId: teamId) { result in
            if case .success = result {
                dismiss()
            }
        }
    }
}
