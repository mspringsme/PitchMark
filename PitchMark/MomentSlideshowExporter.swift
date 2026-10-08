//
//  MomentSlideshowExporter.swift
//  PitchMark
//
//  2026-09-30: builds one exported video from a Moment's user-arranged
//  `[SlideshowSegment]` (MomentSlideshow.swift) - photos and the video
//  stitched together in whatever order the editor saved.
//
//  A still photo isn't an AVAsset, so it can't be inserted into a
//  composition track the way MomentSpeedRamp.swift/OverlayExporter.swift
//  insert real video content. The first version of this file left each
//  `.photo` segment's span as an explicit *empty* range
//  (`insertEmptyTimeRange`) on the composition track, painting the photo
//  in over it via a CALayer sprite - that measurably does NOT work:
//  verified standalone (a synthetic red-video + green-photo composition,
//  outside the simulator) that `insertEmptyTimeRange` does not extend the
//  track's own `timeRange.end`/`composition.duration` the way
//  `insertTimeRange` does, so the whole trailing photo span silently
//  vanished from the export - reported by the user as "export completes,
//  but only the original video remains, no photo." Confirmed root cause
//  before writing this fix, not guessed.
//
//  Fix: a `.photo` segment's span is filled with *real* content instead -
//  the source video's own frames, looped as many times as needed to
//  cover the requested photo duration - inserted into both the video and
//  audio composition tracks via ordinary `insertTimeRange`, which does
//  reliably extend the tracks' reported duration (verified the same way).
//  The looped video frames are never actually seen: the photo's own
//  full-frame, opaque CALayer sprite sits on top of them for exactly that
//  span, same `AVVideoCompositionCoreAnimationTool` technique
//  OverlayExporter.swift already uses for overlay images (full-canvas and
//  constant-opacity here, instead of a small animated sprite). The looped
//  audio, left alone, WOULD be audible under the photo - silenced instead
//  via an `AVMutableAudioMix` that zeroes the composition audio track's
//  volume across every `.photo` segment's own span (see `buildAudioMix`).
//
//  Each segment is inserted at its own track's own actual frontier
//  (`compVideoTrack.timeRange.end`, `compAudioTrack.timeRange.end`
//  queried fresh each time, video and audio tracked independently) -
//  same "each track's own actual frontier, not a shared cursor my own
//  arithmetic advances" discipline `buildSpeedRampedComposition`
//  (MomentSpeedRamp.swift) already had to learn the hard way; see that
//  function's header comment for the on-device failure this avoids.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import AVFoundation
import UIKit

enum SlideshowExportError: Error {
    case noVideoTrack
    case compositionFailed
    case exportFailed
}

/// `AVMutableCompositionTrack.timeRange.end` is `kCMTimeInvalid` - not
/// `.zero` - for a track with no segments inserted yet; there's no
/// meaningful "end" of nothing. `insertTimeRange(at:)` happens to
/// tolerate that (Apple documents passing an invalid `startTime` as
/// "append to the end of the track"), which is exactly why this bug
/// compiled and ran without any error for every call *except* one: every
/// other use of this value here - recording a segment's own `start` for
/// the photo CALayer's `beginTime`, and for the audio mix's
/// `setVolume(at:)` below - needs a real numeric time, and
/// `AVMutableAudioMixInputParameters.setVolume(_:at:)` throws an
/// uncaught `NSException` ("The time of a volume setting must be
/// numeric") for a non-numeric one - a crash Swift's `catch` cannot
/// intercept, since it's a raised exception, not an `NSError`. This hit
/// on literally every export (confirmed via an on-device crash log,
/// `-[AVMutableAudioMixInputParameters setVolume:atTime:]`): the very
/// first segment processed always queries this on a still-empty track.
/// Normalizing here means every caller always gets a well-formed time,
/// rather than needing to remember this one track-state edge case itself.
func compositionTrackFrontier(_ track: AVMutableCompositionTrack) -> CMTime {
    let end = track.timeRange.end
    return end.isNumeric ? end : .zero
}

