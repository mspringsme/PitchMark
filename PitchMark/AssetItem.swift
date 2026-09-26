//
//  AssetItem.swift
//  PitchMark
//
//  Step 2 of the 2026-09-26 Asset + Video Overlay Keyframe Editor spec.
//  User-created library assets: local PNG storage + Firestore
//  metadata-only sync, mirroring Moment.swift's exact pattern. Bundled
//  default assets (see `bundledAssets` below) are a separate, non-
//  Firestore concept - they ship in the asset catalog and are never
//  editable or deletable.
//
//  `kind`/`animationDuration`/`renderer` are here from the start per the
//  2026-09-25 animated-assets addendum, even though nothing produces a
//  non-.staticImage AssetItem yet - avoids a schema migration once
//  looping/one-shot bundled assets are actually built. Every field here
//  is safe as non-optional-with-default because this is a brand-new
//  collection with no pre-existing documents; the "must be genuinely
//  Optional" lesson (see Moment.swift's header comment) applies to fields
//  added *later* to a struct with existing saved documents, not to a
//  type's initial shape.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import UIKit
import FirebaseFirestore
import FirebaseAuth

enum AssetKind: String, Codable {
    case staticImage
    case looping
    case oneShot
}

enum AnimatedRenderer: String, Codable {
    case frameSequence
    case lottie
    case coreAnimationLayer
}

struct AssetItem: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var createdAt: Date = Date()
    var kind: AssetKind = .staticImage
    var animationDuration: Double? = nil
    var renderer: AnimatedRenderer? = nil

    init(
        name: String,
        createdAt: Date = Date(),
        kind: AssetKind = .staticImage,
        animationDuration: Double? = nil,
        renderer: AnimatedRenderer? = nil
    ) {
        self.name = name
        self.createdAt = createdAt
        self.kind = kind
        self.animationDuration = animationDuration
        self.renderer = renderer
    }
}

// MARK: - Local image storage (mirrors Moment.swift's photo storage / Utilities.swift's portrait storage)

private func assetsDirectory() -> URL? {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return nil
    }
    return base.appendingPathComponent("PitchMark/Assets", isDirectory: true)
}

func localAssetImageURL(for assetId: String) -> URL? {
    guard !assetId.isEmpty, let directory = assetsDirectory() else { return nil }
    return directory.appendingPathComponent("\(assetId).png")
}

func localAssetImage(for assetId: String) -> UIImage? {
    guard let url = localAssetImageURL(for: assetId), let data = try? Data(contentsOf: url) else { return nil }
    return UIImage(data: data)
}

/// Saves PNG data (with alpha, if any) for a library asset, downsized so
/// its longest edge is at most 1024px per the spec, so overlays stay
/// light during playback and export.
@discardableResult
func saveLocalAssetImage(_ data: Data, assetId: String) -> Bool {
    guard let destinationURL = localAssetImageURL(for: assetId) else { return false }
    guard let image = UIImage(data: data) else { return false }
    let resized = downsized(image, maxDimension: 1024)
    guard let pngData = resized.pngData() else { return false }
    do {
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try pngData.write(to: destinationURL, options: [.atomic])
        return true
    } catch {
        debugLog("❌ saveLocalAssetImage failed: \(error.localizedDescription)")
        return false
    }
}

func removeLocalAssetImage(assetId: String) {
    guard let url = localAssetImageURL(for: assetId) else { return }
    try? FileManager.default.removeItem(at: url)
}

private func downsized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
    let longestEdge = max(image.size.width, image.size.height)
    guard longestEdge > maxDimension else { return image }
    let scale = maxDimension / longestEdge
    let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = false
    let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
    return renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
}

// MARK: - Bundled default assets (no Firestore, not deletable)

struct BundledAsset: Identifiable {
    let id: String
    let name: String
    /// Asset-catalog image name.
    let imageName: String
}

let bundledAssets: [BundledAsset] = [
    BundledAsset(id: "bundled-circle", name: "Circle", imageName: "OverlayCircle"),
    BundledAsset(id: "bundled-arrow", name: "Arrow", imageName: "OverlayArrow"),
]

// MARK: - Unified library presentation

/// Presents bundled and user-created assets identically to the UI, so the
/// thumbnail strip never has to branch on where an asset came from.
struct LibraryAsset: Identifiable {
    let id: String
    var name: String
    let image: UIImage?
    let isRenamable: Bool
    let isDeletable: Bool
    /// nil for bundled assets - there's no AssetItem/Firestore doc to edit.
    let backingAssetId: String?

    static func bundled(_ asset: BundledAsset) -> LibraryAsset {
        LibraryAsset(
            id: asset.id,
            name: asset.name,
            image: UIImage(named: asset.imageName),
            isRenamable: false,
            isDeletable: false,
            backingAssetId: nil
        )
    }

    static func userCreated(_ asset: AssetItem) -> LibraryAsset? {
        guard let id = asset.id else { return nil }
        return LibraryAsset(
            id: id,
            name: asset.name,
            image: localAssetImage(for: id),
            isRenamable: true,
            isDeletable: true,
            backingAssetId: id
        )
    }
}

// MARK: - AuthManager persistence

extension AuthManager {
    func saveAsset(_ asset: AssetItem, completion: @escaping (Result<AssetItem, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("assets").document()

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
    func updateAssetFields(assetId: String, fields: [String: Any], completion: @escaping (Error?) -> Void) {
        guard let user = user, !assetId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("assets").document(assetId)
            .updateData(fields) { error in
                completion(error)
            }
    }

    func loadAssets(completion: @escaping ([AssetItem]) -> Void) {
        guard let user = user else {
            completion([])
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("assets")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                let assets: [AssetItem] = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: AssetItem.self)
                } ?? []
                completion(assets)
            }
    }

    /// Bundled defaults + the user's own assets, merged into the single
    /// list the UI presents everywhere an asset picker is needed -
    /// AssetLibraryView and OverlayEditorView both call this rather than
    /// each doing their own merge.
    func loadLibraryAssets(completion: @escaping ([LibraryAsset]) -> Void) {
        loadAssets { assets in
            completion(bundledAssets.map(LibraryAsset.bundled) + assets.compactMap(LibraryAsset.userCreated))
        }
    }

    func deleteAsset(assetId: String, completion: @escaping (Error?) -> Void) {
        guard let user = user, !assetId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("assets").document(assetId)
            .delete { error in
                completion(error)
            }
    }
}
