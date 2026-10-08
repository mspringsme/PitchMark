//
//  MomentThumbnail.swift
//  PitchMark
//
//  2026-10-04: a real thumbnail for each Moment, needed everywhere the
//  Moments browsing UI moved from plain text rows to a visual grid
//  (MomentsLibraryView's "All" grid, Folder/Bucket tiles and grids).
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import AVFoundation
import UIKit

/// In-memory only, keyed by the backing video file's own modification
/// date rather than just the Moment's id - an edit that re-exports the
/// video changes its mtime, which changes the key, so a stale thumbnail
/// can never survive an edit. No disk persistence, no separate
/// invalidation bookkeeping to get wrong - same bug class this codebase
/// keeps hitting with cached previews
/// ([[feedback-stale-async-preview-rebuild-race]]), sidestepped for free.
private let momentThumbnailCache = NSCache<NSString, UIImage>()

private func momentThumbnailCacheKey(momentId: String, videoURL: URL) -> NSString {
    let attributes = try? FileManager.default.attributesOfItem(atPath: videoURL.path)
    let mtime = attributes?[.modificationDate] as? Date
    return "\(momentId)-\(mtime?.timeIntervalSinceReferenceDate ?? 0)" as NSString
}

/// Grabs one frame from whatever's currently "the" video for this Moment
/// (`resolvedMomentPlaybackURL` - faded, else edited, else original, the
/// same priority every playback/duplicate path already uses), at a short
/// fixed offset rather than time zero so a freeze-frame/filter Moment
/// isn't mistaken for a blank first frame. Same `AVAssetImageGenerator` +
/// `appliesPreferredTrackTransform` pattern `MomentFilterEditorView.swift`'s
/// `loadFrameAndSwatches` already uses for an in-editor frame grab.
func momentThumbnail(for moment: Moment, completion: @escaping (UIImage?) -> Void) {
    guard let momentId = moment.id, let videoURL = resolvedMomentPlaybackURL(for: momentId) else {
        completion(nil)
        return
    }

    let cacheKey = momentThumbnailCacheKey(momentId: momentId, videoURL: videoURL)
    if let cached = momentThumbnailCache.object(forKey: cacheKey) {
        completion(cached)
        return
    }

    DispatchQueue.global(qos: .userInitiated).async {
        let asset = AVURLAsset(url: videoURL)
        let duration = asset.duration
        guard duration.isValid, duration > .zero else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let offset = CMTimeMinimum(CMTime(seconds: 0.1, preferredTimescale: 600), duration)
        guard let cgImage = try? generator.copyCGImage(at: offset, actualTime: nil) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let image = UIImage(cgImage: cgImage)
        momentThumbnailCache.setObject(image, forKey: cacheKey)
        DispatchQueue.main.async { completion(image) }
    }
}
