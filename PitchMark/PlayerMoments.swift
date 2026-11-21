//
//  PlayerMoments.swift
//  PitchMark
//
//  Moments for a player (2026-11-15): a Moments button on their row in
//  Home's Players list and on team rosters (user's call - not buried in
//  the stats sheets), the library's Player filter, and tagging players on
//  a Moment by hand. A Moment is a player's when one
//  of its `playerTags` names one of their Hitter or Pitcher records - the
//  same ids their stats read, so a merged player's clips come together.
//

import SwiftUI
import Combine

enum PlayerMoments {
    /// The Moment is about one of these records.
    static func matches(_ moment: Moment, hitterIds: Set<String>, pitcherIds: Set<String>) -> Bool {
        (moment.playerTags ?? []).contains { tag in
            (tag.hitterId.map { hitterIds.contains($0) } ?? false)
                || (tag.pitcherId.map { pitcherIds.contains($0) } ?? false)
        }
    }

    /// Every tagged name across the library, A-Z, for the Player filter.
    static func taggedNames(in moments: [Moment]) -> [String] {
        let names = Set(moments.flatMap { ($0.playerTags ?? []).map(\.name) })
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func isTagged(_ moment: Moment, name: String) -> Bool {
        (moment.playerTags ?? []).contains { $0.name == name }
    }

    /// A Players row as a tag.
    static func tag(for row: PlayerDirectoryRow) -> MomentPlayerTag {
        MomentPlayerTag(name: row.name, hitterId: row.hitterId, pitcherId: row.pitcherId)
    }
}

/// Every Moment, loaded once and shared by every player row's button -
/// so a list of 30 players reads the library once, not 30 times.
final class PlayerMomentsIndex: ObservableObject {
    static let shared = PlayerMomentsIndex()

    @Published private(set) var moments: [Moment] = []
    private var lastLoad: Date? = nil

    /// Reloads unless it just did (`force` always reloads).
    func refresh(_ authManager: AuthManager, force: Bool = false) {
        if !force, let lastLoad, Date().timeIntervalSince(lastLoad) < 5 { return }
        lastLoad = Date()
        authManager.loadMoments { [weak self] loaded in
            self?.moments = loaded
        }
    }

    /// A Favorite changed somewhere - show it now, before any reload.
    func setFavorite(momentId: String, _ on: Bool) {
        guard let i = moments.firstIndex(where: { $0.id == momentId }) else { return }
        moments[i].isFavorite = on
    }

    func moments(hitterIds: [String], pitcherIds: [String]) -> [Moment] {
        let hitters = Set(hitterIds)
        let pitchers = Set(pitcherIds)
        return moments.filter { PlayerMoments.matches($0, hitterIds: hitters, pitcherIds: pitchers) }
    }
}

/// A player row's Moments button - only when they have some. Its own view
/// with its own sheet, so the rows' parent screens don't grow.
struct PlayerMomentsButton: View {
    let name: String
    var hitterIds: [String] = []
    var pitcherIds: [String] = []

    @EnvironmentObject var authManager: AuthManager
    @ObservedObject private var index = PlayerMomentsIndex.shared
    @State private var showSheet = false

    var body: some View {
        let count = index.moments(hitterIds: hitterIds, pitcherIds: pitcherIds).count
        if count > 0 {
            Button {
                showSheet = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "video.fill")
                    Text("\(count)")
                        .monospacedDigit()
                }
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(Color.pitchMarkActiveGray)
            .accessibilityLabel("\(count) Moment\(count == 1 ? "" : "s") of \(name)")
            .accessibilityIdentifier("player.moments.\(name)")
            .appSheet(isPresented: $showSheet, chrome: .handle) {
                PlayerMomentsSheet(name: name, hitterIds: hitterIds, pitcherIds: pitcherIds) { showSheet = false }
                    .environmentObject(authManager)
            }
        }
    }
}

/// A player's Moments, newest first; tap to play.
struct PlayerMomentsSheet: View {
    let name: String
    let hitterIds: [String]
    let pitcherIds: [String]
    let onClose: () -> Void

    @EnvironmentObject var authManager: AuthManager
    @ObservedObject private var index = PlayerMomentsIndex.shared
    @State private var playing: Moment? = nil

    var body: some View {
        let moments = index.moments(hitterIds: hitterIds, pitcherIds: pitcherIds)
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 14) {
                    ForEach(moments) { moment in
                        PlayerMomentTile(moment: moment) { playing = moment }
                    }
                }
                .padding()
                if moments.isEmpty {
                    Text("No Moments of \(name) yet.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .navigationTitle("\(name)'s Moments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onClose)
                }
            }
        }
        .fullScreenCover(item: $playing) { moment in
            if let id = moment.id, let url = resolvedMomentPlaybackURL(for: id) {
                MomentPlaybackView(videoURL: url)
            }
        }
    }
}

private struct PlayerMomentTile: View {
    let moment: Moment
    let onTap: () -> Void
    @State private var thumbnail: UIImage? = nil

    private var isHere: Bool { moment.id.map { momentVideoExistsLocally(for: $0) } ?? false }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    Color(.secondarySystemBackground)
                    if let thumbnail {
                        Image(uiImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: isHere ? "play.circle.fill" : "exclamationmark.icloud")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 110, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(moment.displayTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .frame(width: 110, alignment: .leading)
                Text(moment.createdAt.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isHere)
        .onAppear {
            guard thumbnail == nil, isHere else { return }
            momentThumbnail(for: moment) { thumbnail = $0 }
        }
    }
}

/// Pick the players a Moment is about.
struct MomentPlayerTagSheet: View {
    let initialTags: [MomentPlayerTag]
    let onSave: ([MomentPlayerTag]) -> Void
    let onCancel: () -> Void

    @EnvironmentObject var authManager: AuthManager
    @State private var rows: [PlayerDirectoryRow] = []
    @State private var selected: [MomentPlayerTag]
    @State private var search = ""
    @State private var isLoading = true

    init(initialTags: [MomentPlayerTag], onSave: @escaping ([MomentPlayerTag]) -> Void, onCancel: @escaping () -> Void) {
        self.initialTags = initialTags
        self.onSave = onSave
        self.onCancel = onCancel
        _selected = State(initialValue: initialTags)
    }

    private var visibleRows: [PlayerDirectoryRow] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func isSelected(_ row: PlayerDirectoryRow) -> Bool {
        selected.contains { tag in
            (tag.hitterId != nil && tag.hitterId == row.hitterId)
                || (tag.pitcherId != nil && tag.pitcherId == row.pitcherId)
        }
    }

    var body: some View {
        NavigationView {
            List {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                }
                ForEach(visibleRows) { row in
                    Button {
                        toggle(row)
                    } label: {
                        HStack {
                            PlayerDirectoryAvatar(row: row, size: 32)
                            Text(row.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isSelected(row) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.pitchMarkActiveGray)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Find a player")
            .navigationTitle("Players in This Moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { onSave(selected) }.fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            authManager.loadPlayerDirectory { entries, _ in
                authManager.loadPitchers { pitchers in
                    authManager.loadMyPlayers { players in
                        rows = PlayerDirectory.rows(rosterEntries: entries, pitchers: pitchers, players: players)
                        isLoading = false
                    }
                }
            }
        }
    }

    private func toggle(_ row: PlayerDirectoryRow) {
        if isSelected(row) {
            selected.removeAll { tag in
                (tag.hitterId != nil && tag.hitterId == row.hitterId)
                    || (tag.pitcherId != nil && tag.pitcherId == row.pitcherId)
            }
        } else {
            selected.append(PlayerMoments.tag(for: row))
        }
    }
}
