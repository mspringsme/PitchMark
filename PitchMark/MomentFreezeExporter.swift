//
//  MomentFreezeExporter.swift
//  PitchMark
//
//  Bakes a freeze-frame / replay callout (MomentFreeze.swift) into an
//  exported video: hold one frame for a fixed duration, optionally
//  zooming in and/or showing a text callout over it.
//
//  Direct-chain editor, a sibling of Trim/Speed - NOT a frozen-base ring
//  member. A freeze inserts dead time partway through the clip,
//  distorting when everything else happens on the timeline, exactly the
//  effect that forced Speed-ramp (MomentSpeedRamp.swift) to need a
//  timeline remap in the first place - see `remapAllTimeBasedFields`
//  (Moment.swift), generalized from Speed's own remap specifically so
//  this file could reuse it rather than duplicating that field list.
//
//  The held span is filled with real looped source frames (an opaque
//  still-image sprite painted on top, the looped audio silenced) -
//  the exact technique MomentSlideshowExporter.swift already proved
//  correct for its own `.photo` segments, reused verbatim rather than
//  rediscovering why `insertEmptyTimeRange` silently drops trailing
//  content (see that file's header comment for the on-device crash this
//  avoids). Unlike that file, video and audio here are always inserted
//  in exact lockstep (every range - pre-freeze, each loop chunk,
//  post-freeze - is applied identically to both tracks at the same
//  position), so one shared `cursor`, not each track's own queried
//  frontier, drives every insert - same reasoning
//  HighlightReelExporter.swift's header comment gives for its own choice
//  of a shared cursor over per-track frontiers.
//
//  The still frame itself comes from `AVAssetImageGenerator`, unused
//  anywhere else in this codebase - `requestedTimeToleranceBefore`/
//  `After` are explicitly zeroed to force an exact-frame decode rather
//  than snapping to the nearest keyframe (a well-documented AVFoundation
//  gotcha), and `appliesPreferredTrackTransform = true` bakes the
//  source's own rotation into the still image directly, so the sprite
//  needs no extra transform of its own to match `renderSize`.
//
//  Optional zoom-in during the hold reuses `zoomLayerPosition`
//  (MomentZoom.swift) - the exact same position+transform keyframe
//  technique MomentZoomExporter.swift uses, just two keyframes (hold
//  start/end) instead of a sampled curve, and applied to the still
//  sprite instead of the live video layer. Optional callout reuses
//  `buildTextCardLayer` (OverlayExporter.swift) - the same two-line
//  template card every visual overlay uses.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import AVFoundation
import UIKit

enum FreezeExportError: Error {
    case noVideoTrack
    case stillFrameExtractionFailed
    case compositionFailed
    case exportFailed
}

/// How long the automatic zoom-out back to normal takes, right before
/// the hold ends - a fixed, quick default rather than a user-exposed
/// slider, same "fixed quick default" shape `momentFadeDuration`
/// (MomentFadeExporter.swift) already settled on for the whole-clip
/// fade. Not user-adjustable; clamped per-use to at most half the hold
/// duration (see its call site) so a very short hold can't invert the
/// zoom-in/zoom-out ordering.
let freezeZoomQuickOutDuration: Double = 0.3

/// Lower-third anchor for the optional callout card, as a fraction of
/// `min(renderSize.width, renderSize.height)` - same sizing convention
/// `overlayTextWidthFraction`/`overlayTextHeightFraction` (Overlay.swift)
/// already establish, just a fixed placement instead of a user-dragged
/// one (there's no drag UI for a freeze callout - confirmed scope is a
/// single static card, broadcast-lower-third style). Internal, not
/// private - MomentFreezeEditorView.swift reuses these same three
/// numbers for its own live preview overlay, so the editor's callout
/// position/size can't silently drift from where export actually places
/// it.
let freezeCalloutWidthFraction: CGFloat = 0.8
let freezeCalloutHeightFraction: CGFloat = 0.22
let freezeCalloutVerticalCenterFraction: CGFloat = 0.82

