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

struct AudioOverlayItem: Identifiable, Codable, Equatable {
    let id: UUID
    var assetId: String
    var startTime: Double
    var volume: Double   // 0...1

    init(id: UUID = UUID(), assetId: String, startTime: Double, volume: Double = 1.0) {
        self.id = id
        self.assetId = assetId
        self.startTime = startTime
        self.volume = volume
    }
}
