//
//  MomentCropExporter.swift
//  PitchMark
//
//  Bakes a static aspect-ratio crop/reframe (MomentCrop.swift) into an
//  exported video. Simpler than MomentZoomExporter: no CALayer sprite
//  tree or AVVideoCompositionCoreAnimationTool needed at all, since a
//  static crop has nothing to animate - a single
//  AVMutableVideoCompositionLayerInstruction transform does the whole
//  job, same minimal shape MomentFadeExporter.swift uses for its
//  no-op "both toggles off" case.
//
//  The one genuinely new wrinkle versus every other exporter in this
//  feature: `videoComposition.renderSize` is set to the TARGET aspect's
//  pixel size (`cropRenderSize`), not derived from the source. Every
//  other exporter sets renderSize from the source track's own
//  preferredTransform-rotated size because they never change the
//  canvas shape, only what's drawn on it.
//
//  Frozen-base ring member (joins Audio/Overlay/Zoom/Slideshow) - see
//  Moment.swift's invalidateOtherFrozenBases doc comment. Placed in the
//  ring (not Fade's separate-final-pass shape) deliberately: baking the
//  new framing destructively into the shared edited video means every
//  downstream editor (Fade included, since Fade reads
//  resolvedMomentVideoURL fresh every run) picks up the new framing
//  automatically, since they all already derive their own geometry from
//  whatever the current track's preferredTransform/naturalSize is.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import AVFoundation

enum CropExportError: Error {
    case noVideoTrack
    case compositionFailed
    case exportFailed
}

func exportCroppedMoment(sourceURL: URL, cropSettings: CropSettings, completion: @escaping (Result<URL, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        guard cropSettings.aspect != .original else {
            // Same no-op shape MomentFadeExporter.swift uses when both
            // toggles are off: nothing to bake, hand back the source
            // unchanged rather than a pointless re-encode.
            DispatchQueue.main.async { completion(.success(sourceURL)) }
            return
        }

        let sourceAsset = AVURLAsset(url: sourceURL)
        guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async { completion(.failure(CropExportError.noVideoTrack)) }
            return
        }
        let sourceAudioTrack = sourceAsset.tracks(withMediaType: .audio).first
        let duration = sourceAsset.duration
        guard duration.isValid, duration > .zero else {
            DispatchQueue.main.async { completion(.failure(CropExportError.noVideoTrack)) }
            return
        }

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            DispatchQueue.main.async { completion(.failure(CropExportError.compositionFailed)) }
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
        let transformedSize = sourceVideoTrack.naturalSize.applying(transform)
        let sourceSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            DispatchQueue.main.async { completion(.failure(CropExportError.compositionFailed)) }
            return
        }

        let renderSize = cropRenderSize(sourceSize: sourceSize, aspect: cropSettings.aspect)
        guard renderSize.width > 0, renderSize.height > 0 else {
            DispatchQueue.main.async { completion(.failure(CropExportError.compositionFailed)) }
            return
        }

        let (scale, position) = cropLayerGeometry(sourceSize: sourceSize, targetRenderSize: renderSize, offset: cropSettings.offset)
        let crop = CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: position.x, y: position.y))
        let finalTransform = transform.concatenating(crop)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
        layerInstruction.setTransform(finalTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            DispatchQueue.main.async { completion(.failure(CropExportError.exportFailed)) }
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
                    completion(.failure(exportSession.error ?? CropExportError.exportFailed))
                }
            }
        }
    }
}
