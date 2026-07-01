import Foundation

struct PitchStatsSnapshot {
    let totalPitches: Int
    let strikePitches: Int
    let ballPitches: Int
    let hitSpotPitches: Int
    let locationAnalyticsEligibleCount: Int
    let strikeLookingCount: Int
    let strikeSwingingCount: Int
    let walkCount: Int
    let hitCount: Int
    let wildPitchCount: Int
    let passedBallCount: Int
    let firstPitchStrike: (made: Int, total: Int)
    let pitchBreakdown: [(name: String, count: Int)]
    let outcomeBreakdown: [(name: String, count: Int)]

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

#if DEBUG
struct PitchStatsSimulationCase {
    let name: String
    let events: [PitchEvent]
    let expected: PitchStatsSnapshot
}

struct PitchStatsSimulationDifference {
    let field: String
    let expected: String
    let actual: String
}

struct PitchStatsSimulationResult {
    let name: String
    let differences: [PitchStatsSimulationDifference]

    var passed: Bool {
        differences.isEmpty
    }
}

struct PitchStatsSimulationReport {
    let results: [PitchStatsSimulationResult]

    var passedCount: Int { results.filter(\.passed).count }
    var failedCount: Int { results.count - passedCount }

    var summary: String {
        let lines = results.map { result -> String in
            if result.passed { return "PASS \(result.name)" }
            let diffText = result.differences
                .map { "\($0.field): expected \($0.expected) got \($0.actual)" }
                .joined(separator: " | ")
            return "FAIL \(result.name) -> \(diffText)"
        }
        return lines.joined(separator: "\n")
    }
}

enum PitchStatsSimulationLibrary {
    @MainActor
    static func runCoverageSuite() -> PitchStatsSimulationReport {
        PitchStatsSimulationReport(results: coverageCases().map(compare))
    }

