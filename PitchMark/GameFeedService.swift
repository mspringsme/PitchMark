//
//  GameFeedService.swift
//  PitchMark
//
//  Firestore side of game feeds (phase 4, GameFeed.swift has the rules):
//  - team followers: the coach's follower code, joining with it (pending),
//    the coach approving or removing, switching feeds off for the team
//  - feeds: one per scorer per game (`<gameKey>_<uid>`), its settings, and
//    asking to follow / approving followers of a feed
//  - `GameFeedWriter`: the scorer's phone turning saved pitches into feed
//    events - new pitches written, edits rewritten, undos deleted
//
//  Followers are never team members (rules: TEAM FOLLOWERS). PitchMark
//  only - not in the Display target.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

struct GameFeedDoc: Identifiable, Equatable {
    var id: String
    var ownerUid: String
    var teamId: String
    var scheduledGameId: String
    var gameLabel: String
    var startsAt: Date?
    var title: String
    var kind: GameFeedKind
    var audience: GameFeedAudience
    var scope: GameFeedScope
    var showLastNames: Bool
    var ourScore: Int = 0
    var theirScore: Int = 0
    /// The scoreboard's names (the scorer's team, the other side).
    var ourName: String = ""
    var theirName: String = ""
    var inning: Int = 1
    var half: String? = nil
    var status: String = "live"

    init(id: String, ownerUid: String, teamId: String, scheduledGameId: String, gameLabel: String,
         startsAt: Date?, title: String, kind: GameFeedKind, audience: GameFeedAudience = .team,
         scope: GameFeedScope = .everything, showLastNames: Bool = false) {
        self.id = id
        self.ownerUid = ownerUid
        self.teamId = teamId
        self.scheduledGameId = scheduledGameId
        self.gameLabel = gameLabel
        self.startsAt = startsAt
        self.title = title
        self.kind = kind
        self.audience = audience
        self.scope = scope
        self.showLastNames = showLastNames
    }

    init?(id: String, data: [String: Any]) {
        guard let owner = data["ownerUid"] as? String, let teamId = data["teamId"] as? String,
              let game = data["scheduledGameId"] as? String else { return nil }
        self.id = id
        ownerUid = owner
        self.teamId = teamId
        scheduledGameId = game
        gameLabel = data["gameLabel"] as? String ?? ""
        startsAt = (data["startsAt"] as? Timestamp)?.dateValue()
        title = data["title"] as? String ?? "Feed"
        kind = GameFeedKind(rawValue: data["kind"] as? String ?? "") ?? .personal
        audience = GameFeedAudience(rawValue: data["audience"] as? String ?? "") ?? .nobody
        scope = GameFeedScope(rawValue: data["scope"] as? String ?? "") ?? .everything
        showLastNames = data["showLastNames"] as? Bool ?? false
        ourScore = data["ourScore"] as? Int ?? 0
        theirScore = data["theirScore"] as? Int ?? 0
        ourName = data["ourName"] as? String ?? ""
        theirName = data["theirName"] as? String ?? ""
        inning = data["inning"] as? Int ?? 1
        half = data["half"] as? String
        status = data["status"] as? String ?? "live"
    }

    var data: [String: Any] {
        var d: [String: Any] = [
            "ownerUid": ownerUid, "teamId": teamId, "scheduledGameId": scheduledGameId,
            "gameLabel": gameLabel, "title": title, "kind": kind.rawValue,
            "audience": audience.rawValue, "scope": scope.rawValue, "showLastNames": showLastNames,
            "ourScore": ourScore, "theirScore": theirScore, "inning": inning, "status": status,
            "ourName": String(ourName.prefix(40)), "theirName": String(theirName.prefix(40)),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let startsAt { d["startsAt"] = Timestamp(date: startsAt) }
        if let half { d["half"] = half }
        return d
    }
}

extension GameFeedEvent {
    init?(id: String, data: [String: Any]) {
        guard let at = (data["at"] as? Timestamp)?.dateValue() else { return nil }
        self.init(id: id, at: at, inning: data["inning"] as? Int ?? 1, half: data["half"] as? String,
                  batter: data["batter"] as? String ?? "", jersey: data["jersey"] as? String,
                  kind: data["kind"] as? String ?? "",
                  text: data["text"] as? String ?? "", runs: data["runs"] as? Int ?? 0,
                  detail: data["detail"] as? [String] ?? [],
                  batting: data["batting"] as? String, ourScore: data["ourScore"] as? Int,
                  theirScore: data["theirScore"] as? Int, outs: data["outs"] as? Int)
    }
}

/// A follower of a team, or of one feed.
struct FeedFollower: Identifiable, Equatable {
    var id: String { uid }
    var uid: String
    var name: String
    var approved: Bool
    var teamName: String? = nil
    var teamId: String? = nil
}

enum TeamJoinOutcome {
    case member(Team)
    /// Joined as a follower; the coach still has to approve.
    case followerPending(teamName: String)
}

enum GameFeedIds {
    /// The game a feed belongs to: its team schedule entry when it has one,
    /// so every scorer's feed for that game lands together.
    static func gameKey(scheduledGameId: String?, gameId: String) -> String {
        if let s = scheduledGameId, !s.isEmpty { return s }
        return "game-\(gameId)"
    }

