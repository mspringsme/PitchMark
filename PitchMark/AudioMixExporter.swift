//
//  AudioMixExporter.swift
//  PitchMark
//
//  Flattens several placed audio clips (AudioOverlayItem - the exact
//  same model a Moment's audio overlays already use, reused as-is) into
//  one new audio-only file, with no video track and no "original" track
//  to mix against - unlike MomentAudioMixer.swift, an audio mix doesn't
//  layer on top of anything, it IS the thing. Reuses
//  `applyVolumeAutomation` (the fade-aware overlay overload,
//  MomentAudioMixer.swift) and `normalizedTrimAndFade`
//  (AudioOverlay.swift) directly rather than duplicating either - a
//  placed clip here has the identical trim/fade/volume-keyframe shape a
//  Moment's own audio overlay already has.
//
//  Total duration is derived from the clips actually placed (the
//  latest-ending clip's own end), not assumed from any external source -
//  there's no Moment/video duration to anchor to here.
//
//  Output is .m4a (AVAssetExportPresetAppleM4A), matching
//  AudioAssetItem.swift's own local-storage file extension convention
//  for every other audio asset.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import AVFoundation

enum AudioMixExportError: Error {
    case noClips
    case compositionFailed
    case exportFailed
}

func exportAudioMix(
    overlays: [AudioOverlayItem],
    resolveAudioURL: @escaping (String) -> URL?,
    completion: @escaping (Result<URL, Error>) -> Void
) {
    DispatchQueue.global(qos: .userInitiated).async {
        guard !overlays.isEmpty else {
            DispatchQueue.main.async { completion(.failure(AudioMixExportError.noClips)) }
            return
        }

        let composition = AVMutableComposition()
        var audioMixParams: [AVMutableAudioMixInputParameters] = []
        var maxEnd = CMTime.zero

        do {
            for overlay in overlays {
                guard let audioURL = resolveAudioURL(overlay.assetId) else { continue }
                let overlayAsset = AVURLAsset(url: audioURL)
                guard let overlaySourceTrack = overlayAsset.tracks(withMediaType: .audio).first else { continue }
                guard let compOverlayTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }

                let overlayAssetSeconds = overlayAsset.duration.seconds
                let normalized = normalizedTrimAndFade(
                    trimStart: overlay.trimStart,
                    trimEnd: overlay.trimEnd,
                    fadeIn: overlay.fadeInSeconds,
                    fadeOut: overlay.fadeOutSeconds,
                    assetDuration: overlayAssetSeconds.isFinite ? overlayAssetSeconds : 0
                )
                let sourceTrimStart = CMTime(seconds: normalized.trimStart, preferredTimescale: 600)
                let trimmedDuration = CMTime(seconds: max(normalized.trimEnd - normalized.trimStart, 0), preferredTimescale: 600)
                guard trimmedDuration > .zero else { continue }

                let startTime = CMTime(seconds: max(overlay.startTime, 0), preferredTimescale: 600)
                try compOverlayTrack.insertTimeRange(CMTimeRange(start: sourceTrimStart, duration: trimmedDuration), of: overlaySourceTrack, at: startTime)

                // No "remaining" clamp against a shared video end here -
                // unlike MomentAudioMixer's overlay clips (which can be
                // clipped short by the video's own end), a mix clip
                // always gets its FULL trimmed duration; the mix's own
                // total length grows to fit every clip instead.
                let insertedSeconds = trimmedDuration.seconds
                var fadeIn = normalized.fadeIn
                var fadeOut = normalized.fadeOut
                let fadeSum = fadeIn + fadeOut
                if fadeSum > insertedSeconds && fadeSum > 0 {
                    let scale = insertedSeconds / fadeSum
                    fadeIn *= scale
                    fadeOut *= scale
                }

                let params = AVMutableAudioMixInputParameters(track: compOverlayTrack)
                applyVolumeAutomation(
                    params,
                    flatVolume: overlay.volume,
                    keyframes: overlay.volumeKeyframes ?? [],
                    clipStart: overlay.startTime,
                    clipEnd: overlay.startTime + insertedSeconds,
                    fadeIn: fadeIn,
                    fadeOut: fadeOut
                )
                audioMixParams.append(params)

                maxEnd = CMTimeMaximum(maxEnd, CMTimeAdd(startTime, trimmedDuration))
            }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        guard maxEnd > .zero else {
            DispatchQueue.main.async { completion(.failure(AudioMixExportError.noClips)) }
            return
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioMixParams

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            DispatchQueue.main.async { completion(.failure(AudioMixExportError.exportFailed)) }
            return
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.audioMix = audioMix
        // Explicit, not left to default to "the whole composition" -
        // AVAssetExportSession exporting a COMPOSITION (as opposed to a
        // plain single-source asset) to AAC is documented to pad the
        // output to the encoder's own fixed frame size (1024 samples),
        // and that padding isn't always reflected in a correct edit list
        // the way a plain source file's own encoder priming is - so it
        // can end up as genuinely audible silence at both ends instead
        // of being transparently skipped on playback. Explicitly
        // bounding the export to exactly the real composed range (same
        // "real state over an implicit default" discipline several
        // other exporters in this app already learned the hard way) is
        // the standard mitigation.
        exportSession.timeRange = CMTimeRange(start: .zero, duration: maxEnd)

        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                if exportSession.status == .completed {
                    completion(.success(outputURL))
                } else {
                    completion(.failure(exportSession.error ?? AudioMixExportError.exportFailed))
                }
            }
        }
    }
}
