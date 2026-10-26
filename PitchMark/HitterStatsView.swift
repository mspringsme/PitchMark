//
//  HitterStatsView.swift
//  PitchMark
//
//  The "will heatmaps persist" answer: a Hitter's full pitch-location
//  history across every game/team it's been linked from, backed by the new
//  /hitters/{id}/pitchEvents mirror (Hitter.swift, wired up from
//  PitchTrackerView's batterRosterPickerButton selection).
//
//  Deliberately simpler than PitcherStatsSheetView: no pitch-type/hit-spot/
//  swing-K breakdowns (pitching-specific concepts that don't translate to
//  hitting), and a single-source load rather than PitcherStatsSheetView's
//  three-way game/live/pitcher merge - that merge exists to cover years of
//  legacy pre-mirror pitcher data and in-flight live events; /hitters has
//  no such history (the collection is new), so reading it alone is already
//  complete. A pitch thrown in the last instant of an active live session
//  may lag a moment before showing here - acceptable since this view is
//  reached from the roster screen, not from inside an active tracking
//  session.
//

import SwiftUI

struct HitterStatsView: View {
    enum DateRangeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case last7 = "Last 7"
        case last30 = "Last 30"
        case last90 = "Last 90"

        var id: String { rawValue }
    }

    let hitter: Hitter
    /// Every hitting record of the same person - more than one once two
    /// entries with tracked history were linked. Read as one history.
    var combinedHitterIds: [String] = []
    let games: [Game]
    let teams: [Team]

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var allEvents: [PitchEvent] = []
    @State private var isLoading = false
    @State private var dateFilter: DateRangeFilter = .all
    @State private var selectedTeamIds: Set<String> = []

    private var dateRange: ClosedRange<Date>? {
        switch dateFilter {
        case .all: return nil
        case .last7: return (Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date())...Date()
        case .last30: return (Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date())...Date()
        case .last90: return (Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date())...Date()
        }
    }

    private var gameIdsForSelectedTeams: Set<String>? {
        guard !selectedTeamIds.isEmpty else { return nil }
        return Set(games.filter { TeamFilterChips.game($0, belongsTo: selectedTeamIds) }.compactMap { $0.id })
    }

    private var filteredEvents: [PitchEvent] {
        var result = allEvents
        if let range = dateRange {
            result = result.filter { range.contains($0.timestamp) }
        }
        if let gameIds = gameIdsForSelectedTeams {
            result = result.filter { event in
                guard let gid = event.gameId, !gid.isEmpty else { return false }
                return gameIds.contains(gid)
            }
        }
        return result
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(hitter.name)
                            .font(.title2.weight(.semibold))
                        Spacer()
                    }
                    .padding(.horizontal)

                    Picker("Date Range", selection: $dateFilter) {
                        ForEach(DateRangeFilter.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if !teams.isEmpty {
                        TeamFilterChips(teams: teams, selectedTeamIds: $selectedTeamIds)
                    }

                    Text("\(filteredEvents.count) pitch\(filteredEvents.count == 1 ? "" : "es") tracked")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if filteredEvents.isEmpty {
                        Text("No pitches tracked yet for this range.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    } else {
                        StrikeZoneHeatmapView(events: filteredEvents)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("Hitting Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { loadEvents() }
        }
    }

    private func loadEvents() {
        guard let hitterId = hitter.id else { return }
        let hitterIds = combinedHitterIds.contains(hitterId) ? combinedHitterIds : [hitterId]
        isLoading = true
        var collected: [PitchEvent] = []
        let group = DispatchGroup()
        for id in hitterIds {
            group.enter()
            authManager.loadHitterEvents(hitterId: id) { events in
                DispatchQueue.main.async {
                    collected.append(contentsOf: events)
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            self.allEvents = collected.sorted { $0.timestamp < $1.timestamp }
            self.isLoading = false
        }
    }
}

// MARK: - Team filter chips

/// The Teams row on both stats screens (this one and PitcherStatsSheetView).
/// "All" first and selected on open - the whole career across every team the
/// player is linked on. Tapping a team narrows to just that team; tapping
/// more adds them; "All" goes back. Each chip carries its season, since a
/// linked player's teams are often the same name a season apart.
struct TeamFilterChips: View {
    let teams: [Team]
    /// Empty means All.
    @Binding var selectedTeamIds: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Teams")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", isSelected: selectedTeamIds.isEmpty) {
                        selectedTeamIds.removeAll()
                    }
                    ForEach(teams.sorted(by: Team.listOrder), id: \.id) { team in
                        let id = team.id ?? ""
                        let isSelected = selectedTeamIds.contains(id)
                        chip(Self.label(for: team), isSelected: isSelected) {
                            guard !id.isEmpty else { return }
                            if isSelected {
                                selectedTeamIds.remove(id)
                            } else {
                                selectedTeamIds.insert(id)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(Capsule().fill(isSelected ? Color.pitchMarkActiveGray : Color(.systemGray6)))
    }

    /// "Bombers · Fall '26" / "Bombers · Fall–Winter '26–'27"; just the name
    /// for a team with no season set.
    static func label(for team: Team) -> String {
        guard let designation = team.designation else { return team.name }
        return "\(team.name) · \(designation.seasonText) \(designation.yearText)"
    }

    /// A game counts for a team whichever side that team was on - a player
    /// linked on an opponent's roster has their games under `awayTeamId`.
    static func game(_ game: Game, belongsTo teamIds: Set<String>) -> Bool {
        if let id = game.teamId, teamIds.contains(id) { return true }
        if let id = game.awayTeamId, teamIds.contains(id) { return true }
        return false
    }
}
