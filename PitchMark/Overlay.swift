//
//  Overlay.swift
//  PitchMark
//
//  Step 1 of the 2026-09-26 Asset + Video Overlay Keyframe Editor spec
//  (supersedes the original "Phase 8: intelligent overlays" item from the
//  Coach/Parent/Family roadmap). Pure data model + interpolation only - no
//  UI, nothing wired into Moment yet. Deliberately depends on only
//  Foundation/CoreGraphics so this file can be compiled and run standalone
//  for verification, the same way AtBatCountRules was.
//
//  Core principle from the spec: live preview (a later step, synced to
//  AVPlayer) and export (a later step, AVVideoCompositionCoreAnimationTool)
//  must both drive off this same interpolation function, never duplicate
//  the math - so what the user sees while editing is exactly what they get.
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import CoreGraphics

/// An overlay's base (scale = 1) size, as a fraction of the video frame's
/// shorter dimension. Shared by the live preview (`OverlayEditorView`,
/// scaled against the on-screen letterboxed `videoRect`) and export
/// (`OverlayExporter`, scaled against the full pixel `renderSize`) so an
/// overlay's size relative to the video frame is identical in both,
/// regardless of device/window size - a fixed point value (what preview
/// used before this existed) doesn't translate to export pixels without
/// silently changing proportion from device to device.
let overlayBaseSizeFraction: CGFloat = 0.18

struct OverlayKeyframe: Identifiable, Codable, Equatable {
    let id: UUID
    var time: Double        // seconds, relative to the overlay item's own timeline
    var position: CGPoint   // normalized 0...1, relative to video frame
    var scale: Double
    var rotation: Double    // radians
    var opacity: Double

    init(id: UUID = UUID(), time: Double, position: CGPoint, scale: Double = 1, rotation: Double = 0, opacity: Double = 1) {
        self.id = id
        self.time = time
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.opacity = opacity
    }
}

/// The interpolated result at a point in time - what both the live preview
/// and the export compositor actually render.
struct OverlayTransform: Equatable {
    var position: CGPoint
    var scale: Double
    var rotation: Double
    var opacity: Double
}

struct OverlayItem: Identifiable, Codable {
    let id: UUID
    /// A `LibraryAsset`/`AssetItem` id - a plain String for both bundled
    /// assets ("bundled-circle") and user-created ones (Firestore's
    /// `@DocumentID`), not a UUID. Fixed here in step 3, before step 2's
    /// asset-library shape existed yet.
    var assetID: String
    var startTime: Double
    var endTime: Double
    var keyframes: [OverlayKeyframe]
    /// 2026-09-30 - Optional for the same reason every field added after
    /// this struct's first ship is: existing saved Moment documents
    /// have no "fadeInEnabled"/"fadeOutEnabled" key. nil means "off",
    /// same as false - there's no third state.
    var fadeInEnabled: Bool? = nil
    var fadeOutEnabled: Bool? = nil

    init(id: UUID = UUID(), assetID: String, startTime: Double, endTime: Double, keyframes: [OverlayKeyframe] = [], fadeInEnabled: Bool? = nil, fadeOutEnabled: Bool? = nil) {
        self.id = id
        self.assetID = assetID
        self.startTime = startTime
        self.endTime = endTime
        self.keyframes = keyframes
        self.fadeInEnabled = fadeInEnabled
        self.fadeOutEnabled = fadeOutEnabled
    }

    /// Whether this overlay should be rendered at all at `time` - outside
    /// its start/end range it's hidden regardless of what transform() would
    /// compute.
    func isVisible(at time: Double) -> Bool {
        time >= startTime && time <= endTime
    }

