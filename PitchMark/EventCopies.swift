//
//  EventCopies.swift
//  PitchMark
//
//  A pitch lives in up to four places: the live room
//  (liveGames/{id}/pitchEvents), the owner's game
//  (users/{owner}/games/{gid}/pitchEvents), the pitcher's career record
//  (pitchers/{pid}/pitchEvents) and the hitter's record
//  (hitters/{hid}/pitchEvents). This file decides which copies a change
//  touches and what each one holds; the callers only send the writes.
//
//  Pulled out of PitchTrackerView and CalledPitchRecord (2026-10-31) so it
//  can be unit tested. The history behind each rule is in CLAUDE.md ("Never
//  put an event's copies in one WriteBatch", "The owner's device is the only
//  bridge to the permanent record").
//
//  No Firestore import: paths are strings, so this compiles into the
//  Display target too (CalledPitchRecord is shared).
//

import Foundation

/// One request against one stored copy of an event.
enum EventCopyWrite {
    /// Replaces the document (setData, merge: false).
    case set(path: String, data: [String: Any])
    /// Merges fields into an existing document (updateData).
    case update(path: String, data: [String: Any])
    case delete(path: String)

    var path: String {
        switch self {
        case .set(let path, _), .update(let path, _), .delete(let path): return path
        }
    }

    var data: [String: Any]? {
        switch self {
        case .set(_, let data), .update(_, let data): return data
        case .delete: return nil
        }
    }

    var isDelete: Bool {
        if case .delete = self { return true }
        return false
    }
}

enum EventCopyPaths {
    static func liveRoom(liveId: String, eventId: String) -> String {
        "liveGames/\(liveId)/pitchEvents/\(eventId)"
    }

    static func ownerGame(ownerUid: String, gameId: String, eventId: String) -> String {
        "users/\(ownerUid)/games/\(gameId)/pitchEvents/\(eventId)"
    }

    /// nil when the event names no pitcher.
    static func pitcher(_ pitcherId: String?, eventId: String) -> String? {
        guard let id = trimmed(pitcherId) else { return nil }
        return "pitchers/\(id)/pitchEvents/\(eventId)"
    }

    /// nil when the event names no linked hitter.
    static func hitter(_ hitterId: String?, eventId: String) -> String? {
        guard let id = trimmed(hitterId) else { return nil }
        return "hitters/\(id)/pitchEvents/\(eventId)"
    }

