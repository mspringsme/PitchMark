//
//  OverlayExporter.swift
//  PitchMark
//
//  Step 6 of the 2026-09-26 Asset + Video Overlay Keyframe Editor spec:
//  burn `overlays` into an actual video file via AVMutableComposition +
//  AVMutableVideoComposition + AVVideoCompositionCoreAnimationTool +
//  AVAssetExportSession, per the spec's own named approach. Reuses the
//  exact preferredTransform/renderSize technique MomentCapture.swift's
//  stitchMultiCam already proved out in this codebase, rather than
//  inventing orientation handling a third time.
//
//  `sampledTransforms` samples OverlayItem.transform(at:) directly at a
//  fixed interval instead of trying to reproduce its "linear between
//  keyframes, hold before/after" semantics through Core Animation's own
//  keyframe timing curves - that guarantees the export shows exactly
//  what the live preview computes, since it's the literal function being
//  sampled, rather than hoping two independently-authored interpolation
//  systems agree.
//
//  Returns a temp file URL on success, same as stitchMultiCam - the
//  caller decides where it belongs (OverlayEditorView copies it into
//  localMomentEditedVideoURL, the same "committed derivative" slot
//  MomentTrimEditor already writes to).
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import AVFoundation
import UIKit

enum OverlayExportError: Error {
    case noVideoTrack
    case compositionFailed
    case exportFailed
}

/// Samples `item.transform(at:)` every `sampleInterval` seconds across
/// `[item.startTime, item.endTime]`, always including the exact start and
/// end times regardless of whether the interval divides evenly. Pure
/// aside from calling `OverlayItem.transform(at:)`, verified standalone
/// the same way as every other geometry function in this feature.
func sampledTransforms(for item: OverlayItem, sampleInterval: Double) -> (times: [Double], transforms: [OverlayTransform]) {
    guard sampleInterval > 0, item.endTime > item.startTime else {
        guard let only = item.transform(at: item.startTime) else { return ([], []) }
        return ([item.startTime], [only])
    }

    var times: [Double] = []
    var t = item.startTime
    while t < item.endTime {
        times.append(t)
        t += sampleInterval
    }
    times.append(item.endTime)

    let transforms = times.compactMap { item.transform(at: $0) }
    guard transforms.count == times.count else { return ([], []) }
    return (times, transforms)
}

/// The interval `sampledTransforms` uses for export, matching the live
/// preview's own `addPeriodicTimeObserver` rate so both are sampling
/// `transform(at:)` at the same cadence.
private let exportSampleInterval = 1.0 / 30.0