func exportFrozenMoment(sourceURL: URL, freezeFrame: FreezeFrame, completion: @escaping (Result<URL, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let sourceAsset = AVURLAsset(url: sourceURL)
        guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async { completion(.failure(FreezeExportError.noVideoTrack)) }
            return
        }
        let sourceAudioTrack = sourceAsset.tracks(withMediaType: .audio).first
        let videoDuration = sourceAsset.duration
        guard videoDuration.isValid, videoDuration > .zero else {
            DispatchQueue.main.async { completion(.failure(FreezeExportError.noVideoTrack)) }
            return
        }

        let totalSeconds = videoDuration.seconds
        let clampedTimestamp = min(max(freezeFrame.timestamp, 0), totalSeconds)
        let holdSeconds = max(freezeFrame.holdDuration, 0.1)
        let freezeTime = CMTime(seconds: clampedTimestamp, preferredTimescale: 600)
        let holdDuration = CMTime(seconds: holdSeconds, preferredTimescale: 600)

        let imageGenerator = AVAssetImageGenerator(asset: sourceAsset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        guard let stillCGImage = try? imageGenerator.copyCGImage(at: freezeTime, actualTime: nil) else {
            DispatchQueue.main.async { completion(.failure(FreezeExportError.stillFrameExtractionFailed)) }
            return
        }

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            DispatchQueue.main.async { completion(.failure(FreezeExportError.compositionFailed)) }
            return
        }
        let compAudioTrack: AVMutableCompositionTrack? = sourceAudioTrack != nil
            ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            : nil

        var cursor = CMTime.zero
        // The hold loop's actual inserted duration can differ from the
        // nominal `holdDuration` by a tiny rounding epsilon - its chunks
        // are computed via CMTimeMinimum/CMTimeSubtract in the source's
        // own native timescale, while `holdDuration` was built at a
        // fixed 600 timescale. Capturing the REAL cursor position right
        // after the loop (rather than recomputing `freezeTime + holdDuration`
        // separately below) is required, not just tidier - this
        // codebase has already hit the exact failure mode a mismatch
        // here produces, twice: `AVMutableAudioMixInputParameters
        // .setVolume(_:at:)` throws an uncaught NSException (not
        // catchable by Swift's `catch`) for a time that ends up outside
        // the composition's real content, which is silent and
        // indistinguishable from "nothing happened" to the user - see
        // MomentSlideshowExporter.swift's header comment for the
        // on-device crash this exact class of bug caused before.
        var holdEndCursor = CMTime.zero
        do {
            // Pre-freeze content, unchanged.
            if freezeTime > .zero {
                try compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: freezeTime), of: sourceVideoTrack, at: cursor)
                if let sourceAudioTrack, let compAudioTrack {
                    try compAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: freezeTime), of: sourceAudioTrack, at: cursor)
                }
                cursor = CMTimeAdd(cursor, freezeTime)
            }

            // The hold span - real looped frames (never actually seen;
            // the still sprite below covers them) so the track's
            // reported duration genuinely extends, same fix
            // MomentSlideshowExporter.swift's header comment documents
            // for `insertEmptyTimeRange`'s silent failure.
            var remainingHold = holdDuration
            while remainingHold > .zero {
                let chunk = CMTimeMinimum(remainingHold, videoDuration)
                try compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: chunk), of: sourceVideoTrack, at: cursor)
                if let sourceAudioTrack, let compAudioTrack {
                    try compAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: chunk), of: sourceAudioTrack, at: cursor)
                }
                cursor = CMTimeAdd(cursor, chunk)
                remainingHold = CMTimeSubtract(remainingHold, chunk)
            }
            holdEndCursor = cursor

            // Post-freeze content, unchanged, resumed from exactly where
            // the hold interrupted it.
            let postDuration = CMTimeSubtract(videoDuration, freezeTime)
            if postDuration > .zero {
                try compVideoTrack.insertTimeRange(CMTimeRange(start: freezeTime, duration: postDuration), of: sourceVideoTrack, at: cursor)
                if let sourceAudioTrack, let compAudioTrack {
                    try compAudioTrack.insertTimeRange(CMTimeRange(start: freezeTime, duration: postDuration), of: sourceAudioTrack, at: cursor)
                }
                cursor = CMTimeAdd(cursor, postDuration)
            }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        // Silences the looped filler audio under the held frame only -
        // same plain step-function mix MomentSlideshowExporter.swift
        // uses for its own `.photo` spans. The `freezeTime > .zero`
        // guard avoids two points at the exact same time (a freeze right
        // at the clip's start), the identical collision
        // MomentSlideshowExporter.swift's header comment already flags.
        var audioMix: AVMutableAudioMix? = nil
        if let compAudioTrack {
            let params = AVMutableAudioMixInputParameters(track: compAudioTrack)
            if freezeTime > .zero {
                params.setVolume(1.0, at: .zero)
            }
            params.setVolume(0.0, at: freezeTime)
            params.setVolume(1.0, at: holdEndCursor)
            let mix = AVMutableAudioMix()
            mix.inputParameters = [params]
            audioMix = mix
        }

        let transform = sourceVideoTrack.preferredTransform
        let transformedSize = sourceVideoTrack.naturalSize.applying(transform)
        let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        guard renderSize.width > 0, renderSize.height > 0 else {
            DispatchQueue.main.async { completion(.failure(FreezeExportError.compositionFailed)) }
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
        // Same isGeometryFlipped reasoning as every other exporter in
        // this feature - zoomLayerPosition and the callout's fixed
        // anchor both assume a top-left-origin, Y-down space.
        parentLayer.isGeometryFlipped = true
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        let holdBeginSeconds = freezeTime.seconds
        // The real inserted span, not the nominal `holdDuration` - see
        // `holdEndCursor`'s doc comment above. Keeps the still sprite's
        // visible window lined up exactly with the looped filler content
        // it's covering, rather than risking it end a hair before/after
        // the real post-freeze content resumes.
        let holdAnimDuration = max(CMTimeSubtract(holdEndCursor, freezeTime).seconds, 0.01)

        // The still-frame sprite - opaque full canvas, visible only
        // during [freezeTime, freezeTime + holdDuration). Same opaque
        // black backing + .resizeAspect letterbox convention
        // MomentSlideshowExporter.swift's photo sprites already use.
        let stillLayer = CALayer()
        stillLayer.frame = CGRect(origin: .zero, size: renderSize)
        stillLayer.backgroundColor = UIColor.black.cgColor
        stillLayer.contents = stillCGImage
        stillLayer.contentsGravity = .resizeAspect
        stillLayer.opacity = 0
        parentLayer.addSublayer(stillLayer)

        let visibilityAnimation = CAKeyframeAnimation(keyPath: "opacity")
        visibilityAnimation.values = [1, 1]
        visibilityAnimation.keyTimes = [0, 1]
        visibilityAnimation.calculationMode = .discrete
        visibilityAnimation.beginTime = AVCoreAnimationBeginTimeAtZero + holdBeginSeconds
        visibilityAnimation.duration = holdAnimDuration
        visibilityAnimation.fillMode = .removed
        // isRemovedOnCompletion = false required for
        // AVVideoCompositionCoreAnimationTool - see
        // OverlayExporter.swift's doc comment on the same property;
        // without it the offline renderer can treat the animation as
        // already expired before sampling a relevant frame, silently
        // dropping the still frame from the export entirely.
        visibilityAnimation.isRemovedOnCompletion = false
        stillLayer.add(visibilityAnimation, forKey: "opacity")

        if freezeFrame.zoomEnabled {
            // Start centered/unscaled (the frozen frame as actually
            // extracted) - the user-adjustable zoom center only applies
            // to where the hold ENDS UP by the end of the hold.
            let startTransform = ZoomTransform(center: CGPoint(x: 0.5, y: 0.5), scale: 1.0)
            let endTransform = ZoomTransform(center: freezeFrame.zoomCenter, scale: max(freezeFrame.zoomScale, minZoomScale))
            let beginTime = AVCoreAnimationBeginTimeAtZero + holdBeginSeconds

            // A quick zoom-out back to normal right before the hold
            // ends, rather than holding at full zoom until the still
            // sprite disappears and the real video resumes at its
            // normal framing simultaneously - that combination (scale
            // AND visibility both snapping at once) read as a jump cut.
            // Clamped to at most half the hold so a very short hold
            // can't invert the zoom-in/zoom-out ordering.
            let zoomOutSeconds = min(freezeZoomQuickOutDuration, holdAnimDuration / 2)
            let zoomInEndFraction = max(1 - zoomOutSeconds / holdAnimDuration, 0)
            let transforms = [startTransform, endTransform, startTransform]
            let keyTimes: [NSNumber] = [0, NSNumber(value: zoomInEndFraction), 1]

            let positionAnimation = CAKeyframeAnimation(keyPath: "position")
            positionAnimation.values = transforms.map {
                NSValue(cgPoint: zoomLayerPosition(center: $0.center, scale: $0.scale, renderSize: renderSize))
            }
            positionAnimation.keyTimes = keyTimes
            positionAnimation.calculationMode = .linear
            positionAnimation.beginTime = beginTime
            positionAnimation.duration = holdAnimDuration
            positionAnimation.fillMode = .removed
            positionAnimation.isRemovedOnCompletion = false
            stillLayer.add(positionAnimation, forKey: "position")

            let transformAnimation = CAKeyframeAnimation(keyPath: "transform")
            transformAnimation.values = transforms.map {
                NSValue(caTransform3D: CATransform3DMakeScale($0.scale, $0.scale, 1))
            }
            transformAnimation.keyTimes = keyTimes
            transformAnimation.calculationMode = .linear
            transformAnimation.beginTime = beginTime
            transformAnimation.duration = holdAnimDuration
            transformAnimation.fillMode = .removed
            transformAnimation.isRemovedOnCompletion = false
            stillLayer.add(transformAnimation, forKey: "transform")
        }

        if let callout = freezeFrame.callout {
            let cardSize = CGSize(
                width: freezeCalloutWidthFraction * min(renderSize.width, renderSize.height),
                height: freezeCalloutHeightFraction * min(renderSize.width, renderSize.height)
            )
            let cardLayer = buildTextCardLayer(callout, size: cardSize)
            cardLayer.position = CGPoint(x: renderSize.width / 2, y: renderSize.height * freezeCalloutVerticalCenterFraction)
            cardLayer.bounds = CGRect(origin: .zero, size: cardSize)
            cardLayer.opacity = 0
            parentLayer.addSublayer(cardLayer)

            let calloutAnimation = CAKeyframeAnimation(keyPath: "opacity")
            calloutAnimation.values = [1, 1]
            calloutAnimation.keyTimes = [0, 1]
            calloutAnimation.calculationMode = .discrete
            calloutAnimation.beginTime = AVCoreAnimationBeginTimeAtZero + holdBeginSeconds
            calloutAnimation.duration = holdAnimDuration
            calloutAnimation.fillMode = .removed
            calloutAnimation.isRemovedOnCompletion = false
            cardLayer.add(calloutAnimation, forKey: "opacity")
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            DispatchQueue.main.async { completion(.failure(FreezeExportError.exportFailed)) }
            return
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.videoComposition = videoComposition
        exportSession.audioMix = audioMix

        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                if exportSession.status == .completed {
                    completion(.success(outputURL))
                } else {
                    completion(.failure(exportSession.error ?? FreezeExportError.exportFailed))
                }
            }
        }
    }
}
