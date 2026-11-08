//
//  TeamBattingStats.swift
//  PitchMark
//
//  A team's batting (2026-11-05): every roster player's hitting line plus
//  the team's, from the games this account tracked - the batting sibling
//  of TeamFieldingStatsView, opened from the roster screen.
//
//  Read from the games (not each player's /hitters record) so the team
//  line includes batters who were only a jersey number, and so a player's
//  line is only what they did for this team.
//

import SwiftUI

enum TeamBatting {
    /// The team batting on `event`: whoever wasn't fielding. nil when the
    /// pitch has no fielding team or the game isn't known.
    static func battingTeamId(of event: PitchEvent, gamesById: [String: Game]) -> String? {
        guard let fielding = event.fieldingTeamId, let gameId = event.gameId, let game = gamesById[gameId]
        else { return nil }
        if fielding == game.teamId { return game.awayTeamId }
        if fielding == game.awayTeamId { return game.teamId }
        return nil
    }

    /// `teamId`'s at-bats in `events`. A pitch saved before the fielding
    /// team was stamped is placed by its batter: a linked roster player
    /// means this team was up.
    static func battingEvents(_ events: [PitchEvent], teamId: String, games: [Game],
                              rosterHitterIds: Set<String>) -> [PitchEvent] {
        let gamesById = Dictionary(games.compactMap { game in game.id.map { ($0, game) } },
                                   uniquingKeysWith: { first, _ in first })
        return events.filter { event in
            if event.fieldingTeamId != nil {
                return battingTeamId(of: event, gamesById: gamesById) == teamId
            }
            guard let hitterId = event.hitterId else { return false }
            return rosterHitterIds.contains(hitterId)
        }
    }

    /// Running from `games` only - a /hitters record also holds the
    /// player's other teams'.
    static func runnerEvents(_ events: [RunnerEvent], games: [Game]) -> [RunnerEvent] {
        let gameIds = Set(games.compactMap(\.id))
        return events.filter { $0.gameId.map(gameIds.contains) ?? false }
    }

    /// One player's line for this team: their pitches, their running in
    /// these games, and the runs they scored on teammates' pitches.
    static func playerLine(hitterId: String, battingEvents: [PitchEvent], runnerEvents: [RunnerEvent]) -> HittingStatLine {
        var line = HittingStatLine(events: battingEvents.filter { $0.hitterId == hitterId },
                                   runnerEvents: runnerEvents.filter { $0.hitterId == hitterId })
        line.recordRunsScored(onPitches: battingEvents, hitterIds: [hitterId])
        return line
    }

    /// The whole team: every at-bat (jersey-only batters too) and every run
    /// that scored on those pitches, whoever was running.
    static func teamLine(battingEvents: [PitchEvent], runnerEvents: [RunnerEvent]) -> HittingStatLine {
        var line = HittingStatLine(events: battingEvents, runnerEvents: runnerEvents)
        for event in battingEvents {
            line.runs += event.play?.runnerMoves.filter { $0.to == Base.scored }.count ?? 0
        }
        return line
    }
}

/// The table's two column sets - seven columns fit a phone.
enum BattingColumns: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case more = "More"

    var id: String { rawValue }

    var headers: [String] {
        switch self {
        case .standard: return ["AB", "R", "H", "RBI", "BB", "K", "AVG"]
        case .more: return ["2B", "3B", "HR", "HBP", "SB", "OBP", "SLG"]
        }
    }

    func values(_ line: HittingStatLine) -> [String] {
        switch self {
        case .standard:
            return ["\(line.atBats)", "\(line.runs)", "\(line.hits)", "\(line.runsBattedIn)",
                    "\(line.walks)", "\(line.strikeouts)", HittingStatLine.formatRate(line.average)]
        case .more:
            return ["\(line.doubles)", "\(line.triples)", "\(line.homeRuns)", "\(line.hitByPitch)",
                    "\(line.stolenBases)", HittingStatLine.formatRate(line.onBase),
                    HittingStatLine.formatRate(line.slugging)]
        }
    }
}

