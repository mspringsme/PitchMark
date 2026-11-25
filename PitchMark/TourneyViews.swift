//
//  TourneyViews.swift
//  PitchMark
//
//  Round Robin / Tourney Info screens (2026-11-16, reworked 2026-11-17):
//  the list (opened from the Games row's calendar-pin-trophy button on
//  Home) with two tabs - Our Tourneys (own pages + Shared with Me) and
//  Scouting (tourneys the staff might enter) - one tourney's editor, the
//  read-only page a shared tourney opens as, the place search and the
//  share screens. Rules live in Tourney.swift.
//

import SwiftUI
import MapKit
import FirebaseAuth

// MARK: - Home button

/// The Games row's Tourney Info button: calendar, pin and trophy side by
/// side in a rounded rectangle. Its own struct so Home's type doesn't grow.
struct TourneyInfoButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "calendar")
                Image(systemName: "mappin")
                Image(systemName: "trophy")
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Round Robin / Tourney Info")
        .accessibilityIdentifier("home.tourneyInfo")
    }
}

// MARK: - Start a tracked game

/// Set by Home: closes Tourney Info and opens Home's new-game card (the
/// Games row's +) filled in from a tourney game. nil where there's no Home
/// to go to (UI tests), which hides the button.
private struct TourneyStartGameKey: EnvironmentKey {
    static let defaultValue: ((TourneyGame) -> Void)? = nil
}

extension EnvironmentValues {
    var tourneyStartGame: ((TourneyGame) -> Void)? {
        get { self[TourneyStartGameKey.self] }
        set { self[TourneyStartGameKey.self] = newValue }
    }
}

/// Home's teams and its create-team call, so a tourney game picks teams
/// with the same pickers as Home's new-game card (`GameTeamPickers`).
struct TourneyTeamContext {
    var teams: [Team]
    var createTeam: (String, TeamDesignation, @escaping (Team?) -> Void) -> Void
}

private struct TourneyTeamContextKey: EnvironmentKey {
    static let defaultValue: TourneyTeamContext? = nil
}

extension EnvironmentValues {
    var tourneyTeams: TourneyTeamContext? {
        get { self[TourneyTeamContextKey.self] }
        set { self[TourneyTeamContextKey.self] = newValue }
    }
}

/// A tourney game's "Start Game" button.
struct TourneyStartGameButton: View {
    let game: TourneyGame
    @Environment(\.tourneyStartGame) private var startGame

