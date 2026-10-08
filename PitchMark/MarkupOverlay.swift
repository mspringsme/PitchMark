//
//  MarkupOverlay.swift
//  PitchMark
//
//  2026-10-07: coaching "Markup" (lines, arrows, circles, angle
//  measurements, freehand drawing, short text notes) - distinct from the
//  existing decorative asset/sticker overlays (Overlay.swift) because
//  markup needs editable MULTI-POINT geometry (two independent endpoints
//  for a line, three for an angle) rather than one position+scale+
//  rotation anchor. Grafting that onto OverlayItem/OverlayKeyframe would
//  mean fighting their single-anchor shape, not reusing it, so this is a
//  deliberately separate, parallel model - see MarkupEditorView.swift's
//  header for the rest of that reasoning.
//
//  Zero Moment dependency on purpose - this file, MarkupCanvasView.swift,
//  and MarkupExporter.swift are the reusable "engine" a future Training
//  section can consume the same way Moments does; only MarkupEditorView.swift
//  and Moment.swift's own `markupOverlays` field know a Moment exists.
//
//  One struct with a `type` discriminator and optional per-type fields -
//  not a Swift enum with associated values - matching OverlayItem's own
//  `textContent: OverlayTextContent?` convention. This codebase's
//  Firestore `Codable` usage throughout relies on plain Optional fields
//  decoding safely on an old document missing that key; a mixed-
//  associated-value enum would need a hand-rolled Decodable instead,
//  the exact footgun [[feedback-firestore-codable-optional-defaults]]
//  warns about.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import CoreGraphics

/// Storage shape for one freehand point - deliberately NOT `CGPoint`
/// directly. `CGPoint`'s own `Codable` conformance encodes as an
/// UNKEYED (array) container `[x, y]`, which is fine for a single point
/// field (`pointA`, `ellipseCenter`, etc. each produce exactly one
/// array), but `freehandPoints` is an ARRAY of points - an array of
/// `CGPoint` therefore encodes as an array of arrays, and Cloud
/// Firestore rejects nested arrays outright. Confirmed on-device: this
/// crashed the app with an uncaught `FIRInvalidArgumentException`
/// ("Nested arrays are not supported") the instant a Moment with a
/// Freehand stroke tried to save - the video export itself had already
/// succeeded by that point, only the Firestore metadata write crashed.
/// This struct's plain `x`/`y` fields get SYNTHESIZED Codable (a KEYED
/// container, `{"x":.., "y":..}`), so `[MarkupPoint]` is an array of
/// maps - which Firestore allows fine.
struct MarkupPoint: Codable, Equatable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

/// All 6 cases exist from Phase 1 so the picker/model never needed a
/// breaking change to add one as each phase landed - all 6 now have a
/// picker entry and a renderer (MarkupEditorView.swift/
/// MarkupCanvasView.swift) as of Phase 3.
enum MarkupType: String, Codable, CaseIterable {
    case line
    case arrow
    case ellipse
    case angle
    case freehand
    case text
}

/// Fixed thickness presets rather than a free-form slider - "a coach at
/// a ball field," not a drawing app. Same "named presets over a
/// continuous control" shape `OverlayItem`'s own fade toggles use for
/// duration.
enum MarkupLineWidth: String, Codable, CaseIterable {
    case thin
    case medium
    case thick

    /// Fraction of the frame's shorter dimension - the exact
    /// `overlayBaseSizeFraction` convention (Overlay.swift) for the same
    /// reason: a FIXED point value looks like a different proportion of
    /// the frame on every device/export resolution, since the on-screen
    /// preview's videoRect and the real export's pixel renderSize are
    /// almost never the same size. Callers compute the real stroke
    /// width as `fractionOfShorterDimension * min(frame.width, frame.height)`
    /// against whichever frame (`videoRect` in MarkupCanvasView.swift,
    /// `renderSize` in MarkupExporter.swift) they're actually drawing
    /// into, so thickness reads as the same proportion in both.
    var fractionOfShorterDimension: Double {
        switch self {
        case .thin: return 0.0035
        case .medium: return 0.007
        case .thick: return 0.012
        }
    }
}

