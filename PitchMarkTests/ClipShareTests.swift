//
//  ClipShareTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-24 (clip brief 2c, interim clip sharing):
//  6 Quick Send: phone and email checks, 40-character names, duplicates
//    (email any case, phone with or without +1), the 12-person limit
//  7 queue: nobody picked = nothing queued; one message per person, oldest
//    first; removed people skipped; Send Now scope; marking sent touches
//    only that person (HIGH RISK, broken on purpose); pruning
//  8 banner: not on opening a game, not without a change, yes on a new
//    half with clips waiting
//

import XCTest
@testable import PitchMark

@MainActor
final class ClipShareTests: XCTestCase {

    // MARK: 6 Quick Send

    func testAddressChecks() {
        XCTAssertTrue(QuickSendRules.isValidAddress("555-1234"))
        XCTAssertTrue(QuickSendRules.isValidAddress("+1 (555) 123-4567"))
        XCTAssertFalse(QuickSendRules.isValidAddress("555-123"))
        XCTAssertFalse(QuickSendRules.isValidAddress("call me"))
        XCTAssertTrue(QuickSendRules.isValidAddress("nana@example.com"))
        XCTAssertFalse(QuickSendRules.isValidAddress("nana@example"))
        XCTAssertFalse(QuickSendRules.isValidAddress("@example.com"))
        XCTAssertFalse(QuickSendRules.isValidAddress("na na@example.com"))
    }

    func testNamesAreTrimmedAndCapped() {
        XCTAssertNil(QuickSendRules.recipient(name: "  ", address: "5551234567"))
        let long = String(repeating: "a", count: 60)
        XCTAssertEqual(QuickSendRules.recipient(name: "  \(long) ", address: "5551234567")?.name.count, 40)
        XCTAssertEqual(QuickSendRules.recipient(name: " Grandma ", address: " 5551234567 ")?.address, "5551234567")
    }

    func testDuplicatesAreRefused() {
        let nana = QuickSendRules.recipient(name: "Nana", address: "Nana@Example.com")!
        let pop = QuickSendRules.recipient(name: "Pop", address: "(555) 123-4567")!
        let list = [nana, pop]
        XCTAssertNil(QuickSendRules.upserting(QuickSendRules.recipient(name: "N", address: "nana@example.com")!, into: list))
        XCTAssertNil(QuickSendRules.upserting(QuickSendRules.recipient(name: "P", address: "+1 555 123 4567")!, into: list))
        // Editing someone keeps their own address.
        var renamed = pop; renamed.name = "Grandpa"
        XCTAssertEqual(QuickSendRules.upserting(renamed, into: list)?.map(\.name), ["Nana", "Grandpa"])
    }

    func testTwelvePersonLimit() {
        var list: [QuickSendRecipient] = []
        for i in 0..<12 {
            list = QuickSendRules.upserting(QuickSendRules.recipient(name: "P\(i)", address: "55500000\(10 + i)")!, into: list)!
        }
        XCTAssertNil(QuickSendRules.upserting(QuickSendRules.recipient(name: "One more", address: "5559999999")!, into: list))
    }

    // MARK: 7 queue

    private func freshStore() -> ClipShareStore {
        let name = "test.clipShare.\(UUID().uuidString)"
        return ClipShareStore(defaults: UserDefaults(suiteName: name)!)
    }

    private let half = HalfInningKey(inning: 2, pitchingSide: "home")

    func testNobodyPickedQueuesNothing() {
        let store = freshStore()
        store.save(QuickSendRules.recipient(name: "Nana", address: "5551234567")!)
        store.toggle(store.recipients[0].id)   // unpick
        store.enqueue(momentId: "m1", gameId: "g", half: half, batterName: nil, pitchEventId: nil)
        XCTAssertTrue(store.queue.isEmpty)
    }

    func testNewPeopleArePickedAndClipsFollowListOrder() {
        let store = freshStore()
        store.save(QuickSendRules.recipient(name: "Nana", address: "5551234567")!)
        store.save(QuickSendRules.recipient(name: "Pop", address: "5557654321")!)
        store.enqueue(momentId: "m1", gameId: "g", half: half, batterName: "#12", pitchEventId: "p9")
        XCTAssertEqual(store.queue.first?.recipientIds, store.recipients.map(\.id))
        XCTAssertEqual(store.queue.first?.pitchEventId, "p9")
    }