struct BattingStatsKey: View {
    static let entries: [(abbreviation: String, meaning: String)] = [
        ("AB", "At-bats - plate appearances minus walks and hit-by-pitches"),
        ("R", "Runs scored"),
        ("H", "Hits"),
        ("RBI", "Runs batted in - runs that scored on the batter's hit, walk or out (not on an error or a double play)"),
        ("BB", "Walks"),
        ("K", "Strikeouts"),
        ("AVG", "Batting average - H ÷ AB"),
        ("2B / 3B / HR", "Doubles, triples, home runs"),
        ("HBP", "Hit by pitch"),
        ("SB", "Stolen bases"),
        ("OBP", "On-base % - (H + BB + HBP) ÷ plate appearances"),
        ("SLG", "Slugging - total bases ÷ AB; blank when a hit was saved as just \"Hit\"")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Key")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Self.entries, id: \.abbreviation) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.abbreviation)
                        .font(.caption.weight(.bold))
                        .frame(width: 72, alignment: .leading)
                    Text(entry.meaning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("batting.key")
    }
}

private struct BattingRow: View {
    let title: String
    let values: [String]
    var emphasized: Bool = false
    var isHeader: Bool = false

    private var cellFont: Font {
        if isHeader { return .caption2.weight(.semibold) }
        return emphasized ? .subheadline.weight(.bold).monospacedDigit() : .subheadline.monospacedDigit()
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(emphasized ? .subheadline.weight(.bold) : .subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 72, alignment: .leading)
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value)
                    .font(cellFont)
                    .foregroundStyle(isHeader ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct TeamBattingStatsView: View {
    let team: Team
    let players: [TeamPlayer]
    let games: [Game]

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var events: [PitchEvent] = []
    @State private var runnerEvents: [RunnerEvent] = []
    @State private var isLoading = false
    @State private var columns: BattingColumns = .standard

    private var teamGames: [Game] {
        guard let teamId = team.id else { return [] }
        return games.filter {
            TeamFilterChips.game($0, belongsTo: [teamId]) && authManager.gameCountsInStats($0)
        }
    }

    private var rosterHitterIds: Set<String> { Set(players.compactMap(\.hitterId)) }

    private var battingEvents: [PitchEvent] {
        guard let teamId = team.id else { return [] }
        return TeamBatting.battingEvents(events, teamId: teamId, games: teamGames, rosterHitterIds: rosterHitterIds)
    }

    private var teamRunnerEvents: [RunnerEvent] {
        TeamBatting.runnerEvents(runnerEvents, games: teamGames)
    }

    private struct PlayerRow {
        let id: String
        let title: String
        let line: HittingStatLine
    }

    private func playerRows(_ batting: [PitchEvent], _ running: [RunnerEvent]) -> [PlayerRow] {
        players.compactMap { player -> PlayerRow? in
            guard let hitterId = player.hitterId else { return nil }
            let line = TeamBatting.playerLine(hitterId: hitterId, battingEvents: batting, runnerEvents: running)
            guard line.plateAppearances > 0 || line.runs > 0 || line.stolenBases > 0 else { return nil }
            let jersey = player.jerseyNumber.map { "#\($0) " } ?? ""
            return PlayerRow(id: player.id ?? hitterId, title: "\(jersey)\(player.name)", line: line)
        }
        .sorted { $0.line.plateAppearances > $1.line.plateAppearances }
    }

    var body: some View {
        let batting = battingEvents
        let running = teamRunnerEvents
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Columns", selection: $columns) {
                        ForEach(BattingColumns.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            BattingRow(title: "", values: columns.headers, isHeader: true)
                            let rows = playerRows(batting, running)
                            if rows.isEmpty {
                                Text("No at-bats recorded yet.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(rows, id: \.id) { row in
                                BattingRow(title: row.title, values: columns.values(row.line))
                                    .accessibilityIdentifier("batting.player.\(row.id)")
                            }
                            Divider()
                            BattingRow(title: "Team",
                                       values: columns.values(TeamBatting.teamLine(battingEvents: batting, runnerEvents: running)),
                                       emphasized: true)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal)

                        BattingStatsKey()
                            .padding(.horizontal)

                        Text("From games tracked on this account, minus archived games you left out of stats. Team includes batters entered only by jersey number.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("\(team.name) Batting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        isLoading = true
        let group = DispatchGroup()
        group.enter()
        FieldingEventsLoader.load(games: teamGames, authManager: authManager) { loaded in
            events = loaded
            group.leave()
        }
        group.enter()
        RunnerEventStore.loadForHitters(Array(rosterHitterIds)) { loaded in
            runnerEvents = loaded
            group.leave()
        }
        group.notify(queue: .main) { isLoading = false }
    }
}
