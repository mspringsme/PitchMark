//
//  PitchEventEdit.swift
//  PitchMark
//
//  Editing a saved pitch from the cards sheet, and the review step every
//  save passes through. Pulled out of CalledPitchRecord (2026-11-01, audit
//  batch 5) so it can be unit tested - the edit used to rebuild the pitch
//  field by field and silently dropped the tracking mode, catcher's
//  estimate, hitter link, author, count and markers.
//
//  Compiled into the Display target too (CalledPitchRecord is shared).
//

import Foundation

enum PitchEventEdit {
    /// The saved pitch with the edit sheet's answers applied. The sheet
    /// answers the result - the call, outcome, batted ball, markers, play and
    /// count; everything else (who, when, which game/pitcher/batter, tracking
    /// mode, bases before) stays as saved.
    static func applying(_ edited: PitchEvent, to original: PitchEvent) -> PitchEvent {
        var updated = original
        updated.pitch = edited.pitch
        updated.location = edited.location
        updated.codes = edited.codes
        updated.isStrike = edited.isStrike
        updated.isBall = edited.isBall
        updated.calledPitch = edited.calledPitch ?? original.calledPitch
        updated.strikeSwinging = edited.strikeSwinging
        updated.strikeLooking = edited.strikeLooking
        updated.wildPitch = edited.wildPitch
        updated.passedBall = edited.passedBall
        updated.outcome = edited.outcome
        updated.descriptor = edited.descriptor
        updated.errorOnPlay = edited.errorOnPlay
        updated.battedBallRegion = edited.battedBallRegion
        updated.battedBallType = edited.battedBallType
        updated.battedBallTapX = edited.battedBallTapX
        updated.battedBallTapY = edited.battedBallTapY
        updated.strikeSwingingMarker = edited.strikeSwingingMarker
        updated.strikeLookingMarker = edited.strikeLookingMarker
        updated.ballMarker = edited.ballMarker
        updated.foulMarker = edited.foulMarker
        // The sheet only hands the estimate back on a Catcher call; it can't
        // remove one.
        updated.catcherEstimate = edited.catcherEstimate ?? original.catcherEstimate
        if edited.atBatBalls != nil, edited.atBatStrikes != nil {
            updated.atBatBalls = edited.atBatBalls
            updated.atBatStrikes = edited.atBatStrikes
            updated.atBatCount = edited.atBatCount
        }
        updated.play = BaseRunnerRules.playIfConsistent(
            edited.play ?? original.play,
            outcome: edited.outcome,
            errorOnPlay: edited.errorOnPlay
        )
        // The sheet starts from the saved fielders, so its answer is the
        // whole answer; nil means it had none to give. The defense copy is
        // when the pitch was thrown and never changes.
        updated.fieldingOuts = FieldingPlay.consistentOuts(edited.fieldingOuts ?? original.fieldingOuts, for: updated)
        updated.errorPositions = FieldingPlay.consistentErrors(edited.errorPositions ?? original.errorPositions, for: updated)
        return updated
    }

    /// The count `original` was thrown at: the stored count of the pitch
    /// before it to the same batter (already the reset 0-0 if that pitch
    /// ended an at-bat), else 0-0. With no batter recorded, the pitch before
    /// it in the game stands in. Pitches after it are not consulted.
    static func countBefore(_ original: PitchEvent, in events: [PitchEvent]) -> AtBatCount {
        let gameId = EventCopyPaths.trimmed(original.gameId)
        let batterId = EventCopyPaths.trimmed(original.opponentBatterId)
        let jersey = EventCopyPaths.trimmed(original.opponentJersey)

        let earlier = events.filter { event in
            guard event.timestamp < original.timestamp else { return false }
            if let id = original.id, event.id == id { return false }
            if EventCopyPaths.trimmed(event.gameId) != gameId { return false }
            if let batterId { return EventCopyPaths.trimmed(event.opponentBatterId) == batterId }
            if let jersey { return EventCopyPaths.trimmed(event.opponentJersey) == jersey }
            return true
        }
        guard let previous = earlier.max(by: { $0.timestamp < $1.timestamp }),
              let balls = previous.atBatBalls,
              let strikes = previous.atBatStrikes
        else { return .start }
        return AtBatCount(balls: balls, strikes: strikes)
    }

    /// Whether saving an edit may move the tracker's count. Only the game's
    /// latest pitch sets the current count; an older pitch's count belongs
    /// to an at-bat that is over.
    static func editMovesTrackerCount(_ original: PitchEvent, in events: [PitchEvent]) -> Bool {
        let gameId = EventCopyPaths.trimmed(original.gameId)
        return !events.contains { event in
            event.timestamp > original.timestamp
                && event.id != original.id
                && EventCopyPaths.trimmed(event.gameId) == gameId
        }
    }

    /// The review step's count, stamped through `applyCount` like every other
    /// save: a pitch that ends the at-bat is labelled by how it ended and
    /// stores the reset count; any other keeps the count the review shows.
    static func stampReviewedCount(_ event: inout PitchEvent, balls: Int, strikes: Int) {
        let effect = AtBatCountRules.effect(for: AtBatCountRules.PitchFacts(event: event))
        if case .endsAtBat(let terminal) = effect {
            event.applyCount(.start, terminal: terminal)
        } else {
            event.applyCount(AtBatCount(balls: balls, strikes: strikes), terminal: nil)
        }
    }

    /// Whether the review step opens with Strike on: a result that forces a
    /// strike, or a scout pitch that was put in play.
    static func reviewStartsAsStrike(_ event: PitchEvent) -> Bool {
        let scoutInPlay = event.trackingMode == .scout && (
            EventCopyPaths.trimmed(event.battedBallRegion) != nil
                || event.descriptor?.localizedCaseInsensitiveContains("hit") == true
        )
        return pitchEventForcesStrikeResult(event) || scoutInPlay
    }
}
