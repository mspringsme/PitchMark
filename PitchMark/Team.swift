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

    // Designation (2026-10-21). Mandatory at every creation path, but the
    // five fields are genuinely Optional here because teams created before
    // the designation existed have none of them - a non-optional field (or
    // a hand-written Decodable init) would make those documents fail to
    // decode entirely and drop the team off "my teams". `designation`
    // returns nil for them and the UI simply shows no stamp.
    var seasonStart: TeamSeason? = nil
    var seasonEnd: TeamSeason? = nil
    var startYear: Int? = nil
    var ageGroup: TeamAgeGroup? = nil
    var division: TeamDivision? = nil

    /// All-or-nothing on purpose: a half-filled stamp ("16U" with no season)
    /// is worse than none, since the whole point is telling two same-named
    /// teams apart.
    var designation: TeamDesignation? {
        guard let seasonStart, let seasonEnd, let startYear, let ageGroup, let division else { return nil }
        return TeamDesignation(
            seasonStart: seasonStart,
            seasonEnd: seasonEnd,
            startYear: startYear,
            ageGroup: ageGroup,
            division: division
        )
    }

    /// "Reds · Fall–Winter '25–'26 · 16U · A", falling back to just the
    /// name for a pre-designation team.
    var displayNameWithDesignation: String {
        guard let designation else { return name }
        return "\(name) · \(designation.inlineText)"
    }
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
    // Denormalized copy of Player.hitterId, same reasoning as pitcherId.
    var hitterId: String? = nil
    // Positions/battingSide are seeded from the linked Player at creation/
    // link time, but edited here team-locally afterward (updateTeamPlayer) -
    // deliberately not pushed back to the canonical Player, since a kid can
    // legitimately play a different position on a different team.
    var positions: [FieldPosition]? = nil
    var battingSide: BattingSide? = nil
    var createdByUid: String
    var createdAt: Date = Date()
    var archivedAt: Date? = nil
}

// MARK: - AuthManager CRUD

extension AuthManager {
    private func teamsCollection() -> CollectionReference {
        Firestore.firestore().collection("teams")
    }

