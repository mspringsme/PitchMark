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
    guard let call = event.calledPitch else { return false }
    return call.location == event.location && call.isStrike == event.isStrike
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

