//
//  MarkupExporter.swift
//  PitchMark
//
//  2026-10-07: burns MarkupOverlay.swift's model into an actual video
//  file - same AVMutableComposition + AVMutableVideoComposition +
//  AVVideoCompositionCoreAnimationTool + AVAssetExportSession approach
//  OverlayExporter.swift already uses, operating on one single video
//  source the same way (not several clips, like HighlightReelExporter.swift).
//
//  Simpler than OverlayExporter.swift's per-frame keyframe animation:
//  markup is static geometry (no position/scale/rotation keyframes), so
//  most types get one `CAShapeLayer` with a fixed `CGPath` - `.angle`
//  additionally gets a `CATextLayer` for its degree label (a shape
//  layer can't also carry text), and `.text` is ONLY a `CATextLayer`
//  (`markupPath` returns nil for it - there's no shape to draw).
//  `buildLabelTextLayer` is the one text-rendering technique shared by
//  both. Every layer gets its own opacity step animation for its
//  `[startTime, endTime]` window (`addVisibilityAnimation`) - same
//  "model value 0, CAKeyframeAnimation with isRemovedOnCompletion =
//  false" shape OverlayExporter uses for its own opacity, just without
//  the interpolated motion.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import AVFoundation
import UIKit
import SwiftUI

enum MarkupExportError: Error {
    case noVideoTrack
    case compositionFailed
    case exportFailed
}

/// Normalized 0...1 geometry -> real pixel renderSize space - the same
/// conversion `MarkupCanvasView.swift` does against `videoRect`, just
/// against the real pixel frame instead of the on-screen one, so
/// preview and export can't disagree on shape/position.
private func toRenderSpace(_ normalized: CGPoint, renderSize: CGSize) -> CGPoint {
    CGPoint(x: normalized.x * renderSize.width, y: normalized.y * renderSize.height)
}

/// Builds one markup's `CGPath` in `renderSize` pixel space from its
/// normalized geometry. For `.angle` this is just the two line segments
/// (A->vertex->C) - the degree label is a separate `CATextLayer`, added
/// alongside this shape's layer in the main export loop below, since a
/// single `CAShapeLayer` can't also carry text.
private func markupPath(for markup: MarkupOverlay, renderSize: CGSize) -> (path: CGPath, strokeWidth: CGFloat)? {
    func toRender(_ normalized: CGPoint) -> CGPoint {
        toRenderSpace(normalized, renderSize: renderSize)
    }

    let strokeWidth = markupStrokeWidth(markup.lineWidth, in: renderSize)

    switch markup.type {
    case .line:
        guard let a = markup.pointA, let b = markup.pointB else { return nil }
        let path = CGMutablePath()
        path.move(to: toRender(a))
        path.addLine(to: toRender(b))
        return (path, strokeWidth)

    case .arrow:
        guard let a = markup.pointA, let b = markup.pointB else { return nil }
        let tail = toRender(a)
        let tip = toRender(b)
        let path = CGMutablePath()
        path.move(to: tail)
        path.addLine(to: tip)
        let head = arrowheadPoints(from: tail, to: tip, lineWidth: strokeWidth)
        path.move(to: head[0])
        path.addLine(to: head[1])
        path.addLine(to: head[2])
        path.closeSubpath()
        return (path, strokeWidth)

    case .ellipse:
        guard let center = markup.ellipseCenter, let radii = markup.ellipseRadii else { return nil }
        let rect = CGRect(
            x: (center.x - radii.width) * renderSize.width,
            y: (center.y - radii.height) * renderSize.height,
            width: radii.width * 2 * renderSize.width,
            height: radii.height * 2 * renderSize.height
        )
        return (CGPath(ellipseIn: rect, transform: nil), strokeWidth)

    case .angle:
        guard let a = markup.pointA, let vertex = markup.pointB, let c = markup.pointC else { return nil }
        let path = CGMutablePath()
        path.move(to: toRender(a))
        path.addLine(to: toRender(vertex))
        path.addLine(to: toRender(c))
        return (path, strokeWidth)

    case .freehand:
        guard let points = markup.freehandPoints, points.count > 1 else { return nil }
        let path = CGMutablePath()
        path.move(to: toRender(points[0].cgPoint))
        for point in points.dropFirst() {
            path.addLine(to: toRender(point.cgPoint))
        }
        return (path, strokeWidth)

    case .text:
        // No path at all - `.text` is purely a CATextLayer, built in
        // the main export loop below (same as `.angle`'s degree label).
        return nil
    }
}

