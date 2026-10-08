//
//  MomentZoom.swift
//  PitchMark
//
//  2026-09-30: "zoom in and out onto an area" of a Moment's video for
//  export - Ken Burns-style pan/zoom. Pure data model + interpolation
//  only, same discipline as Overlay.swift's header comment: live preview
//  (MomentZoomEditorView, synced to AVPlayer via SwiftUI's own
//  scaleEffect(anchor:)) and export (MomentZoomExporter.swift, via
//  AVVideoCompositionCoreAnimationTool) must both drive off this same
//  interpolation function, never duplicate the math.
//
//  Shape deliberately mirrors `MuteRegion` (AudioOverlay.swift), not the
//  per-item keyframe-list shape `OverlayItem` uses: the user adds a zoom
//  *region* to the timeline (a draggable/resizable range, like a mute
//  section), not an open-ended list of points. Where the two diverge:
//  a mute region holds a single flat `muteLevel` through its own "floor"
//  and only *fades* at its edges, because mute has one steady-state
//  value worth naming. A zoom region's whole reason to exist is the
//  motion between two different framings, so it carries its own start
//  and end transform (center + zoom amount) and linearly interpolates
//  across its full span - there's no separate "floor" period. Outside
//  every region, the frame is untouched (the identity transform) - same
//  "outside a region nothing is affected" rule `muteRegionMultiplier`
//  already establishes for audio.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import CoreGraphics

/// A Ken Burns zoom/pan region on the timeline - a draggable/resizable
/// range (`startTime`...`endTime`), animating linearly from its own
/// `start` framing to its own `end` framing across that span. Outside
/// every region, the frame is untouched (see `identityZoomTransform`).
struct ZoomRegion: Identifiable, Codable, Equatable {
    let id: UUID
    var startTime: Double
    var endTime: Double
    /// Normalized 0...1, relative to video frame - the zoom center at
    /// this region's own `startTime`.
    var startCenterX: Double
    var startCenterY: Double
    /// 1.0 = full frame (no zoom); higher = zoomed in. The zoom amount
    /// at this region's own `startTime`.
    var startScale: Double
    var endCenterX: Double
    var endCenterY: Double
    var endScale: Double

    /// Defaults produce a region that changes nothing until the user
    /// drags something - `startScale: 1` means a freshly-added region is
    /// seamless with the untouched frame right before it, and the
    /// default `endScale` of 2 gives a visibly non-trivial zoom-in
    /// rather than a silent no-op, matching "Add Zoom Area" being
    /// immediately visible the same way `addMuteRegion`'s default
    /// `muteLevel: 0` is immediately audible.
    init(
        id: UUID = UUID(),
        startTime: Double,
        endTime: Double,
        startCenterX: Double = 0.5,
        startCenterY: Double = 0.5,
        startScale: Double = 1.0,
        endCenterX: Double = 0.5,
        endCenterY: Double = 0.5,
        endScale: Double = 2.0
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.startCenterX = startCenterX
        self.startCenterY = startCenterY
        self.startScale = startScale
        self.endCenterX = endCenterX
        self.endCenterY = endCenterY
        self.endScale = endScale
    }

    var startCenter: CGPoint { CGPoint(x: startCenterX, y: startCenterY) }
    var endCenter: CGPoint { CGPoint(x: endCenterX, y: endCenterY) }
}

/// The interpolated result at a point in time - what both the live
/// preview and the export compositor actually render.
struct ZoomTransform: Equatable {
    var center: CGPoint
    var scale: Double
}

/// "No zoom" - the full original frame, centered. What `zoomTransform(at:)`
/// returns everywhere outside every region.
let identityZoomTransform = ZoomTransform(center: CGPoint(x: 0.5, y: 0.5), scale: 1.0)

/// Minimum/maximum zoom amount the editor's slider and every clamp in
/// this feature agree on. 1.0 is the floor (not lower) - there's no more
/// source pixel data to reveal by "zooming out" past the original frame.
let minZoomScale: Double = 1.0
let maxZoomScale: Double = 4.0