    static func coverageCases() -> [PitchStatsSimulationCase] {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

        let coachEvents: [PitchEvent] = [
            makeEvent(
                timestamp: baseDate,
                pitch: "Fastball",
                location: "Strike Up and In",
                isStrike: true,
                isBall: false,
                calledPitch: PitchCall(pitch: "Fastball", location: "Strike Up and In", isStrike: true, codes: []),
                strikeLooking: true,
                batterSide: .right,
                trackingMode: .coach,
                opponentJersey: "10",
                opponentBatterId: "101"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(1),
                pitch: "Slider",
                location: "Strike Down and Away",
                isStrike: true,
                isBall: false,
                calledPitch: PitchCall(pitch: "Slider", location: "Strike Down and Away", isStrike: true, codes: []),
                strikeSwinging: true,
                batterSide: .left,
                trackingMode: .coach,
                opponentJersey: "10",
                opponentBatterId: "101"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(2),
                pitch: "Changeup",
                location: "Ball Low and Away",
                isStrike: false,
                isBall: true,
                calledPitch: PitchCall(pitch: "Changeup", location: "Ball Low and Away", isStrike: false, codes: []),
                batterSide: .right,
                trackingMode: .coach,
                opponentJersey: "11",
                opponentBatterId: "102",
                ballMarker: "Low"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(3),
                pitch: "Curveball",
                location: "Strike Middle",
                isStrike: true,
                isBall: false,
                calledPitch: PitchCall(pitch: "Curveball", location: "Strike Middle", isStrike: true, codes: []),
                outcome: "Foul",
                batterSide: .left,
                trackingMode: .coach,
                opponentJersey: "11",
                opponentBatterId: "102",
                foulMarker: "Top"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(4),
                pitch: "Splitter",
                location: "Strike Middle",
                isStrike: true,
                isBall: false,
                calledPitch: PitchCall(pitch: "Splitter", location: "Strike Middle", isStrike: true, codes: []),
                outcome: "1B",
                descriptor: "Hit, line drive",
                batterSide: .right,
                trackingMode: .coach,
                opponentJersey: "12",
                opponentBatterId: "103"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(5),
                pitch: "Cutter",
                location: "Ball Away",
                isStrike: false,
                isBall: true,
                calledPitch: PitchCall(pitch: "Cutter", location: "Ball Away", isStrike: false, codes: []),
                outcome: "BB",
                batterSide: .right,
                trackingMode: .coach,
                opponentJersey: "12",
                opponentBatterId: "103"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(6),
                pitch: "Sinker",
                location: "Ball Low",
                isStrike: false,
                isBall: true,
                calledPitch: PitchCall(pitch: "Sinker", location: "Ball Low", isStrike: false, codes: []),
                wildPitch: true,
                batterSide: .left,
                trackingMode: .coach,
                opponentJersey: "12",
                opponentBatterId: "103"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(7),
                pitch: "Knuckleball",
                location: "Ball High",
                isStrike: false,
                isBall: true,
                calledPitch: PitchCall(pitch: "Knuckleball", location: "Ball High", isStrike: false, codes: []),
                passedBall: true,
                batterSide: .right,
                trackingMode: .coach,
                opponentJersey: "12",
                opponentBatterId: "103"
            )
        ]

        let scoutEvents: [PitchEvent] = [
            makeEvent(
                timestamp: baseDate.addingTimeInterval(20),
                pitch: "Fastball",
                location: "Strike Up and In",
                isStrike: true,
                isBall: false,
                calledPitch: PitchCall(pitch: "Fastball", location: "Strike Up and In", isStrike: true, codes: []),
                strikeLooking: true,
                batterSide: .right,
                trackingMode: .scout,
                opponentJersey: "20",
                opponentBatterId: "201"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(21),
                pitch: "Slider",
                location: "Ball Away",
                isStrike: false,
                isBall: true,
                calledPitch: PitchCall(pitch: "Slider", location: "Ball Away", isStrike: false, codes: []),
                batterSide: .left,
                trackingMode: .scout,
                opponentJersey: "21",
                opponentBatterId: "202"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(22),
                pitch: "Curveball",
                location: "Ball Down",
                isStrike: false,
                isBall: true,
                calledPitch: PitchCall(pitch: "Curveball", location: "Ball Down", isStrike: false, codes: []),
                outcome: "Walk",
                batterSide: .right,
                trackingMode: .scout,
                opponentJersey: "22",
                opponentBatterId: "203"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(23),
                pitch: "Changeup",
                location: "Strike Down and Away",
                isStrike: true,
                isBall: false,
                calledPitch: PitchCall(pitch: "Changeup", location: "Strike Down and Away", isStrike: true, codes: []),
                outcome: "HR",
                descriptor: "Home run",
                batterSide: .left,
                trackingMode: .scout,
                opponentJersey: "23",
                opponentBatterId: "204"
            )
        ]

        let firstPitchEvents: [PitchEvent] = [
            makeEvent(
                timestamp: baseDate.addingTimeInterval(40),
                pitch: "Fastball",
                location: "Strike Middle",
                isStrike: true,
                isBall: false,
                calledPitch: PitchCall(pitch: "Fastball", location: "Strike Middle", isStrike: true, codes: []),
                batterSide: .right,
                trackingMode: .coach,
                opponentJersey: "30",
                opponentBatterId: "301"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(41),
                pitch: "Fastball",
                location: "Ball Away",
                isStrike: false,
                isBall: true,
                calledPitch: PitchCall(pitch: "Fastball", location: "Ball Away", isStrike: false, codes: []),
                batterSide: .right,
                trackingMode: .coach,
                opponentJersey: "30",
                opponentBatterId: "301"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(42),
                pitch: "Slider",
                location: "Ball Away",
                isStrike: false,
                isBall: true,
                calledPitch: PitchCall(pitch: "Slider", location: "Ball Away", isStrike: false, codes: []),
                batterSide: .left,
                trackingMode: .coach,
                opponentJersey: "31",
                opponentBatterId: "302"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(43),
                pitch: "Curveball",
                location: "Strike Down",
                isStrike: true,
                isBall: false,
                calledPitch: PitchCall(pitch: "Curveball", location: "Strike Down", isStrike: true, codes: []),
                batterSide: .left,
                trackingMode: .coach,
                opponentJersey: "32",
                opponentBatterId: "303"
            )
        ]

        let terminalCountEvents: [PitchEvent] = [
            makeEvent(
                timestamp: baseDate.addingTimeInterval(60),
                pitch: "Fastball",
                location: "Ball Away",
                isStrike: false,
                isBall: true,
                calledPitch: PitchCall(pitch: "Fastball", location: "Ball Away", isStrike: false, codes: []),
                outcome: "Walk",
                batterSide: .right,
                trackingMode: .coach,
                opponentJersey: "40",
                opponentBatterId: "401",
                atBatBalls: 3,
                atBatStrikes: 1,
                atBatCount: "3-1"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(61),
                pitch: "Slider",
                location: "Strike Middle",
                isStrike: true,
                isBall: false,
                calledPitch: PitchCall(pitch: "Slider", location: "Strike Middle", isStrike: true, codes: []),
                batterSide: .left,
                trackingMode: .coach,
                opponentJersey: "41",
                opponentBatterId: "402",
                atBatBalls: 0,
                atBatStrikes: 2,
                atBatCount: "0-2"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(62),
                pitch: "Splitter",
                location: "Strike Down",
                isStrike: true,
                isBall: false,
                calledPitch: PitchCall(pitch: "Splitter", location: "Strike Down", isStrike: true, codes: []),
                outcome: "K",
                batterSide: .right,
                trackingMode: .coach,
                opponentJersey: "42",
                opponentBatterId: "403"
            )
        ]

        let foulInferenceEvents: [PitchEvent] = [
            makeEvent(
                timestamp: baseDate.addingTimeInterval(80),
                pitch: "Curveball",
                location: "Ball Away",
                isStrike: false,
                isBall: false,
                calledPitch: PitchCall(pitch: "Curveball", location: "Ball Away", isStrike: false, codes: []),
                outcome: "Foul Tip",
                batterSide: .right,
                trackingMode: .coach,
                opponentJersey: "50",
                opponentBatterId: "501"
            )
        ]

        let outcomeNormalizationEvents: [PitchEvent] = [
            makeEvent(
                timestamp: baseDate.addingTimeInterval(90),
                pitch: "Fastball",
                location: "Strike Middle",
                isStrike: true,
                isBall: false,
                calledPitch: PitchCall(pitch: "Fastball", location: "Strike Middle", isStrike: true, codes: []),
                batterSide: .right,
                trackingMode: .coach,
                opponentJersey: "60",
                opponentBatterId: "601"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(91),
                pitch: "Slider",
                location: "Ball Away",
                isStrike: false,
                isBall: true,
                calledPitch: PitchCall(pitch: "Slider", location: "Ball Away", isStrike: false, codes: []),
                outcome: "   ",
                batterSide: .left,
                trackingMode: .coach,
                opponentJersey: "61",
                opponentBatterId: "602"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(92),
                pitch: "Changeup",
                location: "Ball Down",
                isStrike: false,
                isBall: true,
                calledPitch: PitchCall(pitch: "Changeup", location: "Ball Down", isStrike: false, codes: []),
                outcome: "",
                descriptor: "Hit, line drive",
                batterSide: .right,
                trackingMode: .coach,
                opponentJersey: "62",
                opponentBatterId: "603"
            )
        ]

        let batterFallbackEvents: [PitchEvent] = [
            makeEvent(
                timestamp: baseDate.addingTimeInterval(100),
                pitch: "Fastball",
                location: "Strike Up",
                isStrike: true,
                isBall: false,
                calledPitch: PitchCall(pitch: "Fastball", location: "Strike Up", isStrike: true, codes: []),
                batterSide: .right,
                trackingMode: .coach,
                opponentJersey: "70",
                opponentBatterId: ""
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(101),
                pitch: "Slider",
                location: "Ball Away",
                isStrike: false,
                isBall: true,
                calledPitch: PitchCall(pitch: "Slider", location: "Ball Away", isStrike: false, codes: []),
                batterSide: .left,
                trackingMode: .coach,
                opponentJersey: "70",
                opponentBatterId: ""
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(102),
                pitch: "Curveball",
                location: "Strike Middle",
                isStrike: true,
                isBall: false,
                calledPitch: PitchCall(pitch: "Curveball", location: "Strike Middle", isStrike: true, codes: []),
                batterSide: .right,
                trackingMode: .coach,
                opponentJersey: "71",
                opponentBatterId: ""
            )
        ]

        let locationAnalyticsEvents: [PitchEvent] = [
            makeEvent(
                timestamp: baseDate.addingTimeInterval(110),
                pitch: "Fastball",
                location: "Strike Middle",
                isStrike: true,
                isBall: false,
                calledPitch: PitchCall(pitch: "Fastball", location: "Strike Middle", isStrike: true, codes: []),
                batterSide: .right,
                trackingMode: .coach,
                opponentJersey: "80",
                opponentBatterId: "801"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(111),
                pitch: "Slider",
                location: "Strike Middle",
                isStrike: true,
                isBall: false,
                calledPitch: PitchCall(pitch: "Slider", location: "Strike Middle", isStrike: true, codes: []),
                batterSide: .left,
                trackingMode: .scout,
                opponentJersey: "81",
                opponentBatterId: "802"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(112),
                pitch: "Curveball",
                location: "Strike Middle",
                isStrike: true,
                isBall: false,
                calledPitch: nil,
                batterSide: .right,
                trackingMode: .coach,
                opponentJersey: "82",
                opponentBatterId: "803"
            ),
            makeEvent(
                timestamp: baseDate.addingTimeInterval(113),
                pitch: "Changeup",
                location: "   ",
                isStrike: false,
                isBall: true,
                calledPitch: PitchCall(pitch: "Changeup", location: "Strike Middle", isStrike: true, codes: []),
                batterSide: .right,
                trackingMode: .coach,
                opponentJersey: "83",
                opponentBatterId: "804"
            )
        ]

        return [
            PitchStatsSimulationCase(
                name: "coach-basics",
                events: coachEvents,
                expected: PitchStatsSnapshot(
                    totalPitches: 8,
                    strikePitches: 4,
                    ballPitches: 4,
                    hitSpotPitches: 8,
                    locationAnalyticsEligibleCount: 8,
                    strikeLookingCount: 1,
                    strikeSwingingCount: 1,
                    walkCount: 1,
                    hitCount: 1,
                    wildPitchCount: 1,
                    passedBallCount: 1,
                    firstPitchStrike: (made: 2, total: 3),
                    pitchBreakdown: [
                        (name: "Changeup", count: 1),
                        (name: "Cutter", count: 1),
                        (name: "Curveball", count: 1),
                        (name: "Fastball", count: 1),
                        (name: "Knuckleball", count: 1),
                        (name: "Slider", count: 1),
                        (name: "Sinker", count: 1),
                        (name: "Splitter", count: 1)
                    ],
                    outcomeBreakdown: [
                        (name: "1B", count: 1),
                        (name: "BB", count: 1),
                        (name: "Foul", count: 1),
                        (name: "No outcome", count: 5)
                    ]
                )
            ),
            PitchStatsSimulationCase(
                name: "scout-visibility",
                events: scoutEvents,
                expected: PitchStatsSnapshot(
                    totalPitches: 4,
                    strikePitches: 2,
                    ballPitches: 2,
                    hitSpotPitches: 0,
                    locationAnalyticsEligibleCount: 0,
                    strikeLookingCount: 1,
                    strikeSwingingCount: 0,
                    walkCount: 1,
                    hitCount: 1,
                    wildPitchCount: 0,
                    passedBallCount: 0,
                    firstPitchStrike: (made: 2, total: 4),
                    pitchBreakdown: [
                        (name: "Changeup", count: 1),
                        (name: "Curveball", count: 1),
                        (name: "Fastball", count: 1),
                        (name: "Slider", count: 1)
                    ],
                    outcomeBreakdown: [
                        (name: "HR", count: 1),
                        (name: "No outcome", count: 2),
                        (name: "Walk", count: 1)
                    ]
                )
            ),
            PitchStatsSimulationCase(
                name: "first-pitch-strike",
                events: firstPitchEvents,
                expected: PitchStatsSnapshot(
                    totalPitches: 4,
                    strikePitches: 2,
                    ballPitches: 2,
                    hitSpotPitches: 4,
                    locationAnalyticsEligibleCount: 4,
                    strikeLookingCount: 0,
                    strikeSwingingCount: 0,
                    walkCount: 0,
                    hitCount: 0,
                    wildPitchCount: 0,
                    passedBallCount: 0,
                    firstPitchStrike: (made: 2, total: 3),
                    pitchBreakdown: [
                        (name: "Curveball", count: 1),
                        (name: "Fastball", count: 2),
                        (name: "Slider", count: 1)
                    ],
                    outcomeBreakdown: [
                        (name: "No outcome", count: 4)
                    ]
                )
            ),
            PitchStatsSimulationCase(
                name: "terminal-counts",
                events: terminalCountEvents,
                expected: PitchStatsSnapshot(
                    totalPitches: 3,
                    strikePitches: 2,
                    ballPitches: 1,
                    hitSpotPitches: 3,
                    locationAnalyticsEligibleCount: 3,
                    strikeLookingCount: 0,
                    strikeSwingingCount: 0,
                    walkCount: 1,
                    hitCount: 0,
                    wildPitchCount: 0,
                    passedBallCount: 0,
                    firstPitchStrike: (made: 2, total: 3),
                    pitchBreakdown: [
                        (name: "Fastball", count: 1),
                        (name: "Slider", count: 1),
                        (name: "Splitter", count: 1)
                    ],
                    outcomeBreakdown: [
                        (name: "K", count: 1),
                        (name: "Walk", count: 1),
                        (name: "No outcome", count: 1)
                    ]
                )
            ),
            PitchStatsSimulationCase(
                name: "foul-inference",
                events: foulInferenceEvents,
                expected: PitchStatsSnapshot(
                    totalPitches: 1,
                    strikePitches: 1,
                    ballPitches: 0,
                    hitSpotPitches: 1,
                    locationAnalyticsEligibleCount: 1,
                    strikeLookingCount: 0,
                    strikeSwingingCount: 0,
                    walkCount: 0,
                    hitCount: 0,
                    wildPitchCount: 0,
                    passedBallCount: 0,
                    firstPitchStrike: (made: 1, total: 1),
                    pitchBreakdown: [
                        (name: "Curveball", count: 1)
                    ],
                    outcomeBreakdown: [
                        (name: "Foul Tip", count: 1)
                    ]
                )
            ),
            PitchStatsSimulationCase(
                name: "outcome-normalization",
                events: outcomeNormalizationEvents,
                expected: PitchStatsSnapshot(
                    totalPitches: 3,
                    strikePitches: 1,
                    ballPitches: 2,
                    hitSpotPitches: 3,
                    locationAnalyticsEligibleCount: 3,
                    strikeLookingCount: 0,
                    strikeSwingingCount: 0,
                    walkCount: 0,
                    hitCount: 1,
                    wildPitchCount: 0,
                    passedBallCount: 0,
                    firstPitchStrike: (made: 1, total: 3),
                    pitchBreakdown: [
                        (name: "Changeup", count: 1),
                        (name: "Fastball", count: 1),
                        (name: "Slider", count: 1)
                    ],
                    outcomeBreakdown: [
                        (name: "No outcome", count: 3)
                    ]
                )
            ),
            PitchStatsSimulationCase(
                name: "batter-key-fallback",
                events: batterFallbackEvents,
                expected: PitchStatsSnapshot(
                    totalPitches: 3,
                    strikePitches: 2,
                    ballPitches: 1,
                    hitSpotPitches: 3,
                    locationAnalyticsEligibleCount: 3,
                    strikeLookingCount: 0,
                    strikeSwingingCount: 0,
                    walkCount: 0,
                    hitCount: 0,
                    wildPitchCount: 0,
                    passedBallCount: 0,
                    firstPitchStrike: (made: 2, total: 2),
                    pitchBreakdown: [
                        (name: "Curveball", count: 1),
                        (name: "Fastball", count: 1),
                        (name: "Slider", count: 1)
                    ],
                    outcomeBreakdown: [
                        (name: "No outcome", count: 3)
                    ]
                )
            ),
            PitchStatsSimulationCase(
                name: "batter-id-precedence",
                events: [
                    makeEvent(
                        timestamp: baseDate.addingTimeInterval(120),
                        pitch: "Fastball",
                        location: "Strike Up",
                        isStrike: true,
                        isBall: false,
                        calledPitch: PitchCall(pitch: "Fastball", location: "Strike Up", isStrike: true, codes: []),
                        batterSide: .right,
                        trackingMode: .coach,
                        opponentJersey: "90",
                        opponentBatterId: "901"
                    ),
                    makeEvent(
                        timestamp: baseDate.addingTimeInterval(121),
                        pitch: "Slider",
                        location: "Ball Away",
                        isStrike: false,
                        isBall: true,
                        calledPitch: PitchCall(pitch: "Slider", location: "Ball Away", isStrike: false, codes: []),
                        batterSide: .left,
                        trackingMode: .coach,
                        opponentJersey: "90",
                        opponentBatterId: "901"
                    ),
                    makeEvent(
                        timestamp: baseDate.addingTimeInterval(122),
                        pitch: "Curveball",
                        location: "Strike Middle",
                        isStrike: true,
                        isBall: false,
                        calledPitch: PitchCall(pitch: "Curveball", location: "Strike Middle", isStrike: true, codes: []),
                        batterSide: .right,
                        trackingMode: .coach,
                        opponentJersey: "90",
                        opponentBatterId: "902"
                    )
                ],
                expected: PitchStatsSnapshot(
                    totalPitches: 3,
                    strikePitches: 2,
                    ballPitches: 1,
                    hitSpotPitches: 3,
                    locationAnalyticsEligibleCount: 3,
                    strikeLookingCount: 0,
                    strikeSwingingCount: 0,
                    walkCount: 0,
                    hitCount: 0,
                    wildPitchCount: 0,
                    passedBallCount: 0,
                    firstPitchStrike: (made: 2, total: 2),
                    pitchBreakdown: [
                        (name: "Curveball", count: 1),
                        (name: "Fastball", count: 1),
                        (name: "Slider", count: 1)
                    ],
                    outcomeBreakdown: [
                        (name: "No outcome", count: 3)
                    ]
                )
            ),
            PitchStatsSimulationCase(
                name: "location-analytics-guardrails",
                events: locationAnalyticsEvents,
                expected: PitchStatsSnapshot(
                    totalPitches: 4,
                    strikePitches: 3,
                    ballPitches: 1,
                    hitSpotPitches: 1,
                    locationAnalyticsEligibleCount: 1,
                    strikeLookingCount: 0,
                    strikeSwingingCount: 0,
                    walkCount: 0,
                    hitCount: 0,
                    wildPitchCount: 0,
                    passedBallCount: 0,
                    firstPitchStrike: (made: 3, total: 4),
                    pitchBreakdown: [
                        (name: "Changeup", count: 1),
                        (name: "Curveball", count: 1),
                        (name: "Fastball", count: 1),
                        (name: "Slider", count: 1)
                    ],
                    outcomeBreakdown: [
                        (name: "No outcome", count: 4)
                    ]
                )
            )
        ]
    }

