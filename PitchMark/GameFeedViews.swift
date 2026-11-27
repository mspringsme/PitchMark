//
//  GameFeedViews.swift
//  PitchMark
//
//  Game feed screens (phase 4; rules in GameFeed.swift, Firestore in
//  GameFeedService.swift):
//  - the scorer: a Feed button on the clip row opens `GameFeedSheet` -
//    start the feed for this game, title, who can follow, what's shared,
//    last names, and requests to approve. `GameFeedWriterHook` keeps the
//    feed in step with the game's pitches.
//  - the coach: `TeamFollowersSection` in Team Members - the follower link,
//    pending followers to approve, feeds on/off for the team.
//  - the follower: `FollowedTeamsSection` on Home's Teams -> a team's
//    games (`FollowerTeamFeedsView`) -> a game (`FollowerGameView`), as one
//    merged timeline or a tab per feed.
//
//  All behind the `gameFeeds` flag. Structs of their own, so the tracker
//  and Home don't grow.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

struct GameFeedLineupEntry: Hashable {
    var hitterId: String
    var name: String
}

// MARK: - Scorer

/// Finds this scorer's feed for the open game and keeps it written.
struct GameFeedWriterHook: ViewModifier {
    let clip: GameClipContext
    let state: () -> GameFeedWriter.GameState
    let signature: String

    @ObservedObject private var writer = GameFeedWriter.shared
    @ObservedObject private var flags = AppFeatureFlagStore.shared

    private var feedId: String? {
        guard flags.flags.isOn(.gameFeeds), clip.isActive, let gid = clip.gameId,
              let uid = Auth.auth().currentUser?.uid else { return nil }
        return GameFeedIds.feedId(gameKey: GameFeedIds.gameKey(scheduledGameId: clip.scheduledGameId, gameId: gid), uid: uid)
    }

    func body(content: Content) -> some View {
        content
            .onAppear { writer.attach(feedId: feedId) }
            .onChange(of: feedId) { _, id in writer.attach(feedId: id) }
            .onChange(of: signature) { _, _ in writer.sync(state()) }
            .onChange(of: writer.feed) { _, _ in writer.sync(state()) }
    }

    /// Changes whenever a pitch is added, edited or undone, or the board moves.
    static func signature(_ pitches: [PitchEvent], inning: Int, us: Int, them: Int) -> String {
        var parts = ["\(inning)", "\(us)", "\(them)", "\(pitches.count)"]
        for p in pitches {
            parts.append("\(p.id ?? "")|\(p.outcome ?? "")|\(p.isBall ?? false)|\(p.strikeSwinging)|\(p.atBatBalls ?? -1)|\(p.atBatStrikes ?? -1)|\(p.play?.runs ?? 0)|\(p.opponentBatterId ?? "")")
        }
        return parts.joined(separator: ";")
    }
}

/// The clip row's Feed button: lit while this game's feed is live.
struct GameFeedButton: View {
    let clip: GameClipContext
    @ObservedObject private var writer = GameFeedWriter.shared
    @State private var showSheet = false

    private var isLive: Bool { writer.feed != nil && writer.feed?.audience != .nobody }

    var body: some View {
        Button { showSheet = true } label: {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isLive ? Color.white : Color.primary)
                .frame(width: 38, height: 34)
                .background(Capsule().fill(isLive ? Color.pitchMarkActiveGray : Color(.secondarySystemBackground)))
        }
        .accessibilityLabel(isLive ? "Game feed is on" : "Game feed")
        .accessibilityIdentifier("gameFeed.button")
        .appSheet(isPresented: $showSheet, chrome: .handle) {
            GameFeedSheet(clip: clip)
        }
    }
}

