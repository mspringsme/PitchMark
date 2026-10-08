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
/// chosen aspect leaves in that axis; 0.5 is centered. Meaningless (no
/// slack to pan through) for `.original`, where the crop window always
/// exactly equals the source frame regardless of offset.
struct CropSettings: Codable, Equatable {
    var aspect: CropAspect
    var offsetX: Double
    var offsetY: Double

    init(aspect: CropAspect = .original, offsetX: Double = 0.5, offsetY: Double = 0.5) {
        self.aspect = aspect
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    var offset: CGPoint { CGPoint(x: offsetX, y: offsetY) }
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

/// Export-only geometry: the plain translation that places the chosen
/// crop window at the render canvas's origin. No scale factor beyond 1 -
/// `targetRenderSize` is already the crop window's own pixel size (see
/// `cropRenderSize` above), so this only needs to slide the source frame,
/// never resize it. Pure CoreGraphics math, no CoreAnimation/AVFoundation
/// dependency - standalone-verifiable, same discipline as
/// `zoomLayerPosition` (MomentZoom.swift).
func cropLayerGeometry(sourceSize: CGSize, targetRenderSize: CGSize, offset: CGPoint) -> (scale: CGFloat, position: CGPoint) {
    let slackX = max(sourceSize.width - targetRenderSize.width, 0)
    let slackY = max(sourceSize.height - targetRenderSize.height, 0)
    let clamped = clampedOffset(offset)
    let cropOriginX = slackX * clamped.x
    let cropOriginY = slackY * clamped.y
    return (1.0, CGPoint(x: -cropOriginX, y: -cropOriginY))
}

/// Preview-only geometry: the on-screen rect (in the same point-space as
/// `displayedVideoSize`) representing the crop window, for drawing the
/// dimmed-outside-the-window overlay. Same slack convention as
/// `cropLayerGeometry` above, just scaled into preview points instead of
/// source pixels - genuinely a different coordinate space, not a
/// duplicate of that function's own math.
func cropWindowRect(sourceSize: CGSize, renderSize: CGSize, offset: CGPoint, displayedVideoSize: CGSize) -> CGRect {
    guard sourceSize.width > 0, sourceSize.height > 0 else {
        return CGRect(origin: .zero, size: displayedVideoSize)
    }
    let widthFraction = renderSize.width / sourceSize.width
    let heightFraction = renderSize.height / sourceSize.height
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
/// Dragging the crop window right means revealing more of the source's
/// left side, i.e. the window's own origin moves left relative to the
/// source - hence the negated delta.
func cropOffsetAfterDrag(base: CGPoint, dragTranslation: CGSize, displayedVideoSize: CGSize, sourceSize: CGSize, renderSize: CGSize) -> CGPoint {
    let widthFraction = sourceSize.width > 0 ? renderSize.width / sourceSize.width : 1
    let heightFraction = sourceSize.height > 0 ? renderSize.height / sourceSize.height : 1
    let slackXPoints = displayedVideoSize.width * max(1 - widthFraction, 0)
    let slackYPoints = displayedVideoSize.height * max(1 - heightFraction, 0)
    let dx = slackXPoints > 0 ? -dragTranslation.width / slackXPoints : 0
    let dy = slackYPoints > 0 ? -dragTranslation.height / slackYPoints : 0
    return clampedOffset(CGPoint(x: base.x + dx, y: base.y + dy))
}
