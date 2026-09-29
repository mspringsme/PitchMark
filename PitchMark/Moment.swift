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
import AVFoundation
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
    /// Step 4 of the Asset + Overlay editor spec - Optional for the same
    /// reason every other field added after Phase 6 is: existing saved
    /// Moment documents have no "overlays" key.
    var overlays: [OverlayItem]? = nil
    /// 2026-09-28 speed ramp editor - same Optional reasoning as `overlays`.
    var speedKeyframes: [SpeedKeyframe]? = nil
    /// 2026-09-28 audio overlay editor - same Optional reasoning.
    var audioOverlays: [AudioOverlayItem]? = nil
    /// nil/1.0 = unchanged, 0 = muted. Same Optional reasoning.
    var originalAudioVolume: Double? = nil
    /// 2026-09-28 - lets the original track's volume vary over time
    /// instead of staying flat. Nil/empty means "flat `originalAudioVolume`,
    /// unchanged" - same Optional reasoning as every other field here.
    var originalVolumeKeyframes: [VolumeKeyframe]? = nil

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
        photoCount: Int = 0,
        overlays: [OverlayItem]? = nil,
        speedKeyframes: [SpeedKeyframe]? = nil,
        audioOverlays: [AudioOverlayItem]? = nil,
        originalAudioVolume: Double? = nil,
        originalVolumeKeyframes: [VolumeKeyframe]? = nil
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
        self.overlays = overlays
        self.speedKeyframes = speedKeyframes
        self.audioOverlays = audioOverlays
        self.originalAudioVolume = originalAudioVolume
        self.originalVolumeKeyframes = originalVolumeKeyframes
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

/// The video `MomentAudioEditorView` always mixes from - snapshotted
/// once, the first time that editor touches this Moment, from whatever
/// `resolvedMomentVideoURL` was at that moment (untouched original, or
/// already trimmed/speed-ramped/overlaid, but never yet audio-mixed).
/// Every later audio-mix operation (live preview and export alike)
/// rebuilds fully from this same frozen file plus the *current* full
/// overlays/volume state - never from a *previous* audio-mix's own
/// output.
///
/// Without this, re-opening the audio editor after a previous audio
/// export would treat that prior export's already-mixed audio track as
/// if it were still a clean, unmixed source: moving or deleting a
/// placed clip added a fresh copy of the current overlay list on top of
/// a track that already permanently contained the old one, so a moved
/// clip "echoed" at both its old and new position, and deleting a clip
/// couldn't remove audio already flattened into that prior export - it
/// kept playing in both the live preview and every future export,
/// because both were built by re-mixing on top of an already-mixed
/// track instead of a clean one.
///
/// Invalidated by `invalidateMomentAudioBase` whenever Trim/Speed/
/// Overlay produce a new edited file, so the next audio edit
/// re-snapshots a fresh base instead of mixing on top of a stale one
/// (stale in the sense of missing that newer video content entirely,
/// not in the ghost-audio sense above).
func localMomentAudioBaseVideoURL(for momentId: String) -> URL? {
    guard !momentId.isEmpty, let directory = momentsDirectory() else { return nil }
    return directory.appendingPathComponent("\(momentId)-audio-base.mov")
}

/// Deletes the audio-mix base snapshot, if any. Call this whenever a
/// non-audio edit (Trim/Speed/Overlay) commits a new edited file - the
/// base's video would otherwise silently miss that newer edit the next
/// time audio is mixed, since the base only gets refreshed lazily.
func invalidateMomentAudioBase(momentId: String) {
    guard let url = localMomentAudioBaseVideoURL(for: momentId) else { return }
    try? FileManager.default.removeItem(at: url)
}

/// The video `OverlayEditorView` always bakes overlays onto -
/// snapshotted once, the first time that editor exports on this
/// Moment, from whatever `resolvedMomentVideoURL` was at that moment.
/// Exact same reasoning and same bug class as
/// `localMomentAudioBaseVideoURL` above, just for visual overlays
/// instead of audio: `OverlayEditorView.startExport()` used to
/// re-fetch `resolvedMomentVideoURL` fresh at export time, which - once
/// this editor had exported even once for a Moment - *is* a prior
/// overlay bake's own output. Moving or deleting a placed overlay after
/// that left its old position permanently burned into that prior
/// export's pixels (impossible to erase) while a fresh copy of the
/// current overlay list got composited on top, so a moved overlay
/// "ghosted" at both positions. (The live preview never had this bug -
/// it draws overlays as plain SwiftUI views on top of whatever's
/// already playing, never re-deriving from a possibly-baked file - only
/// export did.)
///
/// Invalidated by `invalidateMomentOverlayBase` whenever Trim/Speed/
/// Audio produce a new edited file, so the next overlay export
/// re-snapshots a fresh base instead of baking onto pixels that are
/// missing that newer edit entirely.
func localMomentOverlayBaseVideoURL(for momentId: String) -> URL? {
    guard !momentId.isEmpty, let directory = momentsDirectory() else { return nil }
    return directory.appendingPathComponent("\(momentId)-overlay-base.mov")
}

