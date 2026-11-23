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

// MARK: - Estimate step and chips (2026-11-21, user's calls)

extension PitchEntryFlow {
    /// The pitch a Track Game zone tap records before any estimate: the
    /// picked chip, or Unknown with none. Never "Catcher" - a hidden
    /// Catcher pick carried over from Call Pitches used to start the
    /// catcher's estimate in a full-height sheet that hid the zone it asked
    /// you to tap, and the next tap cleared the result.
    static func trackedPitch(chip: String) -> String {
        let trimmed = chip.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty || trimmed == "Catcher") ? PitchEvent.unknownPitch : trimmed
    }

    /// Whether the "Estimate pitch type and called location?" panel shows
    /// after where the pitch went is known: every Track Game pitch, and a
    /// Catcher call in Call Pitches.
    static func showsEstimate(mode: TrackingMode, callPitch: String) -> Bool {
        mode == .scout || callPitch.trimmingCharacters(in: .whitespacesAndNewlines) == "Catcher"
    }

    /// Done needs a called spot for the catcher's estimate; in Track Game a
    /// pitch type alone is an answer.
    static func estimateCanFinish(mode: TrackingMode, draftLocation: String?) -> Bool {
        mode == .scout || draftLocation != nil
    }

    /// A chip tap: tapping the selected chip again deselects it ("" - Catcher
    /// in Call Pitches, nothing in Track Game).
    static func chipAfterTap(current: String, tapped: String) -> String {
        current == tapped ? "" : tapped
    }

    /// The chip picked after a pitch is saved: Track Game starts every
    /// pitch with none; Call Pitches keeps the coach's pick.
    static func chipAfterSave(current: String, mode: TrackingMode) -> String {
        mode == .scout ? "" : current
    }
}

extension PitchEntryFlow {
    /// A zone spot without its Strike/Ball word ("Strike Middle" ->
    /// "Middle"). The zone hands over the full label when no chip is
    /// picked, and the result title adds the word again ("Strike Strike
    /// Middle").
    static func bareLocation(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        for word in ["Strike ", "Ball "] where trimmed.hasPrefix(word) {
            return String(trimmed.dropFirst(word.count))
        }
        return trimmed
    }
}
