//
//  Tourney.swift
//  PitchMark
//
//  Round Robin / Tourney Info (2026-11-16, reworked 2026-11-17): a coach's -
//  or a family's - page for one tournament: dates, venue, game-day plan,
//  meet spots on a satellite image, general info (daily uniforms, metal
//  cleats, things to bring), gate fee, tournament food, hotels, links and
//  notes. Saved at `users/{uid}/tourneys/{id}` (users/** catch-all rule).
//  Archived, never deleted.
//
//  Sharing in the app: the owner's phone keeps a read-only copy at
//  `sharedTourneys/{shareId}` (its own rule) that anyone with the link
//  sees in the same layout. Scouting (`TourneyProspect`) is the coaching
//  staff's list of tourneys they might enter, `users/{uid}/tourneyProspects`.
//
//  This file is the model and the rules (plain types, unit tested); the
//  screens are TourneyViews.swift and TourneyMeetSpot.swift. PitchMark
//  only - not in the Display target.
//

import Foundation
import CoreLocation
import Combine
import FirebaseFirestore

// MARK: - Firestore helpers

private extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String { (self[key] as? String) ?? "" }
    func double(_ key: String) -> Double? {
        if let d = self[key] as? Double { return d }
        if let i = self[key] as? Int { return Double(i) }
        if let n = self[key] as? NSNumber { return n.doubleValue }
        return nil
    }
    func date(_ key: String) -> Date? {
        if let t = self[key] as? Timestamp { return t.dateValue() }
        return self[key] as? Date
    }
    func maps(_ key: String) -> [[String: Any]] { (self[key] as? [[String: Any]]) ?? [] }
}

private func newId() -> String { UUID().uuidString }

// MARK: - Place

/// A spot people drive to: the venue, a hotel, a meet spot's pin.
struct TourneyPlace: Equatable {
    var name: String = ""
    var address: String = ""
    var latitude: Double? = nil
    var longitude: Double? = nil

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isEmpty: Bool {
        name.trimmed.isEmpty && address.trimmed.isEmpty && coordinate == nil
    }

    /// What a map app searches for when there's no pin.
    var searchText: String {
        [name.trimmed, address.trimmed].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var firestoreData: [String: Any] {
        var data: [String: Any] = ["name": name, "address": address]
        if let latitude, let longitude {
            data["latitude"] = latitude
            data["longitude"] = longitude
        }
        return data
    }

    init(name: String = "", address: String = "", latitude: Double? = nil, longitude: Double? = nil) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }

    init(firestoreData data: [String: Any]) {
        name = data.string("name")
        address = data.string("address")
        latitude = data.double("latitude")
        longitude = data.double("longitude")
        if latitude == nil || longitude == nil { latitude = nil; longitude = nil }
    }
}

// MARK: - Directions

/// The map apps a place can be opened in. Every link is a plain https URL,
/// so it opens the app when it's installed and the website when it isn't -
/// no `LSApplicationQueriesSchemes` needed.
enum TourneyMapApp: String, CaseIterable, Identifiable {
    case apple, google, waze
    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return "Apple Maps"
        case .google: return "Google Maps"
        case .waze: return "Waze"
        }
    }

    /// Driving directions to `place`, by pin when it has one, else by its
    /// name and address. nil when there's nothing to go to.
    func directionsURL(to place: TourneyPlace) -> URL? {
        let query = place.searchText
        let coordinate = place.coordinate
        guard coordinate != nil || !query.isEmpty else { return nil }
        let ll = coordinate.map { "\($0.latitude),\($0.longitude)" }
        var components: URLComponents
        switch self {
        case .apple:
            components = URLComponents(string: "https://maps.apple.com/")!
            var items = [URLQueryItem(name: "daddr", value: ll ?? query), URLQueryItem(name: "dirflg", value: "d")]
            if ll != nil, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
            components.queryItems = items
        case .google:
            components = URLComponents(string: "https://www.google.com/maps/dir/")!
            components.queryItems = [
                URLQueryItem(name: "api", value: "1"),
                URLQueryItem(name: "destination", value: ll ?? query),
                URLQueryItem(name: "travelmode", value: "driving"),
            ]
        case .waze:
            components = URLComponents(string: "https://waze.com/ul")!
            components.queryItems = ll.map {
                [URLQueryItem(name: "ll", value: $0), URLQueryItem(name: "navigate", value: "yes")]
            } ?? [URLQueryItem(name: "q", value: query), URLQueryItem(name: "navigate", value: "yes")]
        }
        return components.url
    }
}

// MARK: - Links

struct TourneyLink: Identifiable, Equatable {
    var id: String = newId()
    var title: String = ""
    var urlString: String = ""

    /// The link as typed, with https:// added when it has no scheme.
    /// nil when it can't be a web link.
    var url: URL? { Self.normalizedURL(urlString) }

    static func normalizedURL(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        let withScheme = text.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://", options: .regularExpression) == nil
            ? "https://" + text : text
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, host.contains(".") else { return nil }
        return url
    }

    var displayTitle: String {
        let t = title.trimmed
        if !t.isEmpty { return t }
        return url?.host ?? urlString.trimmed
    }

    var firestoreData: [String: Any] { ["id": id, "title": title, "url": urlString] }

    init(id: String = newId(), title: String = "", urlString: String = "") {
        self.id = id
        self.title = title
        self.urlString = urlString
    }

    init(firestoreData data: [String: Any]) {
        id = data["id"] as? String ?? newId()
        title = data.string("title")
        urlString = data.string("url")
    }
}

// MARK: - Money

enum TourneyMoney {
    static func format(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = amount.rounded() == amount ? 0 : 2
        return f.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}

// MARK: - Hotels

struct TourneyHotel: Identifiable, Equatable {
    var id: String = newId()
    var place: TourneyPlace = TourneyPlace()
    var phone: String = ""
    var link: String = ""
    var nightlyRate: Double? = nil
    var nights: Int = 0
    var bookingCode: String = ""
    var bookBy: Date? = nil
    var notes: String = ""

    /// Rate x nights, before taxes; nil until both are filled in.
    var stayTotal: Double? {
        guard let nightlyRate, nightlyRate > 0, nights > 0 else { return nil }
        return nightlyRate * Double(nights)
    }

