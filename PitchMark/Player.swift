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
