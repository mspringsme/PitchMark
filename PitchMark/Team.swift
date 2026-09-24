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

// MARK: - Debug-only exercise UI (temporary; deleted once Phase 2/3 land)

#if DEBUG
struct DebugTeamsSection: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var newTeamName: String = ""
    @State private var myTeams: [(team: Team, membership: TeamMembership)] = []
    @State private var statusMessage: String? = nil
    @State private var inviteTokenToRedeem: String = ""
    @State private var generatedTokensByTeamId: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Debug: Teams")
                .font(.headline)

            HStack {
                TextField("New team name", text: $newTeamName)
                    .textFieldStyle(.roundedBorder)
                Button("Create") {
                    createTeam()
                }
                .disabled(newTeamName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Button("Refresh My Teams") {
                refreshTeams()
            }

            ForEach(myTeams, id: \.team.id) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(entry.team.name) — \(entry.membership.roles.map { $0.displayName }.joined(separator: ", "))")
                        .font(.subheadline)
                        .bold()
                    if let teamId = entry.team.id {
                        HStack {
                            Button("Generate Invite") {
                                generateInvite(teamId: teamId)
                            }
                            if let token = generatedTokensByTeamId[teamId] {
                                Text(token)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                TextField("Invite token to redeem", text: $inviteTokenToRedeem)
                    .textFieldStyle(.roundedBorder)
                Button("Redeem") {
                    redeemInvite()
                }
                .disabled(inviteTokenToRedeem.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { refreshTeams() }
    }

    private func createTeam() {
        let name = newTeamName.trimmingCharacters(in: .whitespaces)
        authManager.createTeam(name: name) { result in
            switch result {
            case .success:
                newTeamName = ""
                statusMessage = "Created team \"\(name)\""
                refreshTeams()
            case .failure(let error):
                statusMessage = "Create failed: \(error.localizedDescription)"
            }
        }
    }

    private func refreshTeams() {
        authManager.loadMyTeams { teams, error in
            myTeams = teams
            if let error {
                statusMessage = "Refresh failed: \(error.localizedDescription)"
            } else if teams.isEmpty {
                statusMessage = "No teams found for this account."
            } else {
                statusMessage = nil
            }
        }
    }

    private func generateInvite(teamId: String) {
        authManager.createTeamInviteToken(teamId: teamId, roles: [.parent]) { result in
            switch result {
            case .success(let token):
                generatedTokensByTeamId[teamId] = token
                statusMessage = "Invite generated for \(teamId)"
            case .failure(let error):
                statusMessage = "Invite failed: \(error.localizedDescription)"
            }
        }
    }

    private func redeemInvite() {
        let token = inviteTokenToRedeem.trimmingCharacters(in: .whitespaces)
        authManager.redeemTeamInviteToken(token) { result in
            switch result {
            case .success(let team):
                statusMessage = "Joined team \"\(team.name)\""
                inviteTokenToRedeem = ""
                refreshTeams()
            case .failure(let error):
                statusMessage = "Redeem failed: \(error.localizedDescription)"
            }
        }
    }
}
#endif
