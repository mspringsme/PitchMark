//
//  FieldingStatsViews.swift
//  PitchMark
//
//  Where fielding stats show (2026-11-03): a Fielding section on Hitting
//  Stats (one player) and a team table from the roster screen. The numbers
//  come from FieldingLedger (FieldingStats.swift).
//
//  Fielding happens on the *other* team's pitches, which live under the
//  game, not the player's /hitters record - so both read the games this
//  account owns. A game another coach tracked isn't included.
//

import SwiftUI
import FirebaseAuth

enum FieldingEventsLoader {
    /// Every pitch of `games` (this account's), merged.
    static func load(games: [Game], authManager: AuthManager, completion: @escaping ([PitchEvent]) -> Void) {
        guard let uid = authManager.user?.uid else {
            completion([])
            return
        }
        let ids = games.compactMap(\.id)
        guard !ids.isEmpty else {
            completion([])
            return
        }
        var collected: [PitchEvent] = []
        let group = DispatchGroup()
        for gameId in ids {
            group.enter()
            authManager.loadGamePitchEvents(ownerUserId: uid, gameId: gameId) { events in
                DispatchQueue.main.async {
                    collected.append(contentsOf: events)
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { completion(collected) }
    }
}

/// PO / A / E / TC / FPCT / DP / INN as one row of cells.
struct FieldingCountsRow: View {
    let title: String
    let counts: FieldingCounts
    var emphasized: Bool = false

    static let headers = ["PO", "A", "E", "TC", "FPCT", "DP", "INN"]

    var values: [String] {
        [
            "\(counts.putouts)", "\(counts.assists)", "\(counts.errors)", "\(counts.totalChances)",
            counts.fieldingPercentText, "\(counts.doublePlays)", counts.inningsText
        ]
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
                    .font(emphasized ? .subheadline.weight(.bold).monospacedDigit() : .subheadline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    static var headerRow: some View {
        HStack(spacing: 4) {
            Text("")
                .frame(width: 72, alignment: .leading)
            ForEach(headers, id: \.self) { header in
                Text(header)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// A big section title on a stats screen ("Hitting", "Fielding"), so one
/// sheet holding both doesn't read as all one kind.
struct StatsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .accessibilityAddTraits(.isHeader)
    }
}

/// What each fielding column means, under every fielding table.
struct FieldingStatsKey: View {
    static let entries: [(abbreviation: String, meaning: String)] = [
        ("PO", "Putouts - made the out: caught it, tagged the runner or stepped on the bag"),
        ("A", "Assists - threw or deflected the ball on an out someone else finished"),
        ("E", "Errors - a misplay that let a batter or runner get on or move up"),
        ("TC", "Total chances - PO + A + E"),
        ("FPCT", "Fielding % - (PO + A) ÷ TC"),
        ("DP", "Double plays - took part in a play with two or more outs"),
        ("INN", "Innings at the position - 4.2 is 4⅔ innings")
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
                        .frame(width: 40, alignment: .leading)
                    Text(entry.meaning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fielding.key")
    }
}

/// Player Stats' Fielding section: the player's line at each position
/// they played, then the total.
struct PlayerFieldingSection: View {
    let ledger: FieldingLedger
    let hitterIds: Set<String>
    let isLoading: Bool

    var body: some View {
        let byPosition = ledger.byPosition(hitterIds: hitterIds)
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if byPosition.isEmpty {
                Text("No fielding recorded yet. Set positions in the lineup gear sheet; outs and errors are credited from the pitch result's Fielded by row.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                FieldingCountsRow.headerRow
                ForEach(FieldingPlay.positions.filter { byPosition[$0] != nil }, id: \.self) { position in
                    FieldingCountsRow(title: position, counts: byPosition[position] ?? FieldingCounts())
                        .accessibilityIdentifier("fielding.player.\(position)")
                }
                Divider()
                FieldingCountsRow(title: "Total", counts: ledger.total(hitterIds: hitterIds), emphasized: true)
                    .accessibilityIdentifier("fielding.player.total")
                Divider()
                FieldingStatsKey()
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A team's fielding: every roster player, at one position or all, plus
/// the team's total (which includes spots nobody on the lineup held).
struct TeamFieldingStatsView: View {
    let team: Team
    let players: [TeamPlayer]
    let games: [Game]

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var events: [PitchEvent] = []
    @State private var isLoading = false
    /// nil = all positions.
    @State private var position: String? = nil

    private var teamGames: [Game] {
        guard let teamId = team.id else { return [] }
        return games.filter {
            TeamFilterChips.game($0, belongsTo: [teamId]) && authManager.gameCountsInStats($0)
        }
    }

    private var ledger: FieldingLedger {
        let teamIds: Set<String> = team.id.map { [$0] } ?? []
        return FieldingLedger(events: FieldingLedger.events(events, fieldingFor: teamIds))
    }

    var body: some View {
        let ledger = ledger
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            chip("All", isSelected: position == nil) { position = nil }
                            ForEach(FieldingPlay.positions, id: \.self) { value in
                                chip(value, isSelected: position == value) { position = value }
                            }
                        }
                        .padding(.horizontal)
                    }

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            FieldingCountsRow.headerRow
                            let rows = playerRows(ledger)
                            if rows.isEmpty {
                                Text(position == nil ? "No fielding recorded yet." : "Nobody has fielded at \(position ?? "") yet.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(rows, id: \.id) { row in
                                FieldingCountsRow(title: row.title, counts: row.counts)
                            }
                            Divider()
                            FieldingCountsRow(title: "Team", counts: ledger.teamTotal(position: position), emphasized: true)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal)

                        FieldingStatsKey()
                            .padding(.horizontal)

                        Text("From games tracked on this account, minus archived games you left out of stats. Only pitches saved with positions set count.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("\(team.name) Fielding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private struct PlayerRow {
        let id: String
        let title: String
        let counts: FieldingCounts
    }

    /// Roster players who played the selected position (or any), most
    /// chances first.
    private func playerRows(_ ledger: FieldingLedger) -> [PlayerRow] {
        players.compactMap { player -> PlayerRow? in
            guard let hitterId = player.hitterId else { return nil }
            let ids: Set<String> = [hitterId]
            guard ledger.byPosition(hitterIds: ids).keys.contains(where: { position == nil || $0 == position })
            else { return nil }
            let jersey = player.jerseyNumber.map { "#\($0) " } ?? ""
            return PlayerRow(id: player.id ?? hitterId, title: "\(jersey)\(player.name)",
                             counts: ledger.total(hitterIds: ids, position: position))
        }
        .sorted { $0.counts.totalChances > $1.counts.totalChances }
    }

    private func chip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(Capsule().fill(isSelected ? Color.pitchMarkActiveGray : Color(.systemGray6)))
    }

    private func load() {
        isLoading = true
        FieldingEventsLoader.load(games: teamGames, authManager: authManager) { loaded in
            events = loaded
            isLoading = false
        }
    }
}
