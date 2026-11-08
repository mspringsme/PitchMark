import Foundation

struct PitchStatsSnapshot {
    let totalPitches: Int
    let strikePitches: Int
    let ballPitches: Int
    let hitSpotPitches: Int
    let locationAnalyticsEligibleCount: Int
    let strikeLookingCount: Int
    let strikeSwingingCount: Int
    let foulCount: Int
    let walkCount: Int
    let hitCount: Int
    let wildPitchCount: Int
    let passedBallCount: Int
    let firstPitchStrike: (made: Int, total: Int)
    let pitchBreakdown: [(name: String, count: Int)]
    let outcomeBreakdown: [(name: String, count: Int)]

    init(
        totalPitches: Int,
        strikePitches: Int,
        ballPitches: Int,
        hitSpotPitches: Int,
        locationAnalyticsEligibleCount: Int,
        strikeLookingCount: Int,
        strikeSwingingCount: Int,
        foulCount: Int = 0,
        walkCount: Int,
        hitCount: Int,
        wildPitchCount: Int,
        passedBallCount: Int,
        firstPitchStrike: (made: Int, total: Int),
        pitchBreakdown: [(name: String, count: Int)],
        outcomeBreakdown: [(name: String, count: Int)]
    ) {
        self.totalPitches = totalPitches
        self.strikePitches = strikePitches
        self.ballPitches = ballPitches
        self.hitSpotPitches = hitSpotPitches
        self.locationAnalyticsEligibleCount = locationAnalyticsEligibleCount
        self.strikeLookingCount = strikeLookingCount
        self.strikeSwingingCount = strikeSwingingCount
        self.foulCount = foulCount
        self.walkCount = walkCount
        self.hitCount = hitCount
        self.wildPitchCount = wildPitchCount
        self.passedBallCount = passedBallCount
        self.firstPitchStrike = firstPitchStrike
        self.pitchBreakdown = pitchBreakdown
        self.outcomeBreakdown = outcomeBreakdown
    }

    var hasLocationAnalytics: Bool {
        locationAnalyticsEligibleCount > 0
    }
}

enum PitchStatsCalculator {
    /// A strikeout, however it was recorded - an explicit K/ꓘ or a third
    /// strike stored at 0-0 (AtBatCountRules.endOfAtBat), the same rule the
    /// hitter's line uses.
    static func isStrikeout(_ event: PitchEvent) -> Bool {
        event.atBatEnd == .strikeout
    }

    /// Called third strike: marked looking, or recorded as ꓘ.
    static func isStrikeoutLooking(_ event: PitchEvent) -> Bool {
        isStrikeout(event) && (event.strikeLooking || event.outcome?.trimmingCharacters(in: .whitespacesAndNewlines) == "ꓘ")
    }

    static func isStrikeoutSwinging(_ event: PitchEvent) -> Bool {
        isStrikeout(event) && !isStrikeoutLooking(event)
    }

    /// A walk, however it was recorded - "Walk"/"BB" or a fourth ball
    /// stored at 0-0.
    static func isWalk(_ event: PitchEvent) -> Bool {
        event.atBatEnd == .walk
    }

    static func snapshot(for events: [PitchEvent]) -> PitchStatsSnapshot {
        let strikePitches = events.filter { inferredPitchResultType(for: $0) == .strike }.count
        let ballPitches = events.filter { inferredPitchResultType(for: $0) == .ball }.count
        let locationAnalyticsEligibleEvents = events.filter { $0.supportsLocationAnalytics }
        let hitSpotPitches = locationAnalyticsEligibleEvents.filter { isLocationMatch($0) }.count

        let pitchBreakdown = Dictionary(grouping: events, by: { $0.pitch.isEmpty ? "-" : $0.pitch })
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.name < rhs.name }
                return lhs.count > rhs.count
            }

        let outcomeBreakdown = Dictionary(grouping: events, by: { event in
            let trimmed = event.outcome?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "No outcome" : trimmed
        })
        .map { (name: $0.key, count: $0.value.count) }
        .sorted { lhs, rhs in
            if lhs.count == rhs.count { return lhs.name < rhs.name }
            return lhs.count > rhs.count
        }

        return PitchStatsSnapshot(
            totalPitches: events.count,
            strikePitches: strikePitches,
            ballPitches: ballPitches,
            hitSpotPitches: hitSpotPitches,
            locationAnalyticsEligibleCount: locationAnalyticsEligibleEvents.count,
            strikeLookingCount: events.filter { $0.strikeLooking }.count,
            strikeSwingingCount: events.filter { $0.strikeSwinging }.count,
            foulCount: events.filter { event in
                let outcome = event.outcome?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return outcome.caseInsensitiveCompare("Foul") == .orderedSame || event.isFoulInferred || event.foulMarker != nil
            }.count,
            walkCount: events.filter(isWalk).count,
            hitCount: events.filter(pitchEventIsCreditedHit).count,
            wildPitchCount: events.filter { $0.wildPitch }.count,
            passedBallCount: events.filter { $0.passedBall }.count,
            firstPitchStrike: sharedFirstPitchStrikeMetrics(for: events),
            pitchBreakdown: pitchBreakdown,
            outcomeBreakdown: outcomeBreakdown
        )
    }
}

/// What the pitcher stats heatmap shows: one pitch type's coach-mode pitches
/// (`supportsLocationAnalytics`), optionally only those recorded in or out of
/// the zone. Pitch names are compared trimmed - the picker lists trimmed
/// names, so an untrimmed "Fastball " used to drop out of its own map.
enum HeatmapSelection {
    enum Zone { case all, strikes, balls }

    static func pitchName(_ event: PitchEvent) -> String {
        event.pitch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func eligible(_ events: [PitchEvent]) -> [PitchEvent] {
        events.filter { $0.supportsLocationAnalytics && !pitchName($0).isEmpty }
    }

    static func pitchTypes(_ events: [PitchEvent]) -> [String] {
        Set(eligible(events).map(pitchName))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func counts(_ events: [PitchEvent]) -> [String: Int] {
        Dictionary(grouping: eligible(events), by: pitchName).mapValues(\.count)
    }

    static func events(_ events: [PitchEvent], pitch: String, zone: Zone) -> [PitchEvent] {
        eligible(events)
            .filter { pitchName($0) == pitch }
            .filter { event in
                switch zone {
                case .all: return true
                case .strikes: return isStrikeZone(event.location)
                case .balls: return !isStrikeZone(event.location)
                }
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// "Strike …" / "Ball …", or one of the old unprefixed in-zone labels.
    static func isStrikeZone(_ rawLocation: String) -> Bool {
        let lower = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasPrefix("strike ") { return true }
        if lower.hasPrefix("ball ") { return false }
        let legacyStrikeLabels: Set<String> = [
            "up & out", "up", "up & in",
            "out", "middle", "in",
            "↓ & out", "↓", "↓ & in",
            "down & out", "down", "down & in",
            "low & out", "low", "low & in",
            "high"
        ]
        return legacyStrikeLabels.contains(lower)
    }
}
