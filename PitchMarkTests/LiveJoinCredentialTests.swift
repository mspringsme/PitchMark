//
//  LiveJoinCredentialTests.swift
//  PitchMarkTests
//
//  Batch 4, fix G1 (2026-10-31): a partner's presence must name the code
//  or invite it joined with, and must still do so after leaving and
//  re-entering the game.
//

import XCTest
@testable import PitchMark

@MainActor
final class LiveJoinCredentialTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "LiveJoinCredentialTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    /// A typed join code goes on presence as `joinCode`, an invite link as
    /// `inviteToken` - the two fields the rules accept.
    func testPresenceNamesTheCredential() {
        let code = LiveJoinCredential(kind: .joinCode, value: "ABC123")
        let fields = LiveJoinCredential.presenceFields(uid: "partner", credential: code, timestamps: ["lastSeenAt": 1])
        XCTAssertEqual(fields["uid"] as? String, "partner")
        XCTAssertEqual(fields["joinCode"] as? String, "ABC123")
        XCTAssertNil(fields["inviteToken"])
        XCTAssertEqual(fields["lastSeenAt"] as? Int, 1)

        let invite = LiveJoinCredential(kind: .inviteToken, value: "tok")
        let inviteFields = LiveJoinCredential.presenceFields(uid: "partner", credential: invite, timestamps: [:])
        XCTAssertEqual(inviteFields["inviteToken"] as? String, "tok")
        XCTAssertNil(inviteFields["joinCode"])
    }

    /// The owner needs no credential, and none is invented.
    func testOwnerPresenceCarriesNoCredential() {
        let fields = LiveJoinCredential.presenceFields(uid: "owner", credential: nil, timestamps: [:])
        XCTAssertEqual(Set(fields.keys), ["uid"])
    }

    /// Blank codes are not credentials.
    func testBlankIsNotACredential() {
        XCTAssertNil(LiveJoinCredential(kind: .joinCode, value: "  "))
        XCTAssertNil(LiveJoinCredential(kind: .joinCode, value: nil))
        XCTAssertEqual(LiveJoinCredential(kind: .joinCode, value: " ABC ")?.value, "ABC")
    }

    /// Leaving the game deletes presence; re-entering recreates it. The
    /// device remembers each room's credential until the session is over.
    func testRememberedPerRoomUntilForgotten() {
        let code = LiveJoinCredential(kind: .joinCode, value: "ABC123")
        let invite = LiveJoinCredential(kind: .inviteToken, value: "tok")
        LiveJoinCredential.remember(code, for: "live1", in: defaults)
        LiveJoinCredential.remember(invite, for: "live2", in: defaults)
        XCTAssertEqual(LiveJoinCredential.remembered(for: "live1", in: defaults), code)
        XCTAssertEqual(LiveJoinCredential.remembered(for: "live2", in: defaults), invite)
        XCTAssertNil(LiveJoinCredential.remembered(for: "live3", in: defaults))

        LiveJoinCredential.remember(nil, for: "live1", in: defaults)
        XCTAssertEqual(LiveJoinCredential.remembered(for: "live1", in: defaults), code, "nothing new keeps the old one")

        LiveJoinCredential.forget(liveId: "live1", in: defaults)
        XCTAssertNil(LiveJoinCredential.remembered(for: "live1", in: defaults))
        XCTAssertEqual(LiveJoinCredential.remembered(for: "live2", in: defaults), invite)
    }

    /// Re-entering on another device reads the credential from the
    /// joined-session bookmark; bookmarks from older builds have none.
    func testBookmarkCarriesTheCredential() {
        let session = JoinedLiveSession(liveId: "live1", data: ["ownerUid": "owner", "joinCode": "ABC123"])
        XCTAssertEqual(session?.credential, LiveJoinCredential(kind: .joinCode, value: "ABC123"))

        let viaLink = JoinedLiveSession(liveId: "live1", data: ["ownerUid": "owner", "inviteToken": "tok"])
        XCTAssertEqual(viaLink?.credential, LiveJoinCredential(kind: .inviteToken, value: "tok"))

        let old = JoinedLiveSession(liveId: "live1", data: ["ownerUid": "owner"])
        XCTAssertNotNil(old)
        XCTAssertNil(old?.credential)
    }
}