/// A colored label on a dark pill background - the one text-rendering
/// technique this feature uses, shared by `.angle`'s degree label and
/// `.text` markup, rather than two near-identical `CATextLayer` builders.
/// Width is a rough heuristic from the string's length, not real text
/// measurement - acceptable here since this is a short coaching
/// note/degree value, not arbitrary long-form text.
private func buildLabelTextLayer(string: String, color: UIColor, center: CGPoint, fontSize: CGFloat = 18) -> CATextLayer {
    let width = max(CGFloat(string.count) * fontSize * 0.62 + 16, fontSize * 3)
    let height = fontSize + 14
    let textLayer = CATextLayer()
    textLayer.frame = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    textLayer.string = string
    // The actual UIFont OBJECT, not its PostScript name string. The
    // system bold font's name (".SFUI-Bold" and similar) is a private,
    // internal identifier that CATextLayer's string-based font lookup
    // doesn't reliably resolve - glyphs can silently fail to render
    // while the background pill still shows, which is almost certainly
    // why the degree label read as "too small to read" (an empty pill)
    // and the text label as "didn't export" at all (an invisible pill
    // is easy to miss entirely) - confirmed as one root cause for both
    // reports, not two separate bugs. OverlayExporter.swift's own
    // CATextLayers never had this problem because they use CUSTOM
    // bundled fonts with stable, public PostScript names, not Apple's
    // own dynamic system font.
    textLayer.font = UIFont.boldSystemFont(ofSize: fontSize) as CFTypeRef
    textLayer.fontSize = fontSize
    textLayer.foregroundColor = color.cgColor
    textLayer.backgroundColor = UIColor.black.withAlphaComponent(0.6).cgColor
    textLayer.cornerRadius = 6
    textLayer.alignmentMode = .center
    // Vertically centers single-line text in the frame - CATextLayer has
    // no built-in vertical centering of its own otherwise.
    textLayer.contentsGravity = .center
    // Fixed value, not UIScreen.main.scale - this renders through
    // AVVideoCompositionCoreAnimationTool's offline compositor, not
    // on-screen, so there's no real screen to query; same fixed-3x
    // convention OverlayExporter.swift's own CATextLayers use.
    textLayer.contentsScale = 3.0
    return textLayer
}

/// The opacity CAKeyframeAnimation every markup's own layer(s) get - a
/// single "appear, stay visible" step across `[startTime, endTime]`
/// (Phase 1/2 markup is static, no interpolated motion). Shared so a
/// multi-layer markup (Angle's shape + its separate degree-label text
/// layer) can apply the IDENTICAL visibility window to both rather than
/// risking two hand-copied animations drifting apart.
private func addVisibilityAnimation(to layer: CALayer, markup: MarkupOverlay) {
    let animDuration = max(markup.endTime - markup.startTime, 0.01)
    let beginTime = AVCoreAnimationBeginTimeAtZero + markup.startTime

    // Model value while outside [startTime, endTime] - Core Animation's
    // own default fillMode reverts to this both before and after the
    // animation, same "hidden outside the window, no fillMode fighting
    // needed" shape OverlayExporter.swift's opacity model value uses.
    layer.opacity = 0

    // isRemovedOnCompletion = false is required for
    // AVVideoCompositionCoreAnimationTool specifically - its offline
    // renderer can otherwise treat the animation as already expired
    // before sampling a relevant frame, silently dropping the layer
    // from the export entirely (same gotcha OverlayExporter.swift/
    // MomentSlideshowExporter.swift already document for their own
    // animations).
    let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
    opacityAnimation.values = [markup.opacity, markup.opacity]
    opacityAnimation.keyTimes = [0, 1]
    opacityAnimation.calculationMode = .linear
    opacityAnimation.beginTime = beginTime
    opacityAnimation.duration = animDuration
    opacityAnimation.fillMode = .removed
    opacityAnimation.isRemovedOnCompletion = false
    layer.add(opacityAnimation, forKey: "opacity")
}

