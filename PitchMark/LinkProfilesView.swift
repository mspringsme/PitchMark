//
//  LinkProfilesView.swift
//  PitchMark
//
//  Link Profiles - its own flow, reached from its own card on Home and from
//  nowhere inside the Teams or Players lists. Those lists just show the
//  result when the coach comes back.
//
//  Three jobs, one per path off the start screen:
//
//  - Link Player Across Teams: pick a player, then check the teams they've
//    played on over time. They join those rosters as the same kid, so their
//    stats show together.
//  - Merge Duplicates: for a player accidentally created twice. A dialog says
//    so before anything else; then pick the two profiles.
//  - Delete Players: pick players, confirm, gone from every team.
//
//  Every path ends back on the start screen with a one-line confirmation.
//  The model and writes live in PlayerLinks.swift.
//

import SwiftUI
import FirebaseAuth
import Combine

/// The flow's data, shared by reference with every pushed screen. It has to
/// be an observed object rather than `@State` on the root: a view pushed via
/// `navigationDestination(for:)` is not reliably rebuilt when the root's
/// state changes, so a picker pushed before the first load finished kept
/// `isLoading == true` forever - an endless spinner.
final class LinkProfilesStore: ObservableObject {
    @Published var rosterEntries: [PlayerRosterEntry] = []
    @Published var teams: [Team] = []
    @Published var pitchers: [Pitcher] = []
    @Published var players: [Player] = []
    @Published var isLoading = true

    var profiles: [PlayerProfile] {
        PlayerLinks.profiles(rosterEntries: rosterEntries, pitchers: pitchers, players: players)
    }

    /// The three reads run side by side and the spinner clears when all
    /// three have answered. Every loader called here completes on failure
    /// too (with an empty result), so this always finishes.
    func reload(using authManager: AuthManager) {
        let group = DispatchGroup()
        var entries: [PlayerRosterEntry] = []
        var loadedTeams: [Team] = []
        var loadedPitchers: [Pitcher] = []
        var loadedPlayers: [Player] = []

        group.enter()
        authManager.loadPlayerDirectory { e, t in
            entries = e
            loadedTeams = t
            group.leave()
        }
        group.enter()
        authManager.loadPitchers { p in
            loadedPitchers = p
            group.leave()
        }
        group.enter()
        authManager.loadMyPlayers { p in
            loadedPlayers = p
            group.leave()
        }

        group.notify(queue: .main) {
            self.rosterEntries = entries
            self.teams = loadedTeams
            self.pitchers = loadedPitchers
            self.players = loadedPlayers
            self.isLoading = false
        }
    }
}

struct LinkProfilesView: View {
    /// Runs on close if anything changed, so Home reloads underneath.
    var onChanged: () -> Void = {}

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var store = LinkProfilesStore()

    @State private var path: [Route] = []
    @State private var statusMessage: String? = nil
    @State private var showMergeIntro = false
    @State private var didChange = false

    enum Route: Hashable {
        case linkPick
        case linkTeams(profileId: String)
        case mergePick
        case deletePick
    }