    /// One feed per scorer per game.
    static func feedId(gameKey: String, uid: String) -> String {
        let clean = gameKey.replacingOccurrences(of: "/", with: "-")
        return "\(clean)_\(uid)"
    }
}

final class GameFeedService {
    static let shared = GameFeedService()
    private var db: Firestore { Firestore.firestore() }

    private func me() -> User? { Auth.auth().currentUser }

    private static func notSignedIn() -> NSError {
        NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
    }

    private static func displayName(_ user: User) -> String {
        TeamAccessRules.memberName(displayName: user.displayName, email: user.email) ?? "Follower"
    }

    // MARK: Team followers (coach)

    /// The team's reusable follower code; made on first use, or again on reset.
    func followerCode(teamId: String, teamName: String, reset: Bool,
                      completion: @escaping (Result<String, Error>) -> Void) {
        guard let user = me() else { return completion(.failure(Self.notSignedIn())) }
        let teamRef = db.collection("teams").document(teamId)
        teamRef.getDocument { snap, _ in
            let existing = snap?.data()?["followerInviteToken"] as? String
            if !reset, let existing, !existing.isEmpty { return completion(.success(existing)) }
            let token = Self.randomToken()
            let data: [String: Any] = [
                "teamId": teamId, "teamName": teamName, "roles": [TeamRole.follower.rawValue],
                "createdByUid": user.uid, "createdAt": FieldValue.serverTimestamp(),
                "expiresAt": Timestamp(date: Date().addingTimeInterval(TeamAccessRules.inviteLifetime(multiUse: true))),
                "multiUse": true
            ]
            self.db.collection("teamInviteTokens").document(token).setData(data) { error in
                if let error { return completion(.failure(error)) }
                if let existing, !existing.isEmpty {
                    self.db.collection("teamInviteTokens").document(existing).delete()
                }
                teamRef.setData(["followerInviteToken": token], merge: true) { error in
                    error.map { completion(.failure($0)) } ?? completion(.success(token))
                }
            }
        }
    }

    func loadTeamFollowers(teamId: String, completion: @escaping ([FeedFollower]) -> Void) {
        db.collection("teams").document(teamId).collection("followers").getDocuments { snap, _ in
            completion((snap?.documents ?? []).map { Self.follower(id: $0.documentID, $0.data()) })
        }
    }

    func setTeamFollower(teamId: String, uid: String, approved: Bool,
                         completion: @escaping (Error?) -> Void = { _ in }) {
        let ref = db.collection("teams").document(teamId).collection("followers").document(uid)
        if approved {
            ref.updateData(["status": "approved", "approvedAt": FieldValue.serverTimestamp()], completion: completion)
        } else {
            ref.delete(completion: completion)
        }
    }

    func followerFeedsOff(teamId: String, completion: @escaping (Bool) -> Void) {
        db.collection("teams").document(teamId).getDocument { snap, _ in
            completion(snap?.data()?["followerFeedsOff"] as? Bool ?? false)
        }
    }

    func setFollowerFeedsOff(teamId: String, off: Bool, completion: @escaping (Error?) -> Void = { _ in }) {
        db.collection("teams").document(teamId).setData(["followerFeedsOff": off], merge: true, completion: completion)
    }

    // MARK: Joining with a code (members and followers)