/// The single shared interpolation entry point. A region composes its
/// own motion only across `[startTime, endTime]`; everywhere else -
/// before, after, or in a gap between two regions - is the identity
/// transform, same "untouched outside a region" rule
/// `muteRegionMultiplier` already establishes for audio. Regions aren't
/// expected to overlap (the editor doesn't allow it - see
/// `MomentZoomEditorView`), but if two ever do, the first match (by
/// array order) wins rather than attempting to blend two simultaneous
/// framings, which has no sensible visual meaning.
func zoomTransform(at time: Double, regions: [ZoomRegion]) -> ZoomTransform {
    guard let region = regions.first(where: { time >= $0.startTime && time <= $0.endTime }) else {
        return identityZoomTransform
    }
    let span = region.endTime - region.startTime
    let fraction = span > 0 ? min(max((time - region.startTime) / span, 0), 1) : 0
    return ZoomTransform(
        center: CGPoint(
            x: region.startCenterX + (region.endCenterX - region.startCenterX) * fraction,
            y: region.startCenterY + (region.endCenterY - region.startCenterY) * fraction
        ),
        scale: region.startScale + (region.endScale - region.startScale) * fraction
    )
}

/// Live-preview pan math: resolves a drag gesture's translation (points,
/// from SwiftUI's `DragGesture.translation`) into a new normalized center,
/// given the zoom amount currently in effect. Pure geometry, no SwiftUI/
/// AVFoundation dependency, verified standalone the same way as
/// `composeOverlayTransform` (OverlayEditorView.swift).
///
/// Division by `scale` (not just `videoRectSize`) is deliberate: the
/// video is rendered on screen via `.scaleEffect(scale, anchor:)`, so one
/// point of finger movement should always correspond to one point of
/// visible content movement on screen, regardless of how zoomed in the
/// preview currently is - a plain `dx/videoRectSize.width` (what
/// `composeOverlayTransform` does for an overlay, which is never scaled
/// by this same live zoom) would make panning feel faster than the finger
/// at low zoom and slower than the finger at high zoom.
func composeZoomCenter(base: CGPoint, dragTranslation: CGSize, videoRectSize: CGSize, scale: Double) -> CGPoint {
    guard videoRectSize.width > 0, videoRectSize.height > 0, scale > 0 else { return base }
    let dx = dragTranslation.width / (videoRectSize.width * scale)
    let dy = dragTranslation.height / (videoRectSize.height * scale)
    return CGPoint(
        x: min(max(base.x - dx, 0), 1),
        y: min(max(base.y - dy, 0), 1)
    )
}

/// Export-only geometry: the CALayer `position` that makes `renderSize`-
/// space point `center * renderSize` land at the render canvas's center
/// once the layer itself is scaled by `scale` around its own (default,
/// frame-center) anchor point. Pure CoreGraphics math - no CoreAnimation
/// dependency, so this stays standalone-verifiable; `MomentZoomExporter.swift`
/// wraps the result in a `CATransform3D`.
///
/// Derivation: a layer point `p` (in the layer's own unscaled coordinate
/// space) renders on screen at `position + scale * (p - renderSize/2)`
/// (CALayer's default anchorPoint is (0.5, 0.5), i.e. the frame's own
/// center). Solving `position + scale * (center*renderSize - renderSize/2)
/// == renderSize/2` for `position` gives the formula below. At the
/// identity transform (scale 1, center 0.5/0.5) this reduces to
/// `renderSize/2` - the same center-of-canvas position the export's
/// `videoLayer.frame` already sets by default, so an empty region list
/// renders bit-for-bit the same as before this feature existed.
func zoomLayerPosition(center: CGPoint, scale: Double, renderSize: CGSize) -> CGPoint {
    CGPoint(
        x: renderSize.width / 2 - scale * (center.x * renderSize.width - renderSize.width / 2),
        y: renderSize.height / 2 - scale * (center.y * renderSize.height - renderSize.height / 2)
    )
}

/// Samples `zoomTransform(at:)` every `sampleInterval` seconds across
/// `[0, duration]`, always including the exact start and end regardless
/// of whether the interval divides evenly - same shape as
/// `sampledTransforms` (OverlayExporter.swift), just across the whole
/// clip instead of one overlay item's own start/end span. Pure aside from
/// calling `zoomTransform(at:)`, verified standalone the same way as
/// every other timing function in this feature.
func sampledZoomTransforms(regions: [ZoomRegion], duration: Double, sampleInterval: Double) -> (times: [Double], transforms: [ZoomTransform]) {
    guard duration > 0 else {
        return ([0], [zoomTransform(at: 0, regions: regions)])
    }
    guard sampleInterval > 0 else {
        return ([0, duration], [zoomTransform(at: 0, regions: regions), zoomTransform(at: duration, regions: regions)])
    }

    var times: [Double] = []
    var t = 0.0
    while t < duration {
        times.append(t)
        t += sampleInterval
    }
    times.append(duration)

    let transforms = times.map { zoomTransform(at: $0, regions: regions) }
    return (times, transforms)
}
