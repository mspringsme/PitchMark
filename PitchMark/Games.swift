//
//  Games.swift
//  PitchMark
//
//  Created by Mark Springer on 11/1/25.
//
import SwiftUI
import FirebaseFirestore





struct JerseyCell: Identifiable {
    let id: UUID
    var jerseyNumber: String
    init(id: UUID = UUID(), jerseyNumber: String) {
        self.id = id
        self.jerseyNumber = jerseyNumber
    }
}

//hi    

struct JerseyCellView: View {
    let cell: JerseyCell

    var body: some View {
        Text(cell.jerseyNumber)
            .font(.headline)
            .frame(width: 40, height: 40) // Square shape
            .background(Color.clear)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
    }
}

let sampleJerseyCells: [JerseyCell] = [
]

struct Game: Identifiable, Codable {
    // Firestore doc id
    @DocumentID var id: String?

    // Core
    var opponent: String
    var date: Date
    var createdAt: Date = Date()

    // Lineup / participants
    var jerseyNumbers: [String] = []
    var batterIds: [String]? = nil
    var participants: [String: Bool] = [:]

    // Scoreboard
    var balls: Int = 0
    var strikes: Int = 0
    var hits: Int = 0
    var walks: Int = 0
    var inning: Int = 1
    var us: Int = 0
    var them: Int = 0

    // Shared “pending pitch” state (owner sets; joiner reads; joiner can clear)
    var pending: PendingPitch? = nil

    // MARK: - Nested types

    struct PendingPitch: Codable, Equatable {
        var isActive: Bool = false
        var id: String? = nil              // UUID string for correlation
        var label: String? = nil           // whatever you use to highlight UI
        var pitch: String? = nil           // called pitch name
        var location: String? = nil        // called location token/string
        var batterSide: String? = nil      // "L"/"R" or however you store it
        var createdAt: Date? = nil         // optional: when it was initiated
        var createdByUid: String? = nil    // optional: owner uid
        var isStrike: Bool? = nil

    }

    // MARK: - Convenience

    var hasActivePendingPitch: Bool {
        pending?.isActive == true
    }

    // Minimal init (only what you truly need to create a new game)
    init(
        id: String? = nil,
        opponent: String,
        date: Date,
        jerseyNumbers: [String],
        batterIds: [String]? = nil
    ) {
        self.id = id
        self.opponent = opponent
        self.date = date
        self.jerseyNumbers = jerseyNumbers
        self.batterIds = batterIds
    }
}

