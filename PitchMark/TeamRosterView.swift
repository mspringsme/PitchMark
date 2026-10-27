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
//  added for both the team itself and its players - tap a player row to
//  open Player Details (stats buttons sit beside the name), swipe to
//  delete it (deliberately separate from tap, so delete is never one
//  accidental tap away, same reasoning AssetLibraryView already uses).
//
//  Adding a player creates a real cross-team `Player` (Player.swift) with
//  both a linked Pitcher and a linked Hitter, always - no role designation
//  to pick, since a kid might pitch, bat, or both over a season. A player
//  created before this existed gets backfilled with whichever is missing
//  the moment the roster loads (ensureTeamPlayerHasPitcherAndHitter),
//  silently - no edit action required.
//
//  Linking a kid across teams, merging an accidental duplicate and deleting
//  a player everywhere are a separate flow - Link Profiles
//  (LinkProfilesView.swift), its own card on Home. This screen only *shows*
//  the result ("Also on 14U").
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
    /// True when this team is either side of the game open in the tracker.
    /// Its players can't be removed and the team can't be archived until
    /// that game is closed (`OpenGameLock`).
    var isInOpenGame: Bool = false
    var onCloseGame: () -> Void = {}

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var players: [TeamPlayer] = []
    @State private var newPlayerName: String = ""
    @State private var newPlayerJersey: String = ""
    @State private var newPlayerPositions: Set<FieldPosition> = []
    @State private var newPlayerBattingSide: BattingSide? = nil
    @State private var addPlayerErrorMessage: String? = nil
    @State private var myPlayers: [Player] = []
    // Cross-team roster rows, so each row can say which other teams this
    // same kid is on ("Also on 14U") and View Stats can read all of a
    // linked kid's records.
    @State private var rosterEntries: [PlayerRosterEntry] = []

    // For the "View Stats" actions - PitcherStatsSheetView/HitterStatsView
    // need the actual Pitcher/Hitter objects and the owner's full
    // games/teams list, not just ids.
    @State private var myPitchers: [Pitcher] = []
    @State private var myHitters: [Hitter] = []
    @State private var myGames: [Game] = []
    @State private var myTeams: [(team: Team, membership: TeamMembership)] = []
    @State private var statsPitcher: Pitcher? = nil
    @State private var statsHitter: Hitter? = nil
    /// Every record of the person whose stats are open - more than one once
    /// two entries with tracked history were linked (see
    /// `mergeTeamPlayerIntoPlayer`); the stats sheets read them as one.
    @State private var statsPitcherIds: [String] = []
    @State private var statsHitterIds: [String] = []
    /// Only the teams this player is on - the stats sheets' Teams filter
    /// row lists exactly these.
    @State private var statsTeams: [Team] = []

    @State private var teamName: String = ""
    /// Mirrors `teamName`: the sheet's own copy, so an edit shows up here
    /// without waiting for the presenting list to reload.
    @State private var teamDesignation: TeamDesignation? = nil
    @State private var editTeamDesignation = TeamDesignationDraft()

    @State private var editingPlayer: TeamPlayer? = nil

    @State private var playerPendingRemoval: TeamPlayer? = nil
    @State private var showRemovedPlayers = false

    @State private var showTeamActionsDialog = false
    @State private var isRenamingTeam = false
    @State private var renameTeamText: String = ""
    @State private var showArchiveTeamDialog = false
    @State private var showLeaveTeamDialog = false
    @State private var openGameLockMessage: String? = nil

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

    /// Nothing here is ever deleted: a player taken off the roster is an
    /// archived row (`setTeamPlayerArchived`), kept for Restore and so their
    /// stats keep their team.
    private var activePlayers: [TeamPlayer] { players.filter { $0.archivedAt == nil } }
    private var removedPlayers: [TeamPlayer] { players.filter { $0.archivedAt != nil } }

    private var isTeamArchived: Bool {
        selection.team.id.map { authManager.archivedTeamIds.contains($0) } ?? false
    }

    var body: some View {
        NavigationView {
            List {
                Section("Roster") {
                    if activePlayers.isEmpty {
                        Text(isTeamOwner ? "No players yet - add your first one below." : "No players on this roster yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activePlayers, id: \.id) { player in
                            playerRow(player)
                        }
                    }
                }

                if !removedPlayers.isEmpty {
                    Section {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showRemovedPlayers.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Text(showRemovedPlayers ? "Hide Removed" : "Show Removed (\(removedPlayers.count))")
                                    .font(.subheadline.weight(.semibold))
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .rotationEffect(.degrees(showRemovedPlayers ? 0 : -90))
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        if showRemovedPlayers {
                            ForEach(removedPlayers, id: \.id) { player in
                                removedPlayerRow(player)
                            }
                        }
                    } footer: {
                        Text("Removed players keep their stats. Restore puts them back on this roster.")
                    }
                }

                if isTeamOwner {
                    Section {
                        TextField("Name", text: $newPlayerName)
                            .textInputAutocapitalization(.words)

                        TextField("Jersey #", text: $newPlayerJersey)

                        PositionToggleRow(selected: $newPlayerPositions)

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
                    } header: {
                        Text("Add Player")
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
                    // A member who isn't the creator can archive (it's their
                    // own view) and leave; editing the team and its roster
                    // is owner-only, matching what firestore.rules permits.
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            archiveTeamButton
                            Button("Leave Team", role: .destructive) {
                                showLeaveTeamDialog = true
                            }
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
            archiveTeamButton
            Button("Cancel", role: .cancel) { }
        }
        .appConfirmationDialog(
            isPresented: $showArchiveTeamDialog,
            title: "Archive \(teamName)?",
            message: "It'll be hidden from your Teams list and team pickers. Nothing is deleted: its roster, games and stats stay as they are, and other coaches on the team still see it. Unarchive it anytime from Teams → Show Archived.",
            primaryTitle: "Archive",
            primaryAction: {
                guard let teamId = selection.team.id else { return }
                authManager.setTeam(teamId, archived: true)
                dismiss()
            },
            secondaryTitle: "Cancel"
        )
        .appConfirmationDialog(
            isPresented: Binding(
                get: { playerPendingRemoval != nil },
                set: { if !$0 { playerPendingRemoval = nil } }
            ),
            title: "Remove \(playerPendingRemoval?.name ?? "this player") from \(teamName)?",
            message: "They come off this roster but nothing is deleted - they stay in your Players list with all their stats. You can restore them from Show Removed.",
            primaryTitle: "Remove",
            primaryRole: .destructive,
            primaryAction: { removePendingPlayer() },
            secondaryTitle: "Cancel"
        )
        .appConfirmationDialog(
            isPresented: Binding(
                get: { openGameLockMessage != nil },
                set: { if !$0 { openGameLockMessage = nil } }
            ),
            title: OpenGameLock.title,
            message: openGameLockMessage ?? "",
            primaryTitle: "Close Game",
            primaryAction: { onCloseGame() },
            secondaryTitle: "Not Now"
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
        .sheet(isPresented: $isRenamingTeam) {
            renameTeamSheet
        }
        .sheet(item: $editingPlayer) { player in
            editPlayerSheet(player)
        }
    }

    /// Presented from inside Player Details (the only place the stats
    /// buttons live), not from the roster root - a sheet can't present on a
    /// view that already has one up.
    private func statsSheets<Content: View>(_ content: Content) -> some View {
        content
        .sheet(item: $statsPitcher) { pitcher in
            PitcherStatsSheetView(
                pitcher: pitcher,
                combinedPitcherIds: statsPitcherIds,
                games: myGames,
                teams: statsTeams
            )
            .environmentObject(authManager)
            .fixedAppDynamicType()
        }
        .sheet(item: $statsHitter) { hitter in
            HitterStatsView(
                hitter: hitter,
                combinedHitterIds: statsHitterIds,
                games: myGames,
                teams: statsTeams
            )
            .environmentObject(authManager)
            .fixedAppDynamicType()
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
            crossTeamCaption(player)
            if isPlayerArchived(player) {
                Label("Archived - not shown in games. Swipe right to unarchive.", systemImage: "archivebox")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }

        if isTeamOwner {
            Button {
                beginEditing(player)
            } label: {
                label.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    if isInOpenGame {
                        openGameLockMessage = OpenGameLock.message(for: player.name)
                    } else {
                        playerPendingRemoval = player
                    }
                } label: {
                    Label("Remove", systemImage: "person.fill.xmark")
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                unarchivePlayerAction(player)
            }
        } else {
            label
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    unarchivePlayerAction(player)
                }
        }
    }

    /// Archiving a player (Home's Players list or Link Profiles) is per
    /// user and hides them from every game's bench and batter picker, but
    /// the roster still lists them - so it has to say so, or a roster of
    /// six that offers one in a game looks broken. Same rule the game
    /// screen applies (`isArchivedPlayer` in PitchTrackerView).
    private func isPlayerArchived(_ player: TeamPlayer) -> Bool {
        player.pitcherId.map { authManager.archivedPitcherIds.contains($0) } ?? false
    }

    @ViewBuilder
    private func unarchivePlayerAction(_ player: TeamPlayer) -> some View {
        if isPlayerArchived(player) {
            Button {
                // Every record of the person, matching what Archive hid.
                let ids = person(for: player)?.pitcherIds ?? []
                authManager.setPitchers(ids.isEmpty ? [player.pitcherId].compactMap { $0 } : ids, archived: false)
            } label: {
                Label("Unarchive", systemImage: "archivebox")
            }
            .tint(.orange)
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

    // MARK: - Cross-team

    private var profiles: [PlayerProfile] {
        PlayerLinks.profiles(rosterEntries: rosterEntries, pitchers: myPitchers, players: myPlayers)
    }

    private func person(for player: TeamPlayer) -> PlayerProfile? {
        PlayerLinks.profile(containing: player, in: profiles)
    }

    /// Every team this player is on (this one included), for the stats
    /// sheets' Teams filter row.
    private func teamsForStats(_ player: TeamPlayer) -> [Team] {
        let teams = person(for: player)?.teams ?? []
        return (teams.isEmpty ? [selection.team] : teams).sorted(by: Team.listOrder)
    }

    /// "Also on 14U" under a roster row.
    @ViewBuilder
    private func crossTeamCaption(_ player: TeamPlayer) -> some View {
        let others = person(for: player)?.otherTeams(than: selection.team.id) ?? []
        if !others.isEmpty {
            Label("Also on \(PlayerLinks.teamList(others))", systemImage: "link")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func reloadEverything() {
        refreshPlayers()
        refreshPlayerDirectory()
        authManager.loadMyPlayers { myPlayers = $0 }
        authManager.loadPitchers { myPitchers = $0 }
        authManager.loadHitters { myHitters = $0 }
    }

    /// Player Details itself lives in PlayerDetailsSheet.swift, shared with
    /// the game screen's lineup sheet; this roster adds only the stats
    /// buttons beside the name.
    private func editPlayerSheet(_ player: TeamPlayer) -> some View {
        let otherTeams = person(for: player)?.otherTeams(than: selection.team.id) ?? []
        return statsSheets(
            PlayerDetailsSheet(
                player: player,
                teamId: selection.team.id ?? "",
                teamName: teamName,
                otherTeams: otherTeams,
                nameAccessory: {
                    if player.pitcherId != nil {
                        statsButton("Pitching") { openPitchingStats(player) }
                    }
                    if player.hitterId != nil {
                        statsButton("Hitting") { openHittingStats(player) }
                    }
                },
                onCancel: { editingPlayer = nil },
                onSaved: { _, renamed in
                    if renamed {
                        refreshPlayerDirectory()
                        authManager.loadMyPlayers { myPlayers = $0 }
                        authManager.loadPitchers { myPitchers = $0 }
                        authManager.loadHitters { myHitters = $0 }
                    } else {
                        editingPlayer = nil
                        refreshPlayers()
                    }
                }
            )
        )
    }

    /// Borderless so two buttons can share a Form row - with the default
    /// style the whole row is one tap target and fires both.
    private func statsButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(Color.white)
                .background(Capsule().fill(Color.pitchMarkActiveGray))
        }
        .buttonStyle(.borderless)
        .fixedSize()
    }

    private func beginEditing(_ player: TeamPlayer) {
        editingPlayer = player
    }

    private func openPitchingStats(_ player: TeamPlayer) {
        statsPitcherIds = person(for: player)?.pitcherIds ?? []
        statsTeams = teamsForStats(player)
        statsPitcher = myPitchers.first(where: { $0.id == player.pitcherId })
    }

    private func openHittingStats(_ player: TeamPlayer) {
        statsHitterIds = person(for: player)?.hitterIds ?? []
        statsTeams = teamsForStats(player)
        statsHitter = myHitters.first(where: { $0.id == player.hitterId })
    }

    /// `myTeams` (memberships included - the stats sheets need them) plus
    /// every team's roster, which the "Also on" captions are built from.
    private func refreshPlayerDirectory() {
        authManager.loadMyTeams { teams, _ in
            myTeams = teams
            let justTeams = teams.map { $0.team }
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
                reloadEverything()
            case .failure(let error):
                addPlayerErrorMessage = error.localizedDescription
            }
        }
    }

    private func removePendingPlayer() {
        guard let player = playerPendingRemoval else { return }
        setArchived(player, archived: true)
        playerPendingRemoval = nil
    }

    private func setArchived(_ player: TeamPlayer, archived: Bool) {
        guard let teamId = selection.team.id, let playerId = player.id else { return }
        authManager.setTeamPlayerArchived(teamId: teamId, playerId: playerId, archived: archived) { result in
            if case .success = result {
                refreshPlayers()
                // The "Also on" captions are built from the cross-team rows,
                // which skip archived ones.
                refreshPlayerDirectory()
            }
        }
    }

    @ViewBuilder
    private func removedPlayerRow(_ player: TeamPlayer) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let jersey = player.jerseyNumber, !jersey.isEmpty {
                    Text("#\(jersey)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isTeamOwner {
                Button("Restore") { setArchived(player, archived: false) }
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.semibold))
            }
        }
    }

    /// Per-user, so any member can archive - it only changes their own
    /// Teams list.
    @ViewBuilder
    private var archiveTeamButton: some View {
        if isTeamArchived {
            Button("Unarchive Team") {
                guard let teamId = selection.team.id else { return }
                authManager.setTeam(teamId, archived: false)
            }
        } else {
            Button("Archive Team") {
                if isInOpenGame {
                    openGameLockMessage = "\(teamName) is playing in the game that's open right now. Close the game first, then archive."
                } else {
                    showArchiveTeamDialog = true
                }
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

    private func leaveTeam() {
        guard let teamId = selection.team.id else { return }
        authManager.leaveTeam(teamId: teamId) { result in
            if case .success = result {
                dismiss()
            }
        }
    }
}
