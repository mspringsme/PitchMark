//
//  CalledPitchRecord.swift
//  PitchMark
//
//  Created by Mark Springer on 10/9/25.
//


import Foundation

struct CalledPitchRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let pitch: String           // e.g. "2 Seam"
    let calledLocation: String  // e.g. "Ball ↓"
    let actualLocation: String? // e.g. "Strike Middle" (set when user records result)
    let isCalledStrike: Bool
    let isActualStrike: Bool?   // set when actualLocation is recorded
    let assignedCodes: [String] // optional metadata
    let batterSideRaw: String?  // "L" / "R" if helpful
    let notes: String?
    let mode: String
}