/// `width.fractionOfShorterDimension` scaled against whichever frame is
/// actually being drawn into - the one function both the live canvas
/// and export call, so a given preset never looks like two different
/// thicknesses depending on which one asked.
func markupStrokeWidth(_ width: MarkupLineWidth, in frameSize: CGSize) -> CGFloat {
    CGFloat(width.fractionOfShorterDimension) * min(frameSize.width, frameSize.height)
}

/// `.text` only - same fixed-presets-over-a-slider shape `MarkupLineWidth`
/// already uses, and the same reason: a fixed point size would read as
/// a different proportion of the frame in the on-screen preview vs. the
/// real export resolution.
enum MarkupTextSize: String, Codable, CaseIterable {
    case small
    case medium
    case large

    var fractionOfShorterDimension: Double {
        switch self {
        case .small: return 0.035
        case .medium: return 0.05
        case .large: return 0.07
        }
    }
}

/// Same role `markupStrokeWidth` plays for line thickness - the one
/// function both the live canvas and export call to turn a preset into
/// a real font point size for whichever frame they're drawing into.
func markupTextFontSize(_ size: MarkupTextSize, in frameSize: CGSize) -> CGFloat {
    CGFloat(size.fractionOfShorterDimension) * min(frameSize.width, frameSize.height)
}

struct MarkupOverlay: Identifiable, Codable {
    let id: UUID
    var type: MarkupType
    /// Same visibility-window shape as `OverlayItem.startTime`/`endTime` -
    /// a markup is either fully visible or fully hidden outside this
    /// range, no fade/animation in Phase 1.
    var startTime: Double
    var endTime: Double
    /// Hex string ("#RRGGBB") via `colorToHex`/`hexToColor`
    /// (Utilities.swift) - same convention `OverlayTextContent.colorHex`
    /// already uses.
    var colorHex: String
    var lineWidth: MarkupLineWidth
    var opacity: Double
    /// `.text` only - `lineWidth` doesn't apply to a text label, so this
    /// is its own preset, same shape/reasoning as `lineWidth`. Optional,
    /// unlike `colorHex`/`lineWidth`/`opacity` above - those have been
    /// in this struct since its very first version, so no saved
    /// document could predate them, but `textSize` was added LATER,
    /// after real saves had already happened (confirmed: a pre-textSize
    /// document fails to decode at all with a non-Optional field here -
    /// `try? doc.data(as: Moment.self)` would then silently drop the
    /// WHOLE Moment, not just this one field). Same "nil is a real
    /// legacy value, not a missing-data error" convention every other
    /// field-added-after-first-ship in this app already uses - read via
    /// `markup.textSize ?? .medium`.
    var textSize: MarkupTextSize?

    // Geometry - normalized 0...1, the exact same space
    // `OverlayKeyframe.position` already uses, relative to the video
    // frame (never the surrounding toolbar/nav chrome). Optional,
    // populated per `type` - see the file header for why this shape
    // over an associated-value enum.
    /// Line/arrow start point. For `.angle`, one of the two outer
    /// points ("Point A" in the spec).
    var pointA: CGPoint?
    /// Line/arrow end point - the arrowhead is drawn here for `.arrow`.
    /// For `.angle`, the VERTEX the degree is measured at ("Vertex B").
    var pointB: CGPoint?
    /// `.angle` only - the other outer point ("Point C"). The segments
    /// drawn are always A->B->C (`pointA`->`pointB`->`pointC`).
    var pointC: CGPoint?
    var ellipseCenter: CGPoint?
    /// Normalized half-width/half-height - a circle on insert (rx == ry),
    /// independently resizable per axis after that.
    var ellipseRadii: CGSize?
    /// `.freehand` only - every point captured during the drawing
    /// gesture, in order. `[MarkupPoint]`, not `[CGPoint]` - see that
    /// type's doc comment for why (Firestore rejects the nested array
    /// a plain `[CGPoint]` would produce here). No per-point handles
    /// (impractical at potentially hundreds of points) - only a
    /// whole-body drag, which translates every point by the same delta.
    var freehandPoints: [MarkupPoint]?
    /// `.text` only - the note itself (e.g. "Release," "Plant foot").
    /// Deliberately NOT `OverlayTextContent` (Overlay.swift) - that's a
    /// 2-line title/divider/subtitle CARD with a font-pair template,
    /// built for a different job (a branded title card); forcing a
    /// short coaching note into that shape would be the same "fighting
    /// the existing type to reuse it" mistake Line/Arrow avoided by not
    /// reusing OverlayItem's single-anchor-transform. What IS reused is
    /// the proven TECHNIQUE (colored text + dark pill background,
    /// exported as a CATextLayer) - the same one `.angle`'s degree label
    /// already uses. Position is `pointA` - text only ever needs one
    /// anchor point, same as Overlay's own text already gets away with
    /// a single position.
    var text: String?

