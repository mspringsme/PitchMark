//
//  EventCopiesTests.swift
//  PitchMarkTests
//
//  Batch 3 (approved 2026-10-31): the owner's device copying live-room
//  pitches into the permanent records, what the cards show during a live
//  session, and editing/deleting every copy of a pitch.
//

import XCTest
@testable import PitchMark

private let owner = LivePitchMirror.Owner(ownerUid: "owner", gameId: "game-1")

/// A room pitch as Firestore hands it to the listener.
private func roomData(
    createdBy: String = "partner",
    originalCreatedBy: String? = nil,
    pitcherId: String? = "pitcher-1",
    hitterId: String? = "hitter-9",
    outcome: String = "1B"
) -> [String: Any] {
    var data: [String: Any] = ["createdByUid": createdBy, "outcome": outcome, "pitch": "Fastball"]
    if let originalCreatedBy { data["originalCreatedByUid"] = originalCreatedBy }
    if let pitcherId { data["pitcherId"] = pitcherId }
    if let hitterId { data["hitterId"] = hitterId }
    return data
}

private func paths(_ writes: [EventCopyWrite]) -> [String] { writes.map(\.path) }

private func write(_ writes: [EventCopyWrite], at path: String) -> EventCopyWrite? {
    writes.first { $0.path == path }
}

private let gamePath = "users/owner/games/game-1/pitchEvents/ev1"
private let pitcherPath = "pitchers/pitcher-1/pitchEvents/ev1"
private let hitterPath = "hitters/hitter-9/pitchEvents/ev1"

@MainActor
final class LivePitchMirrorTests: XCTestCase {
    /// Rule 1: a partner's device copies nothing.
    func testOnlyTheOwnerCopies() {
        var mirror = LivePitchMirror()
        for kind in [LivePitchMirror.ChangeKind.added, .modified, .removed] {
            XCTAssertTrue(mirror.writes(for: kind, eventId: "ev1", data: roomData(), owner: nil).isEmpty, "\(kind)")
        }
        XCTAssertTrue(mirror.writes(for: .added, eventId: "ev1", data: roomData(),
                                    owner: .init(ownerUid: "", gameId: "game-1")).isEmpty, "no owner uid")
        XCTAssertTrue(mirror.writes(for: .added, eventId: "ev1", data: roomData(),
                                    owner: .init(ownerUid: "owner", gameId: " ")).isEmpty, "no game")
    }

    /// Rule 2: game always; pitcher and hitter only when named.
    func testCopiesGoToGamePitcherAndHitter() {
        var mirror = LivePitchMirror()
        let all = mirror.writes(for: .added, eventId: "ev1", data: roomData(), owner: owner)
        XCTAssertEqual(paths(all), [gamePath, pitcherPath, hitterPath])
        XCTAssertTrue(all.allSatisfy { !$0.isDelete })

        let gameOnly = mirror.writes(for: .added, eventId: "ev2",
                                     data: roomData(pitcherId: "  ", hitterId: nil), owner: owner)
        XCTAssertEqual(paths(gameOnly), ["users/owner/games/game-1/pitchEvents/ev2"])
    }

    /// Rule 3: an edit rewrites every copy with the edited values.
    func testAnEditRewritesEveryCopy() {
        var mirror = LivePitchMirror()
        _ = mirror.writes(for: .added, eventId: "ev1", data: roomData(outcome: "1B"), owner: owner)
        let edit = mirror.writes(for: .modified, eventId: "ev1", data: roomData(outcome: "2B"), owner: owner)
        XCTAssertEqual(paths(edit), [gamePath, pitcherPath, hitterPath])
        for write in edit {
            guard case .set(_, let data) = write else { return XCTFail("\(write.path) should be a full set") }
            XCTAssertEqual(data["outcome"] as? String, "2B", write.path)
        }
    }

    /// Rule 3: a delete removes every copy.
    func testADeleteRemovesEveryCopy() {
        var mirror = LivePitchMirror()
        _ = mirror.writes(for: .added, eventId: "ev1", data: roomData(), owner: owner)
        let removal = mirror.writes(for: .removed, eventId: "ev1", data: roomData(), owner: owner)
        XCTAssertEqual(paths(removal), [gamePath, pitcherPath, hitterPath])
        XCTAssertTrue(removal.allSatisfy(\.isDelete))
        XCTAssertFalse(mirror.mirroredIds.contains("ev1"))
    }

    /// Rule 4: the same pitch arriving as new again in one session is not
    /// copied twice.
    func testARepeatedAddIsSkipped() {
        var mirror = LivePitchMirror()
        XCTAssertEqual(mirror.writes(for: .added, eventId: "ev1", data: roomData(), owner: owner).count, 3)
        XCTAssertTrue(mirror.writes(for: .added, eventId: "ev1", data: roomData(), owner: owner).isEmpty)
    }