    @MainActor
    static func compare(_ testCase: PitchStatsSimulationCase) -> PitchStatsSimulationResult {
        let actual = PitchStatsCalculator.snapshot(for: testCase.events)
        let expected = testCase.expected
        var differences: [PitchStatsSimulationDifference] = []

        func appendIfDifferent(_ field: String, _ expectedValue: String, _ actualValue: String) {
            guard expectedValue == actualValue else {
                differences.append(.init(field: field, expected: expectedValue, actual: actualValue))
                return
            }
        }

        appendIfDifferent("totalPitches", "\(expected.totalPitches)", "\(actual.totalPitches)")
        appendIfDifferent("strikePitches", "\(expected.strikePitches)", "\(actual.strikePitches)")
        appendIfDifferent("ballPitches", "\(expected.ballPitches)", "\(actual.ballPitches)")
        appendIfDifferent("hitSpotPitches", "\(expected.hitSpotPitches)", "\(actual.hitSpotPitches)")
        appendIfDifferent("locationAnalyticsEligibleCount", "\(expected.locationAnalyticsEligibleCount)", "\(actual.locationAnalyticsEligibleCount)")
        appendIfDifferent("strikeLookingCount", "\(expected.strikeLookingCount)", "\(actual.strikeLookingCount)")
        appendIfDifferent("strikeSwingingCount", "\(expected.strikeSwingingCount)", "\(actual.strikeSwingingCount)")
        appendIfDifferent("walkCount", "\(expected.walkCount)", "\(actual.walkCount)")
        appendIfDifferent("hitCount", "\(expected.hitCount)", "\(actual.hitCount)")
        appendIfDifferent("wildPitchCount", "\(expected.wildPitchCount)", "\(actual.wildPitchCount)")
        appendIfDifferent("passedBallCount", "\(expected.passedBallCount)", "\(actual.passedBallCount)")
        appendIfDifferent("firstPitchStrike", "\(expected.firstPitchStrike.made)/\(expected.firstPitchStrike.total)", "\(actual.firstPitchStrike.made)/\(actual.firstPitchStrike.total)")
        appendIfDifferent("pitchBreakdown", normalizedBreakdownString(expected.pitchBreakdown), normalizedBreakdownString(actual.pitchBreakdown))
        appendIfDifferent("outcomeBreakdown", normalizedBreakdownString(expected.outcomeBreakdown), normalizedBreakdownString(actual.outcomeBreakdown))

        return PitchStatsSimulationResult(name: testCase.name, differences: differences)
    }

