//
//  AudioAssetItem.swift
//  PitchMark
//
//  2026-09-28: user-created audio library assets - local .m4a storage +
//  Firestore metadata-only sync, mirroring AssetItem.swift's exact
//  pattern (which itself mirrors Moment.swift's).
//
//  2026-09-28 (later same day): one bundled default sound effect was
//  added as a placeholder/proof of concept.
//
//  2026-09-29: superseded by a real bundled sound pack (9 sfx + 1 music
//  loop, all CC0 from Freesound.org - see
//  ~/Documents/Art Created/PitchMarkAudio/license-log.csv for sourcing,
//  merged into Sounds/sounds.json's author/license/sourceURL fields).
//  Files live under Sounds/sfx/ and Sounds/music/; `bundledAudioAssets`
//  is decoded from Sounds/sounds.json rather than hardcoded, so adding
//  another sound later needs only a new file + manifest entry, no Swift
//  change. `BundledAudioAsset`/`LibraryAudioAsset` mirror AssetItem.swift's
//  `BundledAsset`/`LibraryAsset` shape, so every place that plays or
//  mixes audio (MomentAudioEditorView, MomentAudioMixer) resolves a
//  clip's file through one `fileURL` regardless of whether it's bundled
//  or user-created.
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

// MARK: - Bundled default audio assets (no Firestore, not deletable)

struct BundledAudioAsset: Identifiable {
    let id: String
    let name: String
    /// "sfx" or "music" - drives AudioAssetLibraryView's grouped sections.
    let category: String
    /// Filename (with extension) under the bundled Sounds/ resource folder.
    let resourceFileName: String
    /// Known up front rather than probed at runtime - this is a fixed
    /// bundled file, the same reasoning AudioAssetItem stores a
    /// user-recorded clip's duration instead of re-measuring it each time.
    let durationSeconds: Double
    /// Sourcing, for SoundCreditsView - nil for anything not present in
    /// the manifest (shouldn't happen for a properly logged sound, but
    /// Optional rather than assumed so a manifest gap fails soft).
    let author: String?
    let license: String?
    let sourceURL: String?
}

/// Raw shape of the bundled Sounds/sounds.json manifest - one entry per
/// clip. `author`/`license`/`sourceURL` are merged in from
/// ~/Documents/Art Created/PitchMarkAudio/license-log.csv (outside the
/// repo) at pack-assembly time, not re-derived at runtime.
private struct BundledSoundManifestEntry: Codable {
    let id: String
    let name: String
    let category: String
    let filename: String
    let duration: Double
    let author: String?
    let license: String?
    let sourceURL: String?
}

/// Loaded once from the bundled manifest. Adding a new bundled sound
/// going forward means dropping the file under Sounds/sfx or
/// Sounds/music and adding one entry to sounds.json - no Swift code
/// change needed. Ids are prefixed so they never collide with a
/// Firestore-assigned user AudioAssetItem id.
let bundledAudioAssets: [BundledAudioAsset] = {
    guard let url = Bundle.main.url(forResource: "sounds", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let entries = try? JSONDecoder().decode([BundledSoundManifestEntry].self, from: data) else {
        return []
    }
    return entries.map { entry in
        BundledAudioAsset(
            id: "bundled-\(entry.id)",
            name: entry.name,
            category: entry.category,
            resourceFileName: entry.filename,
            durationSeconds: entry.duration,
            author: entry.author,
            license: entry.license,
            sourceURL: entry.sourceURL
        )
    }
}()

func bundledAudioAssetURL(for asset: BundledAudioAsset) -> URL? {
    let fileName = asset.resourceFileName as NSString
    return Bundle.main.url(forResource: fileName.deletingPathExtension, withExtension: fileName.pathExtension)
}

// MARK: - Unified library presentation (mirrors AssetItem.swift's LibraryAsset)

/// Presents bundled and user-created audio identically - to the picker
/// UI and to the mixer alike, via one `fileURL` - so neither has to
/// branch on where a clip came from.
struct LibraryAudioAsset: Identifiable {
    let id: String
    var name: String
    let durationSeconds: Double
    let isRenamable: Bool
    let isDeletable: Bool
    /// nil for bundled assets - there's no AudioAssetItem/Firestore doc to edit.
    let backingAssetId: String?
    let fileURL: URL?
    /// nil for user-created clips (not categorized); "sfx"/"music" for
    /// bundled ones - drives AudioAssetLibraryView's grouped sections.
    let category: String?

    static func bundled(_ asset: BundledAudioAsset) -> LibraryAudioAsset {
        LibraryAudioAsset(
            id: asset.id,
            name: asset.name,
            durationSeconds: asset.durationSeconds,
            isRenamable: false,
            isDeletable: false,
            backingAssetId: nil,
            fileURL: bundledAudioAssetURL(for: asset),
            category: asset.category
        )
    }

    static func userCreated(_ asset: AudioAssetItem) -> LibraryAudioAsset? {
        guard let id = asset.id else { return nil }
        return LibraryAudioAsset(
            id: id,
            name: asset.name,
            durationSeconds: asset.durationSeconds,
            isRenamable: true,
            isDeletable: true,
            backingAssetId: id,
            fileURL: localAudioAssetURL(for: id),
            category: nil
        )
    }
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

    /// Bundled defaults + user-created clips, unified - the picker/hub
    /// UI and MomentAudioEditorView should load through this, not
    /// `loadAudioAssets` directly, so bundled sounds are always included.
    func loadLibraryAudioAssets(completion: @escaping ([LibraryAudioAsset]) -> Void) {
        loadAudioAssets { assets in
            completion(bundledAudioAssets.map(LibraryAudioAsset.bundled) + assets.compactMap(LibraryAudioAsset.userCreated))
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