    /// Rule 5: after a restart everything is copied again, so an edit made
    /// while disconnected (replayed as "new") still lands.
    func testRestartCopiesEverythingAgain() {
        var mirror = LivePitchMirror()
        _ = mirror.writes(for: .added, eventId: "ev1", data: roomData(outcome: "1B"), owner: owner)
        mirror.restart()
        let replay = mirror.writes(for: .added, eventId: "ev1", data: roomData(outcome: "Out"), owner: owner)
        XCTAssertEqual(paths(replay), [gamePath, pitcherPath, hitterPath])
        XCTAssertEqual(write(replay, at: gamePath)?.data?["outcome"] as? String, "Out")
    }

    /// Rule 6: the game copy keeps the real author, including one the room
    /// backfill had restamped as the owner.
    func testGameCopyKeepsTheRealAuthor() {
        var mirror = LivePitchMirror()
        let partners = mirror.writes(for: .added, eventId: "ev1", data: roomData(createdBy: "partner"), owner: owner)
        XCTAssertEqual(write(partners, at: gamePath)?.data?["createdByUid"] as? String, "partner")

        let backfilled = mirror.writes(for: .added, eventId: "ev2",
                                       data: roomData(createdBy: "owner", originalCreatedBy: "partner"), owner: owner)
        XCTAssertEqual(write(backfilled, at: "users/owner/games/game-1/pitchEvents/ev2")?.data?["createdByUid"] as? String,
                       "partner")

        var noAuthor = roomData()
        noAuthor["createdByUid"] = nil
        let unattributed = mirror.writes(for: .added, eventId: "ev3", data: noAuthor, owner: owner)
        XCTAssertEqual(write(unattributed, at: "users/owner/games/game-1/pitchEvents/ev3")?.data?["createdByUid"] as? String,
                       "owner", "no author at all falls back to the owner")
    }

    /// Rule 6: pitcher and hitter copies are written as the owner, with the
    /// partner kept as the original author.
    func testCareerCopiesAreWrittenAsTheOwner() {
        var mirror = LivePitchMirror()
        let writes = mirror.writes(for: .added, eventId: "ev1", data: roomData(createdBy: "partner"), owner: owner)
        for path in [pitcherPath, hitterPath] {
            let data = write(writes, at: path)?.data
            XCTAssertEqual(data?["createdByUid"] as? String, "owner", path)
            XCTAssertEqual(data?["originalCreatedByUid"] as? String, "partner", path)
        }

        let ownersOwn = mirror.writes(for: .added, eventId: "ev2", data: roomData(createdBy: "owner"), owner: owner)
        let pitcherCopy = write(ownersOwn, at: "pitchers/pitcher-1/pitchEvents/ev2")?.data
        XCTAssertEqual(pitcherCopy?["createdByUid"] as? String, "owner")
        XCTAssertNil(pitcherCopy?["originalCreatedByUid"], "the owner's own pitch gets no original author")
    }

    /// Rule 7: every copy carries the owner's game id.
    func testCopiesAreStampedWithTheGameId() {
        var mirror = LivePitchMirror()
        var data = roomData()
        data["gameId"] = "some-other-game"
        let writes = mirror.writes(for: .added, eventId: "ev1", data: data, owner: owner)
        XCTAssertEqual(writes.count, 3)
        for write in writes {
            XCTAssertEqual(write.data?["gameId"] as? String, "game-1", write.path)
        }
    }

    /// Rule 8: room version wins, one per id, newest first.
    func testCardsMergeSeedAndRoom() {
        let seededOld = Fixture.pitch(id: "a", timestamp: Fixture.t0, outcome: "1B")
        let seededOnly = Fixture.pitch(id: "b", timestamp: Fixture.t0.addingTimeInterval(10))
        let roomEdit = Fixture.pitch(id: "a", timestamp: Fixture.t0, outcome: "2B")
        let roomNew = Fixture.pitch(id: "c", timestamp: Fixture.t0.addingTimeInterval(20))

        let cards = LivePitchMirror.merged(seeded: [seededOld, seededOnly], live: [roomEdit, roomNew])
        XCTAssertEqual(cards.map(\.id), ["c", "b", "a"])
        XCTAssertEqual(cards.last?.outcome, "2B", "the room's version of a wins")
    }

    /// Rule 8: pitches with no id can't be matched, so none are dropped.
    func testPitchesWithoutIdsAreKept() {
        var noId1 = Fixture.pitch(timestamp: Fixture.t0)
        noId1.id = nil
        var noId2 = Fixture.pitch(timestamp: Fixture.t0.addingTimeInterval(5))
        noId2.id = nil
        XCTAssertEqual(LivePitchMirror.merged(seeded: [noId1], live: [noId2]).count, 2)
    }