/// Resolves (creating on first use) the frozen overlay-bake base file -
/// `sourceVideoURL` is only consulted the moment the base doesn't exist
/// yet; every later call returns the existing base regardless of what
/// `sourceVideoURL` newly resolves to. Free function rather than a
/// method on `OverlayEditorView` so its `init` can call it with its raw
/// parameters before `self` is fully initialized - `OverlayEditorView`
/// needs the resolved base for its very first `AVPlayer(url:)`, not
/// just at export time.
///
/// 2026-09-30: `OverlayEditorView`'s live preview used to construct its
/// `AVPlayer` straight from the incoming `videoURL` - `resolvedMomentVideoURL`,
/// which *is* a prior overlay export's own output once one exists for a
/// Moment. Overlays are drawn as plain SwiftUI views on top of whatever's
/// playing, so re-opening this editor after any earlier export showed the
/// old overlay positions burned into the playing video's pixels *underneath*
/// a fresh, editable copy of the same overlays - moving one looked like it
/// left a duplicate behind, since the baked-in copy couldn't be moved.
/// Reported by the user as "the editing of added assets is glitchy." Same
/// bug class `startExport()` was already protected against (see
/// `localMomentOverlayBaseVideoURL`'s doc comment above) - the preview
/// player just wasn't pointed at the same frozen base yet.
func overlayBaseVideoURL(momentId: String, sourceVideoURL: URL) -> URL {
    guard let baseURL = localMomentOverlayBaseVideoURL(for: momentId) else {
        return sourceVideoURL
    }
    if !FileManager.default.fileExists(atPath: baseURL.path) {
        try? FileManager.default.copyItem(at: sourceVideoURL, to: baseURL)
    }
    return FileManager.default.fileExists(atPath: baseURL.path) ? baseURL : sourceVideoURL
}

/// Deletes the overlay-bake base snapshot, if any. Call this whenever a
/// non-overlay edit (Trim/Speed/Audio) commits a new edited file - same
/// reasoning as `invalidateMomentAudioBase`, mirrored for overlays.
func invalidateMomentOverlayBase(momentId: String) {
    guard let url = localMomentOverlayBaseVideoURL(for: momentId) else { return }
    try? FileManager.default.removeItem(at: url)
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

    /// Trim and speed-ramp export both change a Moment's actual video
    /// duration but don't otherwise touch this field - without calling
    /// this after either edit, the list's displayed duration goes stale
    /// (still reflects whatever the Moment's duration was at recording
    /// time). Fire-and-forget by design, matching every other small
    /// field update in this app - callers don't block on it.
    func refreshMomentDuration(momentId: String, videoURL: URL, completion: (() -> Void)? = nil) {
        guard !momentId.isEmpty else {
            completion?()
            return
        }
        Task {
            let asset = AVURLAsset(url: videoURL)
            let loadedDuration = try? await asset.load(.duration)
            guard let seconds = loadedDuration?.seconds, seconds.isFinite else {
                await MainActor.run { completion?() }
                return
            }
            await MainActor.run {
                self.updateMomentFields(momentId: momentId, fields: ["durationSeconds": seconds]) { _ in
                    completion?()
                }
            }
        }
    }

    /// `overlays` is an array of Codable structs, not a primitive -
    /// updateMomentFields's plain [String: Any] shape can't carry that
    /// directly. Encoding through a tiny wrapper via Firestore.Encoder
    /// produces exactly the ["overlays": [[String: Any]]] shape
    /// updateData expects - the same mechanism saveMoment already trusts
    /// via setData(from:), aimed at one field instead of a whole document.
    func updateMomentOverlays(momentId: String, overlays: [OverlayItem], completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        struct OverlaysFieldWrapper: Encodable {
            var overlays: [OverlayItem]
        }

        do {
            let encoded = try Firestore.Encoder().encode(OverlaysFieldWrapper(overlays: overlays))
            Firestore.firestore()
                .collection("users").document(user.uid)
                .collection("moments").document(momentId)
                .updateData(encoded) { error in
                    completion(error)
                }
        } catch {
            completion(error)
        }
    }

    /// Same shape as `updateMomentOverlays` - an array of Codable structs
    /// needs the same Firestore.Encoder wrapper trick.
    func updateMomentSpeedKeyframes(momentId: String, keyframes: [SpeedKeyframe], completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        struct SpeedKeyframesFieldWrapper: Encodable {
            var speedKeyframes: [SpeedKeyframe]
        }

        do {
            let encoded = try Firestore.Encoder().encode(SpeedKeyframesFieldWrapper(speedKeyframes: keyframes))
            Firestore.firestore()
                .collection("users").document(user.uid)
                .collection("moments").document(momentId)
                .updateData(encoded) { error in
                    completion(error)
                }
        } catch {
            completion(error)
        }
    }

    /// Same shape as `updateMomentOverlays`/`updateMomentSpeedKeyframes`.
    func updateMomentAudioOverlays(momentId: String, audioOverlays: [AudioOverlayItem], completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        struct AudioOverlaysFieldWrapper: Encodable {
            var audioOverlays: [AudioOverlayItem]
        }

        do {
            let encoded = try Firestore.Encoder().encode(AudioOverlaysFieldWrapper(audioOverlays: audioOverlays))
            Firestore.firestore()
                .collection("users").document(user.uid)
                .collection("moments").document(momentId)
                .updateData(encoded) { error in
                    completion(error)
                }
        } catch {
            completion(error)
        }
    }

    /// Same shape as `updateMomentAudioOverlays` - `originalVolumeKeyframes`
    /// is also an array of Codable structs, not a primitive
    /// `updateMomentFields` can carry directly.
    func updateMomentOriginalVolumeKeyframes(momentId: String, keyframes: [VolumeKeyframe], completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        struct OriginalVolumeKeyframesFieldWrapper: Encodable {
            var originalVolumeKeyframes: [VolumeKeyframe]
        }

        do {
            let encoded = try Firestore.Encoder().encode(OriginalVolumeKeyframesFieldWrapper(originalVolumeKeyframes: keyframes))
            Firestore.firestore()
                .collection("users").document(user.uid)
                .collection("moments").document(momentId)
                .updateData(encoded) { error in
                    completion(error)
                }
        } catch {
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
    invalidateMomentAudioBase(momentId: momentId)
    invalidateMomentOverlayBase(momentId: momentId)
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
