//
//  Hitter.swift
//  PitchMark
//
//  The Hitter stats entity - mirrors Pitcher's cross-game pattern
//  (Utilities.swift) but deliberately simpler: ownerUid-only, no
//  sharedWith/claimedByUid. A Hitter's pitchEvents collection accumulates
//  PitchEvent rows the same shape as a Pitcher's does, just filtered by
//  `hitterId` instead of `pitcherId`, so the same StrikeZoneHeatmapView and
//  filtering patterns apply unchanged.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct Hitter: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var ownerUid: String
    var createdAt: Date? = nil
}

// MARK: - AuthManager CRUD

extension AuthManager {
    private func hittersCollection() -> CollectionReference {
        Firestore.firestore().collection("hitters")
    }

    func createHitter(name: String, completion: @escaping (Hitter?) -> Void) {
        guard let user = user else {
            debugLog("⚠️ createHitter: user=nil")
            completion(nil)
            return
        }

        let ref = hittersCollection().document()
        let hitter = Hitter(id: ref.documentID, name: name, ownerUid: user.uid, createdAt: Date())

        do {
            try ref.setData(from: hitter) { err in
                if let err {
                    debugLog("❌ createHitter failed:", err.localizedDescription)
                    completion(nil)
                } else {
                    completion(hitter)
                }
            }
        } catch {
            debugLog("❌ createHitter encode failed:", error.localizedDescription)
            completion(nil)
        }
    }

    /// Name-only merge write, so a rename made anywhere reaches the Hitter
    /// doc without touching anything else on it. See
    /// `propagatePlayerRename` (Player.swift) for why a rename has four
    /// documents to visit.
    func updateHitterName(id: String, name: String, completion: (() -> Void)? = nil) {
        guard user != nil else {
            completion?()
            return
        }
        hittersCollection().document(id).setData(["name": name], merge: true) { error in
            if let error {
                debugLog("⚠️ updateHitterName failed:", error.localizedDescription)
            }
            completion?()
        }
    }

    func loadHitters(completion: @escaping ([Hitter]) -> Void) {
        guard let user = user else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        hittersCollection()
            .whereField("ownerUid", isEqualTo: user.uid)
            .getDocuments { snapshot, error in
                if let error {
                    debugLog("❌ loadHitters error:", error.localizedDescription)
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                let hitters = (snapshot?.documents ?? []).compactMap { try? $0.data(as: Hitter.self) }
                DispatchQueue.main.async { completion(hitters) }
            }
    }

    func loadHitterEvents(hitterId: String, completion: @escaping ([PitchEvent]) -> Void) {
        let ref = hittersCollection().document(hitterId).collection("pitchEvents")

        ref.order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                if let error {
                    debugLog("❌ loadHitterEvents error:", error.localizedDescription)
                    completion([])
                    return
                }
                let events: [PitchEvent] = snapshot?.documents.compactMap { doc in
                    PitchEvent.decodeFirestoreDocument(doc)
                } ?? []
                completion(events)
            }
    }

    func saveSharedHitterEvent(hitterId: String, event: PitchEvent) {
        let docId: String? = {
            let raw = event.id?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty == false) ? raw : nil
        }()

        let ref = hittersCollection().document(hitterId).collection("pitchEvents").document(docId ?? UUID().uuidString)

        do {
            var enriched = event
            enriched.hitterId = hitterId
            enriched.createdByUid = Auth.auth().currentUser?.uid
            try ref.setData(from: enriched) { err in
                if let err {
                    debugLog("❌ saveSharedHitterEvent failed:", err.localizedDescription)
                } else {
                    debugLog("✅ Shared hitter event saved.")
                }
            }
        } catch {
            debugLog("❌ saveSharedHitterEvent encode failed:", error.localizedDescription)
        }
    }
}
