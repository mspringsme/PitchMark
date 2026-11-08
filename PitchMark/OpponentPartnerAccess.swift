//
//  OpponentPartnerAccess.swift
//  PitchMark
//
//  Scan Opponent Lineup (2026-11-06). A parent connected to a live room
//  can see and edit the room's opponent roster (firestore.rules, OPPONENT
//  ACCESS FOR LIVE PARTNERS). The claim is the room itself, written to
//  teams/{teamId}/partnerAccess/{uid}; the rules re-check it on every use.
//
//  What changes for a partner holding a claim:
//  - a new opponent player's Pitcher/Hitter/Player records are the
//    coach's (`ownerUid` = room owner), so the coach's phone can save
//    that batter's pitches and edit them later;
//  - a rename names the roster row it came from (`renamedVia`).
//
//  Also here: writing a scanned lineup, to the saved game or the room.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// The claims this device holds: opponent team id -> the room.
final class OpponentPartnerAccess {
    struct Grant: Equatable {
        let liveId: String
        let ownerUid: String
    }

    static let shared = OpponentPartnerAccess()
    private var grants: [String: Grant] = [:]
    private let lock = NSLock()

    func grant(for teamId: String?) -> Grant? {
        guard let teamId, !teamId.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        return grants[teamId]
    }

    func set(_ grant: Grant, for teamId: String) {
        lock.lock(); defer { lock.unlock() }
        grants[teamId] = grant
    }

    /// Leaving a room drops its claims here; the rules stop honouring
    /// them on their own once the room ends or expires.
    func clear(liveId: String) {
        lock.lock(); defer { lock.unlock() }
        grants = grants.filter { $0.value.liveId != liveId }
    }
}

/// One spot to add to a lineup.
struct ScannedLineupEntry: Equatable {
    /// The lineup spot's id, minted once so the room and the saved game
    /// get the same spot.
    var cellId = UUID().uuidString
    var display: String
    var hitterId: String
    var teamPlayerId: String?
}

extension AuthManager {

    // MARK: Claim

    /// Claims the opponent roster for this room. Completion is true once
    /// the claim is written (the roster is then readable); false when the
    /// rules refuse it (not in the room, not this game's opponent).
    ///
    /// `canEdit` false claims the game's own team: readable only (rules
    /// H1-H4), so it's never recorded as a grant - the grant is what turns
    /// on the partner's add/rename paths.
    func claimOpponentAccess(teamId: String, liveId: String, ownerUid: String, canEdit: Bool = true, completion: @escaping (Bool) -> Void) {
        guard let uid = user?.uid, !teamId.isEmpty, !liveId.isEmpty, uid != ownerUid else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        if canEdit, OpponentPartnerAccess.shared.grant(for: teamId)?.liveId == liveId {
            DispatchQueue.main.async { completion(true) }
            return
        }
        Firestore.firestore()
            .collection("teams").document(teamId)
            .collection("partnerAccess").document(uid)
            .setData(["uid": uid, "liveId": liveId, "grantedAt": FieldValue.serverTimestamp()]) { error in
                DispatchQueue.main.async {
                    if let error {
                        debugLog("⚠️ claimOpponentAccess refused:", error.localizedDescription)
                        completion(false)
                    } else {
                        if canEdit {
                            OpponentPartnerAccess.shared.set(.init(liveId: liveId, ownerUid: ownerUid), for: teamId)
                        }
                        completion(true)
                    }
                }
            }
    }

    // MARK: Records for the coach

    /// A partner's new opponent player: Pitcher, Hitter and Player docs
    /// owned by the room's owner (rules: createdForRoomOwner).
    func createPlayerForRoomOwner(
        name: String,
        positions: [FieldPosition]?,
        battingSide: BattingSide?,
        grant: OpponentPartnerAccess.Grant,
        completion: @escaping (Result<Player, Error>) -> Void
    ) {
        guard let uid = user?.uid else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }
        let db = Firestore.firestore()
        let stamp: [String: Any] = ["createdViaLiveId": grant.liveId, "createdByUid": uid]
        let now = Date()

        let pitcherRef = db.collection("pitchers").document()
        let hitterRef = db.collection("hitters").document()
        let playerRef = db.collection("players").document()
        let pitcher = Pitcher(id: nil, name: name, templateId: nil, ownerUid: grant.ownerUid,
                              sharedWith: [grant.ownerUid], claimedByUid: grant.ownerUid, createdAt: now)
        let hitter = Hitter(id: nil, name: name, ownerUid: grant.ownerUid, createdAt: now)
        let player = Player(id: nil, name: name, ownerUid: grant.ownerUid,
                            pitcherId: pitcherRef.documentID, hitterId: hitterRef.documentID,
                            positions: positions, battingSide: battingSide, createdAt: now)

