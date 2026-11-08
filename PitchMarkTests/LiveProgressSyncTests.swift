//
//  LiveProgressSyncTests.swift
//  PitchMarkTests
//
//  Batch 2 (approved 2026-10-31): when a scoreboard update from the other
//  device or the saved game may replace this device's, and what a relaunch
//  restores. Rules 1-11.
//

import XCTest
@testable import PitchMark

@MainActor
final class LiveProgressSyncTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 50_000)

    /// A device in room "live-1" that has already accepted revision 4.
    private func device(revision: Int = 4) -> LiveProgressSync {
        var sync = LiveProgressSync()
        sync.enterRoom("live-1")
        if revision > 0 {
            XCTAssertTrue(sync.acceptRoomSnapshot(remoteRevision: revision, remoteStamp: nil, now: t0))
        }
        return sync
    }

    // MARK: Rule 1 - revision gate

    func testOnlyAHigherRevisionApplies() {
        var sync = device(revision: 4)
        XCTAssertFalse(sync.acceptRoomSnapshot(remoteRevision: 3, remoteStamp: nil, now: t0), "older")
        XCTAssertFalse(sync.acceptRoomSnapshot(remoteRevision: 4, remoteStamp: nil, now: t0), "same - an echo")
        XCTAssertTrue(sync.acceptRoomSnapshot(remoteRevision: 5, remoteStamp: nil, now: t0))
        XCTAssertEqual(sync.revision, 5, "accepting raises the floor")
        XCTAssertFalse(sync.acceptRoomSnapshot(remoteRevision: 5, remoteStamp: nil, now: t0))
    }

    /// The floor is never bumped by local changes (CLAUDE.md: server-assigned only).
    func testLocalChangesNeverRaiseTheRevision() {
        var sync = device(revision: 4)
        for i in 0..<10 { sync.noteLocalChange(now: t0.addingTimeInterval(Double(i))) }
        XCTAssertEqual(sync.revision, 4)
    }

    // MARK: Rules 2-3 - unsent local change, 5-second limit

    func testUnsentLocalChangeBlocksEvenHigherRevisions() {
        var sync = device(revision: 4)
        sync.noteLocalChange(now: t0)
        XCTAssertTrue(sync.hasUnpublishedLocalChange(now: t0.addingTimeInterval(1)))
        XCTAssertFalse(sync.acceptRoomSnapshot(remoteRevision: 9, remoteStamp: nil, now: t0.addingTimeInterval(1)))
        XCTAssertEqual(sync.revision, 4, "a blocked snapshot doesn't move the floor")
    }

    func testProtectionExpiresAfterFiveSeconds() {
        var sync = device(revision: 4)
        sync.noteLocalChange(now: t0)
        XCTAssertTrue(sync.hasUnpublishedLocalChange(now: t0.addingTimeInterval(4.9)))
        XCTAssertFalse(sync.hasUnpublishedLocalChange(now: t0.addingTimeInterval(5)))
        XCTAssertTrue(sync.acceptRoomSnapshot(remoteRevision: 5, remoteStamp: nil, now: t0.addingTimeInterval(5)),
                      "a publish that never reported back can't deafen the device")
    }

    // MARK: Rule 4 - publish results

    func testSuccessfulPublishRaisesTheFloorAndClearsTheGuard() {
        var sync = device(revision: 4)
        sync.noteLocalChange(now: t0)
        let token = sync.tokenForPublish
        sync.publishFinished(token: token, serverRevision: 5, publishedRoomId: "live-1")
        XCTAssertEqual(sync.revision, 5)
        XCTAssertFalse(sync.hasUnpublishedLocalChange(now: t0.addingTimeInterval(1)))
        XCTAssertFalse(sync.acceptRoomSnapshot(remoteRevision: 5, remoteStamp: nil, now: t0.addingTimeInterval(1)),
                       "our own write's echo")
        XCTAssertTrue(sync.acceptRoomSnapshot(remoteRevision: 6, remoteStamp: nil, now: t0.addingTimeInterval(1)),
                      "the partner's next change")
    }

    func testFailedPublishLeavesTheFloor() {
        var sync = device(revision: 4)
        sync.noteLocalChange(now: t0)
        sync.publishFinished(token: sync.tokenForPublish, serverRevision: nil, publishedRoomId: "live-1")
        XCTAssertEqual(sync.revision, 4)
        XCTAssertFalse(sync.hasUnpublishedLocalChange(now: t0.addingTimeInterval(1)))
        XCTAssertTrue(sync.acceptRoomSnapshot(remoteRevision: 5, remoteStamp: nil, now: t0.addingTimeInterval(1)),
                      "the room's state is newer than our failed write")
    }

    func testPublishToAnOldRoomDoesNotMoveTheNewRoomsFloor() {
        var sync = device(revision: 4)
        sync.noteLocalChange(now: t0)
        let token = sync.tokenForPublish
        sync.enterRoom("live-2")
        sync.publishFinished(token: token, serverRevision: 40, publishedRoomId: "live-1")
        XCTAssertEqual(sync.revision, 0)
    }

    func testNoRoomMeansNothingPending() {
        var sync = LiveProgressSync()
        sync.noteLocalChange(now: t0)
        sync.publishSkippedNoRoom(token: sync.tokenForPublish)
        XCTAssertFalse(sync.hasUnpublishedLocalChange(now: t0))
    }

    // MARK: Rule 5 - one publish per turn

    func testSeveralChangesOnePublishClearsTheGuardOnce() {
        var sync = device(revision: 4)
        sync.noteLocalChange(now: t0)                 // count reset
        sync.noteLocalChange(now: t0)                 // out
        sync.noteLocalChange(now: t0)                 // runners
        let token = sync.tokenForPublish              // the coalesced publish starts
        sync.publishFinished(token: token, serverRevision: 5, publishedRoomId: "live-1")
        XCTAssertFalse(sync.hasUnpublishedLocalChange(now: t0), "one publish covered all three")
        XCTAssertEqual(sync.revision, 5, "+1 on the server, not +3")
    }

    func testChangeDuringAPublishStaysProtected() {
        var sync = device(revision: 4)
        sync.noteLocalChange(now: t0)
        let inFlight = sync.tokenForPublish
        sync.noteLocalChange(now: t0.addingTimeInterval(0.2))   // made while the first is in flight
        sync.publishFinished(token: inFlight, serverRevision: 5, publishedRoomId: "live-1")
        XCTAssertTrue(sync.hasUnpublishedLocalChange(now: t0.addingTimeInterval(0.3)))
        XCTAssertFalse(sync.acceptRoomSnapshot(remoteRevision: 6, remoteStamp: nil, now: t0.addingTimeInterval(0.3)))
    }

    // MARK: Rule 6 - old-build rooms

    func testOldBuildRoomFallsBackToTimestamps() {
        var fresh = LiveProgressSync()
        XCTAssertTrue(fresh.acceptRoomSnapshot(remoteRevision: nil, remoteStamp: nil, now: t0),
                      "this device changed nothing")

        var changed = LiveProgressSync()
        changed.noteLocalChange(now: t0)
        changed.publishSkippedNoRoom(token: changed.tokenForPublish)
        XCTAssertFalse(changed.acceptRoomSnapshot(remoteRevision: nil, remoteStamp: t0.addingTimeInterval(-1), now: t0.addingTimeInterval(10)),
                       "older than our change")
        XCTAssertTrue(changed.acceptRoomSnapshot(remoteRevision: nil, remoteStamp: t0.addingTimeInterval(1), now: t0.addingTimeInterval(10)))
        XCTAssertFalse(changed.acceptRoomSnapshot(remoteRevision: nil, remoteStamp: nil, now: t0.addingTimeInterval(10)),
                       "no time, can't prove it's newer")
    }

    // MARK: Rule 7 - rooms

    func testDifferentRoomStartsAtZero() {
        var sync = device(revision: 30)
        sync.enterRoom("live-1")
        XCTAssertEqual(sync.revision, 30, "same room restarting keeps the floor")
        sync.enterRoom("live-2")
        XCTAssertEqual(sync.revision, 0)
        XCTAssertTrue(sync.acceptRoomSnapshot(remoteRevision: 1, remoteStamp: nil, now: t0),
                      "a fresh room's first commit is accepted")
    }

    func testLeavingTheRoomResetsTheFloor() {
        var sync = device(revision: 12)
        sync.leaveRoom()
        XCTAssertEqual(sync.revision, 0)
        XCTAssertNil(sync.roomId)
    }

    // MARK: Rule 8 - relaunch

    func testSnapshotRestoresEverythingButTheRevision() throws {
        let fields = LiveProgressFields(
            board: ScoreboardValues(balls: 2, strikes: 1, inning: 5, us: 3, them: 4),
            outs: 2,
            bases: BaseOccupancy(first: Fixture.r1, third: Fixture.r3)
        )
        let saved = LocalProgressSnapshot(fields: fields, updatedAt: 1_234, progressRevision: 77)
        let decoded = try JSONDecoder().decode(LocalProgressSnapshot.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded.progressRevision, 77, "still written for older builds")

        let restored = decoded.restored(over: LiveProgressFields())
        XCTAssertEqual(restored.fields, fields)
        XCTAssertEqual(restored.changedAt, Date(timeIntervalSince1970: 1_234))

        var sync = LiveProgressSync()
        sync.lastLocalChangeAt = restored.changedAt
        XCTAssertEqual(sync.revision, 0, "the revision is never restored")
    }

    func testOlderSnapshotWithoutOutsOrRunnersKeepsCurrent() throws {
        let json = #"{"balls":1,"strikes":0,"inning":2,"hits":0,"walks":0,"us":0,"them":1,"updatedAt":10}"#
        let old = try JSONDecoder().decode(LocalProgressSnapshot.self, from: Data(json.utf8))
        let current = LiveProgressFields(outs: 1, bases: BaseOccupancy(second: Fixture.r2))
        let restored = old.restored(over: current)
        XCTAssertEqual(restored.fields.board, ScoreboardValues(balls: 1, strikes: 0, inning: 2, us: 0, them: 1))
        XCTAssertEqual(restored.fields.outs, 1)
        XCTAssertEqual(restored.fields.bases, BaseOccupancy(second: Fixture.r2))
    }

    // MARK: Rule 9 - reloading the saved game

    func testReloadDoesNotOverwriteANewerLocalChange() {
        let local = ScoreboardValues(balls: 2, strikes: 2, inning: 3, us: 1)
        let stale = ScoreboardValues(balls: 0, strikes: 1, inning: 3, us: 1)
        let merged = LiveProgressSync.mergeReloadedGame(
            game: stale, gameStamp: t0, local: local, localStamp: t0.addingTimeInterval(5), now: t0.addingTimeInterval(6))
        XCTAssertEqual(merged.game, local)
        XCTAssertEqual(merged.gameStamp, t0.addingTimeInterval(5))
        XCTAssertFalse(LiveProgressSync.snapshotIsNewer(t0, than: t0.addingTimeInterval(5)),
                       "and the game listener won't apply it either")
    }

    func testReloadThatIsNewerStands() {
        let newer = ScoreboardValues(balls: 3, strikes: 2, inning: 4)
        let merged = LiveProgressSync.mergeReloadedGame(
            game: newer, gameStamp: t0.addingTimeInterval(10), local: ScoreboardValues(), localStamp: t0, now: t0.addingTimeInterval(11))
        XCTAssertEqual(merged.game, newer)
        XCTAssertEqual(merged.localStamp, t0)
    }

    func testFirstLookAtAGameAdoptsItsTime() {
        let game = ScoreboardValues(balls: 1, inning: 2)
        let merged = LiveProgressSync.mergeReloadedGame(
            game: game, gameStamp: t0, local: ScoreboardValues(), localStamp: nil, now: t0.addingTimeInterval(100))
        XCTAssertEqual(merged.game, game, "nothing local yet - the saved game stands")
        XCTAssertEqual(merged.localStamp, t0)

        let fresh = LiveProgressSync.mergeReloadedGame(
            game: ScoreboardValues(), gameStamp: nil, local: ScoreboardValues(), localStamp: nil, now: t0)
        XCTAssertNil(fresh.localStamp, "a fresh game with no time sets no local time")
    }

    // MARK: Rules 10-11 - applying a room update

    func testAppliedUpdateReplacesEverything() {
        let current = LiveProgressFields(board: ScoreboardValues(balls: 1, strikes: 1, inning: 2, us: 0, them: 0),
                                         outs: 0, bases: BaseOccupancy(first: Fixture.r1))
        let partner = LiveProgressFields(board: ScoreboardValues(balls: 0, strikes: 0, inning: 3, hits: 4, walks: 2, us: 5, them: 6),
                                         outs: 2, bases: BaseOccupancy(second: Fixture.r2, third: Fixture.r3))
        XCTAssertEqual(current.applying(roomData: partner.payload), partner, "the payload round-trips through apply")
    }

    func testUpdateWithoutRunnersKeepsOurs() {
        let current = LiveProgressFields(outs: 1, bases: BaseOccupancy(first: Fixture.r1))
        let oldPublisher: [String: Any] = ["balls": 2, "strikes": 0, "inning": 1, "hits": 0, "walks": 0, "us": 0, "them": 0, "outs": 2]
        let next = current.applying(roomData: oldPublisher)
        XCTAssertEqual(next.bases, BaseOccupancy(first: Fixture.r1))
        XCTAssertEqual(next.outs, 2)
        XCTAssertEqual(next.board.balls, 2)
    }

    func testUpdateWithEmptyRunnersClearsOurs() {
        let current = LiveProgressFields(bases: BaseOccupancy(first: Fixture.r1))
        let next = current.applying(roomData: ["bases": [String: Any]()])
        XCTAssertEqual(next.bases, .empty, "an empty map is a real 'nobody on', unlike a missing field")
    }
}
