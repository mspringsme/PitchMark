//
//  Team.swift
//  PitchMark
//
//  Phase 1 of the Team/Player/Role foundation described in the 2026-09-24
//  product direction (Coach / Parent / Family). Deliberately kept out of the
//  "Pitchmark Display" target's membershipExceptions in project.pbxproj —
//  Display never needs any of this.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Models

enum TeamRole: String, Codable, CaseIterable {
    case coach
    case parent
    case assistant

    var displayName: String {
        switch self {
        case .coach: return "Coach"
        case .parent: return "Parent"
        case .assistant: return "Assistant"
        }
    }
}

struct Team: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var createdByUid: String
    var createdAt: Date = Date()
    var archivedAt: Date? = nil
}

/// Doc id == the member's uid. `uid` is also stored as a plain field so the
/// "my teams" lookup can run as a collectionGroup query constrained by
/// `request.query.where("uid", "==", ...)`, matching the query-constraint
/// pattern firestore.rules already uses for joinCodes/inviteTokens.
struct TeamMembership: Identifiable, Codable {
    @DocumentID var id: String?
    var uid: String
    var roles: [TeamRole]
    var linkedPlayerIds: [String] = []
    var joinedAt: Date = Date()
    var addedByUid: String
}

/// A team's roster entry. Separate from `Pitcher` on purpose: a player who
/// doesn't pitch has no `pitcherId`, and a player who does keeps using the
/// existing Pitcher/pitchEvents/stats machinery untouched via that link.
struct TeamPlayer: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var jerseyNumber: String? = nil
    var pitcherId: String? = nil
    // The canonical cross-team identity (Player.swift) - the same Player can
    // be linked from a TeamPlayer row on more than one Team, which is what
    // lets one kid's stats span multiple seasons/teams. `pitcherId` above
    // stays a denormalized copy of Player.pitcherId so every existing
    // pitcherId-filtering call site (PitchTrackerView's away-roster picker
    // in particular) needs zero changes.
    var playerId: String? = nil
    var role: PlayerRole? = nil
    var createdByUid: String
    var createdAt: Date = Date()
    var archivedAt: Date? = nil
}

// MARK: - AuthManager CRUD

extension AuthManager {
    private func teamsCollection() -> CollectionReference {
        Firestore.firestore().collection("teams")
    }