    /// Digits (and a leading +) for a tel: link; nil when there aren't enough.
    var phoneURL: URL? {
        let allowed = phone.filter { $0.isNumber || $0 == "+" }
        guard allowed.filter(\.isNumber).count >= 7 else { return nil }
        return URL(string: "tel:\(allowed)")
    }

    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "id": id, "place": place.firestoreData, "phone": phone, "link": link,
            "nights": nights, "bookingCode": bookingCode, "notes": notes,
        ]
        if let nightlyRate { data["nightlyRate"] = nightlyRate }
        if let bookBy { data["bookBy"] = Timestamp(date: bookBy) }
        return data
    }

    init(id: String = newId(), place: TourneyPlace = TourneyPlace(), phone: String = "", link: String = "",
         nightlyRate: Double? = nil, nights: Int = 0, bookingCode: String = "", bookBy: Date? = nil, notes: String = "") {
        self.id = id
        self.place = place
        self.phone = phone
        self.link = link
        self.nightlyRate = nightlyRate
        self.nights = nights
        self.bookingCode = bookingCode
        self.bookBy = bookBy
        self.notes = notes
    }

    init(firestoreData data: [String: Any]) {
        id = data["id"] as? String ?? newId()
        place = TourneyPlace(firestoreData: (data["place"] as? [String: Any]) ?? [:])
        phone = data.string("phone")
        link = data.string("link")
        nightlyRate = data.double("nightlyRate")
        nights = max(0, Int(data.double("nights") ?? 0))
        bookingCode = data.string("bookingCode")
        bookBy = data.date("bookBy")
        notes = data.string("notes")
    }
}

// MARK: - Game day

struct TourneyGameDay: Equatable {
    var fieldName: String = ""
    var notes: String = ""

    var firestoreData: [String: Any] { ["fieldName": fieldName, "notes": notes] }

    init() {}

    init(firestoreData data: [String: Any]) {
        fieldName = data.string("fieldName")
        notes = data.string("notes")
    }
}

// MARK: - Meet spots (satellite image + markup)

enum TourneyMarkKind: String, CaseIterable, Identifiable {
    case pin, text, bullets, arrow, line
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pin: return "Pin"
        case .text: return "Text"
        case .bullets: return "List"
        case .arrow: return "Arrow"
        case .line: return "Line"
        }
    }
    var systemImage: String {
        switch self {
        case .pin: return "mappin"
        case .text: return "textformat"
        case .bullets: return "list.bullet"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        }
    }
    var hasText: Bool { self == .text || self == .bullets || self == .pin }
    var isStroke: Bool { self == .arrow || self == .line }
}

/// One thing drawn on a meet spot's image. Positions are 0...1 of the
/// image's width/height, so the editor and the shared image (any size)
/// put it in the same place. Lines are two named points, never a nested
/// array (Firestore can't store one).
struct TourneyMark: Identifiable, Equatable {
    var id: String = newId()
    var kind: TourneyMarkKind
    var x: Double
    var y: Double
    var x2: Double = 0
    var y2: Double = 0
    var text: String = ""
    var colorHex: String = TourneyMark.palette[1]
    /// 1 = small, 2 = medium, 3 = large.
    var size: Int = 2

    static let palette = ["#FFFFFF", "#FFD60A", "#FF3B30", "#30D158", "#0A84FF", "#000000"]

    /// A List's lines as shown, each with a bullet. Blank lines are skipped
    /// and a bullet the coach typed isn't doubled.
    static func bulletLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { line -> String in
                var s = line.trimmingCharacters(in: .whitespaces)
                for prefix in ["•", "-", "*"] where s.hasPrefix(prefix) {
                    s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    break
                }
                return s
            }
            .filter { !$0.isEmpty }
            .map { "• " + $0 }
    }

    /// How far (in 0...1 units, measured in the image's own aspect) a
    /// point is from this mark - for picking which mark a tap meant.
    func distance(toX px: Double, y py: Double, aspect: Double) -> Double {
        // aspect = height / width; scale y so distances are uniform.
        func d(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
            let dx = ax - bx, dy = (ay - by) * aspect
            return (dx * dx + dy * dy).squareRoot()
        }
        guard kind.isStroke else { return d(x, y, px, py) }
        let vx = x2 - x, vy = (y2 - y) * aspect
        let wx = px - x, wy = (py - y) * aspect
        let len2 = vx * vx + vy * vy
        guard len2 > 0 else { return d(x, y, px, py) }
        let t = max(0, min(1, (wx * vx + wy * vy) / len2))
        let cx = wx - t * vx, cy = wy - t * vy
        return (cx * cx + cy * cy).squareRoot()
    }

    /// Moved by (dx, dy), kept inside the image.
    func moved(dx: Double, dy: Double) -> TourneyMark {
        var m = self
        func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
        m.x = clamp(x + dx); m.y = clamp(y + dy)
        if kind.isStroke { m.x2 = clamp(x2 + dx); m.y2 = clamp(y2 + dy) }
        return m
    }

    var firestoreData: [String: Any] {
        ["id": id, "kind": kind.rawValue, "x": x, "y": y, "x2": x2, "y2": y2,
         "text": text, "color": colorHex, "size": size]
    }

    init(id: String = newId(), kind: TourneyMarkKind, x: Double, y: Double, x2: Double = 0, y2: Double = 0,
         text: String = "", colorHex: String = TourneyMark.palette[1], size: Int = 2) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.x2 = x2
        self.y2 = y2
        self.text = text
        self.colorHex = colorHex
        self.size = size
    }

    init?(firestoreData data: [String: Any]) {
        guard let kind = TourneyMarkKind(rawValue: data.string("kind")),
              let x = data.double("x"), let y = data.double("y") else { return nil }
        self.id = data["id"] as? String ?? newId()
        self.kind = kind
        self.x = x
        self.y = y
        self.x2 = data.double("x2") ?? x
        self.y2 = data.double("y2") ?? y
        self.text = data.string("text")
        self.colorHex = (data["color"] as? String) ?? TourneyMark.palette[1]
        self.size = min(3, max(1, Int(data.double("size") ?? 2)))
    }
}

/// A satellite view of part of the complex with marks on it - "we meet
/// here for warmups". Only the map region and the marks are saved; the
/// image is re-made from the region (and cached on the phone, so it still
/// opens at a field with no signal).
struct TourneyMeetSpot: Identifiable, Equatable {
    var id: String = newId()
    var title: String = ""
    var centerLatitude: Double
    var centerLongitude: Double
    var latitudeDelta: Double
    var longitudeDelta: Double
    var marks: [TourneyMark] = []

    /// Width : height of every meet spot image (portrait, phone-friendly).
    static let aspect: Double = 4.0 / 5.0

