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
/// writing forward at a cursor this function fully owns - not "insert
/// the whole video once, then scale sub-ranges of that one segment."
/// That first approach needed reverse-order processing to keep each
/// range's original-timeline coordinates valid, and turned out fragile
/// once 2+ ranges actually needed scaling in the same export (a real
/// on-device export failure, "the operation could not be completed").
/// This shape has no such fragility: at the moment any range is
/// inserted+scaled, `cursor` is the frontier of everything built so
/// far - nothing else in the composition occupies that position yet,
/// so there's no boundary-adjacency-with-other-scaled-segments
/// reasoning required at all, in either direction.
func buildSpeedRampedComposition(sourceURL: URL, keyframes: [SpeedKeyframe], completion: @escaping (Result<AVMutableComposition, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let sourceAsset = AVURLAsset(url: sourceURL)
        guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async { completion(.failure(SpeedRampError.noVideoTrack)) }
            return
        }
        let sourceAudioTrack = sourceAsset.tracks(withMediaType: .audio).first
        let totalDuration = sourceAsset.duration.seconds

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
        var cursor = CMTime.zero

        do {
            for range in ranges {
                let sourceRange = CMTimeRange(
                    start: CMTime(seconds: range.start, preferredTimescale: 600),
                    duration: CMTime(seconds: range.end - range.start, preferredTimescale: 600)
                )
                guard sourceRange.duration > .zero else { continue }

                try compVideoTrack.insertTimeRange(sourceRange, of: sourceVideoTrack, at: cursor)
                if let sourceAudioTrack, let compAudioTrack {
                    try compAudioTrack.insertTimeRange(sourceRange, of: sourceAudioTrack, at: cursor)
                }

                if range.speed != 1.0 {
                    // scaleTimeRange doesn't throw - it silently no-ops on
                    // an invalid range, which can't happen here since
                    // `insertedRange` is exactly what was just inserted.
                    let insertedRange = CMTimeRange(start: cursor, duration: sourceRange.duration)
                    let scaledDuration = CMTime(seconds: (range.end - range.start) / range.speed, preferredTimescale: 600)
                    compVideoTrack.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                    compAudioTrack?.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                    cursor = CMTimeAdd(cursor, scaledDuration)
                } else {
                    cursor = CMTimeAdd(cursor, sourceRange.duration)
                }
            }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        DispatchQueue.main.async { completion(.success(composition)) }
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
        case .success(let composition):
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                completion(.failure(SpeedRampError.exportFailed))
                return
            }
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mov
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
