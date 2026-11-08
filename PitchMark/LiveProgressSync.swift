//
//  LiveProgressSync.swift
//  PitchMark
//
//  The rules for when a scoreboard update from the other device (via the
//  live room) or from the saved Game document may replace this device's
//  scoreboard, and what survives a relaunch. Pulled out of PitchTrackerView
//  (2026-10-31) so it can be unit tested; the tracker keeps one of these in
//  TrackerUIState and forwards its old property names into it.
//
//  The history behind each rule is in CLAUDE.md ("Live progress uses
//  progressRevision", "progressRevision is server-assigned only"):
//
//  - Room updates are gated on `progressRevision`, a counter the SERVER
//    mints inside commitLiveProgress's transaction. Never incremented here.
//  - A local change that hasn't reached the room yet is protected by a
//    token pair, for at most `unpublishedGraceWindow` seconds.
//  - Rooms written by old builds carry no revision and fall back to
//    comparing timestamps.
//  - The revision floor belongs to one room: reset on a different room,
//    never restored from the on-device snapshot.
//
//  PitchMark target only.
//

import Foundation
import FirebaseFirestore

/// The scoreboard fields that sync between devices.
struct ScoreboardValues: Equatable, Codable {
    var balls: Int = 0
    var strikes: Int = 0
    var inning: Int = 1
    /// No longer shown (removed 2026-10-31) but still synced for older builds.
    var hits: Int = 0
    var walks: Int = 0
    var us: Int = 0
    var them: Int = 0

    /// A brand-new game's board.
    var isFreshGame: Bool { self == ScoreboardValues() }
}

/// The live room's progress fields: the scoreboard plus outs and runners,
/// which have no column on Game and sync through the room only.
struct LiveProgressFields: Equatable {
    var board = ScoreboardValues()
    var outs: Int = 0
    var bases: BaseOccupancy = .empty

    /// What `commitLiveProgress` publishes.
    var payload: [String: Any] {
        [
            "balls": board.balls,
            "strikes": board.strikes,
            "inning": board.inning,
            "hits": board.hits,
            "walks": board.walks,
            "us": board.us,
            "them": board.them,
            "outs": outs,
            "bases": (try? Firestore.Encoder().encode(bases)) ?? [String: Any]()
        ]
    }

    /// A room snapshot laid over this device's values. Every field the room
    /// carries replaces ours; a field it doesn't carry (an older publisher
    /// with no `bases`, say) keeps ours.
    func applying(roomData data: [String: Any]) -> LiveProgressFields {
        var next = self
        next.board.balls = data["balls"] as? Int ?? board.balls
        next.board.strikes = data["strikes"] as? Int ?? board.strikes
        next.board.inning = data["inning"] as? Int ?? board.inning
        next.board.hits = data["hits"] as? Int ?? board.hits
        next.board.walks = data["walks"] as? Int ?? board.walks
        next.board.us = data["us"] as? Int ?? board.us
        next.board.them = data["them"] as? Int ?? board.them
        next.outs = data["outs"] as? Int ?? outs
        if let raw = data["bases"] as? [String: Any],
           let decoded = try? Firestore.Decoder().decode(BaseOccupancy.self, from: raw) {
            next.bases = decoded
        }
        return next
    }
}

/// The on-device copy of a game's progress, per game id, so a relaunch
/// resumes where it was (UserDefaults, JSON).
struct LocalProgressSnapshot: Codable, Equatable {
    let balls: Int
    let strikes: Int
    let inning: Int
    let hits: Int
    let walks: Int
    let us: Int
    let them: Int
    let updatedAt: TimeInterval
    /// Still written so older builds reading this cache keep working, but
    /// **never restored**: the revision belongs to a single live room, and
    /// carrying a stale floor across relaunches is exactly what made a
    /// device reject the partner's updates.
    let progressRevision: Int?
    /// Outs and runners ride in the live room, so they have to survive a
    /// relaunch too - or a relaunched device republishes 0 / empty bases over
    /// the other device's real state.
    let outs: Int?
    let bases: BaseOccupancy?

    init(fields: LiveProgressFields, updatedAt: TimeInterval, progressRevision: Int) {
        balls = fields.board.balls
        strikes = fields.board.strikes
        inning = fields.board.inning
        hits = fields.board.hits
        walks = fields.board.walks
        us = fields.board.us
        them = fields.board.them
        self.updatedAt = updatedAt
        self.progressRevision = progressRevision
        outs = fields.outs
        bases = fields.bases
    }

    /// What a relaunch puts back. There is deliberately no revision in it.
    /// Outs and runners fall back to `current` for snapshots written before
    /// they were stored.
    func restored(over current: LiveProgressFields) -> (fields: LiveProgressFields, changedAt: Date) {
        let board = ScoreboardValues(balls: balls, strikes: strikes, inning: inning,
                                     hits: hits, walks: walks, us: us, them: them)
        return (LiveProgressFields(board: board, outs: outs ?? current.outs, bases: bases ?? current.bases),
                Date(timeIntervalSince1970: updatedAt))
    }
}

