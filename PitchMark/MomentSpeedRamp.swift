//
//  MomentSpeedRamp.swift
//  PitchMark
//
//  2026-09-28: mark different points in a Moment's video and assign each
//  a playback speed (slow-mo / speed-up at different times), then burn
//  that in via AVFoundation - the same "one place all the timing math
//  lives, so preview and export can't disagree" discipline the overlay
//  editor already uses (see Overlay.swift's header comment).
//
//  SpeedKeyframe uses step/hold semantics like OverlayItem's "before
//  first / after last" rule, not linear interpolation: speed holds at
//  the most recent keyframe's value going forward until the next one.
//  Zero keyframes = uniform 1x, a perfectly valid default - unlike
//  overlay keyframes, there's no minimum-keyframe-count restriction here.
//
//  Known, accepted limitation: scaleTimeRange retimes audio samples
//  along with video - it does not pitch-correct, so slow-mo audio sounds
//  lower-pitched and sped-up audio higher-pitched. Standard behavior for
//  a basic speed tool; pitch correction is out of scope.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import AVFoundation

struct SpeedKeyframe: Identifiable, Codable, Equatable {
    let id: UUID
    var time: Double    // seconds, source (original video) time
    var speed: Double   // multiplier; 1.0 = normal, 0.5 = half speed, 2.0 = double

    init(id: UUID = UUID(), time: Double, speed: Double) {
        self.id = id
        self.time = time
        self.speed = speed
    }
}

enum SpeedRampError: Error {
    case noVideoTrack
    case compositionFailed
    case exportFailed
}

/// Point query - the speed in effect at `time`, per the step/hold rule.
/// Used by the UI (e.g. seeding a newly-inserted keyframe with whatever
/// speed already applies there, so adding a point never itself changes
/// anything).
func speed(at time: Double, keyframes: [SpeedKeyframe]) -> Double {
    let sorted = keyframes.sorted { $0.time < $1.time }
    var current = 1.0
    for keyframe in sorted {
        guard keyframe.time <= time else { break }
        current = keyframe.speed
    }
    return current
}

/// Turns a keyframe list into a gapless set of ranges covering
/// `[0, totalDuration]` - the shape `buildSpeedRampedComposition` and
/// the timeline UI both need. Pure, verified standalone the same way as
/// every other timing function in this app.
func speedRanges(keyframes: [SpeedKeyframe], totalDuration: Double) -> [(start: Double, end: Double, speed: Double)] {
    guard totalDuration > 0 else { return [] }

    let sorted = keyframes.sorted { $0.time < $1.time }
    var ranges: [(start: Double, end: Double, speed: Double)] = []
    var cursor: Double = 0
    var currentSpeed: Double = 1.0

    for keyframe in sorted {
        let clampedTime = min(max(keyframe.time, 0), totalDuration)
        if clampedTime > cursor {
            ranges.append((start: cursor, end: clampedTime, speed: currentSpeed))
            cursor = clampedTime
        }
        currentSpeed = keyframe.speed
    }
    if cursor < totalDuration {
        ranges.append((start: cursor, end: totalDuration, speed: currentSpeed))
    }
    if ranges.isEmpty {
        ranges.append((start: 0, end: totalDuration, speed: 1.0))
    }
    return ranges
}

/// One-way source-time -> composite-time conversion (sum of each
/// preceding range's *scaled* duration, plus the partial distance into
/// the range containing `sourceTime`). There is no general inverse of
/// this - see MomentSpeedEditorView's header comment for why this
/// screen deliberately only ever needs this direction.
func sourceTimeToCompositeTime(_ sourceTime: Double, ranges: [(start: Double, end: Double, speed: Double)]) -> Double {
    var composite: Double = 0
    for range in ranges {
        let rangeDuration = range.end - range.start
        guard rangeDuration > 0 else { continue }
        if sourceTime >= range.end {
            composite += rangeDuration / range.speed
        } else if sourceTime > range.start {
            composite += (sourceTime - range.start) / range.speed
            break
        } else {
            break
        }
    }
    return composite
}

