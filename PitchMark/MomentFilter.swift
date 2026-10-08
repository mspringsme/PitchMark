//
//  MomentFilter.swift
//  PitchMark
//
//  Color/brightness filter presets - simple CIColorControls-based
//  brightness/contrast/saturation adjustment, baked into export via a
//  custom AVVideoCompositing class (MomentFilterCompositor.swift) since
//  CIFilters don't bake into AVVideoCompositionCoreAnimationTool, the
//  CALayer-based pipeline every other exporter in this feature uses -
//  this codebase already confirmed empirically that real CALayer.shadow*
//  properties don't bake into that offline renderer either, and the same
//  reasoning (it skips Core Animation's own rasterization passes)
//  extends to CALayer.filters.
//
//  Named by what they actually look like rather than implying a color
//  temperature shift ("Warm"/"Cool") that CIColorControls genuinely
//  cannot produce (no temperature/tint parameter exists in this filter -
//  that would need CITemperatureAndTint, deliberately out of scope for a
//  "simple brightness/contrast/saturation" feature). Nil `filterPreset`
//  on Moment means "no filter," same "nil means off" convention
//  fadeInEnabled/cropSettings/freezeFrame all use - there's no `.none`
//  case here, since "don't run the compositor at all" is simpler and
//  more direct than a case that has to map to a no-op adjustment.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation

enum FilterPreset: String, Codable, CaseIterable {
    case vivid
    case muted
    case highContrast
    case blackAndWhite

    var displayName: String {
        switch self {
        case .vivid: return "Vivid"
        case .muted: return "Muted"
        case .highContrast: return "High Contrast"
        case .blackAndWhite: return "B&W"
        }
    }
}

/// Plain Swift mirror of CIColorControls' three input parameters -
/// `Float`, not `Double`, matching the filter's own key types exactly so
/// `MomentFilterCompositor.swift` can pass these straight through with
/// no conversion. Defaults for an untouched image: brightness 0,
/// contrast 1, saturation 1.
struct FilterAdjustment: Equatable {
    var brightness: Float
    var contrast: Float
    var saturation: Float
}

/// The preset -> parameter lookup table - pure, no CoreImage import
/// needed to read it, standalone-verifiable on its own. Values are a
/// first pass, deliberately conservative (no preset pushes saturation
/// to 0 except the dedicated B&W case, none push contrast past 1.35) -
/// flagged for an on-device visual check before considering them final,
/// since this sandbox can't render CoreImage output to confirm they
/// look right.
func filterAdjustment(for preset: FilterPreset) -> FilterAdjustment {
    switch preset {
    case .vivid:
        return FilterAdjustment(brightness: 0, contrast: 1.15, saturation: 1.35)
    case .muted:
        return FilterAdjustment(brightness: 0.02, contrast: 0.9, saturation: 0.65)
    case .highContrast:
        return FilterAdjustment(brightness: -0.02, contrast: 1.35, saturation: 1.1)
    case .blackAndWhite:
        return FilterAdjustment(brightness: 0, contrast: 1.05, saturation: 0)
    }
}