struct LiveProgressSync: Equatable {
    /// How long a local change that hasn't reached the room is protected
    /// from incoming snapshots. Bounded so a publish that never reports back
    /// can't leave this device deaf to its partner.
    static let unpublishedGraceWindow: TimeInterval = 5

    /// Highest `progressRevision` the server has handed this device for
    /// `roomId`. Server-assigned only.
    var revision: Int = 0
    /// The room `revision` belongs to.
    var roomId: String? = nil
    /// Bumped by every local progress change; `publishedToken` trails it
    /// until the publish covering it reports back.
    var localChangeToken: Int = 0
    var publishedToken: Int = 0
    var lastUnpublishedChangeAt: Date? = nil
    /// When this device last changed (or adopted) the scoreboard.
    var lastLocalChangeAt: Date? = nil

    // MARK: Local changes and publishing

    /// Any scoreboard change on this device. Several in one run-loop turn
    /// still go out as one publish (the tracker coalesces them); the token
    /// that publish captures covers all of them.
    mutating func noteLocalChange(now: Date) {
        lastLocalChangeAt = now
        localChangeToken += 1
        lastUnpublishedChangeAt = now
    }

    /// True while a local change hasn't reached the room - within the grace
    /// window only.
    func hasUnpublishedLocalChange(now: Date) -> Bool {
        guard publishedToken < localChangeToken, let changedAt = lastUnpublishedChangeAt else { return false }
        return now.timeIntervalSince(changedAt) < Self.unpublishedGraceWindow
    }

    /// The token a publish starting now covers.
    var tokenForPublish: Int { localChangeToken }

    /// A publish reported back. Whatever it carried is no longer
    /// unpublished. On success the server's revision raises the floor - but
    /// only for the room it was published to. A failure leaves the floor, so
    /// the room's own state (newer than our failed write) applies next.
    mutating func publishFinished(token: Int, serverRevision: Int?, publishedRoomId: String) {
        publishedToken = max(publishedToken, token)
        guard let serverRevision, roomId == publishedRoomId else { return }
        revision = max(revision, serverRevision)
    }

    /// No room to publish to: nothing is pending.
    mutating func publishSkippedNoRoom(token: Int) {
        publishedToken = max(publishedToken, token)
    }

    // MARK: Rooms

    /// Started listening to a room. A different room starts from 0 - a
    /// fresh room's first commit lands at 1, whatever the old room reached.
    mutating func enterRoom(_ id: String) {
        guard roomId != id else { return }
        revision = 0
        roomId = id
    }

    /// The live session ended.
    mutating func leaveRoom() {
        revision = 0
        roomId = nil
    }

    // MARK: Incoming updates

    /// Should a room snapshot be applied? Accepting one also raises the
    /// revision floor to it.
    mutating func acceptRoomSnapshot(remoteRevision: Int?, remoteStamp: Date?, now: Date) -> Bool {
        if hasUnpublishedLocalChange(now: now) {
            return false
        }
        if let remoteRevision {
            guard remoteRevision > revision else { return false }
            revision = remoteRevision
            return true
        }
        // A room written by an older build: no revision, compare times.
        return Self.snapshotIsNewer(remoteStamp, than: lastLocalChangeAt)
    }

    /// Timestamp rule, for old-build rooms and the saved Game document: apply
    /// when this device has changed nothing, or the snapshot is at least as
    /// new as our last change. A snapshot with no time can't prove it's newer.
    static func snapshotIsNewer(_ snapshotStamp: Date?, than localStamp: Date?) -> Bool {
        guard let localStamp else { return true }
        guard let snapshotStamp else { return false }
        return snapshotStamp >= localStamp
    }

    // MARK: Reloading the saved Game document

    /// A reload of the game list merged with this device's board. Returns
    /// what the game's entry should hold and this device's change time
    /// afterwards. When this device changed the board more recently than the
    /// document (or the document has no time), the entry keeps our values;
    /// otherwise the document's stand.
    static func mergeReloadedGame(
        game: ScoreboardValues,
        gameStamp: Date?,
        local: ScoreboardValues,
        localStamp: Date?,
        now: Date
    ) -> (game: ScoreboardValues, gameStamp: Date?, localStamp: Date?) {
        var stamp = localStamp
        if stamp == nil {
            // First look at this game: adopt its time; a board that already
            // shows play but carries no time is treated as changed now, which
            // makes this device's copy (loaded from it) the one that stands.
            if let gameStamp {
                stamp = gameStamp
            } else if !game.isFreshGame {
                stamp = now
            }
        }
        guard let stamp else { return (game, gameStamp, nil) }
        if gameStamp == nil || gameStamp! < stamp {
            return (local, stamp, stamp)
        }
        return (game, gameStamp, stamp)
    }
}
