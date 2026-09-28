//
//  AudioAssetItem.swift
//  PitchMark
//
//  2026-09-28: user-created audio library assets - local .m4a storage +
//  Firestore metadata-only sync, mirroring AssetItem.swift's exact
//  pattern (which itself mirrors Moment.swift's). Unlike the image
//  library, there are no bundled defaults - no equivalent "ship a couple
//  of generic audio clips" makes sense here, so there's no LibraryAsset-
//  style bundled/user-created unification either; every AudioAssetItem
//  is a real Firestore-backed document.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

struct AudioAssetItem: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var createdAt: Date = Date()
    var durationSeconds: Double = 0

    init(name: String, createdAt: Date = Date(), durationSeconds: Double = 0) {
        self.name = name
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
    }
}

// MARK: - Local audio storage (mirrors AssetItem.swift's image storage)

private func audioAssetsDirectory() -> URL? {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return nil
    }
    return base.appendingPathComponent("PitchMark/AudioAssets", isDirectory: true)
}

func localAudioAssetURL(for assetId: String) -> URL? {
    guard !assetId.isEmpty, let directory = audioAssetsDirectory() else { return nil }
    return directory.appendingPathComponent("\(assetId).m4a")
}

@discardableResult
func saveLocalAudioAsset(from sourceURL: URL, assetId: String) -> Bool {
    guard let destinationURL = localAudioAssetURL(for: assetId) else { return false }
    do {
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return true
    } catch {
        debugLog("❌ saveLocalAudioAsset failed: \(error.localizedDescription)")
        return false
    }
}

func removeLocalAudioAsset(assetId: String) {
    guard let url = localAudioAssetURL(for: assetId) else { return }
    try? FileManager.default.removeItem(at: url)
}

// MARK: - AuthManager persistence

extension AuthManager {
    func saveAudioAsset(_ asset: AudioAssetItem, completion: @escaping (Result<AudioAssetItem, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("audioAssets").document()

        var asset = asset
        asset.id = ref.documentID

        do {
            try ref.setData(from: asset) { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(asset))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    /// Partial update - used for rename so an edit to the name never
    /// touches any other field.
    func updateAudioAssetFields(assetId: String, fields: [String: Any], completion: @escaping (Error?) -> Void) {
        guard let user = user, !assetId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("audioAssets").document(assetId)
            .updateData(fields) { error in
                completion(error)
            }
    }

    func loadAudioAssets(completion: @escaping ([AudioAssetItem]) -> Void) {
        guard let user = user else {
            completion([])
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("audioAssets")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                let assets: [AudioAssetItem] = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: AudioAssetItem.self)
                } ?? []
                completion(assets)
            }
    }

    func deleteAudioAsset(assetId: String, completion: @escaping (Error?) -> Void) {
        guard let user = user, !assetId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("audioAssets").document(assetId)
            .delete { error in
                completion(error)
            }
    }
}