struct GameFeedSheet: View {
    let clip: GameClipContext

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var writer = GameFeedWriter.shared
    @State private var isCreator = false
    @State private var loaded = false
    @State private var title = ""
    @State private var audience: GameFeedAudience = .team
    @State private var scope: GameFeedScope = .everything
    @State private var showLastNames = false
    @State private var myPlayers: Set<String> = []
    @State private var followers: [FeedFollower] = []
    @State private var listener: ListenerRegistration?
    @State private var errorText: String?
    @State private var saving = false

    private var uid: String? { Auth.auth().currentUser?.uid }

    private var feedId: String? {
        guard let gid = clip.gameId, let uid else { return nil }
        return GameFeedIds.feedId(gameKey: GameFeedIds.gameKey(scheduledGameId: clip.scheduledGameId, gameId: gid), uid: uid)
    }

    var body: some View {
        NavigationStack {
            Form {
                if clip.teamId == nil {
                    Section {
                        Text("Pick your team for this game first - followers follow a team's games.")
                            .foregroundStyle(.secondary)
                    }
                } else if !loaded {
                    ProgressView()
                } else {
                    settings
                    if writer.feed != nil, audience == .approved { requests }
                }
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.red)
                }
            }
            .navigationTitle("Game Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if clip.teamId != nil, loaded {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(writer.feed == nil ? "Start" : "Save") { save() }
                            .fontWeight(.semibold)
                            .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("gameFeed.save")
                    }
                }
            }
        }
        .onAppear(perform: load)
        .onDisappear { listener?.remove() }
    }

    private var settings: some View {
        Group {
            Section {
                TextField("Title followers see", text: $title)
                    .accessibilityIdentifier("gameFeed.title")
                Text(isCreator ? "Official feed - drives the game's score for followers."
                               : "Your own feed - never changes the official score.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text(writer.feed == nil ? "Share This Game" : "Live")
            } footer: {
                Text("Followers see each pitch's result - ball, strike, hit, out, runs. Never what was called or signaled.")
            }
            Section("Who Can Follow") {
                Picker("Who can follow", selection: $audience) {
                    Text("Everyone on the team").tag(GameFeedAudience.team)
                    Text("People I approve").tag(GameFeedAudience.approved)
                    Text("Nobody (paused)").tag(GameFeedAudience.nobody)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("What's Shared") {
                Picker("What's shared", selection: $scope) {
                    Text("Every at-bat").tag(GameFeedScope.everything)
                    Text("Only my players").tag(GameFeedScope.myPlayers)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if scope == .myPlayers {
                    if clip.lineup.isEmpty {
                        Text("No linked players in this lineup yet.").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(clip.lineup, id: \.hitterId) { entry in
                        Button {
                            if myPlayers.contains(entry.hitterId) { myPlayers.remove(entry.hitterId) } else { myPlayers.insert(entry.hitterId) }
                        } label: {
                            HStack {
                                Text(entry.name).foregroundStyle(.primary)
                                Spacer()
                                if myPlayers.contains(entry.hitterId) { Image(systemName: "checkmark").foregroundStyle(.primary) }
                            }
                        }
                    }
                }
                Toggle("Show last names", isOn: $showLastNames)
            }
        }
    }

    private var requests: some View {
        Section("Requests") {
            if followers.isEmpty {
                Text("No one has asked yet.").foregroundStyle(.secondary)
            }
            ForEach(followers) { f in
                HStack {
                    Text(f.name)
                    Spacer()
                    if f.approved {
                        Text("Following").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Button("Approve") {
                            if let id = feedId { GameFeedService.shared.setFeedFollower(feedId: id, uid: f.uid, approved: true) }
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.pitchMarkActiveGray)
                    }
                }
                .swipeActions {
                    Button("Remove", role: .destructive) {
                        if let id = feedId { GameFeedService.shared.setFeedFollower(feedId: id, uid: f.uid, approved: false) }
                    }
                }
            }
        }
    }

    private func load() {
        guard let teamId = clip.teamId, let feedId else { return }
        Firestore.firestore().collection("teams").document(teamId).getDocument { snap, _ in
            let creator = snap?.data()?["createdByUid"] as? String == uid
            GameFeedService.shared.loadFeed(id: feedId) { doc in
                DispatchQueue.main.async {
                    isCreator = creator
                    if let doc {
                        title = doc.title
                        audience = doc.audience
                        scope = doc.scope
                        showLastNames = doc.showLastNames
                        writer.feedSaved(doc)
                    } else {
                        title = creator ? "Coach" : (Auth.auth().currentUser?.displayName?
                            .split(separator: " ").first.map(String.init) ?? "My feed")
                    }
                    myPlayers = writer.myHitterIds(feedId: feedId)
                    loaded = true
                    listener = GameFeedService.shared.listenFeedFollowers(feedId: feedId) { list in
                        followers = list.sorted { !$0.approved && $1.approved }
                    }
                }
            }
        }
    }

    private func save() {
        guard let teamId = clip.teamId, let gid = clip.gameId, let uid, let feedId else { return }
        saving = true
        errorText = nil
        var doc = writer.feed ?? GameFeedDoc(
            id: feedId, ownerUid: uid, teamId: teamId,
            scheduledGameId: GameFeedIds.gameKey(scheduledGameId: clip.scheduledGameId, gameId: gid),
            gameLabel: clip.gameName ?? "Game", startsAt: clip.gameDate,
            title: title, kind: isCreator ? .official : .personal
        )
        doc.title = String(title.trimmingCharacters(in: .whitespaces).prefix(40))
        doc.audience = audience
        doc.scope = scope
        doc.showLastNames = showLastNames
        writer.setMyHitterIds(myPlayers, feedId: feedId)
        GameFeedService.shared.saveFeed(doc) { error in
            DispatchQueue.main.async {
                saving = false
                if let error {
                    errorText = error.localizedDescription
                } else {
                    writer.feedSaved(doc)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Coach

@MainActor
final class TeamFollowersModel: ObservableObject {
    @Published var followers: [FeedFollower] = []
    @Published var feedsOff = false
    @Published var errorText: String?
    /// Team Members' model - its share sheet sits at the roster's root (a
    /// sheet on a List section is copied onto every row).
    weak var members: TeamMembersModel?
    private var teamId: String?
    private var teamName = ""

    func start(teamId: String, teamName: String) {
        self.teamId = teamId
        self.teamName = teamName
        reload()
        GameFeedService.shared.followerFeedsOff(teamId: teamId) { off in
            Task { @MainActor in self.feedsOff = off }
        }
    }

    func reload() {
        guard let teamId else { return }
        GameFeedService.shared.loadTeamFollowers(teamId: teamId) { list in
            Task { @MainActor in
                self.followers = list.sorted { a, b in
                    a.approved == b.approved ? a.name < b.name : !a.approved
                }
            }
        }
    }

    func share(reset: Bool = false) {
        guard let teamId else { return }
        GameFeedService.shared.followerCode(teamId: teamId, teamName: teamName, reset: reset) { result in
            Task { @MainActor in
                switch result {
                case .success(let token):
                    self.members?.shareItems = TeamMembersModel.ShareItems(items: [
                        "Follow \(self.teamName)'s games in PitchMark - live results as they happen: "
                            + "\(TeamAccessRules.inviteLink(token).absoluteString)\n"
                            + "Or in PitchMark: Home → Teams → + → Join a Team, code \(token). The coach approves you."
                    ])
                case .failure(let error):
                    self.errorText = error.localizedDescription
                }
            }
        }
    }

    func set(_ follower: FeedFollower, approved: Bool) {
        guard let teamId else { return }
        if approved {
            if let i = followers.firstIndex(of: follower) { followers[i].approved = true }
        } else {
            followers.removeAll { $0.uid == follower.uid }
        }
        GameFeedService.shared.setTeamFollower(teamId: teamId, uid: follower.uid, approved: approved) { _ in
            Task { @MainActor in self.reload() }
        }
    }

    func setFeedsOff(_ off: Bool) {
        guard let teamId else { return }
        feedsOff = off
        GameFeedService.shared.setFollowerFeedsOff(teamId: teamId, off: off)
    }
}

/// Team Members' Followers rows (creator only, behind the gameFeeds flag).
struct TeamFollowersSection: View {
    let teamId: String
    let teamName: String
    let members: TeamMembersModel
    @StateObject private var model = TeamFollowersModel()
    @ObservedObject private var flags = AppFeatureFlagStore.shared

    var body: some View {
        if flags.flags.isOn(.gameFeeds) {
            Section {
                ForEach(model.followers) { f in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name)
                            Text(f.approved ? "Follower" : "Wants to follow")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !f.approved {
                            Button("Approve") { model.set(f, approved: true) }
                                .buttonStyle(.bordered)
                                .tint(Color.pitchMarkActiveGray)
                                .accessibilityIdentifier("team.follower.approve")
                        }
                        Button("Remove", role: .destructive) { model.set(f, approved: false) }
                            .buttonStyle(.borderless)
                    }
                }
                Button {
                    model.share()
                } label: {
                    Label("Share Follower Link", systemImage: "dot.radiowaves.left.and.right")
                }
                .accessibilityIdentifier("team.followerLink")
                Toggle("Game feeds for followers", isOn: Binding(get: { !model.feedsOff }, set: { model.setFeedsOff(!$0) }))
                if let errorText = model.errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Followers")
            } footer: {
                Text("Followers - grandparents, family far away - follow your games' results from anywhere. They never see the roster, schedule or pitch calls. You approve each one.")
            }
            .onAppear {
                model.members = members
                model.start(teamId: teamId, teamName: teamName)
            }
        }
    }
}

// MARK: - Follower

@MainActor
final class FollowedTeamsModel: ObservableObject {
    @Published var teams: [FeedFollower] = []

    func reload() {
        GameFeedService.shared.myFollowedTeams { list in
            Task { @MainActor in
                self.teams = list.sorted { ($0.teamName ?? "") < ($1.teamName ?? "") }
            }
        }
    }
}

/// The teams this account follows, on Home's Teams (behind gameFeeds).
struct FollowedTeamsSection: View {
    @StateObject private var model = FollowedTeamsModel()
    @ObservedObject private var flags = AppFeatureFlagStore.shared
    @State private var open: FeedFollower?

    var body: some View {
        if flags.flags.isOn(.gameFeeds) {
            VStack(alignment: .leading, spacing: 8) {
                if !model.teams.isEmpty {
                    Text("Following")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(model.teams) { team in
                    Button {
                        if team.approved { open = team }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(team.teamName ?? "Team")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(team.approved ? "Follower · Game Feeds" : "Waiting for the coach to approve")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if team.approved { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("following.team")
                }
            }
            .task { model.reload() }
            .appSheet(item: $open, chrome: .handle) { team in
                FollowerTeamFeedsView(teamId: team.teamId ?? "", teamName: team.teamName ?? "Team")
            }
        }
    }
}

/// A followed team's games, from its feeds - newest first.
struct FollowerTeamFeedsView: View {
    let teamId: String
    let teamName: String
    @Environment(\.dismiss) private var dismiss
    @State private var feeds: [GameFeedDoc] = []
    @State private var listener: ListenerRegistration?

    private struct GameEntry: Identifiable {
        var id: String
        var label: String
        var startsAt: Date?
        var feeds: [GameFeedDoc]
    }

    private var games: [GameEntry] {
        Dictionary(grouping: feeds, by: \.scheduledGameId).map { key, list in
            GameEntry(id: key, label: list.first { $0.kind == .official }?.gameLabel ?? list.first?.gameLabel ?? "Game",
                      startsAt: list.compactMap(\.startsAt).first, feeds: list)
        }
        .sorted { ($0.startsAt ?? .distantPast) > ($1.startsAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            List {
                if games.isEmpty {
                    Text("No game feeds yet. When a scorer starts one, it shows here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(games) { game in
                    NavigationLink {
                        FollowerGameView(label: game.label, feeds: game.feeds)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(game.label).font(.body.weight(.semibold))
                            Text([game.startsAt.map { $0.formatted(date: .abbreviated, time: .shortened) },
                                  "\(game.feeds.count) feed\(game.feeds.count == 1 ? "" : "s")"]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(teamName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear {
            listener = GameFeedService.shared.listenFeeds(teamId: teamId) { list in
                feeds = list.filter { $0.audience != .nobody }
            }
        }
        .onDisappear { listener?.remove() }
    }
}

@MainActor
final class FollowerGameModel: ObservableObject {
    enum Access: Equatable { case open, notAsked, asked }

    @Published var events: [String: [GameFeedEvent]] = [:]
    @Published var access: [String: Access] = [:]
    /// Plays whose animation runs on their own: the newest when the game
    /// opens, then each new play as it arrives (not every old play at once).
    @Published var autoPlayIds: Set<String> = []
    private var seenIds: [String: Set<String>] = [:]
    private var listeners: [String: ListenerRegistration] = [:]

    func played(_ id: String) { autoPlayIds.remove(id) }

    private func noteArrivals(feedId: String, events: [GameFeedEvent]) {
        let ids = Set(events.map(\.id))
        if let seen = seenIds[feedId] {
            autoPlayIds.formUnion(ids.subtracting(seen))
            seenIds[feedId] = seen.union(ids)
        } else {
            if let newest = events.max(by: { $0.at < $1.at }) { autoPlayIds.insert(newest.id) }
            seenIds[feedId] = ids
        }
    }

    func start(_ feeds: [GameFeedDoc]) {
        for feed in feeds where listeners[feed.id] == nil {
            if feed.audience == .team {
                listen(feed.id)
            } else {
                GameFeedService.shared.myFeedStatus(feedId: feed.id) { approved in
                    Task { @MainActor in
                        switch approved {
                        case true?: self.listen(feed.id)
                        case false?: self.access[feed.id] = .asked
                        case nil: self.access[feed.id] = .notAsked
                        }
                    }
                }
            }
        }
    }

    private func listen(_ feedId: String) {
        access[feedId] = .open
        listeners[feedId] = GameFeedService.shared.listenEvents(feedId: feedId) { events in
            // A dropped connection keeps what's on screen; never clear it.
            guard let events else { return }
            Task { @MainActor in
                self.noteArrivals(feedId: feedId, events: events)
                self.events[feedId] = events
            }
        }
    }

    func ask(_ feedId: String) {
        access[feedId] = .asked
        GameFeedService.shared.askToFollow(feedId: feedId) { _ in }
    }

    func stop() {
        listeners.values.forEach { $0.remove() }
        listeners = [:]
    }
}

/// One game: score from the official feed, then a merged timeline or a
/// tab per feed. Newest plays on top.
struct FollowerGameView: View {
    let label: String
    let feeds: [GameFeedDoc]
    @StateObject private var model = FollowerGameModel()
    @State private var tab = "all"

    private var sortedFeeds: [GameFeedDoc] {
        feeds.sorted { a, b in a.kind == b.kind ? a.title < b.title : a.kind == .official }
    }

    private var official: GameFeedDoc? { feeds.first { $0.kind == .official } }

    /// Plays that made an out, per feed (red text).
    private var outPlayIds: Set<String> {
        sortedFeeds.reduce(into: Set<String>()) { result, feed in
            result.formUnion(GameFeedRules.outPlays(model.events[feed.id] ?? []))
        }
    }

    /// The scoreboard's names, from the official feed (else any feed).
    private var scoreNames: (our: String, their: String) {
        let source = official ?? feeds.first
        let our = source?.ourName ?? "", their = source?.theirName ?? ""
        return (our.isEmpty ? "Us" : our, their.isEmpty ? "Them" : their)
    }

    private var rows: [GameFeedRules.TimelineItem] {
        let chosen = tab == "all" ? sortedFeeds : sortedFeeds.filter { $0.id == tab }
        let merged = GameFeedRules.merged(chosen.map { (title: $0.title, events: model.events[$0.id] ?? []) })
        return merged.reversed()
    }

    var body: some View {
        List {
            if let official {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(scoreNames.our) \(official.ourScore)")
                            Text("\(scoreNames.their) \(official.theirScore)")
                        }
                        .font(.title3.monospacedDigit().weight(.bold))
                        Spacer()
                        Text("Inning \(official.inning)").foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section {
                Picker("Feed", selection: $tab) {
                    Text("All").tag("all")
                    ForEach(sortedFeeds) { Text($0.title).tag($0.id) }
                }
                .pickerStyle(.segmented)
            }
            ForEach(sortedFeeds.filter { model.access[$0.id] != .open && model.access[$0.id] != nil }) { feed in
                HStack {
                    Text(feed.title).font(.subheadline.weight(.semibold))
                    Spacer()
                    if model.access[feed.id] == .asked {
                        Text("Asked to follow").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Button("Ask to Follow") { model.ask(feed.id) }
                            .buttonStyle(.bordered)
                            .tint(Color.pitchMarkActiveGray)
                    }
                }
            }
            Section("Plays") {
                if rows.isEmpty {
                    Text("Nothing yet.").foregroundStyle(.secondary)
                }
                let outs = outPlayIds
                ForEach(rows, id: \.event.id) { item in
                    FeedPlayRow(event: item.event, isOut: outs.contains(item.event.id),
                                autoPlay: model.autoPlayIds.contains(item.event.id),
                                onPlayed: { model.played(item.event.id) },
                                feedTitle: tab == "all" && sortedFeeds.count > 1 ? item.feedTitle : nil,
                                ourName: scoreNames.our, theirName: scoreNames.their)
                }
            }
        }
        .navigationTitle(label)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.start(feeds) }
        .onDisappear { model.stop() }
    }
}

/// One play, laid out like the card's result box: batter and number, the
/// result word, then the play lines (runner icon on a hit) - or the count
/// for a ball or strike.
struct FeedPlayRow: View {
    let event: GameFeedEvent
    /// The play made an out: its result shows in red (user, 2026-11-24).
    var isOut: Bool = false
    /// Run the play animation on appearing (PlayAnimation.swift).
    var autoPlay: Bool = false
    var onPlayed: () -> Void = {}
    let feedTitle: String?
    var ourName: String = "Us"
    var theirName: String = "Them"

    @State private var animating = false
    @State private var didAutoPlay = false

    private var plan: PlayAnimationPlan? { PlayAnimationPlan.make(for: event) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.batterLabel).font(.subheadline.weight(.semibold))
                Spacer()
                Text("Inn. \(event.inning)").font(.caption).foregroundStyle(.secondary)
            }
            // The play on the left; outs and the score stacked on the
            // right, right-aligned (user, 2026-11-24).
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    if let batting = event.batting, !batting.isEmpty {
                        Text("\(batting) Batting")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text(event.kindLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isOut ? Color.red : Color.secondary)
                        if plan != nil, !animating {
                            Button { animating = true } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.pitchMarkActiveGray)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Play animation")
                            .accessibilityIdentifier("feed.play")
                        }
                    }
                    if animating, let plan {
                        PlayAnimationView(plan: plan) {
                            animating = false
                            onPlayed()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("feed.animation")
                    } else {
                    Group {
                        if event.showsPlayLines {
                            HStack(spacing: 4) {
                                if event.batterRan { Image(systemName: "figure.run") }
                                Text(event.detail[0]).font(.body.weight(.semibold))
                            }
                            ForEach(Array(event.detail.dropFirst()), id: \.self) { line in
                                Text(line).font(.subheadline)
                            }
                            if event.runs > 0, !event.detail.joined().localizedCaseInsensitiveContains("run") {
                                Text("\(event.runs) run\(event.runs == 1 ? "" : "s") scored").font(.subheadline)
                            }
                        } else {
                            Text(event.text).font(.body)
                        }
                    }
                    .foregroundStyle(isOut ? Color.red : Color.primary)
                    }
                    if let feedTitle {
                        Text(feedTitle).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if event.outs != nil || event.ourScore != nil {
                    VStack(alignment: .trailing, spacing: 1) {
                        if let outsLabel = event.outsLabel { Text(outsLabel) }
                        if let our = event.ourScore, let their = event.theirScore {
                            Text("\(ourName) \(our)")
                            Text("\(theirName) \(their)")
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .onAppear {
            if autoPlay, !didAutoPlay, plan != nil {
                didAutoPlay = true
                animating = true
            }
        }
        .onChange(of: autoPlay) { _, now in
            if now, !didAutoPlay, plan != nil {
                didAutoPlay = true
                animating = true
            }
        }
    }
}

/// `-UITestPlayAnimations`: sample plays in feed cards, in memory, for
/// screenshots of each animation.
struct PlayAnimationsUITestHarness: View {
    private static func sample(_ id: String, _ kind: String, text: String, detail: [String] = [],
                               spot: (Double, Double)? = nil, type: String? = nil, moves: [FeedMove] = []) -> GameFeedEvent {
        GameFeedEvent(id: id, at: Date(), inning: 1, half: nil, batter: "Smith", jersey: "26",
                      kind: kind, text: text, runs: moves.filter { $0.to == 4 }.count, detail: detail,
                      batting: "Hawks", ourScore: 1, theirScore: 2, outs: 1,
                      spotX: spot?.0, spotY: spot?.1, ballType: type, moves: moves)
    }

    static let samples: [GameFeedEvent] = [
        sample("line", "hit", text: "1B", detail: ["1B", "Line · Shallow Center"], spot: (0.5, 0.36), type: "line",
               moves: [FeedMove(from: 0, to: 1), FeedMove(from: 2, to: 4)]),
        sample("fly", "out", text: "Out", detail: ["Out", "Fly · Deep Right"], spot: (0.66, 0.33), type: "fly",
               moves: [FeedMove(from: 0, to: -1)]),
        sample("grounder", "out", text: "Out", detail: ["Out", "Grounder · Short"], spot: (0.42, 0.5), type: "grounder",
               moves: [FeedMove(from: 0, to: -1), FeedMove(from: 1, to: 2)]),
        sample("hr", "hit", text: "HR", detail: ["HR", "Fly · Left"], spot: (0.2, 0.1), type: "hr",
               moves: [FeedMove(from: 0, to: 4), FeedMove(from: 3, to: 4)]),
        sample("k", "strikeout", text: "Strikeout"),
        sample("walk", "walk", text: "Walk")
    ]

    private let frozen = ProcessInfo.processInfo.arguments.contains("-UITestPlayAnimationsFrozen")

    var body: some View {
        if frozen { frozenGrid } else { liveList }
    }

    /// Each sample at 30%, 65% and 100% of its animation.
    private var frozenGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Self.samples) { event in
                    if let plan = PlayAnimationPlan.make(for: event) {
                        Text(event.id).font(.caption.weight(.bold))
                        HStack(spacing: 4) {
                            ForEach([0.12, 0.3, 1.0], id: \.self) { f in
                                PlayAnimationView(plan: plan, frozenAt: f)
                                    .frame(height: 150)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private var liveList: some View {
        NavigationStack {
            List(Self.samples) { event in
                FeedPlayRow(event: event, isOut: event.kind == "out" || event.kind == "strikeout",
                            autoPlay: true, feedTitle: nil, ourName: "Reds", theirName: "Hawks")
            }
            .navigationTitle("Play Animations")
        }
    }
}