    static func trimmed(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

/// Sends an event's copies one request each - never as one `WriteBatch`.
/// A batch is atomic, and the copies are governed by different rules (a
/// partner has create-only access to the owner's game copy and none to the
/// pitcher's), so one denial used to take every other copy down with it
/// while the UI showed the change as applied.
enum EventCopyWriter {
    /// `perform` sends one write and reports its error. Every write is sent
    /// whatever happened to the ones before it.
    static func send(
        _ writes: [EventCopyWrite],
        label: String,
        perform: (EventCopyWrite, @escaping (Error?) -> Void) -> Void,
        log: @escaping (String) -> Void = { _ in }
    ) {
        for write in writes {
            perform(write) { error in
                if let error {
                    log("❌ \(label) failed for \(write.path): \(error.localizedDescription)")
                }
            }
        }
    }
}

/// Stands for `FieldValue.delete()` in an update, so the plans below stay
/// free of Firestore; the sender swaps it in.
struct EventCopyFieldDelete: Equatable {}

/// Every stored copy of one saved pitch, as paths.
struct EventCopyTargets: Equatable {
    /// The game copy and the live-room copy, or the legacy users/{uid}/pitchEvents
    /// copy for a pitch outside a game.
    var records: [String]
    /// The pitcher's and the hitter's own records. Career stats are read from
    /// these, so an edit made after the game - with no live room for the
    /// owner's mirror to carry it - has to write them directly.
    var pitcher: String?
    var hitter: String?

    var all: [String] { records + [pitcher, hitter].compactMap { $0 } }

    /// nil when the pitch has no id yet.
    static func of(
        eventId rawId: String?,
        isGame: Bool,
        gameId: String?,
        gameOwnerUid: String?,
        liveId: String?,
        createdByUid: String?,
        currentUid: String,
        pitcherId: String?,
        hitterId: String?
    ) -> EventCopyTargets? {
        guard let eventId = EventCopyPaths.trimmed(rawId) else { return nil }
        var records: [String] = []
        if isGame {
            if let gid = EventCopyPaths.trimmed(gameId), let owner = EventCopyPaths.trimmed(gameOwnerUid) {
                records.append(EventCopyPaths.ownerGame(ownerUid: owner, gameId: gid, eventId: eventId))
            }
            if let live = EventCopyPaths.trimmed(liveId) {
                records.append(EventCopyPaths.liveRoom(liveId: live, eventId: eventId))
            }
        }
        if records.isEmpty {
            let owner = EventCopyPaths.trimmed(createdByUid) ?? currentUid
            records.append("users/\(owner)/pitchEvents/\(eventId)")
        }
        return EventCopyTargets(
            records: records,
            pitcher: EventCopyPaths.pitcher(pitcherId, eventId: eventId),
            hitter: EventCopyPaths.hitter(hitterId, eventId: eventId)
        )
    }
}

/// The writes each change to a saved pitch needs, across all its copies.
/// Each goes out as its own request (EventCopyWriter.send); the rules decide
/// copy by copy, so a copy this user can't write fails alone.
enum EventCopyPlan {
    /// The pitcher and hitter create rules require the writer to be the
    /// author, so those copies carry the writer and keep the real author as
    /// originalCreatedByUid.
    static func careerCopy(of data: [String: Any], writerUid: String) -> [String: Any] {
        var copy = data
        if let author = EventCopyPaths.trimmed(data["createdByUid"] as? String), author != writerUid {
            copy["originalCreatedByUid"] = author
        }
        copy["createdByUid"] = writerUid
        return copy
    }

    /// An edited pitch replaces every copy.
    static func edit(_ data: [String: Any], targets: EventCopyTargets, writerUid: String) -> [EventCopyWrite] {
        let career = careerCopy(of: data, writerUid: writerUid)
        return targets.records.map { .set(path: $0, data: data) }
            + [targets.pitcher, targets.hitter].compactMap { $0 }.map { .set(path: $0, data: career) }
    }

    /// A deleted (or undone) pitch leaves every copy.
    static func delete(targets: EventCopyTargets) -> [EventCopyWrite] {
        targets.all.map { .delete(path: $0) }
    }

    /// The pitch moves to another pitcher: every copy names the new one, the
    /// old pitcher's record loses it and the new pitcher's record gains it.
    /// `data` is the whole pitch, needed to create the new row.
    static func reassignPitcher(
        _ data: [String: Any],
        eventId: String,
        targets: EventCopyTargets,
        newPitcherId: String,
        writerUid: String
    ) -> [EventCopyWrite] {
        guard let newId = EventCopyPaths.trimmed(newPitcherId),
              let newPath = EventCopyPaths.pitcher(newId, eventId: eventId)
        else { return [] }
        let change: [String: Any] = ["pitcherId": newId]
        var writes: [EventCopyWrite] = targets.records.map { .update(path: $0, data: change) }
        if let hitter = targets.hitter { writes.append(.update(path: hitter, data: change)) }
        if let old = targets.pitcher, old != newPath { writes.append(.delete(path: old)) }
        var moved = data
        moved["pitcherId"] = newId
        writes.append(.set(path: newPath, data: careerCopy(of: moved, writerUid: writerUid)))
        return writes
    }

    /// The pitch is given to a batter by jersey number: the roster links go,
    /// and so does the row in the hitter's record it is no longer thrown to.
    static func changeBatter(jersey: String, targets: EventCopyTargets) -> [EventCopyWrite] {
        let change: [String: Any] = [
            "opponentJersey": jersey,
            "opponentBatterId": EventCopyFieldDelete(),
            "hitterId": EventCopyFieldDelete()
        ]
        var writes: [EventCopyWrite] = targets.records.map { .update(path: $0, data: change) }
        if let pitcher = targets.pitcher { writes.append(.update(path: pitcher, data: change)) }
        if let hitter = targets.hitter { writes.append(.delete(path: hitter)) }
        return writes
    }

    /// The cards sheet's Done with a new pitcher and/or batter for the
    /// selected pitches. Either may be nil; a pitcher that doesn't change is
    /// no move.
    static func selectionChange(
        _ data: [String: Any],
        eventId: String,
        targets: EventCopyTargets,
        newPitcherId: String?,
        jersey: String?,
        writerUid: String
    ) -> [EventCopyWrite] {
        let jersey = EventCopyPaths.trimmed(jersey)
        let newPitcher = EventCopyPaths.trimmed(newPitcherId)
        let moves = newPitcher.map { EventCopyPaths.pitcher($0, eventId: eventId) != targets.pitcher } ?? false

        var writes: [EventCopyWrite] = []
        var moved = data
        var remaining = targets
        if let jersey {
            var batterTargets = targets
            if moves { batterTargets.pitcher = nil }   // that row is about to go
            writes += changeBatter(jersey: jersey, targets: batterTargets)
            moved["opponentJersey"] = jersey
            moved.removeValue(forKey: "opponentBatterId")
            moved.removeValue(forKey: "hitterId")
            remaining.hitter = nil
        }
        if moves, let newPitcher {
            writes += reassignPitcher(moved, eventId: eventId, targets: remaining,
                                      newPitcherId: newPitcher, writerUid: writerUid)
        }
        return writes
    }
}

/// The owner's device copying live-room pitches into the permanent records.
struct LivePitchMirror {
    enum ChangeKind { case added, modified, removed }

    /// Present only on the owner's device for the open game.
    struct Owner: Equatable {
        var ownerUid: String
        var gameId: String
    }

    /// Ids already copied by the current listener.
    private(set) var mirroredIds: Set<String> = []

    /// A new listener replays the whole room as `.added`; forgetting what was
    /// copied makes it copy everything again, so edits made while it was
    /// detached arrive. Re-copying an unchanged pitch is harmless.
    mutating func restart() {
        mirroredIds.removeAll()
    }

    /// The writes one room change needs. Nothing unless this is the owner.
    mutating func writes(
        for change: ChangeKind,
        eventId: String,
        data roomData: [String: Any],
        owner: Owner?
    ) -> [EventCopyWrite] {
        guard let owner,
              EventCopyPaths.trimmed(owner.ownerUid) != nil,
              EventCopyPaths.trimmed(owner.gameId) != nil
        else { return [] }

        let gamePath = EventCopyPaths.ownerGame(ownerUid: owner.ownerUid, gameId: owner.gameId, eventId: eventId)
        let pitcherPath = EventCopyPaths.pitcher(roomData["pitcherId"] as? String, eventId: eventId)
        let hitterPath = EventCopyPaths.hitter(roomData["hitterId"] as? String, eventId: eventId)

        if change == .removed {
            mirroredIds.remove(eventId)
            return [gamePath, pitcherPath, hitterPath].compactMap { $0 }.map { .delete(path: $0) }
        }

        // A re-add of a pitch already copied by this listener is skipped; an
        // edit always rewrites.
        if change == .added, mirroredIds.contains(eventId) { return [] }
        mirroredIds.insert(eventId)

        var gameData = roomData
        gameData["gameId"] = owner.gameId
        // The room's backfill stamps the owner as author so it passes the
        // live-room create rule, keeping the real author beside it. The
        // game copy goes back to the real author.
        if let original = EventCopyPaths.trimmed(roomData["originalCreatedByUid"] as? String) {
            gameData["createdByUid"] = original
        }
        if gameData["createdByUid"] == nil {
            gameData["createdByUid"] = owner.ownerUid
        }

        var writes: [EventCopyWrite] = [.set(path: gamePath, data: gameData)]

        let careerData = EventCopyPlan.careerCopy(of: gameData, writerUid: owner.ownerUid)
        if let pitcherPath { writes.append(.set(path: pitcherPath, data: careerData)) }
        if let hitterPath { writes.append(.set(path: hitterPath, data: careerData)) }
        return writes
    }

    /// The owner's pre-live pitches with the room's deletions taken out, so a
    /// deleted pitch can't come back from the seed on the next merge.
    static func pruned(seed: [PitchEvent], removedIds: Set<String>) -> [PitchEvent] {
        guard !removedIds.isEmpty else { return seed }
        return seed.filter { event in
            guard let id = event.id else { return true }
            return !removedIds.contains(id)
        }
    }

    /// What the cards show during a live session: the seeded pitches and the
    /// room's, one per id with the room's version winning, newest first.
    /// Pitches with no id can't be matched and are all kept.
    static func merged(seeded: [PitchEvent], live: [PitchEvent]) -> [PitchEvent] {
        var byId: [String: PitchEvent] = [:]
        var result: [PitchEvent] = []
        for event in seeded + live {
            if let id = event.id {
                byId[id] = event
            } else {
                result.append(event)
            }
        }
        result.append(contentsOf: byId.values)
        return result.sorted { $0.timestamp > $1.timestamp }
    }
}