/// Builds each range as its own insert-then-scale-immediately step,
/// writing forward at each track's own actual frontier - not "insert
/// the whole video once, then scale sub-ranges of that one segment."
/// That first approach needed reverse-order processing to keep each
/// range's original-timeline coordinates valid, and turned out fragile
/// once 2+ ranges actually needed scaling in the same export (a real
/// on-device export failure, "the operation could not be completed").
///
/// 2026-09-30: "each track's own actual frontier," not a single shared
/// `cursor` this function advanced by its own arithmetic (what this used
/// to do) - `scaleTimeRange` rounds internally to each track's own
/// native timescale, so asking the video and audio composition tracks
/// to scale to the "same" nominal duration doesn't guarantee they land
/// on the exact same actual `CMTime`. A shared cursor assumed they
/// always would; that held for one speed segment but compounded with
/// more (another real on-device failure, "when trying to add speed
/// points" - AVFoundationErrorDomain -11800 / NSOSStatusErrorDomain
/// -16364, a pair commonly associated with audio/video timestamp
/// inconsistency at the final mux pass). Querying each track's own
/// `timeRange.end` fresh before every insert means neither track can
/// ever end up with an insert that overlaps or gaps its own prior
/// content, regardless of how the two tracks' rounding diverges.
/// `buildSpeedRampedComposition`'s result: the composition plus the
/// *source* video track's own `naturalSize`/`preferredTransform`,
/// captured directly from the real asset track rather than left for a
/// caller to re-derive later from the composition track. `exportSpeedRampedMoment`
/// needs this for its `AVMutableVideoComposition` - see that function
/// for why re-deriving it from `compVideoTrack` instead (what this used
/// to do) was fragile enough to matter.
struct SpeedRampedComposition {
    var composition: AVMutableComposition
    var renderSize: CGSize
    var transform: CGAffineTransform
}

func buildSpeedRampedComposition(sourceURL: URL, keyframes: [SpeedKeyframe], completion: @escaping (Result<SpeedRampedComposition, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let sourceAsset = AVURLAsset(url: sourceURL)
        guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async { completion(.failure(SpeedRampError.noVideoTrack)) }
            return
        }
        let sourceAudioTrack = sourceAsset.tracks(withMediaType: .audio).first
        let totalDuration = sourceAsset.duration.seconds
        let sourceTransform = sourceVideoTrack.preferredTransform
        let sourceTransformedSize = sourceVideoTrack.naturalSize.applying(sourceTransform)
        let sourceRenderSize = CGSize(width: abs(sourceTransformedSize.width), height: abs(sourceTransformedSize.height))

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            DispatchQueue.main.async { completion(.failure(SpeedRampError.compositionFailed)) }
            return
        }
        // A composition track does NOT inherit the source track's
        // preferredTransform automatically - it defaults to identity.
        // Since there's no AVMutableVideoComposition/layerInstruction
        // here (unlike OverlayExporter, this file only retimes, it
        // doesn't need to composite CALayers), AVPlayerItem and
        // AVAssetExportSession fall back to reading this track's own
        // transform directly - without this line a portrait-recorded
        // video plays/exports in its raw, unrotated encoding.
        compVideoTrack.preferredTransform = sourceVideoTrack.preferredTransform

        let compAudioTrack: AVMutableCompositionTrack? = sourceAudioTrack != nil
            ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            : nil

        let ranges = speedRanges(keyframes: keyframes, totalDuration: totalDuration)

        do {
            for range in ranges {
                let sourceRange = CMTimeRange(
                    start: CMTime(seconds: range.start, preferredTimescale: 600),
                    duration: CMTime(seconds: range.end - range.start, preferredTimescale: 600)
                )
                guard sourceRange.duration > .zero else { continue }

                // Each track's own actual end, queried fresh every
                // range - not a single shared cursor advanced by my own
                // arithmetic (`CMTimeAdd(cursor, scaledDuration)`), which
                // is what this used to do. `scaleTimeRange` rounds
                // internally to each track's own native timescale -
                // video quantizes to its frame boundaries, audio to its
                // sample-rate boundaries - so asking both tracks to
                // scale to the "same" nominal `scaledDuration` does not
                // guarantee they land on the exact same actual CMTime.
                // A shared cursor assumed they always would; with only
                // one speed segment that assumption's error was too
                // small to matter, but it compounds with every
                // additional segment ("when trying to add speed
                // points"), and eventually the audio track's next
                // insert lands at a position that no longer matches
                // where its own real content actually ends - an
                // overlapping or gapped insert within one track, which
                // is invalid composition structure. AVAssetExportSession
                // doesn't catch that at insert time (insertTimeRange/
                // scaleTimeRange don't throw for it here) - it only
                // surfaces once the actual encode pass tries to mux
                // audio and video whose timing no longer lines up,
                // which matches this reporting as a failure from
                // `exportAsynchronously`'s callback, not from this
                // function's own try/catch, and matches the specific
                // error pair (AVFoundationErrorDomain -11800 /
                // NSOSStatusErrorDomain -16364) that's commonly
                // associated with exactly this class of audio/video
                // timestamp inconsistency in AVFoundation's muxer.
                let videoInsertAt = compVideoTrack.timeRange.end
                try compVideoTrack.insertTimeRange(sourceRange, of: sourceVideoTrack, at: videoInsertAt)

                let audioInsertAt = compAudioTrack?.timeRange.end
                if let sourceAudioTrack, let compAudioTrack, let audioInsertAt {
                    try compAudioTrack.insertTimeRange(sourceRange, of: sourceAudioTrack, at: audioInsertAt)
                }

                if range.speed != 1.0 {
                    // scaleTimeRange doesn't throw - it silently no-ops on
                    // an invalid range, which can't happen here since
                    // each range below is exactly what was just inserted
                    // into that same track.
                    let scaledDuration = CMTime(seconds: (range.end - range.start) / range.speed, preferredTimescale: 600)
                    compVideoTrack.scaleTimeRange(CMTimeRange(start: videoInsertAt, duration: sourceRange.duration), toDuration: scaledDuration)
                    if let compAudioTrack, let audioInsertAt {
                        compAudioTrack.scaleTimeRange(CMTimeRange(start: audioInsertAt, duration: sourceRange.duration), toDuration: scaledDuration)
                    }
                }
            }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        DispatchQueue.main.async {
            completion(.success(SpeedRampedComposition(composition: composition, renderSize: sourceRenderSize, transform: sourceTransform)))
        }
    }
}

