//
//  MomentFreeze.swift
//  PitchMark
//
//  Freeze-frame / replay callout - hold one frame of the video for a
//  fixed duration, optionally zooming in and/or showing a text callout
//  over it, broadcast-replay style. A single freeze point per Moment for
//  V1 - confirmed scope with the user, not a list like `zoomRegions`.
//
//  Unlike every frozen-base ring member (Audio/Overlay/Zoom/Slideshow/
//  Crop), Freeze is a direct-chain editor, a sibling of Trim/Speed - see
//  MomentFreezeExporter.swift's header comment for why (it inserts dead
//  time, distorting when everything else happens, exactly like Speed).
//  No base of its own.
//
//  Reuses `OverlayTextContent` (Overlay.swift) for the optional callout
//  rather than inventing a parallel text model - the callout is rendered
//  via the exact same two-line template card every visual overlay uses
//  (`buildTextCardLayer`, OverlayExporter.swift), just painted over a
//  held still frame instead of a moving video.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import CoreGraphics

/// Nil `freezeFrame` on `Moment` means "no freeze frame" - same "nil
/// means off" convention `fadeInEnabled`/`cropSettings` already use.
struct FreezeFrame: Codable, Equatable {
    /// Seconds into the source video where the hold happens.
    var timestamp: Double
    var holdDuration: Double
    var zoomEnabled: Bool
    /// 1.0 = no zoom; higher = zoomed in by the hold's end. Only
    /// meaningful while `zoomEnabled`, same "field exists but is inert
    /// unless its toggle is on" shape `MomentDetailView`'s fade toggles
    /// already use.
    var zoomScale: Double
    /// Normalized 0...1, where the zoom centers by the hold's end - the
    /// *where*, as distinct from `zoomScale`'s *how much*. Genuinely
    /// `Optional`, not defaulted to a concrete 0.5 the way `zoomScale`
    /// is, even though every freshly-created `FreezeFrame` in this app
    /// always gets a concrete value via the init below - existing saved
    /// Moments already have a `freezeFrame` object with no
    /// "zoomCenterX"/"zoomCenterY" key at all, and Swift's synthesized
    /// `Decodable` only tolerates a missing key for an `Optional`
    /// property (the same rule that applies to `Moment`'s own fields
    /// applies recursively to a struct nested inside one of its Optional
    /// fields). `zoomCenter` below is what every reader should use -
    /// nil means "centered," same as if the key had never existed.
    var zoomCenterX: Double?
    var zoomCenterY: Double?
    var callout: OverlayTextContent?

    init(
        timestamp: Double,
        holdDuration: Double = 2.0,
        zoomEnabled: Bool = false,
        zoomScale: Double = 1.4,
        zoomCenterX: Double? = 0.5,
        zoomCenterY: Double? = 0.5,
        callout: OverlayTextContent? = nil
    ) {
        self.timestamp = timestamp
        self.holdDuration = holdDuration
        self.zoomEnabled = zoomEnabled
        self.zoomScale = zoomScale
        self.zoomCenterX = zoomCenterX
        self.zoomCenterY = zoomCenterY
        self.callout = callout
    }

    var zoomCenter: CGPoint {
        CGPoint(x: zoomCenterX ?? 0.5, y: zoomCenterY ?? 0.5)
    }
}

/// The single shared time-remap entry point for Freeze, mirroring
/// `sourceTimeToCompositeTime` (MomentSpeedRamp.swift)'s role for Speed -
/// both the exporter's own composition-building and
/// `remapAllTimeBasedFields` (Moment.swift) use this exact function, so
/// every other time-based field (mute regions, overlays, zoom regions,
/// audio overlays, volume keyframes) stays aligned with the real
/// composite timeline after a freeze is baked in.
///
/// A source time at or before the freeze point is untouched - the held
/// frame IS the frame at `freezeTimestamp`, so nothing before or at that
/// instant moves. Everything strictly after is pushed forward by the
/// full hold duration, since that much dead time was inserted right
/// after `freezeTimestamp`.
func freezeTimeToCompositeTime(_ sourceTime: Double, freezeTimestamp: Double, holdDuration: Double) -> Double {
    sourceTime <= freezeTimestamp ? sourceTime : sourceTime + holdDuration
}
