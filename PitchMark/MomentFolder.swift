//
//  MomentFolder.swift
//  PitchMark
//
//  2026-10-04: lets the user organize Moments into folders they name
//  themselves (e.g. "2026 Reds 16U"), each optionally holding secondary
//  buckets (e.g. "Bradley Bash Tourney") - plain user-owned organization,
//  deliberately independent of the Team/TeamPlayer roster system
//  (Team.swift). Exactly two levels; no bucket-within-bucket.
//
//  `MomentBucket` carries no `folderId` field of its own - same
//  convention `TeamPlayer` already uses (it carries no `teamId` either):
//  the Firestore path already encodes the parent
//  (`users/{uid}/momentFolders/{folderId}/buckets/{bucketId}`).
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

struct MomentFolder: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var createdAt: Date = Date()
    /// 2026-10-05 - marks the one auto-created "Highlight Reels" folder
    /// (`getOrCreateHighlightReelsFolder`) so it's found by what it IS,
    /// not by matching its name - a user renaming it shouldn't spawn a
    /// second one on the next reel export. Nil/false for every ordinary,
    /// user-created folder.
    var isHighlightReelsFolder: Bool? = nil
}

struct MomentBucket: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var createdAt: Date = Date()
}

// MARK: - AuthManager CRUD

extension AuthManager {
    private func momentFoldersCollection(uid: String) -> CollectionReference {
        Firestore.firestore().collection("users").document(uid).collection("momentFolders")
    }

