//
//  PlayerLinks.swift
//  PitchMark
//
//  The model behind Link Profiles (LinkProfilesView.swift): what one player
//  *profile* is, and the three things the coach can do there - link a
//  player across teams, merge an accidental duplicate, delete a player.
//
//  A profile is everything that is one kid: roster rows on any number of
//  teams, standalone Pitcher docs (Home's +), and the canonical `Player` doc,
//  grouped transitively by any shared playerId / pitcherId / hitterId. That
//  includes a Player's `linkedPitcherIds`/`linkedHitterIds` - the records a
//  link left behind because they already held tracked history. Events are
//  never moved between records; the stats sheets read every record of a
//  profile as one history.
//
//  Combining always keeps the **oldest** profile, so the outcome never
//  depends on selection order. A profile can only be folded or deleted when
//  this account can write every piece of it (teams it created, Pitchers it
//  owns) - firestore.rules refuses the rest, and a half-applied link is
//  worse than none.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Profile

struct PlayerProfile: Identifiable {
    let id: String
    /// Oldest first.
    let entries: [PlayerRosterEntry]
    let pitchers: [Pitcher]
    let players: [Player]

    var name: String {
        pitchers.first?.name ?? entries.first?.teamPlayer.name ?? players.first?.name ?? ""
    }

    var jersey: String? {
        entries.lazy.compactMap { $0.teamPlayer.jerseyNumber }.first { !$0.isEmpty }
    }

    var createdAt: Date {
        let dates = entries.map { $0.teamPlayer.createdAt }
            + pitchers.compactMap { $0.createdAt }
            + players.map { $0.createdAt }
        return dates.min() ?? .distantFuture
    }

    var teams: [Team] {
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard let id = entry.team.id, seen.insert(id).inserted else { return nil }
            return entry.team
        }
    }

    var playerIds: [String] {
        PlayerLinks.uniqueOrdered(entries.compactMap { $0.teamPlayer.playerId } + players.compactMap { $0.id })
    }

    /// Every pitching record, primary first - what the stats sheet reads.
    var pitcherIds: [String] {
        PlayerLinks.uniqueOrdered(
            entries.compactMap { $0.teamPlayer.pitcherId }
                + players.flatMap { $0.allPitcherIds }
                + pitchers.compactMap { $0.id }
        )
    }

    var hitterIds: [String] {
        PlayerLinks.uniqueOrdered(
            entries.compactMap { $0.teamPlayer.hitterId } + players.flatMap { $0.allHitterIds }
        )
    }

    func isOnTeam(_ teamId: String?) -> Bool {
        guard let teamId else { return false }
        return entries.contains { $0.team.id == teamId }
    }

    func contains(_ teamPlayer: TeamPlayer) -> Bool {
        entries.contains { $0.teamPlayer.id != nil && $0.teamPlayer.id == teamPlayer.id }
    }

    func otherTeams(than teamId: String?) -> [Team] {
        teams.filter { $0.id != teamId }
    }

    /// "Kenzie (14U, 16U)" - how dialogs name a profile.
    var labelWithTeams: String {
        teams.isEmpty ? "\(name) (no team)" : "\(name) (\(PlayerLinks.teamList(teams)))"
    }

    /// True when this account can rewrite or delete every piece of it.
    func isFullyEditable(by uid: String?) -> Bool {
        guard let uid else { return false }
        return entries.allSatisfy { $0.team.createdByUid == uid }
            && pitchers.allSatisfy { $0.ownerUid == uid }
            && players.allSatisfy { $0.ownerUid == uid }
    }
}

// MARK: - Rules