    /// Rule 9: a room deletion leaves the seed too, so the merge can't bring
    /// it back.
    func testADeletedPitchDoesNotComeBackFromTheSeed() {
        let seed = [Fixture.pitch(id: "a"), Fixture.pitch(id: "b")]
        let pruned = LivePitchMirror.pruned(seed: seed, removedIds: ["a"])
        XCTAssertEqual(pruned.map(\.id), ["b"])
        XCTAssertEqual(LivePitchMirror.merged(seeded: pruned, live: []).map(\.id), ["b"])
        XCTAssertEqual(LivePitchMirror.pruned(seed: seed, removedIds: []).map(\.id), ["a", "b"])
    }
}

@MainActor
final class EventCopyWriterTests: XCTestCase {
    private struct Denied: Error {}

    /// Rule 10: one request per copy, and a refused copy doesn't stop the
    /// rest.
    func testEachCopyIsItsOwnRequestAndADenialDoesNotStopTheOthers() {
        let writes: [EventCopyWrite] = [
            .update(path: "liveGames/l1/pitchEvents/ev1", data: ["outcome": "2B"]),
            .update(path: gamePath, data: ["outcome": "2B"]),
            .update(path: pitcherPath, data: ["outcome": "2B"]),
        ]
        var sent: [String] = []
        var logs: [String] = []
        EventCopyWriter.send(writes, label: "edit", perform: { write, completion in
            sent.append(write.path)
            completion(write.path == gamePath ? Denied() : nil)
        }, log: { logs.append($0) })

        XCTAssertEqual(sent, ["liveGames/l1/pitchEvents/ev1", gamePath, pitcherPath])
        XCTAssertEqual(logs.count, 1)
        XCTAssertTrue(logs.first?.contains(gamePath) == true)
    }

    /// Rule 10: even when every request is refused, every one is tried.
    func testEveryCopyIsTriedEvenWhenAllFail() {
        var sent = 0
        EventCopyWriter.send([.delete(path: gamePath), .delete(path: pitcherPath), .delete(path: hitterPath)],
                             label: "delete", perform: { _, completion in
            sent += 1
            completion(Denied())
        })
        XCTAssertEqual(sent, 3)
    }
}

/// Batch 5 (approved 2026-11-01), rules 4-8: every copy a change to a saved
/// pitch reaches, live room open or not.
@MainActor
final class EventCopyPlanTests: XCTestCase {
    private let roomPath = "liveGames/l1/pitchEvents/ev1"

    private func targets(liveId: String? = nil, pitcherId: String? = "pitcher-1",
                         hitterId: String? = "hitter-9") -> EventCopyTargets {
        EventCopyTargets.of(eventId: "ev1", isGame: true, gameId: "game-1", gameOwnerUid: "owner",
                            liveId: liveId, createdByUid: "partner", currentUid: "owner",
                            pitcherId: pitcherId, hitterId: hitterId)!
    }

    /// Rule 4: with no live room open the pitcher's and hitter's records are
    /// still copies - career stats are read from them.
    func testCopiesIncludeTheCareerRecordsWithOrWithoutALiveRoom() {
        XCTAssertEqual(targets().all, [gamePath, pitcherPath, hitterPath])
        XCTAssertEqual(targets(liveId: "l1").all, [gamePath, roomPath, pitcherPath, hitterPath])
        XCTAssertEqual(targets(pitcherId: " ", hitterId: nil).all, [gamePath], "only records it names")
    }

    func testAPitchOutsideAGameUsesItsAuthorsLegacyRecord() {
        let practice = EventCopyTargets.of(eventId: "ev1", isGame: false, gameId: nil, gameOwnerUid: "owner",
                                           liveId: "l1", createdByUid: "author", currentUid: "me",
                                           pitcherId: "pitcher-1", hitterId: nil)
        XCTAssertEqual(practice?.all, ["users/author/pitchEvents/ev1", pitcherPath])
        XCTAssertNil(EventCopyTargets.of(eventId: " ", isGame: true, gameId: "g", gameOwnerUid: "o", liveId: nil,
                                         createdByUid: nil, currentUid: "me", pitcherId: nil, hitterId: nil))
    }