    init(
        id: UUID = UUID(),
        type: MarkupType,
        startTime: Double,
        endTime: Double,
        colorHex: String = "#FFFFFF",
        lineWidth: MarkupLineWidth = .medium,
        opacity: Double = 1,
        textSize: MarkupTextSize = .medium,
        pointA: CGPoint? = nil,
        pointB: CGPoint? = nil,
        pointC: CGPoint? = nil,
        ellipseCenter: CGPoint? = nil,
        ellipseRadii: CGSize? = nil,
        freehandPoints: [MarkupPoint]? = nil,
        text: String? = nil
    ) {
        self.id = id
        self.type = type
        self.startTime = startTime
        self.endTime = endTime
        self.colorHex = colorHex
        self.lineWidth = lineWidth
        self.opacity = opacity
        self.textSize = textSize
        self.pointA = pointA
        self.pointB = pointB
        self.pointC = pointC
        self.ellipseCenter = ellipseCenter
        self.ellipseRadii = ellipseRadii
        self.freehandPoints = freehandPoints
        self.text = text
    }

    /// Mirrors `OverlayItem.isVisible(at:)` - outside this Markup's own
    /// start/end range it's hidden entirely, in both the live preview
    /// and export.
    func isVisible(at time: Double) -> Bool {
        time >= startTime && time <= endTime
    }
}

/// The 3 points of an arrowhead triangle at `tip`, oriented along the
/// line from `tail` to `tip`, sized from `lineWidth` so it scales with
/// thickness without distorting proportions. Pure geometry, shared by
/// the live canvas (MarkupCanvasView.swift) and export
/// (MarkupExporter.swift) so they can't disagree - same principle
/// `videoDisplayRect`/`composeOverlayTransform` (OverlayEditorView.swift)
/// already establish for the rest of this app's overlay-family math.
///
/// `tail`/`tip` and `lineWidth` must already be in the SAME real
/// (point or pixel) space - never normalized 0...1 - since `lineWidth`
/// here is already the real, frame-scaled stroke width
/// (`markupStrokeWidth`), not a fraction of the frame. Convert
/// normalized geometry to view/render space first, then call this.
func arrowheadPoints(from tail: CGPoint, to tip: CGPoint, lineWidth: Double) -> [CGPoint] {
    let dx = tip.x - tail.x
    let dy = tip.y - tail.y
    let length = (dx * dx + dy * dy).squareRoot()
    guard length > 0 else { return [tip, tip, tip] }

    let angle = atan2(dy, dx)
    let headLength = CGFloat(lineWidth) * 2.6
    let headAngle: CGFloat = .pi / 7 // ~25.7 degrees each side

    let leftAngle = angle + .pi - headAngle
    let rightAngle = angle + .pi + headAngle

    let left = CGPoint(x: tip.x + headLength * cos(leftAngle), y: tip.y + headLength * sin(leftAngle))
    let right = CGPoint(x: tip.x + headLength * cos(rightAngle), y: tip.y + headLength * sin(rightAngle))

    return [tip, left, right]
}