    private func clip(_ id: String, _ at: TimeInterval, to ids: [String], game: String = "g") -> QueuedClip {
        QueuedClip(id: id, gameId: game, half: half, batterName: nil, pitchEventId: nil,
                   recipientIds: ids, queuedAt: Date(timeIntervalSince1970: at))
    }

    func testOneMessagePerPersonOldestFirst() {
        let nana = QuickSendRecipient(id: "n", name: "Nana", address: "5551234567")
        let pop = QuickSendRecipient(id: "p", name: "Pop", address: "5557654321")
        let clips = [clip("late", 20, to: ["n", "p"]), clip("early", 10, to: ["n"])]
        let messages = ClipSendQueue.pendingMessages(clips: clips, recipients: [nana, pop])
        XCTAssertEqual(messages.map(\.recipient.id), ["n", "p"])
        XCTAssertEqual(messages[0].clipIds, ["early", "late"])
        XCTAssertEqual(messages[1].clipIds, ["late"])
    }

    func testRemovedPeopleAreSkipped() {
        let nana = QuickSendRecipient(id: "n", name: "Nana", address: "5551234567")
        let messages = ClipSendQueue.pendingMessages(clips: [clip("c", 1, to: ["n", "gone"])], recipients: [nana])
        XCTAssertEqual(messages.map(\.recipient.id), ["n"])
        XCTAssertEqual(ClipSendQueue.pendingCount([clip("c", 1, to: ["gone"])], recipients: [nana]), 0)
    }

    func testSendNowScopesToOneClip() {
        let nana = QuickSendRecipient(id: "n", name: "Nana", address: "5551234567")
        let clips = [clip("a", 1, to: ["n"]), clip("b", 2, to: ["n"])]
        XCTAssertEqual(ClipSendQueue.pendingMessages(clips: clips, recipients: [nana], onlyClipId: "b").first?.clipIds, ["b"])
    }

    func testMarkSentTouchesOnlyThatPerson() {
        let clips = [clip("a", 1, to: ["n", "p"]), clip("b", 2, to: ["n"])]
        let sent = ClipSendQueue.markSent(clips, clipIds: ["a"], recipientId: "n", at: Date())
        XCTAssertFalse(sent[0].isPending(for: "n"))
        XCTAssertTrue(sent[0].isPending(for: "p"))
        XCTAssertFalse(sent[0].isFullySent)
        XCTAssertTrue(sent[1].isPending(for: "n"), "a clip not in the message stays waiting")
        let both = ClipSendQueue.markSent(sent, clipIds: ["a"], recipientId: "p", at: Date())
        XCTAssertTrue(both[0].isFullySent)
    }

    func testPruning() {
        let now = Date(timeIntervalSince1970: 10 * 86_400)
        var sentOld = clip("sentOld", now.timeIntervalSince1970 - 86_400, to: ["n"], game: "old")
        sentOld.sentAt["n"] = now
        let clips = [
            clip("current", 0, to: ["n"], game: "now"),
            clip("recentUnsent", now.timeIntervalSince1970 - 2 * 86_400, to: ["n"], game: "old"),
            clip("staleUnsent", now.timeIntervalSince1970 - 4 * 86_400, to: ["n"], game: "old"),
            sentOld
        ]
        XCTAssertEqual(ClipSendQueue.pruned(clips, currentGameId: "now", now: now).map(\.id), ["current", "recentUnsent"])
    }

    func testMessageBody() {
        var a = clip("a", 1, to: []); a.batterName = "#12"
        let b = clip("b", 2, to: [])
        XCTAssertEqual(ClipSendQueue.messageBody(gameName: "Reds vs. Hawks", clips: [a, b]),
                       "Reds vs. Hawks: Inning 2 · #12, Inning 2")
        XCTAssertEqual(ClipSendQueue.messageBody(gameName: nil, clips: [b]), "Inning 2")
    }

    // MARK: 8 banner

    func testBannerRule() {
        let next = HalfInningKey(inning: 2, pitchingSide: "away")
        XCTAssertFalse(ClipSendQueue.shouldOfferSend(previous: nil, current: half, pendingCount: 3))
        XCTAssertFalse(ClipSendQueue.shouldOfferSend(previous: half, current: half, pendingCount: 3))
        XCTAssertTrue(ClipSendQueue.shouldOfferSend(previous: half, current: next, pendingCount: 1))
        XCTAssertFalse(ClipSendQueue.shouldOfferSend(previous: half, current: next, pendingCount: 0))
    }
}