    /// Rule 4: an edit replaces every copy; the career copies carry the
    /// writer as author (their create rule) and keep the real one.
    func testAnEditReplacesEveryCopy() {
        let data: [String: Any] = ["createdByUid": "partner", "outcome": "2B"]
        let writes = EventCopyPlan.edit(data, targets: targets(liveId: "l1"), writerUid: "owner")
        XCTAssertEqual(paths(writes), [gamePath, roomPath, pitcherPath, hitterPath])
        for record in [gamePath, roomPath] {
            guard case .set(_, let sent)? = write(writes, at: record) else { return XCTFail(record) }
            XCTAssertEqual(sent["createdByUid"] as? String, "partner")
            XCTAssertNil(sent["originalCreatedByUid"])
        }
        for career in [pitcherPath, hitterPath] {
            guard case .set(_, let sent)? = write(writes, at: career) else { return XCTFail(career) }
            XCTAssertEqual(sent["createdByUid"] as? String, "owner")
            XCTAssertEqual(sent["originalCreatedByUid"] as? String, "partner")
            XCTAssertEqual(sent["outcome"] as? String, "2B")
        }
    }

    /// Rule 5: deleting or undoing a pitch removes every copy.
    func testADeleteRemovesEveryCopy() {
        let writes = EventCopyPlan.delete(targets: targets())
        XCTAssertEqual(paths(writes), [gamePath, pitcherPath, hitterPath])
        XCTAssertTrue(writes.allSatisfy(\.isDelete))
    }

    /// Rule 6: moving a pitch to another pitcher takes it out of the old
    /// pitcher's record and puts it in the new one's.
    func testMovingAPitchToAnotherPitcher() {
        let data: [String: Any] = ["createdByUid": "owner", "pitcherId": "pitcher-1", "outcome": "1B"]
        let newPath = "pitchers/pitcher-2/pitchEvents/ev1"
        let writes = EventCopyPlan.selectionChange(data, eventId: "ev1", targets: targets(),
                                                   newPitcherId: "pitcher-2", jersey: nil, writerUid: "owner")
        XCTAssertEqual(paths(writes), [gamePath, hitterPath, pitcherPath, newPath])
        guard case .update(_, let change)? = write(writes, at: gamePath) else { return XCTFail() }
        XCTAssertEqual(change["pitcherId"] as? String, "pitcher-2")
        XCTAssertTrue(write(writes, at: pitcherPath)?.isDelete == true)
        guard case .set(_, let row)? = write(writes, at: newPath) else { return XCTFail("new pitcher gains it") }
        XCTAssertEqual(row["pitcherId"] as? String, "pitcher-2")
        XCTAssertEqual(row["outcome"] as? String, "1B")
        XCTAssertEqual(row["createdByUid"] as? String, "owner")

        let same = EventCopyPlan.selectionChange(data, eventId: "ev1", targets: targets(),
                                                 newPitcherId: "pitcher-1", jersey: nil, writerUid: "owner")
        XCTAssertTrue(same.isEmpty, "the same pitcher is no move")
    }

    /// Rule 7: giving a pitch to a jersey number drops the roster links and
    /// the row in the hitter's record.
    func testChangingTheBatterUnlinksTheHitter() {
        let writes = EventCopyPlan.selectionChange([:], eventId: "ev1", targets: targets(),
                                                   newPitcherId: nil, jersey: " 12 ", writerUid: "owner")
        XCTAssertEqual(paths(writes), [gamePath, pitcherPath, hitterPath])
        for path in [gamePath, pitcherPath] {
            guard case .update(_, let change)? = write(writes, at: path) else { return XCTFail(path) }
            XCTAssertEqual(change["opponentJersey"] as? String, "12")
            XCTAssertTrue(change["opponentBatterId"] is EventCopyFieldDelete)
            XCTAssertTrue(change["hitterId"] is EventCopyFieldDelete)
        }
        XCTAssertTrue(write(writes, at: hitterPath)?.isDelete == true)
    }

    /// Rules 6+7 together: the new pitcher's row is created already
    /// unlinked, and the rows about to go aren't updated first.
    func testBatterAndPitcherChangedTogether() {
        let data: [String: Any] = ["createdByUid": "owner", "pitcherId": "pitcher-1",
                                   "opponentBatterId": "cell-9", "hitterId": "hitter-9", "opponentJersey": "9"]
        let newPath = "pitchers/pitcher-2/pitchEvents/ev1"
        let writes = EventCopyPlan.selectionChange(data, eventId: "ev1", targets: targets(),
                                                   newPitcherId: "pitcher-2", jersey: "12", writerUid: "owner")
        XCTAssertEqual(paths(writes), [gamePath, hitterPath, gamePath, pitcherPath, newPath])
        XCTAssertTrue(write(writes, at: hitterPath)?.isDelete == true)
        XCTAssertFalse(writes.contains { $0.path == pitcherPath && !$0.isDelete }, "old pitcher row only deleted")
        guard case .set(_, let row)? = write(writes, at: newPath) else { return XCTFail() }
        XCTAssertEqual(row["opponentJersey"] as? String, "12")
        XCTAssertNil(row["hitterId"])
        XCTAssertNil(row["opponentBatterId"])
    }
}
