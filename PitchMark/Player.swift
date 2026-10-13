//
//  Player.swift
//  PitchMark
//
//  A persistent identity that outlives any one Team - the fix for "this kid
//  on this season's roster is the same kid as last season's roster." A
//  TeamPlayer (Team.swift) links to one Player via `playerId`; the same
//  Player can be linked from TeamPlayer rows on multiple different Teams,
//  so that player's stats (via their linked Pitcher) naturally span every
//  team/season once you're looking at the Player rather than a single
//  team's roster entry.
//
//  `hitterId` is reserved now but unused until a Hitter stats entity exists
//  (not this phase) - picking Hitter or Both as a role today only records
//  intent on the TeamPlayer, nothing more.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

enum PlayerRole: String, Codable, CaseIterable {
    case pitcher
    case hitter
    case both

    var displayName: String {
        switch self {
        case .pitcher: return "Pitcher"
        case .hitter: return "Hitter"
        case .both: return "Both"
        }
    }

    var includesPitcher: Bool { self == .pitcher || self == .both }
    var includesHitter: Bool { self == .hitter || self == .both }
}

struct Player: Identifiable, Codable {
    @DocumentID var id: String?

    var name: String
    var ownerUid: String
    var pitcherId: String? = nil
    var hitterId: String? = nil
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

    /// Creates the Player doc, and - only when the role calls for it -
    /// a real linked Pitcher via the existing `createPitcher`, so pitching
    /// stats work exactly as they do today. Hitter/Both record the role but
    /// create nothing hitter-related yet (no Hitter entity exists).
    func createPlayer(name: String, role: PlayerRole, completion: @escaping (Result<Player, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        func savePlayer(pitcherId: String?) {
            let ref = playersCollection().document()
            let player = Player(id: ref.documentID, name: name, ownerUid: user.uid, pitcherId: pitcherId, createdAt: Date())
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

        if role.includesPitcher {
            createPitcher(name: name, templateId: nil) { pitcher in
                savePlayer(pitcherId: pitcher?.id)
            }
        } else {
            savePlayer(pitcherId: nil)
        }
    }
}