    /// `designation` is a required parameter, not an optional one: every
    /// creation path in the app (Home's Teams section, the tracker's Set My
    /// Team / Set Opponent Team sheets) collects all four choices before
    /// calling, so there is no way to mint a team without a stamp.
    func createTeam(name: String, designation: TeamDesignation, completion: @escaping (Result<Team, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let ref = teamsCollection().document()
        let team = Team(
            id: ref.documentID,
            name: name,
            createdByUid: user.uid,
            createdAt: Date(),
            seasonStart: designation.seasonStart,
            seasonEnd: designation.seasonEnd,
            startYear: designation.startYear,
            ageGroup: designation.ageGroup,
            division: designation.division
        )

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


    /// "Create new" path for TeamRosterView's Add Player flow - creates a
    /// real cross-team `Player` (with both a linked Pitcher and Hitter,
    /// always, via `createPlayer`) and a `TeamPlayer` row on this team
    /// pointing at it.
    func addTeamPlayerCreatingNewPlayer(
        teamId: String,
        name: String,
        jerseyNumber: String?,
        positions: [FieldPosition]? = nil,
        battingSide: BattingSide? = nil,
        completion: @escaping (Result<TeamPlayer, Error>) -> Void
    ) {
        createPlayer(name: name, positions: positions, battingSide: battingSide) { result in
            switch result {
            case .success(let player):
                self.addTeamPlayerLinkingPlayer(teamId: teamId, player: player, jerseyNumber: jerseyNumber, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// "Link existing player" path - the actual cross-team mechanism. Name/
    /// pitcherId/hitterId/positions/battingSide are all copied from the
    /// existing `Player` as this team's starting point (so this team's
    /// picker filtering keeps working unchanged); only the jersey number is
    /// team-specific. Positions/battingSide can then be edited team-locally
    /// afterward via `updateTeamPlayer`.
    func addTeamPlayerLinkingPlayer(
        teamId: String,
        player: Player,
        jerseyNumber: String?,
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
            hitterId: player.hitterId,
            positions: player.positions,
            battingSide: player.battingSide,
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

    /// Stamps a freshly minted `playerId` onto every roster row that links
    /// the same Pitcher but has no canonical identity yet, so the next team
    /// to link this kid links *that* Player instead of minting a second one.
    /// Best-effort: a roster row on a team someone else created isn't
    /// writable here (firestore.rules gates roster writes on
    /// `isTeamCreator`), and a denial is logged, not surfaced.
    func backfillPlayerIdOnRosterRows(playerId: String, pitcherId: String?, hitterId: String?) {
        guard let pitcherId else { return }
        loadMyTeams { entries, _ in
            for entry in entries {
                guard let teamId = entry.team.id else { continue }
                self.loadTeamPlayers(teamId: teamId) { rows in
                    for row in rows where row.pitcherId == pitcherId && row.playerId == nil {
                        guard let rowId = row.id else { continue }
                        var data: [String: Any] = ["playerId": playerId]
                        if row.hitterId == nil, let hitterId {
                            data["hitterId"] = hitterId
                        }
                        self.teamsCollection()
                            .document(teamId)
                            .collection("players")
                            .document(rowId)
                            .updateData(data) { error in
                                if let error {
                                    debugLog("⚠️ backfillPlayerIdOnRosterRows failed:", error.localizedDescription)
                                }
                            }
                    }
                }
            }
        }
    }

    /// Self-healing backfill for players created before every player always
    /// got both a Pitcher and Hitter: creates whichever is missing and
    /// writes it onto both this TeamPlayer row and (when linked) the
    /// canonical Player, so revisiting a roster is enough to fix it with no
    /// manual designation step. No-ops (completion called immediately) once
    /// both already exist - safe to call on every roster load.
    func ensureTeamPlayerHasPitcherAndHitter(teamId: String, teamPlayer: TeamPlayer, completion: @escaping (TeamPlayer) -> Void) {
        guard let rowId = teamPlayer.id else {
            completion(teamPlayer)
            return
        }
        guard teamPlayer.pitcherId == nil || teamPlayer.hitterId == nil else {
            completion(teamPlayer)
            return
        }

        func finish(pitcherId: String?, hitterId: String?) {
            var updated = teamPlayer
            updated.pitcherId = pitcherId
            updated.hitterId = hitterId
            var data: [String: Any] = [:]
            if let pitcherId { data["pitcherId"] = pitcherId }
            if let hitterId { data["hitterId"] = hitterId }
            guard !data.isEmpty else {
                completion(teamPlayer)
                return
            }
            self.teamsCollection().document(teamId).collection("players").document(rowId).updateData(data) { _ in
                completion(updated)
            }
            if let playerId = teamPlayer.playerId {
                Firestore.firestore().collection("players").document(playerId).updateData(data)
            }
        }

        if teamPlayer.pitcherId == nil {
            createPitcher(name: teamPlayer.name, templateId: nil) { pitcher in
                if teamPlayer.hitterId == nil {
                    self.createHitter(name: teamPlayer.name) { hitter in
                        finish(pitcherId: pitcher?.id, hitterId: hitter?.id)
                    }
                } else {
                    finish(pitcherId: pitcher?.id, hitterId: teamPlayer.hitterId)
                }
            }
        } else {
            createHitter(name: teamPlayer.name) { hitter in
                finish(pitcherId: teamPlayer.pitcherId, hitterId: hitter?.id)
            }
        }
    }

    func updateTeamPlayer(
        teamId: String,
        playerId: String,
        name: String,
        jerseyNumber: String?,
        positions: [FieldPosition]? = nil,
        battingSide: BattingSide? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
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
        if let positions, !positions.isEmpty {
            data["positions"] = positions.map { $0.rawValue }
        } else {
            data["positions"] = FieldValue.delete()
        }
        if let battingSide {
            data["battingSide"] = battingSide.rawValue
        } else {
            data["battingSide"] = FieldValue.delete()
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

    /// `designation` stays optional here (unlike `createTeam`) only so a
    /// plain rename of a pre-designation team doesn't have to invent one;
    /// passing a designation writes all five fields together.
    func updateTeam(teamId: String, name: String, designation: TeamDesignation? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard user != nil else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }
        var data: [String: Any] = ["name": name]
        if let designation {
            data["seasonStart"] = designation.seasonStart.rawValue
            data["seasonEnd"] = designation.seasonEnd.rawValue
            data["startYear"] = designation.startYear
            data["ageGroup"] = designation.ageGroup.rawValue
            data["division"] = designation.division.rawValue
        }
        teamsCollection().document(teamId).updateData(data) { error in
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

