//
//  HighlightReelExporter.swift
//  PitchMark
//
//  Concatenates several Moments' already-finished output
//  (resolvedMomentPlaybackURL - so a reel picks up each clip's current
//  fade/trim/overlay/zoom/etc. exactly as a viewer would see it today)
//  into one exported video.
//
//  Source clips can differ in aspect ratio/resolution (e.g. one already
//  Crop'd to 9:16 next to an original 16:9 clip), so this builds one
//  AVMutableVideoComposition with a SEPARATE AVMutableVideoCompositionInstruction
//  per clip - the first multi-instruction composition in this codebase
//  (every existing Moment exporter uses one instruction spanning the
//  whole timeline, since they only ever touch one clip at a time). This
//  is standard, documented AVFoundation structure, not custom-compositor
//  territory.
//
//  Each clip gets a letterbox-fit transform (fitTransform below) rather
//  than being cropped/stretched to the canonical render size - matching
//  the ordinary "fit, pillarbox/letterbox if needed" convention
//  MomentSlideshowExporter.swift already uses for photos (there via an
//  opaque black CALayer backing; here there's no CALayer tree at all -
//  a video composition with no animationTool renders any area a frame's
//  instruction doesn't cover as opaque black by default, so no backing
//  layer is needed for a plain transform-only instruction).
//
//  2026-10-06: an optional crossfade between adjacent clips
//  (`transitionsEnabled`). This is a genuinely different case from every
//  other transition in this app's Moments feature set:
//  MomentSlideshowExporter.swift's photo<->video crossfade gets away with
//  a SINGLE shared composition track (a photo's opaque sprite just sits
//  over looped filler video frames) specifically because there's always
//  exactly one real video source in that feature - see that file's own
//  comment on why a genuine video<->video crossfade "can't occur" there.
//  Here it's the opposite: every clip is real video, so two clips being
//  simultaneously visible during a dissolve needs two DIFFERENT
//  composition tracks (one track can only ever play one source at a
//  given instant) - the standard "ping-pong" technique: even-indexed
//  clips go on track A, odd-indexed on track B, so any two ADJACENT
//  clips (the only ones that ever overlap) always land on different
//  tracks. Each overlap window gets its own
//  `AVMutableVideoCompositionInstruction` with TWO layer instructions;
//  only the incoming (topmost) layer needs an opacity ramp (0->1) - the
//  outgoing layer underneath stays fully opaque the whole time, since
//  standard "over" alpha compositing alone already produces a correct
//  linear dissolve without also ramping the bottom layer down.
//
//  Audio doesn't get this "only ramp one side" shortcut - two audio
//  tracks played simultaneously SUM rather than alpha-blend, so both
//  the outgoing (1->0) and incoming (0->1) tracks need a volume ramp
//  during their shared overlap, same two-sided
//  `AVMutableAudioMixInputParameters.setVolumeRamp` shape
//  MomentSlideshowExporter.swift's own audio mix already uses at its
//  video segment's edges.
//
//  Clips are placed end-to-end via one explicit `cursor` CMTime, not each
//  track's own queried frontier (compositionTrackFrontier, as
//  MomentSlideshowExporter.swift/MomentSpeedRamp.swift use) - those files
//  need per-track frontiers because a single segment can insert multiple
//  chunks into one track at different counts for video vs. audio
//  (looped filler). Here video and audio for one clip always share the
//  exact same start and duration, so a single shared cursor, advanced by
//  this clip's duration after both inserts, can't drift the two tracks
//  apart the way separately-queried frontiers could if one track's
//  insert for a clip were ever skipped (e.g. a clip with no audio track)
//  while the other's wasn't. With transitions on, `positionedReelClips`
//  computes each clip's explicit start time up front instead (needed
//  either way, since a crossfading clip's start isn't simply "after the
//  previous one ends").
//
//  `positionedReelClips` operates on real `CMTime` values end to end -
//  NOT `Double` seconds reconstructed into CMTime at each use - on
//  purpose. The first version used Double for this (and was standalone-
//  verifiable without CoreMedia as a result), but shipped a real bug:
//  an instruction boundary rebuilt from `clip.duration.seconds` can land
//  on a different 1/600s tick than the SAME boundary derived from
//  `clip.duration` (the real CMTime) during the actual `insertTimeRange`
//  call, because the two paths round at different points.
//  `AVMutableVideoComposition` requires its instructions to tile the
//  composition's real duration exactly - even a single tick of mismatch
//  gets the whole export rejected immediately by `AVAssetExportSession`
//  (confirmed on-device: failed instantly with "operation stopped," the
//  classic symptom of this exact class of bug - see
//  [[feedback-avcomposition-pertrack-cursor]], confirmed a 5th time
//  here). Working natively in CMTime (CMTimeAdd/CMTimeSubtract/
//  CMTimeMinimum/CMTimeMultiplyByRatio, never `.seconds` mid-pipeline)
//  means the tested placement math and the real insertion code are
//  bit-identical, not just numerically close. `CMTime` itself has no
//  AVFoundation/asset dependency, so this is still standalone-verifiable
//  with a plain `import CoreMedia` script - just not with plain `Double`.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import AVFoundation

