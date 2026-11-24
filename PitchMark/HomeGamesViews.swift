//
//  HomeGamesViews.swift
//  PitchMark
//
//  Home's Games screens (2026-11-24): the New Game form's extra fields and
//  an upcoming game's card. Rules: HomeGames.swift. Kept out of
//  SettingsView, whose type is already as deep as it can safely go.
//

import SwiftUI

/// Arrive by, where it's played, field and notes on the New Game form.
struct NewGameDetailsFields: View {
    @Binding var details: NewGameDetails
    let gameDate: Date
    @State private var searchingPlace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TourneyOptionalDateRow(title: "Arrive by", value: $details.arriveAt,
                                   components: [.hourAndMinute], defaultDate: gameDate.addingTimeInterval(-3600))
            Button {
                searchingPlace = true
            } label: {
                Label(details.venue.isEmpty ? "Where (field or park)"
                      : (details.venue.name.isEmpty ? details.venue.address : details.venue.name),
                      systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("newGame.where")
            HStack {
                Text("Field").foregroundStyle(.secondary)
                TextField("Number or name", text: $details.field)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("newGame.field")
            }
            TextField("Notes - uniform, what to bring", text: $details.notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .accessibilityIdentifier("newGame.notes")
        }
        .appSheet(isPresented: $searchingPlace, chrome: .handle) {
            TourneyPlaceSearchSheet(initialQuery: details.venue.name) { place in
                details.venue = place
            }
        }
    }
}

/// An upcoming game's card: when, arrive by, where, field, notes, and
/// Start Tracking / Edit / the tourney's page.
struct UpcomingGameCard: View {
    let title: String
    let date: Date
    let kindOrTourney: String?
    let canceled: Bool
    let details: NewGameDetails
    var onStart: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onOpenTourney: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if canceled {
                    Section {
                        Label("This game is canceled", systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                            .font(.headline)
                    }
                }
                Section {
                    row("When", date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))
                    if let arrive = details.arriveAt {
                        row("Arrive", arrive.formatted(date: .omitted, time: .shortened))
                    }
                    if let kindOrTourney { row(onOpenTourney == nil ? "Type" : "Tournament", kindOrTourney) }
                    let field = details.field.trimmingCharacters(in: .whitespaces)
                    if !field.isEmpty { row("Field", field.lowercased().hasPrefix("field") ? field : "Field \(field)") }
                    let notes = details.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !notes.isEmpty { row("Notes", notes) }
                }
                if !details.venue.isEmpty {
                    Section("Directions to \(details.venue.name.isEmpty ? "the field" : details.venue.name)") {
                        TourneyDirectionsRow(place: details.venue)
                    }
                }
                Section {
                    if let onStart, !canceled {
                        Button {
                            dismiss()
                            onStart()
                        } label: {
                            Label("Start Tracking", systemImage: "play.circle.fill")
                                .font(.headline)
                        }
                        .accessibilityIdentifier("upcoming.start")
                    }
                    if let onEdit {
                        Button {
                            dismiss()
                            onEdit()
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .accessibilityIdentifier("upcoming.edit")
                    }
                    if let onOpenTourney {
                        Button {
                            dismiss()
                            onOpenTourney()
                        } label: {
                            Label("Open Tournament", systemImage: "trophy")
                        }
                        .accessibilityIdentifier("upcoming.tourney")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}

/// Games' Tournaments button (replaces the Tourney Info button).
struct TournamentsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trophy")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 36)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tournaments")
        .accessibilityIdentifier("games.tournaments")
    }
}

/// A joined team's page, opened from Home's Teams list.
struct TeamPageTarget: Identifiable {
    let id: String
}

/// Home's Games sheets and dialog, in one modifier so SettingsView's type
/// doesn't grow (CLAUDE.md, Home's depth limit).
struct HomeUpcomingSheets: ViewModifier {
    @Binding var upcomingItem: HomeGameList.Item?
    @Binding var editingTeamGame: TeamScheduledGame?
    @Binding var editingUpcomingGame: Game?
    @Binding var teamPageTarget: TeamPageTarget?
    @Binding var showJoinTeam: Bool
    @Binding var showStartStatsQuestion: Bool
    let startingKind: GameKind
    @ObservedObject var store: TourneyStore
    let card: (HomeGameList.Item) -> AnyView
    let onSaveUpcoming: (Game) -> Void
    let onStatsAnswer: (Bool) -> Void
    let onJoined: () -> Void

    func body(content: Content) -> some View {
        content
            .appSheet(item: $upcomingItem) { item in card(item) }
            .appSheet(item: $editingTeamGame, chrome: .handle) { game in
                TeamScheduledGameEditor(game: game, isNew: false,
                                        onSave: { store.saveTeamGame($0) },
                                        onDelete: { store.deleteTeamGame($0) })
            }
            .appSheet(item: $editingUpcomingGame, chrome: .handle) { game in
                UpcomingGameEditor(game: game, onSave: onSaveUpcoming)
            }
            .appSheet(item: $teamPageTarget) { target in
                NavigationStack { TeamPageView(store: store, teamId: target.id) }
            }
            .appSheet(isPresented: $showJoinTeam, chrome: .handle) {
                JoinTeamSheet(onJoined: onJoined)
            }
            .gameStatsQuestionDialog(isPresented: $showStartStatsQuestion, kind: startingKind, onAnswer: onStatsAnswer)
    }
}

/// Edits an upcoming game from its card: opponent, time, type and the
/// details. Teams stay as they are (the tracker owns the lineup).
struct UpcomingGameEditor: View {
    let onSave: (Game) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var game: Game
    @State private var kind: GameKind
    @State private var details: NewGameDetails

    init(game: Game, onSave: @escaping (Game) -> Void) {
        self.onSave = onSave
        _game = State(initialValue: game)
        _kind = State(initialValue: game.kind ?? .game)
        _details = State(initialValue: NewGamePlan.details(of: game))
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    ForEach(GameKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("Opponent", text: $game.opponent)
                DatePicker("Game time", selection: $game.date, displayedComponents: [.date, .hourAndMinute])
                NewGameDetailsFields(details: $details, gameDate: game.date)
            }
            .navigationTitle("Edit Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = game
                        saved.kind = kind == .game ? nil : kind
                        let built = NewGamePlan.make(opponent: saved.opponent, date: saved.date, ourTeamId: nil,
                                                     opponentTeamId: nil, kind: kind, trackingMode: .coach,
                                                     details: details, schedulesForTeam: false).game
                        saved.arriveAt = built.arriveAt
                        saved.venueName = built.venueName
                        saved.venueAddress = built.venueAddress
                        saved.venueLatitude = built.venueLatitude
                        saved.venueLongitude = built.venueLongitude
                        saved.field = built.field
                        saved.notes = built.notes
                        onSave(saved)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(game.opponent.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