    /// Where a point on the image (0...1) is on the ground. Linear across
    /// the region - at a ballpark's scale the projection's curve is far
    /// smaller than a finger.
    func coordinate(atX px: Double, y py: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: centerLatitude + (0.5 - py) * latitudeDelta,
            longitude: centerLongitude + (px - 0.5) * longitudeDelta
        )
    }

    /// The first pin's spot, else the image's center - where "Directions"
    /// goes.
    var meetPlace: TourneyPlace {
        let pin = marks.first { $0.kind == .pin }
        let c = pin.map { coordinate(atX: $0.x, y: $0.y) }
            ?? CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
        let name = pin.map(\.text.trimmed).flatMap { $0.isEmpty ? nil : $0 } ?? title.trimmed
        return TourneyPlace(name: name, latitude: c.latitude, longitude: c.longitude)
    }

    /// Changes whenever the image underneath would change - the cache key.
    var regionKey: String {
        String(format: "%.6f_%.6f_%.6f_%.6f", centerLatitude, centerLongitude, latitudeDelta, longitudeDelta)
    }

    var firestoreData: [String: Any] {
        ["id": id, "title": title, "centerLatitude": centerLatitude, "centerLongitude": centerLongitude,
         "latitudeDelta": latitudeDelta, "longitudeDelta": longitudeDelta,
         "marks": marks.map(\.firestoreData)]
    }

    init(id: String = newId(), title: String = "", centerLatitude: Double, centerLongitude: Double,
         latitudeDelta: Double, longitudeDelta: Double, marks: [TourneyMark] = []) {
        self.id = id
        self.title = title
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
        self.marks = marks
    }

    init?(firestoreData data: [String: Any]) {
        guard let lat = data.double("centerLatitude"), let lon = data.double("centerLongitude"),
              let dLat = data.double("latitudeDelta"), let dLon = data.double("longitudeDelta"),
              dLat > 0, dLon > 0 else { return nil }
        id = data["id"] as? String ?? newId()
        title = data.string("title")
        centerLatitude = lat
        centerLongitude = lon
        latitudeDelta = dLat
        longitudeDelta = dLon
        marks = data.maps("marks").compactMap(TourneyMark.init(firestoreData:))
    }
}

// MARK: - Checklist

struct TourneyChecklistItem: Identifiable, Equatable {
    var id: String = newId()
    var text: String
    var done: Bool = false

    var firestoreData: [String: Any] { ["id": id, "text": text, "done": done] }

    init(id: String = newId(), text: String, done: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
    }

    init?(firestoreData data: [String: Any]) {
        let text = data.string("text").trimmed
        guard !text.isEmpty else { return nil }
        id = data["id"] as? String ?? newId()
        self.text = text
        done = data["done"] as? Bool ?? false
    }
}

// MARK: - Games

/// When in the tourney a game is: the games scheduled up front (pool /
/// round robin) or one added once bracket play begins.
enum TourneyGameStage: String, CaseIterable, Identifiable {
    case scheduled, bracket
    var id: String { rawValue }
    var title: String { self == .scheduled ? "Scheduled" : "Bracket" }
}

struct TourneyGame: Identifiable, Equatable {
    var id: String = newId()
    var stage: TourneyGameStage = .scheduled
    var time: Date
    /// When the team should be there for this game (optional).
    var arriveAt: Date? = nil
    var field: String = ""
    var opponent: String = ""
    var result: String = ""
    /// The teams picked the way a new game picks them (Home's + card), so
    /// Start Game can hand them on. The owner's team ids - a follower's
    /// Start Game uses them only if they're on that team too.
    var ourTeamId: String? = nil
    var opponentTeamId: String? = nil
    /// Called off (2026-11-22): stays on the schedule marked Canceled, so
    /// families following the team see it.
    var canceled: Bool = false

    var firestoreData: [String: Any] {
        var data: [String: Any] = ["id": id, "stage": stage.rawValue, "time": Timestamp(date: time),
                                   "field": field, "opponent": opponent, "result": result,
                                   "canceled": canceled]
        data["arriveAt"] = arriveAt.map { Timestamp(date: $0) } ?? NSNull()
        data["ourTeamId"] = ourTeamId ?? NSNull()
        data["opponentTeamId"] = opponentTeamId ?? NSNull()
        return data
    }

    init(id: String = newId(), stage: TourneyGameStage = .scheduled, time: Date, arriveAt: Date? = nil,
         field: String = "", opponent: String = "", result: String = "",
         ourTeamId: String? = nil, opponentTeamId: String? = nil) {
        self.ourTeamId = ourTeamId
        self.opponentTeamId = opponentTeamId
        self.id = id
        self.stage = stage
        self.time = time
        self.arriveAt = arriveAt
        self.field = field
        self.opponent = opponent
        self.result = result
    }

    /// "Field 7" from "7"; a field typed as "Field 7" or "field 7" isn't
    /// doubled. "" when blank.
    var fieldLabel: String {
        let f = field.trimmed
        guard !f.isEmpty else { return "" }
        return f.lowercased().hasPrefix("field") ? f : "Field \(f)"
    }

    /// What Start Game hands to Home's new-game card: the opponent's name
    /// and time, and each team only if it's one of `myTeamIds` (a shared
    /// tourney's ids may be teams this user isn't on).
    func newGameSeed(myTeamIds: Set<String>) -> (opponentName: String, date: Date, ourTeamId: String?, opponentTeamId: String?) {
        (opponent.trimmed, time,
         ourTeamId.flatMap { myTeamIds.contains($0) ? $0 : nil },
         opponentTeamId.flatMap { myTeamIds.contains($0) ? $0 : nil })
    }

    /// The default arrive-at: an hour before the game.
    var suggestedArriveAt: Date { time.addingTimeInterval(-60 * 60) }