func exportMomentWithOverlays(
    sourceURL: URL,
    overlays: [OverlayItem],
    resolveImage: @escaping (String) -> UIImage?,
    completion: @escaping (Result<URL, Error>) -> Void
) {
    DispatchQueue.global(qos: .userInitiated).async {
        let sourceAsset = AVURLAsset(url: sourceURL)
        guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async { completion(.failure(OverlayExportError.noVideoTrack)) }
            return
        }
        let sourceAudioTrack = sourceAsset.tracks(withMediaType: .audio).first

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            DispatchQueue.main.async { completion(.failure(OverlayExportError.compositionFailed)) }
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

        // Same preferredTransform-aware render size stitchMultiCam already
        // uses - naturalSize alone is the raw pre-rotation pixel size.
        let transform = sourceVideoTrack.preferredTransform
        let transformedSize = sourceVideoTrack.naturalSize.applying(transform)
        let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        guard renderSize.width > 0, renderSize.height > 0 else {
            DispatchQueue.main.async { completion(.failure(OverlayExportError.compositionFailed)) }
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
        // A bare CALayer tree used for AVFoundation compositing (not
        // hosted inside a UIView) defaults to Core Animation's native
        // bottom-left-origin, Y-up coordinate system - not UIKit's
        // top-left-origin, Y-down one that videoDisplayRect/transform(at:)
        // and every position value in this feature already assume.
        // Without this, overlays render vertically mirrored relative to
        // where the live preview showed them. Flipping the parent makes
        // its sublayers' `position` interpret Y the same way UIKit does;
        // it does not flip each layer's own `contents` image.
        parentLayer.isGeometryFlipped = true
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        let overlayBaseSize = min(renderSize.width, renderSize.height) * overlayBaseSizeFraction

        for item in overlays {
            guard let cgImage = resolveImage(item.assetID)?.cgImage else { continue }
            let (times, transforms) = sampledTransforms(for: item, sampleInterval: exportSampleInterval)
            guard !times.isEmpty else { continue }

            let animDuration = max(item.endTime - item.startTime, 0.01)
            let keyTimes = times.map { NSNumber(value: ($0 - item.startTime) / animDuration) }

            let layer = CALayer()
            layer.bounds = CGRect(x: 0, y: 0, width: overlayBaseSize, height: overlayBaseSize)
            layer.contents = cgImage
            // CALayer.contentsGravity defaults to .resize - stretch the
            // image to exactly fill `bounds`, ignoring its own aspect
            // ratio - not .resizeAspect (fit within bounds, preserving
            // aspect ratio, letterboxed on the shorter axis), which is
            // what the live preview's `.scaledToFit()` already does for
            // this same square baseSize frame (OverlayEditorView.swift).
            // A non-square overlay (any Smart Cutout that isn't a square
            // crop, e.g. a standing or crouching player) looked correct
            // in preview and was silently stretched to fill the square
            // only at export time - reported by the user with a
            // screenshot showing exactly this distortion.
            layer.contentsGravity = .resizeAspect
            // Model value while no animation is active - Core Animation's
            // ordinary default (no custom fillMode/isRemovedOnCompletion)
            // reverts to this both before beginTime and after
            // beginTime+duration, which is exactly "hidden outside
            // [startTime, endTime]" with no fill-mode fighting needed.
            layer.opacity = 0
            layer.position = CGPoint(
                x: renderSize.width / 2,
                y: renderSize.height / 2
            )
            parentLayer.addSublayer(layer)

            let beginTime = AVCoreAnimationBeginTimeAtZero + item.startTime

            // isRemovedOnCompletion = false (+ the default .removed fillMode,
            // set explicitly here for clarity) is required for
            // AVVideoCompositionCoreAnimationTool specifically: its offline
            // renderer can treat a default (isRemovedOnCompletion = true)
            // animation as already expired before ever sampling a relevant
            // frame, silently dropping it for the whole export - "the
            // overlay never appears" rather than a partial/wrong result.
            // fillMode = .removed still reverts to the layer's model value
            // (opacity = 0) outside [beginTime, beginTime+duration], so
            // this doesn't reintroduce the "visible forever" problem
            // .both would.
            let positionAnimation = CAKeyframeAnimation(keyPath: "position")
            positionAnimation.values = transforms.map {
                NSValue(cgPoint: CGPoint(x: $0.position.x * renderSize.width, y: $0.position.y * renderSize.height))
            }
            positionAnimation.keyTimes = keyTimes
            positionAnimation.calculationMode = .linear
            positionAnimation.beginTime = beginTime
            positionAnimation.duration = animDuration
            positionAnimation.fillMode = .removed
            positionAnimation.isRemovedOnCompletion = false
            layer.add(positionAnimation, forKey: "position")

            let transformAnimation = CAKeyframeAnimation(keyPath: "transform")
            transformAnimation.values = transforms.map { t -> NSValue in
                let affine = CGAffineTransform(scaleX: t.scale, y: t.scale).rotated(by: t.rotation)
                return NSValue(caTransform3D: CATransform3DMakeAffineTransform(affine))
            }
            transformAnimation.keyTimes = keyTimes
            transformAnimation.calculationMode = .linear
            transformAnimation.beginTime = beginTime
            transformAnimation.duration = animDuration
            transformAnimation.fillMode = .removed
            transformAnimation.isRemovedOnCompletion = false
            layer.add(transformAnimation, forKey: "transform")

            let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
            opacityAnimation.values = transforms.map { NSNumber(value: $0.opacity) }
            opacityAnimation.keyTimes = keyTimes
            opacityAnimation.calculationMode = .linear
            opacityAnimation.beginTime = beginTime
            opacityAnimation.duration = animDuration
            opacityAnimation.fillMode = .removed
            opacityAnimation.isRemovedOnCompletion = false
            layer.add(opacityAnimation, forKey: "opacity")

            // Glow, added *below* the main layer (added to parentLayer
            // first) so it renders behind it - see GlowSettings.swift/
            // GlowEffect.swift. Reuses this same position/opacity
            // animation timing; only contents (and, for a pulsing glow,
            // bounds.size - see below) differ from the main layer.
            if let glowSettings = item.glow, glowSettings.isEnabled {
                let glowLayer = CALayer()
                glowLayer.compositingFilter = "screenBlendMode"
                // Same fix as the main layer above - the glow image
                // GlowEffect.render produces isn't necessarily square
                // either (it pads the source's own extent, whatever
                // shape that is), and glowLayer's own bounds below are
                // computed as a square regardless.
                glowLayer.contentsGravity = .resizeAspect
                glowLayer.opacity = 0
                glowLayer.position = layer.position
                parentLayer.insertSublayer(glowLayer, below: layer)

                if glowSettings.pulse.isEnabled {
                    // A "contents" CAKeyframeAnimation can only jump
                    // between CGImages (calculationMode .discrete below -
                    // there's no such thing as Core Animation
                    // interpolating between two bitmaps), so unlike
                    // position/transform this needs *enough* samples to
                    // look smooth rather than visibly stepping, not just
                    // "no worse than 1/30s." Scales with the pulse's own
                    // speed - at least 6 samples per cycle - floored at
                    // 8/s for a slow pulse (no point sampling faster than
                    // that) and capped at the same 1/30s position uses
                    // for a fast one (no point sampling faster than the
                    // video's own frame rate). Re-rendering a Core Image
                    // blur is far more expensive than sampling a
                    // keyframe value, so this still meaningfully bounds
                    // cost for the common (slower) pulse speeds even
                    // though it can't reduce it for a fast one.
                    let glowSampleInterval = 1.0 / min(max(glowSettings.pulse.speed * 6, 8), 1 / exportSampleInterval)
                    let (glowTimes, _) = sampledTransforms(for: item, sampleInterval: glowSampleInterval)
                    let glowSamples: [(time: Double, size: CGSize, image: CGImage)] = glowTimes.compactMap { sampleTime in
                        guard let params = resolvedGlow(glowSettings, at: sampleTime),
                              let cgGlow = GlowEffect.render(sourceImage: cgImage, params: params, referenceSize: overlayBaseSize) else {
                            return nil
                        }
                        let ratio = CGFloat(cgGlow.width) / CGFloat(max(cgImage.width, 1))
                        return (sampleTime, CGSize(width: overlayBaseSize * ratio, height: overlayBaseSize * ratio), cgGlow)
                    }

                    // If the pulse dips to nothing at some sampled
                    // moments (very high amount + low base intensity),
                    // those samples simply drop out here - the
                    // remaining ones still animate correctly, just
                    // without a frame at that exact instant.
                    if !glowSamples.isEmpty {
                        let glowKeyTimes = glowSamples.map { NSNumber(value: ($0.time - item.startTime) / animDuration) }

                        let boundsAnimation = CAKeyframeAnimation(keyPath: "bounds")
                        boundsAnimation.values = glowSamples.map { NSValue(cgRect: CGRect(origin: .zero, size: $0.size)) }
                        boundsAnimation.keyTimes = glowKeyTimes
                        boundsAnimation.calculationMode = .linear
                        boundsAnimation.beginTime = beginTime
                        boundsAnimation.duration = animDuration
                        boundsAnimation.fillMode = .removed
                        boundsAnimation.isRemovedOnCompletion = false
                        glowLayer.add(boundsAnimation, forKey: "bounds")

                        let contentsAnimation = CAKeyframeAnimation(keyPath: "contents")
                        contentsAnimation.values = glowSamples.map { $0.image }
                        contentsAnimation.keyTimes = glowKeyTimes
                        contentsAnimation.calculationMode = .discrete
                        contentsAnimation.beginTime = beginTime
                        contentsAnimation.duration = animDuration
                        contentsAnimation.fillMode = .removed
                        contentsAnimation.isRemovedOnCompletion = false
                        glowLayer.add(contentsAnimation, forKey: "contents")

                        glowLayer.add(positionAnimation, forKey: "position")
                        glowLayer.add(opacityAnimation, forKey: "opacity")
                    }
                } else if let params = resolvedGlow(glowSettings, at: item.startTime),
                          let cgGlow = GlowEffect.render(sourceImage: cgImage, params: params, referenceSize: overlayBaseSize) {
                    // Static glow - render once, no contents animation.
                    let ratio = CGFloat(cgGlow.width) / CGFloat(max(cgImage.width, 1))
                    let size = overlayBaseSize * ratio
                    glowLayer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
                    glowLayer.contents = cgGlow
                    glowLayer.add(positionAnimation, forKey: "position")
                    glowLayer.add(opacityAnimation, forKey: "opacity")
                }
            }
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            DispatchQueue.main.async { completion(.failure(OverlayExportError.exportFailed)) }
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
                    completion(.failure(exportSession.error ?? OverlayExportError.exportFailed))
                }
            }
        }
    }
}
