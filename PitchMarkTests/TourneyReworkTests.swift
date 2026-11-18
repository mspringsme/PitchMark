//
//  TourneyReworkTests.swift
//  PitchMarkTests
//
//  Round Robin / Tourney Info rework (approved 2026-11-17): save/load of the
//  new fields, uniforms by day, games (order, times, field label, team
//  hand-off), a follower's own items, the shared copy, share links, the
//  text share, scouting, and the shared list.
//

import XCTest
import FirebaseFirestore
@testable import PitchMark

@MainActor
final class TourneyReworkTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func tourney(start: Date, end: Date) -> Tourney {
        var t = Tourney(now: start, calendar: cal)
        t.startDate = start
        t.endDate = end
        return t
    }

    // MARK: 1. Save and load

    func testNewFieldsSurviveSaveAndLoad() {
        var t = tourney(start: day(2027, 6, 5), end: day(2027, 6, 6))
        t.games = [TourneyGame(time: day(2027, 6, 5, 9), arriveAt: day(2027, 6, 5, 8), field: "7", opponent: "Hawks",
                               result: "W 7-3", ourTeamId: "us", opponentTeamId: "hawks"),
                   TourneyGame(stage: .bracket, time: day(2027, 6, 6, 10))]
        t.dailyUniforms = ["Whites", "", "Blacks"]
        t.metalCleatsAllowed = true
        t.gateFee = true
        t.gateFeeNotes = "$10"
        t.cashOnly = true
        t.food = [TourneyFoodItem(family: "Garcia", food: "Subs", done: true)]
        t.shareId = String(repeating: "b", count: 32)
        let back = Tourney(id: t.id, firestoreData: t.firestoreData)
        XCTAssertEqual(back, t)
        XCTAssertNil(back.games[1].arriveAt)
        XCTAssertNil(back.games[1].ourTeamId)

        var unshared = t
        unshared.shareId = nil
        XCTAssertTrue(unshared.firestoreData["shareId"] is NSNull, "Stop Sharing clears the saved field")
        XCTAssertNil(Tourney(id: "x", firestoreData: unshared.firestoreData).shareId)
    }

    func testOldPagesLoadIntoTheNewLayout() {
        let old = Tourney(id: "x", firestoreData: [
            "startDate": Timestamp(date: day(2027, 6, 5)),
            "gameDay": ["meetTime": Timestamp(date: day(2027, 6, 5, 7)), "parking": "Lot C",
                        "uniform": "Whites", "fieldName": "North", "notes": "Hi"],
            "costs": [["label": "Entry", "amount": 650]],
        ])
        XCTAssertEqual(old.dailyUniforms, ["Whites"], "the old single uniform becomes Day 1's")
        XCTAssertEqual(old.gameDay.fieldName, "North")
        XCTAssertEqual(old.gameDay.notes, "Hi")
        XCTAssertFalse(old.metalCleatsAllowed)
        XCTAssertFalse(old.gateFee)
        XCTAssertTrue(old.games.isEmpty)
        XCTAssertNil(old.gameDay.firestoreData["parking"], "removed fields aren't written back")

        let saved = Tourney(id: "y", firestoreData: [
            "dailyUniforms": ["Blacks"], "gameDay": ["uniform": "Whites"],
        ])
        XCTAssertEqual(saved.dailyUniforms, ["Blacks"], "a saved day 1 isn't overwritten by the old field")

        let games = Tourney(id: "z", firestoreData: ["games": [["opponent": "No time"], ["time": Timestamp(date: day(2027, 6, 5)), "stage": "weird"]]])
        XCTAssertEqual(games.games.count, 1, "a game with no time is dropped")
        XCTAssertEqual(games.games.first?.stage, .scheduled)
    }

    // MARK: 2. Uniforms

    func testUniformsAlwaysShowOneDayAndAddAndRemove() {
        var t = tourney(start: day(2027, 6, 5), end: day(2027, 6, 6))
        XCTAssertEqual(t.uniformDayCount, 1, "one blank day ready")
        XCTAssertEqual(t.uniform(day: 0), "")

        t.addUniformDay()
        XCTAssertEqual(t.uniformDayCount, 2, "+ adds a day after the blank one")
        t.setUniform("Whites", day: 0)
        t.setUniform("Blacks", day: 1)
        t.addUniformDay()
        XCTAssertEqual(t.dailyUniforms, ["Whites", "Blacks", ""])

        t.removeUniformDay(0)
        XCTAssertEqual(t.dailyUniforms, ["Blacks", ""], "later days move up")
        t.removeUniformDay(9)
        XCTAssertEqual(t.dailyUniforms.count, 2, "removing a missing day does nothing")
        t.removeUniformDay(0); t.removeUniformDay(0)
        XCTAssertEqual(t.uniformDayCount, 1, "never fewer than one row")

        t.setUniform("Grays", day: 3)
        XCTAssertEqual(t.dailyUniforms, ["", "", "", "Grays"], "setting a later day fills the gap")
    }

    func testUniformDaysKeepTheirNumberWhenDatesMove() {
        var t = tourney(start: day(2027, 6, 5), end: day(2027, 6, 6))
        t.dailyUniforms = ["Whites", "Blacks", "Reds"]
        XCTAssertEqual(t.date(ofDay: 1, calendar: cal), day(2027, 6, 6))
        XCTAssertNil(t.date(ofDay: 2, calendar: cal), "a day past the end has no date, but keeps its uniform")
        t.startDate = day(2027, 7, 10); t.endDate = day(2027, 7, 12)
        XCTAssertEqual(t.uniform(day: 1), "Blacks")
        XCTAssertEqual(t.date(ofDay: 2, calendar: cal), day(2027, 7, 12))
    }

    // MARK: 3. Games

    func testGamesListScheduledThenBracketEachByTime() {
        let a = TourneyGame(stage: .bracket, time: day(2027, 6, 6, 9), opponent: "B1")
        let b = TourneyGame(time: day(2027, 6, 5, 13), opponent: "S2")
        let c = TourneyGame(time: day(2027, 6, 5, 9), opponent: "S1")
        let d = TourneyGame(stage: .bracket, time: day(2027, 6, 5, 18), opponent: "B0")
        XCTAssertEqual(TourneyGame.sorted([a, b, c, d]).map(\.opponent), ["S1", "S2", "B0", "B1"])
    }

    func testNewGameTimesAndArriveDefault() {
        let start = day(2027, 6, 5, 15)
        XCTAssertEqual(TourneyGame.nextStart(after: [], tourneyStart: start, calendar: cal), day(2027, 6, 5, 8),
                       "8 AM on day one")
        let games = [TourneyGame(time: day(2027, 6, 5, 9)), TourneyGame(time: day(2027, 6, 5, 13))]
        XCTAssertEqual(TourneyGame.nextStart(after: games, tourneyStart: start, calendar: cal), day(2027, 6, 5, 14, 30),
                       "90 minutes after the latest game")
        XCTAssertEqual(TourneyGame(time: day(2027, 6, 5, 9)).suggestedArriveAt, day(2027, 6, 5, 8))
    }

    func testFieldIsShownWithTheWordField() {
        XCTAssertEqual(TourneyGame(time: Date(), field: "7").fieldLabel, "Field 7")
        XCTAssertEqual(TourneyGame(time: Date(), field: " North 2 ").fieldLabel, "Field North 2")
        XCTAssertEqual(TourneyGame(time: Date(), field: "Field 7").fieldLabel, "Field 7", "not doubled")
        XCTAssertEqual(TourneyGame(time: Date(), field: "field 3").fieldLabel, "field 3")
        XCTAssertEqual(TourneyGame(time: Date(), field: "  ").fieldLabel, "")
        XCTAssertEqual(TourneyGame(time: Date(), field: "7", opponent: "Hawks").summary, "vs Hawks · Field 7")
        XCTAssertEqual(TourneyGame(time: Date(), opponent: "Hawks").summary, "vs Hawks")
        XCTAssertEqual(TourneyGame(time: Date()).summary, "")
    }

    func testStartGameHandsOnlyMyOwnTeams() {
        let game = TourneyGame(time: day(2027, 6, 5, 9), opponent: " Hawks ", ourTeamId: "us", opponentTeamId: "hawks")
        let mine = game.newGameSeed(myTeamIds: ["us", "hawks", "other"])
        XCTAssertEqual(mine.opponentName, "Hawks")
        XCTAssertEqual(mine.date, day(2027, 6, 5, 9))
        XCTAssertEqual(mine.ourTeamId, "us")
        XCTAssertEqual(mine.opponentTeamId, "hawks")

        let follower = game.newGameSeed(myTeamIds: ["mine"])
        XCTAssertNil(follower.ourTeamId, "a shared tourney's team isn't this user's")
        XCTAssertNil(follower.opponentTeamId)
        XCTAssertEqual(follower.opponentName, "Hawks", "the name and time still come through")

        let typed = TourneyGame(time: day(2027, 6, 5, 9), opponent: "Winner of G3").newGameSeed(myTeamIds: ["us"])
        XCTAssertNil(typed.ourTeamId)
        XCTAssertEqual(typed.opponentName, "Winner of G3")
    }

    // MARK: 4. A follower's own items

    func testAFollowersItemsStayOnTheirOwnRecord() async throws {
        let store = TourneyStore(inMemory: true)
        let id = String(repeating: "c", count: 32)
        try await store.follow(linkOrId: id)
        store.addMyItem("  Chairs ", to: id)
        store.addMyItem("   ", to: id)
        store.addMyItem("Ice", to: "d" + String(repeating: "c", count: 31))
        XCTAssertEqual(store.followed.first?.myItems.map(\.text), ["Chairs"], "trimmed; blank and unknown ignored")

        let itemId = try XCTUnwrap(store.followed.first?.myItems.first?.id)
        store.removeMyItem(itemId, from: id)
        XCTAssertEqual(store.followed.first?.myItems, [])

        var coach = Tourney()
        coach.checklist = [TourneyChecklistItem(text: "Sunscreen")]
        coach.shareId = id
        let shared = coach.sharedData(ownerUid: "coach")
        XCTAssertNil(shared["myItems"], "the shared copy carries no follower's items")
        XCTAssertEqual((shared["checklist"] as? [[String: Any]])?.count, 1, "the coach's items are shared")
    }

    // MARK: 5. The shared copy

    func testTheSharedCopyNamesTheOwnerAndDropsBookkeeping() {
        var t = Tourney()
        t.name = "Summer Slam"
        t.archivedAt = Date()
        t.shareId = String(repeating: "e", count: 32)
        let data = t.sharedData(ownerUid: "coach1")
        XCTAssertEqual(data["ownerUid"] as? String, "coach1")
        XCTAssertNil(data["archivedAt"])
        XCTAssertNil(data["shareId"])
        XCTAssertEqual(Tourney(id: "x", firestoreData: data).name, "Summer Slam", "reads back as the same page")
    }

    // MARK: 6. Share links

    func testShareLinksAreAcceptedOnlyInTheRightShape() {
        let id = "0123456789abcdef0123456789abcdef"
        XCTAssertEqual(TourneyShareLink.shareId(from: "https://pitchmark-fb9f8.web.app/tourney/\(id)"), id)
        XCTAssertEqual(TourneyShareLink.shareId(from: "  https://pitchmark-fb9f8.firebaseapp.com/tourney/\(id.uppercased()) "), id)
        XCTAssertEqual(TourneyShareLink.shareId(from: "pitchmark://tourney/\(id)"), id)
        XCTAssertEqual(TourneyShareLink.shareId(from: id), id, "a bare pasted code")
        XCTAssertEqual(TourneyShareLink.shareId(from: TourneyShareLink.url(for: id).absoluteString), id, "round trip")

        XCTAssertNil(TourneyShareLink.shareId(from: "https://evil.example.com/tourney/\(id)"), "other sites")
        XCTAssertNil(TourneyShareLink.shareId(from: "http://pitchmark-fb9f8.web.app/tourney/\(id)"), "not https")
        XCTAssertNil(TourneyShareLink.shareId(from: "https://pitchmark-fb9f8.web.app/signin/live/\(id)"), "wrong path")
        XCTAssertNil(TourneyShareLink.shareId(from: "https://pitchmark-fb9f8.web.app/tourney/\(id)/x"))
        XCTAssertNil(TourneyShareLink.shareId(from: "https://pitchmark-fb9f8.web.app/tourney/abc123"), "too short")
        XCTAssertNil(TourneyShareLink.shareId(from: String(repeating: "g", count: 32)), "not hex")
        XCTAssertNil(TourneyShareLink.shareId(from: String(repeating: "a", count: 65)), "too long")
        XCTAssertNil(TourneyShareLink.shareId(from: "pitchmark://join/\(id)"))
        XCTAssertNil(TourneyShareLink.shareId(from: ""))

        let fresh = TourneyShareLink.newShareId()
        XCTAssertEqual(fresh.count, 64)
        XCTAssertEqual(TourneyShareLink.shareId(from: fresh), fresh, "new ids pass the same check the rules make")
        XCTAssertNotEqual(fresh, TourneyShareLink.newShareId())
    }

    // MARK: 7. Text share

    private func fullForText() -> Tourney {
        var t = tourney(start: day(2027, 6, 5), end: day(2027, 6, 6))
        t.name = "Summer Slam"
        t.venue = TourneyPlace(name: "Dreams Park", address: "1 Field Rd", latitude: 42.6, longitude: -74.9)
        t.games = [TourneyGame(stage: .bracket, time: day(2027, 6, 6, 10), field: "1", opponent: "Seed 4"),
                   TourneyGame(time: day(2027, 6, 5, 9), arriveAt: day(2027, 6, 5, 8), field: "7", opponent: "Hawks", result: "W 7-3")]
        t.gameDay.fieldName = "North complex"
        t.dailyUniforms = ["Whites", "", "Reds"]
        t.checklist = [TourneyChecklistItem(text: "Chairs")]
        t.metalCleatsAllowed = true
        t.gateFee = true
        t.gateFeeNotes = "$10 per adult"
        t.cashOnly = true
        t.food = [TourneyFoodItem(family: "Garcia", food: "Subs", done: true), TourneyFoodItem(family: "Lee"), TourneyFoodItem()]
        t.hotels = [TourneyHotel(place: TourneyPlace(name: "Lakeside Inn"), nightlyRate: 139)]
        t.links = [TourneyLink(title: "Brackets", urlString: "example.com/b")]
        t.notes = "Have fun"
        return t
    }

    func testTextShareCoversEverySection() {
        let text = TourneyShareText.text(for: fullForText(), calendar: cal)
        for piece in ["🏆 Summer Slam", "📅 Jun 5 - 6, 2027", "📍 Dreams Park, 1 Field Rd",
                      "GAMES\nScheduled:\nSat Jun 5, 9:00 AM · vs Hawks · Field 7 · arrive 8:00 AM · W 7-3\nBracket:\nSun Jun 6, 10:00 AM · vs Seed 4 · Field 1",
                      "Field / complex: North complex",
                      "UNIFORMS\nDay 1 (Sat Jun 5): Whites\nDay 3: Reds",
                      "GENERAL INFO\nMetal cleats allowed\nChairs",
                      "GATE\nGate fee: $10 per adult\nCash only",
                      "TOURNAMENT FOOD\n✅ Garcia: Subs\n• Lee: TBD",
                      "HOTELS\n• Lakeside Inn · $139/night",
                      "LINKS\nBrackets: https://example.com/b", "NOTES\nHave fun"] {
            XCTAssertTrue(text.contains(piece), "missing:\n\(piece)\nin:\n\(text)")
        }
        XCTAssertFalse(text.contains("•  Chairs"), "general info items have no bullets")
        XCTAssertFalse(text.contains("Day 2"), "a blank day is left out")
        XCTAssertFalse(text.contains("Meet:") || text.contains("Parking") || text.contains("COSTS"), "removed sections")
    }

    func testTextShareLeavesOutOffAndEmptySections() {
        var off = TourneyShareOptions()
        off.games = false; off.uniforms = false; off.gateFee = false; off.food = false
        off.hotels = false; off.links = false; off.notes = false; off.gameDay = false
        let some = TourneyShareText.text(for: fullForText(), options: off, calendar: cal)
        for gone in ["GAMES", "UNIFORMS", "GATE", "TOURNAMENT FOOD", "HOTELS", "LINKS", "NOTES", "GAME DAY"] {
            XCTAssertFalse(some.contains(gone), "\(gone) was turned off")
        }
        XCTAssertTrue(some.contains("GENERAL INFO"))

        let bare = TourneyShareText.text(for: tourney(start: day(2027, 6, 5), end: day(2027, 6, 5)), calendar: cal)
        for gone in ["GAMES", "UNIFORMS", "GATE", "TOURNAMENT FOOD", "HOTELS", "LINKS", "NOTES", "GAME DAY", "📍"] {
            XCTAssertFalse(bare.contains(gone), "\(gone) is empty and left out")
        }
        XCTAssertTrue(bare.contains("GENERAL INFO\nNo metal cleats"), "cleats always say which")

        var onlyNotes = tourney(start: day(2027, 6, 5), end: day(2027, 6, 5))
        onlyNotes.gateFeeNotes = "Free for kids"
        XCTAssertTrue(TourneyShareText.text(for: onlyNotes, calendar: cal).contains("GATE\nFree for kids"),
                      "gate notes show without the fee toggle")
    }

    // MARK: 8. Scouting

    func testScoutingSortsDatedFirstThenByName() {
        var a = TourneyProspect(name: "zeta"); a.startDate = day(2027, 8, 1)
        var b = TourneyProspect(name: "Alpha"); b.startDate = day(2027, 7, 1)
        let c = TourneyProspect(name: "beta")
        let d = TourneyProspect(name: "Able")
        XCTAssertEqual(TourneyProspect.sortedForList([a, c, d, b]).map(\.name), ["Alpha", "zeta", "Able", "beta"])
    }

    func testScoutingDatesAndSaveLoad() {
        var p = TourneyProspect(name: "Fall Classic")
        XCTAssertEqual(p.dateText(calendar: cal), "Dates TBD")
        p.startDate = day(2027, 9, 10)
        XCTAssertEqual(p.dateText(calendar: cal), "Sep 10, 2027")
        p.endDate = day(2027, 9, 12)
        XCTAssertEqual(p.dateText(calendar: cal), "Sep 10 - 12, 2027")
        p.organizer = "USSSA"; p.cost = "$595"; p.distance = "45 mi"; p.location = "Ocala, FL"; p.notes = "10U"
        p.links = [TourneyLink(title: "Site", urlString: "example.com")]
        XCTAssertEqual(TourneyProspect(id: p.id, firestoreData: p.firestoreData), p)

        let bad = TourneyProspect(id: "x", firestoreData: [
            "startDate": Timestamp(date: day(2027, 9, 10)), "endDate": Timestamp(date: day(2027, 9, 1)),
        ])
        XCTAssertEqual(bad.endDate, day(2027, 9, 10), "the end is never before the start")
        let noStart = TourneyProspect(id: "y", firestoreData: ["endDate": Timestamp(date: day(2027, 9, 1))])
        XCTAssertNil(noStart.endDate, "no end without a start")
    }

    func testStartingATourneyPageFromScouting() {
        var p = TourneyProspect(name: " Fall Classic ")
        p.organizer = "USSSA"; p.cost = "$595"; p.location = "Ocala, FL"; p.notes = "10U"
        p.startDate = day(2027, 9, 10); p.endDate = day(2027, 9, 12)
        p.links = [TourneyLink(title: "Site", urlString: "example.com")]
        let t = p.makeTourney(now: day(2027, 1, 1), calendar: cal)
        XCTAssertEqual(t.name, "Fall Classic")
        XCTAssertEqual(t.startDate, day(2027, 9, 10))
        XCTAssertEqual(t.endDate, day(2027, 9, 12))
        XCTAssertEqual(t.venue.address, "Ocala, FL")
        XCTAssertEqual(t.links, p.links)
        XCTAssertEqual(t.notes, "Organizer: USSSA\nCost: $595\n10U")

        let undated = TourneyProspect(name: "TBD").makeTourney(now: day(2027, 6, 2), calendar: cal)
        XCTAssertEqual(undated.startDate, day(2027, 6, 5), "no dates = the usual coming Saturday")
    }

    // MARK: 9. The shared list and sharing

    func testFollowingRefusesBadLinksAndOwnTourneysAndDoesntDouble() async throws {
        let store = TourneyStore(inMemory: true)
        let id = String(repeating: "f", count: 32)
        do {
            try await store.follow(linkOrId: "not a link")
            XCTFail("a bad link is refused")
        } catch let error as TourneyStore.FollowError {
            XCTAssertEqual(error, .badLink)
        }

        var mine = Tourney()
        mine.shareId = id
        store.save(mine)
        do {
            try await store.follow(linkOrId: TourneyShareLink.url(for: id).absoluteString)
            XCTFail("your own tourney is refused")
        } catch let error as TourneyStore.FollowError {
            XCTAssertEqual(error, .ownTourney)
        }

        let other = String(repeating: "1", count: 32)
        try await store.follow(linkOrId: other)
        try await store.follow(linkOrId: "pitchmark://tourney/\(other)")
        XCTAssertEqual(store.followed.map(\.id), [other], "the same link twice isn't doubled")
        store.unfollow(other)
        XCTAssertTrue(store.followed.isEmpty)
    }

    func testStartAndStopSharing() {
        let store = TourneyStore(inMemory: true)
        let t = Tourney()
        store.save(t)
        let url = store.startSharing(t)
        let shareId = try? XCTUnwrap(store.tourney(id: t.id)?.shareId)
        XCTAssertEqual(TourneyShareLink.shareId(from: url.absoluteString), shareId)
        XCTAssertEqual(store.startSharing(store.tourney(id: t.id)!), url, "sharing again keeps the same link")
        store.stopSharing(store.tourney(id: t.id)!)
        XCTAssertNil(store.tourney(id: t.id)?.shareId)
        XCTAssertNotEqual(store.startSharing(store.tourney(id: t.id)!), url, "sharing after stopping is a new link")
    }

    func testScoutingStoreArchivesWithoutDeleting() {
        let store = TourneyStore(inMemory: true)
        var p = TourneyProspect(name: "A")
        p.startDate = day(2027, 9, 1)
        store.save(p)
        store.save(TourneyProspect(name: "B"))
        store.setArchived(p, true)
        XCTAssertEqual(store.activeProspects.map(\.name), ["B"])
        XCTAssertEqual(store.archivedProspects.map(\.name), ["A"])
        XCTAssertEqual(store.prospects.count, 2)
    }
}
