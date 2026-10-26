//
//  PlayerDirectory.swift
//  PitchMark
//
//  One Players list, shared by every screen that shows players.
//
//  Home's Players section (SettingsView) grew the real one - avatar +
//  name/jersey caption, the team it comes from with its designation stamp,
//  "Bats only"/"Archived" flags, a Pitchers/All scope toggle and a
//  team/age-group/division filter. Two other places then listed the same
//  people as bare names with none of that context: the pitcher picker when
//  you enter a game, and "Link Existing Player" on a team roster. Picking
//  the right kid out of a plain list of names is exactly what the Home row
//  was built to fix (two kids named Hadley on different teams), so the row
//  model, row view, filter and picker all live here and Home consumes them
//  too - otherwise the two renderings drift apart again.
//
//  Note the row model collapses one *person*, not one roster entry: a kid
//  linked from two teams is a single row carrying both teams.
//

import SwiftUI

// MARK: - Roster entry

/// One `TeamPlayer` paired with the team it came from, so a row can show the
/// team's designation without a second lookup.
struct PlayerRosterEntry: Identifiable {
    let id: String
    let teamPlayer: TeamPlayer
    let team: Team

    init(teamPlayer: TeamPlayer, team: Team) {
        self.id = "\(team.id ?? "-")|\(teamPlayer.id ?? UUID().uuidString)"
        self.teamPlayer = teamPlayer
        self.team = team
    }
}

// MARK: - Scope + filter

/// What the Pitchers/All toggle switches between. `.pitchers` is the old
/// pitcher roster; `.all` adds every other player on your teams - kids who
/// only bat.
enum PlayerDirectoryScope: Hashable {
    case pitchers
    case all
}

struct PlayerDirectoryFilter: Equatable {
    var teamIds: Set<String> = []
    var ageGroups: Set<TeamAgeGroup> = []
    var divisions: Set<TeamDivision> = []
    /// Archive is a local, per-device notion and only pitchers have one.
    var showArchived = false

    /// Sentinel id for the filter's "No team" row - a real team id can never
    /// be empty, so it can share the same `Set<String>`.
    static let noTeamId = ""

    var isActive: Bool {
        !teamIds.isEmpty || !ageGroups.isEmpty || !divisions.isEmpty || showArchived
    }

    mutating func clear() {
        self = PlayerDirectoryFilter()
    }
}

// MARK: - Row model

/// What counts as "one row" when the same person carries more than one
/// pitching record - which happens once a coach links two separately-entered
/// roster entries together (`mergeTeamPlayerIntoPlayer`, Player.swift) and
/// both already had recorded history, so neither career could be discarded.
enum PlayerDirectoryCollapse {
    /// One row per *person*: keyed by the canonical `Player` first, so two
    /// roster entries that were folded onto one identity show up once even
    /// though they still point at two different Pitcher docs. What Home and
    /// the link pickers want.
    case person
    /// One row per *pitching record*: keyed by `pitcherId` first. What the
    /// tracker's pitcher picker wants - it selects a Pitcher, so a person
    /// with two of them has to be able to reach either.
    case pitchingRecord
}

/// One row in a Players list - one *person*, not one roster entry.
struct PlayerDirectoryRow: Identifiable {
    let id: String
    var name: String
    var jersey: String?
    var pitcher: Pitcher?
    var pitcherId: String?
    /// The cross-team `Player` identity (Player.swift) behind this row, when
    /// a roster entry carried one. "Link Existing Player" selects by this.
    var playerId: String?
    var hitterId: String?
    var teams: [Team]
    /// Union of the roster positions this player is listed at, across every
    /// team they're linked from.
    var positions: Set<FieldPosition>
    /// True when this row came from a standalone `Pitcher` record with no
    /// roster entry behind it - i.e. something created straight from Home's
    /// + button, or shared in. Those are pitchers by construction; there's
    /// no roster row to carry a position.
    var isStandalonePitcher: Bool

    /// Every distinct Pitcher/Hitter record this person's roster entries
    /// point at, primary first. More than one only after two
    /// separately-entered roster rows were linked together and both already
    /// had recorded history (see `PlayerDirectoryCollapse.person`); the Stats
    /// sheets are handed all of them and read them as one history. `pitcherId`/`hitterId` above stay the primary, so every
    /// existing single-record call site is unaffected.
    var pitcherIds: [String] = []
    var hitterIds: [String] = []