/// The angle ABC (at vertex `vertex`, between rays toward `a` and `c`),
/// in degrees, 0...180. Pure geometry, shared by the live canvas and
/// export so they can't disagree. Uses `atan2(|cross|, dot)` rather than
/// two separate `atan2` calls subtracted from each other, specifically
/// so orientation can't flip the sign and produce the wrong magnitude
/// (e.g. 360-42 instead of 42) - `|cross|` discards the ONE thing that's
/// actually orientation-dependent (which way the shorter rotation from
/// one ray to the other goes), leaving only the magnitude, which is
/// exactly what "mathematically correct regardless of orientation"
/// requires. Degenerate (either ray zero-length) returns 0 rather than
/// NaN.
///
/// Like `arrowheadPoints`, `a`/`vertex`/`c` must already be in the SAME
/// real (point or pixel) space, never normalized 0...1 directly - a
/// non-square aspect ratio scales X and Y by different factors, so an
/// angle computed straight from normalized coordinates would read wrong
/// whenever width != height.
func angleDegrees(a: CGPoint, vertex: CGPoint, c: CGPoint) -> Double {
    let v1 = CGVector(dx: a.x - vertex.x, dy: a.y - vertex.y)
    let v2 = CGVector(dx: c.x - vertex.x, dy: c.y - vertex.y)
    let dot = v1.dx * v2.dx + v1.dy * v2.dy
    let cross = v1.dx * v2.dy - v1.dy * v2.dx
    guard v1.dx != 0 || v1.dy != 0, v2.dx != 0 || v2.dy != 0 else { return 0 }
    return atan2(abs(cross), dot) * 180 / .pi
}

/// Where the degree label sits - `distance` out from `vertex` along the
/// bisector of rays toward `a` and `c`, so it reads as "belonging to"
/// the vertex without covering it (or its drag handle). Falls back to
/// straight up when the two rays point in exactly opposite directions
/// (a 180 degree angle has no well-defined bisector side). Same real-
/// space requirement as `angleDegrees`.
func angleLabelAnchor(a: CGPoint, vertex: CGPoint, c: CGPoint, distance: CGFloat) -> CGPoint {
    func unit(_ from: CGPoint, _ to: CGPoint) -> CGVector {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.0001 else { return .zero }
        return CGVector(dx: dx / length, dy: dy / length)
    }

    let v1 = unit(vertex, a)
    let v2 = unit(vertex, c)
    var bisector = CGVector(dx: v1.dx + v2.dx, dy: v1.dy + v2.dy)
    let length = (bisector.dx * bisector.dx + bisector.dy * bisector.dy).squareRoot()
    if length < 0.0001 {
        bisector = CGVector(dx: 0, dy: -1)
    } else {
        bisector = CGVector(dx: bisector.dx / length, dy: bisector.dy / length)
    }
    return CGPoint(x: vertex.x + bisector.dx * distance, y: vertex.y + bisector.dy * distance)
}

/// A sensible default-sized Line/Arrow/Ellipse centered in the video
/// frame when a tool button is first tapped - matches
/// `OverlayEditorView`'s own "tap a thumbnail to add one, centered, at
/// the current playhead" convention (`addOverlay`), just with geometry
/// instead of a single anchor point.
func defaultMarkupOverlay(type: MarkupType, at time: Double) -> MarkupOverlay {
    switch type {
    case .line:
        return MarkupOverlay(type: .line, startTime: time, endTime: time + 4, pointA: CGPoint(x: 0.35, y: 0.5), pointB: CGPoint(x: 0.65, y: 0.5))
    case .arrow:
        return MarkupOverlay(type: .arrow, startTime: time, endTime: time + 4, pointA: CGPoint(x: 0.35, y: 0.5), pointB: CGPoint(x: 0.65, y: 0.5))
    case .ellipse:
        return MarkupOverlay(type: .ellipse, startTime: time, endTime: time + 4, ellipseCenter: CGPoint(x: 0.5, y: 0.5), ellipseRadii: CGSize(width: 0.12, height: 0.12))
    case .angle:
        // A V shape opening upward - vertex B at bottom-center, A/C
        // splayed out above it, so the degree reads clearly before the
        // user drags anything.
        return MarkupOverlay(type: .angle, startTime: time, endTime: time + 4, pointA: CGPoint(x: 0.38, y: 0.42), pointB: CGPoint(x: 0.5, y: 0.6), pointC: CGPoint(x: 0.62, y: 0.42))
    case .freehand, .text:
        // Not created through this function at all - `.freehand` comes
        // from the drawing-capture gesture (MarkupCanvasView.swift's
        // `MarkupDrawingCaptureView`), and `.text` from the name-prompt
        // sheet (`MarkupEditorView.addTextMarkup`), both of which need
        // data (captured points / the typed string) this function's
        // plain `(type, time)` signature has no way to carry.
        return MarkupOverlay(type: type, startTime: time, endTime: time + 4)
    }
}