    func createTeam(name: String, completion: @escaping (Result<Team, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let ref = teamsCollection().document()
        let team = Team(id: ref.documentID, name: name, createdByUid: user.uid, createdAt: Date())

        do {
            try ref.setData(from: team) { error in
                if let error {
                    completion(.failure(error))
                    return
                }
                let membership = TeamMembership(
                    id: user.uid,
                    uid: user.uid,
                    roles: [.coach],
                    joinedAt: Date(),
                    addedByUid: user.uid
                )
                do {
                    try ref.collection("members").document(user.uid).setData(from: membership) { memberError in
                        if let memberError {
                            completion(.failure(memberError))
                        } else {
                            completion(.success(team))
                        }
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    func loadMyTeams(completion: @escaping ([(team: Team, membership: TeamMembership)], Error?) -> Void) {
        guard let user = user else {
            debugLog("⚠️ loadMyTeams: user=nil")
            DispatchQueue.main.async { completion([], nil) }
            return
        }

        Firestore.firestore().collectionGroup("members")
            .whereField("uid", isEqualTo: user.uid)
            .getDocuments { snapshot, error in
                if let error {
                    debugLog("❌ loadMyTeams (members) error:", error.localizedDescription)
                    DispatchQueue.main.async { completion([], error) }
                    return
                }

                let memberDocs = snapshot?.documents ?? []
                guard !memberDocs.isEmpty else {
                    DispatchQueue.main.async { completion([], nil) }
                    return
                }

                let group = DispatchGroup()
                var results: [(team: Team, membership: TeamMembership)] = []
                let lock = NSLock()

                for doc in memberDocs {
                    guard let membership = try? doc.data(as: TeamMembership.self),
                          let teamRef = doc.reference.parent.parent else { continue }

                    group.enter()
                    teamRef.getDocument { teamSnap, teamError in
                        defer { group.leave() }
                        if let teamError {
                            debugLog("❌ loadMyTeams (team) error:", teamError.localizedDescription)
                            return
                        }
                        guard let teamSnap, let team = try? teamSnap.data(as: Team.self) else { return }
                        lock.lock()
                        results.append((team, membership))
                        lock.unlock()
                    }
                }

                group.notify(queue: .main) {
                    completion(results, nil)
                }
            }
    }

    func loadTeamMembers(teamId: String, completion: @escaping ([TeamMembership]) -> Void) {
        teamsCollection().document(teamId).collection("members")
            .getDocuments { snapshot, error in
                if let error {
                    debugLog("❌ loadTeamMembers error:", error.localizedDescription)
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                let members = (snapshot?.documents ?? []).compactMap { try? $0.data(as: TeamMembership.self) }
                DispatchQueue.main.async { completion(members) }
            }
    }

    func loadTeamPlayers(teamId: String, completion: @escaping ([TeamPlayer]) -> Void) {
        teamsCollection().document(teamId).collection("players")
            .getDocuments { snapshot, error in
                if let error {
                    debugLog("❌ loadTeamPlayers error:", error.localizedDescription)
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                let players = (snapshot?.documents ?? []).compactMap { try? $0.data(as: TeamPlayer.self) }
                DispatchQueue.main.async { completion(players) }
            }
    }

    func addTeamPlayer(teamId: String, name: String, jerseyNumber: String?, pitcherId: String?, completion: @escaping (Result<TeamPlayer, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let ref = teamsCollection().document(teamId).collection("players").document()
        let player = TeamPlayer(
            id: ref.documentID,
            name: name,
            jerseyNumber: jerseyNumber,
            pitcherId: pitcherId,
            createdByUid: user.uid,
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

    /// Creates a real `Pitcher` doc and adds a `TeamPlayer` linked to it in
    /// one step, so a player added to a roster this way actually shows up
    /// anywhere pitchers are picked from - the plain `addTeamPlayer` above
    /// (pitcherId: nil) does not.
    func addTeamPlayerWithLinkedPitcher(
        teamId: String,
        name: String,
        jerseyNumber: String?,
        completion: @escaping (Result<TeamPlayer, Error>) -> Void
    ) {
        createPitcher(name: name, templateId: nil) { pitcher in
            guard let pitcher, let pitcherId = pitcher.id else {
                completion(.failure(NSError(domain: "Team", code: 500, userInfo: [NSLocalizedDescriptionKey: "Couldn't create a pitcher for this player."])))
                return
            }
            self.addTeamPlayer(teamId: teamId, name: name, jerseyNumber: jerseyNumber, pitcherId: pitcherId, completion: completion)
        }
    }

    /// "Create new" path for TeamRosterView's Add Player flow - creates a
    /// real cross-team `Player` (plus a linked Pitcher when the role calls
    /// for one, via `createPlayer`) and a `TeamPlayer` row on this team
    /// pointing at it.
    func addTeamPlayerCreatingNewPlayer(
        teamId: String,
        name: String,
        jerseyNumber: String?,
        role: PlayerRole,
        completion: @escaping (Result<TeamPlayer, Error>) -> Void
    ) {
        createPlayer(name: name, role: role) { result in
            switch result {
            case .success(let player):
                self.addTeamPlayerLinkingPlayer(teamId: teamId, player: player, jerseyNumber: jerseyNumber, role: role, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// "Link existing player" path - the actual cross-team mechanism. Name/
    /// pitcherId/role are copied from the existing `Player` (so this team's
    /// picker filtering keeps working unchanged); only the jersey number is
    /// team-specific.
    func addTeamPlayerLinkingPlayer(
        teamId: String,
        player: Player,
        jerseyNumber: String?,
        role: PlayerRole?,
        completion: @escaping (Result<TeamPlayer, Error>) -> Void
    ) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }
        let ref = teamsCollection().document(teamId).collection("players").document()
        let teamPlayer = TeamPlayer(
            id: ref.documentID,
            name: player.name,
            jerseyNumber: jerseyNumber,
            pitcherId: player.pitcherId,
            playerId: player.id,
            role: role,
            createdByUid: user.uid,
            createdAt: Date()
        )
        do {
            try ref.setData(from: teamPlayer) { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(teamPlayer))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    func updateTeamPlayer(teamId: String, playerId: String, name: String, jerseyNumber: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        guard user != nil else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }
        var data: [String: Any] = ["name": name]
        if let jerseyNumber, !jerseyNumber.isEmpty {
            data["jerseyNumber"] = jerseyNumber
        } else {
            data["jerseyNumber"] = FieldValue.delete()
        }
        teamsCollection().document(teamId).collection("players").document(playerId).updateData(data) { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    /// Only removes the roster entry - a linked Pitcher (and its pitch
    /// history) is left alone, same reasoning as team deletion below.
    func deleteTeamPlayer(teamId: String, playerId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard user != nil else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }
        teamsCollection().document(teamId).collection("players").document(playerId).delete { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func updateTeam(teamId: String, name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard user != nil else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }
        teamsCollection().document(teamId).updateData(["name": name]) { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    /// Blocked (not cascading) if the team still has players - the caller
    /// is expected to have already checked this and only call through when
    /// it's actually empty, but this re-checks server-side too rather than
    /// trusting a possibly-stale local `players` array.
    func deleteTeam(teamId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard user != nil else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }
        loadTeamPlayers(teamId: teamId) { players in
            guard players.isEmpty else {
                completion(.failure(NSError(domain: "Team", code: 409, userInfo: [NSLocalizedDescriptionKey: "Remove all players before deleting this team."])))
                return
            }
            self.teamsCollection().document(teamId).delete { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    /// Removes the signed-in user's own membership - the only team action a
    /// non-creator member has. Leaves the team doc, its players, and every
    /// other member untouched; firestore.rules permits a member to delete
    /// only their own membership doc, never anyone else's.
    func leaveTeam(teamId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }
        teamsCollection().document(teamId).collection("members").document(user.uid).delete { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func createTeamInviteToken(teamId: String, roles: [TeamRole], completion: @escaping (Result<String, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let token = randomToken(length: 12)
        let ref = Firestore.firestore().collection("teamInviteTokens").document(token)
        let data: [String: Any] = [
            "teamId": teamId,
            "roles": roles.map { $0.rawValue },
            "createdByUid": user.uid,
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: Date().addingTimeInterval(60 * 60 * 24 * 7))
        ]

        ref.setData(data) { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(token))
            }
        }
    }

    func redeemTeamInviteToken(_ token: String, completion: @escaping (Result<Team, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let db = Firestore.firestore()
        let tokenRef = db.collection("teamInviteTokens").document(token)
        tokenRef.getDocument { snap, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let snap, snap.exists,
                  let data = snap.data(),
                  let teamId = data["teamId"] as? String,
                  !teamId.isEmpty
            else {
                completion(.failure(NSError(domain: "Invite", code: 404, userInfo: [NSLocalizedDescriptionKey: "Invite not found."])))
                return
            }

            let roleStrings = data["roles"] as? [String] ?? ["parent"]
            let roles = roleStrings.compactMap { TeamRole(rawValue: $0) }

            let teamRef = db.collection("teams").document(teamId)
            let membership = TeamMembership(
                id: user.uid,
                uid: user.uid,
                roles: roles.isEmpty ? [.parent] : roles,
                joinedAt: Date(),
                addedByUid: (data["createdByUid"] as? String) ?? user.uid
            )

            do {
                try teamRef.collection("members").document(user.uid).setData(from: membership, merge: true) { memberError in
                    if let memberError {
                        completion(.failure(memberError))
                        return
                    }
                    teamRef.getDocument { teamSnap, teamError in
                        if let teamError {
                            completion(.failure(teamError))
                            return
                        }
                        guard let teamSnap, let team = try? teamSnap.data(as: Team.self) else {
                            completion(.failure(NSError(domain: "Invite", code: 404, userInfo: [NSLocalizedDescriptionKey: "Team not found."])))
                            return
                        }
                        completion(.success(team))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
}

