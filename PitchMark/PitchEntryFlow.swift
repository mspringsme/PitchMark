//
//  PitchEntryFlow.swift
//  PitchMark
//
//  Track Game uses the Call Pitches screen (2026-11-20, user's call): the
//  same pitch chips, strike zone and result sheet, for continuity. The one
//  difference is the code: Call Pitches calls a pitch (a code goes to the
//  armband / Display), then records where it actually went; Track Game is
//  watching a pitch that was already thrown, so its one zone tap IS where
//  it went and the result sheet opens straight away - no code, no second
//  tap, nothing sent to the Display or the live room's pending call.
//
//  Plain rules, kept out of PitchTrackerView so they can be tested.
//

import Foundation

enum PitchEntryFlow {
    enum Step: Equatable {
        /// Show the code(s) to signal, then wait for where it went.
        case signalCode
        /// Straight to the result sheet; the zone tap was where it went.
        case recordResult
    }

    /// What follows a zone tap with a pitch chip picked.
    static func stepAfterZoneTap(mode: TrackingMode) -> Step {
        mode == .scout ? .recordResult : .signalCode
    }

    /// The code panel (CalledPitchView) is only for calling pitches.
    static func showsCodePanel(_ mode: TrackingMode) -> Bool {
        stepAfterZoneTap(mode: mode) == .signalCode
    }

    /// Only a called pitch is announced (Display, the room's pending call).
    static func announcesCall(_ mode: TrackingMode) -> Bool {
        mode == .coach
    }

    /// The pitch chips: Call Pitches has the Catcher chip ("" - the
    /// catcher calls it); Track Game has Unknown last instead - you often
    /// can't tell what the other team's pitcher threw.
    static func chipOptions(_ pitches: [String], mode: TrackingMode) -> [String] {
        mode == .scout ? pitches + [PitchEvent.unknownPitch] : [""] + pitches
    }
}