enum HighlightReelExportError: Error {
    case noClips
    case noVideoTrack
    case compositionFailed
    case exportFailed
}

/// Pure letterbox-fit math: how to scale and position a clip whose own
/// (already preferredTransform-rotated) size is `sourceSize` so it fits
/// entirely inside `targetRenderSize`, centered, without cropping or
/// distorting it. `position` is the top-left of the scaled frame once
/// centered - the letterbox/pillarbox margin on each side is implicit
/// (targetRenderSize minus the scaled size, halved).
func fitTransform(sourceSize: CGSize, targetRenderSize: CGSize) -> (scale: CGFloat, position: CGPoint) {
    guard sourceSize.width > 0, sourceSize.height > 0, targetRenderSize.width > 0, targetRenderSize.height > 0 else {
        return (1, .zero)
    }
    let scale = min(targetRenderSize.width / sourceSize.width, targetRenderSize.height / sourceSize.height)
    let scaledWidth = sourceSize.width * scale
    let scaledHeight = sourceSize.height * scale
    let position = CGPoint(
        x: (targetRenderSize.width - scaledWidth) / 2,
        y: (targetRenderSize.height - scaledHeight) / 2
    )
    return (scale, position)
}

/// Default crossfade length between adjacent clips when the fade toggle
/// is on - deliberately short ("very fast"): a reel splices full, often
/// multi-second clips end-to-end, where a lingering dissolve would read
/// as sluggish rather than snappy. Fixed, not a per-transition slider -
/// same "fixed quick default" shape MomentSlideshow.swift's own
/// defaultSlideshowTransitionDuration already settled on for the same
/// reason, just shorter. A plain Double is fine here specifically
/// because it's converted to CMTime exactly ONCE, at the single call
/// site below - it never gets re-derived or round-tripped mid-pipeline,
/// which is the part that actually has to stay in CMTime.
let defaultHighlightReelTransitionDuration: Double = 0.2

/// One clip's placement once crossfades are laid out - which of the two
/// alternating composition tracks it lands on, its position on the
/// FINAL spliced timeline, and the (already-clamped) overlap shared with
/// each neighbor. Pure CMTime math, no asset/AVURLAsset dependency -
/// standalone-verifiable with a plain `import CoreMedia` script, the
/// same way MomentSlideshow.swift's positionedSlideshowSegments is
/// verifiable with plain Double (CMTime itself needs no simulator or
/// real media file, just the CoreMedia framework).
struct PositionedReelClip: Equatable {
    let index: Int
    let trackIndex: Int
    let duration: CMTime
    let start: CMTime
    let leadingOverlap: CMTime
    let trailingOverlap: CMTime
}

/// Each shared overlap is clamped to at most half of EACH of the two
/// clips it sits between - same discipline, same reason, as
/// MomentSlideshow.swift's positionedSlideshowSegments: a transition can
/// never make a clip "disappear" or invert clip order. With
/// transitions off (or only one clip), this collapses to plain
/// end-to-end placement with every clip on track 0 - confirmed via the
/// standalone verification script, no behavior change from the simple
/// concatenation case. `CMTimeMultiplyByRatio` (exact rational halving,
/// Int32 multiplier/divisor) rather than `.seconds / 2` is what keeps
/// this whole function free of any lossy Double arithmetic.
func positionedReelClips(durations: [CMTime], transitionDuration: CMTime, transitionsEnabled: Bool) -> [PositionedReelClip] {
    guard transitionsEnabled, durations.count > 1, transitionDuration > .zero else {
        var start = CMTime.zero
        return durations.enumerated().map { index, duration in
            let clip = PositionedReelClip(index: index, trackIndex: 0, duration: duration, start: start, leadingOverlap: .zero, trailingOverlap: .zero)
            start = CMTimeAdd(start, duration)
            return clip
        }
    }

    let overlaps: [CMTime] = (0..<(durations.count - 1)).map { i in
        CMTimeMinimum(transitionDuration, CMTimeMinimum(CMTimeMultiplyByRatio(durations[i], multiplier: 1, divisor: 2), CMTimeMultiplyByRatio(durations[i + 1], multiplier: 1, divisor: 2)))
    }

    var result: [PositionedReelClip] = []
    var start = CMTime.zero
    for (index, duration) in durations.enumerated() {
        let leading = index > 0 ? overlaps[index - 1] : .zero
        let trailing = index < overlaps.count ? overlaps[index] : .zero
        result.append(PositionedReelClip(index: index, trackIndex: index % 2, duration: duration, start: start, leadingOverlap: leading, trailingOverlap: trailing))
        start = CMTimeSubtract(CMTimeAdd(start, duration), trailing)
    }
    return result
}

