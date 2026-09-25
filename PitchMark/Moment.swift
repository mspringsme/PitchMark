//
//  Moment.swift
//  PitchMark
//
//  Phase 6 of the 2026-09-24 Coach/Parent/Family direction: Moments V1.
//  "Capture now, create later" - this file is deliberately minimal: a
//  Moment is just enough metadata to find a clip again later. Video files
//  stay on-device (mirrors Utilities.swift's local-portrait-storage
//  pattern exactly); only this small metadata record syncs to Firestore.
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this UI.
//

import Foundation
import UIKit
import Photos
import FirebaseFirestore
import FirebaseAuth

struct Moment: Identifiable, Codable {
    @DocumentID var id: String?
    var createdAt: Date = Date()
    var teamId: String? = nil
    var playerId: String? = nil
    var playerName: String? = nil
    var durationSeconds: Double? = nil
    /// User-set name for the clip, editable any time after recording -
    /// falls back to the player's name (then "Moment") wherever displayed
    /// when unset.
    var title: String? = nil
    // Stored as Optional deliberately, even though every write always sets
    // a real value - see the two custom-decoder attempts this replaced,
    // both wrong, in git history for why. Swift's synthesized Decodable
    // only skips a missing key without throwing for Optional-typed
    // properties; a non-optional `var photoCount: Int = 0` still throws on
    // decode when an older document has no "photoCount" field, and `try?`
    // at the call site then silently drops that whole document. Keeping
    // these Optional and relying on the plain synthesized Decodable (the
    // same mechanism @DocumentID already works correctly with elsewhere in
    // this codebase - Team.swift, TeamMembership, TeamPlayer) sidesteps
    // that without any custom init(from:) to get subtly wrong again.
    // Read via `moment.isFavorite ?? false` / `moment.photoCount ?? 0`.
    var isFavorite: Bool? = false
    var opponent: String? = nil
    var score: String? = nil
    var inning: Int? = nil
    var gameInfoUpdatedAt: Date? = nil
    var photoCount: Int? = 0

    init(
        createdAt: Date = Date(),
        teamId: String? = nil,
        playerId: String? = nil,
        playerName: String? = nil,
        durationSeconds: Double? = nil,
        isFavorite: Bool = false,
        opponent: String? = nil,
        score: String? = nil,
        inning: Int? = nil,
        gameInfoUpdatedAt: Date? = nil,
        photoCount: Int = 0
    ) {
        self.createdAt = createdAt
        self.teamId = teamId
        self.playerId = playerId
        self.playerName = playerName
        self.durationSeconds = durationSeconds
        self.isFavorite = isFavorite
        self.opponent = opponent
        self.score = score
        self.inning = inning
        self.gameInfoUpdatedAt = gameInfoUpdatedAt
        self.photoCount = photoCount
    }

    /// The user-set title if there is one, else the tagged player's name,
    /// else a generic fallback - the one place this fallback chain should
    /// be computed, used everywhere a Moment's name is displayed.
    var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespaces) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return playerName ?? "Moment"
    }
}

// MARK: - Local video storage (mirrors Utilities.swift's portrait pattern)

private func momentsDirectory() -> URL? {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return nil
    }
    return base.appendingPathComponent("PitchMark/Moments", isDirectory: true)
}

func localMomentVideoURL(for momentId: String) -> URL? {
    guard !momentId.isEmpty, let directory = momentsDirectory() else { return nil }
    return directory.appendingPathComponent("\(momentId).mov")
}

/// Copies a picker's temp file into the app's own sandbox - the temp URL
/// `UIImagePickerController` hands back does not survive past the current
/// launch.
@discardableResult
func saveLocalMomentVideo(from sourceURL: URL, momentId: String) -> Bool {
    guard let destinationURL = localMomentVideoURL(for: momentId) else { return false }
    do {
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return true
    } catch {
        debugLog("❌ saveLocalMomentVideo failed: \(error.localizedDescription)")
        return false
    }
}

func removeLocalMomentVideo(momentId: String) {
    guard let url = localMomentVideoURL(for: momentId) else { return }
    try? FileManager.default.removeItem(at: url)
}

/// The exported, edited video (Phase 7b) - separate from the original so
/// re-editing always starts from the untouched recording, never a prior
/// export.
func localMomentEditedVideoURL(for momentId: String) -> URL? {
    guard !momentId.isEmpty, let directory = momentsDirectory() else { return nil }
    return directory.appendingPathComponent("\(momentId)-edited.mov")
}