    init?(firestoreData data: [String: Any]) {
        guard let time = data.date("time") else { return nil }
        id = data["id"] as? String ?? newId()
        stage = TourneyGameStage(rawValue: data.string("stage")) ?? .scheduled
        self.time = time
        arriveAt = data.date("arriveAt")
        ourTeamId = (data["ourTeamId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        opponentTeamId = (data["opponentTeamId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        field = data.string("field")
        opponent = data.string("opponent")
        result = data.string("result")
        canceled = data["canceled"] as? Bool ?? false
    }

    /// "vs Hawks · Field 7", leaving out what's blank.
    var summary: String {
        [opponent.trimmed.isEmpty ? nil : "vs \(opponent.trimmed)",
         fieldLabel.isEmpty ? nil : fieldLabel].compactMap { $0 }.joined(separator: " · ")
    }

    /// Scheduled games first, then bracket games, each by time.
    static func sorted(_ games: [TourneyGame]) -> [TourneyGame] {
        games.sorted {
            if $0.stage != $1.stage { return $0.stage == .scheduled }
            return $0.time < $1.time
        }
    }

    /// When a new game starts: 90 minutes after the latest game, or 8 AM
    /// on the tourney's first day.
    static func nextStart(after games: [TourneyGame], tourneyStart: Date, calendar: Calendar = .current) -> Date {
        if let last = games.map(\.time).max() { return last.addingTimeInterval(90 * 60) }
        let day = calendar.startOfDay(for: tourneyStart)
        return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day
    }
}

// MARK: - Tournament food

/// One family's food for the tourney - the green check is "it's covered".
struct TourneyFoodItem: Identifiable, Equatable {
    var id: String = newId()
    var family: String = ""
    var food: String = ""
    var done: Bool = false

    var isEmpty: Bool { family.trimmed.isEmpty && food.trimmed.isEmpty }

    var firestoreData: [String: Any] { ["id": id, "family": family, "food": food, "done": done] }

    init(id: String = newId(), family: String = "", food: String = "", done: Bool = false) {
        self.id = id
        self.family = family
        self.food = food
        self.done = done
    }

    init(firestoreData data: [String: Any]) {
        id = data["id"] as? String ?? newId()
        family = data.string("family")
        food = data.string("food")
        done = data["done"] as? Bool ?? false
    }
}

// MARK: - Tourney

struct Tourney: Identifiable, Equatable {
    var id: String = newId()
    var name: String = ""
    var startDate: Date
    var endDate: Date
    var venue: TourneyPlace = TourneyPlace()
    var gameDay: TourneyGameDay = TourneyGameDay()
    var games: [TourneyGame] = []
    var meetSpots: [TourneyMeetSpot] = []
    /// One uniform per day ("Day 1" first), its own section. Kept by day
    /// number, not date, so moving the dates keeps them; the coach adds
    /// days with +, and there's always at least one.
    var dailyUniforms: [String] = []
    var metalCleatsAllowed: Bool = false
    var checklist: [TourneyChecklistItem] = []
    var gateFee: Bool = false
    var gateFeeNotes: String = ""
    var cashOnly: Bool = false
    var food: [TourneyFoodItem] = []
    var links: [TourneyLink] = []
    var hotels: [TourneyHotel] = []
    var notes: String = ""
    var archivedAt: Date? = nil
    /// Set while shared in the app: the id of its `sharedTourneys` copy.
    var shareId: String? = nil
    /// The team this tourney belongs to (2026-11-22). Set = it lives at
    /// `teams/{teamId}/tourneys`, edited by the coach and their Schedulers
    /// and seen live by every member. Nil = the coach's own.
    var teamId: String? = nil
    /// Who made the shared link's copy - its owner can't change, and on a
    /// team tourney a Scheduler keeps it current under that owner.
    var shareOwnerUid: String? = nil

    /// Days the tourney runs, start day first (at most 14).
    func days(calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: startDate)
        let end = max(start, calendar.startOfDay(for: endDate))
        let count = min(14, (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// How many uniform rows to show: every saved day, never fewer than one.
    var uniformDayCount: Int { max(1, dailyUniforms.count) }

    /// Day `index`'s date when it falls inside the tourney's dates.
    func date(ofDay index: Int, calendar: Calendar = .current) -> Date? {
        let all = days(calendar: calendar)
        return all.indices.contains(index) ? all[index] : nil
    }

    mutating func addUniformDay() {
        while dailyUniforms.count < uniformDayCount { dailyUniforms.append("") }
        dailyUniforms.append("")
    }

    mutating func removeUniformDay(_ index: Int) {
        guard dailyUniforms.indices.contains(index) else { return }
        dailyUniforms.remove(at: index)
    }

    /// Day `index`'s uniform ("" when none).
    func uniform(day index: Int) -> String {
        dailyUniforms.indices.contains(index) ? dailyUniforms[index] : ""
    }

    mutating func setUniform(_ text: String, day index: Int) {
        guard index >= 0 else { return }
        while dailyUniforms.count <= index { dailyUniforms.append("") }
        dailyUniforms[index] = text
    }

    var isArchived: Bool { archivedAt != nil }

    /// A new tourney: this coming Saturday through Sunday.
    init(now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday
        let toSaturday = (7 - weekday + 7) % 7
        startDate = calendar.date(byAdding: .day, value: toSaturday, to: today) ?? today
        endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
    }

    var displayName: String { name.trimmed.isEmpty ? "Untitled Tourney" : name.trimmed }

    /// "Jun 6 - 8, 2027", "Jun 30 - Jul 2, 2027", "Jun 6, 2027".
    func dateRangeText(calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: startDate)
        let end = max(start, calendar.startOfDay(for: endDate))
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US")
        f.timeZone = calendar.timeZone
        if start == end {
            f.dateFormat = "MMM d, yyyy"
            return f.string(from: start)
        }
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: end)
        let sameMonth = sameYear && calendar.component(.month, from: start) == calendar.component(.month, from: end)
        f.dateFormat = sameYear ? "MMM d" : "MMM d, yyyy"
        let a = f.string(from: start)
        f.dateFormat = sameMonth ? "d, yyyy" : "MMM d, yyyy"
        return "\(a) - \(f.string(from: end))"
    }

    /// Upcoming (or under way) vs. done, by the day it ends.
    func isPast(now: Date, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: max(startDate, endDate)) < calendar.startOfDay(for: now)
    }

    /// Upcoming first (soonest first), then past (most recent first).
    static func sortedForList(_ tourneys: [Tourney], now: Date, calendar: Calendar = .current) -> [Tourney] {
        let upcoming = tourneys.filter { !$0.isPast(now: now, calendar: calendar) }.sorted { $0.startDate < $1.startDate }
        let past = tourneys.filter { $0.isPast(now: now, calendar: calendar) }.sorted { $0.startDate > $1.startDate }
        return upcoming + past
    }

    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "name": name,
            "startDate": Timestamp(date: startDate),
            "endDate": Timestamp(date: endDate),
            "venue": venue.firestoreData,
            "gameDay": gameDay.firestoreData,
            "games": games.map(\.firestoreData),
            "meetSpots": meetSpots.map(\.firestoreData),
            "dailyUniforms": dailyUniforms,
            "metalCleatsAllowed": metalCleatsAllowed,
            "checklist": checklist.map(\.firestoreData),
            "gateFee": gateFee,
            "gateFeeNotes": gateFeeNotes,
            "cashOnly": cashOnly,
            "food": food.map(\.firestoreData),
            "links": links.map(\.firestoreData),
            "hotels": hotels.map(\.firestoreData),
            "notes": notes,
        ]
        data["archivedAt"] = archivedAt.map { Timestamp(date: $0) } ?? NSNull()
        data["shareId"] = shareId ?? NSNull()
        data["teamId"] = teamId ?? NSNull()
        data["shareOwnerUid"] = shareOwnerUid ?? NSNull()
        return data
    }

    /// What the `sharedTourneys` copy holds: the page, without the owner's
    /// own bookkeeping (archive, share id).
    func sharedData(ownerUid: String) -> [String: Any] {
        var data = firestoreData
        data.removeValue(forKey: "archivedAt")
        data.removeValue(forKey: "shareId")
        data.removeValue(forKey: "shareOwnerUid")
        data["ownerUid"] = shareOwnerUid ?? ownerUid
        return data
    }

    init(id: String, firestoreData data: [String: Any]) {
        self.id = id
        name = data.string("name")
        let start = data.date("startDate") ?? Date()
        startDate = start
        endDate = max(start, data.date("endDate") ?? start)
        venue = TourneyPlace(firestoreData: (data["venue"] as? [String: Any]) ?? [:])
        gameDay = TourneyGameDay(firestoreData: (data["gameDay"] as? [String: Any]) ?? [:])
        games = data.maps("games").compactMap(TourneyGame.init(firestoreData:))
        meetSpots = data.maps("meetSpots").compactMap(TourneyMeetSpot.init(firestoreData:))
        dailyUniforms = (data["dailyUniforms"] as? [Any])?.map { ($0 as? String) ?? "" } ?? []
        if dailyUniforms.allSatisfy({ $0.trimmed.isEmpty }),
           let old = (data["gameDay"] as? [String: Any])?["uniform"] as? String, !old.trimmed.isEmpty {
            dailyUniforms = [old]   // the single Uniform field from 2026-11-16
        }
        metalCleatsAllowed = data["metalCleatsAllowed"] as? Bool ?? false
        checklist = data.maps("checklist").compactMap(TourneyChecklistItem.init(firestoreData:))
        gateFee = data["gateFee"] as? Bool ?? false
        gateFeeNotes = data.string("gateFeeNotes")
        cashOnly = data["cashOnly"] as? Bool ?? false
        food = data.maps("food").map(TourneyFoodItem.init(firestoreData:))
        links = data.maps("links").map(TourneyLink.init(firestoreData:))
        hotels = data.maps("hotels").map(TourneyHotel.init(firestoreData:))
        notes = data.string("notes")
        archivedAt = data.date("archivedAt")
        shareId = (data["shareId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        teamId = (data["teamId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        shareOwnerUid = (data["shareOwnerUid"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}

// MARK: - Share text

/// What goes in the text shared with families who don't have the app.
/// Each part is a toggle on the share screen; empty parts are left out
/// whatever the toggle says.
struct TourneyShareOptions: Equatable {
    var schedule = true
    var games = true
    var gameDay = true
    var uniforms = true
    var generalInfo = true
    var gateFee = true
    var food = true
    var hotels = true
    var links = true
    var notes = true
}

enum TourneyShareText {
    static func text(for t: Tourney, options: TourneyShareOptions = TourneyShareOptions(),
                     calendar: Calendar = .current) -> String {
        var blocks: [String] = []
        let timeF = DateFormatter()
        timeF.locale = Locale(identifier: "en_US")
        timeF.timeZone = calendar.timeZone
        timeF.dateFormat = "EEE MMM d, h:mm a"
        let dayF = DateFormatter()
        dayF.locale = Locale(identifier: "en_US")
        dayF.timeZone = calendar.timeZone
        dayF.dateFormat = "MMM d"
        let arriveF = DateFormatter()
        arriveF.locale = Locale(identifier: "en_US")
        arriveF.timeZone = calendar.timeZone
        arriveF.dateFormat = "h:mm a"
        let weekdayF = DateFormatter()
        weekdayF.locale = Locale(identifier: "en_US")
        weekdayF.timeZone = calendar.timeZone
        weekdayF.dateFormat = "EEE MMM d"

        var head = ["🏆 \(t.displayName)"]
        if options.schedule {
            head.append("📅 \(t.dateRangeText(calendar: calendar))")
            if !t.venue.isEmpty {
                head.append("📍 \(t.venue.searchText)")
                if let url = TourneyMapApp.apple.directionsURL(to: t.venue) {
                    head.append("Directions: \(url.absoluteString)")
                }
            }
        }
        blocks.append(head.joined(separator: "\n"))

        if options.games {
            var lines: [String] = []
            for stage in TourneyGameStage.allCases {
                let games = TourneyGame.sorted(t.games).filter { $0.stage == stage }
                guard !games.isEmpty else { continue }
                if t.games.contains(where: { $0.stage != stage }) { lines.append("\(stage.title):") }
                for g in games {
                    var line = timeF.string(from: g.time)
                    if !g.summary.isEmpty { line += " · \(g.summary)" }
                    if let arrive = g.arriveAt { line += " · arrive \(arriveF.string(from: arrive))" }
                    if !g.result.trimmed.isEmpty { line += " · \(g.result.trimmed)" }
                    lines.append(line)
                }
            }
            if !lines.isEmpty { blocks.append((["GAMES"] + lines).joined(separator: "\n")) }
        }

        if options.gameDay {
            let g = t.gameDay
            var lines: [String] = []
            if !g.fieldName.trimmed.isEmpty { lines.append("Field / complex: \(g.fieldName.trimmed)") }
            if !g.notes.trimmed.isEmpty { lines.append(g.notes.trimmed) }
            for spot in t.meetSpots {
                let place = spot.meetPlace
                let name = spot.title.trimmed.isEmpty ? "Meet spot" : spot.title.trimmed
                if let url = TourneyMapApp.apple.directionsURL(to: place) {
                    lines.append("\(name): \(url.absoluteString)")
                }
            }
            if !lines.isEmpty { blocks.append((["GAME DAY"] + lines).joined(separator: "\n")) }
        }

        if options.uniforms {
            var lines: [String] = []
            for i in 0..<t.uniformDayCount {
                let u = t.uniform(day: i).trimmed
                guard !u.isEmpty else { continue }
                let when = t.date(ofDay: i, calendar: calendar).map { " (\(weekdayF.string(from: $0)))" } ?? ""
                lines.append("Day \(i + 1)\(when): \(u)")
            }
            if !lines.isEmpty { blocks.append((["UNIFORMS"] + lines).joined(separator: "\n")) }
        }

        if options.generalInfo {
            var lines = [t.metalCleatsAllowed ? "Metal cleats allowed" : "No metal cleats"]
            lines += t.checklist.map(\.text)
            blocks.append((["GENERAL INFO"] + lines).joined(separator: "\n"))
        }

        if options.gateFee {
            var lines: [String] = []
            if t.gateFee { lines.append("Gate fee" + (t.gateFeeNotes.trimmed.isEmpty ? "" : ": \(t.gateFeeNotes.trimmed)")) }
            else if !t.gateFeeNotes.trimmed.isEmpty { lines.append(t.gateFeeNotes.trimmed) }
            if t.cashOnly { lines.append("Cash only") }
            if !lines.isEmpty { blocks.append((["GATE"] + lines).joined(separator: "\n")) }
        }

        if options.food {
            let lines = t.food.filter { !$0.isEmpty }.map { f -> String in
                let who = f.family.trimmed.isEmpty ? "Open" : f.family.trimmed
                let what = f.food.trimmed.isEmpty ? "TBD" : f.food.trimmed
                return "\(f.done ? "✅" : "•") \(who): \(what)"
            }
            if !lines.isEmpty { blocks.append((["TOURNAMENT FOOD"] + lines).joined(separator: "\n")) }
        }

        if options.hotels {
            let lines = t.hotels.filter { !$0.place.isEmpty }.map { h -> String in
                var parts = [h.place.name.trimmed.isEmpty ? "Hotel" : h.place.name.trimmed]
                if !h.place.address.trimmed.isEmpty { parts.append(h.place.address.trimmed) }
                if let rate = h.nightlyRate, rate > 0 { parts.append("\(TourneyMoney.format(rate))/night") }
                if !h.bookingCode.trimmed.isEmpty { parts.append("Code: \(h.bookingCode.trimmed)") }
                if let by = h.bookBy { parts.append("Book by \(dayF.string(from: by))") }
                if !h.phone.trimmed.isEmpty { parts.append(h.phone.trimmed) }
                if let url = TourneyLink.normalizedURL(h.link) { parts.append(url.absoluteString) }
                return "• " + parts.joined(separator: " · ")
            }
            if !lines.isEmpty { blocks.append((["HOTELS"] + lines).joined(separator: "\n")) }
        }

        if options.links {
            let lines = t.links.compactMap { link -> String? in
                guard let url = link.url else { return nil }
                return "\(link.displayTitle): \(url.absoluteString)"
            }
            if !lines.isEmpty { blocks.append((["LINKS"] + lines).joined(separator: "\n")) }
        }

        if options.notes, !t.notes.trimmed.isEmpty {
            blocks.append("NOTES\n\(t.notes.trimmed)")
        }
        return blocks.joined(separator: "\n\n")
    }
}

// MARK: - In-app share link

/// The link that opens a shared tourney in someone else's PitchMark:
/// `https://pitchmark-fb9f8.web.app/tourney/{shareId}`. The id is 32
/// random hex characters; the rules refuse shorter ones and never list the
/// collection, so a copy can't be found without its link.
enum TourneyShareLink {
    static let host = "pitchmark-fb9f8.web.app"
    static let minIdLength = 32

    static func newShareId() -> String {
        (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func url(for shareId: String) -> URL {
        URL(string: "https://\(host)/tourney/\(shareId)")!
    }

    /// The share id in a link (https or pitchmark://tourney/{id}), or a
    /// bare id pasted on its own. nil for anything else.
    static func shareId(from text: String) -> String? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        func valid(_ id: String) -> String? {
            let id = id.lowercased()
            guard id.count >= minIdLength, id.count <= 64,
                  id.allSatisfy({ $0.isHexDigit }) else { return nil }
            return id
        }
        if let id = valid(raw) { return id }
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch scheme {
        case "https":
            guard [host, "pitchmark-fb9f8.firebaseapp.com"].contains(url.host?.lowercased() ?? ""),
                  parts.count == 2, parts[0] == "tourney" else { return nil }
            return valid(parts[1])
        case "pitchmark":
            guard url.host?.lowercased() == "tourney", parts.count == 1 else { return nil }
            return valid(parts[0])
        default:
            return nil
        }
    }
}

// MARK: - Scouting (tourneys the staff might enter)

/// One tourney the coaching staff found and might enter. Basic fields
/// only, all free text except the dates, which are optional because a
/// listing often has none yet.
struct TourneyProspect: Identifiable, Equatable {
    var id: String = newId()
    var name: String = ""
    var organizer: String = ""
    var cost: String = ""
    var startDate: Date? = nil
    var endDate: Date? = nil
    var location: String = ""
    var distance: String = ""
    var links: [TourneyLink] = []
    var notes: String = ""
    var archivedAt: Date? = nil

    var isArchived: Bool { archivedAt != nil }
    var displayName: String { name.trimmed.isEmpty ? "Untitled Tourney" : name.trimmed }

    /// "Jun 6 - 8, 2027" / "Dates TBD".
    func dateText(calendar: Calendar = .current) -> String {
        guard let startDate else { return "Dates TBD" }
        var t = Tourney(now: startDate, calendar: calendar)
        t.startDate = startDate
        t.endDate = max(startDate, endDate ?? startDate)
        return t.dateRangeText(calendar: calendar)
    }

    /// Dated ones soonest first, then the undated, each by name.
    static func sortedForList(_ list: [TourneyProspect]) -> [TourneyProspect] {
        list.sorted { a, b in
            switch (a.startDate, b.startDate) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
        }
    }

    /// A Round Robin / Tourney Info page started from this listing.
    func makeTourney(now: Date = Date(), calendar: Calendar = .current) -> Tourney {
        var t = Tourney(now: now, calendar: calendar)
        t.name = name.trimmed
        if let startDate {
            t.startDate = startDate
            t.endDate = max(startDate, endDate ?? startDate)
        }
        if !location.trimmed.isEmpty { t.venue = TourneyPlace(address: location.trimmed) }
        t.links = links
        let extra = [organizer.trimmed.isEmpty ? nil : "Organizer: \(organizer.trimmed)",
                     cost.trimmed.isEmpty ? nil : "Cost: \(cost.trimmed)",
                     notes.trimmed.isEmpty ? nil : notes.trimmed].compactMap { $0 }
        t.notes = extra.joined(separator: "\n")
        return t
    }

    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "name": name, "organizer": organizer, "cost": cost, "location": location,
            "distance": distance, "links": links.map(\.firestoreData), "notes": notes,
        ]
        data["startDate"] = startDate.map { Timestamp(date: $0) } ?? NSNull()
        data["endDate"] = endDate.map { Timestamp(date: $0) } ?? NSNull()
        data["archivedAt"] = archivedAt.map { Timestamp(date: $0) } ?? NSNull()
        return data
    }

    init(id: String = newId(), name: String = "") {
        self.id = id
        self.name = name
    }

    init(id: String, firestoreData data: [String: Any]) {
        self.id = id
        name = data.string("name")
        organizer = data.string("organizer")
        cost = data.string("cost")
        location = data.string("location")
        distance = data.string("distance")
        links = data.maps("links").map(TourneyLink.init(firestoreData:))
        notes = data.string("notes")
        startDate = data.date("startDate")
        endDate = startDate.flatMap { s in data.date("endDate").map { max(s, $0) } }
        archivedAt = data.date("archivedAt")
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Store

/// The signed-in user's tourneys, live from `users/{uid}/tourneys`, the
/// shared tourneys they follow (`users/{uid}/followedTourneys`), and their
/// scouting list (`users/{uid}/tourneyProspects`).
@MainActor
final class TourneyStore: ObservableObject {
    @Published private(set) var tourneys: [Tourney] = []
    /// Tourneys of the teams this user is on (2026-11-22), live from
    /// `teams/{teamId}/tourneys`.
    @Published private(set) var teamTourneys: [Tourney] = []
    @Published private(set) var teams: [TeamAccess] = []

    /// A team this user is on, and whether they edit its schedule (the
    /// creator or a Scheduler) or only see it (a Family).
    struct TeamAccess: Identifiable, Equatable {
        var id: String
        var name: String
        var canEdit: Bool
    }

    private var teamListeners: [String: ListenerRegistration] = [:]
    private var teamTourneysByTeam: [String: [Tourney]] = [:]
    @Published private(set) var followed: [FollowedTourney] = []
    @Published private(set) var prospects: [TourneyProspect] = []
    @Published private(set) var errorMessage: String? = nil

    /// A shared tourney someone else's phone publishes; this user saved its
    /// link. `name` is a label for the list until the copy loads.
    struct FollowedTourney: Identifiable, Equatable {
        var id: String   // the share id
        var name: String
        var addedAt: Date
        /// General Info items this user added for themselves - kept on
        /// their own follow record, never on the coach's copy.
        var myItems: [TourneyChecklistItem] = []
    }

    private let inMemory: Bool
    private var uid: String? = nil
    private var listeners: [ListenerRegistration] = []

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
    }

    deinit {
        listeners.forEach { $0.remove() }
        teamListeners.values.forEach { $0.remove() }
    }

    /// Own and team tourneys together - one list for the coach.
    private var allTourneys: [Tourney] {
        let teamIds = Set(teamTourneys.map(\.id))
        return tourneys.filter { !teamIds.contains($0.id) } + teamTourneys
    }
    var active: [Tourney] { allTourneys.filter { !$0.isArchived } }
    var archived: [Tourney] { allTourneys.filter(\.isArchived) }

    /// Own tourneys always; a team's only for its creator and Schedulers.
    func canEdit(_ tourney: Tourney) -> Bool {
        guard let teamId = tourney.teamId else { return true }
        return teams.first { $0.id == teamId }?.canEdit ?? false
    }

    func teamName(_ teamId: String?) -> String? {
        guard let teamId else { return nil }
        return teams.first { $0.id == teamId }?.name
    }

    /// The teams a tourney can be put on: ones this user schedules for.
    var editableTeams: [TeamAccess] { teams.filter(\.canEdit) }

    /// Listens to each team's tourneys; stops listening to teams left.
    func startTeams(_ access: [TeamAccess]) {
        teams = access.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !inMemory else { return }
        let wanted = Set(access.map(\.id))
        for (id, listener) in teamListeners where !wanted.contains(id) {
            listener.remove()
            teamListeners[id] = nil
            teamTourneysByTeam[id] = nil
        }
        for team in access where teamListeners[team.id] == nil {
            teamListeners[team.id] = Self.teamCollection(team.id).addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error { return self.report("team tourneys listener", error, "Couldn't load a team's tourneys.") }
                    self.teamTourneysByTeam[team.id] = (snapshot?.documents ?? []).map {
                        Tourney(id: $0.documentID, firestoreData: $0.data())
                    }
                    self.publishTeamTourneys()
                }
            }
        }
        publishTeamTourneys()
    }

    private func publishTeamTourneys() {
        teamTourneys = teamTourneysByTeam.values.flatMap { $0 }
    }

    private static func teamCollection(_ teamId: String) -> CollectionReference {
        Firestore.firestore().collection("teams").document(teamId).collection("tourneys")
    }
    var activeProspects: [TourneyProspect] { TourneyProspect.sortedForList(prospects.filter { !$0.isArchived }) }
    var archivedProspects: [TourneyProspect] { prospects.filter(\.isArchived) }

    func tourney(id: String) -> Tourney? { allTourneys.first { $0.id == id } }
    func prospect(id: String) -> TourneyProspect? { prospects.first { $0.id == id } }

    func start(uid: String?) {
        guard !inMemory, uid != self.uid else { return }
        listeners.forEach { $0.remove() }
        listeners = []
        self.uid = uid
        tourneys = []
        followed = []
        prospects = []
        guard let uid, !uid.isEmpty else { return }
        let user = Firestore.firestore().collection("users").document(uid)
        listeners.append(user.collection("tourneys").addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if let error { return self.report("tourneys listener", error, "Couldn't load tourneys.") }
                self.errorMessage = nil
                self.tourneys = (snapshot?.documents ?? []).map { Tourney(id: $0.documentID, firestoreData: $0.data()) }
            }
        })
        listeners.append(user.collection("followedTourneys").addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if let error { return self.report("followed listener", error, "Couldn't load shared tourneys.") }
                self.followed = (snapshot?.documents ?? []).map {
                    let d = $0.data()
                    return FollowedTourney(id: $0.documentID, name: d["name"] as? String ?? "",
                                           addedAt: (d["addedAt"] as? Timestamp)?.dateValue() ?? Date(),
                                           myItems: ((d["myItems"] as? [[String: Any]]) ?? [])
                                               .compactMap(TourneyChecklistItem.init(firestoreData:)))
                }.sorted { $0.addedAt > $1.addedAt }
            }
        })
        listeners.append(user.collection("tourneyProspects").addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if let error { return self.report("prospects listener", error, "Couldn't load the scouting list.") }
                self.prospects = (snapshot?.documents ?? []).map { TourneyProspect(id: $0.documentID, firestoreData: $0.data()) }
            }
        })
    }

    private func report(_ what: String, _ error: Error, _ message: String) {
        debugLog("❌ \(what):", error.localizedDescription)
        errorMessage = "\(message) \(error.localizedDescription)"
    }

    private func userCollection(_ name: String) -> CollectionReference? {
        guard !inMemory, let uid else { return nil }
        return Firestore.firestore().collection("users").document(uid).collection(name)
    }

    private static func sharedDoc(_ shareId: String) -> DocumentReference {
        Firestore.firestore().collection("sharedTourneys").document(shareId)
    }

    // MARK: Own tourneys

    /// Saves the tourney, and its shared copy when it's shared - so people
    /// following it see each change. A team tourney is saved with its team;
    /// an own tourney given a team moves there (2026-11-22).
    func save(_ tourney: Tourney) {
        if let teamId = tourney.teamId {
            saveTeamTourney(tourney, teamId: teamId)
            return
        }
        if let index = tourneys.firstIndex(where: { $0.id == tourney.id }) {
            tourneys[index] = tourney
        } else {
            tourneys.append(tourney)
        }
        guard let collection = userCollection("tourneys"), let uid else { return }
        var data = tourney.firestoreData
        data["updatedAt"] = FieldValue.serverTimestamp()
        collection.document(tourney.id).setData(data) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in self?.report("tourney save", error, "Couldn't save the tourney.") }
        }
        saveSharedCopy(tourney, uid: uid)
    }

    private func saveTeamTourney(_ tourney: Tourney, teamId: String) {
        let wasOwn = tourneys.contains { $0.id == tourney.id }
        tourneys.removeAll { $0.id == tourney.id }
        var list = teamTourneysByTeam[teamId] ?? []
        if let index = list.firstIndex(where: { $0.id == tourney.id }) {
            list[index] = tourney
        } else {
            list.append(tourney)
        }
        teamTourneysByTeam[teamId] = list
        publishTeamTourneys()
        guard !inMemory, let uid else { return }
        var data = tourney.firestoreData
        data["updatedAt"] = FieldValue.serverTimestamp()
        Self.teamCollection(teamId).document(tourney.id).setData(data) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.report("team tourney save", error, "Couldn't save the tourney to the team.")
                    return
                }
                // Moved from this coach's own list: drop the old copy only
                // once the team has it.
                if wasOwn { self?.userCollection("tourneys")?.document(tourney.id).delete() }
            }
        }
        saveSharedCopy(tourney, uid: uid)
    }

    private func saveSharedCopy(_ tourney: Tourney, uid: String) {
        if let shareId = tourney.shareId, !inMemory {
            var shared = tourney.sharedData(ownerUid: uid)
            shared["updatedAt"] = FieldValue.serverTimestamp()
            Self.sharedDoc(shareId).setData(shared) { [weak self] error in
                guard let error else { return }
                Task { @MainActor in self?.report("shared tourney save", error, "Couldn't update the shared copy.") }
            }
        }
    }

    func setArchived(_ tourney: Tourney, _ archived: Bool) {
        var updated = tourney
        updated.archivedAt = archived ? Date() : nil
        save(updated)
    }

    /// Starts sharing (or keeps the existing link) and returns the link.
    @discardableResult
    func startSharing(_ tourney: Tourney) -> URL {
        var updated = tourney
        if updated.shareId == nil {
            updated.shareId = TourneyShareLink.newShareId()
            updated.shareOwnerUid = uid
        }
        save(updated)
        return TourneyShareLink.url(for: updated.shareId!)
    }

    /// Removes the shared copy; everyone's link stops working. The
    /// tourney itself is untouched.
    func stopSharing(_ tourney: Tourney) {
        guard let shareId = tourney.shareId else { return }
        var updated = tourney
        updated.shareId = nil
        updated.shareOwnerUid = nil
        save(updated)
        guard !inMemory else { return }
        Self.sharedDoc(shareId).delete { error in
            if let error { debugLog("❌ stop sharing:", error.localizedDescription) }
        }
    }

    // MARK: Following someone else's

    enum FollowError: LocalizedError {
        case badLink, notFound, ownTourney, notSignedIn
        var errorDescription: String? {
            switch self {
            case .badLink: return "That isn't a PitchMark tourney link."
            case .notFound: return "That tourney isn't shared any more, or the link is wrong."
            case .ownTourney: return "That's your own tourney - it's already in your list."
            case .notSignedIn: return "Sign in to save a shared tourney."
            }
        }
    }

    /// Checks the shared copy exists, then saves it to this user's list.
    func follow(linkOrId: String) async throws {
        guard let shareId = TourneyShareLink.shareId(from: linkOrId) else { throw FollowError.badLink }
        if tourneys.contains(where: { $0.shareId == shareId }) { throw FollowError.ownTourney }
        if inMemory {
            if !followed.contains(where: { $0.id == shareId }) {
                followed.insert(FollowedTourney(id: shareId, name: "", addedAt: Date()), at: 0)
            }
            return
        }
        guard let uid else { throw FollowError.notSignedIn }
        _ = try await Self.followShared(shareId: shareId, uid: uid)
    }

    /// Reads the shared copy and saves it to `uid`'s Shared with Me list;
    /// returns its name. Also used when a tourney link opens the app.
    static func followShared(shareId: String, uid: String) async throws -> String {
        let snapshot: DocumentSnapshot
        do {
            snapshot = try await sharedDoc(shareId).getDocument()
        } catch {
            throw FollowError.notFound
        }
        guard let data = snapshot.data() else { throw FollowError.notFound }
        if (data["ownerUid"] as? String) == uid { throw FollowError.ownTourney }
        let name = data["name"] as? String ?? ""
        try await Firestore.firestore().collection("users").document(uid)
            .collection("followedTourneys").document(shareId)
            .setData(["name": name, "addedAt": FieldValue.serverTimestamp()])
        return name
    }

    /// Takes it off this user's list. The owner's copy is untouched.
    func unfollow(_ shareId: String) {
        followed.removeAll { $0.id == shareId }
        userCollection("followedTourneys")?.document(shareId).delete()
    }

    /// Adds one of this user's own General Info items to a shared tourney.
    func addMyItem(_ text: String, to shareId: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let i = followed.firstIndex(where: { $0.id == shareId }) else { return }
        followed[i].myItems.append(TourneyChecklistItem(text: text))
        saveMyItems(shareId)
    }

    func removeMyItem(_ itemId: String, from shareId: String) {
        guard let i = followed.firstIndex(where: { $0.id == shareId }) else { return }
        followed[i].myItems.removeAll { $0.id == itemId }
        saveMyItems(shareId)
    }

    private func saveMyItems(_ shareId: String) {
        guard let f = followed.first(where: { $0.id == shareId }) else { return }
        userCollection("followedTourneys")?.document(shareId)
            .setData(["myItems": f.myItems.map(\.firestoreData)], merge: true)
    }

    /// Keeps the list's label in step with the copy's current name.
    func refreshFollowedName(_ shareId: String, _ name: String) {
        guard let i = followed.firstIndex(where: { $0.id == shareId }), followed[i].name != name else { return }
        followed[i].name = name
        userCollection("followedTourneys")?.document(shareId).setData(["name": name], merge: true)
    }

    // MARK: Scouting

    func save(_ prospect: TourneyProspect) {
        if let index = prospects.firstIndex(where: { $0.id == prospect.id }) {
            prospects[index] = prospect
        } else {
            prospects.append(prospect)
        }
        guard let collection = userCollection("tourneyProspects") else { return }
        var data = prospect.firestoreData
        data["updatedAt"] = FieldValue.serverTimestamp()
        collection.document(prospect.id).setData(data) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in self?.report("prospect save", error, "Couldn't save the scouting entry.") }
        }
    }

    func setArchived(_ prospect: TourneyProspect, _ archived: Bool) {
        var updated = prospect
        updated.archivedAt = archived ? Date() : nil
        save(updated)
    }
}

/// Live read of one shared tourney, for the read-only page.
@MainActor
final class SharedTourneyListener: ObservableObject {
    enum State: Equatable { case loading, loaded(Tourney), gone }
    @Published private(set) var state: State = .loading
    private var listener: ListenerRegistration? = nil

    init(shareId: String, preview: Tourney? = nil) {
        if let preview {
            state = .loaded(preview)
            return
        }
        listener = Firestore.firestore().collection("sharedTourneys").document(shareId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let data = snapshot?.data() {
                        self.state = .loaded(Tourney(id: shareId, firestoreData: data))
                    } else if error != nil || snapshot?.exists == false {
                        self.state = .gone
                    }
                }
            }
    }

    deinit { listener?.remove() }
}
