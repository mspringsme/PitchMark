//
//  GlowSettings.swift
//  PitchMark
//
//  2026-09-29: per-overlay glow modifier - a soft colored halo around an
//  overlay's own alpha shape, optionally pulsing. Persisted as an
//  Optional field on OverlayItem (Overlay.swift) since existing saved
//  Moment documents have no "glow" key - same reasoning as every other
//  field added after a struct's first ship in this codebase (see
//  Moment.swift's header comment). GlowSettings/GlowPulse's own fields
//  are non-optional-with-defaults since they're brand new types with no
//  prior saved shape to stay compatible with.
//
//  The actual Core Image rendering lives in GlowEffect.swift - this file
//  is just the persisted parameters plus the pure time-to-resolved-value
//  function (`resolvedGlow`) both the live preview and the export
//  compositor call with their own notion of "now" (a synced AVPlayer's
//  currentTime for preview, a sampled composition time for export) -
//  never wall-clock time, so a pulsing glow is deterministic in an
//  export and matches whatever the preview showed at the same video
//  timestamp.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import SwiftUI
import CoreImage

/// `Color` itself isn't Codable - this is the persisted RGBA form,
/// converted to/from `Color`/`CIColor` at the edges.
struct GlowColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let white = GlowColor(red: 1, green: 1, blue: 1, alpha: 1)

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: Color) {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        red = Double(r)
        green = Double(g)
        blue = Double(b)
        alpha = Double(a)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var ciColor: CIColor {
        CIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

struct GlowPulse: Codable, Equatable {
    var isEnabled: Bool = false
    /// Cycles per second.
    var speed: Double = 1.0
    /// 0...1 - how far intensity/radius swing above and below their base
    /// value (e.g. 0.35 = +/-35%).
    var amount: Double = 0.35

    init(isEnabled: Bool = false, speed: Double = 1.0, amount: Double = 0.35) {
        self.isEnabled = isEnabled
        self.speed = speed
        self.amount = amount
    }
}

struct GlowSettings: Codable, Equatable {
    var isEnabled: Bool = false
    var color: GlowColor = .white
    var intensity: Double = 0.6   // 0...1
    var radius: Double = 12       // points - UI caps this at 40; GlowEffect caps it again defensively
    var pulse: GlowPulse = GlowPulse()

    init(isEnabled: Bool = false, color: GlowColor = .white, intensity: Double = 0.6, radius: Double = 12, pulse: GlowPulse = GlowPulse()) {
        self.isEnabled = isEnabled
        self.color = color
        self.intensity = intensity
        self.radius = radius
        self.pulse = pulse
    }
}

/// Resolves `settings` at a moment of *video* time (never wall-clock) -
/// applies the pulse oscillation, a plain sine wave scaling intensity
/// and radius together by a factor in [1-amount, 1+amount], clamped back
/// into their valid ranges. Returns nil when glow is disabled or the
/// resolved values round to nothing worth rendering, so a caller can
/// skip the Core Image pass entirely rather than run it for a no-op
/// result.
func resolvedGlow(_ settings: GlowSettings?, at time: Double) -> GlowRenderParams? {
    guard let settings, settings.isEnabled else { return nil }

    var intensity = settings.intensity
    var radius = settings.radius

    if settings.pulse.isEnabled {
        let phase = sin(2 * Double.pi * settings.pulse.speed * time)
        let factor = 1 + phase * settings.pulse.amount
        intensity = min(max(settings.intensity * factor, 0), 1)
        radius = min(max(settings.radius * factor, 0), settings.radius * (1 + settings.pulse.amount))
    }

    guard intensity > 0.001, radius > 0.01 else { return nil }
    return GlowRenderParams(color: settings.color.ciColor, intensity: intensity, radius: radius)
}