enum PlayerLinks {
    static func normalized(_ name: String) -> String {
        name
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    static func uniqueOrdered(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    /// "Reds · Fall '25, Reds · Fall '26" - with the season, since a linked
    /// player's teams are often the same name a year apart.
    static func teamList(_ teams: [Team]) -> String {
        teams.map { TeamFilterChips.label(for: $0) }.joined(separator: ", ")
    }

    /// Union-find: items sharing any key are one group. Groups come back in
    /// order of their first item, each sorted. Pure so it can be checked
    /// without Firestore types.
    static func groupIndices(keys: [[String]]) -> [[Int]] {
        var parent = Array(0..<keys.count)
        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != root { root = parent[root] }
            var node = i
            while parent[node] != root {
                let next = parent[node]
                parent[node] = root
                node = next
            }
            return root
        }
        var firstByKey: [String: Int] = [:]
        for (i, itemKeys) in keys.enumerated() {
            for key in itemKeys {
                if let first = firstByKey[key] {
                    let a = find(first), b = find(i)
                    if a != b { parent[max(a, b)] = min(a, b) }
                } else {
                    firstByKey[key] = i
                }
            }
        }
        var groups: [Int: [Int]] = [:]
        for i in 0..<keys.count { groups[find(i), default: []].append(i) }
        return groups.keys.sorted().map { groups[$0]! }
    }

    /// Every profile, alphabetical. A `Player` doc with no roster row and no
    /// Pitcher behind it is left out - there's nothing of the kid to show.
    static func profiles(
        rosterEntries: [PlayerRosterEntry],
        pitchers: [Pitcher],
        players: [Player]
    ) -> [PlayerProfile] {
        let entries = rosterEntries.sorted {
            if $0.teamPlayer.createdAt != $1.teamPlayer.createdAt {
                return $0.teamPlayer.createdAt < $1.teamPlayer.createdAt
            }
            return $0.id < $1.id
        }

        var keys: [[String]] = []
        for entry in entries {
            let tp = entry.teamPlayer
            var k = ["row:\(entry.id)"]
            if let id = tp.playerId { k.append("pl:\(id)") }
            if let id = tp.pitcherId { k.append("pi:\(id)") }
            if let id = tp.hitterId { k.append("hi:\(id)") }
            keys.append(k)
        }
        for pitcher in pitchers {
            keys.append(pitcher.id.map { ["pi:\($0)"] } ?? [])
        }
        for player in players {
            var k: [String] = player.id.map { ["pl:\($0)"] } ?? []
            k += player.allPitcherIds.map { "pi:\($0)" }
            k += player.allHitterIds.map { "hi:\($0)" }
            keys.append(k)
        }

        let pitcherBase = entries.count
        let playerBase = pitcherBase + pitchers.count

        return groupIndices(keys: keys).compactMap { indices -> PlayerProfile? in
            let groupEntries = indices.filter { $0 < pitcherBase }.map { entries[$0] }
            let groupPitchers = indices.filter { $0 >= pitcherBase && $0 < playerBase }.map { pitchers[$0 - pitcherBase] }
            let groupPlayers = indices.filter { $0 >= playerBase }.map { players[$0 - playerBase] }
            guard !groupEntries.isEmpty || !groupPitchers.isEmpty else { return nil }
            let id = groupEntries.first?.id ?? groupPitchers.first?.id ?? UUID().uuidString
            return PlayerProfile(id: id, entries: groupEntries, pitchers: groupPitchers, players: groupPlayers)
        }
        .sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            if order != .orderedSame { return order == .orderedAscending }
            return $0.createdAt < $1.createdAt
        }
    }

    static func profile(containing teamPlayer: TeamPlayer, in profiles: [PlayerProfile]) -> PlayerProfile? {
        profiles.first { $0.contains(teamPlayer) }
    }

    enum CombinePlanError: Error, Equatable {
        case needsTwo
        case notEditable(names: [String])
    }

    /// Keep the oldest; fold the rest. Every folded profile must be fully
    /// editable - if exactly one selected profile isn't, it becomes the keep
    /// side instead (only its Player doc is written, never its rows).
    static func combinePlan(
        _ selected: [PlayerProfile],
        currentUid: String?
    ) -> Result<(keep: PlayerProfile, fold: [PlayerProfile]), CombinePlanError> {
        guard selected.count >= 2 else { return .failure(.needsTwo) }
        let byAge = selected.sorted { $0.createdAt < $1.createdAt }
        let locked = byAge.filter { !$0.isFullyEditable(by: currentUid) }
        if locked.count > 1 {
            return .failure(.notEditable(names: locked.map(\.labelWithTeams)))
        }
        let keep = locked.first ?? byAge[0]
        return .success((keep, byAge.filter { $0.id != keep.id }))
    }
}

// MARK: - Writes

extension AuthManager {
    enum ProfileCombineMode {
        /// Same kid, different teams: every roster row is kept.
        case link
        /// Same kid entered twice: on a team where the kept profile already
        /// has a row, the duplicate's row is removed.
        case mergeDuplicate
    }

