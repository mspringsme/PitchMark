//
//  Pitch%.swift
//  PitchMark
//
//  Created by Mark Springer on 10/19/25.
//
import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import Combine

enum PitchEventResultType {
    case strike
    case ball
}

private let inPlayStrikeKeywords: [String] = [
    "hit", "ground", "line", "pop", "fly", "bunt",
    "single", "double", "triple", "hr", "home run", "homerun",
    "1b", "2b", "3b", "out", "sac", "fielder's choice", "fielders choice", "fc"
]

private func normalizedEventText(_ event: PitchEvent) -> String {
    [event.outcome, event.descriptor, event.battedBallType, event.battedBallRegion]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
}

func inferredPitchResultType(for event: PitchEvent) -> PitchEventResultType? {
    if event.strikeLooking || event.strikeSwinging || event.isFoulInferred {
        return .strike
    }

    if let isBall = event.isBall, isBall {
        return .ball
    }

    let text = normalizedEventText(event)
    if inPlayStrikeKeywords.contains(where: { text.contains($0) }) {
        return .strike
    }

    if event.isStrike {
        return .strike
    }

    let rawLocation = event.location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if rawLocation.hasPrefix("strike ") {
        return .strike
    }
    if rawLocation.hasPrefix("ball ") {
        return .ball
    }

    if event.isStrike == false {
        return .ball
    }

    return nil
}

func sharedFirstPitchStrikeMetrics(for events: [PitchEvent]) -> (made: Int, total: Int) {
    let ordered = events.sorted { lhs, rhs in
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        return lhs.identity < rhs.identity
    }

    func batterKey(for event: PitchEvent) -> String? {
        if let batterId = event.opponentBatterId?.trimmingCharacters(in: .whitespacesAndNewlines), !batterId.isEmpty {
            return "id:\(batterId)"
        }
        if let jersey = event.opponentJersey?.trimmingCharacters(in: .whitespacesAndNewlines), !jersey.isEmpty {
            return "jersey:\(jersey.lowercased())"
        }
        return nil
    }

    var total = 0
    var made = 0
    var previousBatterKey: String? = nil

    for event in ordered {
        guard let key = batterKey(for: event) else { continue }
        guard key != previousBatterKey else { continue }
        total += 1
        if inferredPitchResultType(for: event) == .strike {
            made += 1
        }
        previousBatterKey = key
    }

    return (made: made, total: total)
}

func pitchEventCountsAsHit(_ event: PitchEvent) -> Bool {
    let normalizedOutcome = (event.outcome ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    let descriptorTokens: Set<String> = Set(
        (event.descriptor ?? "")
            .lowercased()
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    )

    let hitOutcomes: Set<String> = ["1b", "2b", "3b", "hr", "hit"]
    if hitOutcomes.contains(normalizedOutcome) {
        return true
    }

    return descriptorTokens.contains("hit")
}

func isSuccessful(_ event: PitchEvent) -> Bool {
    guard let call = event.calledPitch else { return false }
    return call.isStrike == event.isStrike
}

/// Stricter, side-aware, normalized location matching used across the app
/// - Ensures pitch names match (normalized)
/// - Parses locations (handles "Strike"/"Ball" prefixes), adjusts for batter side, normalizes punctuation/spaces
/// - Enforces type parity when available with sensible fallbacks
func strictIsLocationMatch(_ event: PitchEvent) -> Bool {
    guard let called = event.calledPitch else { return false }

    // Normalize a pitch label (e.g., "FB" vs "Fastball") by trimming and lowercasing
    func normalizedPitch(_ raw: String) -> String {
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    struct ParsedLocation {
        let type: String?   // "strike" or "ball" if present
        let zone: String    // e.g., "middle", "up and out"
    }

    // Parse a location into (type, zone), using same adjustments used for assets/UI
    func parseLocation(_ raw: String, batterSide: BatterSide) -> ParsedLocation {
        let manager = PitchLabelManager(batterSide: batterSide)
        let adjusted = manager.adjustedLabel(from: raw)
        let cleaned = adjusted
            .replacingOccurrences(of: "—", with: " ")
            .replacingOccurrences(of: "–", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if cleaned.hasPrefix("strike ") {
            let zone = String(cleaned.dropFirst("strike ".count)).trimmingCharacters(in: .whitespaces)
            return ParsedLocation(type: "strike", zone: zone)
        } else if cleaned.hasPrefix("ball ") {
            let zone = String(cleaned.dropFirst("ball ".count)).trimmingCharacters(in: .whitespaces)
            return ParsedLocation(type: "ball", zone: zone)
        } else {
            return ParsedLocation(type: nil, zone: cleaned)
        }
    }

    let calledPitchNorm = normalizedPitch(called.pitch)
    let actualPitchNorm = normalizedPitch(event.pitch)
    guard calledPitchNorm == actualPitchNorm else { return false }

    let calledLoc = parseLocation(called.location, batterSide: event.batterSide)
    let actualLoc = parseLocation(event.location, batterSide: event.batterSide)

    // Zones must match exactly after parsing
    guard calledLoc.zone == actualLoc.zone else { return false }

    // Enforce type parity strictly when available
    if let cType = calledLoc.type, let aType = actualLoc.type {
        return cType == aType
    } else if let cType = calledLoc.type {
        // If called has type but actual doesn't, derive from event.isStrike
        let actualType = event.isStrike ? "strike" : "ball"
        return cType == actualType
    } else if let aType = actualLoc.type {
        // If actual has type but called doesn't, derive from calledPitch.isStrike
        let calledType = called.isStrike ? "strike" : "ball"
        return calledType == aType
    } else {
        // Neither provided a type; zones matched
        return true
    }
}

func isLocationMatch(_ event: PitchEvent) -> Bool {
    return strictIsLocationMatch(event)
}

func isFullySuccessful(_ event: PitchEvent) -> Bool {
    return strictIsLocationMatch(event)
}

struct PitchSummary {
    let pitchType: String
    let calledStrikes: Int
    let strikeSuccesses: Int
    let calledBalls: Int
    let ballSuccesses: Int

    var strikeSuccessRate: Int {
        calledStrikes == 0 ? 0 : Int(Double(strikeSuccesses) / Double(calledStrikes) * 100)
    }

    var ballSuccessRate: Int {
        calledBalls == 0 ? 0 : Int(Double(ballSuccesses) / Double(calledBalls) * 100)
    }
}

func summarize(events: [PitchEvent]) -> [PitchSummary] {
    let grouped = Dictionary(grouping: events.compactMap { event -> (String, PitchEvent)? in
        guard let call = event.calledPitch else { return nil }
        return (call.pitch, event)
    }, by: { $0.0 })

    return grouped.mapValues { events in
        let strikeCalls = events.map(\.1).filter { $0.calledPitch?.isStrike == true }
        let ballCalls = events.map(\.1).filter { $0.calledPitch?.isStrike == false }

        let strikeSuccesses = strikeCalls.filter { isSuccessful($0) }.count
        let ballSuccesses = ballCalls.filter { isSuccessful($0) }.count

        return PitchSummary(
            pitchType: events.first?.0 ?? "Unknown",
            calledStrikes: strikeCalls.count,
            strikeSuccesses: strikeSuccesses,
            calledBalls: ballCalls.count,
            ballSuccesses: ballSuccesses
        )
    }
    .values.sorted(by: { $0.pitchType < $1.pitchType })
}