    func createMomentFolder(name: String, isHighlightReelsFolder: Bool = false, completion: @escaping (Result<MomentFolder, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let ref = momentFoldersCollection(uid: user.uid).document()
        let folder = MomentFolder(id: ref.documentID, name: name, createdAt: Date(), isHighlightReelsFolder: isHighlightReelsFolder ? true : nil)
        do {
            try ref.setData(from: folder) { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(folder))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    /// The one well-known folder Highlight Reel exports auto-file into -
    /// created the first time a reel is ever exported, found by
    /// `isHighlightReelsFolder` (not by name) on every export after
    /// that. Like any other folder, the user is free to rename it or
    /// move its Moments elsewhere.
    func getOrCreateHighlightReelsFolder(completion: @escaping (Result<MomentFolder, Error>) -> Void) {
        loadMomentFolders { folders in
            if let existing = folders.first(where: { $0.isHighlightReelsFolder == true }) {
                completion(.success(existing))
                return
            }
            self.createMomentFolder(name: "Highlight Reels", isHighlightReelsFolder: true, completion: completion)
        }
    }

    func loadMomentFolders(completion: @escaping ([MomentFolder]) -> Void) {
        guard let user = user else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        momentFoldersCollection(uid: user.uid).getDocuments { snapshot, error in
            if let error {
                debugLog("❌ loadMomentFolders error:", error.localizedDescription)
                DispatchQueue.main.async { completion([]) }
                return
            }
            let folders = (snapshot?.documents ?? []).compactMap { try? $0.data(as: MomentFolder.self) }
            DispatchQueue.main.async { completion(folders) }
        }
    }

    func renameMomentFolder(folderId: String, name: String, completion: @escaping (Error?) -> Void) {
        guard let user = user, !folderId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }
        momentFoldersCollection(uid: user.uid).document(folderId).updateData(["name": name]) { error in
            completion(error)
        }
    }

    func createMomentBucket(folderId: String, name: String, completion: @escaping (Result<MomentBucket, Error>) -> Void) {
        guard let user = user, !folderId.isEmpty else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let ref = momentFoldersCollection(uid: user.uid).document(folderId).collection("buckets").document()
        let bucket = MomentBucket(id: ref.documentID, name: name, createdAt: Date())
        do {
            try ref.setData(from: bucket) { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(bucket))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    func loadMomentBuckets(folderId: String, completion: @escaping ([MomentBucket]) -> Void) {
        guard let user = user, !folderId.isEmpty else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        momentFoldersCollection(uid: user.uid).document(folderId).collection("buckets").getDocuments { snapshot, error in
            if let error {
                debugLog("❌ loadMomentBuckets error:", error.localizedDescription)
                DispatchQueue.main.async { completion([]) }
                return
            }
            let buckets = (snapshot?.documents ?? []).compactMap { try? $0.data(as: MomentBucket.self) }
            DispatchQueue.main.async { completion(buckets) }
        }
    }

    func renameMomentBucket(folderId: String, bucketId: String, name: String, completion: @escaping (Error?) -> Void) {
        guard let user = user, !folderId.isEmpty, !bucketId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }
        momentFoldersCollection(uid: user.uid).document(folderId).collection("buckets").document(bucketId)
            .updateData(["name": name]) { error in
                completion(error)
            }
    }

    /// Clears the given Moment fields (via `FieldValue.delete()`, same
    /// convention `updateMomentFreezeFrame` already uses) on every Moment
    /// matching `field == value`, chunked into ≤500-write batches -
    /// Firestore's own per-batch limit. Used by folder/bucket deletion to
    /// un-file every Moment that referenced the thing being deleted,
    /// rather than deleting those Moments.
    private func clearMomentFields(_ fields: [String], where field: String, equals value: String, completion: @escaping (Error?) -> Void) {
        guard let user = user else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        let db = Firestore.firestore()
        let momentsRef = db.collection("users").document(user.uid).collection("moments")
        momentsRef.whereField(field, isEqualTo: value).getDocuments { snapshot, error in
            if let error {
                completion(error)
                return
            }
            let docs = snapshot?.documents ?? []
            guard !docs.isEmpty else {
                completion(nil)
                return
            }

            let clearedFields = Dictionary(uniqueKeysWithValues: fields.map { ($0, FieldValue.delete() as Any) })
            let chunks = stride(from: 0, to: docs.count, by: 500).map { Array(docs[$0..<min($0 + 500, docs.count)]) }
            let group = DispatchGroup()
            var firstError: Error? = nil
            for chunk in chunks {
                group.enter()
                let batch = db.batch()
                for doc in chunk {
                    batch.updateData(clearedFields, forDocument: doc.reference)
                }
                batch.commit { error in
                    if let error { firstError = firstError ?? error }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                completion(firstError)
            }
        }
    }

    /// Un-files every Moment in this folder (both fields - a Moment that
    /// was in a bucket inside this folder is cleared all the way back to
    /// unfiled, not left pointing at a now-deleted bucket), deletes every
    /// bucket inside it, then the folder itself. Moments are never
    /// deleted by this.
    func deleteMomentFolder(folderId: String, completion: @escaping (Error?) -> Void) {
        guard let user = user, !folderId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        clearMomentFields(["momentFolderId", "momentBucketId"], where: "momentFolderId", equals: folderId) { error in
            if let error {
                completion(error)
                return
            }

            let db = Firestore.firestore()
            let folderRef = self.momentFoldersCollection(uid: user.uid).document(folderId)
            folderRef.collection("buckets").getDocuments { snapshot, error in
                if let error {
                    completion(error)
                    return
                }
                let batch = db.batch()
                for doc in snapshot?.documents ?? [] {
                    batch.deleteDocument(doc.reference)
                }
                batch.deleteDocument(folderRef)
                batch.commit { error in
                    completion(error)
                }
            }
        }
    }

    /// Un-files every Moment in this bucket (only `momentBucketId` -
    /// `momentFolderId` is left alone, so those Moments fall back to
    /// "directly in the parent folder" rather than all the way to
    /// unfiled), then deletes the bucket itself.
    func deleteMomentBucket(folderId: String, bucketId: String, completion: @escaping (Error?) -> Void) {
        guard let user = user, !folderId.isEmpty, !bucketId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        clearMomentFields(["momentBucketId"], where: "momentBucketId", equals: bucketId) { error in
            if let error {
                completion(error)
                return
            }
            self.momentFoldersCollection(uid: user.uid).document(folderId).collection("buckets").document(bucketId)
                .delete { error in
                    completion(error)
                }
        }
    }

    /// The only writer of `Moment.momentFolderId`/`momentBucketId` - pass
    /// nil for either (or both) to clear it. A thin wrapper around the
    /// existing `updateMomentFields`, same `NSNull()`-clears-a-field
    /// convention `MomentDetailView`'s `updateGameInfo` already uses for
    /// `opponent`/`score`.
    func moveMoment(momentId: String, toFolderId folderId: String?, bucketId: String?, completion: @escaping (Error?) -> Void) {
        updateMomentFields(momentId: momentId, fields: [
            "momentFolderId": folderId ?? NSNull(),
            "momentBucketId": bucketId ?? NSNull()
        ], completion: completion)
    }
}