    /// A team link or code: a follower code makes a pending follower; any
    /// other goes through the member invite as before.
    func join(token: String, authManager: AuthManager, completion: @escaping (Result<TeamJoinOutcome, Error>) -> Void) {
        guard let user = me() else { return completion(.failure(Self.notSignedIn())) }
        db.collection("teamInviteTokens").document(token).getDocument { snap, error in
            if let error { return completion(.failure(error)) }
            let data = snap?.data() ?? [:]
            let roles = data["roles"] as? [String] ?? []
            guard roles == [TeamRole.follower.rawValue], let teamId = data["teamId"] as? String else {
                authManager.redeemTeamInviteToken(token) { result in
                    completion(result.map { .member($0) })
                }
                return
            }
            if let expiresAt = (data["expiresAt"] as? Timestamp)?.dateValue(), expiresAt <= Date() {
                return completion(.failure(NSError(domain: "Invite", code: 410,
                    userInfo: [NSLocalizedDescriptionKey: "This link has expired. Ask the coach for a new one."])))
            }
            let teamName = data["teamName"] as? String ?? "the team"
            let ref = self.db.collection("teams").document(teamId).collection("followers").document(user.uid)
            ref.getDocument { existing, _ in
                if existing?.exists == true {
                    // Already asked (or approved) - nothing to write.
                    return completion(.success(.followerPending(teamName: teamName)))
                }
                ref.setData([
                    "uid": user.uid, "name": Self.displayName(user), "teamName": teamName,
                    "status": "pending", "inviteToken": token, "joinedAt": FieldValue.serverTimestamp()
                ]) { error in
                    error.map { completion(.failure($0)) } ?? completion(.success(.followerPending(teamName: teamName)))
                }
            }
        }
    }

    /// The teams this account follows (pending or approved).
    func myFollowedTeams(completion: @escaping ([FeedFollower]) -> Void) {
        guard let user = me() else { return completion([]) }
        db.collectionGroup("followers").whereField("uid", isEqualTo: user.uid).getDocuments { snap, error in
            if let error { debugLog("⚠️ followed teams:", error.localizedDescription) }
            completion((snap?.documents ?? []).map { doc in
                var f = Self.follower(id: doc.documentID, doc.data())
                f.teamId = doc.reference.parent.parent?.documentID
                return f
            })
        }
    }

    func leaveTeam(teamId: String, completion: @escaping (Error?) -> Void = { _ in }) {
        guard let user = me() else { return completion(Self.notSignedIn()) }
        db.collection("teams").document(teamId).collection("followers").document(user.uid).delete(completion: completion)
    }

    // MARK: Feeds

    func loadFeed(id: String, completion: @escaping (GameFeedDoc?) -> Void) {
        db.collection("gameFeeds").document(id).getDocument { snap, _ in
            completion(snap.flatMap { s in s.data().flatMap { GameFeedDoc(id: s.documentID, data: $0) } })
        }
    }

    func saveFeed(_ feed: GameFeedDoc, completion: @escaping (Error?) -> Void = { _ in }) {
        var data = feed.data
        data["createdAt"] = FieldValue.serverTimestamp()
        db.collection("gameFeeds").document(feed.id).setData(data, merge: true, completion: completion)
    }

    /// A team's feeds (for the follower's game list).
    func listenFeeds(teamId: String, onChange: @escaping ([GameFeedDoc]) -> Void) -> ListenerRegistration {
        db.collection("gameFeeds").whereField("teamId", isEqualTo: teamId).addSnapshotListener { snap, error in
            if let error { debugLog("⚠️ team feeds:", error.localizedDescription) }
            onChange((snap?.documents ?? []).compactMap { GameFeedDoc(id: $0.documentID, data: $0.data()) })
        }
    }

    func listenEvents(feedId: String, onChange: @escaping ([GameFeedEvent]?) -> Void) -> ListenerRegistration {
        db.collection("gameFeeds").document(feedId).collection("events").addSnapshotListener { snap, error in
            if error != nil { return onChange(nil) }
            onChange((snap?.documents ?? []).compactMap { GameFeedEvent(id: $0.documentID, data: $0.data()) })
        }
    }

    // MARK: Following one feed

    /// This account's standing with a feed: nil (not asked), false (asked), true (approved).
    func myFeedStatus(feedId: String, completion: @escaping (Bool?) -> Void) {
        guard let user = me() else { return completion(nil) }
        db.collection("gameFeeds").document(feedId).collection("feedFollowers").document(user.uid).getDocument { snap, _ in
            guard let data = snap?.data() else { return completion(nil) }
            completion(data["status"] as? String == "approved")
        }
    }

