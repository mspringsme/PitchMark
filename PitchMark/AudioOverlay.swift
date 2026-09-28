//
//  AudioOverlay.swift
//  PitchMark
//
//  2026-09-28: an instance of an AudioAssetItem placed onto a Moment.
//  No keyframing (nothing to animate for audio - unlike the visual
//  overlay system, there's no step/hold or linear-interpolation
//  machinery needed here) and no in-clip trim: plays the full referenced
//  asset from `startTime`. `endTime` is derived (`startTime +` the
//  asset's own duration), not stored here.
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

    init(id: UUID = UUID(), assetId: String, startTime: Double, volume: Double = 1.0, volumeKeyframes: [VolumeKeyframe]? = nil) {
        self.id = id
        self.assetId = assetId
        self.startTime = startTime
        self.volume = volume
        self.volumeKeyframes = volumeKeyframes
    }
}
