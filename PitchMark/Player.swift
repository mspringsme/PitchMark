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
                    self.addTeamPlayerLinkingPlayer(
                        teamId: teamId,
                        player: player,
                        jerseyNumber: jerseyNumber,
                        completion: completion
                    )
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