    private static func normalizedBreakdownString(_ items: [(name: String, count: Int)]) -> String {
        items
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.name < rhs.name }
                return lhs.count > rhs.count
            }
            .map { "\($0.name)=\($0.count)" }
            .joined(separator: ",")
    }

    private static func makeEvent(
        timestamp: Date,
        pitch: String,
        location: String,
        isStrike: Bool,
        isBall: Bool?,
        calledPitch: PitchCall?,
        strikeSwinging: Bool = false,
        wildPitch: Bool = false,
        passedBall: Bool = false,
        strikeLooking: Bool = false,
        outcome: String? = nil,
        descriptor: String? = nil,
        errorOnPlay: Bool = false,
        batterSide: BatterSide,
        trackingMode: TrackingMode,
        opponentJersey: String,
        opponentBatterId: String,
        templateId: String? = nil,
        gameId: String? = nil,
        pitcherId: String? = nil,
        createdByUid: String? = nil,
        strikeSwingingMarker: String? = nil,
        strikeLookingMarker: String? = nil,
        ballMarker: String? = nil,
        foulMarker: String? = nil,
        atBatBalls: Int? = nil,
        atBatStrikes: Int? = nil,
        atBatCount: String? = nil
    ) -> PitchEvent {
        PitchEvent(
            id: nil,
            timestamp: timestamp,
            pitch: pitch,
            location: location,
            codes: [],
            isStrike: isStrike,
            isBall: isBall,
            mode: .game,
            calledPitch: calledPitch,
            batterSide: batterSide,
            templateId: templateId,
            strikeSwinging: strikeSwinging,
            wildPitch: wildPitch,
            passedBall: passedBall,
            strikeLooking: strikeLooking,
            outcome: outcome,
            descriptor: descriptor,
            errorOnPlay: errorOnPlay,
            battedBallRegion: nil,
            battedBallType: nil,
            battedBallTapX: nil,
            battedBallTapY: nil,
            gameId: gameId,
            opponentJersey: opponentJersey,
            opponentBatterId: opponentBatterId,
            pitcherId: pitcherId,
            createdByUid: createdByUid,
            strikeSwingingMarker: strikeSwingingMarker,
            strikeLookingMarker: strikeLookingMarker,
            ballMarker: ballMarker,
            foulMarker: foulMarker,
            atBatBalls: atBatBalls,
            atBatStrikes: atBatStrikes,
            atBatCount: atBatCount,
            trackingMode: trackingMode
        )
    }
}
#endif