    func askToFollow(feedId: String, completion: @escaping (Error?) -> Void) {
        guard let user = me() else { return completion(Self.notSignedIn()) }
        db.collection("gameFeeds").document(feedId).collection("feedFollowers").document(user.uid).setData([
            "uid": user.uid, "name": Self.displayName(user), "status": "requested",
            "requestedAt": FieldValue.serverTimestamp()
        ], completion: completion)
    }

    func listenFeedFollowers(feedId: String, onChange: @escaping ([FeedFollower]) -> Void) -> ListenerRegistration {
        db.collection("gameFeeds").document(feedId).collection("feedFollowers").addSnapshotListener { snap, _ in
            onChange((snap?.documents ?? []).map { Self.follower(id: $0.documentID, $0.data()) })
        }
    }

    func setFeedFollower(feedId: String, uid: String, approved: Bool) {
        let ref = db.collection("gameFeeds").document(feedId).collection("feedFollowers").document(uid)
        if approved {
            ref.updateData(["status": "approved", "approvedAt": FieldValue.serverTimestamp()])
        } else {
            ref.delete()
        }
    }

    // MARK: Writing events (scorer)

    func apply(feedId: String, write: [GameFeedEvent], delete: [String], completion: @escaping (Error?) -> Void) {
        guard !write.isEmpty || !delete.isEmpty else { return completion(nil) }
        // Every write is to this one feed's events, under one rule - one
        // batch is safe here (unlike a pitch's copies, CLAUDE.md).
        let events = db.collection("gameFeeds").document(feedId).collection("events")
        let batch = db.batch()
        for event in write.prefix(450) {
            var data = event.firestoreData
            data["at"] = Timestamp(date: event.at)
            data["updatedAt"] = FieldValue.serverTimestamp()
            batch.setData(data, forDocument: events.document(event.id))
        }
        for id in delete.prefix(max(0, 450 - write.count)) {
            batch.deleteDocument(events.document(id))
        }
        batch.commit(completion: completion)
    }

    func loadEvents(feedId: String, completion: @escaping ([GameFeedEvent]) -> Void) {
        db.collection("gameFeeds").document(feedId).collection("events").getDocuments { snap, _ in
            completion((snap?.documents ?? []).compactMap { GameFeedEvent(id: $0.documentID, data: $0.data()) })
        }
    }

    func updateScoreboard(feedId: String, ourScore: Int, theirScore: Int, inning: Int, half: String?,
                          ourName: String = "", theirName: String = "") {
        var data: [String: Any] = ["ourScore": ourScore, "theirScore": theirScore, "inning": inning,
                                   "updatedAt": FieldValue.serverTimestamp()]
        if !ourName.isEmpty { data["ourName"] = String(ourName.prefix(40)) }
        if !theirName.isEmpty { data["theirName"] = String(theirName.prefix(40)) }
        if let half { data["half"] = half }
        db.collection("gameFeeds").document(feedId).updateData(data)
    }

    // MARK: Helpers

    private static func follower(id: String, _ data: [String: Any]) -> FeedFollower {
        FeedFollower(uid: data["uid"] as? String ?? id, name: data["name"] as? String ?? "Follower",
                     approved: data["status"] as? String == "approved", teamName: data["teamName"] as? String)
    }

    private static func randomToken() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<12).map { _ in alphabet.randomElement()! })
    }
}

/// The scorer's phone keeping its feed in step with the game's pitches.
@MainActor
final class GameFeedWriter: ObservableObject {
    static let shared = GameFeedWriter()

    @Published private(set) var feed: GameFeedDoc?
    private var written: [String: GameFeedEvent] = [:]
    /// The inning/half each pitch was first seen in - a pitch doesn't store
    /// them, and an edit later in the game must keep the original inning.
    private var placeById: [String: GameFeedRules.Situation] = [:]
    private var attachedFeedId: String?
    private var isLoaded = false
    private var lastScoreboard: [Int] = []
    /// The plays the last sync wanted, this session - the only ones a later
    /// sync may delete (GameFeedRules.diff).
    private var lastWantedIds: Set<String>? = nil

