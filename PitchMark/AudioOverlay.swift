//
//  AudioOverlay.swift
//  PitchMark
//
//  2026-09-28: an instance of an AudioAssetItem placed onto a Moment.
//  No keyframing (nothing to animate for audio - unlike the visual
//  overlay system, there's no step/hold or linear-interpolation
//  machinery needed here). `endTime` is derived, not stored here.
//
//  2026-09-29: trim (trimStart/trimEnd) and fade (fadeInSeconds/
//  fadeOutSeconds) added. Fades need a genuine smooth ramp
//  (AVMutableAudioMixInputParameters.setVolumeRamp), unlike
//  VolumeKeyframe's step function above, which can only jump - so
//  they're separate fields layered on top of the existing volume
//  model in MomentAudioMixer, not expressed as keyframes.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation

/// A volume level effective from `time` onward, held constant until the
/// next keyframe (or the end of the clip) - a step function, same model
/// SpeedKeyframe/speed(at:keyframes:) uses for playback speed. This
/// mirrors AVMutableAudioMixInputParameters.setVolume(_:at:)'s own step
/// semantics exactly, so applying these to a mix needs no interpolation
/// math of its own (see MomentAudioMixer.applyVolumeAutomation).
struct VolumeKeyframe: Identifiable, Codable, Equatable {
    let id: UUID
    var time: Double
    var volume: Double   // 0...1

    init(id: UUID = UUID(), time: Double, volume: Double) {
        self.id = id
        self.time = time
        self.volume = volume
    }
}

/// The volume in effect at `time` under the step-function model above:
/// the latest keyframe at-or-before `time`, or `flat` if `time` is
/// before the first keyframe (or there are none at all). Used by the
/// editor's "Add Volume Point" to seed a new point at whatever value is
/// already playing there, so adding a point never causes a jump.
func volumeAt(_ time: Double, keyframes: [VolumeKeyframe], flat: Double) -> Double {
    let sorted = keyframes.sorted { $0.time < $1.time }
    guard let match = sorted.last(where: { $0.time <= time }) else {
        return sorted.first?.volume ?? flat
    }
    return match.volume
}

struct AudioOverlayItem: Identifiable, Codable, Equatable {
    let id: UUID
    var assetId: String
    var startTime: Double
    var volume: Double   // 0...1 - flat/legacy volume, used when volumeKeyframes is nil/empty
    /// Optional for the same reason every field added after a struct's
    /// first ship is: existing saved AudioOverlayItems have no
    /// "volumeKeyframes" key. Nil/empty means "flat `volume`, unchanged."
    var volumeKeyframes: [VolumeKeyframe]? = nil
    /// 2026-09-29 - all four default to "no trim, no fade" so every
    /// overlay placed before this shipped keeps playing identically.
    var trimStart: Double = 0
    /// nil = play to the asset's own natural end.
    var trimEnd: Double? = nil
    var fadeInSeconds: Double = 0
    var fadeOutSeconds: Double = 0

    init(
        id: UUID = UUID(),
        assetId: String,
        startTime: Double,
        volume: Double = 1.0,
        volumeKeyframes: [VolumeKeyframe]? = nil,
        trimStart: Double = 0,
        trimEnd: Double? = nil,
        fadeInSeconds: Double = 0,
        fadeOutSeconds: Double = 0
    ) {
        self.id = id
        self.assetId = assetId
        self.startTime = startTime
        self.volume = volume
        self.volumeKeyframes = volumeKeyframes
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.fadeInSeconds = fadeInSeconds
        self.fadeOutSeconds = fadeOutSeconds
    }
}

/// Clamps trim/fade to a valid, mutually-consistent shape for a source
/// asset of `assetDuration`: trimStart/trimEnd stay in [0, assetDuration]
/// with trimStart <= trimEnd (trimEnd nil means "play to the asset's
/// natural end"), and fadeIn/fadeOut are scaled down proportionally -
/// never just clipped, which would change their ratio - if their sum
/// would exceed the resulting trimmed duration. Used by both the editor
/// UI (so a slider can never express an inconsistent shape) and the
/// mixer (so export matches whatever was previewed - one clamping rule,
/// not two that could drift apart).
func normalizedTrimAndFade(
    trimStart: Double,
    trimEnd: Double?,
    fadeIn: Double,
    fadeOut: Double,
    assetDuration: Double
) -> (trimStart: Double, trimEnd: Double, fadeIn: Double, fadeOut: Double) {
    let clampedAssetDuration = max(assetDuration, 0)
    let resolvedTrimEnd = min(max(trimEnd ?? clampedAssetDuration, 0), clampedAssetDuration)
    let resolvedTrimStart = min(max(trimStart, 0), resolvedTrimEnd)
    let trimmedDuration = resolvedTrimEnd - resolvedTrimStart

    var resolvedFadeIn = max(fadeIn, 0)
    var resolvedFadeOut = max(fadeOut, 0)
    let fadeSum = resolvedFadeIn + resolvedFadeOut
    if fadeSum > trimmedDuration && fadeSum > 0 {
        let scale = trimmedDuration / fadeSum
        resolvedFadeIn *= scale
        resolvedFadeOut *= scale
    }

    return (resolvedTrimStart, resolvedTrimEnd, resolvedFadeIn, resolvedFadeOut)
}
