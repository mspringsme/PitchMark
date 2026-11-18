//
//  TourneyTests.swift
//  PitchMarkTests
//
//  Tourney Info (approved 2026-11-16, 2026-11-17): save/load, directions
//  links, web links, hotel totals, date labels and list order, meet spot
//  geometry, bullet lists and mark picking. The 2026-11-17 rework (games,
//  uniforms, sharing, scouting, share text) is TourneyReworkTests.swift.
//

import XCTest
import FirebaseFirestore
@testable import PitchMark

@MainActor
final class TourneyTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func fullTourney() -> Tourney {
        var t = Tourney(now: day(2027, 6, 1), calendar: cal)
        t.name = "Summer Slam"
        t.startDate = day(2027, 6, 5)
        t.endDate = day(2027, 6, 7)
        t.venue = TourneyPlace(name: "Dreams Park", address: "1 Field Rd", latitude: 42.6, longitude: -74.9)
        t.gameDay.fieldName = "Field 7"
        t.gameDay.notes = "Bring two bats"
        t.meetSpots = [TourneyMeetSpot(title: "Warmups", centerLatitude: 42.6, centerLongitude: -74.9,
                                       latitudeDelta: 0.004, longitudeDelta: 0.003,
                                       marks: [TourneyMark(kind: .pin, x: 0.25, y: 0.75, text: "Here"),
                                               TourneyMark(kind: .arrow, x: 0.1, y: 0.2, x2: 0.4, y2: 0.6, colorHex: "#FF3B30", size: 3),
                                               TourneyMark(kind: .bullets, x: 0.6, y: 0.6, text: "a\nb")])]
        t.links = [TourneyLink(title: "Schedule", urlString: "example.com/s")]
        t.hotels = [TourneyHotel(place: TourneyPlace(name: "Lakeside Inn", address: "12 Main"), phone: "555-123-4567",
                                 link: "lakeside.com", nightlyRate: 139, nights: 2, bookingCode: "SLAM",
                                 bookBy: day(2027, 5, 15), notes: "Pool")]
        t.checklist = [TourneyChecklistItem(text: "Cleats", done: true)]
        t.notes = "Have fun"
        t.games = [TourneyGame(time: day(2027, 6, 5, 9), arriveAt: day(2027, 6, 5, 8), field: "7", opponent: "Hawks",
                               result: "W 7-3", ourTeamId: "us", opponentTeamId: "hawks"),
                   TourneyGame(stage: .bracket, time: day(2027, 6, 6, 10), field: "Field 1", opponent: "Seed 4")]
        t.dailyUniforms = ["Whites", "", "Blacks"]
        t.metalCleatsAllowed = true
        t.gateFee = true
        t.gateFeeNotes = "$10 per adult"
        t.cashOnly = true
        t.food = [TourneyFoodItem(family: "Garcia", food: "Sandwiches", done: true), TourneyFoodItem(family: "Lee")]
        t.shareId = String(repeating: "a", count: 32)
        return t
    }

    /// True when any array anywhere in `value` holds an array directly.
    private func hasNestedArray(_ value: Any) -> Bool {
        if let array = value as? [Any] {
            return array.contains { $0 is [Any] } || array.contains(where: hasNestedArray)
        }
        if let map = value as? [String: Any] { return map.values.contains(where: hasNestedArray) }
        return false
    }

    // MARK: 1. Save and load

    func testATourneySurvivesSaveAndLoadWithEverySection() {
        let t = fullTourney()
        let back = Tourney(id: t.id, firestoreData: t.firestoreData)
        XCTAssertEqual(back, t)
        XCTAssertFalse(hasNestedArray(t.firestoreData), "Firestore can't store an array inside an array")

        var archived = t
        archived.archivedAt = day(2027, 7, 1)
        XCTAssertEqual(Tourney(id: t.id, firestoreData: archived.firestoreData).archivedAt, day(2027, 7, 1))
        XCTAssertTrue(t.firestoreData["archivedAt"] is NSNull, "un-archiving clears the field")
    }

    func testDamagedRecordsLoadSafely() {
        let t = Tourney(id: "x", firestoreData: [
            "name": 5,
            "startDate": Timestamp(date: day(2027, 6, 5)),
            "endDate": Timestamp(date: day(2027, 6, 1)),   // before the start
            "venue": ["name": "Park", "latitude": 42.0],     // half a pin
            "meetSpots": [["centerLatitude": 1, "centerLongitude": 2, "latitudeDelta": 0, "longitudeDelta": 1],
                          ["title": "no region"]],
            "costs": [["label": "Fee", "amount": -20, "basis": "nonsense"]],
            "checklist": [["text": "  "], ["text": "Glove"]],
            "hotels": [["nights": -3]],
            "links": "not a list",
        ])
        XCTAssertEqual(t.name, "")
        XCTAssertEqual(t.endDate, t.startDate, "end is never before start")
        XCTAssertNil(t.venue.coordinate, "half a pin is no pin")
        XCTAssertEqual(t.venue.name, "Park")
        XCTAssertTrue(t.meetSpots.isEmpty, "a spot needs a real region")
        XCTAssertEqual(t.checklist.map(\.text), ["Glove"])
        XCTAssertEqual(t.hotels.first?.nights, 0)
        XCTAssertTrue(t.links.isEmpty)

        let marks = [["kind": "pin", "x": 0.5, "y": 0.5, "size": 9], ["kind": "blob", "x": 1, "y": 1], ["kind": "text"]]
        let spot = TourneyMeetSpot(firestoreData: ["centerLatitude": 1, "centerLongitude": 2,
                                                   "latitudeDelta": 0.01, "longitudeDelta": 0.01, "marks": marks])
        XCTAssertEqual(spot?.marks.count, 1, "unknown kinds and marks with no position are dropped")
        XCTAssertEqual(spot?.marks.first?.size, 3, "size is kept to 1...3")
    }

    // MARK: 2. Directions

    func testDirectionsGoToThePinWhenThereIsOne() throws {
        let pinned = TourneyPlace(name: "Dreams Park", address: "1 Field Rd", latitude: 42.5, longitude: -74.25)
        let apple = try XCTUnwrap(TourneyMapApp.apple.directionsURL(to: pinned)).absoluteString
        XCTAssertTrue(apple.hasPrefix("https://maps.apple.com/"))
        XCTAssertTrue(apple.contains("daddr=42.5,-74.25"), apple)
        let google = try XCTUnwrap(TourneyMapApp.google.directionsURL(to: pinned)).absoluteString
        XCTAssertTrue(google.hasPrefix("https://www.google.com/maps/dir/"))
        XCTAssertTrue(google.contains("destination=42.5,-74.25"), google)
        let waze = try XCTUnwrap(TourneyMapApp.waze.directionsURL(to: pinned)).absoluteString
        XCTAssertTrue(waze.contains("ll=42.5,-74.25"), waze)
        XCTAssertTrue(waze.contains("navigate=yes"))
    }

    func testDirectionsSearchTheNameAndAddressWithNoPin() throws {
        let typed = TourneyPlace(name: "Dreams Park", address: "1 Field Rd")
        for app in TourneyMapApp.allCases {
            let url = try XCTUnwrap(app.directionsURL(to: typed), app.title)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertTrue(query.contains { $0.value == "Dreams Park, 1 Field Rd" }, "\(app.title): \(url)")
        }
        for app in TourneyMapApp.allCases {
            XCTAssertNil(app.directionsURL(to: TourneyPlace(name: "  ", address: "")), "nowhere to go")
        }
    }

    // MARK: 3. Web links

    func testWebLinksGetHttpsAndRefuseNonWebText() {
        XCTAssertEqual(TourneyLink.normalizedURL(" example.com/schedule ")?.absoluteString, "https://example.com/schedule")
        XCTAssertEqual(TourneyLink.normalizedURL("http://example.com")?.absoluteString, "http://example.com")
        XCTAssertEqual(TourneyLink.normalizedURL("HTTPS://Example.com/x")?.host?.lowercased(), "example.com")
        XCTAssertNil(TourneyLink.normalizedURL(""))
        XCTAssertNil(TourneyLink.normalizedURL("not a link"))
        XCTAssertNil(TourneyLink.normalizedURL("schedule"), "a word isn't a site")
        XCTAssertNil(TourneyLink.normalizedURL("ftp://example.com"))
        XCTAssertNil(TourneyLink.normalizedURL("javascript:alert(1)"))
        XCTAssertEqual(TourneyLink(title: "", urlString: "example.com/x").displayTitle, "example.com")
        XCTAssertEqual(TourneyLink(title: " Brackets ", urlString: "example.com").displayTitle, "Brackets")
    }

    // MARK: 4. Costs and hotel totals

    func testHotelStayTotalNeedsRateAndNights() {
        XCTAssertEqual(TourneyHotel(nightlyRate: 139.5, nights: 3).stayTotal, 418.5)
        XCTAssertNil(TourneyHotel(nightlyRate: 139, nights: 0).stayTotal)
        XCTAssertNil(TourneyHotel(nightlyRate: nil, nights: 2).stayTotal)
        XCTAssertEqual(TourneyHotel(phone: "(555) 123-4567").phoneURL?.absoluteString, "tel:5551234567")
        XCTAssertNil(TourneyHotel(phone: "ask desk").phoneURL)
    }

    // MARK: 5. Dates and list order

    func testDateLabels() {
        var t = Tourney(now: day(2027, 1, 1), calendar: cal)
        t.startDate = day(2027, 6, 6); t.endDate = day(2027, 6, 8)
        XCTAssertEqual(t.dateRangeText(calendar: cal), "Jun 6 - 8, 2027")
        t.startDate = day(2027, 6, 30); t.endDate = day(2027, 7, 2)
        XCTAssertEqual(t.dateRangeText(calendar: cal), "Jun 30 - Jul 2, 2027")
        t.startDate = day(2027, 12, 31); t.endDate = day(2028, 1, 1)
        XCTAssertEqual(t.dateRangeText(calendar: cal), "Dec 31, 2027 - Jan 1, 2028")
        t.startDate = day(2027, 6, 6, 9); t.endDate = day(2027, 6, 6, 18)
        XCTAssertEqual(t.dateRangeText(calendar: cal), "Jun 6, 2027")
    }

    func testANewTourneyStartsThisComingSaturday() {
        let fromWednesday = Tourney(now: day(2027, 6, 2, 14), calendar: cal)   // Wed
        XCTAssertEqual(fromWednesday.startDate, day(2027, 6, 5))
        XCTAssertEqual(fromWednesday.endDate, day(2027, 6, 6))
        XCTAssertEqual(Tourney(now: day(2027, 6, 5, 8), calendar: cal).startDate, day(2027, 6, 5), "Saturday = today")
    }

    func testUpcomingComesBeforePast() {
        func make(_ name: String, _ start: Date, _ end: Date) -> Tourney {
            var t = Tourney(now: start, calendar: cal)
            t.name = name; t.startDate = start; t.endDate = end
            return t
        }
        let now = day(2027, 6, 10, 12)
        let list = [
            make("Old", day(2027, 5, 1), day(2027, 5, 2)),
            make("Far", day(2027, 8, 1), day(2027, 8, 2)),
            make("Today", day(2027, 6, 9), day(2027, 6, 10)),   // ends today - still on
            make("Recent", day(2027, 6, 1), day(2027, 6, 2)),
            make("Soon", day(2027, 6, 20), day(2027, 6, 21)),
        ]
        XCTAssertEqual(Tourney.sortedForList(list, now: now, calendar: cal).map(\.name),
                       ["Today", "Soon", "Far", "Recent", "Old"])
    }

    // MARK: 6. Meet spot geometry

    func testImagePointsMapToTheGround() {
        let spot = TourneyMeetSpot(centerLatitude: 40, centerLongitude: -75, latitudeDelta: 0.01, longitudeDelta: 0.02)
        let center = spot.coordinate(atX: 0.5, y: 0.5)
        XCTAssertEqual(center.latitude, 40, accuracy: 1e-9)
        XCTAssertEqual(center.longitude, -75, accuracy: 1e-9)
        let topRight = spot.coordinate(atX: 1, y: 0)
        XCTAssertEqual(topRight.latitude, 40.005, accuracy: 1e-9, "top of the image is north")
        XCTAssertEqual(topRight.longitude, -74.99, accuracy: 1e-9, "right is east")
        let bottomLeft = spot.coordinate(atX: 0, y: 1)
        XCTAssertEqual(bottomLeft.latitude, 39.995, accuracy: 1e-9)
        XCTAssertEqual(bottomLeft.longitude, -75.01, accuracy: 1e-9)
    }

    func testDirectionsGoToTheFirstPinElseTheMiddle() {
        var spot = TourneyMeetSpot(title: "Warmups", centerLatitude: 40, centerLongitude: -75,
                                   latitudeDelta: 0.01, longitudeDelta: 0.01,
                                   marks: [TourneyMark(kind: .text, x: 0, y: 0, text: "Gate")])
        XCTAssertEqual(spot.meetPlace.latitude ?? 0, 40, accuracy: 1e-9)
        XCTAssertEqual(spot.meetPlace.name, "Warmups")
        spot.marks.append(TourneyMark(kind: .pin, x: 1, y: 1, text: "Shade tree"))
        spot.marks.append(TourneyMark(kind: .pin, x: 0, y: 0))
        XCTAssertEqual(spot.meetPlace.latitude ?? 0, 39.995, accuracy: 1e-9)
        XCTAssertEqual(spot.meetPlace.longitude ?? 0, -74.995, accuracy: 1e-9)
        XCTAssertEqual(spot.meetPlace.name, "Shade tree")
        XCTAssertNotEqual(spot.regionKey,
                          TourneyMeetSpot(centerLatitude: 40, centerLongitude: -75, latitudeDelta: 0.02, longitudeDelta: 0.01).regionKey,
                          "a new area means a new image")
    }

    // MARK: 7. Marks

    func testBulletLines() {
        XCTAssertEqual(TourneyMark.bulletLines("8:00 warmups\n\n• Water\n - Hats \n*Sunscreen"),
                       ["• 8:00 warmups", "• Water", "• Hats", "• Sunscreen"])
        XCTAssertEqual(TourneyMark.bulletLines("  \n "), [])
    }

    func testPickingTheNearestMarkIncludingAlongALine() {
        let line = TourneyMark(kind: .line, x: 0, y: 0.5, x2: 1, y2: 0.5)
        XCTAssertEqual(line.distance(toX: 0.5, y: 0.6, aspect: 1), 0.1, accuracy: 1e-9, "middle of the line, not its end")
        XCTAssertEqual(line.distance(toX: 1.2, y: 0.5, aspect: 1), 0.2, accuracy: 1e-9, "past the end measures to the end")
        let pin = TourneyMark(kind: .pin, x: 0.5, y: 0.5)
        XCTAssertEqual(pin.distance(toX: 0.5, y: 0.6, aspect: 1.25), 0.125, accuracy: 1e-9, "height is scaled to the image's shape")
    }

    func testMovedMarksStayInsideTheImage() {
        let arrow = TourneyMark(kind: .arrow, x: 0.9, y: 0.1, x2: 0.5, y2: 0.5)
        let moved = arrow.moved(dx: 0.3, dy: -0.3)
        XCTAssertEqual(moved.x, 1); XCTAssertEqual(moved.y, 0)
        XCTAssertEqual(moved.x2, 0.8, accuracy: 1e-9); XCTAssertEqual(moved.y2, 0.2, accuracy: 1e-9, "both ends move")
        let text = TourneyMark(kind: .text, x: 0.1, y: 0.1, x2: 0.3, y2: 0.3).moved(dx: -0.5, dy: 0.2)
        XCTAssertEqual(text.x, 0)
        XCTAssertEqual(text.y, 0.3, accuracy: 1e-9)
        XCTAssertEqual(text.x2, 0.3, "only lines carry a second point")
    }

    // MARK: 8. Checklist

    // MARK: 9. Share text

    // MARK: Store

    func testStoreArchivesWithoutDeleting() {
        let store = TourneyStore(inMemory: true)
        var t = Tourney()
        t.name = "A"
        store.save(t)
        store.setArchived(t, true)
        XCTAssertEqual(store.tourneys.count, 1)
        XCTAssertTrue(store.active.isEmpty)
        XCTAssertEqual(store.archived.map(\.name), ["A"])
        store.setArchived(store.archived[0], false)
        XCTAssertEqual(store.active.map(\.name), ["A"])
    }
}
