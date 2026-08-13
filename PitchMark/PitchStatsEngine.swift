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
            walkCount: events.filter { event in
                guard let outcome = event.outcome?.trimmingCharacters(in: .whitespacesAndNewlines), !outcome.isEmpty else { return false }
                return outcome == "BB" || outcome == "Walk"
            }.count,
            hitCount: events.filter(pitchEventCountsAsHit).count,
            wildPitchCount: events.filter { $0.wildPitch }.count,
            passedBallCount: events.filter { $0.passedBall }.count,
            firstPitchStrike: sharedFirstPitchStrikeMetrics(for: events),
            pitchBreakdown: pitchBreakdown,
            outcomeBreakdown: outcomeBreakdown
        )
    }
}
