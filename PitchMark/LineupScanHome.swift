//
//  LineupScanHome.swift
//  PitchMark
//
//  What Home needs to run Scan Opponent Lineup from its three places:
//  the new-game card, an own game's ⋯ menu, and a joined live game's ⋯
//  menu. The flow itself lives in SettingsView (Home); this is its state.
//

import Foundation

struct LineupScanContext {
    enum Kind {
        /// The new-game card: the reviewed lineup waits for Save.
        case newGame
        /// One of this user's games.
        case game(Game)
        /// A live game joined as a partner.
        case joined(JoinedLiveSession)
    }

    var kind: Kind
    var teamId: String
    var teamName: String
    var alreadyInLineup: Set<String> = []

    var confirmTitle: String {
        if case .newGame = kind { return "Use for New Game" }
        return "Add to Game"
    }

    /// Hitter ids already batting in a game, read off its own cells (the
    /// link map keeps keys for removed cells).
    static func lineupHitters(of game: Game) -> Set<String> {
        let links = game.hitterIdByBatterId ?? [:]
        return Set((game.batterIds ?? []).compactMap { links[$0] })
    }
}

/// A reviewed lineup held by the new-game card until Save.
struct PendingNewGameLineup {
    var teamId: String
    var decisions: [LineupScanDecision]
    var roster: [TeamPlayer]

    var summary: String {
        "\(decisions.count) batter\(decisions.count == 1 ? "" : "s") ready - added when you Save"
    }
}

/// Leaving a live game from Home's ⋯ menus (2026-11-07): a partner
/// disconnects from a joined game; the coach ends the room of the game
/// that's in use. Both confirm first.
enum HomeLiveLeave: Equatable {
    case disconnect(JoinedLiveSession)
    case endSession(liveId: String, title: String)

    var title: String {
        switch self {
        case .disconnect: return "Disconnect?"
        case .endSession: return "End Live Session?"
        }
    }

    var message: String {
        switch self {
        case .disconnect(let session):
            return "You'll leave \"\(session.opponent)\" and it comes off your games. To join again you'll need a new code from the coach."
        case .endSession(_, let title):
            return "Everyone connected to \"\(title)\" is disconnected. The game and its pitches stay."
        }
    }

    var confirmTitle: String {
        switch self {
        case .disconnect: return "Disconnect"
        case .endSession: return "End Live Session"
        }
    }
}
