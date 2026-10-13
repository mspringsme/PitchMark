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

    /// Creates the Player doc, and - only when the role calls for it -
    /// a real linked Pitcher and/or Hitter, so stats work exactly like the
    /// existing Pitcher machinery. `positions`/`battingSide` are stored on
    /// the Player as the default a newly linked team starts from; editing
    /// them on a specific team's roster entry afterward is team-local only
    /// (see `updateTeamPlayer`), not pushed back here.
    func createPlayer(
        name: String,
        role: PlayerRole,
        positions: [FieldPosition]? = nil,
        battingSide: BattingSide? = nil,
        completion: @escaping (Result<Player, Error>) -> Void
    ) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        func savePlayer(pitcherId: String?, hitterId: String?) {
            let ref = playersCollection().document()
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
                    } else {
                        completion(.success(player))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }

        func createHitterIfNeeded(pitcherId: String?) {
            if role.includesHitter {
                createHitter(name: name) { hitter in
                    savePlayer(pitcherId: pitcherId, hitterId: hitter?.id)
                }
            } else {
                savePlayer(pitcherId: pitcherId, hitterId: nil)
            }
        }

        if role.includesPitcher {
            createPitcher(name: name, templateId: nil) { pitcher in
                createHitterIfNeeded(pitcherId: pitcher?.id)
            }
        } else {
            createHitterIfNeeded(pitcherId: nil)
        }
    }
}
