//
//  GlowSettings.swift
//  PitchMark
//
//  2026-09-29: per-overlay glow modifier - a soft colored halo around an
//  overlay's own alpha shape. 2026-09-30: simplified to on/off per the
//  user's own feedback ("I don't think it's necessary to have
//  adjustments... the setting would be either glow is on or off") -
//  color/intensity/radius/pulse speed & amount are no longer stored per
//  overlay; GlowLook below is the one fixed "medium, slightly animated"
//  look every glow-enabled overlay gets. `isEnabled` stays inside a
//  struct (not a raw Bool) purely so a Moment saved by the old,
//  richer-schema build still decodes cleanly - Codable ignores the
//  extra color/intensity/radius/pulse keys already sitting in an old
//  document rather than failing to decode the document at all.
//
//  The actual Core Image rendering lives in GlowEffect.swift - this file
//  is just the persisted flag plus the pure time-to-resolved-value
//  function (`resolvedGlow`) both the live preview and the export
//  compositor call with their own notion of "now" (a synced AVPlayer's
//  currentTime for preview, a sampled composition time for export) -
//  never wall-clock time, so the built-in shimmer is deterministic in an
//  export and matches whatever the preview showed at the same video
//  timestamp.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation

struct GlowSettings: Codable, Equatable {
    var isEnabled: Bool = false

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }
}

/// The one fixed glow look every enabled overlay gets - tuned to read as
/// a "medium," slightly shimmering halo rather than a subtle highlight
/// or an overpowering blob. `radiusFraction` is defined relative to the
/// overlay's *own* source pixel size (see GlowEffect.render) rather than
/// any UI/screen unit - deliberately: the previous points-based radius
/// needed a separate `referenceSize` parameter and two different caps
/// (one in points, one in pixels) to stay sane across wildly different
/// source image sizes (a small bundled PNG vs. a large Smart Cutout),
/// and that conversion was the root of two separate silent-failure bugs
/// this session. A size-relative fraction has no unit to convert and no
/// external reference to get out of sync with, by construction.
enum GlowLook {
    static let baseIntensity: Double = 0.65
    static let baseRadiusFraction: Double = 0.055
    /// Cycles per second - slow enough to read as an ambient shimmer,
    /// not a strobe.
    static let pulseSpeed: Double = 0.5
    /// 0...1 - how far intensity/radius swing above and below their base
    /// value each cycle.
    static let pulseAmount: Double = 0.4
}

/// Resolves whether/how strongly `settings` should glow at a moment of
/// *video* time (never wall-clock) - always applies `GlowLook`'s built-in
/// shimmer when enabled, since there's no longer a per-overlay pulse
/// toggle to check. Returns nil when glow is disabled or the resolved
/// values round to nothing worth rendering, so a caller can skip the
/// Core Image pass entirely rather than run it for a no-op result.
func resolvedGlow(_ settings: GlowSettings?, at time: Double) -> GlowRenderParams? {
    guard let settings, settings.isEnabled else { return nil }

    let phase = sin(2 * Double.pi * GlowLook.pulseSpeed * time)
    let factor = 1 + phase * GlowLook.pulseAmount
    let intensity = min(max(GlowLook.baseIntensity * factor, 0), 1)
    let radiusFraction = min(max(GlowLook.baseRadiusFraction * factor, 0), GlowLook.baseRadiusFraction * (1 + GlowLook.pulseAmount))

    guard intensity > 0.001, radiusFraction > 0.0005 else { return nil }
    return GlowRenderParams(intensity: intensity, radiusFraction: radiusFraction)
}