    private var uid: String? { authManager.user?.uid }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let statusMessage {
                    Section {
                        Label {
                            Text(statusMessage)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.pitchMarkActiveGray)
                        }
                        .font(.subheadline)
                    }
                }

                Section {
                    NavigationLink(value: Route.linkPick) {
                        optionRow(
                            title: "Link Player Across Teams",
                            icon: "link",
                            detail: "Connect a player to the teams they've played on over time. Their stats from every team show together."
                        )
                    }
                }

                Section {
                    Button {
                        showMergeIntro = true
                    } label: {
                        HStack {
                            optionRow(
                                title: "Merge Duplicates",
                                icon: "arrow.triangle.merge",
                                detail: "Combine a player you accidentally added twice."
                            )
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    NavigationLink(value: Route.deletePick) {
                        optionRow(
                            title: "Delete Players",
                            icon: "trash",
                            detail: "Remove players from every team, along with their stats."
                        )
                    }
                }
            }
            .navigationTitle("Link Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: Route.self) { route in
                destination(route)
            }
            // Root of the flow - see CLAUDE.md's Dialogs section.
            .appConfirmationDialog(
                isPresented: $showMergeIntro,
                title: "Merge Duplicates",
                message: "This is for a player you accidentally added twice - for example, Kenzie typed in as a new player on a second team instead of being linked.\n\nPick the two profiles that are the same player and they become one, keeping all of their tracked pitches.\n\nTo connect a player to another team they've played on, use Link Player Across Teams instead.",
                primaryTitle: "Continue",
                primaryAction: { path.append(.mergePick) },
                secondaryTitle: "Cancel"
            )
        }
        .onAppear { store.reload(using: authManager) }
        .onDisappear {
            if didChange { onChanged() }
        }
    }

    private func optionRow(title: String, icon: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.pitchMarkActiveGray)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .linkPick:
            ProfilePickerList(
                prompt: "Choose the player to link to other teams.",
                store: store,
                mode: .single { profile in
                    path.append(.linkTeams(profileId: profile.id))
                }
            )
            .navigationTitle("Link Player")
            .navigationBarTitleDisplayMode(.inline)
        case .linkTeams(let profileId):
            LinkTeamsScreen(profileId: profileId, store: store, currentUid: uid, onDone: finish)
        case .mergePick:
            MergePickScreen(store: store, currentUid: uid, onDone: finish)
        case .deletePick:
            DeletePickScreen(store: store, currentUid: uid, onDone: finish)
        }
    }

    /// Every path ends here: back to the start, say what happened, reload.
    private func finish(_ message: String) {
        statusMessage = message
        didChange = true
        path = []
        store.reload(using: authManager)
    }
}

// MARK: - Shared picker

/// The A–Z list every path picks from: search, letter sections, and either
/// tap-to-choose (`.single`) or checkboxes (`.multi`).
private struct ProfilePickerList: View {
    enum Mode {
        case single((PlayerProfile) -> Void)
        case multi(Binding<Set<String>>)
    }

    let prompt: String
    @ObservedObject var store: LinkProfilesStore
    let mode: Mode

    @State private var searchText = ""

    private var visible: [PlayerProfile] {
        let profiles = store.profiles
        let query = PlayerLinks.normalized(searchText)
        guard !query.isEmpty else { return profiles }
        return profiles.filter { PlayerLinks.normalized($0.name).contains(query) }
    }

