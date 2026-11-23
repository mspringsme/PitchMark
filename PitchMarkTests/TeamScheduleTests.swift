//
//  TeamScheduleTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-22 (team schedule, unit): who coaches and schedules,
//  invite links and codes, the tourney's team / Canceled fields, and the
//  store's edit rights and moving a tourney to a team.
//

import XCTest
@testable import PitchMark

final class TeamScheduleTests: XCTestCase {
    private func team(_ creator: String = "coach") -> Team {
        var t = Team(name: "Reds", createdByUid: creator)
        t.id = "reds"
        return t
    }

    private func member(_ uid: String, _ roles: [TeamRole]) -> TeamMembership {
        TeamMembership(id: uid, uid: uid, roles: roles, addedByUid: "coach")
    }

    func testWhoCoachesAndWhoSchedules() {
        let reds = team()
        XCTAssertTrue(TeamAccessRules.coaches(team: reds, membership: member("coach", [.coach]), uid: "coach"))
        XCTAssertFalse(TeamAccessRules.coaches(team: reds, membership: member("helper", [.assistant]), uid: "helper"),
                       "a Scheduler's Home doesn't get the coach's roster")
        XCTAssertFalse(TeamAccessRules.coaches(team: reds, membership: member("fam", [.parent]), uid: "fam"))

        XCTAssertTrue(TeamAccessRules.schedules(team: reds, membership: nil, uid: "coach"), "the creator")
        XCTAssertTrue(TeamAccessRules.schedules(team: reds, membership: member("helper", [.assistant]), uid: "helper"))
        XCTAssertFalse(TeamAccessRules.schedules(team: reds, membership: member("fam", [.parent]), uid: "fam"))

        XCTAssertEqual(member("helper", [.assistant]).roleTitle, "Scheduler")
        XCTAssertEqual(member("fam", [.parent]).roleTitle, "Family")
    }

    func testInvitesLastAWeekOrASeason() {
        XCTAssertEqual(TeamAccessRules.inviteLifetime(multiUse: false), 7 * 86_400)
        XCTAssertEqual(TeamAccessRules.inviteLifetime(multiUse: true), 180 * 86_400)
        XCTAssertEqual(TeamAccessRules.memberName(displayName: " Jo Garcia ", email: "jo@x.com"), "Jo Garcia")
        XCTAssertEqual(TeamAccessRules.memberName(displayName: nil, email: "jo@x.com"), "jo@x.com")
        XCTAssertNil(TeamAccessRules.memberName(displayName: "", email: nil))
    }

    func testReadingALinkOrCode() {
        XCTAssertEqual(TeamAccessRules.inviteToken(from: "abcd2345efgh"), "ABCD2345EFGH", "typed in lowercase")
        XCTAssertEqual(TeamAccessRules.inviteToken(from: "https://pitchmark-fb9f8.web.app/team/ABCD2345EFGH"), "ABCD2345EFGH")
        XCTAssertNil(TeamAccessRules.inviteToken(from: "abc"))

        let link = TeamAccessRules.inviteLink("ABCD2345EFGH")
        XCTAssertEqual(TeamAccessRules.inviteToken(fromURL: link), "ABCD2345EFGH")
        XCTAssertEqual(TeamAccessRules.inviteToken(fromURL: URL(string: "pitchmark://team/ABCD2345EFGH")!), "ABCD2345EFGH",
                       "the fallback page's link")
        XCTAssertNil(TeamAccessRules.inviteToken(fromURL: URL(string: "https://pitchmark-fb9f8.web.app/tourney/abc")!))
    }

    func testTheTeamAndCanceledAreSavedAndRead() {
        var t = Tourney()
        t.teamId = "reds"
        t.shareOwnerUid = "coach"
        t.games = [TourneyGame(time: Date(timeIntervalSince1970: 1_000), opponent: "Hawks")]
        t.games[0].canceled = true
        let back = Tourney(id: t.id, firestoreData: t.firestoreData)
        XCTAssertEqual(back.teamId, "reds")
        XCTAssertEqual(back.shareOwnerUid, "coach")
        XCTAssertTrue(back.games[0].canceled)

        let shared = t.sharedData(ownerUid: "helper")
        XCTAssertEqual(shared["ownerUid"] as? String, "coach", "the link copy keeps its owner when a Scheduler saves")
        XCTAssertEqual(shared["teamId"] as? String, "reds")
        XCTAssertNil(shared["shareOwnerUid"])
        XCTAssertFalse(TourneyGame(time: Date()).canceled)
    }

    @MainActor
    func testTheStoreKnowsWhoEditsAndMovesATourneyToATeam() {
        let store = TourneyStore(inMemory: true)
        store.startTeams([.init(id: "reds", name: "Reds", canEdit: true),
                          .init(id: "hawks", name: "Hawks", canEdit: false)])
        XCTAssertEqual(store.editableTeams.map(\.id), ["reds"])

        var own = Tourney()
        own.name = "Summer Slam"
        store.save(own)
        XCTAssertTrue(store.canEdit(own))
        XCTAssertEqual(store.tourneys.map(\.id), [own.id])

        own.teamId = "reds"
        store.save(own)
        XCTAssertTrue(store.tourneys.isEmpty, "moved off the coach's own list")
        XCTAssertEqual(store.teamTourneys.map(\.id), [own.id])
        XCTAssertEqual(store.active.map(\.id), [own.id], "still in the coach's list, once")
        XCTAssertTrue(store.canEdit(own))

        var theirs = Tourney()
        theirs.teamId = "hawks"
        store.save(theirs)
        XCTAssertFalse(store.canEdit(theirs), "a Family sees it read-only")
        XCTAssertEqual(store.teamName("hawks"), "Hawks")
    }
}
