//
//  MomentCrop.swift
//  PitchMark
//
//  Aspect-ratio crop/reframe - pick a target aspect ratio (original,
//  square, vertical 9:16 for Reels/Stories) and a static pan offset
//  within the source frame. Pure data model + geometry only, same
//  discipline as MomentZoom.swift's header comment: live preview
//  (MomentCropEditorView) and export (MomentCropExporter.swift) both
//  drive off these same functions, never duplicate the math.
//
//  Unlike MomentZoom's Ken Burns regions, this is a single static
//  setting for the whole clip (no timeline, no keyframing) - confirmed
//  scope with the user. "Cover crop" semantics: the chosen aspect's
//  window always fills the full render canvas (no letterboxing/black
//  bars) by cropping away whichever source dimension has slack; `offset`
//  (normalized 0...1 per axis) picks where within that slack the window
//  sits - 0.5/0.5 is centered. This is the opposite convention from
//  HighlightReelExporter.swift's `fitTransform` (which letterboxes to
//  show the whole source, never cropping) - crop/reframe is specifically
//  about filling the target frame, so cropping is the point.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import CoreGraphics

enum CropAspect: String, Codable, CaseIterable {
    case original
    case square
    case vertical9x16

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .square: return "Square"
        case .vertical9x16: return "9:16"
        }
    }
}

/// Nil `cropSettings` on `Moment` means "no crop" (original framing) -
/// same "nil means off" convention `fadeInEnabled` already established.
/// `offsetX`/`offsetY` are normalized 0...1 within whatever slack the
/// chosen aspect AND zoom level together leave in that axis; 0.5 is
/// centered. At `scale` 1.0 on `.original` there's no slack at all (the
/// crop window exactly equals the source frame regardless of offset) -
/// but zooming in on `.original` creates real pan slack of its own, same
/// as choosing Square or 9:16 does at `scale` 1.0. So "no slack" is a
/// `scale`-dependent fact, not an `.original`-dependent one.
///
/// Zoom range the editor's slider and every clamp below agree on - 1.0 is
/// the floor (no more source pixel data to reveal by zooming out past the
/// cover-fit window). Deliberately a smaller ceiling than MomentZoom's
/// `maxZoomScale` (4.0): Crop is a static framing choice, not a Ken Burns
/// move, so there's less reason to push quality loss as far.
let minCropZoomScale: Double = 1.0
let maxCropZoomScale: Double = 3.0

struct CropSettings: Codable, Equatable {
    var aspect: CropAspect
    var offsetX: Double
    var offsetY: Double
    /// Optional, not a non-optional field with a Swift default - documents
    /// saved before zoom existed have no `scale` key, and a non-optional
    /// default does NOT survive Codable decoding of a missing key (see
    /// feedback-firestore-codable-optional-defaults memory). Always read
    /// via `resolvedScale`, never this raw property.
    var scale: Double?

    init(aspect: CropAspect = .original, offsetX: Double = 0.5, offsetY: Double = 0.5, scale: Double = 1.0) {
        self.aspect = aspect
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.scale = scale
    }

    var offset: CGPoint { CGPoint(x: offsetX, y: offsetY) }

    /// `scale` decoded as nil (old document) resolves to 1.0 - identical
    /// to a freshly-created CropSettings, i.e. "no zoom". Also clamps a
    /// stored value back into range defensively, same reasoning as
    /// `clampedOffset` below.
    var resolvedScale: Double { min(max(scale ?? 1.0, minCropZoomScale), maxCropZoomScale) }
}

/// The crop window's own size, in the same pixel space as `sourceSize`
/// (already preferredTransform-rotated, matching every exporter's
/// `renderSize` convention in this feature) - this becomes the actual
/// export `renderSize` for Crop, so there's no up/downscaling beyond
/// whatever cropping away the slack dimension requires.
func cropRenderSize(sourceSize: CGSize, aspect: CropAspect) -> CGSize {
    guard sourceSize.width > 0, sourceSize.height > 0 else { return sourceSize }
    switch aspect {
    case .original:
        return sourceSize
    case .square:
        let side = min(sourceSize.width, sourceSize.height)
        return CGSize(width: side, height: side)
    case .vertical9x16:
        let targetRatio: CGFloat = 9.0 / 16.0
        let sourceRatio = sourceSize.width / sourceSize.height
        if sourceRatio > targetRatio {
            // Source is wider than the target ratio - keep full height,
            // crop width down to match.
            let height = sourceSize.height
            return CGSize(width: height * targetRatio, height: height)
        } else {
            // Source is narrower/taller than the target ratio - keep
            // full width, crop height down to match.
            let width = sourceSize.width
            return CGSize(width: width, height: width / targetRatio)
        }
    }
}

/// Clamps a raw offset to the valid 0...1-per-axis range. Doesn't need
/// to know the aspect/source size - a zero-slack axis (e.g. both axes
/// for `.original`) already contributes nothing regardless of offset,
/// via `cropLayerGeometry`'s own slack computation below.
func clampedOffset(_ offset: CGPoint) -> CGPoint {
    CGPoint(x: min(max(offset.x, 0), 1), y: min(max(offset.y, 0), 1))
}

