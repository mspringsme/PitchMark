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

enum TrackingMode: String, Codable, CaseIterable {
    case coach
    case scout

    var displayName: String {
        switch self {
        case .coach:
            return "Coach Mode"
        case .scout:
            return "Scout Mode"
        }
    }
}

/// Which side's pitcher PitchTrackerView is currently tracking. Local/
/// ephemeral per device - not written to Game, since different viewers of
/// the same game may legitimately be looking at different sides, and it
/// always resets to .home when a game is (re)chosen.
enum GameSide: String, CaseIterable {
    case home
    case away

    /// **Fallback only.** Every side label in the tracker - the pitching
    /// toggle, the header score pills, the Score row's steppers - shows the
    /// actual team name now, via `PitchTrackerView.sideLabel(for:maxLength:)`.
    /// These two strings are what that falls back to when a side has no team
    /// linked yet (a game made before the new-game card asked for both sides,
    /// or one where the coach skipped a side).
    var displayName: String {
        switch self {
        case .home: return "Us"
        case .away: return "Them"
        }
    }
}

struct Game: Identifiable, Codable {
    // Firestore doc id
    @DocumentID var id: String?

    // Core
    var opponent: String
    var date: Date
    var createdAt: Date = Date()
    var archivedAt: Date? = nil
    var teamId: String? = nil
    // Which Team's roster is the opponent for this game, so PitchTrackerView
    // can track the away pitcher's pitches to our batter alongside our own
    // pitcher, switchable mid-game. Optional - most games never set this.
    var awayTeamId: String? = nil
    // TeamPlayer ids from the away roster to actually show in the "Select
    // Batter" scroll (not every hitter-capable player on a large roster is
    // necessarily worth tracking). nil or empty = no restriction, show the
    // whole roster - this is what every game had before the feature existed,
    // and what a game stays at until the coach deliberately narrows it.
    var activeAwayBatterIds: [String]? = nil

    // Lineup / participants
    var jerseyNumbers: [String] = []
    var batterIds: [String]? = nil
    var participants: [String: Bool] = [:]
    var selectedBatterId: String? = nil
    var selectedBatterJersey: String? = nil
    
    // Scoreboard
    var balls: Int = 0
    var strikes: Int = 0
    var hits: Int = 0
    var walks: Int = 0
    var inning: Int = 1
    var us: Int = 0
    var them: Int = 0
    var progressUpdatedAt: Date? = nil

    // Shared “pending pitch” state (owner sets; joiner reads; joiner can clear)
    var pending: PendingPitch? = nil
    var templateName: String? = nil
    var lastTemplateId: String? = nil
    var lastPitcherId: String? = nil
    var trackingMode: TrackingMode? = .coach

    var isArchived: Bool {
        archivedAt != nil
    }

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
        var isStrike: Bool? = nil  // "L" or "R"
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
        batterIds: [String]? = nil,
        trackingMode: TrackingMode? = .coach
    ) {
        self.id = id
        self.opponent = opponent
        self.date = date
        self.jerseyNumbers = jerseyNumbers
        self.batterIds = batterIds
        self.trackingMode = trackingMode
    }
}
