import Foundation

/// Canonical balls/strikes pair. Values are always clamped to legal ranges, so an
/// `AtBatCount` can never hold an impossible count like 5-4.
struct AtBatCount: Equatable, Codable {
    /// A fourth ball ends the at-bat, so a live count never exceeds three.
    static let maxBalls = 3
    /// A third strike ends the at-bat, so a live count never exceeds two.
    static let maxStrikes = 2

    static let start = AtBatCount(balls: 0, strikes: 0)

    private(set) var balls: Int
    private(set) var strikes: Int

    init(balls: Int, strikes: Int) {
        self.balls = min(max(balls, 0), AtBatCount.maxBalls)
        self.strikes = min(max(strikes, 0), AtBatCount.maxStrikes)
    }

    var displayText: String { "\(balls)-\(strikes)" }
}

/// Why an at-bat ended. Used for the human-readable count label on a saved pitch.
enum AtBatTerminal: String, Equatable, Codable {
    case walk
    case strikeout
    case hitByPitch
    case out
    case hit

    var displayText: String {
        switch self {
        case .walk: return "Ball 4"
        case .strikeout: return "Strikeout"
        case .hitByPitch: return "HBP"
        case .out: return "Out"
        case .hit: return "Hit"
        }
    }
}

/// What a single pitch does to the count.
enum PitchCountEffect: Equatable {
    case ball
    case strike
    case foul
    case endsAtBat(AtBatTerminal)
    case noChange
}

/// The only place in the app that knows how a pitch changes the count.
///
/// This replaced three separate implementations that had drifted apart (the pitch
/// result sheet's live preview, the sheet's save path, and scout mode). They
/// disagreed on real cases - for example whether recording an `Out` reset the
/// count, and whether a bare in-zone location counted as a strike - which is why
/// the count could appear to change at random depending on which screen you used.
enum AtBatCountRules {

    /// The subset of a pitch that matters for counting. Deliberately dumb data so
    /// the rules stay pure and testable, with no Firestore or SwiftUI dependency.
    struct PitchFacts: Equatable {
        var isBall: Bool = false
        var strikeSwinging: Bool = false
        var strikeLooking: Bool = false
        var isFoul: Bool = false
        /// The recorded location was inside the strike zone. This is a *location*
        /// fact, not a call, so it only counts as a strike when nothing more
        /// specific was recorded.
        var locationInStrikeZone: Bool = false
        var isHitBatter: Bool = false
        var outcome: String? = nil

        init(
            isBall: Bool = false,
            strikeSwinging: Bool = false,
            strikeLooking: Bool = false,
            isFoul: Bool = false,
            locationInStrikeZone: Bool = false,
            isHitBatter: Bool = false,
            outcome: String? = nil
        ) {
            self.isBall = isBall
            self.strikeSwinging = strikeSwinging
            self.strikeLooking = strikeLooking
            self.isFoul = isFoul
            self.locationInStrikeZone = locationInStrikeZone
            self.isHitBatter = isHitBatter
            self.outcome = outcome
        }
    }

    /// Outcomes that put the batter on base with a hit, ending the at-bat.
    private static let hitOutcomes: Set<String> = ["1B", "2B", "3B", "HR", "HIT"]

    /// Classify a pitch. Order matters: explicit terminal outcomes win over
    /// per-pitch effects, and specific calls win over the generic location fact.
    static func effect(for facts: PitchFacts) -> PitchCountEffect {
        let outcome = (facts.outcome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Outcomes that end the at-bat outright, whatever the current count.
        if facts.isHitBatter || outcome.caseInsensitiveCompare("HBP") == .orderedSame {
            return .endsAtBat(.hitByPitch)
        }
        if outcome.caseInsensitiveCompare("Walk") == .orderedSame {
            return .endsAtBat(.walk)
        }
        if outcome == "K" || outcome == "ꓘ" {
            return .endsAtBat(.strikeout)
        }
        if outcome.caseInsensitiveCompare("Out") == .orderedSame {
            return .endsAtBat(.out)
        }
        if hitOutcomes.contains(outcome.uppercased()) {
            return .endsAtBat(.hit)
        }

        // 2. A foul is a strike only below two strikes, so it needs its own case.
        if facts.isFoul || outcome.caseInsensitiveCompare("Foul") == .orderedSame {
            return .foul
        }

        // 3. Explicit calls beat the generic location fact.
        if facts.strikeSwinging || facts.strikeLooking {
            return .strike
        }
        if facts.isBall {
            return .ball
        }
        if facts.locationInStrikeZone {
            return .strike
        }

        return .noChange
    }

    /// Apply one pitch to a count, reporting whether it ended the at-bat.
    /// When the at-bat ends the count resets, because the next pitch belongs to
    /// the next batter.
    static func apply(
        _ facts: PitchFacts,
        to prior: AtBatCount
    ) -> (count: AtBatCount, terminal: AtBatTerminal?) {
        switch effect(for: facts) {
        case .endsAtBat(let terminal):
            return (.start, terminal)

        case .foul:
            // A foul with two strikes leaves the count alone.
            guard prior.strikes < AtBatCount.maxStrikes else { return (prior, nil) }
            return (AtBatCount(balls: prior.balls, strikes: prior.strikes + 1), nil)

        case .ball:
            // The fourth ball is a walk.
            guard prior.balls < AtBatCount.maxBalls else { return (.start, .walk) }
            return (AtBatCount(balls: prior.balls + 1, strikes: prior.strikes), nil)

        case .strike:
            // The third strike is a strikeout.
            guard prior.strikes < AtBatCount.maxStrikes else { return (.start, .strikeout) }
            return (AtBatCount(balls: prior.balls, strikes: prior.strikes + 1), nil)

        case .noChange:
            return (prior, nil)
        }
    }

    /// Replay a sequence of pitches over a starting count.
    static func reduce(_ pitches: [PitchFacts], from seed: AtBatCount = .start) -> AtBatCount {
        pitches.reduce(seed) { apply($1, to: $0).count }
    }
}

extension AtBatCountRules.PitchFacts {
    /// Read the count-relevant facts off a recorded pitch.
    init(event: PitchEvent) {
        let outcome = (event.outcome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            isBall: event.isBall == true,
            strikeSwinging: event.strikeSwinging,
            strikeLooking: event.strikeLooking,
            isFoul: outcome.caseInsensitiveCompare("Foul") == .orderedSame,
            locationInStrikeZone: event.isStrike,
            isHitBatter: outcome.caseInsensitiveCompare("HBP") == .orderedSame,
            outcome: event.outcome
        )
    }
}

extension PitchEvent {
    /// Stamp the count onto this event from a single place, so the numeric fields
    /// and the human-readable label can never disagree. `atBatCount` is written
    /// for display only and is never parsed back into a count.
    mutating func applyCount(_ count: AtBatCount, terminal: AtBatTerminal?) {
        if let terminal {
            // A terminal pitch is labelled by how the at-bat ended, and the stored
            // count is the reset one the next batter starts from.
            atBatBalls = AtBatCount.start.balls
            atBatStrikes = AtBatCount.start.strikes
            atBatCount = terminal.displayText
        } else {
            atBatBalls = count.balls
            atBatStrikes = count.strikes
            atBatCount = count.displayText
        }
    }
}