    private var sections: [(letter: String, profiles: [PlayerProfile])] {
        var grouped: [String: [PlayerProfile]] = [:]
        for profile in visible {
            let first = profile.name.trimmingCharacters(in: .whitespaces).prefix(1).uppercased()
            let letter = first.first?.isLetter == true ? first : "#"
            grouped[letter, default: []].append(profile)
        }
        return grouped.keys.sorted { lhs, rhs in
            if lhs == "#" { return false }
            if rhs == "#" { return true }
            return lhs < rhs
        }
        .map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            Section {
                Text(prompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if visible.isEmpty {
                Text(searchText.isEmpty ? "No players yet." : "No players match \"\(searchText)\".")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sections, id: \.letter) { section in
                    Section(section.letter) {
                        ForEach(section.profiles) { profile in
                            row(profile)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search players")
    }

    @ViewBuilder
    private func row(_ profile: PlayerProfile) -> some View {
        switch mode {
        case .single(let onSelect):
            Button {
                onSelect(profile)
            } label: {
                HStack {
                    ProfileRowLabel(profile: profile)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .multi(let selection):
            let isSelected = selection.wrappedValue.contains(profile.id)
            Button {
                if isSelected {
                    selection.wrappedValue.remove(profile.id)
                } else {
                    selection.wrappedValue.insert(profile.id)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.pitchMarkActiveGray : Color.secondary)
                    ProfileRowLabel(profile: profile)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Name, jersey, and every team the player is on - enough to tell two
/// Kenzies apart.
private struct ProfileRowLabel: View {
    let profile: PlayerProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(profile.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let jersey = profile.jersey {
                    Text("#\(jersey)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if profile.teams.isEmpty {
                Text("No team")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(profile.teams, id: \.id) { team in
                    HStack(spacing: 4) {
                        Text(team.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TeamDesignationBadge(designation: team.designation, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// Full-screen black overlay + white spinner - the app's saving convention.
private struct SavingOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text(text)
                    .foregroundStyle(.white)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

/// The bottom action button shared by the pick screens.
private struct BottomActionBar: View {
    let caption: String
    let title: String
    var isDestructive = false
    let isEnabled: Bool
    var errorMessage: String? = nil
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Button(role: isDestructive ? .destructive : nil, action: action) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(isDestructive ? .red : Color.pitchMarkActiveGray)
            .disabled(!isEnabled)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }
}

// MARK: - Link

/// Step two of Link: the coach's teams, checked where the player already is.
private struct LinkTeamsScreen: View {
    let profileId: String
    @ObservedObject var store: LinkProfilesStore
    let currentUid: String?
    let onDone: (String) -> Void

    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        if let profile = store.profiles.first(where: { $0.id == profileId }) {
            LinkTeamsContent(
                profile: profile,
                teams: store.teams,
                profiles: store.profiles,
                currentUid: currentUid,
                onDone: onDone
            )
        } else {
            Text("That player is no longer available.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct LinkTeamsContent: View {
    let profile: PlayerProfile
    let teams: [Team]
    let profiles: [PlayerProfile]
    let currentUid: String?
    let onDone: (String) -> Void

    @EnvironmentObject var authManager: AuthManager

    @State private var chosenTeamIds: Set<String> = []
    @State private var showConfirm = false
    @State private var isWorking = false
    @State private var errorMessage: String? = nil

    /// Only teams this account created and hasn't archived - firestore.rules
    /// lets only a team's creator add to its roster.
    private var eligibleTeams: [Team] {
        teams
            .filter { $0.createdByUid == currentUid && $0.archivedAt == nil && $0.id != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var chosenTeams: [Team] {
        eligibleTeams.filter { chosenTeamIds.contains($0.id ?? "") }
    }

    /// Checked teams that already list this kid separately - those get
    /// combined rather than gaining a second row.
    private var profilesToCombine: [PlayerProfile] {
        var seen = Set<String>()
        return chosenTeams.compactMap { sameNamedOther(on: $0) }.filter { seen.insert($0.id).inserted }
    }

    /// Checked teams that need a new roster row: not already covered by a
    /// profile being combined in.
    private var teamsToAdd: [Team] {
        let combined = profilesToCombine
        return chosenTeams.filter { team in !combined.contains { $0.isOnTeam(team.id) } }
    }

    /// A different profile with the same name already on that team - almost
    /// always the same kid typed in on each season's roster.
    private func sameNamedOther(on team: Team) -> PlayerProfile? {
        let name = PlayerLinks.normalized(profile.name)
        return profiles.first { other in
            other.id != profile.id
                && other.isOnTeam(team.id)
                && PlayerLinks.normalized(other.name) == name
        }
    }

    var body: some View {
        List {
            Section {
                ProfileRowLabel(profile: profile)
            } header: {
                Text("Player")
            }

            Section {
                if eligibleTeams.isEmpty {
                    Text("You haven't created any teams yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(eligibleTeams, id: \.id) { team in
                    teamRow(team)
                }
            } header: {
                Text("Teams \(profile.name) has played on")
            } footer: {
                Text("Check each team to link. \(profile.name) joins those rosters as the same player, so their stats from every team show together. Jersey number and positions are set on each team's roster.")
            }
        }
        .navigationTitle("Link \(profile.name)")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar(
                caption: chosenTeams.isEmpty ? "Check the teams to link" : "\(chosenTeams.count) team\(chosenTeams.count == 1 ? "" : "s") checked",
                title: "Link",
                isEnabled: !chosenTeams.isEmpty && !isWorking,
                errorMessage: errorMessage
            ) {
                showConfirm = true
            }
        }
        .overlay {
            if isWorking { SavingOverlay(text: "Linking…") }
        }
        .appConfirmationDialog(
            isPresented: $showConfirm,
            title: "Link \(profile.name)?",
            message: confirmMessage,
            primaryTitle: "Link",
            primaryAction: { link() },
            secondaryTitle: "Cancel"
        )
    }

    private var confirmMessage: String {
        var text = "\(profile.name) will be on \(PlayerLinks.teamList(profile.teams + chosenTeams)) as one player, with stats from every team together."
        let combined = profilesToCombine
        if !combined.isEmpty {
            text += "\n\nAlready listed separately, and combined into this player: \(combined.map(\.labelWithTeams).joined(separator: ", ")). Tracked pitches from both are kept."
        }
        return text
    }

    @ViewBuilder
    private func teamRow(_ team: Team) -> some View {
        let alreadyOn = profile.isOnTeam(team.id)
        let conflict = alreadyOn ? nil : sameNamedOther(on: team)
        let isChosen = chosenTeamIds.contains(team.id ?? "")
        Button {
            guard let id = team.id else { return }
            if isChosen { chosenTeamIds.remove(id) } else { chosenTeamIds.insert(id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: alreadyOn || isChosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChosen ? Color.pitchMarkActiveGray : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(team.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(alreadyOn ? .secondary : .primary)
                    TeamDesignationBadge(designation: team.designation, alignment: .leading)
                    if alreadyOn {
                        Text("Already linked")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let conflict {
                        Text("Already lists a \(conflict.name) here. Linking makes them one player and combines their stats.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(alreadyOn || isWorking)
    }

    private func link() {
        let targets = chosenTeams
        isWorking = true
        errorMessage = nil
        authManager.linkProfile(
            profile,
            toTeams: teamsToAdd,
            combiningWith: profilesToCombine,
            currentUid: currentUid
        ) { result in
            isWorking = false
            switch result {
            case .success:
                onDone("\(profile.name) is now linked on \(PlayerLinks.teamList(profile.teams + targets)).")
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Merge

private struct MergePickScreen: View {
    @ObservedObject var store: LinkProfilesStore
    let currentUid: String?
    let onDone: (String) -> Void

    @EnvironmentObject var authManager: AuthManager

    @State private var selectedIds: Set<String> = []
    @State private var showConfirm = false
    @State private var isWorking = false
    @State private var errorMessage: String? = nil

    private var selected: [PlayerProfile] {
        store.profiles.filter { selectedIds.contains($0.id) }
    }

    private var plan: Result<(keep: PlayerProfile, fold: [PlayerProfile]), PlayerLinks.CombinePlanError> {
        PlayerLinks.combinePlan(selected, currentUid: currentUid)
    }

    var body: some View {
        ProfilePickerList(
            prompt: "Select the two profiles that are the same player.",
            store: store,
            mode: .multi($selectedIds)
        )
        .navigationTitle("Merge Duplicates")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar(
                caption: selectedIds.count == 2 ? "2 selected" : "Select 2 profiles (\(selectedIds.count) selected)",
                title: "Merge",
                isEnabled: selectedIds.count == 2 && !isWorking,
                errorMessage: errorMessage
            ) {
                if case .failure(let error) = plan {
                    errorMessage = message(for: error)
                } else {
                    errorMessage = nil
                    showConfirm = true
                }
            }
        }
        .overlay {
            if isWorking { SavingOverlay(text: "Merging…") }
        }
        .appConfirmationDialog(
            isPresented: $showConfirm,
            title: "Merge Into One Player?",
            message: confirmMessage,
            primaryTitle: "Merge",
            primaryAction: { merge() },
            secondaryTitle: "Cancel"
        )
    }

    private var confirmMessage: String {
        guard case .success(let plan) = plan else { return "" }
        let names = selected.map(\.labelWithTeams).joined(separator: "\n")
        return "\(names)\n\nThese become one player, keeping \(plan.keep.labelWithTeams). Where both are on the same team, the extra roster entry is removed. Tracked pitches from both are kept."
    }

    private func message(for error: PlayerLinks.CombinePlanError) -> String {
        switch error {
        case .needsTwo:
            return "Select two profiles."
        case .notEditable(let names):
            return "\(names.joined(separator: " and ")) come from another coach's account, so they can't be merged with each other here."
        }
    }

    private func merge() {
        guard case .success(let plan) = plan else { return }
        isWorking = true
        errorMessage = nil
        authManager.combineProfiles(keep: plan.keep, fold: plan.fold, mode: .mergeDuplicate) { result in
            isWorking = false
            switch result {
            case .success:
                onDone("Merged into one \(plan.keep.name).")
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Delete

private struct DeletePickScreen: View {
    @ObservedObject var store: LinkProfilesStore
    let currentUid: String?
    let onDone: (String) -> Void

    @EnvironmentObject var authManager: AuthManager

    @State private var selectedIds: Set<String> = []
    @State private var showConfirm = false
    @State private var isWorking = false
    @State private var errorMessage: String? = nil

    private var selected: [PlayerProfile] {
        store.profiles.filter { selectedIds.contains($0.id) }
    }

    var body: some View {
        ProfilePickerList(
            prompt: "Select the players to delete.",
            store: store,
            mode: .multi($selectedIds)
        )
        .navigationTitle("Delete Players")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar(
                caption: selectedIds.isEmpty ? "Select players to delete" : "\(selectedIds.count) selected",
                title: selectedIds.count > 1 ? "Delete \(selectedIds.count) Players" : "Delete Player",
                isDestructive: true,
                isEnabled: !selectedIds.isEmpty && !isWorking,
                errorMessage: errorMessage
            ) {
                let locked = selected.filter { !$0.isFullyEditable(by: currentUid) }
                if locked.isEmpty {
                    errorMessage = nil
                    showConfirm = true
                } else {
                    errorMessage = "\(locked.map(\.labelWithTeams).joined(separator: ", ")) comes from another coach's account, so it can't be deleted here."
                }
            }
        }
        .overlay {
            if isWorking { SavingOverlay(text: "Deleting…") }
        }
        .appConfirmationDialog(
            isPresented: $showConfirm,
            title: selected.count > 1 ? "Delete \(selected.count) Players?" : "Delete \(selected.first?.name ?? "Player")?",
            message: "\(selected.map(\.labelWithTeams).joined(separator: "\n"))\n\nRemoves them from every team and deletes their player profile and stats. Pitches already recorded in your games stay in those games. This can't be undone.",
            primaryTitle: "Delete",
            primaryRole: .destructive,
            primaryAction: { deleteSelected() },
            secondaryTitle: "Cancel"
        )
    }

    private func deleteSelected() {
        let chosen = selected
        isWorking = true
        errorMessage = nil
        var remaining = chosen
        func next() {
            guard !remaining.isEmpty else {
                isWorking = false
                onDone(chosen.count == 1 ? "Deleted \(chosen[0].name)." : "Deleted \(chosen.count) players.")
                return
            }
            let profile = remaining.removeFirst()
            authManager.deleteProfile(profile) { result in
                if case .failure(let error) = result {
                    isWorking = false
                    errorMessage = "Couldn't delete \(profile.name): \(error.localizedDescription)"
                    return
                }
                next()
            }
        }
        next()
    }
}
