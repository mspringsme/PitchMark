//
//  MomentFilterExporter.swift
//  PitchMark
//
//  Bakes a color/brightness filter preset (MomentFilter.swift) into an
//  exported video via MomentFilterCompositor.swift's custom
//  AVVideoCompositing class, set as `customVideoCompositorClass` -
//  mutually exclusive with `animationTool` (the CALayer-based pipeline
//  every other exporter in this feature uses) on one
//  AVMutableVideoComposition, which is fine here: a plain 1:1 copy-
//  through composition (same shape as MomentFadeExporter.swift's
//  no-op case) with nothing else to composite.
//
//  Frozen-base ring member (joins Audio/Overlay/Zoom/Slideshow/Crop) -
//  reading its own frozen pre-filter base means every other visual
//  effect is already flattened to plain pixels by the time this runs,
//  so this exporter's custom compositor never needs to coexist with a
//  CALayer sprite tree in the same pass.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import AVFoundation

enum FilterExportError: Error {
    case noVideoTrack
    case compositionFailed
    case exportFailed
}

func exportFilteredMoment(sourceURL: URL, preset: FilterPreset, completion: @escaping (Result<URL, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let sourceAsset = AVURLAsset(url: sourceURL)
        guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async { completion(.failure(FilterExportError.noVideoTrack)) }
            return
        }
        let sourceAudioTrack = sourceAsset.tracks(withMediaType: .audio).first
        let duration = sourceAsset.duration
        guard duration.isValid, duration > .zero else {
            DispatchQueue.main.async { completion(.failure(FilterExportError.noVideoTrack)) }
            return
        }

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            DispatchQueue.main.async { completion(.failure(FilterExportError.compositionFailed)) }
            return
        }
        let compAudioTrack: AVMutableCompositionTrack? = sourceAudioTrack != nil
            ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            : nil

        do {
            try compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideoTrack, at: .zero)
            if let sourceAudioTrack, let compAudioTrack {
                try compAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceAudioTrack, at: .zero)
            }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        let transform = sourceVideoTrack.preferredTransform
        // Explicit, not inherited - same lesson every exporter in this
        // feature already applies (AVMutableCompositionTrack defaults to
        // identity on insert). A custom compositor's raw pixel access
        // doesn't use this for rotation (MomentFilterCompositor.swift
        // handles that itself via the instruction's own `transform`),
        // but other consumers of this composition/track (thumbnailing,
        // a still-frame extractor) do read it, so it's set for
        // consistency with the rest of this codebase regardless.
        compVideoTrack.preferredTransform = transform

        let transformedSize = sourceVideoTrack.naturalSize.applying(transform)
        let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        guard renderSize.width > 0, renderSize.height > 0 else {
            DispatchQueue.main.async { completion(.failure(FilterExportError.compositionFailed)) }
            return
        }

        let adjustment = filterAdjustment(for: preset)
        let instruction = MomentFilterInstruction(
            timeRange: CMTimeRange(start: .zero, duration: composition.duration),
            sourceTrackID: compVideoTrack.trackID,
            adjustment: adjustment,
            transform: transform
        )

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]
        videoComposition.customVideoCompositorClass = MomentFilterCompositor.self

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            DispatchQueue.main.async { completion(.failure(FilterExportError.exportFailed)) }
            return
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.videoComposition = videoComposition

        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                if exportSession.status == .completed {
                    completion(.success(outputURL))
                } else {
                    completion(.failure(exportSession.error ?? FilterExportError.exportFailed))
                }
            }
        }
    }
}
