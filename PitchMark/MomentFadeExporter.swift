//
//  MomentFadeExporter.swift
//  PitchMark
//
//  2026-09-30: fade the main edited video in from black at its start
//  and/or out to black at its end - both picture (an opacity ramp on the
//  video layer, same `AVVideoCompositionCoreAnimationTool` technique
//  every other exporter in this feature uses) and sound (an
//  `AVMutableAudioMix` volume ramp over the same span), so the video
//  doesn't fade to black while the audio keeps playing at full volume or
//  cuts off abruptly.
//
//  No composition restructuring here (unlike MomentSlideshowExporter) -
//  the whole source is copied through once, at its own duration, same
//  simple shape as OverlayExporter. The only new technique: a solid
//  black layer behind the video layer, so a fading-out video genuinely
//  reveals black rather than whatever an alpha channel means to a
//  container format that doesn't really support one - same lesson the
//  Slideshow photo-letterbox fix already established for the opposite
//  direction (a photo revealing the video behind it).
//
//  `setVolumeRamp(fromStartVolume:toEndVolume:timeRange:)` documents
//  that it "throws an exception if the time range's start or duration is
//  not numeric" - the exact crash class MomentSlideshowExporter.swift
//  hit (confirmed via an on-device crash log) from an empty composition
//  track's `timeRange.end` being `kCMTimeInvalid`, not `.zero`. Not at
//  risk here: this file never queries a track's own frontier at all (one
//  insert, always at `.zero`), so every CMTime used for the ramps is
//  built directly from the asset's own real `duration`, never from a
//  track's current extent.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import AVFoundation
import UIKit

enum FadeExportError: Error {
    case noVideoTrack
    case compositionFailed
    case exportFailed
}

/// Fixed fade length - a toggle, not a slider, same "quick, fixed
/// default" simplification Overlay.swift's `quickFadeDuration` already
/// settled on for its own fade in/out. Longer than that 0.3s, deliberate:
/// this fades the whole finished piece, not one small overlay element,
/// so a touch more weight reads as intentional rather than abrupt.
let momentFadeDuration: Double = 0.75

func exportFadedMoment(sourceURL: URL, fadeInEnabled: Bool, fadeOutEnabled: Bool, completion: @escaping (Result<URL, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        guard fadeInEnabled || fadeOutEnabled else {
            // This is how a previously-applied fade gets removed -
            // MomentDetailView's "Apply Fade" is tappable with both
            // toggles off specifically so this path is reachable; a
            // no-op success returning `sourceURL` (the pre-fade base)
            // unchanged, which the caller copies into the edited slot,
            // restores the pristine pre-fade video without a pointless
            // re-encode.
            DispatchQueue.main.async { completion(.success(sourceURL)) }
            return
        }

        let sourceAsset = AVURLAsset(url: sourceURL)
        guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async { completion(.failure(FadeExportError.noVideoTrack)) }
            return
        }
        let sourceAudioTrack = sourceAsset.tracks(withMediaType: .audio).first
        let duration = sourceAsset.duration
        guard duration.isValid, duration.seconds > 0 else {
            DispatchQueue.main.async { completion(.failure(FadeExportError.noVideoTrack)) }
            return
        }
        let totalSeconds = duration.seconds
        // Never let the fade-in and fade-out spans overlap on a clip
        // shorter than twice the fixed duration - same floor-scaling
        // shape Overlay.swift's `fadeOpacityMultiplier` already uses for
        // the identical "two fades that might collide in a short span"
        // situation.
        let fadeSeconds = min(momentFadeDuration, totalSeconds / 2)

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            DispatchQueue.main.async { completion(.failure(FadeExportError.compositionFailed)) }
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
        let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        guard renderSize.width > 0, renderSize.height > 0 else {
            DispatchQueue.main.async { completion(.failure(FadeExportError.compositionFailed)) }
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
        parentLayer.isGeometryFlipped = true

        // Opaque black backing BEHIND the video layer - without it, a
        // video layer faded below full opacity reveals whatever an
        // uncomposited frame means for this pixel format, not a clean
        // fade to black. Same opaque-backing lesson the Slideshow
        // photo-letterbox fix already established, just the other
        // direction (here the video itself fades, not a photo on top of
        // it).
        let blackLayer = CALayer()
        blackLayer.frame = CGRect(origin: .zero, size: renderSize)
        blackLayer.backgroundColor = UIColor.black.cgColor
        parentLayer.addSublayer(blackLayer)

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        var times: [Double] = fadeInEnabled ? [0, fadeSeconds] : [0]
        var values: [NSNumber] = fadeInEnabled ? [0, 1] : [1]
        if fadeOutEnabled {
            times.append(contentsOf: [totalSeconds - fadeSeconds, totalSeconds])
            values.append(contentsOf: [1, 0])
        } else {
            times.append(totalSeconds)
            values.append(1)
        }
        let keyTimes = times.map { NSNumber(value: $0 / totalSeconds) }

        let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnimation.values = values
        opacityAnimation.keyTimes = keyTimes
        opacityAnimation.calculationMode = .linear
        opacityAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
        opacityAnimation.duration = totalSeconds
        opacityAnimation.fillMode = .removed
        // isRemovedOnCompletion = false is required for
        // AVVideoCompositionCoreAnimationTool specifically - see
        // OverlayExporter.swift's doc comment on the same property.
        opacityAnimation.isRemovedOnCompletion = false
        videoLayer.opacity = fadeInEnabled ? 0 : 1
        videoLayer.add(opacityAnimation, forKey: "opacity")

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        var audioMix: AVMutableAudioMix? = nil
        if let compAudioTrack {
            let params = AVMutableAudioMixInputParameters(track: compAudioTrack)
            if fadeInEnabled {
                params.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: fadeSeconds, preferredTimescale: 600)))
            }
            if fadeOutEnabled {
                let start = CMTime(seconds: totalSeconds - fadeSeconds, preferredTimescale: 600)
                params.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: start, duration: CMTime(seconds: fadeSeconds, preferredTimescale: 600)))
            }
            let mix = AVMutableAudioMix()
            mix.inputParameters = [params]
            audioMix = mix
        }

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            DispatchQueue.main.async { completion(.failure(FadeExportError.exportFailed)) }
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
                    completion(.failure(exportSession.error ?? FadeExportError.exportFailed))
                }
            }
        }
    }
}
