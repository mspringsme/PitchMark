//
//  RunnerEventStore.swift
//  PitchMark
//
//  Where between-pitch runner events (RunnerEvent, BaseRunnerRules.swift)
//  are stored. Same three-place shape as a pitch, for the same reasons:
//
//  - liveGames/{liveId}/runnerEvents      - the room, during a live session
//  - users/{owner}/games/{gid}/runnerEvents - the permanent game record
//  - hitters/{hitterId}/runnerEvents      - the runner's stats history
//
//  Each copy is written on its own, never in one WriteBatch: they are
//  governed by different rules (a partner can only *create* in the owner's
//  game and can't touch /hitters), and one denial would sink the batch
//  (CLAUDE.md, "Never put an event's copies in one WriteBatch").
//
//  As with pitches, the owner's device is the only bridge to the hitter
//  copy during a live session - `mirrorLiveChanges` is called from its
//  runnerEvents listener.
//
//  PitchMark target only.
//

import Foundation
import FirebaseFirestore

enum RunnerEventStore {
    static let collection = "runnerEvents"

    private static var db: Firestore { Firestore.firestore() }

    static func livePath(liveId: String, eventId: String) -> String {
        "liveGames/\(liveId)/\(collection)/\(eventId)"
    }

    static func gamePath(ownerUid: String, gameId: String, eventId: String) -> String {
        "users/\(ownerUid)/games/\(gameId)/\(collection)/\(eventId)"
    }

    static func hitterPath(hitterId: String, eventId: String) -> String {
        "hitters/\(hitterId)/\(collection)/\(eventId)"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Where a new event is written. In a live room: the room and the
    /// owner's game - the owner's listener adds the hitter copy, because a
    /// partner can't write /hitters. Otherwise this device is the owner and
    /// writes the game and hitter copies itself. No linked hitter, no hitter
    /// copy.
    static func savePaths(for event: RunnerEvent, liveId: String?, ownerUid: String?, gameId: String?) -> [String] {
        var paths: [String] = []
        if let liveId = nonEmpty(liveId) {
            paths.append(livePath(liveId: liveId, eventId: event.id))
        }
        if let ownerUid = nonEmpty(ownerUid), let gameId = nonEmpty(gameId) {
            paths.append(gamePath(ownerUid: ownerUid, gameId: gameId, eventId: event.id))
        }
        if nonEmpty(liveId) == nil, let hitterId = nonEmpty(event.hitterId) {
            paths.append(hitterPath(hitterId: hitterId, eventId: event.id))
        }
        return paths
    }

    /// Every copy undo tries to delete. Each is attempted on its own: a
    /// partner's delete of the owner's copies is denied by rules, and the
    /// owner's mirror removes those.
    static func deletePaths(for event: RunnerEvent, liveId: String?, ownerUid: String?, gameId: String?) -> [String] {
        var paths: [String] = []
        if let liveId = nonEmpty(liveId) {
            paths.append(livePath(liveId: liveId, eventId: event.id))
        }
        if let ownerUid = nonEmpty(ownerUid), let gameId = nonEmpty(gameId) {
            paths.append(gamePath(ownerUid: ownerUid, gameId: gameId, eventId: event.id))
        }
        if let hitterId = nonEmpty(event.hitterId) {
            paths.append(hitterPath(hitterId: hitterId, eventId: event.id))
        }
        return paths
    }

    /// The fields saved for an event - its Codable form, plus the room id a
    /// partner's create in the owner's game is checked against.
    static func savedData(for event: RunnerEvent, liveId: String?) -> [String: Any]? {
        do {
            var data = try Firestore.Encoder().encode(event)
            if let liveId = nonEmpty(liveId) { data["liveId"] = liveId }
            return data
        } catch {
            debugLog("❌ runnerEvent encode failed:", error.localizedDescription)
            return nil
        }
    }

    static func decode(_ data: [String: Any]) -> RunnerEvent? {
        try? Firestore.Decoder().decode(RunnerEvent.self, from: data)
    }

    static func save(_ event: RunnerEvent, liveId: String?, ownerUid: String?, gameId: String?) {
        guard let data = savedData(for: event, liveId: liveId) else { return }
        for path in savePaths(for: event, liveId: liveId, ownerUid: ownerUid, gameId: gameId) {
            db.document(path).setData(data, merge: false) { err in
                if let err {
                    debugLog("❌ runnerEvent save failed \(path):", err.localizedDescription)
                }
            }
        }
    }

    static func delete(_ event: RunnerEvent, liveId: String?, ownerUid: String?, gameId: String?) {
        for path in deletePaths(for: event, liveId: liveId, ownerUid: ownerUid, gameId: gameId) {
            db.document(path).delete { err in
                if let err {
                    debugLog("⚠️ runnerEvent delete skipped \(path):", err.localizedDescription)
                }
            }
        }
    }

    /// Owner only: keep the game and hitter copies in step with the room,
    /// including partner undos (`.removed`). Re-mirroring on a listener
    /// restart is an idempotent setData, so there is no seen-set to go stale.
    static func mirrorLiveChanges(_ changes: [DocumentChange], ownerUid: String, gameId: String) {
        for change in changes {
            let eventId = change.document.documentID
            var data = change.document.data()
            let hitterId = (data["hitterId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let game = db.document(gamePath(ownerUid: ownerUid, gameId: gameId, eventId: eventId))
            let hitter = (hitterId?.isEmpty == false) ? db.document(hitterPath(hitterId: hitterId!, eventId: eventId)) : nil

            if change.type == .removed {
                game.delete()
                hitter?.delete()
                continue
            }
            data["gameId"] = gameId
            game.setData(data, merge: false) { err in
                if let err { debugLog("❌ mirror runnerEvent failed:", err.localizedDescription) }
            }
            if let hitter {
                // The hitter-copy create rule wants the writer as author;
                // keep the partner who recorded it beside that.
                var hitterData = data
                if let author = data["createdByUid"] as? String, author != ownerUid {
                    hitterData["originalCreatedByUid"] = author
                }
                hitterData["createdByUid"] = ownerUid
                hitter.setData(hitterData, merge: false) { err in
                    if let err { debugLog("❌ mirror hitter runnerEvent failed:", err.localizedDescription) }
                }
            }
        }
    }

    /// A hitter's runner history, for stats.
    static func loadForHitters(_ hitterIds: [String], completion: @escaping ([RunnerEvent]) -> Void) {
        let ids = Array(Set(hitterIds.filter { !$0.isEmpty }))
        guard !ids.isEmpty else { completion([]); return }
        let group = DispatchGroup()
        var collected: [String: RunnerEvent] = [:]
        let lock = NSLock()
        for id in ids {
            group.enter()
            db.collection("hitters").document(id).collection(collection).getDocuments { snapshot, error in
                if let error {
                    debugLog("❌ load hitter runnerEvents failed:", error.localizedDescription)
                }
                let events = snapshot?.documents.compactMap { decode($0.data()) } ?? []
                lock.lock()
                for event in events { collected[event.id] = event }
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(Array(collected.values))
        }
    }
}
