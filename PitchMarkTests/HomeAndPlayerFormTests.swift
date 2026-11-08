//
//  HomeAndPlayerFormTests.swift
//  PitchMarkTests
//
//  Rules 50-52 (approved 2026-11-05): number-only players and the Home
//  games calendar.
//

import XCTest
@testable import PitchMark

final class HomeAndPlayerFormTests: XCTestCase {

    /// Rule 50: number only saves "#12" and needs a jersey; otherwise a
    /// typed name is needed.
    func testNumberOnlySavedName() {
        XCTAssertEqual(NumberOnlyName.savedName(typed: "", jersey: " 12 ", numberOnly: true), "#12")
        XCTAssertEqual(NumberOnlyName.savedName(typed: "Ava Smith", jersey: "12", numberOnly: true), "#12",
                       "a typed name is ignored once number only is on")
        XCTAssertNil(NumberOnlyName.savedName(typed: "Ava", jersey: "", numberOnly: true), "no jersey, nothing to save")
        XCTAssertEqual(NumberOnlyName.savedName(typed: " Ava Smith ", jersey: "", numberOnly: false), "Ava Smith")
        XCTAssertNil(NumberOnlyName.savedName(typed: "  ", jersey: "12", numberOnly: false), "a name is still needed")
    }

    /// Rule 51: the avatar shows the whole number for a number-only
    /// player; a normal name keeps its initials.
    func testAvatarText() {
        XCTAssertEqual(NumberOnlyName.avatarText(for: "#12", fallback: "?"), "12")
        XCTAssertEqual(NumberOnlyName.avatarText(for: "#00", fallback: "?"), "00")
        XCTAssertEqual(NumberOnlyName.avatarText(for: "Ava Smith", fallback: "?"), "AS")
        XCTAssertEqual(NumberOnlyName.avatarText(for: "#12 Smith", fallback: "?"), "#S", "not number-only")
        XCTAssertNil(NumberOnlyName.number(in: "#12 Smith"))
        XCTAssertNil(NumberOnlyName.number(in: "#1 A"), "a space means it's a name, even a short one")
        XCTAssertEqual(NumberOnlyName.number(in: "#7"), "7", "how the edit sheet knows to start on number only")
        XCTAssertEqual(NumberOnlyName.avatarText(for: "", fallback: "?"), "?")
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        cal.firstWeekday = 1
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func game(_ date: Date) -> Game {
        Game(opponent: "Opp", date: date, jerseyNumbers: [])
    }

    /// Rule 52: month layout, games by day, and the month it opens on.
    func testCalendarMonthAndGames() {
        // November 2026 starts on a Sunday and has 30 days; October 2026
        // starts on a Thursday (4 blanks).
        let november = GameCalendar.monthCells(for: date(2026, 11, 15), calendar: calendar)
        XCTAssertEqual(november.count, 30)
        XCTAssertEqual(november.first??.timeIntervalSince1970, calendar.startOfDay(for: date(2026, 11, 1)).timeIntervalSince1970)
        let october = GameCalendar.monthCells(for: date(2026, 10, 15), calendar: calendar)
        XCTAssertEqual(october.prefix(4).filter { $0 == nil }.count, 4)
        XCTAssertNotNil(october[4])
        XCTAssertEqual(october.count, 4 + 31)

        let morning = game(date(2026, 10, 3, hour: 9))
        let evening = game(date(2026, 10, 3, hour: 19))
        let later = game(date(2026, 10, 20))
        let byDay = GameCalendar.gamesByDay([morning, evening, later], calendar: calendar)
        XCTAssertEqual(byDay[calendar.startOfDay(for: date(2026, 10, 3))]?.map(\.date), [evening.date, morning.date])
        XCTAssertEqual(byDay[calendar.startOfDay(for: date(2026, 10, 20))]?.count, 1)

        let today = date(2026, 11, 5)
        XCTAssertEqual(GameCalendar.initialMonth(games: [morning, later], today: today, calendar: calendar),
                       calendar.startOfDay(for: date(2026, 10, 1)), "no game this month: the latest month with one")
        XCTAssertEqual(GameCalendar.initialMonth(games: [morning, game(date(2026, 11, 2))], today: today, calendar: calendar),
                       calendar.startOfDay(for: date(2026, 11, 1)))
        XCTAssertEqual(GameCalendar.initialMonth(games: [morning, game(date(2026, 11, 20))], today: today, calendar: calendar),
                       calendar.startOfDay(for: date(2026, 11, 1)), "a game later this month still opens on this month")
        XCTAssertEqual(GameCalendar.initialMonth(games: [], today: today, calendar: calendar),
                       calendar.startOfDay(for: date(2026, 11, 1)))
    }
}

/// Rules 55-56 (approved 2026-11-05): Home's Add Player form.
final class HomeAddPlayerTests: XCTestCase {
    private func team(_ id: String) -> Team {
        Team(id: id, name: id, createdByUid: "me")
    }

    /// Rule 55: starts on the first team in list order; no teams, no team.
    func testDefaultTeam() {
        XCTAssertEqual(HomeAddPlayer.defaultTeamId([team("Zebras"), team("Bombers")]), "Bombers",
                       "list order (A-Z for teams without a season), not the order given")
        XCTAssertNil(HomeAddPlayer.defaultTeamId([]))
    }

    /// Rule 56: number only needs a team; with no team a name is required.
    func testNumberOnlyNeedsATeam() {
        XCTAssertEqual(HomeAddPlayer.savedName(typed: "", jersey: "12", numberOnly: true, hasTeam: true), "#12")
        XCTAssertNil(HomeAddPlayer.savedName(typed: "", jersey: "12", numberOnly: true, hasTeam: false),
                     "no team: the number has nowhere to live")
        XCTAssertEqual(HomeAddPlayer.savedName(typed: "Ava", jersey: "12", numberOnly: true, hasTeam: false), "Ava")
        XCTAssertEqual(HomeAddPlayer.savedName(typed: "Ava", jersey: "", numberOnly: false, hasTeam: true), "Ava")
    }
}