    /// **Not** `pitcher != nil`. Every `Player` in this app is created with
    /// both a linked Pitcher and a linked Hitter, always (`createPlayer`, and
    /// `ensureTeamPlayerHasPitcherAndHitter` backfills older ones), so
    /// `pitcherId` is non-nil for essentially everyone and tells you nothing.
    /// The only real signal is whether the coach listed P among their
    /// positions.
    var isPitcher: Bool {
        isStandalonePitcher || positions.contains(.pitcher)
    }

    /// Archived only when *every* pitching record is - a linked player
    /// whose older record was archived is still an active player. Keying on
    /// the primary record alone hid the whole person the moment a link made
    /// an archived record primary.
    func isArchived(in archivedPitcherIds: Set<String>) -> Bool {
        let ids = pitcherIds.isEmpty ? [pitcherId].compactMap { $0 } : pitcherIds
        return !ids.isEmpty && ids.allSatisfy { archivedPitcherIds.contains($0) }
    }
}

enum PlayerDirectory {
    /// Roster rows and standalone Pitchers folded into one row per person
    /// (`.person`) or per pitching record (`.pitchingRecord`) - see
    /// `PlayerDirectoryCollapse`. Either way the Pitcher doc and the roster
    /// entry that links it collapse together instead of listing the same kid
    /// twice, via `keyForPitcherId` below.
    ///
    /// Entries are folded oldest-roster-row-first so the result is stable:
    /// which of two linked entries supplies the row's primary pitcher,
    /// jersey and name must not depend on the order the per-team roster
    /// reads happened to complete in.
    ///
    /// `players` (`.person` only) folds in records that belong to a person
    /// through their `Player` doc rather than a roster row - what Link
    /// Profiles leaves in `linkedPitcherIds`/`linkedHitterIds` when combined
    /// profiles each had tracked history, or a standalone Pitcher linked to a
    /// roster player. Without it those would list as separate "No team" rows.
    static func rows(
        rosterEntries: [PlayerRosterEntry],
        pitchers: [Pitcher],
        players: [Player] = [],
        collapse: PlayerDirectoryCollapse = .person
    ) -> [PlayerDirectoryRow] {
        // One person = one Link Profiles profile, by construction. This used
        // to key each roster row on a single id (playerId, else pitcherId),
        // so an older row with no playerId and a newer linked row on another
        // team became two rows - and Stats only saw the older team.
        if collapse == .person {
            return PlayerLinks.profiles(rosterEntries: rosterEntries, pitchers: pitchers, players: players)
                .map(personRow(from:))
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }

        var rows: [String: PlayerDirectoryRow] = [:]
        var order: [String] = []
        /// Which row key each Pitcher doc already belongs to, so the
        /// standalone pass below doesn't list a pitcher that a roster entry
        /// has already folded in.
        var keyForPitcherId: [String: String] = [:]
        var pitchersById: [String: Pitcher] = [:]
        for pitcher in pitchers {
            if let id = pitcher.id { pitchersById[id] = pitcher }
        }

        let orderedEntries = rosterEntries.sorted {
            $0.teamPlayer.createdAt < $1.teamPlayer.createdAt
        }

        for entry in orderedEntries {
            let teamPlayer = entry.teamPlayer
            // `.pitchingRecord` from here on (`.person` returned above).
            let candidateKey = teamPlayer.pitcherId ?? teamPlayer.playerId ?? teamPlayer.id
            guard let key = candidateKey else { continue }
            if let pitcherId = teamPlayer.pitcherId { keyForPitcherId[pitcherId] = key }
            // The linked Pitcher's name wins over the roster row's copy.
            // `propagatePlayerRename` keeps the two in step from now on, but
            // a rename made before that existed left them disagreeing - and
            // the Pitcher doc is the copy the Edit sheet writes and the one
            // the tracker shows next to the pitch strip once a pitcher is
            // selected, so deferring to it is what makes every surface agree
            // instead of the list saying one name and the screen another.
            let linkedPitcher = teamPlayer.pitcherId.flatMap { pitchersById[$0] }
            let displayName = linkedPitcher?.name ?? teamPlayer.name
            if var existing = rows[key] {
                if !existing.teams.contains(where: { $0.id == entry.team.id }) {
                    existing.teams.append(entry.team)
                }
                if existing.jersey == nil { existing.jersey = teamPlayer.jerseyNumber }
                if existing.hitterId == nil { existing.hitterId = teamPlayer.hitterId }
                if existing.playerId == nil { existing.playerId = teamPlayer.playerId }
                if let pitcherId = teamPlayer.pitcherId, !existing.pitcherIds.contains(pitcherId) {
                    existing.pitcherIds.append(pitcherId)
                }
                if let hitterId = teamPlayer.hitterId, !existing.hitterIds.contains(hitterId) {
                    existing.hitterIds.append(hitterId)
                }
                // Same precedence as the fresh-row branch: once any entry
                // for this person resolves a Pitcher doc, its name and
                // portrait are the row's.
                if let linkedPitcher {
                    existing.name = linkedPitcher.name
                    if existing.pitcher == nil { existing.pitcher = linkedPitcher }
                    if existing.pitcherId == nil { existing.pitcherId = teamPlayer.pitcherId }
                }
                existing.positions.formUnion(teamPlayer.positions ?? [])
                rows[key] = existing
            } else {
                rows[key] = PlayerDirectoryRow(
                    id: key,
                    name: displayName,
                    jersey: teamPlayer.jerseyNumber,
                    pitcher: linkedPitcher,
                    pitcherId: teamPlayer.pitcherId,
                    playerId: teamPlayer.playerId,
                    hitterId: teamPlayer.hitterId,
                    teams: [entry.team],
                    positions: Set(teamPlayer.positions ?? []),
                    isStandalonePitcher: false,
                    pitcherIds: [teamPlayer.pitcherId].compactMap { $0 },
                    hitterIds: [teamPlayer.hitterId].compactMap { $0 }
                )
                order.append(key)
            }
        }

        // A Pitcher created straight from Home's +, or shared in by someone
        // else, has no roster row of its own but still belongs here. A
        // pitcher a roster entry above already claimed is skipped via
        // `keyForPitcherId` - checking `rows[id]` alone would miss it in
        // `.person` mode, where that row is keyed by playerId instead and
        // the pitcher would be listed a second time as a "No team" person.
        for pitcher in pitchers {
            guard let id = pitcher.id else { continue }
            if let claimedKey = keyForPitcherId[id], rows[claimedKey] != nil { continue }
            guard rows[id] == nil else { continue }
            rows[id] = PlayerDirectoryRow(
                id: id,
                name: pitcher.name,
                jersey: nil,
                pitcher: pitcher,
                pitcherId: id,
                playerId: nil,
                hitterId: nil,
                teams: [],
                positions: [],
                isStandalonePitcher: true,
                pitcherIds: [id],
                hitterIds: []
            )
            keyForPitcherId[id] = id
            order.append(id)
        }

        return order
            .compactMap { rows[$0] }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private static func personRow(from profile: PlayerProfile) -> PlayerDirectoryRow {
        let primaryPitcherId = profile.entries.first?.teamPlayer.pitcherId ?? profile.pitcherIds.first
        let primaryPitcher = profile.pitchers.first(where: { $0.id == primaryPitcherId }) ?? profile.pitchers.first
        let positions = profile.entries.reduce(into: Set<FieldPosition>()) { result, entry in
            result.formUnion(entry.teamPlayer.positions ?? [])
        }
        return PlayerDirectoryRow(
            id: profile.playerIds.first ?? profile.pitcherIds.first ?? profile.id,
            name: profile.name,
            jersey: profile.jersey,
            pitcher: primaryPitcher,
            pitcherId: primaryPitcherId,
            playerId: profile.playerIds.first,
            hitterId: profile.entries.first?.teamPlayer.hitterId ?? profile.hitterIds.first,
            teams: profile.teams,
            positions: positions,
            isStandalonePitcher: profile.entries.isEmpty,
            pitcherIds: profile.pitcherIds,
            hitterIds: profile.hitterIds
        )
    }

    static func filtered(
        _ rows: [PlayerDirectoryRow],
        scope: PlayerDirectoryScope,
        filter: PlayerDirectoryFilter,
        archivedPitcherIds: Set<String>
    ) -> [PlayerDirectoryRow] {
        rows.filter { row in
            guard scope == .all || row.isPitcher else { return false }
            return passes(row, filter: filter, archivedPitcherIds: archivedPitcherIds)
        }
    }

    static func passes(
        _ row: PlayerDirectoryRow,
        filter: PlayerDirectoryFilter,
        archivedPitcherIds: Set<String>
    ) -> Bool {
        if row.isArchived(in: archivedPitcherIds), !filter.showArchived {
            return false
        }
        if !filter.teamIds.isEmpty {
            let matchesTeam = row.teams.contains { filter.teamIds.contains($0.id ?? "") }
            let matchesNoTeam = row.teams.isEmpty && filter.teamIds.contains(PlayerDirectoryFilter.noTeamId)
            if !matchesTeam && !matchesNoTeam { return false }
        }
        if !filter.ageGroups.isEmpty {
            let matches = row.teams.contains { team in
                guard let group = team.ageGroup else { return false }
                return filter.ageGroups.contains(group)
            }
            if !matches { return false }
        }
        if !filter.divisions.isEmpty {
            let matches = row.teams.contains { team in
                guard let division = team.division else { return false }
                return filter.divisions.contains(division)
            }
            if !matches { return false }
        }
        return true
    }

    /// Which scope a freshly opened picker should start on. `.pitchers` is
    /// the right default - you're picking a pitcher - but a coach who never
    /// filled in positions has nobody listed at P, and defaulting to a scope
    /// that hides every selectable person reads as "my pitcher is gone."
    static func initialScope(for rows: [PlayerDirectoryRow]) -> PlayerDirectoryScope {
        rows.contains(where: { $0.isPitcher }) ? .pitchers : .all
    }
}

// MARK: - Avatar

/// Non-pitching players have no portrait store of their own (portraits are
/// keyed by pitcherId), so they get an initials circle instead of
/// `PitcherAvatarView`.
struct PlayerDirectoryAvatar: View {
    let row: PlayerDirectoryRow
    var size: CGFloat = 52