    var body: some View {
        if let startGame {
            // "Track", not a bare + (which read as "add"): this opens Home's
            // new-game card to track the game.
            Button {
                startGame(game)
            } label: {
                Text("Track")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Track this game")
            .accessibilityIdentifier("tourney.startGame.\(game.opponent)")
        }
    }
}

// MARK: - List

enum TourneyRoute: Hashable {
    case own(String)
    case shared(String)
    case prospect(String)
    /// A team's page: its schedule, sponsors and trading cards (2026-11-24).
    case team(String)
}

struct TourneysView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case ours = "Our Tournaments"
        case scouting = "Scouting"
        var id: String { rawValue }
    }

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: TourneyStore
    @State private var tab: Tab
    @State private var route: TourneyRoute? = nil
    @State private var showArchived = false
    @State private var pendingArchive: Tourney? = nil
    @State private var pendingArchiveProspect: TourneyProspect? = nil
    @State private var showArchiveDialog = false
    @State private var showAddShared = false
    /// Teams this user joined as a Scheduler or Family (2026-11-22).
    @State private var joinedTeams: [JoinedTeam] = []
    @State private var showJoinTeam = false
    @State private var pendingLeave: JoinedTeam? = nil
    @State private var showLeaveDialog = false
    private let onStartGame: ((TourneyGame) -> Void)?
    /// Games + → Tournament (2026-11-24): open straight onto a new
    /// tournament for this team (.some(nil) = no team).
    private let startNewForTeam: String??
    @State private var didStartNew = false

    struct JoinedTeam: Identifiable, Equatable {
        var id: String
        var name: String
        var role: String
    }
    private let teamContext: TourneyTeamContext?

    init(inMemory: Bool = false, seed: [Tourney] = [], seedProspects: [TourneyProspect] = [],
         openId: String? = nil, openSharedId: String? = nil, tab: Tab = .ours, onStartGame: ((TourneyGame) -> Void)? = nil,
         teamContext: TourneyTeamContext? = nil, seedTeams: [TourneyStore.TeamAccess] = [],
         startNewForTeam: String?? = nil) {
        self.startNewForTeam = startNewForTeam
        self.onStartGame = onStartGame
        self.teamContext = teamContext
        _route = State(initialValue: openId.map(TourneyRoute.own) ?? openSharedId.map(TourneyRoute.shared))
        _tab = State(initialValue: tab)
        _store = StateObject(wrappedValue: {
            let store = TourneyStore(inMemory: inMemory)
            if !seedTeams.isEmpty { store.startTeams(seedTeams) }
            seed.forEach { store.save($0) }
            seedProspects.forEach { store.save($0) }
            return store
        }())
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("List", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("tourney.tab")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if let error = store.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                switch tab {
                case .ours: oursSections
                case .scouting: scoutingSections
                }
            }
            .navigationTitle("Tournaments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        tab == .ours ? createNew() : createProspect()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel(tab == .ours ? "New Tourney" : "New Scouting Entry")
                    .accessibilityIdentifier("tourney.new")
                }
            }
            .navigationDestination(item: $route) { route in
                switch route {
                case .own(let id):
                    // A Family sees a team tourney read-only, live.
                    if let t = store.tourney(id: id), !store.canEdit(t) {
                        TeamTourneyReadView(store: store, tourneyId: id)
                    } else {
                        TourneyDetailView(store: store, tourneyId: id)
                    }
                case .shared(let id):
                    SharedTourneyView(store: store, shareId: id)
                case .team(let id):
                    TeamPageView(store: store, teamId: id)
                case .prospect(let id):
                    TourneyProspectDetailView(store: store, prospectId: id) { tourney in
                        tab = .ours
                        self.route = .own(tourney.id)
                    }
                }
            }
        }
        .tint(.primary)   // no default blue accent; sheets opened inside inherit it
        .environment(\.tourneyStartGame, onStartGame)
        .environment(\.tourneyTeams, teamContext)
        .task(id: authManager.user?.uid) {
            store.start(uid: authManager.user?.uid)
            // A new team tournament waits for the teams, so it opens as
            // editable rather than read-only.
            loadTeams {
                if let teamId = startNewForTeam, !didStartNew {
                    didStartNew = true
                    createNew(teamId: teamId)
                }
            }
        }
        .appSheet(isPresented: $showJoinTeam, chrome: .handle) {
            JoinTeamSheet { loadTeams() }
        }
        .appConfirmationDialog(
            isPresented: $showLeaveDialog,
            title: "Leave \(pendingLeave?.name ?? "the team")?",
            message: "You stop seeing the team's schedule. The coach can invite you again.",
            primaryTitle: "Leave Team",
            primaryAction: {
                guard let team = pendingLeave else { return }
                authManager.leaveTeam(teamId: team.id) { _ in
                    DispatchQueue.main.async { loadTeams() }
                }
                pendingLeave = nil
            },
            secondaryTitle: "Cancel",
            secondaryAction: { pendingLeave = nil }
        )
        .appSheet(isPresented: $showAddShared, chrome: .handle) {
            AddSharedTourneySheet(store: store) { shareId in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { route = .shared(shareId) }
            }
        }
        .appConfirmationDialog(
            isPresented: $showArchiveDialog,
            title: "Archive \(pendingArchive?.displayName ?? pendingArchiveProspect?.displayName ?? "it")?",
            message: "It moves to Archived at the bottom of the list. Nothing is deleted, and you can restore it.",
            primaryTitle: "Archive",
            primaryAction: {
                if let t = pendingArchive { store.setArchived(t, true) }
                if let p = pendingArchiveProspect { store.setArchived(p, true) }
                pendingArchive = nil
                pendingArchiveProspect = nil
            },
            secondaryTitle: "Cancel",
            secondaryAction: { pendingArchive = nil; pendingArchiveProspect = nil }
        )
    }

    // MARK: Our Tourneys

    @ViewBuilder
    private var oursSections: some View {
        let sorted = Tourney.sortedForList(store.active, now: Date())
        if sorted.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Plan a tourney").font(.headline)
                    Text("Save dates, game day plans with maps and a meet spot, uniforms, gate fee, food and hotels - then share it to families in PitchMark or by text.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        createNew()
                    } label: {
                        Label("New Tourney", systemImage: "plus.circle.fill")
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 6)
            }
        } else {
            Section {
                ForEach(sorted) { t in
                    if store.canEdit(t) {
                        tourneyRow(t)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    pendingArchive = t
                                    showArchiveDialog = true
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(.gray)
                            }
                    } else {
                        tourneyRow(t)
                    }
                }
            }
        }


        Section {
            ForEach(store.followed) { f in
                Button {
                    route = .shared(f.id)
                } label: {
                    rowLabel(icon: "person.2.fill", iconColor: .secondary,
                             title: f.name.isEmpty ? "Shared tourney" : f.name, lines: ["Shared with you"])
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tourney.shared.\(f.name)")
                .swipeActions {
                    Button(role: .destructive) {
                        store.unfollow(f.id)
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                    }
                }
            }
            Button {
                showAddShared = true
            } label: {
                Label("Add a Shared Tourney", systemImage: "link.badge.plus")
            }
            .accessibilityIdentifier("tourney.addShared")
        } header: {
            Text("Shared with Me")
        } footer: {
            Text("A coach shares a tourney from its Share menu. Open their link, or paste it here.")
        }

        if !store.archived.isEmpty {
            Section {
                DisclosureGroup("Archived (\(store.archived.count))", isExpanded: $showArchived) {
                    ForEach(store.archived) { t in
                        tourneyRow(t)
                            .swipeActions(edge: .leading) {
                                Button {
                                    store.setArchived(t, false)
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)
                            }
                    }
                }
            }
        }
    }

    private func tourneyRow(_ t: Tourney) -> some View {
        Button {
            route = .own(t.id)
        } label: {
            rowLabel(
                icon: "trophy.fill",
                iconColor: t.isPast(now: Date()) ? .secondary : .orange,
                title: t.displayName,
                lines: [t.dateRangeText(), t.venue.name.isEmpty ? t.venue.address : t.venue.name]
                    + (store.teamName(t.teamId).map { ["Team: \($0)"] } ?? [])
                    + (t.shareId != nil ? ["Shared in PitchMark"] : [])
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tourney.row.\(t.displayName)")
    }

    private func rowLabel(icon: String, iconColor: Color, title: String, lines: [String]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                ForEach(lines.filter { !$0.isEmpty }, id: \.self) { line in
                    Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    // MARK: Scouting

    @ViewBuilder
    private var scoutingSections: some View {
        let list = store.activeProspects
        if list.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scout tourneys").font(.headline)
                    Text("Keep the tourneys you find online in one place - links, organizer, cost, dates and distance - while the staff decides which to enter.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        createProspect()
                    } label: {
                        Label("Add a Tourney", systemImage: "plus.circle.fill")
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 6)
            }
        } else {
            Section {
                ForEach(list) { p in
                    prospectRow(p)
                        .swipeActions(edge: .trailing) {
                            Button {
                                pendingArchiveProspect = p
                                showArchiveDialog = true
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.gray)
                        }
                }
            } footer: {
                Text("For the coaching staff - families don't see this list.")
            }
        }
        if !store.archivedProspects.isEmpty {
            Section {
                DisclosureGroup("Archived (\(store.archivedProspects.count))", isExpanded: $showArchived) {
                    ForEach(store.archivedProspects) { p in
                        prospectRow(p)
                            .swipeActions(edge: .leading) {
                                Button {
                                    store.setArchived(p, false)
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)
                            }
                    }
                }
            }
        }
    }

    private func prospectRow(_ p: TourneyProspect) -> some View {
        Button {
            route = .prospect(p.id)
        } label: {
            let facts = [p.organizer, p.cost, p.distance].map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " · ")
            rowLabel(icon: "binoculars.fill", iconColor: .secondary, title: p.displayName,
                     lines: [p.dateText(), facts])
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("prospect.row.\(p.displayName)")
    }

    private func createNew(teamId: String? = nil) {
        var t = Tourney()
        t.teamId = teamId
        store.save(t)
        route = .own(t.id)
    }

    /// Every team this user is on: which tourneys they see and edit, and
    /// the joined ones listed under Your Teams.
    private func loadTeams(then: (() -> Void)? = nil) {
        guard let uid = authManager.user?.uid else { then?(); return }
        authManager.loadMyTeams(includeJoined: true) { entries, _ in
            let access: [TourneyStore.TeamAccess] = entries.compactMap { entry in
                guard let id = entry.team.id else { return nil }
                return .init(id: id, name: entry.team.nameWithClass,
                             canEdit: TeamAccessRules.schedules(team: entry.team, membership: entry.membership, uid: uid))
            }
            store.startTeams(access)
            joinedTeams = entries
                .filter { !TeamAccessRules.coaches(team: $0.team, membership: $0.membership, uid: uid) }
                .compactMap { entry in
                    entry.team.id.map { JoinedTeam(id: $0, name: entry.team.nameWithClass, role: entry.membership.roleTitle) }
                }
            then?()
        }
    }

    private func createProspect() {
        let p = TourneyProspect()
        store.save(p)
        route = .prospect(p.id)
    }
}

// MARK: - Team tourneys and joining a team (2026-11-22)

/// A team tourney for a Family: read-only, live from the store (a pushed
/// view keeps the value it was pushed with, so it reads the store itself).
struct TeamTourneyReadView: View {
    @ObservedObject var store: TourneyStore
    let tourneyId: String
    @StateObject private var sponsors = TeamSponsorStore()

    var body: some View {
        Group {
            if let tourney = store.tourney(id: tourneyId) {
                TourneyReadView(tourney: tourney, sponsors: sponsors.activeSlots)
                    .navigationTitle(tourney.displayName)
                    .task(id: tourney.teamId) { sponsors.start(teamId: tourney.teamId) }
            } else {
                ContentUnavailableView("No Longer on the Team", systemImage: "person.3",
                                       description: Text("The coach took this tourney off the team, or you left the team."))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Paste a team invite link or code; joins the team.
struct JoinTeamSheet: View {
    let onJoined: () -> Void

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isJoining = false
    @State private var errorText: String? = nil
    @State private var followerNote: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Link or code", text: $text)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("joinTeam.code")
                } footer: {
                    Text("Your coach sends a team link or a code. Families see the schedule; Schedulers can also edit it.")
                }
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.red)
                }
                if let followerNote {
                    Text(followerNote).font(.footnote)
                }
            }
            .navigationTitle("Join a Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") { join() }
                        .fontWeight(.semibold)
                        .disabled(isJoining || TeamAccessRules.inviteToken(from: text) == nil)
                        .accessibilityIdentifier("joinTeam.join")
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func join() {
        guard let token = TeamAccessRules.inviteToken(from: text) else { return }
        isJoining = true
        errorText = nil
        // A follower code makes a pending follower (GameFeedService).
        GameFeedService.shared.join(token: token, authManager: authManager) { result in
            DispatchQueue.main.async {
                isJoining = false
                switch result {
                case .success(.member):
                    onJoined()
                    dismiss()
                case .success(.followerPending(let teamName)):
                    followerNote = "You asked to follow \(teamName). The coach approves you - then their games show under Home → Teams → Following."
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Add a shared tourney

struct AddSharedTourneySheet: View {
    @ObservedObject var store: TourneyStore
    let onAdded: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var working = false
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Paste the tourney link", text: $text, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("tourney.sharedLink")
                    Button("Paste") {
                        text = UIPasteboard.general.string ?? text
                    }
                } footer: {
                    Text("The link looks like \(TourneyShareLink.host)/tourney/…")
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .navigationTitle("Add a Shared Tourney")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await add() }
                    } label: {
                        if working { ProgressView() } else { Text("Add").fontWeight(.semibold) }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)
                    .accessibilityIdentifier("tourney.sharedAdd")
                }
            }
        }
    }

    private func add() async {
        working = true
        error = nil
        defer { working = false }
        do {
            try await store.follow(linkOrId: text)
            if let id = TourneyShareLink.shareId(from: text) { onAdded(id) }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - One tourney (editor)

/// One tourney's page. Edits go into a local draft and save a moment after
/// the last change (and on leaving), so typing doesn't write every key.
struct TourneyDetailView: View {
    @ObservedObject var store: TourneyStore
    let tourneyId: String

    @State private var draft: Tourney? = nil
    @State private var saveTask: Task<Void, Never>? = nil
    @State private var placeSearch: PlaceSearchTarget? = nil
    @State private var areaPickerFor: AreaTarget? = nil
    @State private var editingSpot: TourneyMeetSpot? = nil
    @State private var showTextShare = false
    @State private var showPreview = false
    @State private var appShareItems: [Any]? = nil
    @State private var showStopSharing = false
    @State private var newChecklistText = ""
    @State private var editingGame: TourneyGame? = nil
    /// "Share with a Team…" picked, waiting on the confirmation.
    @State private var pendingTeam: TourneyStore.TeamAccess? = nil
    @State private var showMoveToTeam = false

    enum PlaceSearchTarget: Identifiable {
        case venue
        case hotel(String)
        var id: String {
            switch self {
            case .venue: return "venue"
            case .hotel(let id): return "hotel-\(id)"
            }
        }
    }

    struct AreaTarget: Identifiable {
        let id = UUID()
        /// Replacing an existing spot's area keeps its id, title and marks.
        let existing: TourneyMeetSpot?
    }

    var body: some View {
        Group {
            if draft != nil {
                form
            } else {
                ProgressView()
            }
        }
        .navigationTitle(draft?.displayName ?? "Tourney")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { shareMenu }
        }
        .onAppear {
            if draft == nil { draft = store.tourney(id: tourneyId) }
        }
        .onChange(of: store.tourneys) { _, _ in
            // First load only - after that the draft is the source.
            if draft == nil { draft = store.tourney(id: tourneyId) }
        }
        .onChange(of: store.teamTourneys) { _, _ in
            if draft == nil { draft = store.tourney(id: tourneyId) }
        }
        .appConfirmationDialog(
            isPresented: $showMoveToTeam,
            title: "Put this tourney on \(pendingTeam?.name ?? "the team")?",
            message: "Your Schedulers can edit it and everyone on the team sees it, kept up to date. It stays with the team.",
            primaryTitle: "Put on Team",
            primaryAction: {
                guard let team = pendingTeam, draft != nil else { return }
                draft!.teamId = team.id
                flushSave()
                pendingTeam = nil
            },
            secondaryTitle: "Cancel",
            secondaryAction: { pendingTeam = nil }
        )
        .onChange(of: draft) { old, new in
            guard old != nil, new != nil, old != new else { return }
            scheduleSave()
        }
        .onDisappear { flushSave() }
        .appSheet(item: $placeSearch, chrome: .handle) { target in
            TourneyPlaceSearchSheet(initialQuery: initialQuery(for: target)) { place in
                apply(place, to: target)
            }
        }
        .appSheet(item: $areaPickerFor, chrome: .handle) { target in
            TourneyMeetAreaPicker(start: target.existing?.meetPlace ?? draft?.venue ?? TourneyPlace()) { region in
                var spot = target.existing ?? TourneyMeetSpot(
                    title: (draft?.meetSpots.isEmpty ?? true) ? "Day 1 warmups" : "",
                    centerLatitude: 0, centerLongitude: 0, latitudeDelta: 0, longitudeDelta: 0
                )
                spot.centerLatitude = region.center.latitude
                spot.centerLongitude = region.center.longitude
                spot.latitudeDelta = region.span.latitudeDelta
                spot.longitudeDelta = region.span.longitudeDelta
                // Open the markup editor once this sheet is gone.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { editingSpot = spot }
            }
        }
        .appSheet(item: $editingSpot, chrome: .handle) { spot in
            TourneyMeetSpotEditor(spot: spot, onChangeArea: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    let saved = draft?.meetSpots.first { $0.id == spot.id } ?? spot
                    areaPickerFor = AreaTarget(existing: saved)
                }
            }) { saved in
                guard draft != nil else { return }
                if let i = draft!.meetSpots.firstIndex(where: { $0.id == saved.id }) {
                    draft!.meetSpots[i] = saved
                } else {
                    draft!.meetSpots.append(saved)
                }
            }
        }
        .appSheet(item: $editingGame, chrome: .handle) { game in
            TourneyGameEditorSheet(game: game, isNew: !(draft?.games.contains { $0.id == game.id } ?? false)) { saved in
                guard draft != nil else { return }
                if let i = draft!.games.firstIndex(where: { $0.id == saved.id }) {
                    draft!.games[i] = saved
                } else {
                    draft!.games.append(saved)
                }
            } onDelete: { id in
                draft?.games.removeAll { $0.id == id }
            }
        }
        .appSheet(isPresented: $showTextShare, chrome: .handle) {
            if let draft { TourneyShareView(tourney: draft) }
        }
        .appSheet(isPresented: $showPreview, chrome: .handle) {
            if let draft {
                NavigationStack {
                    TourneyReadView(tourney: draft)
                        .navigationTitle("As Others See It")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { showPreview = false } }
                        }
                }
                .tint(.primary)
            }
        }
        .appSheet(isPresented: Binding(get: { appShareItems != nil }, set: { if !$0 { appShareItems = nil } }), chrome: .none) {
            ShareSheet(items: appShareItems ?? [])
        }
        .appConfirmationDialog(
            isPresented: $showStopSharing,
            title: "Stop sharing?",
            message: "Everyone who saved the link loses this tourney from their PitchMark. Your page is kept. Sharing again makes a new link.",
            primaryTitle: "Stop Sharing",
            primaryRole: .destructive,
            primaryAction: {
                flushSave()
                if let t = draft {
                    store.stopSharing(t)
                    draft?.shareId = nil
                }
            },
            secondaryTitle: "Cancel"
        )
    }

    private var shareMenu: some View {
        Menu {
            Button {
                shareInApp()
            } label: {
                Label(draft?.shareId == nil ? "Share in PitchMark" : "Send PitchMark Link Again",
                      systemImage: "person.2.fill")
            }
            Button {
                flushSave()
                showTextShare = true
            } label: {
                Label("Share as Text", systemImage: "text.bubble")
            }
            Button {
                showPreview = true
            } label: {
                Label("Preview as Shared", systemImage: "eye")
            }
            if draft?.shareId != nil {
                Button(role: .destructive) {
                    showStopSharing = true
                } label: {
                    Label("Stop Sharing", systemImage: "xmark.circle")
                }
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .disabled(draft == nil)
        .accessibilityIdentifier("tourney.share")
    }

    private func shareInApp() {
        guard var t = draft else { return }
        saveTask?.cancel()
        let url = store.startSharing(t)
        t.shareId = store.tourney(id: t.id)?.shareId
        draft = t
        appShareItems = ["\(t.displayName) - tap to open it in PitchMark:\n\(url.absoluteString)"]
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            flushSave()
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        guard let draft, draft != store.tourney(id: tourneyId) else { return }
        store.save(draft)
    }

    // MARK: Form

    private var t: Binding<Tourney> {
        Binding(get: { draft ?? Tourney() }, set: { draft = $0 })
    }

    private var form: some View {
        Form {
            if t.wrappedValue.shareId != nil {
                Section {
                    Label("Shared in PitchMark - changes reach everyone with the link.", systemImage: "person.2.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            teamSection
            overviewSection
            gamesSection
            gameDaySection
            uniformsSection
            generalInfoSection
            gateFeeSection
            foodSection
            hotelsSection
            linksSection
            Section("Notes") {
                TextField("Anything else - rules, contacts, food nearby", text: t.notes, axis: .vertical)
                    .lineLimit(3...10)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Which team the tourney is on (2026-11-22). On one: the team's
    /// Schedulers edit it and every member sees it. Not yet: put it on one
    /// you schedule for.
    @ViewBuilder
    private var teamSection: some View {
        if let teamId = t.wrappedValue.teamId {
            Section {
                Label("Team: \(store.teamName(teamId) ?? "your team")", systemImage: "person.3.fill")
                    .accessibilityIdentifier("tourney.team")
            } footer: {
                Text("Your Schedulers can edit this tourney, and everyone on the team sees it - changes reach them on their own.")
            }
        } else if !store.editableTeams.isEmpty {
            Section {
                Menu {
                    ForEach(store.editableTeams) { team in
                        Button(team.name) {
                            pendingTeam = team
                            showMoveToTeam = true
                        }
                    }
                } label: {
                    Label("Share with a Team…", systemImage: "person.3")
                }
                .accessibilityIdentifier("tourney.putOnTeam")
            } footer: {
                Text("Every member of the team sees it, and your Schedulers can edit it - no link to send each time.")
            }
        }
    }

    private var overviewSection: some View {
        Section {
            TextField("Tourney name", text: t.name)
                .font(.headline)
                .accessibilityIdentifier("tourney.name")
            DatePicker("Starts", selection: Binding(
                get: { t.wrappedValue.startDate },
                set: { newValue in
                    let length = t.wrappedValue.endDate.timeIntervalSince(t.wrappedValue.startDate)
                    t.wrappedValue.startDate = newValue
                    // Moving the start keeps the tourney's length.
                    t.wrappedValue.endDate = newValue.addingTimeInterval(max(0, length))
                }
            ), displayedComponents: .date)
            DatePicker("Ends", selection: t.endDate, in: t.wrappedValue.startDate..., displayedComponents: .date)

            placeRow(t.wrappedValue.venue, empty: "Add the venue", target: .venue)
            if !t.wrappedValue.venue.isEmpty {
                TourneyDirectionsRow(place: t.wrappedValue.venue)
            }
        } header: {
            Text("Tourney")
        }
    }

    private var gameDaySection: some View {
        Section {
            TextField("Field / complex (e.g. Field 7, North)", text: t.gameDay.fieldName)
            TextField("Game day notes", text: t.gameDay.notes, axis: .vertical)
                .lineLimit(2...6)

            ForEach(t.wrappedValue.meetSpots) { spot in
                HStack(spacing: 12) {
                    Button {
                        editingSpot = spot
                    } label: {
                        HStack(spacing: 12) {
                            TourneyMeetSpotThumbnail(spot: spot)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(spot.title.isEmpty ? "Meet spot" : spot.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("Tap to mark up and share")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    TourneyDirectionsMenu(place: spot.meetPlace)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        draft?.meetSpots.removeAll { $0.id == spot.id }
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
            Button {
                areaPickerFor = AreaTarget(existing: nil)
            } label: {
                Label("Add Meet Spot (satellite)", systemImage: "map")
            }
            .accessibilityIdentifier("tourney.addMeetSpot")
        } header: {
            Text("Game Day")
        } footer: {
            Text("A meet spot is a satellite picture of the complex with a pin, notes and arrows on it - share it so families can find the team on day one.")
        }
    }

    private var gamesSection: some View {
        Section {
            let games = TourneyGame.sorted(t.wrappedValue.games)
            ForEach(games) { game in
                HStack(spacing: 10) {
                    Button {
                        editingGame = game
                    } label: {
                        TourneyGameRow(game: game, showStage: Set(games.map(\.stage)).count > 1)
                    }
                    .buttonStyle(.plain)
                    TourneyStartGameButton(game: game)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        draft?.games.removeAll { $0.id == game.id }
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
            HStack {
                Button {
                    addGame(.scheduled)
                } label: {
                    Label("Scheduled Game", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("tourney.addScheduledGame")
                Spacer()
                Button {
                    addGame(.bracket)
                } label: {
                    Label("Bracket Game", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("tourney.addBracketGame")
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        } header: {
            Text("Games")
        } footer: {
            Text("Add the scheduled games now, and bracket games as they're set.")
        }
    }

    private func addGame(_ stage: TourneyGameStage) {
        let start = TourneyGame.nextStart(after: t.wrappedValue.games, tourneyStart: t.wrappedValue.startDate)
        editingGame = TourneyGame(stage: stage, time: start)
    }

    private var uniformsSection: some View {
        Section {
            ForEach(0..<t.wrappedValue.uniformDayCount, id: \.self) { index in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Day \(index + 1)").font(.subheadline.weight(.semibold))
                        if let date = t.wrappedValue.date(ofDay: index) {
                            Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 84, alignment: .leading)
                    TextField("Uniform", text: Binding(
                        get: { t.wrappedValue.uniform(day: index) },
                        set: { draft?.setUniform($0, day: index) }
                    ))
                    .accessibilityIdentifier("tourney.uniform.\(index)")
                }
            }
            .onDelete { offsets in
                for index in offsets.sorted(by: >) { draft?.removeUniformDay(index) }
            }
        } header: {
            HStack {
                Text("Uniforms")
                Spacer()
                Button {
                    draft?.addUniformDay()
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add a day")
                .accessibilityIdentifier("tourney.addUniformDay")
            }
        }
    }

    private var generalInfoSection: some View {
        Section {
            Toggle("Metal cleats allowed", isOn: t.metalCleatsAllowed)
                .accessibilityIdentifier("tourney.metalCleats")
            ForEach(t.wrappedValue.checklist) { item in
                Text(item.text)
            }
            .onDelete { draft?.checklist.remove(atOffsets: $0) }
            HStack {
                TextField("Add an item", text: $newChecklistText)
                    .onSubmit(addChecklistItem)
                    .submitLabel(.done)
                    .accessibilityIdentifier("tourney.newItem")
                Button("Add", action: addChecklistItem)
                    .disabled(newChecklistText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("General Info")
        } footer: {
            Text("Everyone you share with sees these. They can add their own items, just for them.")
        }
    }

    private func addChecklistItem() {
        let text = newChecklistText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        draft?.checklist.append(TourneyChecklistItem(text: text))
        newChecklistText = ""
    }

    private var gateFeeSection: some View {
        Section("Gate Fee") {
            Toggle("Gate fee", isOn: t.gateFee)
                .accessibilityIdentifier("tourney.gateFee")
            TextField("Notes (e.g. $10 per adult per day, kids free)", text: t.gateFeeNotes, axis: .vertical)
                .accessibilityIdentifier("tourney.gateFeeNotes")
            Toggle("Cash only", isOn: t.cashOnly)
                .accessibilityIdentifier("tourney.cashOnly")
        }
    }

    private var foodSection: some View {
        Section {
            ForEach(t.food) { $item in
                HStack(spacing: 10) {
                    Button {
                        item.done.toggle()
                    } label: {
                        Image(systemName: item.done ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundStyle(item.done ? Color.green : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(item.done ? "Covered" : "Not covered")
                    VStack(spacing: 6) {
                        TextField("Family name", text: $item.family)
                            .font(.subheadline.weight(.semibold))
                        TextField("Food", text: $item.food)
                            .font(.subheadline)
                    }
                }
            }
            .onDelete { draft?.food.remove(atOffsets: $0) }
            Button {
                draft?.food.append(TourneyFoodItem())
            } label: {
                Label("Add Family", systemImage: "fork.knife")
            }
            .accessibilityIdentifier("tourney.addFood")
        } header: {
            Text("Tournament Food")
        }
    }

    private var linksSection: some View {
        Section("Links") {
            ForEach(t.links) { $link in
                TourneyLinkEditorRow(link: $link)
            }
            .onDelete { draft?.links.remove(atOffsets: $0) }
            Button {
                draft?.links.append(TourneyLink(urlString: UIPasteboard.general.hasURLs ? (UIPasteboard.general.url?.absoluteString ?? "") : ""))
            } label: {
                Label("Add Link", systemImage: "link")
            }
        }
    }

    private var hotelsSection: some View {
        Section {
            ForEach(t.hotels) { $hotel in
                VStack(alignment: .leading, spacing: 8) {
                    placeRow(hotel.place, empty: "Find the hotel", target: .hotel(hotel.id))
                    if !hotel.place.isEmpty {
                        TourneyDirectionsRow(place: hotel.place)
                    }
                    HStack {
                        Text("Per night").font(.subheadline)
                        Spacer()
                        TextField("$0", value: $hotel.nightlyRate, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                    }
                    Stepper("Nights: \(hotel.nights)", value: $hotel.nights, in: 0...14)
                        .font(.subheadline)
                    if let total = hotel.stayTotal {
                        Text("Stay: \(TourneyMoney.format(total)) before taxes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextField("Group code / block name", text: $hotel.bookingCode)
                        .font(.subheadline)
                    optionalDateRow("Book by", value: $hotel.bookBy, components: [.date])
                    HStack {
                        TextField("Phone", text: $hotel.phone)
                            .keyboardType(.phonePad)
                            .font(.subheadline)
                        if let url = hotel.phoneURL {
                            Link(destination: url) { Image(systemName: "phone.fill") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Call hotel")
                        }
                    }
                    HStack {
                        TextField("Booking link", text: $hotel.link)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.subheadline)
                        if let url = TourneyLink.normalizedURL(hotel.link) {
                            Link(destination: url) { Image(systemName: "safari") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Open booking link")
                        }
                    }
                    TextField("Notes (breakfast, pool, distance)", text: $hotel.notes, axis: .vertical)
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
            .onDelete { draft?.hotels.remove(atOffsets: $0) }
            Button {
                let hotel = TourneyHotel(nights: max(1, t.wrappedValue.days().count - 1))
                draft?.hotels.append(hotel)
                placeSearch = .hotel(hotel.id)
            } label: {
                Label("Add Hotel", systemImage: "bed.double")
            }
        } header: {
            Text("Hotels")
        }
    }

    // MARK: Rows

    private func placeRow(_ place: TourneyPlace, empty: String, target: PlaceSearchTarget) -> some View {
        Button {
            placeSearch = target
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(.secondary)
                if place.isEmpty {
                    Text(empty).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        if !place.name.isEmpty {
                            Text(place.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        }
                        if !place.address.isEmpty {
                            Text(place.address).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func optionalDateRow(_ title: String, value: Binding<Date?>, components: DatePickerComponents) -> some View {
        TourneyOptionalDateRow(title: title, value: value, components: components,
                               defaultDate: defaultDate(for: components))
    }

    private func defaultDate(for components: DatePickerComponents) -> Date {
        let start = Calendar.current.startOfDay(for: t.wrappedValue.startDate)
        if components.contains(.hourAndMinute) {
            return Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: start) ?? start
        }
        return Date()
    }

    private func initialQuery(for target: PlaceSearchTarget) -> String {
        switch target {
        case .venue:
            return draft?.venue.searchText ?? ""
        case .hotel(let id):
            let hotel = draft?.hotels.first { $0.id == id }
            if let hotel, !hotel.place.isEmpty { return hotel.place.searchText }
            let near = draft?.venue.address.isEmpty == false ? draft!.venue.address : (draft?.venue.name ?? "")
            return near.isEmpty ? "hotels" : "hotels near \(near)"
        }
    }

    private func apply(_ place: TourneyPlace, to target: PlaceSearchTarget) {
        switch target {
        case .venue:
            draft?.venue = place
        case .hotel(let id):
            if let i = draft?.hotels.firstIndex(where: { $0.id == id }) {
                draft?.hotels[i].place = place
            }
        }
    }
}

// MARK: - Games

/// "Sat 9:00 AM  vs Hawks · Field 7  W 7-3", with a Bracket tag when the
/// list has both kinds.
struct TourneyGameRow: View {
    let game: TourneyGame
    var showStage = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(game.time, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(game.time, format: .dateTime.hour().minute())
                    .font(.subheadline.weight(.semibold))
            }
            .frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(game.summary.isEmpty ? "Game" : game.summary)
                    .font(.subheadline)
                    .foregroundStyle(game.canceled ? .secondary : .primary)
                    .strikethrough(game.canceled)
                if game.canceled {
                    Text("Canceled")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("tourney.game.canceled")
                }
                if let arrive = game.arriveAt {
                    Text("Arrive \(arrive.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if showStage {
                    Text(game.stage.title)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.secondarySystemFill), in: Capsule())
                }
            }
            Spacer(minLength: 0)
            if !game.result.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(game.result).font(.subheadline.weight(.semibold))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tourney.game.\(game.opponent)")
    }
}

struct TourneyGameEditorSheet: View {
    let isNew: Bool
    let onSave: (TourneyGame) -> Void
    let onDelete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.tourneyStartGame) private var startGame
    @Environment(\.tourneyTeams) private var teamContext
    @State private var game: TourneyGame
    @State private var isAddingTeam = false

    init(game: TourneyGame, isNew: Bool, onSave: @escaping (TourneyGame) -> Void, onDelete: @escaping (String) -> Void) {
        _game = State(initialValue: game)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Stage", selection: $game.stage) {
                    ForEach(TourneyGameStage.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                DatePicker("Game time", selection: $game.time, displayedComponents: [.date, .hourAndMinute])
                TourneyOptionalDateRow(title: "Arrive at", value: $game.arriveAt,
                                       components: [.hourAndMinute], defaultDate: game.suggestedArriveAt)
                if let teamContext {
                    GameTeamPickers(
                        myTeams: teamContext.teams,
                        ourTeamId: $game.ourTeamId,
                        opponentTeamId: $game.opponentTeamId,
                        opponentName: $game.opponent,
                        isAddingTeam: $isAddingTeam,
                        onCreateTeam: teamContext.createTeam
                    )
                    .padding(.vertical, 4)
                }
                TextField(teamContext == nil ? "Opponent" : "Opponent name (or Winner of G3)", text: $game.opponent)
                    .accessibilityIdentifier("tourneyGame.opponent")
                HStack {
                    Text("Field").foregroundStyle(.secondary)
                    TextField("Number or name", text: $game.field)
                        .accessibilityIdentifier("tourneyGame.field")
                }
                TextField("Result (e.g. W 7-3)", text: $game.result)
                // Stays on the schedule marked Canceled - families see it
                // (2026-11-22).
                Toggle("Canceled", isOn: $game.canceled)
                    .accessibilityIdentifier("tourneyGame.canceled")
                if let startGame {
                    Section {
                        Button {
                            onSave(game)
                            startGame(game)
                        } label: {
                            Label("Start This Game", systemImage: "plus.circle.fill")
                        }
                        .disabled(isAddingTeam)
                    } footer: {
                        Text("Opens a new game on Home with the teams, opponent and time filled in.")
                    }
                }
                if !isNew {
                    Section {
                        Button("Remove Game", role: .destructive) {
                            onDelete(game.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Add Game" : "Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(game)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(isAddingTeam)
                    .accessibilityIdentifier("tourneyGame.save")
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// One game on a shared tourney, read-only: when, where, how to get
/// there, and - below, for the parents and assistants who track - Track
/// This Game.
struct TourneyGameCardSheet: View {
    let game: TourneyGame
    let venue: TourneyPlace
    let meetSpots: [TourneyMeetSpot]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.tourneyStartGame) private var startGame

    var body: some View {
        NavigationStack {
            List {
                if game.canceled {
                    Section {
                        Label("This game is canceled", systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                            .font(.headline)
                    }
                }
                Section {
                    row("When", game.time.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))
                    if let arrive = game.arriveAt {
                        row("Arrive", arrive.formatted(date: .omitted, time: .shortened))
                    }
                    if !game.fieldLabel.isEmpty { row("Field", game.fieldLabel) }
                    if !game.opponent.trimmingCharacters(in: .whitespaces).isEmpty { row("Opponent", game.opponent) }
                    row("Stage", game.stage.title)
                    if !game.result.trimmingCharacters(in: .whitespaces).isEmpty { row("Result", game.result) }
                }
                if !venue.isEmpty {
                    Section("Directions to \(venue.name.isEmpty ? "the venue" : venue.name)") {
                        TourneyDirectionsRow(place: venue)
                    }
                }
                ForEach(meetSpots) { spot in
                    Section("Directions to \(spot.title.isEmpty ? "the meet spot" : spot.title)") {
                        TourneyDirectionsRow(place: spot.meetPlace)
                    }
                }
                if let startGame {
                    Section {
                        Button {
                            startGame(game)
                        } label: {
                            Label("Track This Game", systemImage: "figure.baseball")
                        }
                        .accessibilityIdentifier("tourneyGameCard.track")
                    } footer: {
                        Text("For tracking pitches in PitchMark. Opens a new game on Home with the opponent and time filled in.")
                    }
                }
            }
            .navigationTitle(game.summary.isEmpty ? "Game" : game.summary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

// MARK: - Shared pieces

struct TourneyOptionalDateRow: View {
    let title: String
    @Binding var value: Date?
    let components: DatePickerComponents
    let defaultDate: Date

    var body: some View {
        HStack {
            if let date = value {
                DatePicker(title, selection: Binding(get: { date }, set: { value = $0 }),
                           displayedComponents: components)
                Button {
                    value = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear \(title)")
            } else {
                Text(title)
                Spacer()
                Button("Set") { value = defaultDate }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("optionalDate.\(title)")
            }
        }
        .font(.subheadline)
    }
}

struct TourneyLinkEditorRow: View {
    @Binding var link: TourneyLink

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Title (Schedule, Brackets, Rules)", text: $link.title)
                .font(.subheadline.weight(.semibold))
            HStack {
                TextField("Web address", text: $link.urlString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                if let url = link.url {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Open \(link.displayTitle)")
                }
            }
        }
    }
}

// MARK: - Read-only page (shared tourneys)

/// A shared tourney, live from its `sharedTourneys` copy, in the read-only
/// layout. Also the owner's "Preview as Shared".
struct SharedTourneyView: View {
    @ObservedObject var store: TourneyStore
    let shareId: String
    @StateObject private var listener: SharedTourneyListener

    init(store: TourneyStore, shareId: String, preview: Tourney? = nil) {
        self.store = store
        self.shareId = shareId
        _listener = StateObject(wrappedValue: SharedTourneyListener(shareId: shareId, preview: preview))
    }

    var body: some View {
        Group {
            switch listener.state {
            case .loading:
                ProgressView()
            case .gone:
                ContentUnavailableView {
                    Label("No Longer Shared", systemImage: "person.2.slash")
                } description: {
                    Text("The coach stopped sharing this tourney, or the link is wrong.")
                } actions: {
                    Button("Remove from My List") { store.unfollow(shareId) }
                }
            case .loaded(let tourney):
                TourneyReadView(tourney: tourney, personal: .init(
                    items: store.followed.first { $0.id == shareId }?.myItems ?? [],
                    add: { store.addMyItem($0, to: shareId) },
                    remove: { store.removeMyItem($0, from: shareId) }
                ))
                .onAppear { store.refreshFollowedName(shareId, tourney.displayName) }
            }
        }
        .navigationTitle(loadedName ?? "Shared Tourney")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var loadedName: String? {
        if case .loaded(let t) = listener.state { return t.displayName }
        return nil
    }
}

/// Every section of a tourney, read-only, in the editor's order. Empty
/// sections are left out.
struct TourneyReadView: View {
    let tourney: Tourney
    /// A follower's own General Info items, when the page is opened from
    /// Shared with Me (nil in the owner's preview).
    var personal: PersonalItems? = nil
    /// The team's sponsors, on a team tourney's page (2026-11-24) - drawn
    /// by SponsorBadge on the tourney page surface.
    var sponsors: [SponsorSlot] = []

    struct PersonalItems {
        var items: [TourneyChecklistItem]
        var add: (String) -> Void
        var remove: (String) -> Void
    }

    @State private var viewingSpot: TourneyMeetSpot? = nil
    @State private var viewingGame: TourneyGame? = nil
    @State private var newItem = ""
    @State private var shareTextItems: [Any]? = nil

    private var t: Tourney { tourney }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.displayName).font(.title3.weight(.bold))
                    Text(t.dateRangeText()).font(.subheadline).foregroundStyle(.secondary)
                }
                if !t.venue.isEmpty {
                    placeLines(t.venue)
                    TourneyDirectionsRow(place: t.venue)
                }
            }

            if !sponsors.isEmpty {
                Section("Team Sponsors") {
                    ForEach(sponsors) { slot in
                        SponsorBadge(slot: slot, surface: .tourneyPage)
                    }
                }
            }

            let games = TourneyGame.sorted(t.games)
            if !games.isEmpty {
                Section("Games") {
                    // No Track on the row here: on a shared tourney most
                    // readers are families. Tapping opens the game's card,
                    // with Directions first and Track This Game below.
                    ForEach(games) { game in
                        Button {
                            viewingGame = game
                        } label: {
                            HStack(spacing: 8) {
                                TourneyGameRow(game: game, showStage: Set(games.map(\.stage)).count > 1)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("tourneyRead.game.\(game.opponent)")
                    }
                }
            }

            let g = t.gameDay
            if !g.fieldName.isBlank || !g.notes.isBlank || !t.meetSpots.isEmpty {
                Section("Game Day") {
                    if !g.fieldName.isBlank { fact("Field / complex", g.fieldName) }
                    if !g.notes.isBlank { Text(g.notes).font(.subheadline) }
                    ForEach(t.meetSpots) { spot in
                        HStack(spacing: 12) {
                            Button {
                                viewingSpot = spot
                            } label: {
                                HStack(spacing: 12) {
                                    TourneyMeetSpotThumbnail(spot: spot)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(spot.title.isEmpty ? "Meet spot" : spot.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text("Tap to see the map").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            TourneyDirectionsMenu(place: spot.meetPlace)
                        }
                    }
                }
            }

            let uniforms = (0..<t.uniformDayCount).filter { !t.uniform(day: $0).isBlank }
            if !uniforms.isEmpty {
                Section("Uniforms") {
                    ForEach(uniforms, id: \.self) { index in
                        let when = t.date(ofDay: index).map {
                            " · " + $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                        } ?? ""
                        fact("Day \(index + 1)\(when)", t.uniform(day: index))
                    }
                }
            }

            Section("General Info") {
                Label(t.metalCleatsAllowed ? "Metal cleats allowed" : "No metal cleats",
                      systemImage: t.metalCleatsAllowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(t.metalCleatsAllowed ? Color.green : Color.red)
                ForEach(t.checklist) { item in
                    Text(item.text).font(.subheadline)
                }
                if let personal {
                    ForEach(personal.items) { item in
                        Text(item.text)
                            .font(.subheadline)
                            .swipeActions {
                                Button(role: .destructive) {
                                    personal.remove(item.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                    HStack {
                        TextField("Add an item for you", text: $newItem)
                            .onSubmit(addPersonal)
                            .submitLabel(.done)
                            .accessibilityIdentifier("tourney.myItem")
                        Button("Add", action: addPersonal)
                            .disabled(newItem.isBlank)
                    }
                    .font(.subheadline)
                }
            }

            if t.gateFee || t.cashOnly || !t.gateFeeNotes.isBlank {
                Section("Gate Fee") {
                    if t.gateFee { Label("Gate fee", systemImage: "ticket.fill").font(.subheadline) }
                    if !t.gateFeeNotes.isBlank { Text(t.gateFeeNotes).font(.subheadline) }
                    if t.cashOnly { Label("Cash only", systemImage: "banknote.fill").font(.subheadline.weight(.semibold)) }
                }
            }

            let food = t.food.filter { !$0.isEmpty }
            if !food.isEmpty {
                Section("Tournament Food") {
                    ForEach(food) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.done ? "checkmark.square.fill" : "square")
                                .foregroundStyle(item.done ? Color.green : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.family.isBlank ? "Open" : item.family).font(.subheadline.weight(.semibold))
                                if !item.food.isBlank { Text(item.food).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }

            let hotels = t.hotels.filter { !$0.place.isEmpty }
            if !hotels.isEmpty {
                Section("Hotels") {
                    ForEach(hotels) { h in
                        VStack(alignment: .leading, spacing: 6) {
                            placeLines(h.place)
                            if let rate = h.nightlyRate, rate > 0 {
                                fact("Per night", TourneyMoney.format(rate))
                            }
                            if !h.bookingCode.isBlank { fact("Code", h.bookingCode) }
                            if let by = h.bookBy { fact("Book by", by.formatted(date: .abbreviated, time: .omitted)) }
                            if !h.notes.isBlank { Text(h.notes).font(.caption).foregroundStyle(.secondary) }
                            HStack(spacing: 14) {
                                if let url = h.phoneURL {
                                    Link(destination: url) { Label("Call", systemImage: "phone.fill") }
                                }
                                if let url = TourneyLink.normalizedURL(h.link) {
                                    Link(destination: url) { Label("Book", systemImage: "safari") }
                                }
                            }
                            .font(.subheadline)
                            .buttonStyle(.borderless)
                            TourneyDirectionsRow(place: h.place)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            let links = t.links.filter { $0.url != nil }
            if !links.isEmpty {
                Section("Links") {
                    ForEach(links) { link in
                        Link(destination: link.url!) {
                            Label(link.displayTitle, systemImage: "safari")
                        }
                    }
                }
            }

            if !t.notes.isBlank {
                Section("Notes") { Text(t.notes).font(.subheadline) }
            }
        }
        .appSheet(item: $viewingSpot, chrome: .handle) { spot in
            TourneyMeetSpotViewer(spot: spot)
        }
        .appSheet(item: $viewingGame, chrome: .handle) { game in
            TourneyGameCardSheet(game: game, venue: t.venue, meetSpots: t.meetSpots)
        }
    }

    private func addPersonal() {
        guard let personal, !newItem.isBlank else { return }
        personal.add(newItem)
        newItem = ""
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).font(.subheadline).multilineTextAlignment(.trailing)
        }
    }

    private func placeLines(_ place: TourneyPlace) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !place.name.isEmpty { Text(place.name).font(.subheadline.weight(.semibold)) }
            if !place.address.isEmpty { Text(place.address).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct TourneyBulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
            configuration.title
        }
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

// MARK: - Directions

/// Apple Maps / Google Maps / Waze buttons for a place.
struct TourneyDirectionsRow: View {
    let place: TourneyPlace
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 8) {
            Text("Directions").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            ForEach(TourneyMapApp.allCases) { app in
                if let url = app.directionsURL(to: place) {
                    Button(app.title) { openURL(url) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }
}

/// The same choices in a small menu, for rows with no room for buttons.
struct TourneyDirectionsMenu: View {
    let place: TourneyPlace
    @Environment(\.openURL) private var openURL

    var body: some View {
        Menu {
            ForEach(TourneyMapApp.allCases) { app in
                if let url = app.directionsURL(to: place) {
                    Button(app.title) { openURL(url) }
                }
            }
        } label: {
            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                .font(.title2)
        }
        .accessibilityLabel("Directions")
    }
}

// MARK: - Scouting entry

struct TourneyProspectDetailView: View {
    @ObservedObject var store: TourneyStore
    let prospectId: String
    let onStartedTourney: (Tourney) -> Void

    @State private var draft: TourneyProspect? = nil
    @State private var saveTask: Task<Void, Never>? = nil

    var body: some View {
        Group {
            if draft != nil { form } else { ProgressView() }
        }
        .navigationTitle(draft?.displayName ?? "Scouting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        guard let p = draft else { return }
                        flushSave()
                        let t = p.makeTourney()
                        store.save(t)
                        onStartedTourney(t)
                    } label: {
                        Label("Start a Tourney Info Page", systemImage: "trophy")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
        .onAppear { if draft == nil { draft = store.prospect(id: prospectId) } }
        .onChange(of: store.prospects) { _, _ in
            if draft == nil { draft = store.prospect(id: prospectId) }
        }
        .onChange(of: draft) { old, new in
            guard old != nil, new != nil, old != new else { return }
            saveTask?.cancel()
            saveTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled else { return }
                flushSave()
            }
        }
        .onDisappear { flushSave() }
    }

    private func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        guard let draft, draft != store.prospect(id: prospectId) else { return }
        store.save(draft)
    }

    private var p: Binding<TourneyProspect> {
        Binding(get: { draft ?? TourneyProspect() }, set: { draft = $0 })
    }

    private var form: some View {
        Form {
            Section("Tourney") {
                TextField("Tourney name", text: p.name)
                    .font(.headline)
                    .accessibilityIdentifier("prospect.name")
                TextField("Organizer (e.g. USSSA, Triple Crown)", text: p.organizer)
                    .accessibilityIdentifier("prospect.organizer")
                TextField("Cost (e.g. $650 per team)", text: p.cost)
                    .accessibilityIdentifier("prospect.cost")
            }
            Section("When and Where") {
                TourneyOptionalDateRow(title: "Starts", value: Binding(
                    get: { p.wrappedValue.startDate },
                    set: { newValue in
                        p.wrappedValue.startDate = newValue
                        if let s = newValue, let e = p.wrappedValue.endDate, e < s { p.wrappedValue.endDate = s }
                        if newValue == nil { p.wrappedValue.endDate = nil }
                    }
                ), components: [.date], defaultDate: Date())
                if let start = p.wrappedValue.startDate {
                    TourneyOptionalDateRow(title: "Ends", value: Binding(
                        get: { p.wrappedValue.endDate },
                        set: { p.wrappedValue.endDate = $0.map { max(start, $0) } }
                    ), components: [.date], defaultDate: start)
                }
                TextField("City or park", text: p.location)
                TextField("Distance (e.g. 45 mi, 1 hr)", text: p.distance)
                    .accessibilityIdentifier("prospect.distance")
            }
            Section("Links") {
                ForEach(p.links) { $link in
                    TourneyLinkEditorRow(link: $link)
                }
                .onDelete { draft?.links.remove(atOffsets: $0) }
                Button {
                    draft?.links.append(TourneyLink(urlString: UIPasteboard.general.hasURLs ? (UIPasteboard.general.url?.absoluteString ?? "") : ""))
                } label: {
                    Label("Add Link", systemImage: "link")
                }
            }
            Section("Notes") {
                TextField("Age groups, format, deadlines, who's going", text: p.notes, axis: .vertical)
                    .lineLimit(3...10)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Place search

struct TourneyPlaceSearchSheet: View {
    let initialQuery: String
    let onPick: (TourneyPlace) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var message: String? = nil
    @State private var manualName = ""
    @State private var manualAddress = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Park, complex, hotel or address", text: $query)
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                            .autocorrectionDisabled()
                        if searching { ProgressView() }
                    }
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results, id: \.self) { item in
                            Button {
                                onPick(Self.place(from: item))
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Place").foregroundStyle(.primary)
                                    Text(Self.address(of: item)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section {
                    TextField("Name", text: $manualName)
                    TextField("Address", text: $manualAddress)
                    Button("Use Without a Map Pin") {
                        onPick(TourneyPlace(name: manualName.trimmingCharacters(in: .whitespaces),
                                            address: manualAddress.trimmingCharacters(in: .whitespaces)))
                        dismiss()
                    }
                    .disabled(manualName.trimmingCharacters(in: .whitespaces).isEmpty
                              && manualAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Or type it in")
                } footer: {
                    Text("Map apps will search for the name and address.")
                }
            }
            .navigationTitle("Find a Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Search") { Task { await search() } }
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
                }
            }
            .task {
                guard query.isEmpty else { return }
                query = initialQuery
                if !query.isEmpty { await search() }
            }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searching = true
        message = nil
        defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        do {
            results = try await MKLocalSearch(request: request).start().mapItems
            if results.isEmpty { message = "Nothing found. Try another name, or type it in below." }
        } catch {
            results = []
            message = "Couldn't search. Check your connection, or type it in below."
        }
    }

    static func address(of item: MKMapItem) -> String {
        let p = item.placemark
        let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let cityLine = [p.locality, p.administrativeArea].compactMap { $0 }.joined(separator: ", ")
        return [street, cityLine, p.postalCode ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static func place(from item: MKMapItem) -> TourneyPlace {
        let c = item.placemark.coordinate
        return TourneyPlace(name: item.name ?? "", address: address(of: item), latitude: c.latitude, longitude: c.longitude)
    }
}

// MARK: - Share as text (families without the app)

struct TourneyShareView: View {
    let tourney: Tourney

    @Environment(\.dismiss) private var dismiss
    @State private var options = TourneyShareOptions()
    @State private var includeMeetSpots = true
    @State private var shareItems: [Any]? = nil
    @State private var preparing = false

    private var text: String { TourneyShareText.text(for: tourney, options: options) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Include") {
                    Toggle("Dates & venue", isOn: $options.schedule)
                    Toggle("Games", isOn: $options.games)
                    Toggle("Game day", isOn: $options.gameDay)
                    if !tourney.meetSpots.isEmpty {
                        Toggle("Meet spot images", isOn: $includeMeetSpots)
                    }
                    Toggle("Uniforms", isOn: $options.uniforms)
                    Toggle("General info", isOn: $options.generalInfo)
                    Toggle("Gate fee", isOn: $options.gateFee)
                    Toggle("Tournament food", isOn: $options.food)
                    Toggle("Hotels", isOn: $options.hotels)
                    Toggle("Links", isOn: $options.links)
                    Toggle("Notes", isOn: $options.notes)
                }
                Section("Preview") {
                    Text(text)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Share as Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await prepare() }
                    } label: {
                        if preparing { ProgressView() } else { Text("Share").fontWeight(.semibold) }
                    }
                    .disabled(preparing)
                }
            }
            .appSheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } }), chrome: .none) {
                ShareSheet(items: shareItems ?? [])
            }
        }
    }

    private func prepare() async {
        preparing = true
        defer { preparing = false }
        var items: [Any] = [text]
        if includeMeetSpots {
            for spot in tourney.meetSpots {
                guard let base = try? await TourneySnapshotter.image(for: spot),
                      let image = TourneySnapshotter.renderShareImage(spot: spot, base: base) else { continue }
                items.append(image)
            }
        }
        shareItems = items
    }
}

// MARK: - UI test harness

/// `-UITestTourneys`: Home's Games row and Tourney Info on their own, in
/// memory, with one sample tourney and one scouting entry - nothing is
/// written to Firestore.
struct TourneyUITestHarness: View {
    @State private var showTourneys = ProcessInfo.processInfo.arguments.contains("-UITestTourneysOpen")
    /// Stands in for Home's new-game card: what Start Game would fill in.
    @State private var startedGame: String? = nil

    static var sample: Tourney {
        var t = Tourney()
        t.name = "Summer Slam"
        t.venue = TourneyPlace(name: "Cooperstown Dreams Park", address: "4550 State Highway 28, Milford, NY",
                               latitude: 42.6489, longitude: -74.9626)
        t.links = [TourneyLink(title: "Schedule", urlString: "example.com/schedule")]
        t.dailyUniforms = ["Whites", "Blacks"]
        let day1 = Calendar.current.startOfDay(for: t.startDate)
        t.games = [TourneyGame(time: day1.addingTimeInterval(9 * 3600), arriveAt: day1.addingTimeInterval(8 * 3600),
                               field: "7", opponent: "Hawks", result: "W 7-3",
                               ourTeamId: "t-Lightning", opponentTeamId: "t-Hawks"),
                   TourneyGame(time: day1.addingTimeInterval(13 * 3600), field: "Field 2", opponent: "Storm"),
                   TourneyGame(stage: .bracket, time: day1.addingTimeInterval(33 * 3600), field: "1", opponent: "Seed 4")]
        t.gateFee = true
        t.gateFeeNotes = "$10 per adult per day"
        t.cashOnly = true
        t.food = [TourneyFoodItem(family: "Garcia", food: "Sandwiches", done: true),
                  TourneyFoodItem(family: "Lee", food: "Fruit")]
        t.hotels = [TourneyHotel(place: TourneyPlace(name: "Lakeside Inn", address: "12 Main St"), nightlyRate: 139, nights: 2, bookingCode: "SLAM26")]
        t.meetSpots = [TourneyMeetSpot(title: "Day 1 warmups", centerLatitude: 42.6489, centerLongitude: -74.9626,
                                       latitudeDelta: 0.004, longitudeDelta: 0.004,
                                       marks: [TourneyMark(kind: .pin, x: 0.5, y: 0.45, text: "Meet here", colorHex: TourneyMark.palette[2]),
                                               TourneyMark(kind: .arrow, x: 0.2, y: 0.85, x2: 0.45, y2: 0.52),
                                               TourneyMark(kind: .bullets, x: 0.7, y: 0.75, text: "8:00 warmups\nBring water")])]
        return t
    }

    static var teams: [Team] {
        ["Lightning", "Hawks", "Storm"].map { name in
            var team = Team(name: name, createdByUid: "uitest")
            team.id = "t-\(name)"
            return team
        }
    }

    static var sampleProspect: TourneyProspect {
        var p = TourneyProspect(name: "Fall Classic")
        p.organizer = "USSSA"
        p.cost = "$595 per team"
        p.distance = "45 mi"
        return p
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                HStack {
                    Text("Games").font(.headline)
                    Spacer()
                    Image(systemName: "plus.circle.fill").font(.title2).padding(.trailing, 10)
                    Image(systemName: "calendar").font(.title2).padding(.trailing, 10)
                    TourneyInfoButton { showTourneys = true }
                }
                .padding(.horizontal)
                if let startedGame {
                    Text(startedGame)
                        .padding()
                        .accessibilityIdentifier("harness.startedGame")
                }
                Spacer()
            }
            .padding(.top)
        }
        .appSheet(isPresented: $showTourneys, chrome: .handle) {
            let sample = Self.sample
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-UITestTourneysSpot") {
                TourneyMeetSpotEditor(spot: sample.meetSpots[0]) { _ in }
                    .tint(.primary)
            } else if args.contains("-UITestTourneysGame") {
                TourneyGameEditorSheet(game: sample.games[0], isNew: false, onSave: { _ in }, onDelete: { _ in })
                    .environment(\.tourneyTeams, TourneyTeamContext(teams: Self.teams) { _, _, done in done(nil) })
                    .environment(\.tourneyStartGame) { _ in }
                    .tint(.primary)
            } else if args.contains("-UITestTourneysRead") {
                NavigationStack { TourneyReadView(tourney: sample) }
                    .tint(.primary)
                    .environment(\.tourneyStartGame) { game in
                        startedGame = "New game: \(game.opponent)"
                        showTourneys = false
                    }
            } else if args.contains("-UITestTeamPage") {
                // A team page in memory: the Reds' tourney; editable with
                // -UITestTeamPageEdit (a Scheduler), read-only otherwise.
                TeamPageHarness(sample: sample, canEdit: args.contains("-UITestTeamPageEdit"))
            } else if args.contains("-UITestTourneysCalendar") {
                // Home's calendar with the sample's games scheduled (2026-11-24).
                GamesCalendarView(games: [], title: { $0.opponent }, onOpen: { _ in },
                                  scheduled: TeamSchedule.entries(tourneys: [{ var t = sample; t.teamId = "t-Reds"; return t }()],
                                                                  singles: []))
            } else if args.contains("-UITestTourneysFamily") {
                // A family on the Reds: the Reds' tourney, read-only.
                TourneysView(inMemory: true, seed: [{ var t = sample; t.teamId = "t-Reds"; return t }()],
                             seedTeams: [.init(id: "t-Reds", name: "Reds 16U B", canEdit: false)])
            } else {
                TourneysView(inMemory: true, seed: [sample], seedProspects: [Self.sampleProspect],
                             openId: args.contains("-UITestTourneysDetail") ? sample.id : nil,
                             tab: args.contains("-UITestTourneysScouting") ? .scouting : .ours,
                             onStartGame: { game in
                                 let seed = game.newGameSeed(myTeamIds: Set(Self.teams.compactMap(\.id)))
                                 startedGame = "New game: \(seed.opponentName) · ours \(seed.ourTeamId ?? "-") · opp \(seed.opponentTeamId ?? "-")"
                                 showTourneys = false
                             },
                             teamContext: TourneyTeamContext(teams: Self.teams) { name, _, done in
                                 var team = Team(name: name, createdByUid: "uitest")
                                 team.id = "t-\(name)"
                                 done(team)
                             },
                             // `-UITestTourneysTeams`: the coach schedules for the Reds.
                             seedTeams: args.contains("-UITestTourneysTeams")
                                 ? [.init(id: "t-Reds", name: "Reds 16U B", canEdit: true)] : [])
            }
        }
    }
}


/// `-UITestTeamPage`: the Reds' team page in memory.
private struct TeamPageHarness: View {
    let sample: Tourney
    let canEdit: Bool
    @StateObject private var store = TourneyStore(inMemory: true)

    var body: some View {
        NavigationStack {
            TeamPageView(store: store, teamId: "t-Reds", showsTeamExtras: false)
        }
        .tint(.primary)
        .onAppear {
            store.startTeams([.init(id: "t-Reds", name: "Reds 16U B", canEdit: canEdit)])
            var t = sample
            t.teamId = "t-Reds"
            store.save(t)
        }
    }
}
