//
//  OverlayLayer.swift
//  PitchMark
//
//  Overlays (images, text, the game caption) are the top layer of a
//  Moment's video, always drawn last (2026-11-16).
//
//  The bug this fixes: every editor bakes onto a saved "before" copy. Any
//  other editor's save used to throw the overlays' copy away, so the next
//  overlay edit started from video that already had the overlays in it
//  and drew them again - a doubled caption after a crop. Now:
//
//  - every other editor works on the video *without* overlays
//    (`videoBelowOverlays`), so nothing it bakes carries them;
//  - when it saves, the overlays are drawn back on top
//    (`OverlayLayer.afterOtherEdit`), from a fresh "before overlays" copy of what
//    it just saved;
//  - an overlay save never throws other editors' copies away - they hold
//    overlay-free video by design.
//

import Foundation
import AVFoundation
import UIKit

/// The video other editors should work from: the "before overlays" copy
/// whenever it exists, else the current video. Decided by the files, not
/// the overlay list on screen - that can lag a moment behind (right after
/// game info is added from a recording) and once let Crop copy the
/// captioned video. The copy only exists while there are overlays:
/// `OverlayLayer.afterOtherEdit` drops it when there are none.
func videoBelowOverlays(momentId: String, overlays: [OverlayItem]? = nil) -> URL? {
    if let base = localMomentOverlayBaseVideoURL(for: momentId),
       FileManager.default.fileExists(atPath: base.path) {
        return base
    }
    return resolvedMomentVideoURL(for: momentId)
}

enum OverlayLayer {
    /// Bakes `overlays` onto the "before overlays" copy and saves the
    /// result as the Moment's video. `freshBase` first replaces that copy
    /// with the current video - after another editor saved.
    static func bake(
        momentId: String,
        overlays: [OverlayItem],
        freshBase: Bool,
        authManager: AuthManager,
        completion: @escaping (Error?) -> Void
    ) {
        if freshBase { invalidateMomentOverlayBase(momentId: momentId) }
        guard let source = resolvedMomentVideoURL(for: momentId),
              FileManager.default.fileExists(atPath: source.path) else {
            completion(NSError(domain: "Overlays", code: -1,
                               userInfo: [NSLocalizedDescriptionKey: "This Moment's video isn't on this phone."]))
            return
        }
        let base = overlayBaseVideoURL(momentId: momentId, sourceVideoURL: source)
        guard !overlays.isEmpty else {
            // Nothing on top: the video is the copy itself.
            replaceEditedVideo(momentId: momentId, with: base, removeSource: false, completion: completion)
            return
        }
        authManager.loadLibraryAssets { assets in
            exportMomentWithOverlays(
                sourceURL: base,
                overlays: overlays,
                resolveImage: { id in assets.first(where: { $0.id == id })?.image }
            ) { result in
                switch result {
                case .failure(let error): completion(error)
                case .success(let temp): replaceEditedVideo(momentId: momentId, with: temp, removeSource: true, completion: completion)
                }
            }
        }
    }

    /// After another editor saved, from the Moment's saved overlay list
    /// (never the one on screen):
    /// - overlays and their copy: draw them back on top of the new video;
    /// - no overlays: drop the copy, now out of date, so the next game
    ///   info or overlay starts from the edited video;
    /// - overlays but no copy: they're already part of the video (an
    ///   older edit) - redrawing would double them, so leave it.
    static func afterOtherEdit(momentId: String, authManager: AuthManager, completion: @escaping (Error?) -> Void) {
        authManager.loadMoment(momentId: momentId) { moment in
            let overlays = moment?.overlays ?? []
            let hasCopy = localMomentOverlayBaseVideoURL(for: momentId).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            guard !overlays.isEmpty else {
                invalidateMomentOverlayBase(momentId: momentId)
                completion(nil)
                return
            }
            guard hasCopy else {
                completion(nil)
                return
            }
            bake(momentId: momentId, overlays: overlays, freshBase: true, authManager: authManager) { error in
                refreshFadeIfNeeded(momentId: momentId, authManager: authManager) { completion(error) }
            }
        }
    }

    private static func replaceEditedVideo(momentId: String, with file: URL, removeSource: Bool, completion: @escaping (Error?) -> Void) {
        guard let destination = localMomentEditedVideoURL(for: momentId) else {
            completion(NSError(domain: "Overlays", code: -2, userInfo: [NSLocalizedDescriptionKey: "Couldn't save the video."]))
            return
        }
        do {
            if file != destination {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: file, to: destination)
                if removeSource { try? FileManager.default.removeItem(at: file) }
            }
            completion(nil)
        } catch {
            completion(error)
        }
    }
}

/// One-time cleanup per clip (2026-11-16). Before the overlay layer, other
/// editors' "before" copies were taken from video that had the overlays
/// (the game caption) baked in - and each copy lasts the life of the clip.
/// Removing game info then worked, but the next Crop started from Crop's
/// old copy and brought the caption back. The first time a clip opens on
/// this build, those copies go; each editor takes a fresh one from the
/// overlay-free video next time. The overlays' own copy is kept.
enum OverlayLayerMigration {
    static func markerURL(for momentId: String) -> URL? {
        localMomentOverlayBaseVideoURL(for: momentId)?
            .deletingLastPathComponent()
            .appendingPathComponent("\(momentId)-layers-v2")
    }

    static func runIfNeeded(momentId: String) {
        guard !momentId.isEmpty, let marker = markerURL(for: momentId),
              !FileManager.default.fileExists(atPath: marker.path) else { return }
        invalidateMomentCropBase(momentId: momentId)
        invalidateMomentZoomBase(momentId: momentId)
        invalidateMomentFilterBase(momentId: momentId)
        invalidateMomentMarkupBase(momentId: momentId)
        invalidateMomentAudioBase(momentId: momentId)
        invalidateMomentSlideshowBase(momentId: momentId)
        try? FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: marker.path, contents: Data())
    }
}
