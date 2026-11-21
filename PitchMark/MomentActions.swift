//
//  MomentActions.swift
//  PitchMark
//
//  The per-Moment actions both the library (long-press menu) and a
//  Moment's own screen (its ⋯ menu) offer, in one place so the two can't
//  drift (2026-11-15): Duplicate, Duplicate to Original, Revert to
//  Original, Delete, Save then Delete.
//

import SwiftUI
import AVFoundation
import FirebaseFirestore

/// What a library tile's long-press menu asks the library to do.
enum MomentQuickAction {
    case play
    case share
    case duplicate
    case duplicateOriginal
    case move
    case delete
    /// The ♥ on a tile.
    case toggleFavorite
}

private struct MomentQuickActionKey: EnvironmentKey {
    static let defaultValue: ((Moment, MomentQuickAction) -> Void)? = nil
}

extension EnvironmentValues {
    /// Set by MomentsLibraryView; every MomentGridView under it (the All
    /// tab and the pushed folder/bucket screens) gives its tiles the
    /// long-press menu when it's set.
    var momentQuickAction: ((Moment, MomentQuickAction) -> Void)? {
        get { self[MomentQuickActionKey.self] }
        set { self[MomentQuickActionKey.self] = newValue }
    }
}

/// True when the Moment has a separately edited video to fall back from.
func momentHasEdits(_ momentId: String) -> Bool {
    guard let edited = localMomentEditedVideoURL(for: momentId) else { return false }
    let fm = FileManager.default
    if fm.fileExists(atPath: edited.path) { return true }
    if let faded = localMomentFadedVideoURL(for: momentId), fm.fileExists(atPath: faded.path) { return true }
    return false
}

enum MomentActions {
    /// The Firestore fields that describe edits. Revert clears them all;
    /// Duplicate never copies them (the copy's video already has the
    /// edits baked in, or is the original).
    static let editFieldNames = [
        "overlays", "markupOverlays", "speedKeyframes", "audioOverlays",
        "originalAudioVolume", "originalVolumeKeyframes", "originalMuteRegions",
        "zoomRegions", "slideshowSegments", "slideshowTransitionsEnabled",
        "fadeInEnabled", "fadeOutEnabled", "cropSettings", "freezeFrame",
        "filterPreset", "gameCaption"
    ]

    /// A copy of the Moment as its own new Moment: its current video (or
    /// the original, `fromOriginal`), its photos, title, favorite and
    /// folder (user's call, 2026-11-15).
    static func duplicate(
        _ moment: Moment,
        fromOriginal: Bool,
        authManager: AuthManager,
        completion: @escaping (Result<Moment, Error>) -> Void
    ) {
        guard let id = moment.id else { return }
        let sourceURL = fromOriginal ? localMomentVideoURL(for: id) : resolvedMomentPlaybackURL(for: id)
        guard let sourceURL, FileManager.default.fileExists(atPath: sourceURL.path) else {
            completion(.failure(NSError(domain: "Moment", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "Video file not found."])))
            return
        }
        Task {
            let loaded = try? await AVURLAsset(url: sourceURL).load(.duration)
            let seconds = loaded.map(\.seconds).flatMap { $0.isFinite ? $0 : nil } ?? moment.durationSeconds
            await MainActor.run {
                var copy = Moment(
                    teamId: moment.teamId,
                    playerId: moment.playerId,
                    playerName: moment.playerName,
                    durationSeconds: seconds,
                    isFavorite: moment.isFavorite ?? false,
                    photoCount: moment.photoCount ?? 0,
                    momentKind: moment.momentKind,
                    momentFolderId: moment.momentFolderId,
                    momentBucketId: moment.momentBucketId,
                    cityName: moment.cityName
                )
                copy.title = moment.title
                copy.gameContext = moment.gameContext
                copy.playerTags = moment.playerTags
                authManager.saveMoment(copy) { result in
                    if case .success(let saved) = result, let newId = saved.id {
                        saveLocalMomentVideo(from: sourceURL, momentId: newId, autoBackupToPhotos: false)
                        for index in 0..<max(moment.photoCount ?? 0, 0) {
                            if let photo = localMomentPhotoURL(momentId: id, index: index),
                               let data = try? Data(contentsOf: photo) {
                                saveLocalMomentPhoto(data, momentId: newId, index: index)
                            }
                        }
                    }
                    completion(result)
                }
            }
        }
    }

    /// Back to the video as recorded: every edited file goes, and every
    /// edit setting is cleared. Photos stay.
    static func revertToOriginal(_ moment: Moment, authManager: AuthManager, completion: @escaping (Error?) -> Void) {
        guard let id = moment.id else { return }
        let fm = FileManager.default
        if let edited = localMomentEditedVideoURL(for: id) { try? fm.removeItem(at: edited) }
        if let faded = localMomentFadedVideoURL(for: id) { try? fm.removeItem(at: faded) }
        if let preFreeze = localMomentPreFreezeVideoURL(for: id) { try? fm.removeItem(at: preFreeze) }
        invalidateOtherFrozenBases(momentId: id, except: [])
        invalidateMomentOverlayBase(momentId: id)
        var fields: [String: Any] = [:]
        for name in editFieldNames { fields[name] = FieldValue.delete() }
        authManager.updateMomentFields(momentId: id, fields: fields) { error in
            if let original = localMomentVideoURL(for: id) {
                authManager.refreshMomentDuration(momentId: id, videoURL: original)
            }
            completion(error)
        }
    }

    /// Removes it from PitchMark and this phone.
    static func delete(_ moment: Moment, authManager: AuthManager, completion: @escaping (Error?) -> Void) {
        guard let id = moment.id else { return }
        authManager.deleteMoment(momentId: id) { error in
            if error == nil {
                removeAllLocalMomentFiles(momentId: id, photoCount: moment.photoCount ?? 0)
            }
            completion(error)
        }
    }

    /// Saves its video to Photos first; deletes only if that worked.
    static func saveThenDelete(_ moment: Moment, authManager: AuthManager, completion: @escaping (Error?) -> Void) {
        guard let id = moment.id else { return }
        saveMomentVideoToCameraRoll(momentId: id) { result in
            switch result {
            case .success:
                delete(moment, authManager: authManager, completion: completion)
            case .failure(let error):
                completion(NSError(domain: "Moment", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Couldn't save to Camera Roll, so nothing was deleted: \(error.localizedDescription)"
                ]))
            }
        }
    }
}
