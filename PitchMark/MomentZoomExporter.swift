//
//  MomentZoomExporter.swift
//  PitchMark
//
//  2026-09-30: burns `zoomRegions` (MomentZoom.swift) into an actual
//  video file. Same approach as OverlayExporter.swift - AVMutableComposition
//  + AVMutableVideoComposition + AVVideoCompositionCoreAnimationTool +
//  AVAssetExportSession - except the animation is applied directly to the
//  `postProcessingAsVideoLayer` video layer itself (position + transform),
//  not to a separate sprite sublayer sitting on top of it. No retiming
//  happens here (unlike MomentSpeedRamp.swift) - the whole source
//  duration is copied through at 1:1 speed, same as OverlayExporter.
//
//  `sampledZoomTransforms` samples `zoomTransform(at:)` directly at a
//  fixed interval instead of trying to reproduce its hold/linear timing
//  through Core Animation's own keyframe timing curves - guarantees the
//  export shows exactly what the live preview computes, same reasoning
//  as OverlayExporter's own doc comment.
//
//  Returns a temp file URL on success, same contract as every other
//  exporter in this feature - the caller decides where it belongs
//  (MomentZoomEditorView copies it into localMomentEditedVideoURL).
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import AVFoundation
import UIKit

enum ZoomExportError: Error {
    case noVideoTrack
    case compositionFailed
    case exportFailed
}

/// The interval export samples `zoomTransform(at:)` at, matching the
/// other exporters' own cadence (OverlayExporter, 1/30s).
private let zoomExportSampleInterval = 1.0 / 30.0

func exportZoomedMoment(sourceURL: URL, regions: [ZoomRegion], completion: @escaping (Result<URL, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let sourceAsset = AVURLAsset(url: sourceURL)
        guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async { completion(.failure(ZoomExportError.noVideoTrack)) }
            return
        }
        let sourceAudioTrack = sourceAsset.tracks(withMediaType: .audio).first

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            DispatchQueue.main.async { completion(.failure(ZoomExportError.compositionFailed)) }
            return
        }

        do {
            try compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: sourceAsset.duration), of: sourceVideoTrack, at: .zero)
            if let sourceAudioTrack, let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try compAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: sourceAsset.duration), of: sourceAudioTrack, at: .zero)
            }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        // Same preferredTransform-aware render size every exporter in
        // this feature uses - naturalSize alone is the raw pre-rotation
        // pixel size.
        let transform = sourceVideoTrack.preferredTransform
        let transformedSize = sourceVideoTrack.naturalSize.applying(transform)
        let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        guard renderSize.width > 0, renderSize.height > 0 else {
            DispatchQueue.main.async { completion(.failure(ZoomExportError.compositionFailed)) }
            return
        }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        // Same isGeometryFlipped reasoning as OverlayExporter.swift - a
        // bare CALayer tree used for AVFoundation compositing defaults to
        // Core Animation's bottom-left-origin, Y-up coordinate system,
        // not the top-left-origin, Y-down one `zoomLayerPosition` and
        // every normalized center value in this feature already assume.
        // Flipping the parent makes `videoLayer`'s own position interpret
        // Y the same way UIKit does; it does not flip the decoded video
        // frames themselves.
        parentLayer.isGeometryFlipped = true
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        let duration = composition.duration.seconds
        let (times, transforms) = sampledZoomTransforms(regions: regions, duration: duration, sampleInterval: zoomExportSampleInterval)

        if let firstTransform = transforms.first {
            let animDuration = max(duration, 0.01)
            let keyTimes = times.map { NSNumber(value: $0 / animDuration) }
            let beginTime = AVCoreAnimationBeginTimeAtZero

            let positionAnimation = CAKeyframeAnimation(keyPath: "position")
            positionAnimation.values = transforms.map {
                NSValue(cgPoint: zoomLayerPosition(center: $0.center, scale: $0.scale, renderSize: renderSize))
            }
            positionAnimation.keyTimes = keyTimes
            positionAnimation.calculationMode = .linear
            positionAnimation.beginTime = beginTime
            positionAnimation.duration = animDuration
            positionAnimation.fillMode = .removed
            // isRemovedOnCompletion = false is required for
            // AVVideoCompositionCoreAnimationTool specifically - see
            // OverlayExporter.swift's doc comment on the same property.
            // Without it the offline renderer can treat the animation as
            // already expired before sampling a relevant frame, silently
            // leaving the video at its very first frame's zoom for the
            // whole export.
            positionAnimation.isRemovedOnCompletion = false
            videoLayer.add(positionAnimation, forKey: "position")

            let transformAnimation = CAKeyframeAnimation(keyPath: "transform")
            transformAnimation.values = transforms.map { NSValue(caTransform3D: CATransform3DMakeScale($0.scale, $0.scale, 1)) }
            transformAnimation.keyTimes = keyTimes
            transformAnimation.calculationMode = .linear
            transformAnimation.beginTime = beginTime
            transformAnimation.duration = animDuration
            transformAnimation.fillMode = .removed
            transformAnimation.isRemovedOnCompletion = false
            videoLayer.add(transformAnimation, forKey: "transform")

            // Model values while no animation is active - shouldn't
            // matter given beginTime 0 spans the whole export, but kept
            // for clarity/safety, matching the first sampled frame.
            videoLayer.position = zoomLayerPosition(center: firstTransform.center, scale: firstTransform.scale, renderSize: renderSize)
            videoLayer.transform = CATransform3DMakeScale(firstTransform.scale, firstTransform.scale, 1)
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            DispatchQueue.main.async { completion(.failure(ZoomExportError.exportFailed)) }
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
                    completion(.failure(exportSession.error ?? ZoomExportError.exportFailed))
                }
            }
        }
    }
}