func exportHighlightReel(
    momentVideoURLs: [URL],
    transitionsEnabled: Bool = false,
    completion: @escaping (Result<URL, Error>) -> Void
) {
    guard !momentVideoURLs.isEmpty else {
        completion(.failure(HighlightReelExportError.noClips))
        return
    }

    DispatchQueue.global(qos: .userInitiated).async {
        struct ClipInfo {
            let asset: AVURLAsset
            let videoTrack: AVAssetTrack
            let audioTrack: AVAssetTrack?
            let duration: CMTime
            /// This clip's own natural size after its preferredTransform
            /// is applied - the same abs(naturalSize.applying(transform))
            /// every exporter in this feature uses for renderSize.
            let transformedSize: CGSize
        }

        var clips: [ClipInfo] = []
        for url in momentVideoURLs {
            let asset = AVURLAsset(url: url)
            guard let videoTrack = asset.tracks(withMediaType: .video).first else {
                DispatchQueue.main.async { completion(.failure(HighlightReelExportError.noVideoTrack)) }
                return
            }
            let duration = asset.duration
            guard duration.isValid, duration > .zero else {
                DispatchQueue.main.async { completion(.failure(HighlightReelExportError.noVideoTrack)) }
                return
            }
            let transform = videoTrack.preferredTransform
            let transformedSize = videoTrack.naturalSize.applying(transform)
            let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
            guard renderSize.width > 0, renderSize.height > 0 else {
                DispatchQueue.main.async { completion(.failure(HighlightReelExportError.noVideoTrack)) }
                return
            }
            clips.append(ClipInfo(
                asset: asset,
                videoTrack: videoTrack,
                audioTrack: asset.tracks(withMediaType: .audio).first,
                duration: duration,
                transformedSize: renderSize
            ))
        }

        // Canonical canvas: the first clip's own transformed size. Every
        // other clip is letterbox-fit into this rather than forcing the
        // first clip to fit everyone else.
        let renderSize = clips[0].transformedSize

        let composition = AVMutableComposition()
        let hasAnyAudio = clips.contains { $0.audioTrack != nil }
        var useCrossfade = transitionsEnabled && clips.count > 1

        guard let firstVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            DispatchQueue.main.async { completion(.failure(HighlightReelExportError.compositionFailed)) }
            return
        }
        var compVideoTracks = [firstVideoTrack]
        if useCrossfade, let secondVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            compVideoTracks.append(secondVideoTrack)
        }
        // Everything below indexes compVideoTracks[placement.trackIndex]
        // (0 or 1) whenever useCrossfade is true - if the second track
        // somehow failed to allocate, fall back to the plain
        // concatenation path instead of risking an out-of-bounds access.
        if compVideoTracks.count < 2 {
            useCrossfade = false
        }

        var compAudioTracks: [AVMutableCompositionTrack] = []
        if hasAnyAudio {
            if let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                compAudioTracks.append(track)
            }
            if useCrossfade, let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                compAudioTracks.append(track)
            }
        }

        let positioned = positionedReelClips(
            durations: clips.map { $0.duration },
            transitionDuration: CMTime(seconds: defaultHighlightReelTransitionDuration, preferredTimescale: 600),
            transitionsEnabled: useCrossfade
        )

        var instructions: [AVMutableVideoCompositionInstruction] = []

        do {
            for (clip, placement) in zip(clips, positioned) {
                let videoTrackIndex = useCrossfade ? placement.trackIndex : 0
                try compVideoTracks[videoTrackIndex].insertTimeRange(CMTimeRange(start: .zero, duration: clip.duration), of: clip.videoTrack, at: placement.start)
                if let sourceAudioTrack = clip.audioTrack, !compAudioTracks.isEmpty {
                    let audioTrackIndex = useCrossfade ? placement.trackIndex : 0
                    try compAudioTracks[audioTrackIndex].insertTimeRange(CMTimeRange(start: .zero, duration: clip.duration), of: sourceAudioTrack, at: placement.start)
                }

                let (scale, position) = fitTransform(sourceSize: clip.transformedSize, targetRenderSize: renderSize)
                let fit = CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: position.x, y: position.y))
                let finalTransform = clip.videoTrack.preferredTransform.concatenating(fit)

                // This clip's own exclusive window - everything except
                // whatever overlap it shares with a neighbor, which gets
                // its own separate crossfade instruction below instead.
                // All CMTime arithmetic (no `.seconds` round-trip) so
                // this lines up exactly with the real inserted content -
                // see the file header comment for why that precision
                // actually matters here.
                let exclusiveStart = CMTimeAdd(placement.start, placement.leadingOverlap)
                let exclusiveEnd = CMTimeSubtract(CMTimeAdd(placement.start, placement.duration), placement.trailingOverlap)
                guard exclusiveEnd > exclusiveStart else { continue }

                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: exclusiveStart, duration: CMTimeSubtract(exclusiveEnd, exclusiveStart))
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTracks[videoTrackIndex])
                layerInstruction.setTransform(finalTransform, at: exclusiveStart)
                instruction.layerInstructions = [layerInstruction]
                instructions.append(instruction)
            }

            if useCrossfade {
                for i in 0..<(clips.count - 1) {
                    let overlap = positioned[i].trailingOverlap
                    guard overlap > .zero else { continue }
                    let outgoing = positioned[i]
                    let incoming = positioned[i + 1]
                    let overlapStart = incoming.start

                    let (outScale, outPos) = fitTransform(sourceSize: clips[i].transformedSize, targetRenderSize: renderSize)
                    let outTransform = clips[i].videoTrack.preferredTransform.concatenating(
                        CGAffineTransform(scaleX: outScale, y: outScale).concatenating(CGAffineTransform(translationX: outPos.x, y: outPos.y))
                    )
                    let (inScale, inPos) = fitTransform(sourceSize: clips[i + 1].transformedSize, targetRenderSize: renderSize)
                    let inTransform = clips[i + 1].videoTrack.preferredTransform.concatenating(
                        CGAffineTransform(scaleX: inScale, y: inScale).concatenating(CGAffineTransform(translationX: inPos.x, y: inPos.y))
                    )

                    let outLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTracks[outgoing.trackIndex])
                    outLayer.setTransform(outTransform, at: overlapStart)

                    let inLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTracks[incoming.trackIndex])
                    inLayer.setTransform(inTransform, at: overlapStart)
                    inLayer.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: CMTimeRange(start: overlapStart, duration: overlap))

                    let instruction = AVMutableVideoCompositionInstruction()
                    instruction.timeRange = CMTimeRange(start: overlapStart, duration: overlap)
                    // Incoming clip topmost, fading in over the outgoing
                    // clip beneath - see the file header comment for why
                    // only this one layer needs the opacity ramp.
                    instruction.layerInstructions = [inLayer, outLayer]
                    instructions.append(instruction)
                }
                instructions.sort { $0.timeRange.start < $1.timeRange.start }
            }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        var audioMix: AVMutableAudioMix? = nil
        if useCrossfade, !compAudioTracks.isEmpty {
            var audioParams: [AVMutableAudioMixInputParameters] = []
            for trackIndex in compAudioTracks.indices {
                let params = AVMutableAudioMixInputParameters(track: compAudioTracks[trackIndex])
                for i in 0..<(clips.count - 1) {
                    let overlap = positioned[i].trailingOverlap
                    guard overlap > .zero, clips[i].audioTrack != nil, clips[i + 1].audioTrack != nil else { continue }
                    let outgoing = positioned[i]
                    let incoming = positioned[i + 1]
                    let overlapStart = incoming.start
                    if outgoing.trackIndex == trackIndex {
                        params.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: overlapStart, duration: overlap))
                    }
                    if incoming.trackIndex == trackIndex {
                        params.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: CMTimeRange(start: overlapStart, duration: overlap))
                    }
                }
                audioParams.append(params)
            }
            let mix = AVMutableAudioMix()
            mix.inputParameters = audioParams
            audioMix = mix
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            DispatchQueue.main.async { completion(.failure(HighlightReelExportError.exportFailed)) }
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
                    completion(.failure(exportSession.error ?? HighlightReelExportError.exportFailed))
                }
            }
        }
    }
}
