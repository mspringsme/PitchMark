//
//  Player.swift
//  PitchMark
//
//  A persistent identity that outlives any one Team - the fix for "this kid
//  on this season's roster is the same kid as last season's roster." A
//  TeamPlayer (Team.swift) links to one Player via `playerId`; the same
//  Player can be linked from TeamPlayer rows on multiple different Teams,
//  so that player's stats (via their linked Pitcher/Hitter) naturally span
//  every team/season once you're looking at the Player rather than a single
//  team's roster entry.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

enum FieldPosition: String, Codable, CaseIterable {
    case pitcher = "P"
    case catcher = "C"
    case first = "1B"
    case second = "2B"
    case third = "3B"
    case shortstop = "SS"
    case leftField = "LF"
    case centerField = "CF"
    case rightField = "RF"
    case outfield = "OF"
    case utility = "UTIL"
}

enum BattingSide: String, Codable, CaseIterable {
    case right
    case left
    case switchHitter = "switch"
    case slapper

    var displayName: String {
        switch self {
        case .right: return "Right"
        case .left: return "Left"
        case .switchHitter: return "Switch"
        case .slapper: return "Slapper"
        }
    }
}

struct Player: Identifiable, Codable {
    @DocumentID var id: String?

    var name: String
    var ownerUid: String
    var pitcherId: String? = nil
    var hitterId: String? = nil
    var positions: [FieldPosition]? = nil
    var battingSide: BattingSide? = nil
    var createdAt: Date = Date()
    /// Extra Pitcher/Hitter records that belong to this person - left behind
    /// when Link Profiles combined profiles that each already had tracked
    /// history (events are never moved). Stats read them together with
    /// `pitcherId`/`hitterId`. Genuinely Optional so older docs still decode.
    var linkedPitcherIds: [String]? = nil
    var linkedHitterIds: [String]? = nil

    var allPitcherIds: [String] { PlayerLinks.uniqueOrdered([pitcherId].compactMap { $0 } + (linkedPitcherIds ?? [])) }
    var allHitterIds: [String] { PlayerLinks.uniqueOrdered([hitterId].compactMap { $0 } + (linkedHitterIds ?? [])) }
}

// MARK: - AuthManager CRUD

extension AuthManager {
    private func playersCollection() -> CollectionReference {
        Firestore.firestore().collection("players")
    }

