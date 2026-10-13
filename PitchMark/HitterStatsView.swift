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
        return Set(games.filter { selectedTeamIds.contains($0.teamId ?? "") }.compactMap { $0.id })
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
                        teamFilterRow
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

    private var teamFilterRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Teams")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("All Teams") {
                    selectedTeamIds.removeAll()
                }
                .font(.caption)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(teams, id: \.id) { team in
                        let isSelected = selectedTeamIds.contains(team.id ?? "")
                        Button(team.name) {
                            guard let tid = team.id else { return }
                            if isSelected {
                                selectedTeamIds.remove(tid)
                            } else {
                                selectedTeamIds.insert(tid)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background(Capsule().fill(isSelected ? Color.pitchMarkActiveGray : Color(.systemGray6)))
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func loadEvents() {
        guard let hitterId = hitter.id else { return }
        isLoading = true
        authManager.loadHitterEvents(hitterId: hitterId) { events in
            self.allEvents = events
            self.isLoading = false
        }
    }
}