        func encoded<T: Encodable>(_ value: T) throws -> [String: Any] {
            try Firestore.Encoder().encode(value).merging(stamp) { _, new in new }
        }

        do {
            let pitcherData = try encoded(pitcher)
            let hitterData = try encoded(hitter)
            let playerData = try encoded(player)
            // Separate requests, never one batch (CLAUDE.md): each doc
            // has its own rule.
            pitcherRef.setData(pitcherData) { error in
                if let error { completion(.failure(error)); return }
                hitterRef.setData(hitterData) { error in
                    if let error { completion(.failure(error)); return }
                    playerRef.setData(playerData) { error in
                        if let error { completion(.failure(error)); return }
                        var saved = player
                        saved.id = playerRef.documentID
                        completion(.success(saved))
                    }
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    /// A partner's rename of an opponent player's records, naming the
    /// roster row (rules: renamedViaOpponentRow). Best-effort, like
    /// `propagatePlayerRename`.
    func renameOpponentRecordsAsPartner(
        teamId: String,
        rowId: String,
        name: String,
        pitcherId: String?,
        hitterId: String?,
        playerId: String?,
        completion: (() -> Void)? = nil
    ) {
        let db = Firestore.firestore()
        let data: [String: Any] = ["name": name, "renamedVia": ["teamId": teamId, "rowId": rowId]]
        let group = DispatchGroup()
        for (collection, id) in [("pitchers", pitcherId), ("hitters", hitterId), ("players", playerId)] {
            guard let id, !id.isEmpty else { continue }
            group.enter()
            db.collection(collection).document(id).setData(data, merge: true) { error in
                if let error { debugLog("⚠️ partner rename \(collection) failed:", error.localizedDescription) }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion?() }
    }

    // MARK: Adding a scanned lineup

    /// Creates the roster rows a plan needs and hands back the lineup in
    /// batting order. A player whose row couldn't be made is left out and
    /// counted in `failed`.
    func resolveScanPlan(
        teamId: String,
        plan: LineupScanPlan,
        existingTeamPlayerIds: [String: String],
        completion: @escaping (_ entries: [ScannedLineupEntry], _ failed: Int) -> Void
    ) {
        var created: [Int: TeamPlayer] = [:]
        var failed = 0
        let group = DispatchGroup()
        for (index, decision) in plan.newPlayers.enumerated() {
            group.enter()
            addTeamPlayerCreatingNewPlayer(teamId: teamId, name: decision.name, jerseyNumber: decision.jersey) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let row) where row.hitterId != nil:
                        created[index] = row
                    case .success:
                        failed += 1
                    case .failure(let error):
                        debugLog("❌ scan: roster row failed:", error.localizedDescription)
                        failed += 1
                    }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            let entries: [ScannedLineupEntry] = plan.lineup.compactMap { entry in
                switch entry {
                case .existing(let hitterId, let display):
                    return ScannedLineupEntry(display: display, hitterId: hitterId, teamPlayerId: existingTeamPlayerIds[hitterId])
                case .new(let index, let display):
                    guard let row = created[index], let hitterId = row.hitterId else { return nil }
                    return ScannedLineupEntry(display: display, hitterId: hitterId, teamPlayerId: row.id)
                }
            }
            completion(entries, failed)
        }
    }

    /// Appends to the owner's saved game in one transaction: lineup,
    /// links, and the curated opponent batter list when the game has one.
    /// Anyone already linked in the game is skipped against the fresh copy.
    func appendScannedLineupToSavedGame(
        ownerUid: String,
        gameId: String,
        entries: [ScannedLineupEntry],
        completion: @escaping (Error?) -> Void
    ) {
        guard user?.uid == ownerUid else {
            completion(NSError(domain: "Auth", code: 403, userInfo: [NSLocalizedDescriptionKey: "Only the game's owner can do that"]))
            return
        }
        let db = Firestore.firestore()
        let ref = db.collection("users").document(ownerUid).collection("games").document(gameId)
        db.runTransaction({ txn, errPtr -> Any? in
            do {
                let snap = try txn.getDocument(ref)
                guard let data = snap.data() else { return nil }
                var jerseys = (data["jerseyNumbers"] as? [String]) ?? []
                var ids = (data["batterIds"] as? [String]) ?? []
                if ids.count != jerseys.count { ids = jerseys.map { _ in UUID().uuidString } }
                var links = (data["hitterIdByBatterId"] as? [String: String]) ?? [:]
                var active = (data["activeAwayBatterIds"] as? [String]) ?? []
                let curated = !active.isEmpty
                var linkedHitters = Set(ids.compactMap { links[$0] })
                for entry in entries where !linkedHitters.contains(entry.hitterId) && !ids.contains(entry.cellId) {
                    let id = entry.cellId
                    jerseys.append(entry.display)
                    ids.append(id)
                    links[id] = entry.hitterId
                    linkedHitters.insert(entry.hitterId)
                    if curated, let rowId = entry.teamPlayerId, !active.contains(rowId) { active.append(rowId) }
                }
                var update: [String: Any] = ["jerseyNumbers": jerseys, "batterIds": ids, "hitterIdByBatterId": links]
                if curated { update["activeAwayBatterIds"] = active }
                txn.updateData(update, forDocument: ref)
                return true
            } catch let error as NSError {
                errPtr?.pointee = error
                return nil
            }
        }) { _, error in
            DispatchQueue.main.async { completion(error) }
        }
    }
}

extension LiveGameService {
    /// Appends to the room's lineup and its link map in one transaction.
    /// The owner's phone copies both into the saved game when its tracker
    /// sees the room (LiveLineupLinks).
    func appendScannedLineup(liveId: String, entries: [ScannedLineupEntry], completion: @escaping (Error?) -> Void) {
        let db = Firestore.firestore()
        let ref = db.collection("liveGames").document(liveId)
        db.runTransaction({ txn, errPtr -> Any? in
            do {
                let snap = try txn.getDocument(ref)
                guard let data = snap.data() else { return nil }
                var jerseys = (data["jerseyNumbers"] as? [String]) ?? []
                var ids = (data["batterIds"] as? [String]) ?? []
                guard ids.count == jerseys.count else {
                    errPtr?.pointee = NSError(domain: "LiveGame", code: -2, userInfo: [NSLocalizedDescriptionKey: "The live lineup is out of step - try again in a moment"])
                    return nil
                }
                let links = (data[LiveLineupLinks.field] as? [String: String]) ?? [:]
                var linkedHitters = Set(ids.compactMap { links[$0] })
                var update: [String: Any] = [:]
                for entry in entries where !linkedHitters.contains(entry.hitterId) && !ids.contains(entry.cellId) {
                    let id = entry.cellId
                    jerseys.append(entry.display)
                    ids.append(id)
                    update["\(LiveLineupLinks.field).\(id)"] = entry.hitterId
                    linkedHitters.insert(entry.hitterId)
                }
                update["jerseyNumbers"] = jerseys
                update["batterIds"] = ids
                txn.updateData(update, forDocument: ref)
                return true
            } catch let error as NSError {
                errPtr?.pointee = error
                return nil
            }
        }) { _, error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    /// The coach's phone, on a room whose lineup is empty: copy the game's
    /// lineup and links in. A transaction, so a partner's add that lands
    /// first is never overwritten.
    func seedLineupIfEmpty(liveId: String, ownerUid: String, gameId: String) {
        let db = Firestore.firestore()
        let roomRef = db.collection("liveGames").document(liveId)
        let gameRef = db.collection("users").document(ownerUid).collection("games").document(gameId)
        db.runTransaction({ txn, errPtr -> Any? in
            do {
                let room = try txn.getDocument(roomRef)
                guard let roomData = room.data() else { return nil }
                let game = try txn.getDocument(gameRef)
                guard let gameData = game.data(),
                      let update = LiveLineupLinks.seedForEmptyRoom(
                        roomJerseys: (roomData["jerseyNumbers"] as? [String]) ?? [],
                        gameJerseys: (gameData["jerseyNumbers"] as? [String]) ?? [],
                        gameIds: (gameData["batterIds"] as? [String]) ?? [],
                        gameLinks: gameData[LiveLineupLinks.field] as? [String: String]
                      ) else { return nil }
                txn.updateData(update, forDocument: roomRef)
                return true
            } catch let error as NSError {
                errPtr?.pointee = error
                return nil
            }
        }) { _, error in
            if let error { debugLog("⚠️ seedLineupIfEmpty failed:", error.localizedDescription) }
        }
    }

    /// A partner leaving from Home: their presence goes, so the coach's
    /// phone shows them gone (rules let a participant delete their own).
    func leaveLiveRoom(liveId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore()
            .collection("liveGames").document(liveId)
            .collection("participants").document(uid)
            .delete { error in
                if let error { debugLog("⚠️ leaveLiveRoom failed:", error.localizedDescription) }
            }
    }

    /// The room's copy of this device's lineup links, one field per spot
    /// so two phones writing at once don't clobber each other.
    func publishLineupLinks(liveId: String, links: [String: String]) {
        guard !links.isEmpty else { return }
        var fields: [String: Any] = [:]
        for (spot, hitter) in links where !hitter.isEmpty {
            fields["\(LiveLineupLinks.field).\(spot)"] = hitter
        }
        updateLiveFields(liveId: liveId, fields: fields)
    }
}

extension AuthManager {

    /// The open live room for one of this user's games, if any: their
    /// rooms are listed in users/{uid}/liveSessions (owner-only), and the
    /// room itself says which game it's for and whether it's still open.
    func findOpenLiveRoom(ownerUid: String, gameId: String, completion: @escaping (String?) -> Void) {
        let db = Firestore.firestore()
        db.collection("users").document(ownerUid).collection("liveSessions").getDocuments { snap, error in
            let liveIds = (snap?.documents ?? []).map(\.documentID)
            if let error { debugLog("⚠️ findOpenLiveRoom:", error.localizedDescription) }
            guard !liveIds.isEmpty else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            var open: [(id: String, created: Date)] = []
            let group = DispatchGroup()
            for liveId in liveIds {
                group.enter()
                db.collection("liveGames").document(liveId).getDocument { roomSnap, _ in
                    defer { group.leave() }
                    guard let data = roomSnap?.data(),
                          data["ownerGameId"] as? String == gameId,
                          data["status"] as? String == "active" else { return }
                    if let expires = (data["expiresAt"] as? Timestamp)?.dateValue(), expires <= Date() { return }
                    let created = (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
                    DispatchQueue.main.async { open.append((liveId, created)) }
                }
            }
            group.notify(queue: .main) {
                // The appends above hop to main too; let them land first.
                DispatchQueue.main.async {
                    completion(open.max(by: { $0.created < $1.created })?.id)
                }
            }
        }
    }

    /// Sets a game's opponent team - a targeted write, never `saveGame`
    /// (whose struct may hold a stale lineup).
    func setGameAwayTeam(ownerUid: String, gameId: String, teamId: String, opponentName: String, completion: @escaping (Error?) -> Void) {
        Firestore.firestore()
            .collection("users").document(ownerUid).collection("games").document(gameId)
            .updateData(["awayTeamId": teamId, "opponent": opponentName]) { error in
                DispatchQueue.main.async { completion(error) }
            }
    }

    /// Add to Game, start to finish: roster rows for new players, then
    /// the lineup wherever `route` says. Completion gets a message when
    /// anything couldn't be added (nil when everything was).
    func addScannedLineup(
        teamId: String,
        decisions: [LineupScanDecision],
        roster: [TeamPlayer],
        alreadyInLineup: Set<String>,
        route: LineupScanRoute,
        ownerUid: String,
        gameId: String?,
        liveId: String?,
        completion: @escaping (String?) -> Void
    ) {
        let plan = LineupScanPlan.make(decisions, alreadyInLineup: alreadyInLineup)
        var rowIdByHitter: [String: String] = [:]
        for player in roster {
            if let hitterId = player.hitterId, let id = player.id { rowIdByHitter[hitterId] = id }
        }
        resolveScanPlan(teamId: teamId, plan: plan, existingTeamPlayerIds: rowIdByHitter) { entries, failed in
            func finish(_ error: Error?) {
                var problems: [String] = []
                if failed > 0 { problems.append("\(failed) new player\(failed == 1 ? "" : "s") couldn't be added to the roster.") }
                if let error { problems.append("The lineup couldn't be saved: \(error.localizedDescription)") }
                completion(problems.isEmpty ? nil : problems.joined(separator: " "))
            }
            guard !entries.isEmpty else { finish(nil); return }

            func writeSavedGame(_ then: @escaping (Error?) -> Void) {
                guard let gameId else { then(nil); return }
                self.appendScannedLineupToSavedGame(ownerUid: ownerUid, gameId: gameId, entries: entries, completion: then)
            }

            switch route {
            case .savedGame:
                writeSavedGame(finish)
            case .liveRoom(let alsoSavedGame):
                guard let liveId else { finish(NSError(domain: "LiveGame", code: -3, userInfo: [NSLocalizedDescriptionKey: "The live game has ended"])); return }
                LiveGameService.shared.appendScannedLineup(liveId: liveId, entries: entries) { roomError in
                    guard alsoSavedGame else { finish(roomError); return }
                    writeSavedGame { gameError in finish(roomError ?? gameError) }
                }
            }
        }
    }
}