/// Playback and sharing should resolve a Moment's video through this,
/// not `localMomentVideoURL` directly - it prefers the edited file once
/// one exists, falling back to the original otherwise.
func resolvedMomentVideoURL(for momentId: String) -> URL? {
    if let edited = localMomentEditedVideoURL(for: momentId), FileManager.default.fileExists(atPath: edited.path) {
        return edited
    }
    return localMomentVideoURL(for: momentId)
}

// MARK: - Local photo storage (same directory convention as video)

func localMomentPhotoURL(momentId: String, index: Int) -> URL? {
    guard !momentId.isEmpty, let directory = momentsDirectory() else { return nil }
    return directory.appendingPathComponent("\(momentId)-photo-\(index).jpg")
}

/// Camera captures (and some Photos-library assets) can carry an HDR gain
/// map. Displaying that as-is produces a real, ~0.8s brightness
/// "breathing" pulse on the thumbnail as iOS's HDR-to-SDR tone-mapping
/// re-negotiates - reported against the Moments detail screen and
/// confirmed via frame-by-frame brightness analysis of a screen
/// recording (both thumbnails pulsed in sync; the plain white background
/// and text around them stayed perfectly constant, ruling out a
/// display/auto-brightness cause). Round-tripping through UIImage's
/// re-encoder strips the gain map, so every path that saves a Moment
/// photo - the camera shutter and the PhotosPicker "+" button alike -
/// writes plain SDR to disk.
private func stripHDRGainMap(from data: Data) -> Data {
    guard let image = UIImage(data: data), let sdrData = image.jpegData(compressionQuality: 0.92) else {
        return data
    }
    return sdrData
}

@discardableResult
func saveLocalMomentPhoto(_ data: Data, momentId: String, index: Int) -> Bool {
    guard let destinationURL = localMomentPhotoURL(momentId: momentId, index: index) else { return false }
    do {
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try stripHDRGainMap(from: data).write(to: destinationURL, options: [.atomic])
        return true
    } catch {
        debugLog("❌ saveLocalMomentPhoto failed: \(error.localizedDescription)")
        return false
    }
}

// MARK: - AuthManager persistence

extension AuthManager {
    func saveMoment(_ moment: Moment, completion: @escaping (Result<Moment, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("moments").document()

        var moment = moment
        moment.id = ref.documentID

        do {
            try ref.setData(from: moment) { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(moment))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    /// Partial update - callers pass only the fields they're changing.
    /// Used for Favorite/Game Info/photoCount so an edit to one field
    /// never touches the others.
    func updateMomentFields(momentId: String, fields: [String: Any], completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("moments").document(momentId)
            .updateData(fields) { error in
                completion(error)
            }
    }

    func loadMoments(completion: @escaping ([Moment]) -> Void) {
        guard let user = user else {
            completion([])
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("moments")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                let moments: [Moment] = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: Moment.self)
                } ?? []
                completion(moments)
            }
    }

    func deleteMoment(momentId: String, completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("moments").document(momentId)
            .delete { error in
                completion(error)
            }
    }
}

/// Removes everything local to a Moment - original video, edited video,
/// and any attached photos. Call after the Firestore doc itself is
/// deleted (see AuthManager.deleteMoment).
func removeAllLocalMomentFiles(momentId: String, photoCount: Int) {
    removeLocalMomentVideo(momentId: momentId)
    if let edited = localMomentEditedVideoURL(for: momentId) {
        try? FileManager.default.removeItem(at: edited)
    }
    for index in 0..<max(photoCount, 0) {
        if let photoURL = localMomentPhotoURL(momentId: momentId, index: index) {
            try? FileManager.default.removeItem(at: photoURL)
        }
    }
}

/// Saves a copy of a Moment's current video (edited version if one
/// exists, else the original) to the system Photos library.
func saveMomentVideoToCameraRoll(momentId: String, completion: @escaping (Result<Void, Error>) -> Void) {
    guard let url = resolvedMomentVideoURL(for: momentId) else {
        completion(.failure(NSError(domain: "Moment", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video file found for this Moment."])))
        return
    }

    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        guard status == .authorized || status == .limited else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "Moment", code: -2, userInfo: [NSLocalizedDescriptionKey: "Photos access is needed to save this video."])))
            }
            return
        }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    completion(.success(()))
                } else {
                    completion(.failure(error ?? NSError(domain: "Moment", code: -3, userInfo: [NSLocalizedDescriptionKey: "Couldn't save to Photos."])))
                }
            }
        }
    }
}