func exportMarkupMoment(
    videoSourceURL: URL,
    markups: [MarkupOverlay],
    completion: @escaping (Result<URL, Error>) -> Void
) {
    DispatchQueue.global(qos: .userInitiated).async {
        let sourceAsset = AVURLAsset(url: videoSourceURL)
        guard let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async { completion(.failure(MarkupExportError.noVideoTrack)) }
            return
        }
        let sourceAudioTrack = sourceAsset.tracks(withMediaType: .audio).first

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            DispatchQueue.main.async { completion(.failure(MarkupExportError.compositionFailed)) }
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

        let transform = sourceVideoTrack.preferredTransform
        let transformedSize = sourceVideoTrack.naturalSize.applying(transform)
        let renderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        guard renderSize.width > 0, renderSize.height > 0 else {
            DispatchQueue.main.async { completion(.failure(MarkupExportError.compositionFailed)) }
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
        // Same Y-flip OverlayExporter.swift's parentLayer uses - a bare
        // CALayer tree defaults to Core Animation's bottom-left-origin,
        // Y-up space, not UIKit's top-left Y-down one every normalized
        // coordinate in this feature already assumes.
        parentLayer.isGeometryFlipped = true
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        for markup in markups {
            let color = (hexToColor(markup.colorHex) ?? .white)

            if let (path, strokeWidth) = markupPath(for: markup, renderSize: renderSize) {
                let shapeLayer = CAShapeLayer()
                shapeLayer.frame = CGRect(origin: .zero, size: renderSize)
                shapeLayer.path = path
                shapeLayer.strokeColor = UIColor(color).cgColor
                shapeLayer.lineWidth = strokeWidth
                shapeLayer.lineCap = .round
                // Arrow's head is a closed triangle sub-path meant to be
                // filled solid, same color as the stroke - Line/Ellipse
                // have no second sub-path, so filling is a no-op for
                // them (an unfilled stroke-only shape has no area to
                // fill).
                shapeLayer.fillColor = markup.type == .arrow ? UIColor(color).cgColor : UIColor.clear.cgColor
                parentLayer.addSublayer(shapeLayer)
                addVisibilityAnimation(to: shapeLayer, markup: markup)
            }

            // Angle's degree label - a separate CATextLayer alongside
            // its shape's layer above, since a single CAShapeLayer
            // can't also carry text. Same real-space angle math
            // MarkupCanvasView.swift's live preview uses so the
            // exported label can't disagree with what the user saw
            // while placing it.
            if markup.type == .angle, let a = markup.pointA, let vertex = markup.pointB, let c = markup.pointC {
                let aPt = toRenderSpace(a, renderSize: renderSize)
                let vertexPt = toRenderSpace(vertex, renderSize: renderSize)
                let cPt = toRenderSpace(c, renderSize: renderSize)
                let degrees = angleDegrees(a: aPt, vertex: vertexPt, c: cPt)
                let labelCenter = angleLabelAnchor(a: aPt, vertex: vertexPt, c: cPt, distance: 28)
                // Same frame-relative size the live preview now uses -
                // the fixed default `fontSize: 18` this used to rely on
                // is a real export resolution's worth of pixels, which
                // reads as "extremely small" there even though a
                // similar point size looked fine in the on-screen
                // preview's much smaller videoRect.
                let labelFontSize = markupTextFontSize(.medium, in: renderSize)
                let textLayer = buildLabelTextLayer(string: "\(Int(degrees.rounded()))°", color: .white, center: labelCenter, fontSize: labelFontSize)
                parentLayer.addSublayer(textLayer)
                addVisibilityAnimation(to: textLayer, markup: markup)
            }

            // `.text` has no shape layer at all (markupPath returns nil
            // for it) - just this one label, at `pointA`.
            if markup.type == .text, let position = markup.pointA, let text = markup.text, !text.isEmpty {
                let center = toRenderSpace(position, renderSize: renderSize)
                let fontSize = markupTextFontSize(markup.textSize ?? .medium, in: renderSize)
                let textLayer = buildLabelTextLayer(string: text, color: UIColor(color), center: center, fontSize: fontSize)
                parentLayer.addSublayer(textLayer)
                addVisibilityAnimation(to: textLayer, markup: markup)
            }
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            DispatchQueue.main.async { completion(.failure(MarkupExportError.exportFailed)) }
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
                    completion(.failure(exportSession.error ?? MarkupExportError.exportFailed))
                }
            }
        }
    }
}