/// Reuses `buildSpeedRampedComposition` - the same composition preview
/// plays from (as an in-memory AVPlayerItem) is what gets exported here,
/// so the two can't disagree. Returns a temp file URL, same contract as
/// `exportMomentWithOverlays` - the caller decides where it belongs.
func exportSpeedRampedMoment(sourceURL: URL, keyframes: [SpeedKeyframe], completion: @escaping (Result<URL, Error>) -> Void) {
    buildSpeedRampedComposition(sourceURL: sourceURL, keyframes: keyframes) { result in
        switch result {
        case .failure(let error):
            completion(.failure(error))
        case .success(let ramped):
            guard let compVideoTrack = ramped.composition.tracks(withMediaType: .video).first else {
                completion(.failure(SpeedRampError.compositionFailed))
                return
            }
            // `ramped.renderSize`/`.transform` came from the *source*
            // video track directly (captured inside
            // buildSpeedRampedComposition, before anything touched the
            // composition) rather than being re-derived here from
            // `compVideoTrack.naturalSize`/`.preferredTransform` after
            // the fact - what this originally did. A composition
            // track's own `naturalSize` isn't guaranteed to reliably
            // reflect what's been inserted into it the way
            // `preferredTransform` (set explicitly, one line up in
            // buildSpeedRampedComposition) is - if it ever came out
            // zero for some source file's particular characteristics,
            // the old code's `if renderSize.width > 0, ... { ... }`
            // guard would silently skip assigning `videoComposition`
            // altogether, resurrecting the exact bug this was meant to
            // fix but now only for whatever files hit that path - a
            // real, plausible explanation for "works for a fresh
            // recording, fails once the video's been through a prior
            // Trim" (Trim's output comes from Apple's own
            // UIVideoEditorController, a re-encode with no guarantee of
            // matching a fresh camera recording's characteristics).
            // Reading directly from the source track removes the
            // composition-track-metadata question entirely.
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            guard let exportSession = AVAssetExportSession(asset: ramped.composition, presetName: AVAssetExportPresetHighestQuality) else {
                completion(.failure(SpeedRampError.exportFailed))
                return
            }
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mov
            // 2026-09-30: explicit AVMutableVideoComposition, previously
            // missing entirely - without one, AVAssetExportSession has
            // to decide on its own how to repackage a composition whose
            // video track has scaleTimeRange-retimed segments, and it
            // reliably failed with AVFoundationErrorDomain -11800 /
            // NSOSStatusErrorDomain -16364. That error pair is commonly
            // tied to timestamp inconsistency at the muxer, and real
            // device-recorded H.264/HEVC footage commonly uses B-frames
            // (decode order != presentation order); retiming a segment
            // boundary without forcing genuine frame-accurate
            // recomposition is a known way to corrupt that reordering.
            // An explicit video composition (even a trivial
            // single-instruction one, like OverlayExporter.swift already
            // builds for its own export) forces AVAssetExportSession to
            // actually decode and re-render every frame instead of
            // attempting any more fragile segment-level copy. Same
            // preferredTransform-via-explicit-setTransform technique as
            // OverlayExporter - a layer instruction does NOT inherit its
            // track's preferredTransform automatically, only AVPlayerItem
            // does, which is why the live preview (a plain AVPlayerItem
            // over this same composition, no video composition needed)
            // never had this problem and stayed rotated correctly even
            // before this fix.
            guard ramped.renderSize.width > 0, ramped.renderSize.height > 0 else {
                // A real video file's own track should never report a
                // zero natural size - if this guard ever actually fires,
                // something upstream is badly wrong. Fail loudly with a
                // specific error rather than silently falling back to
                // the no-videoComposition path this whole fix exists to
                // avoid.
                completion(.failure(SpeedRampError.compositionFailed))
                return
            }
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: ramped.composition.duration)
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
            layerInstruction.setTransform(ramped.transform, at: .zero)
            instruction.layerInstructions = [layerInstruction]

            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = ramped.renderSize
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            videoComposition.instructions = [instruction]
            exportSession.videoComposition = videoComposition

            exportSession.exportAsynchronously {
                if exportSession.status == .completed {
                    completion(.success(outputURL))
                } else {
                    completion(.failure(exportSession.error ?? SpeedRampError.exportFailed))
                }
            }
        }
    }
}