func exportSlideshowMoment(
    videoSourceURL: URL,
    segments: [SlideshowSegment],
    transitionsEnabled: Bool = false,
    resolvePhoto: @escaping (Int) -> UIImage?,
    completion: @escaping (Result<URL, Error>) -> Void
) {
    DispatchQueue.global(qos: .userInitiated).async {
        let sourceAsset = AVURLAsset(url: videoSourceURL)
        guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async { completion(.failure(SlideshowExportError.noVideoTrack)) }
            return
        }
        let sourceAudioTrack = sourceAsset.tracks(withMediaType: .audio).first
        let videoDuration = sourceAsset.duration
        // A `.photo` segment fills its span by looping chunks of this
        // duration (see the file header comment) - `CMTimeMinimum(_, 0)`
        // is `.zero`, which would make the fill loop below insert
        // zero-length ranges forever (`remainingVideo` never decreases)
        // and/or hand AVFoundation a degenerate `CMTimeRange`, which can
        // raise an uncaught Objective-C `NSException` - Swift's `catch`
        // below only catches `NSError`-bridged failures, not a raised
        // exception, so that crashes the app outright rather than
        // reporting a clean `.failure`. A real recorded Moment should
        // never have a zero/invalid duration; failing cleanly here if it
        // somehow does is cheap insurance against that crash.
        guard videoDuration.isValid, videoDuration > .zero else {
            DispatchQueue.main.async { completion(.failure(SlideshowExportError.noVideoTrack)) }
            return
        }

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            DispatchQueue.main.async { completion(.failure(SlideshowExportError.compositionFailed)) }
            return
        }
        let compAudioTrack: AVMutableCompositionTrack? = sourceAudioTrack != nil
            ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            : nil

        // Same preferredTransform-aware render size every exporter in
        // this feature uses - naturalSize alone is the raw pre-rotation
        // pixel size.
        let transform = sourceVideoTrack.preferredTransform
        let transformedSize = sourceVideoTrack.naturalSize.applying(transform)
        let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        guard renderSize.width > 0, renderSize.height > 0 else {
            DispatchQueue.main.async { completion(.failure(SlideshowExportError.compositionFailed)) }
            return
        }

        // See MomentSlideshow.swift's positionedSlideshowSegments doc
        // comment: only a photo's TRAILING edge ever shortens what gets
        // inserted here, and video is never shortened at all. That's
        // deliberate, not a simplification that loses anything - the
        // crossfade itself is produced entirely by the photo sprite's
        // opacity window extending beyond its own (shortened) track
        // insertion (see the sprite loop below), never by overlapping
        // track content. A video segment's content plays underneath a
        // neighboring photo's fade in BOTH directions unchanged, which is
        // exactly what makes "video dissolves into photo" (or the
        // reverse) look right with a single shared track and zero new
        // AVFoundation machinery - no second track, no overlapping
        // layerInstructions. There's always exactly one `.video` segment
        // in this feature (MomentSlideshow.swift), so a genuine
        // video<->video crossfade (which WOULD need two tracks
        // compositing simultaneously, since neither side has a sprite to
        // hide behind) can't occur - nothing here needs to handle it.
        let positioned = positionedSlideshowSegments(segments, videoDuration: videoDuration.seconds, transitionsEnabled: transitionsEnabled)

        struct PlacedSegment {
            let segment: SlideshowSegment
            let start: CMTime
            /// The segment's own full configured length, unaffected by
            /// any trailing shortening - what the sprite/audio-ramp
            /// windows below are sized against. What's ACTUALLY on the
            /// shared track (a photo's shortened filler, or the video's
            /// untouched full duration) only matters locally while
            /// inserting below; nothing downstream needs it.
            let nominalDuration: CMTime
            let leadingTransition: CMTime
            let trailingTransition: CMTime
        }
        var placed: [PlacedSegment] = []

        do {
            for item in positioned {
                let nominalDuration = CMTime(seconds: item.nominalDuration, preferredTimescale: 600)
                let leadingTransition = CMTime(seconds: item.leadingTransitionDuration, preferredTimescale: 600)
                let trailingTransition = CMTime(seconds: item.trailingTransitionDuration, preferredTimescale: 600)

                switch item.segment.kind {
                case .video:
                    let videoInsertAt = compositionTrackFrontier(compVideoTrack)
                    try compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: sourceVideoTrack, at: videoInsertAt)
                    if let sourceAudioTrack, let compAudioTrack {
                        let audioInsertAt = compositionTrackFrontier(compAudioTrack)
                        try compAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: sourceAudioTrack, at: audioInsertAt)
                    }
                    placed.append(PlacedSegment(segment: item.segment, start: videoInsertAt, nominalDuration: videoDuration, leadingTransition: leadingTransition, trailingTransition: trailingTransition))
                case .photo:
                    // Real content, looped to cover the requested span -
                    // see the file header comment for why this replaced
                    // `insertEmptyTimeRange`. Never actually seen (the
                    // photo's own opaque sprite covers it) or heard (the
                    // audio mix built below silences it) - shortening it
                    // on the trailing edge when a transition is active is
                    // exactly what lets the next segment's real content
                    // start early, which is what makes the overall export
                    // shorter than the simple sum of every segment's own
                    // nominal duration once transitions are on.
                    let insertedDuration = CMTimeMaximum(CMTimeSubtract(nominalDuration, trailingTransition), CMTime(seconds: 0.01, preferredTimescale: 600))
                    let videoInsertAt = compositionTrackFrontier(compVideoTrack)
                    var remainingVideo = insertedDuration
                    while remainingVideo > .zero {
                        let chunk = CMTimeMinimum(remainingVideo, videoDuration)
                        let insertAt = compositionTrackFrontier(compVideoTrack)
                        try compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: chunk), of: sourceVideoTrack, at: insertAt)
                        remainingVideo = CMTimeSubtract(remainingVideo, chunk)
                    }
                    if let sourceAudioTrack, let compAudioTrack {
                        var remainingAudio = insertedDuration
                        while remainingAudio > .zero {
                            let chunk = CMTimeMinimum(remainingAudio, videoDuration)
                            let insertAt = compositionTrackFrontier(compAudioTrack)
                            try compAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: chunk), of: sourceAudioTrack, at: insertAt)
                            remainingAudio = CMTimeSubtract(remainingAudio, chunk)
                        }
                    }
                    placed.append(PlacedSegment(segment: item.segment, start: videoInsertAt, nominalDuration: nominalDuration, leadingTransition: leadingTransition, trailingTransition: trailingTransition))
                }
            }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        // Base step function unchanged from before transitions existed -
        // mute during every photo span, full volume during the video
        // span, a new point only where the kind actually changes (see
        // the original comment on why: avoids emitting two points at the
        // exact same time for adjacent same-kind segments, which
        // `setVolume(_:at:)` requires strictly increasing times to avoid
        // corrupting). On top of that, the video segment's own two edges
        // get a smooth ramp instead of a hard step when a transition is
        // active there, so its audio fades in/out in step with the
        // neighboring photo's sprite rather than cutting abruptly under
        // a still-dissolving picture. Only the video needs this - a
        // photo's filler is always silent regardless of transitions, so
        // ramping "into" or "out of" silence on the photo's own side
        // would be a no-op anyway.
        var audioMix: AVMutableAudioMix? = nil
        if let compAudioTrack {
            let params = AVMutableAudioMixInputParameters(track: compAudioTrack)
            var previousKind: SlideshowSegmentKind? = nil
            for item in placed {
                if item.segment.kind == .video, item.leadingTransition > .zero {
                    params.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: CMTimeRange(start: item.start, duration: item.leadingTransition))
                } else if item.segment.kind != previousKind {
                    params.setVolume(item.segment.kind == .photo ? 0.0 : 1.0, at: item.start)
                }
                if item.segment.kind == .video, item.trailingTransition > .zero {
                    let rampStart = CMTimeAdd(item.start, CMTimeSubtract(item.nominalDuration, item.trailingTransition))
                    params.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: rampStart, duration: item.trailingTransition))
                }
                previousKind = item.segment.kind
            }
            let mix = AVMutableAudioMix()
            mix.inputParameters = [params]
            audioMix = mix
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
        // this feature - a bare CALayer tree used for AVFoundation
        // compositing defaults to Core Animation's bottom-left-origin,
        // Y-up coordinate system. Each photo sprite here is full-canvas
        // and centered, so the flip is inert for them in practice, but
        // kept for consistency with the rest of this file family rather
        // than relying on that coincidence.
        parentLayer.isGeometryFlipped = true
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        for item in placed where item.segment.kind == .photo {
            // `.cgImage` discards `UIImage.imageOrientation` entirely -
            // any photo stored with non-`.up` orientation (the normal
            // case for anything shot with the phone held upright; the
            // sensor is natively landscape) would export using its raw,
            // unrotated pixels instead of the correctly-rotated image
            // SwiftUI's `Image(uiImage:)` already displays everywhere
            // else in this app. `.normalizedUpOrientation()`
            // (Utilities.swift) bakes the rotation into real pixels
            // first - reported by the user as a photo exporting rotated
            // counter-clockwise.
            guard let photoIndex = item.segment.photoIndex, let cgImage = resolvePhoto(photoIndex)?.normalizedUpOrientation().cgImage else { continue }

            let layer = CALayer()
            layer.frame = CGRect(origin: .zero, size: renderSize)
            // Opaque black backing filling the *entire* canvas, painted
            // before the image itself - without this, a photo whose
            // aspect ratio doesn't match the video's render size leaves
            // this layer's own uncovered letterbox/pillarbox margins
            // transparent, and the looped filler *video* frames directly
            // behind this layer (the real bug the user reported: "images
            // overlapping the vid instead of adjacent") show through
            // exactly there. A solid backing is what makes this layer
            // truly full-canvas and opaque regardless of the photo's own
            // proportions, matching every ordinary slideshow tool's
            // letterbox convention rather than cropping the photo to fit.
            layer.backgroundColor = UIColor.black.cgColor
            layer.contents = cgImage
            // Same .resizeAspect reasoning as OverlayExporter's own
            // sprites (see [[feedback-calayer-contentsgravity-aspect]]) -
            // CALayer.contents defaults to stretch-to-fill, which would
            // distort any photo whose aspect ratio doesn't exactly match
            // the video's own render size. Combined with the black
            // backing above, a mismatched photo now letterboxes instead
            // of either distorting or leaking the video behind it.
            layer.contentsGravity = .resizeAspect
            // Model value while this photo's own animation isn't active
            // - invisible everywhere except its own [start, start+duration)
            // window below.
            layer.opacity = 0
            parentLayer.addSublayer(layer)

            // The animation window extends `leadingTransition` seconds
            // BEFORE this photo's own track insertion (still showing the
            // previous segment's real content, which a fade-in plays
            // over) and ends at the photo's full NOMINAL duration past
            // its insertion start, not its (possibly trailing-shortened)
            // inserted duration - the extra tail is where the next
            // segment's content has already begun, which a fade-out
            // reveals. With both transitions 0 (today's default, or
            // transitions disabled), `slideshowSpriteOpacityKeyframes`
            // collapses to exactly the original two-keyframe
            // "stay at 1" shape below - confirmed standalone.
            // `calculationMode = .linear` is required for the ramps to
            // actually ramp (not just snap) - between two EQUAL values
            // (the steady portions) linear interpolation is just a
            // constant, so this is strictly more general than the old
            // `.discrete`, not a behavior change for the non-transition
            // case. isRemovedOnCompletion = false is required for
            // AVVideoCompositionCoreAnimationTool specifically - see
            // OverlayExporter.swift's doc comment on the same property;
            // without it the offline renderer can treat the animation as
            // already expired before sampling a relevant frame, silently
            // dropping the photo from the export entirely.
            let (keyTimes, keyValues) = slideshowSpriteOpacityKeyframes(
                leadingTransitionDuration: item.leadingTransition.seconds,
                nominalDuration: item.nominalDuration.seconds,
                trailingTransitionDuration: item.trailingTransition.seconds
            )
            let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
            opacityAnimation.values = keyValues
            opacityAnimation.keyTimes = keyTimes.map { NSNumber(value: $0) }
            opacityAnimation.calculationMode = .linear
            opacityAnimation.beginTime = AVCoreAnimationBeginTimeAtZero + item.start.seconds - item.leadingTransition.seconds
            opacityAnimation.duration = max(item.nominalDuration.seconds + item.leadingTransition.seconds, 0.01)
            opacityAnimation.fillMode = .removed
            opacityAnimation.isRemovedOnCompletion = false
            layer.add(opacityAnimation, forKey: "opacity")
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            DispatchQueue.main.async { completion(.failure(SlideshowExportError.exportFailed)) }
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
                    completion(.failure(exportSession.error ?? SlideshowExportError.exportFailed))
                }
            }
        }
    }
}
