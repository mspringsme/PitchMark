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
    /// Set when opened from inside a game: adds a This Game / All Games
    /// switch, starting on This Game.
    var focusGameId: String? = nil

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var allEvents: [PitchEvent] = []
    /// Steals / caught stealing / pickoffs (RunnerEventStore), filtered the
    /// same way as the pitches.
    @State private var allRunnerEvents: [RunnerEvent] = []
    @State private var isLoading = false
    /// Every pitch of the games this player's teams played (FieldingStatsViews),
    /// for the Fielding section - fielding is on the other team's pitches.
    @State private var gameEvents: [PitchEvent] = []
    @State private var isLoadingFielding = false
    @State private var dateFilter: DateRangeFilter = .all
    @State private var selectedTeamIds: Set<String> = []
    @State private var showsFocusGameOnly = true

    private var isFocusedOnGame: Bool {
        focusGameId != nil && showsFocusGameOnly
    }

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

    /// Archived games this viewer chose to remove from stats. Events from
    /// games not in `games` (another coach's) are left as they were.
    private var excludedGameIds: Set<String> {
        Set(games.filter { !authManager.gameCountsInStats($0) }.compactMap { $0.id })
    }

    private var statsFilter: StatsEventFilter {
        StatsEventFilter(
            focusGameId: isFocusedOnGame ? focusGameId : nil,
            excludedGameIds: excludedGameIds,
            dateRange: dateRange,
            teamGameIds: gameIdsForSelectedTeams
        )
    }

    private var filteredEvents: [PitchEvent] {
        statsFilter.pitches(allEvents)
    }

    private var allHitterIds: Set<String> {
        guard let hitterId = hitter.id else { return [] }
        return Set(combinedHitterIds.contains(hitterId) ? combinedHitterIds : [hitterId])
    }

    private var fieldingLedger: FieldingLedger {
        FieldingLedger(events: statsFilter.pitches(gameEvents))
    }

    private var statLine: HittingStatLine {
        var line = HittingStatLine(events: filteredEvents, runnerEvents: statsFilter.runnerEvents(allRunnerEvents))
        line.recordRunsScored(onPitches: statsFilter.pitches(gameEvents), hitterIds: allHitterIds)
        return line
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

                    if focusGameId != nil {
                        Picker("Scope", selection: $showsFocusGameOnly) {
                            Text("This Game").tag(true)
                            Text("All Games").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }

                    if !isFocusedOnGame {
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
                    }

                    StatsSectionHeader(title: "Hitting")

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
                        statLineGrid(statLine)
                            .padding(.horizontal)
                        StrikeZoneHeatmapView(events: filteredEvents)
                            .padding(.horizontal)
                    }

                    StatsSectionHeader(title: "Fielding")
                        .padding(.top, 8)

                    PlayerFieldingSection(ledger: fieldingLedger, hitterIds: allHitterIds, isLoading: isLoadingFielding)
                        .padding(.horizontal)
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("Player Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                loadEvents()
                loadFieldingEvents()
            }
        }
    }

    private func statLineGrid(_ line: HittingStatLine) -> some View {
        let rates: [(String, String)] = [
            ("AVG", HittingStatLine.formatRate(line.average)),
            ("OBP", HittingStatLine.formatRate(line.onBase)),
            ("SLG", HittingStatLine.formatRate(line.slugging))
        ]
        let counts: [(String, Int)] = [
            ("PA", line.plateAppearances), ("AB", line.atBats), ("R", line.runs), ("H", line.hits),
            ("1B", line.singles), ("2B", line.doubles), ("3B", line.triples), ("HR", line.homeRuns),
            ("RBI", line.runsBattedIn),
            ("BB", line.walks), ("HBP", line.hitByPitch), ("K", line.strikeouts),
            ("ROE", line.reachedOnError),
            ("SB", line.stolenBases), ("CS", line.caughtStealing), ("PO", line.pickedOff)
        ]
        let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]
        return VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(rates, id: \.0) { label, value in
                    statTile(label: label, value: value, emphasized: true)
                }
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(counts, id: \.0) { label, value in
                    statTile(label: label, value: "\(value)", emphasized: false)
                }
            }
            if line.unspecifiedHits > 0 {
                Text("SLG needs every hit marked 1B, 2B, 3B or HR - \(line.unspecifiedHits) \(line.unspecifiedHits == 1 ? "was" : "were") saved as just \"Hit\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statTile(label: String, value: String, emphasized: Bool) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(emphasized ? .title3.weight(.bold) : .headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// The games of this player's teams (all games when none are known).
    private func loadFieldingEvents() {
        let teamIds = Set(teams.compactMap(\.id))
        let relevant = teamIds.isEmpty ? games : games.filter { TeamFilterChips.game($0, belongsTo: teamIds) }
        isLoadingFielding = true
        FieldingEventsLoader.load(games: relevant, authManager: authManager) { events in
            gameEvents = events
            isLoadingFielding = false
        }
    }

    private func loadEvents() {
        guard let hitterId = hitter.id else { return }
        let hitterIds = combinedHitterIds.contains(hitterId) ? combinedHitterIds : [hitterId]
        isLoading = true
        var collected: [PitchEvent] = []
        let group = DispatchGroup()
        group.enter()
        RunnerEventStore.loadForHitters(hitterIds) { events in
            self.allRunnerEvents = events
            group.leave()
        }
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