/// Export-only geometry: the translation (and, when zoomed in, scale)
/// that places the chosen crop window at the render canvas's origin.
/// `targetRenderSize` is always the crop window's own OUTPUT pixel size
/// (see `cropRenderSize` above) regardless of zoom - what changes with
/// `scale` is how much of the SOURCE that output size is sampled from.
/// At `scale` 1.0 the sampled footprint equals `targetRenderSize` exactly
/// (no resize, same as before zoom existed); above 1.0 the footprint
/// shrinks to `targetRenderSize / scale` source pixels, then gets scaled
/// back up to fill the full output - i.e. "zoom in." Pure CoreGraphics
/// math, no CoreAnimation/AVFoundation dependency - standalone-verifiable,
/// same discipline as `zoomLayerPosition` (MomentZoom.swift).
func cropLayerGeometry(sourceSize: CGSize, targetRenderSize: CGSize, offset: CGPoint, scale: Double) -> (scale: CGFloat, position: CGPoint) {
    let scale = max(scale, minCropZoomScale)
    let sampleSize = CGSize(width: targetRenderSize.width / scale, height: targetRenderSize.height / scale)
    let slackX = max(sourceSize.width - sampleSize.width, 0)
    let slackY = max(sourceSize.height - sampleSize.height, 0)
    let clamped = clampedOffset(offset)
    let cropOriginX = slackX * clamped.x
    let cropOriginY = slackY * clamped.y
    return (CGFloat(scale), CGPoint(x: -scale * cropOriginX, y: -scale * cropOriginY))
}

/// Preview-only geometry: the on-screen rect (in the same point-space as
/// `displayedVideoSize`) representing the crop window, for drawing the
/// dimmed-outside-the-window overlay. Same slack convention as
/// `cropLayerGeometry` above, just scaled into preview points instead of
/// source pixels - genuinely a different coordinate space, not a
/// duplicate of that function's own math. The box shrinks as `scale`
/// grows, same as `cropLayerGeometry`'s sampled footprint - zooming in
/// means a smaller slice of the source ends up inside the window.
func cropWindowRect(sourceSize: CGSize, renderSize: CGSize, offset: CGPoint, displayedVideoSize: CGSize, scale: Double) -> CGRect {
    guard sourceSize.width > 0, sourceSize.height > 0 else {
        return CGRect(origin: .zero, size: displayedVideoSize)
    }
    let scale = max(scale, minCropZoomScale)
    let widthFraction = (renderSize.width / scale) / sourceSize.width
    let heightFraction = (renderSize.height / scale) / sourceSize.height
    let boxWidth = displayedVideoSize.width * widthFraction
    let boxHeight = displayedVideoSize.height * heightFraction
    let slackXPoints = displayedVideoSize.width - boxWidth
    let slackYPoints = displayedVideoSize.height - boxHeight
    let clamped = clampedOffset(offset)
    return CGRect(x: slackXPoints * clamped.x, y: slackYPoints * clamped.y, width: boxWidth, height: boxHeight)
}

/// Live-preview pan math: resolves a drag gesture's translation (points)
/// into a new normalized offset, given how the displayed video frame
/// relates to the real source/crop pixel sizes. Mirrors
/// `composeZoomCenter`'s role (MomentZoom.swift) for Zoom's drag-to-pan.
///
/// `offset` is the crop WINDOW's own position within the source's slack
/// (see `cropWindowRect`), and the video itself never moves on screen -
/// only the window does. So the window has to track the finger directly,
/// same direction, no negation: drag right, window moves right. (A
/// negated delta here previously made the window visibly move opposite
/// the drag - reported by the user as the crop box moving "reverse" to
/// the touch.) `scale` shrinks the window (and its slack) the same way
/// `cropWindowRect` does, so drag distance keeps tracking the finger 1:1
/// regardless of zoom level - same reasoning as `composeZoomCenter`'s own
/// scale division.
func cropOffsetAfterDrag(base: CGPoint, dragTranslation: CGSize, displayedVideoSize: CGSize, sourceSize: CGSize, renderSize: CGSize, scale: Double) -> CGPoint {
    let scale = max(scale, minCropZoomScale)
    let widthFraction = sourceSize.width > 0 ? (renderSize.width / scale) / sourceSize.width : 1
    let heightFraction = sourceSize.height > 0 ? (renderSize.height / scale) / sourceSize.height : 1
    let slackXPoints = displayedVideoSize.width * max(1 - widthFraction, 0)
    let slackYPoints = displayedVideoSize.height * max(1 - heightFraction, 0)
    let dx = slackXPoints > 0 ? dragTranslation.width / slackXPoints : 0
    let dy = slackYPoints > 0 ? dragTranslation.height / slackYPoints : 0
    return clampedOffset(CGPoint(x: base.x + dx, y: base.y + dy))
}