    /// Link / Merge Duplicate. Folds every piece of `fold` onto `keep`'s
    /// canonical `Player`:
    ///
    /// 1. Resolve the canonical Player (or mint one around keep's existing
    ///    records - never fresh ones, which would abandon their history).
    /// 2. Each folded roster row is repointed (`mergeTeamPlayerIntoPlayer`),
    ///    or - when merging a duplicate on a team keep is already on -
    ///    deleted.
    /// 3. Every folded record that already holds history is added to the
    ///    Player's `linkedPitcherIds`/`linkedHitterIds`, so it stays part of
    ///    this kid even with no roster row pointing at it.
    /// 4. What's left over and empty is cleaned up
    ///    (`cleanupOrphanedPlayerIdentity` only deletes unreferenced,
    ///    history-free docs).
    ///
    /// Rows are processed one at a time on purpose: each step's cleanup scans
    /// for references, and the rows still waiting are what keep a shared
    /// empty record alive until the last of them has moved.
    func combineProfiles(
        keep: PlayerProfile,
        fold: [PlayerProfile],
        mode: ProfileCombineMode,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        resolveCanonicalPlayer(for: keep) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let canonical):
                self.stampPlayerId(canonical, onRowsOf: keep) {
                    self.foldProfiles(fold, into: canonical, keep: keep, mode: mode, completion: completion)
                }
            }
        }
    }

    /// Link Player Across Teams. Two kinds of team can be checked:
    ///
    /// - a team with no entry for this kid: a roster row is added there,
    ///   pointing at the canonical `Player` (`toTeams`);
    /// - a team that already lists the same kid as a separate player - the
    ///   usual case when each season's roster was typed in fresh: that
    ///   profile is combined into this one (`combiningWith`), keeping the
    ///   oldest, exactly as Merge Duplicates does.
    ///
    /// The combine runs first and its canonical Player is the one the new
    /// rows point at, so everything ends up one person even when that
    /// identity had to be minted along the way.
    func linkProfile(
        _ profile: PlayerProfile,
        toTeams teams: [Team],
        combiningWith others: [PlayerProfile] = [],
        currentUid: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var keep = profile
        var fold: [PlayerProfile] = []
        if !others.isEmpty {
            switch PlayerLinks.combinePlan([profile] + others, currentUid: currentUid) {
            case .success(let plan):
                keep = plan.keep
                fold = plan.fold
            case .failure:
                completion(.failure(NSError(
                    domain: "Player",
                    code: 403,
                    userInfo: [NSLocalizedDescriptionKey: "Some of these players come from another coach's account, so they can't be combined here."]
                )))
                return
            }
        }

        resolveCanonicalPlayer(for: keep) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let canonical):
                self.stampPlayerId(canonical, onRowsOf: keep) {
                    func addRows() {
                        self.addRosterRows(for: canonical, teams: teams, completion: completion)
                    }
                    guard !fold.isEmpty else { addRows(); return }
                    self.foldProfiles(fold, into: canonical, keep: keep, mode: .mergeDuplicate) { result in
                        if case .failure(let error) = result { completion(.failure(error)); return }
                        addRows()
                    }
                }
            }
        }
    }

    /// One roster row per team, all pointing at `canonical`. Sequential so a
    /// failure stops cleanly. Jersey numbers are team-local and left blank.
    private func addRosterRows(for canonical: Player, teams: [Team], completion: @escaping (Result<Void, Error>) -> Void) {
        var remaining = teams.compactMap { $0.id }
        func next() {
            guard !remaining.isEmpty else {
                completion(.success(()))
                return
            }
            let teamId = remaining.removeFirst()
            addTeamPlayerLinkingPlayer(teamId: teamId, player: canonical, jerseyNumber: nil) { result in
                if case .failure(let error) = result {
                    completion(.failure(error))
                    return
                }
                next()
            }
        }
        next()
    }

    private func resolveCanonicalPlayer(for keep: PlayerProfile, completion: @escaping (Result<Player, Error>) -> Void) {
        let anchor = keep.entries.first?.teamPlayer
        if let playerId = anchor?.playerId ?? keep.playerIds.first {
            if let cached = keep.players.first(where: { $0.id == playerId }) {
                completion(.success(cached))
                return
            }
            loadPlayer(id: playerId) { player in
                if let player {
                    completion(.success(player))
                } else {
                    self.mintCanonical(for: keep, completion: completion)
                }
            }
        } else {
            mintCanonical(for: keep, completion: completion)
        }
    }

    private func mintCanonical(for keep: PlayerProfile, completion: @escaping (Result<Player, Error>) -> Void) {
        let anchor = keep.entries.first?.teamPlayer
        mintPlayerAroundExistingRecords(
            name: keep.name,
            pitcherId: keep.pitcherIds.first,
            hitterId: keep.hitterIds.first,
            positions: anchor?.positions,
            battingSide: anchor?.battingSide,
            completion: completion
        )
    }

    private func foldProfiles(
        _ fold: [PlayerProfile],
        into canonical: Player,
        keep: PlayerProfile,
        mode: ProfileCombineMode,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var coveredTeamIds = Set(keep.teams.compactMap { $0.id })
        var remaining = fold.flatMap { $0.entries }

        func nextRow() {
            guard !remaining.isEmpty else {
                attachLeftoverRecords()
                return
            }
            let entry = remaining.removeFirst()
            guard let teamId = entry.team.id, let rowId = entry.teamPlayer.id else { nextRow(); return }

            if mode == .mergeDuplicate, coveredTeamIds.contains(teamId) {
                deleteTeamPlayer(teamId: teamId, playerId: rowId) { result in
                    if case .failure(let error) = result { completion(.failure(error)); return }
                    nextRow()
                }
                return
            }
            coveredTeamIds.insert(teamId)
            mergeTeamPlayerIntoPlayer(teamId: teamId, duplicate: entry.teamPlayer, player: canonical) { result in
                if case .failure(let error) = result { completion(.failure(error)); return }
                nextRow()
            }
        }

        func attachLeftoverRecords() {
            let pitcherIds = PlayerLinks.uniqueOrdered(fold.flatMap { $0.pitcherIds })
                .filter { $0 != canonical.pitcherId }
            let hitterIds = PlayerLinks.uniqueOrdered(fold.flatMap { $0.hitterIds })
                .filter { $0 != canonical.hitterId }
            let foldPlayerIds = PlayerLinks.uniqueOrdered(fold.flatMap { $0.playerIds })
                .filter { $0 != canonical.id }

            var keptPitchers: [String] = []
            var keptHitters: [String] = []
            let group = DispatchGroup()
            for id in pitcherIds {
                group.enter()
                pitcherHasRecordedEvents(pitcherId: id) { has in
                    if has { keptPitchers.append(id) }
                    group.leave()
                }
            }
            for id in hitterIds {
                group.enter()
                hitterHasRecordedEvents(hitterId: id) { has in
                    if has { keptHitters.append(id) }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                guard let canonicalId = canonical.id else { completion(.success(())); return }
                var data: [String: Any] = [:]
                if !keptPitchers.isEmpty { data["linkedPitcherIds"] = FieldValue.arrayUnion(keptPitchers) }
                if !keptHitters.isEmpty { data["linkedHitterIds"] = FieldValue.arrayUnion(keptHitters) }

                func cleanup() {
                    for id in foldPlayerIds {
                        self.cleanupOrphanedPlayerIdentity(playerId: id, pitcherId: nil, hitterId: nil, canonical: canonical)
                    }
                    for id in pitcherIds where !keptPitchers.contains(id) {
                        self.cleanupOrphanedPlayerIdentity(playerId: nil, pitcherId: id, hitterId: nil, canonical: canonical)
                    }
                    for id in hitterIds where !keptHitters.contains(id) {
                        self.cleanupOrphanedPlayerIdentity(playerId: nil, pitcherId: nil, hitterId: id, canonical: canonical)
                    }
                    completion(.success(()))
                }

                guard !data.isEmpty else { cleanup(); return }
                Firestore.firestore().collection("players").document(canonicalId).updateData(data) { error in
                    if let error {
                        completion(.failure(error))
                        return
                    }
                    cleanup()
                }
            }
        }

        nextRow()
    }

    /// Keep-side rows that predate the canonical identity get it stamped on,
    /// or a folded record kept under a different Pitcher would share no id
    /// with them and the two halves would stop being one profile.
    private func stampPlayerId(_ player: Player, onRowsOf profile: PlayerProfile, completion: @escaping () -> Void) {
        guard let playerId = player.id else { completion(); return }
        let group = DispatchGroup()
        for entry in profile.entries where entry.teamPlayer.playerId != playerId {
            guard let teamId = entry.team.id, let rowId = entry.teamPlayer.id,
                  entry.team.createdByUid == user?.uid else { continue }
            group.enter()
            Firestore.firestore()
                .collection("teams").document(teamId)
                .collection("players").document(rowId)
                .updateData(["playerId": playerId]) { error in
                    if let error {
                        debugLog("⚠️ stampPlayerId failed:", error.localizedDescription)
                    }
                    group.leave()
                }
        }
        group.notify(queue: .main, execute: completion)
    }

    /// Delete Player: every roster row, the Player doc(s), and the Pitcher/
    /// Hitter records. Pitches already recorded inside games stay in those
    /// games - this removes the kid, not the games they appeared in.
    /// Callers must only offer it for `isFullyEditable` profiles.
    func deleteProfile(_ profile: PlayerProfile, completion: @escaping (Result<Void, Error>) -> Void) {
        let db = Firestore.firestore()
        var firstError: Error? = nil
        let group = DispatchGroup()

        func run(_ ref: DocumentReference) {
            group.enter()
            ref.delete { error in
                if let error, firstError == nil { firstError = error }
                group.leave()
            }
        }

        for entry in profile.entries {
            guard let teamId = entry.team.id, let rowId = entry.teamPlayer.id else { continue }
            run(db.collection("teams").document(teamId).collection("players").document(rowId))
        }
        for id in profile.playerIds { run(db.collection("players").document(id)) }
        for id in profile.pitcherIds { run(db.collection("pitchers").document(id)) }
        for id in profile.hitterIds { run(db.collection("hitters").document(id)) }

        group.notify(queue: .main) {
            if let firstError {
                completion(.failure(firstError))
            } else {
                completion(.success(()))
            }
        }
    }
}