    func loadMyPlayers(completion: @escaping ([Player]) -> Void) {
        guard let user = user else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        playersCollection()
            .whereField("ownerUid", isEqualTo: user.uid)
            .getDocuments { snapshot, error in
                if let error {
                    debugLog("❌ loadMyPlayers error:", error.localizedDescription)
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                let players = (snapshot?.documents ?? []).compactMap { try? $0.data(as: Player.self) }
                DispatchQueue.main.async { completion(players) }
            }
    }

    /// Links someone who has **no canonical `Player` doc** onto `teamId` -
    /// a roster row created before Player existed (`playerId == nil`, and
    /// `ensureTeamPlayerHasPitcherAndHitter` backfills the pitcher/hitter
    /// links but never this one), or a `Pitcher` created straight from
    /// Home's + with no roster row at all. Both show up in Home's Players
    /// list, so both have to be linkable, or "Link Existing Player" silently
    /// lists fewer people than Home does.
    ///
    /// The Player doc is minted **around their existing Pitcher/Hitter**
    /// rather than via `createPlayer`, which would mint new ones - and a new
    /// Pitcher means a new `pitchEvents` collection, i.e. the kid's whole
    /// career history abandoned on the old document. Whichever of the two is
    /// genuinely missing is created, keeping `createPlayer`'s
    /// both-links-always invariant.
    func adoptAndLinkPlayer(
        teamId: String,
        name: String,
        pitcherId: String?,
        hitterId: String?,
        positions: [FieldPosition]? = nil,
        battingSide: BattingSide? = nil,
        jerseyNumber: String?,
        completion: @escaping (Result<TeamPlayer, Error>) -> Void
    ) {
        mintPlayerAroundExistingRecords(
            name: name,
            pitcherId: pitcherId,
            hitterId: hitterId,
            positions: positions,
            battingSide: battingSide
        ) { result in
            switch result {
            case .success(let player):
                self.addTeamPlayerLinkingPlayer(
                    teamId: teamId,
                    player: player,
                    jerseyNumber: jerseyNumber,
                    completion: completion
                )
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// `adoptAndLinkPlayer` minus the roster row - the minting half on its
    /// own, for the linking paths that need a canonical identity for someone
    /// who has none but must *not* gain a roster entry as a side effect (see
    /// `mergePeople`, where every row involved already exists).
    func mintPlayerAroundExistingRecords(
        name: String,
        pitcherId: String?,
        hitterId: String?,
        positions: [FieldPosition]? = nil,
        battingSide: BattingSide? = nil,
        completion: @escaping (Result<Player, Error>) -> Void
    ) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        func mintPlayer(pitcherId: String?, hitterId: String?) {
            let ref = self.playersCollection().document()
            let player = Player(
                id: ref.documentID,
                name: name,
                ownerUid: user.uid,
                pitcherId: pitcherId,
                hitterId: hitterId,
                positions: positions,
                battingSide: battingSide,
                createdAt: Date()
            )
            do {
                try ref.setData(from: player) { error in
                    if let error {
                        completion(.failure(error))
                        return
                    }
                    self.backfillPlayerIdOnRosterRows(
                        playerId: ref.documentID,
                        pitcherId: pitcherId,
                        hitterId: hitterId
                    )
                    completion(.success(player))
                }
            } catch {
                completion(.failure(error))
            }
        }

        if pitcherId == nil {
            createPitcher(name: name, templateId: nil) { pitcher in
                if hitterId == nil {
                    self.createHitter(name: name) { hitter in
                        mintPlayer(pitcherId: pitcher?.id, hitterId: hitter?.id)
                    }
                } else {
                    mintPlayer(pitcherId: pitcher?.id, hitterId: hitterId)
                }
            }
        } else if hitterId == nil {
            createHitter(name: name) { hitter in
                mintPlayer(pitcherId: pitcherId, hitterId: hitter?.id)
            }
        } else {
            mintPlayer(pitcherId: pitcherId, hitterId: hitterId)
        }
    }

    func loadPlayer(id: String, completion: @escaping (Player?) -> Void) {
        playersCollection().document(id).getDocument { snapshot, error in
            if let error {
                debugLog("❌ loadPlayer error:", error.localizedDescription)
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let player = snapshot.flatMap { try? $0.data(as: Player.self) }
            DispatchQueue.main.async { completion(player) }
        }
    }

    /// A person's name is denormalized into up to four documents: the
    /// `Pitcher`, the `Hitter`, the canonical `Player`, and one `TeamPlayer`
    /// row per team they're linked from. Renaming only one of them is what
    /// made Home's Players row (and the pitcher picker, which reads the same
    /// roster rows) keep showing the old name while the Edit sheet - which
    /// reads the Pitcher doc - showed the new one.
    ///
    /// Best-effort by design: a `TeamPlayer` row on a team someone else
    /// created is not writable by this user (firestore.rules gates roster
    /// writes on `isTeamCreator`), so a denial there is logged and skipped
    /// rather than failing the rename. Every write is a name-only merge, so
    /// nothing else on any of those documents is touched.
    ///
    /// `playerId`/`hitterId` are optional because a caller that starts from
    /// a Pitcher has no backlink to them - they're harvested from whichever
    /// roster row links the same pitcher.
    func propagatePlayerRename(
        name: String,
        pitcherId: String?,
        playerId: String? = nil,
        hitterId: String? = nil,
        completion: (() -> Void)? = nil
    ) {
        guard user != nil, !name.isEmpty else {
            completion?()
            return
        }

        if let pitcherId {
            Firestore.firestore().collection("pitchers").document(pitcherId)
                .setData(["name": name], merge: true) { error in
                    if let error {
                        debugLog("⚠️ propagatePlayerRename pitcher failed:", error.localizedDescription)
                    }
                }
        }

        loadMyTeams { entries, _ in
            var resolvedPlayerId = playerId
            var resolvedHitterId = hitterId
            let group = DispatchGroup()

            for entry in entries {
                guard let teamId = entry.team.id else { continue }
                group.enter()
                self.loadTeamPlayers(teamId: teamId) { players in
                    for teamPlayer in players {
                        let matches = (pitcherId != nil && teamPlayer.pitcherId == pitcherId)
                            || (playerId != nil && teamPlayer.playerId == playerId)
                        guard matches, let rowId = teamPlayer.id else { continue }
                        if resolvedPlayerId == nil { resolvedPlayerId = teamPlayer.playerId }
                        if resolvedHitterId == nil { resolvedHitterId = teamPlayer.hitterId }
                        guard teamPlayer.name != name else { continue }
                        group.enter()
                        self.updateTeamPlayer(
                            teamId: teamId,
                            playerId: rowId,
                            name: name,
                            jerseyNumber: teamPlayer.jerseyNumber,
                            positions: teamPlayer.positions,
                            battingSide: teamPlayer.battingSide
                        ) { result in
                            if case .failure(let error) = result {
                                debugLog("⚠️ propagatePlayerRename roster row failed:", error.localizedDescription)
                            }
                            group.leave()
                        }
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                if let resolvedPlayerId {
                    self.playersCollection().document(resolvedPlayerId)
                        .setData(["name": name], merge: true) { error in
                            if let error {
                                debugLog("⚠️ propagatePlayerRename player failed:", error.localizedDescription)
                            }
                        }
                }
                if let resolvedHitterId {
                    self.updateHitterName(id: resolvedHitterId, name: name)
                }
                completion?()
            }
        }
    }

    // MARK: - Linking an existing player onto another team

    /// True when this Pitcher's career collection has at least one event -
    /// `limit(to: 1)`, so this stays one tiny read however long a career is.
    /// The question linking has to answer before it may repoint a roster row
    /// off a Pitcher doc: a record with history can never be quietly
    /// abandoned, an empty one is just the duplicate the coach is cleaning up.
    func pitcherHasRecordedEvents(pitcherId: String, completion: @escaping (Bool) -> Void) {
        Firestore.firestore().collection("pitchers").document(pitcherId)
            .collection("pitchEvents").limit(to: 1)
            .getDocuments { snapshot, error in
                if let error {
                    debugLog("⚠️ pitcherHasRecordedEvents failed:", error.localizedDescription)
                    // Assume history on a failed read - the safe direction is
                    // keeping a record, never deleting one on a guess.
                    DispatchQueue.main.async { completion(true) }
                    return
                }
                DispatchQueue.main.async { completion(!(snapshot?.documents.isEmpty ?? true)) }
            }
    }

    /// `pitcherHasRecordedEvents` for the Hitter side - `/hitters/{id}/
    /// pitchEvents` accumulates the same PitchEvent rows filtered by
    /// hitterId (see Hitter.swift), so a hitting record can carry history
    /// the pitching one doesn't and the two are checked independently.
    func hitterHasRecordedEvents(hitterId: String, completion: @escaping (Bool) -> Void) {
        Firestore.firestore().collection("hitters").document(hitterId)
            .collection("pitchEvents").limit(to: 1)
            .getDocuments { snapshot, error in
                if let error {
                    debugLog("⚠️ hitterHasRecordedEvents failed:", error.localizedDescription)
                    DispatchQueue.main.async { completion(true) }
                    return
                }
                DispatchQueue.main.async { completion(!(snapshot?.documents.isEmpty ?? true)) }
            }
    }

    /// Folds a roster row that was entered as its own person onto `player`'s
    /// identity. `playerId` always moves across - that is what makes the two
    /// stop being two people in every Players list - and so does the name,
    /// so the row reads the same as the person it now belongs to.
    ///
    /// The Pitcher/Hitter links move only when the duplicate's own records
    /// are *empty*. A record with recorded history stays exactly where it is
    /// and that team's row keeps pointing at it: repointing would strand a
    /// whole career on a document nothing references any more, and moving
    /// the events would mean rewriting every one in `/pitchers` and in the
    /// owner's games. The coach never sees the two records as two: every
    /// person-level stats entry point hands the stats sheets *all* of a
    /// person's records (`PlayerDirectoryRow.pitcherIds`/`hitterIds`,
    /// `PlayerProfile`) and they read them as one history.
    ///
    /// Whatever the duplicate leaves behind is then cleaned up by
    /// `cleanupOrphanedPlayerIdentity`, which only deletes what nothing
    /// references and what holds no history.
    func mergeTeamPlayerIntoPlayer(
        teamId: String,
        duplicate: TeamPlayer,
        player: Player,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let rowId = duplicate.id, let playerId = player.id else {
            completion(.failure(NSError(
                domain: "Player",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "That roster entry can't be linked."]
            )))
            return
        }

        recordsToKeepSeparate(for: duplicate, canonical: player) { keptPitcherId, keptHitterId in
            var data: [String: Any] = ["playerId": playerId, "name": player.name]
            if keptPitcherId == nil, let canonicalPitcherId = player.pitcherId {
                data["pitcherId"] = canonicalPitcherId
            }
            if keptHitterId == nil, let canonicalHitterId = player.hitterId {
                data["hitterId"] = canonicalHitterId
            }

            Firestore.firestore()
                .collection("teams").document(teamId)
                .collection("players").document(rowId)
                .updateData(data) { error in
                    if let error {
                        completion(.failure(error))
                        return
                    }
                    self.cleanupOrphanedPlayerIdentity(
                        playerId: duplicate.playerId == playerId ? nil : duplicate.playerId,
                        pitcherId: keptPitcherId == nil ? duplicate.pitcherId : nil,
                        hitterId: keptHitterId == nil ? duplicate.hitterId : nil,
                        canonical: player
                    )
                    completion(.success(()))
                }
        }
    }

    /// Which of the duplicate's records must stay put because they already
    /// hold history. A record that *is* the canonical one, or isn't there at
    /// all, is nothing to keep separate.
    private func recordsToKeepSeparate(
        for duplicate: TeamPlayer,
        canonical: Player,
        completion: @escaping (String?, String?) -> Void
    ) {
        func checkHitter(keptPitcherId: String?) {
            guard let hitterId = duplicate.hitterId, hitterId != canonical.hitterId else {
                completion(keptPitcherId, nil)
                return
            }
            hitterHasRecordedEvents(hitterId: hitterId) { hasHistory in
                completion(keptPitcherId, hasHistory ? hitterId : nil)
            }
        }

        guard let pitcherId = duplicate.pitcherId, pitcherId != canonical.pitcherId else {
            checkHitter(keptPitcherId: nil)
            return
        }
        pitcherHasRecordedEvents(pitcherId: pitcherId) { hasHistory in
            checkHitter(keptPitcherId: hasHistory ? pitcherId : nil)
        }
    }

    /// Deletes what a merge left behind - but only ever what no roster row
    /// still points at, and (for Pitcher/Hitter docs) only what holds no
    /// recorded history. Three guards earn that:
    ///
    /// 1. The canonical player's own records are excluded outright.
    /// 2. The reference scan bails unless it actually saw roster rows -
    ///    `loadTeamPlayers` reports a failed read as an empty roster, and
    ///    "no rows anywhere" would otherwise read as "nothing references
    ///    this", which is precisely the input that would delete a `Player`
    ///    doc three other teams still link.
    /// 3. A duplicate identity can itself span several teams; merging one of
    ///    its rows leaves the rest, and the scan sees them.
    ///
    /// Best-effort and silent either way: an orphan that survives is a
    /// stray row in Home's Players, which is cosmetic. Deleting something
    /// live is not, so every ambiguity resolves toward keeping.
    func cleanupOrphanedPlayerIdentity(
        playerId: String?,
        pitcherId: String?,
        hitterId: String?,
        canonical: Player
    ) {
        let playerId = playerId.flatMap { $0 == canonical.id ? nil : $0 }
        let pitcherId = pitcherId.flatMap { $0 == canonical.pitcherId ? nil : $0 }
        let hitterId = hitterId.flatMap { $0 == canonical.hitterId ? nil : $0 }
        guard playerId != nil || pitcherId != nil || hitterId != nil else { return }

        loadMyTeams { entries, error in
            guard error == nil, !entries.isEmpty else { return }

            var referencedPlayerIds: Set<String> = []
            var referencedPitcherIds: Set<String> = []
            var referencedHitterIds: Set<String> = []
            var sawAnyRow = false
            let group = DispatchGroup()

            for entry in entries {
                guard let teamId = entry.team.id else { continue }
                group.enter()
                // loadTeamPlayers completes on the main queue, so these
                // mutations are serialized without a lock.
                self.loadTeamPlayers(teamId: teamId) { rows in
                    for row in rows {
                        sawAnyRow = true
                        if let id = row.playerId { referencedPlayerIds.insert(id) }
                        if let id = row.pitcherId { referencedPitcherIds.insert(id) }
                        if let id = row.hitterId { referencedHitterIds.insert(id) }
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                guard sawAnyRow else { return }

                if let playerId, !referencedPlayerIds.contains(playerId) {
                    self.playersCollection().document(playerId).delete { error in
                        if let error {
                            debugLog("⚠️ cleanupOrphanedPlayerIdentity player failed:", error.localizedDescription)
                        }
                    }
                }

                if let pitcherId, !referencedPitcherIds.contains(pitcherId) {
                    self.pitcherHasRecordedEvents(pitcherId: pitcherId) { hasHistory in
                        guard !hasHistory else { return }
                        Firestore.firestore().collection("pitchers").document(pitcherId).delete { error in
                            if let error {
                                debugLog("⚠️ cleanupOrphanedPlayerIdentity pitcher failed:", error.localizedDescription)
                            }
                        }
                    }
                }

                if let hitterId, !referencedHitterIds.contains(hitterId) {
                    self.hitterHasRecordedEvents(hitterId: hitterId) { hasHistory in
                        guard !hasHistory else { return }
                        Firestore.firestore().collection("hitters").document(hitterId).delete { error in
                            if let error {
                                debugLog("⚠️ cleanupOrphanedPlayerIdentity hitter failed:", error.localizedDescription)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Creates the Player doc with both a linked Pitcher and a linked
    /// Hitter, always - no role designation to pick, since a player might
    /// pitch, bat, or both over a season and there's no reason to make a
    /// coach decide that up front (or ever go back and "unlock" the other
    /// one). `positions`/`battingSide` are stored on the Player as the
    /// default a newly linked team starts from; editing them on a specific
    /// team's roster entry afterward is team-local only (see
    /// `updateTeamPlayer`), not pushed back here.
    func createPlayer(
        name: String,
        positions: [FieldPosition]? = nil,
        battingSide: BattingSide? = nil,
        completion: @escaping (Result<Player, Error>) -> Void
    ) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        createPitcher(name: name, templateId: nil) { pitcher in
            self.createHitter(name: name) { hitter in
                let ref = self.playersCollection().document()
                let player = Player(
                    id: ref.documentID,
                    name: name,
                    ownerUid: user.uid,
                    pitcherId: pitcher?.id,
                    hitterId: hitter?.id,
                    positions: positions,
                    battingSide: battingSide,
                    createdAt: Date()
                )
                do {
                    try ref.setData(from: player) { error in
                        if let error {
                            completion(.failure(error))
                        } else {
                            completion(.success(player))
                        }
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }
}
