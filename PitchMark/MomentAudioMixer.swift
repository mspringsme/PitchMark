//
//  MomentAudioMixer.swift
//  PitchMark
//
//  2026-09-28: the AVFoundation work behind the audio overlay editor -
//  mixes the Moment's own (possibly turned-down or muted) audio with
//  zero or more placed AudioOverlayItems into one exported file.
//
//  Like MomentSpeedRamp.swift, this file builds no
//  AVMutableVideoComposition/layerInstruction (no visual compositing
//  needed - only audio), so the lesson from
//  [[feedback-compositiontrack-preferredtransform]] applies the same
//  way: the composition's video track needs its preferredTransform set
//  explicitly, or a portrait-recorded source plays/exports rotated.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import AVFoundation

enum AudioMixError: Error {
    case noVideoTrack
    case compositionFailed
    case exportFailed
}

/// Feeds a VolumeKeyframe list into a track's mix automation.
/// AVMutableAudioMixInputParameters.setVolume(_:at:) is itself a step
/// function - the volume set at a given time holds until the next
/// setVolume call - so this needs no interpolation math of its own, just
/// an explicit point at time zero (seeded from the first keyframe, or
/// the flat/legacy value if there are none) so playback before the
/// first keyframe is never left at the API's own default rather than a
/// value the editor actually showed.
private func applyVolumeAutomation(_ params: AVMutableAudioMixInputParameters, flatVolume: Double, keyframes: [VolumeKeyframe]) {
    let sorted = keyframes.sorted { $0.time < $1.time }
    guard let first = sorted.first else {
        params.setVolume(Float(flatVolume), at: .zero)
        return
    }
    params.setVolume(Float(first.volume), at: .zero)
    for keyframe in sorted where keyframe.time > 0 {
        params.setVolume(Float(keyframe.volume), at: CMTime(seconds: keyframe.time, preferredTimescale: 600))
    }
}

/// Builds the video (unmodified, transform carried over explicitly) +
/// original-audio-at-its-own-volume + one additional audio track per
/// overlay (inserted at its own `startTime`, clipped so it never extends
/// past the video's own end), plus the `AVMutableAudioMix` that applies
/// each track's volume. `resolveAudioURL` looks up an overlay's local
/// audio file by asset id - the caller's job, same separation
/// `OverlayEditorView.overlayView`'s asset lookup already uses.
func buildAudioMixedComposition(
    sourceURL: URL,
    audioOverlays: [AudioOverlayItem],
    originalVolume: Double,
    originalVolumeKeyframes: [VolumeKeyframe],
    resolveAudioURL: @escaping (String) -> URL?,
    completion: @escaping (Result<(composition: AVMutableComposition, audioMix: AVMutableAudioMix), Error>) -> Void
) {
    DispatchQueue.global(qos: .userInitiated).async {
        let sourceAsset = AVURLAsset(url: sourceURL)
        guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async { completion(.failure(AudioMixError.noVideoTrack)) }
            return
        }
        let sourceAudioTrack = sourceAsset.tracks(withMediaType: .audio).first
        let totalDuration = sourceAsset.duration

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            DispatchQueue.main.async { completion(.failure(AudioMixError.compositionFailed)) }
            return
        }

        var audioMixParams: [AVMutableAudioMixInputParameters] = []

        do {
            try compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: totalDuration), of: sourceVideoTrack, at: .zero)
            // See this file's header comment - a composition track does
            // not inherit the source's rotation automatically.
            compVideoTrack.preferredTransform = sourceVideoTrack.preferredTransform

            if let sourceAudioTrack,
               let compOriginalAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try compOriginalAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: totalDuration), of: sourceAudioTrack, at: .zero)
                let params = AVMutableAudioMixInputParameters(track: compOriginalAudioTrack)
                applyVolumeAutomation(params, flatVolume: originalVolume, keyframes: originalVolumeKeyframes)
                audioMixParams.append(params)
            }

            for overlay in audioOverlays {
                guard let audioURL = resolveAudioURL(overlay.assetId) else { continue }
                let overlayAsset = AVURLAsset(url: audioURL)
                guard let overlaySourceTrack = overlayAsset.tracks(withMediaType: .audio).first else { continue }
                guard let compOverlayTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }

                let startTime = CMTime(seconds: overlay.startTime, preferredTimescale: 600)
                let remaining = CMTimeSubtract(totalDuration, startTime)
                guard remaining > .zero else { continue }
                let insertDuration = CMTimeMinimum(overlayAsset.duration, remaining)
                guard insertDuration > .zero else { continue }

                try compOverlayTrack.insertTimeRange(CMTimeRange(start: .zero, duration: insertDuration), of: overlaySourceTrack, at: startTime)
                let params = AVMutableAudioMixInputParameters(track: compOverlayTrack)
                applyVolumeAutomation(params, flatVolume: overlay.volume, keyframes: overlay.volumeKeyframes ?? [])
                audioMixParams.append(params)
            }
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioMixParams

        DispatchQueue.main.async { completion(.success((composition, audioMix))) }
    }
}

/// Reuses `buildAudioMixedComposition` - same contract as
/// `exportSpeedRampedMoment`/`exportMomentWithOverlays`: temp file URL
/// on success, caller decides where it belongs.
func exportAudioMixedMoment(
    sourceURL: URL,
    audioOverlays: [AudioOverlayItem],
    originalVolume: Double,
    originalVolumeKeyframes: [VolumeKeyframe],
    resolveAudioURL: @escaping (String) -> URL?,
    completion: @escaping (Result<URL, Error>) -> Void
) {
    buildAudioMixedComposition(
        sourceURL: sourceURL,
        audioOverlays: audioOverlays,
        originalVolume: originalVolume,
        originalVolumeKeyframes: originalVolumeKeyframes,
        resolveAudioURL: resolveAudioURL
    ) { result in
        switch result {
        case .failure(let error):
            completion(.failure(error))
        case .success(let built):
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            guard let exportSession = AVAssetExportSession(asset: built.composition, presetName: AVAssetExportPresetHighestQuality) else {
                completion(.failure(AudioMixError.exportFailed))
                return
            }
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mov
            exportSession.audioMix = built.audioMix
            exportSession.exportAsynchronously {
                if exportSession.status == .completed {
                    completion(.success(outputURL))
                } else {
                    completion(.failure(exportSession.error ?? AudioMixError.exportFailed))
                }
            }
        }
    }
}
