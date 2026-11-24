//
//  TeamScheduleViews.swift
//  PitchMark
//
//  The team page (2026-11-24): the Team Schedule (every tourney game and
//  single game, upcoming by date, past folded away), Add Game for the coach
//  and Schedulers, the team's sponsors, and - for families - Team Trading
//  Cards. Opened from Tourney Info → Your Teams, and from the coach's team
//  roster. Rules and model: TeamSchedule.swift.
//
//  Every sheet hangs off the page's root (a sheet on a List section is
//  copied onto every row - the Make a Trading Card bug).
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

/// A team's page for anyone on it.
struct TeamPageView: View {
    @ObservedObject var store: TourneyStore
    let teamId: String
    /// The coach's roster already has sponsors and trading cards; their
    /// page shows only the schedule.
    var showsTeamExtras: Bool = true

    @EnvironmentObject private var authManager: AuthManager
    @State private var team: Team? = nil
    @State private var players: [TeamPlayer] = []
    @State private var showPast = false
    @State private var editing: TeamScheduledGame? = nil
    @State private var isNewGame = false
    @State private var viewing: TeamSchedule.Entry? = nil
    @State private var showLeave = false
    @StateObject private var extras = RosterExtrasPresentation()
    @Environment(\.dismiss) private var dismiss

    private var canEdit: Bool { store.canEditTeam(teamId) }
    private var teamName: String { store.teamName(teamId) ?? team?.nameWithClass ?? "Team" }

    var body: some View {
        let parts = TeamSchedule.split(store.schedule(teamId: teamId), now: Date())
        List {
            Section {
                if canEdit {
                    Button {
                        isNewGame = true
                        editing = TeamScheduledGame(teamId: teamId, time: TeamPageView.nextHour())
                    } label: {
                        Label("Add Game", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("teamSchedule.addGame")
                }
                if parts.upcoming.isEmpty {
                    Text("No games coming up.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(parts.upcoming) { entry in
                    TeamScheduleRow(entry: entry) { open(entry) }
                }
            } header: {
                Text("Team Schedule")
            } footer: {
                Text(canEdit
                     ? "Games here and in your team's tourneys. Everyone on the team sees changes on their own."
                     : "Kept up to date by your coach - every tourney and game.")
            }
            if !parts.past.isEmpty {
                Section {
                    DisclosureGroup("Past games (\(parts.past.count))", isExpanded: $showPast) {
                        ForEach(parts.past) { entry in
                            TeamScheduleRow(entry: entry) { open(entry) }
                        }
                    }
                }
            }
            if showsTeamExtras, let team {
                TeamSponsorSection(team: team, isTeamOwner: false, presentation: extras)
                TeamTradingCardsSection(team: team, presentation: extras)
                // A Scheduler or Family leaves from here (the creator
                // can't leave their own team).
                if team.createdByUid != authManager.user?.uid {
                    Section {
                        Button("Leave Team", role: .destructive) { showLeave = true }
                            .accessibilityIdentifier("teamPage.leave")
                    }
                }
            }
        }
        .navigationTitle(teamName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: teamId) { loadTeam() }
        .appSheet(item: $editing, chrome: .handle) { game in
            TeamScheduledGameEditor(game: game, isNew: isNewGame,
                                    onSave: { store.saveTeamGame($0) },
                                    onDelete: { store.deleteTeamGame($0) })
        }
        .appSheet(item: $viewing) { entry in
            TourneyGameCardSheet(game: entry.game, venue: entry.venue, meetSpots: [])
        }
        .modifier(OptionalRosterExtras(enabled: showsTeamExtras, presentation: extras, team: team, players: players))
        .appConfirmationDialog(
            isPresented: $showLeave,
            title: "Leave \(teamName)?",
            message: "You stop seeing the team's schedule. The coach can invite you again.",
            primaryTitle: "Leave Team",
            primaryRole: .destructive,
            primaryAction: {
                authManager.leaveTeam(teamId: teamId) { _ in
                    DispatchQueue.main.async {
                        store.startTeams(store.teams.filter { $0.id != teamId })
                        dismiss()
                    }
                }
            },
            secondaryTitle: "Cancel"
        )
    }

    /// A single game opens its editor for the coach and Schedulers; any
    /// other game opens its card (when, where, directions, Track).
    private func open(_ entry: TeamSchedule.Entry) {
        if entry.source == .single, canEdit, let single = store.teamGames.first(where: { $0.id == entry.id }) {
            isNewGame = false
            editing = single
        } else {
            viewing = entry
        }
    }

    private func loadTeam() {
        guard showsTeamExtras else { return }
        Firestore.firestore().collection("teams").document(teamId).getDocument { snapshot, _ in
            guard let loaded = try? snapshot?.data(as: Team.self) else { return }
            DispatchQueue.main.async {
                team = loaded
                extras.start(teamId: teamId, uid: authManager.user?.uid)
            }
        }
        authManager.loadTeamPlayers(teamId: teamId) { loaded in
            DispatchQueue.main.async { players = loaded.filter { $0.archivedAt == nil } }
        }
    }

    static func nextHour(from now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let hour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return hour.addingTimeInterval(3600)
    }
}

/// The roster's sponsor and trading card sheets, only when the page shows
/// those sections and the team has loaded.
private struct OptionalRosterExtras: ViewModifier {
    let enabled: Bool
    @ObservedObject var presentation: RosterExtrasPresentation
    let team: Team?
    let players: [TeamPlayer]

    func body(content: Content) -> some View {
        if enabled, let team {
            content.modifier(RosterExtrasSheets(presentation: presentation, team: team, players: players))
        } else {
            content
        }
    }
}

/// One game on the Team Schedule.
struct TeamScheduleRow: View {
    let entry: TeamSchedule.Entry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.time, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.time, format: .dateTime.hour().minute())
                        .font(.subheadline.weight(.semibold))
                }
                .frame(width: 84, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.subheadline)
                        .foregroundStyle(entry.canceled ? .secondary : .primary)
                        .strikethrough(entry.canceled)
                    HStack(spacing: 6) {
                        Text(entry.label)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.secondarySystemFill), in: Capsule())
                        if entry.canceled {
                            Text("Canceled")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.red)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("teamSchedule.row.\(entry.title)")
    }
}

