//
//  CardHeaderTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-21 (item 6): a card's header is its own pitcher vs. the
//  team at bat for that pitch (whoever wasn't fielding), with the batter's
//  number - "Cassie vs. Hawks #7". It used to show the game's opponent,
//  backwards whenever the other team's pitcher threw.
//

import XCTest
@testable import PitchMark

final class CardHeaderTests: XCTestCase {
    private let matchup = CardMatchupNames(homeTeamId: "lightning", homeName: "Lightning",
                                           awayTeamId: "hawks", awayName: "Hawks")

    private func event(fielding: String?, jersey: String?) -> PitchEvent {
        var event = PitchEvent(
            id: "e1", timestamp: Date(), pitch: "Rise", location: "Strike Up", codes: [],
            isStrike: true, isBall: false, mode: .game, calledPitch: nil, batterSide: .right,
            templateId: nil, strikeSwinging: false, wildPitch: false, passedBall: false,
            strikeLooking: false, outcome: nil, descriptor: nil, errorOnPlay: false,
            battedBallRegion: nil, battedBallType: nil, battedBallTapX: nil, battedBallTapY: nil,
            gameId: "g1", opponentJersey: jersey, opponentBatterId: nil, pitcherId: "p1"
        )
        event.fieldingTeamId = fielding
        return event
    }

    func testOurPitcherFacesTheirBatters() {
        XCTAssertEqual(CardHeader.title(pitcherName: "Cassie", event: event(fielding: "lightning", jersey: "7"),
                                        matchup: matchup, fallbackOpponent: "Hawks"), "Cassie vs. Hawks #7")
    }

    func testTheirPitcherFacesOurBatters() {
        XCTAssertEqual(CardHeader.title(pitcherName: "Lockport #12", event: event(fielding: "hawks", jersey: "3"),
                                        matchup: matchup, fallbackOpponent: "Hawks"), "Lockport #12 vs. Lightning #3",
                       "not the pitcher's own team")
    }

    func testNoBatterNumberWhenNoneIsSelected() {
        XCTAssertEqual(CardHeader.title(pitcherName: "Cassie", event: event(fielding: "lightning", jersey: nil),
                                        matchup: matchup, fallbackOpponent: nil), "Cassie vs. Hawks")
        XCTAssertEqual(CardHeader.title(pitcherName: "Cassie", event: event(fielding: "lightning", jersey: " "),
                                        matchup: matchup, fallbackOpponent: nil), "Cassie vs. Hawks")
    }

    func testOlderPitchesWithNoFieldingTeamUseTheGamesOpponent() {
        XCTAssertEqual(CardHeader.title(pitcherName: "Cassie", event: event(fielding: nil, jersey: "7"),
                                        matchup: matchup, fallbackOpponent: "Hawks"), "Cassie vs. Hawks #7")
        XCTAssertEqual(CardHeader.title(pitcherName: "Cassie", event: event(fielding: nil, jersey: nil),
                                        matchup: nil, fallbackOpponent: nil), "Cassie")
    }
}