    /// The scorer's own players for "only my players" - picked in the feed
    /// sheet, kept on this phone per feed.
    func myHitterIds(feedId: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "gameFeed.myPlayers.\(feedId)") ?? [])
    }

    func setMyHitterIds(_ ids: Set<String>, feedId: String) {
        UserDefaults.standard.set(Array(ids), forKey: "gameFeed.myPlayers.\(feedId)")
    }

    /// Looks for this scorer's feed for the open game.
    func attach(feedId: String?) {
        guard feedId != attachedFeedId else { return }
        attachedFeedId = feedId
        feed = nil
        written = [:]
        placeById = [:]
        isLoaded = false
        lastScoreboard = []
        lastWantedIds = nil
        guard let feedId else { return }
        GameFeedService.shared.loadFeed(id: feedId) { [weak self] doc in
            guard let doc else { return }
            GameFeedService.shared.loadEvents(feedId: feedId) { events in
                Task { @MainActor in
                    guard let self, self.attachedFeedId == feedId else { return }
                    self.written = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
                    for e in events {
                        self.placeById[e.id] = GameFeedRules.Situation(
                            inning: e.inning, half: e.half, batting: e.batting,
                            ourScore: e.ourScore, theirScore: e.theirScore, outs: e.outs)
                    }
                    self.feed = doc
                    self.isLoaded = true
                }
            }
        }
    }

    /// The feed was just started or its settings changed in the sheet.
    func feedSaved(_ doc: GameFeedDoc) {
        if attachedFeedId != doc.id {
            attachedFeedId = doc.id
            written = [:]
            placeById = [:]
        }
        feed = doc
        isLoaded = true
    }

    struct GameState {
        var pitches: [PitchEvent]
        var inning: Int
        var half: String?
        /// Batter names by the pitch's `opponentBatterId`.
        var names: [String: String]
        var ourScore: Int
        var theirScore: Int
        var outs: Int = 0
        /// The batting side's name, and the scoreboard's two names.
        var batting: String = ""
        var ourName: String = ""
        var theirName: String = ""
    }

    func sync(_ state: GameState) {
        guard isLoaded, let feed, feed.ownerUid == Auth.auth().currentUser?.uid else { return }
        // A game closing or reloading empties the list for a moment - that's
        // not every pitch being undone.
        guard !state.pitches.isEmpty else { return }
        let mine = myHitterIds(feedId: feed.id)
        let now = GameFeedRules.Situation(inning: state.inning, half: state.half,
                                          batting: state.batting.isEmpty ? nil : state.batting,
                                          ourScore: state.ourScore, theirScore: state.theirScore, outs: state.outs)
        // Each pitch keeps the board from when this phone first saw it;
        // `boards` then floors it by the pitch before (GameFeedRules).
        let ordered = state.pitches.filter { ($0.id ?? "").isEmpty == false }.sorted { $0.timestamp < $1.timestamp }
        var seen: [(id: String, situation: GameFeedRules.Situation, outsMade: Int, runs: Int)] = []
        for pitch in ordered {
            let id = pitch.id ?? ""
            let place = placeById[id] ?? now
            placeById[id] = place
            seen.append((id, place, GameFeedRules.outsMade(by: pitch), pitch.play?.runs ?? 0))
        }
        let boards = GameFeedRules.boards(seen, ourName: state.ourName)
        var wanted: [GameFeedEvent] = []
        for pitch in ordered {
            guard let id = pitch.id, let board = boards[id],
                  GameFeedRules.shares(pitch, scope: feed.scope, myHitterIds: mine) else { continue }
            let name = pitch.opponentBatterId.flatMap { state.names[$0] }
            wanted.append(GameFeedRules.event(from: pitch, id: id, situation: board,
                                              batterName: name, showLastNames: feed.showLastNames))
        }
        let diff = GameFeedRules.diff(current: written, wanted: wanted, lastWantedIds: lastWantedIds)
        lastWantedIds = Set(wanted.map(\.id))
        if !diff.write.isEmpty || !diff.delete.isEmpty {
            for e in diff.write { written[e.id] = e }
            for id in diff.delete { written[id] = nil }
            GameFeedService.shared.apply(feedId: feed.id, write: diff.write, delete: diff.delete) { error in
                if let error { debugLog("⚠️ feed events:", error.localizedDescription) }
            }
        }
        let board = [state.ourScore, state.theirScore, state.inning, state.half == "top" ? 0 : 1,
                     state.ourName.hashValue, state.theirName.hashValue]
        if board != lastScoreboard {
            lastScoreboard = board
            GameFeedService.shared.updateScoreboard(feedId: feed.id, ourScore: state.ourScore,
                                                    theirScore: state.theirScore, inning: state.inning, half: state.half,
                                                    ourName: state.ourName, theirName: state.theirName)
        }
    }
}