/// Adds or edits a team's single game: Game, Friendly or Scrimmage.
struct TeamScheduledGameEditor: View {
    let isNew: Bool
    let onSave: (TeamScheduledGame) -> Void
    let onDelete: (TeamScheduledGame) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var game: TeamScheduledGame
    @State private var searchingPlace = false

    init(game: TeamScheduledGame, isNew: Bool,
         onSave: @escaping (TeamScheduledGame) -> Void, onDelete: @escaping (TeamScheduledGame) -> Void) {
        _game = State(initialValue: game)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $game.kind) {
                    ForEach(GameKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("teamGame.kind")
                DatePicker("Game time", selection: $game.time, displayedComponents: [.date, .hourAndMinute])
                TourneyOptionalDateRow(title: "Arrive at", value: $game.arriveAt,
                                       components: [.hourAndMinute],
                                       defaultDate: game.time.addingTimeInterval(-3600))
                TextField("Opponent", text: $game.opponent)
                    .accessibilityIdentifier("teamGame.opponent")
                Section("Where") {
                    Button {
                        searchingPlace = true
                    } label: {
                        Label(game.venue.isEmpty ? "Find the field or park" : (game.venue.name.isEmpty ? game.venue.address : game.venue.name),
                              systemImage: "mappin.and.ellipse")
                    }
                    HStack {
                        Text("Field").foregroundStyle(.secondary)
                        TextField("Number or name", text: $game.field)
                    }
                }
                Section("Notes") {
                    TextField("Uniform, what to bring, anything else", text: $game.notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    Toggle("Canceled", isOn: $game.canceled)
                        .accessibilityIdentifier("teamGame.canceled")
                } footer: {
                    Text("A canceled game stays on the schedule, marked Canceled, so families see it.")
                }
                if !isNew {
                    Section {
                        Button("Remove Game", role: .destructive) {
                            onDelete(game)
                            dismiss()
                        }
                    } footer: {
                        Text("For a game added by mistake. If it was called off, mark it Canceled instead.")
                    }
                }
            }
            .navigationTitle(isNew ? "Add Game" : game.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(game)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("teamGame.save")
                }
            }
        }
        .presentationDetents([.large])
        .appSheet(isPresented: $searchingPlace, chrome: .handle) {
            TourneyPlaceSearchSheet(initialQuery: game.venue.name) { place in
                game.venue = place
            }
        }
    }
}

/// The Team Schedule from the coach's roster, with its own store.
struct TeamScheduleHost: View {
    let team: Team
    let canEdit: Bool

    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var store = TourneyStore()

    var body: some View {
        TeamPageView(store: store, teamId: team.id ?? "", showsTeamExtras: false)
            .task(id: authManager.user?.uid) {
                store.start(uid: authManager.user?.uid)
                if let id = team.id {
                    store.startTeams([.init(id: id, name: team.nameWithClass, canEdit: canEdit)])
                }
            }
    }
}

/// Home's Games Calendar with scheduled games (2026-11-24): this user's
/// own tourneys and every team they're on, minus any already tracked.
/// Track on a scheduled game's card goes back to Home's new-game card.
struct HomeGamesCalendar: View {
    let games: [Game]
    let title: (Game) -> String
    let onOpen: (Game) -> Void
    let onTrack: (TourneyGame) -> Void

    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var store = TourneyStore()

    var body: some View {
        GamesCalendarView(games: games, title: title, onOpen: onOpen,
                          scheduled: TeamSchedule.calendarEntries(store.allScheduled, trackedGames: games))
            .environment(\.tourneyStartGame, onTrack)
            .task(id: authManager.user?.uid) {
                guard let uid = authManager.user?.uid else { return }
                store.start(uid: uid)
                authManager.loadMyTeams(includeJoined: true) { entries, _ in
                    store.startTeams(entries.compactMap { entry in
                        guard let id = entry.team.id else { return nil }
                        return .init(id: id, name: entry.team.nameWithClass,
                                     canEdit: TeamAccessRules.schedules(team: entry.team, membership: entry.membership, uid: uid))
                    })
                }
            }
    }
}