    var body: some View {
        if let pitcher = row.pitcher {
            PitcherAvatarView(pitcher: pitcher, size: size)
        } else {
            ZStack {
                Circle().fill(Color(.systemGray3))
                Text(initials)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
    }

    private var initials: String {
        let parts = row.name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let initials = parts.compactMap { $0.first }.map(String.init).joined()
        return initials.isEmpty ? "?" : initials.uppercased()
    }
}

// MARK: - Row view

/// The Players row itself. `accessory` is whatever that screen puts on the
/// trailing edge - Home's Stats button + gear menu, or a picker's checkmark.
struct PlayerDirectoryRowView<Accessory: View>: View {
    let row: PlayerDirectoryRow
    var isArchived: Bool = false
    var isSelected: Bool = false
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 4) {
                PlayerDirectoryAvatar(row: row, size: 52)
                Text(teamCaption)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(row.teams.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                    .frame(width: 70)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(row.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let jersey = row.jersey, !jersey.isEmpty {
                        Text("#\(jersey)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                    }
                }
                // One team's season would be misleading under "Multiple".
                if row.teams.count == 1, let team = row.teams.first {
                    TeamDesignationBadge(designation: team.designation, alignment: .leading)
                }

                if !row.isPitcher {
                    Text("Bats only")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if isArchived {
                    Text("Archived")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            accessory()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.pitchMarkActiveGray.opacity(0.14) : Color.clear)
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.pitchMarkActiveGray.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    /// Under the avatar: the team, or "Multiple" for a player linked on
    /// more than one.
    private var teamCaption: String {
        guard let team = row.teams.first else { return "No team" }
        return row.teams.count > 1 ? "Multiple" : team.name
    }
}

// MARK: - Filter UI

/// Sheet-hosted `List`, not a `Menu`: Home re-renders constantly from the
/// pitcher listeners, and a `Menu`'s contents are a transient `UIMenu` that
/// loses its scroll position on every one of those re-renders (same reason
/// the cards filter UI is a List - see CLAUDE.md).
struct PlayerDirectoryFilterList: View {
    let teams: [Team]
    @Binding var filter: PlayerDirectoryFilter
    /// Archive is a Home-local notion that only applies to Pitcher records.
    /// A list that was handed no archived ids has nothing for the toggle to
    /// reveal, so it isn't offered one.
    var showsArchivedToggle: Bool = true

    var body: some View {
        List {
            Section("Team") {
                ForEach(teams, id: \.id) { team in
                    let teamId = team.id ?? ""
                    row(
                        title: team.name,
                        subtitle: team.designation?.inlineText,
                        isOn: filter.teamIds.contains(teamId)
                    ) {
                        toggle(teamId, in: &filter.teamIds)
                    }
                }
                row(
                    title: "No team",
                    subtitle: "Players not on any roster",
                    isOn: filter.teamIds.contains(PlayerDirectoryFilter.noTeamId)
                ) {
                    toggle(PlayerDirectoryFilter.noTeamId, in: &filter.teamIds)
                }
            }

            Section("Age Group") {
                ForEach(TeamAgeGroup.allCases) { group in
                    row(title: group.displayName, subtitle: nil, isOn: filter.ageGroups.contains(group)) {
                        toggle(group, in: &filter.ageGroups)
                    }
                }
            }

            Section("Division") {
                ForEach(TeamDivision.allCases) { division in
                    row(title: division.displayName, subtitle: nil, isOn: filter.divisions.contains(division)) {
                        toggle(division, in: &filter.divisions)
                    }
                }
            }

            Section {
                if showsArchivedToggle {
                    Toggle("Show archived", isOn: $filter.showArchived)
                        .tint(Color.pitchMarkActiveGray)
                }
                Button("Clear All Filters") {
                    filter.clear()
                }
                .disabled(!filter.isActive)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private func row(
        title: String,
        subtitle: String?,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.pitchMarkActiveGray : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The standalone sheet version, for Home (which presents the filter from a
/// header button rather than pushing it inside a picker).
struct PlayerDirectoryFilterSheet: View {
    let teams: [Team]
    @Binding var filter: PlayerDirectoryFilter
    let onDone: () -> Void

    var body: some View {
        NavigationView {
            PlayerDirectoryFilterList(teams: teams, filter: $filter)
                .navigationTitle("Filter Players")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { onDone() }
                    }
                }
        }
    }
}

// MARK: - Picker

/// Home's Players list as a chooser: same rows, same scope toggle, same
/// filter - tap selects instead of opening a gear menu.
struct PlayerPickerSheet: View {
    let title: String
    /// Already narrowed to the people this picker may select (e.g. the
    /// current side's pitchers), before scope/filter are applied.
    let rows: [PlayerDirectoryRow]
    /// Teams offered by the filter list.
    let teams: [Team]
    var archivedPitcherIds: Set<String> = []
    /// Rendered above the list, same as `ScrollableSelectionSheet` - e.g.
    /// "New Pitcher on Reds".
    var topActions: [SelectionSheetAction] = []
    var emptyMessage: String = "No players available."
    /// Which scope the sheet opens on. Left nil, it picks `.pitchers` when
    /// anyone qualifies - right for a pitcher picker, wrong for a chooser
    /// where pitching is beside the point (linking a roster player), which
    /// passes `.all`.
    var initialScope: PlayerDirectoryScope? = nil
    var isSelected: (PlayerDirectoryRow) -> Bool = { _ in false }
    let onSelect: (PlayerDirectoryRow) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scope: PlayerDirectoryScope = .pitchers
    @State private var filter = PlayerDirectoryFilter()
    @State private var didSeedScope = false

    private var visibleRows: [PlayerDirectoryRow] {
        PlayerDirectory.filtered(
            rows,
            scope: scope,
            filter: filter,
            archivedPitcherIds: archivedPitcherIds
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(topActions) { action in
                            Button(role: action.role) {
                                action.action()
                                dismiss()
                            } label: {
                                actionRow(action)
                            }
                            .buttonStyle(.plain)
                        }

                        let visible = visibleRows
                        if visible.isEmpty {
                            Text(emptyText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(visible) { row in
                                Button {
                                    onSelect(row)
                                    dismiss()
                                } label: {
                                    PlayerDirectoryRowView(
                                        row: row,
                                        isArchived: isArchived(row),
                                        isSelected: isSelected(row)
                                    ) {
                                        if isSelected(row) {
                                            Image(systemName: "checkmark")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Color.pitchMarkActiveGray)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            // Only once: re-seeding on every re-render would stomp the
            // coach's own toggle while the sheet is open.
            guard !didSeedScope else { return }
            didSeedScope = true
            scope = initialScope ?? PlayerDirectory.initialScope(for: rows)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            CapsuleSegmentedControl(
                options: [("Pitchers", PlayerDirectoryScope.pitchers), ("All", PlayerDirectoryScope.all)],
                selection: $scope,
                segmentMinWidth: 60
            )
            .font(.caption)

            Spacer(minLength: 4)

            // Pushed, not presented: a sheet on top of this sheet is the
            // presentation shape behind several "tapped it, nothing
            // happened" bugs in this codebase (see CLAUDE.md).
            NavigationLink {
                PlayerDirectoryFilterList(
                    teams: teams,
                    filter: $filter,
                    showsArchivedToggle: !archivedPitcherIds.isEmpty
                )
                .navigationTitle("Filter Players")
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                Image(systemName: filter.isActive
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                    .font(.title3)
                    .foregroundStyle(filter.isActive ? Color.pitchMarkActiveGray : Color.primary)
            }
            .accessibilityLabel("Filter players")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var emptyText: String {
        if scope == .pitchers, rows.contains(where: { !$0.isPitcher }) {
            return "No one here is listed at P. Switch to All, or add P to their positions on the team's roster."
        }
        if filter.isActive {
            return "No players match the current filter."
        }
        return emptyMessage
    }

    private func isArchived(_ row: PlayerDirectoryRow) -> Bool {
        row.isArchived(in: archivedPitcherIds)
    }

    private func actionRow(_ action: SelectionSheetAction) -> some View {
        HStack(spacing: 12) {
            Text(action.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let systemImage = action.systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

/// Button + sheet pairing, mirroring `ScrollableSelectionMenuButton` so a
/// call site swaps one for the other without restructuring.
struct PlayerPickerButton<Label: View>: View {
    let title: String
    let rows: [PlayerDirectoryRow]
    let teams: [Team]
    var archivedPitcherIds: Set<String> = []
    var topActions: [SelectionSheetAction] = []
    var emptyMessage: String = "No players available."
    var initialScope: PlayerDirectoryScope? = nil
    var isSelected: (PlayerDirectoryRow) -> Bool = { _ in false }
    let onSelect: (PlayerDirectoryRow) -> Void
    /// Fired on tap, before the sheet presents - the hook for refreshing a
    /// cached roster that may have changed since this screen loaded.
    var onOpen: (() -> Void)? = nil
    @ViewBuilder let label: () -> Label

    @State private var isPresented = false

    var body: some View {
        Button {
            onOpen?()
            isPresented = true
        } label: {
            label()
        }
        .sheet(isPresented: $isPresented) {
            PlayerPickerSheet(
                title: title,
                rows: rows,
                teams: teams,
                archivedPitcherIds: archivedPitcherIds,
                topActions: topActions,
                emptyMessage: emptyMessage,
                initialScope: initialScope,
                isSelected: isSelected,
                onSelect: onSelect
            )
            .fixedAppDynamicType()
        }
    }
}

// MARK: - Loading

extension AuthManager {
    /// Every active roster row across the given teams, paired with its team.
    /// Archived roster entries are dropped here so no caller has to remember.
    func loadPlayerRosterEntries(
        for teams: [Team],
        completion: @escaping ([PlayerRosterEntry]) -> Void
    ) {
        guard !teams.isEmpty else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        var collected: [PlayerRosterEntry] = []
        let group = DispatchGroup()
        for team in teams {
            guard team.id != nil else { continue }
            group.enter()
            // loadTeamPlayers already completes on the main queue, so the
            // appends below are serialized without a lock.
            loadTeamPlayers(teamId: team.id ?? "") { players in
                for player in players where player.archivedAt == nil {
                    collected.append(PlayerRosterEntry(teamPlayer: player, team: team))
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(collected)
        }
    }

    /// `loadMyTeams` + the fan-out above, for callers that don't already hold
    /// a teams list.
    func loadPlayerDirectory(
        completion: @escaping ([PlayerRosterEntry], [Team]) -> Void
    ) {
        loadMyTeams { entries, _ in
            let teams = entries.map { $0.team }
            self.loadPlayerRosterEntries(for: teams) { rosterEntries in
                completion(rosterEntries, teams)
            }
        }
    }
}