    /// The single shared interpolation entry point. Before the first
    /// keyframe or after the last, holds that keyframe's value (no
    /// extrapolation, per spec); between two keyframes, interpolates
    /// linearly. Returns nil only when there are no keyframes at all.
    func transform(at time: Double) -> OverlayTransform? {
        let sorted = keyframes.sorted { $0.time < $1.time }
        guard let first = sorted.first else { return nil }
        guard let last = sorted.last else { return nil }

        if time <= first.time {
            return OverlayTransform(position: first.position, scale: first.scale, rotation: first.rotation, opacity: first.opacity)
        }
        if time >= last.time {
            return OverlayTransform(position: last.position, scale: last.scale, rotation: last.rotation, opacity: last.opacity)
        }

        // sorted has >= 2 entries here, since time is strictly between
        // first.time and last.time.
        for index in 0..<(sorted.count - 1) {
            let start = sorted[index]
            let end = sorted[index + 1]
            guard time >= start.time && time <= end.time else { continue }
            let span = end.time - start.time
            let fraction = span > 0 ? (time - start.time) / span : 0
            return OverlayTransform(
                position: CGPoint(
                    x: start.position.x + (end.position.x - start.position.x) * fraction,
                    y: start.position.y + (end.position.y - start.position.y) * fraction
                ),
                scale: start.scale + (end.scale - start.scale) * fraction,
                rotation: start.rotation + (end.rotation - start.rotation) * fraction,
                opacity: start.opacity + (end.opacity - start.opacity) * fraction
            )
        }

        // Unreachable given the bounds checks above, but keeps this total.
        return OverlayTransform(position: last.position, scale: last.scale, rotation: last.rotation, opacity: last.opacity)
    }

    /// "No explicit add-keyframe button" from the spec: moving/scaling/
    /// rotating an overlay while the playhead sits at `time` should call
    /// this rather than always appending. Replaces the existing keyframe
    /// within `tolerance` seconds of `time` if one exists; otherwise
    /// inserts a new one, keeping `keyframes` sorted by time.
    mutating func upsertKeyframe(time: Double, transform: OverlayTransform, tolerance: Double) {
        let newKeyframe = OverlayKeyframe(
            time: time,
            position: transform.position,
            scale: transform.scale,
            rotation: transform.rotation,
            opacity: transform.opacity
        )

        if let matchIndex = keyframes.firstIndex(where: { abs($0.time - time) <= tolerance }) {
            let existingId = keyframes[matchIndex].id
            keyframes[matchIndex] = OverlayKeyframe(
                id: existingId,
                time: time,
                position: transform.position,
                scale: transform.scale,
                rotation: transform.rotation,
                opacity: transform.opacity
            )
        } else {
            keyframes.append(newKeyframe)
        }

        keyframes.sort { $0.time < $1.time }
    }
}

/// Fixed duration for a "quick" fade, in seconds - deliberately not a
/// user-adjustable value. Fade in/out are on/off toggles per overlay
/// (`OverlayItem.fadeInEnabled`/`fadeOutEnabled`), not a duration
/// slider - matches the Glow feature's earlier simplification to
/// on/off-with-fixed-internal-parameters rather than exposing more
/// controls than the user asked for.
let quickFadeDuration: Double = 0.3

/// Multiplies an already-keyframe-interpolated opacity (whatever
/// `OverlayItem.transform(at:)` produced) by a fade-in/fade-out
/// envelope. Pure and standalone-verifiable, same discipline as every
/// other timing function in this feature - both the live preview
/// (`OverlayEditorView`) and the export compositor
/// (`OverlayExporter.swift`) call this at the same sampled times they
/// already use for everything else, so a fade can't disagree between
/// the two.
///
/// If both fades are enabled and the overlay's own `startTime...endTime`
/// span is shorter than `2 * quickFadeDuration`, both scale down
/// proportionally so they meet in the middle rather than overlapping -
/// same shape as `AudioOverlay.swift`'s `normalizedTrimAndFade` scaling
/// fadeIn/fadeOut down when they'd exceed the trimmed clip's own
/// duration.
func fadeOpacityMultiplier(time: Double, startTime: Double, endTime: Double, fadeInEnabled: Bool, fadeOutEnabled: Bool) -> Double {
    guard fadeInEnabled || fadeOutEnabled else { return 1 }
    let span = endTime - startTime
    guard span > 0 else { return 1 }

    var fadeIn = fadeInEnabled ? quickFadeDuration : 0
    var fadeOut = fadeOutEnabled ? quickFadeDuration : 0
    let total = fadeIn + fadeOut
    if total > span {
        let scale = span / total
        fadeIn *= scale
        fadeOut *= scale
    }

    var multiplier = 1.0
    if fadeIn > 0 {
        let elapsed = time - startTime
        if elapsed < fadeIn {
            multiplier = min(multiplier, max(elapsed / fadeIn, 0))
        }
    }
    if fadeOut > 0 {
        let remaining = endTime - time
        if remaining < fadeOut {
            multiplier = min(multiplier, max(remaining / fadeOut, 0))
        }
    }
    return multiplier
}
