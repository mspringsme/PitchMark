//
//  TradingCardTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-19 (trading cards):
//  U1 every card side is 2.5 x 3.5 in plus 1/8 in bleed, front then back,
//     and a team order's pages come out in the right order
//  U2 long names and numbers shrink to fit the template and never overflow
//     - measured, on every template
//  U3 the stats on the back equal the stats screens' numbers
//  Plus: a saved design holds no birthdate, school or hometown.
//

import XCTest
import UIKit
@testable import PitchMark

final class TradingCardTests: XCTestCase {

    private func design(_ template: TradingCardTemplate, name: String = "Ava Smith", number: String = "12") -> TradingCardDesign {
        TradingCardDesign(template: template, teamName: "Lightning 12U", playerName: name, jerseyNumber: number,
                          position: "SS / P", batsThrows: "Bats Right", favoritePlayer: "Jennie Finch",
                          funFact: "Loves sunflower seeds", stats: [TradingCardStat(label: "AVG", value: ".412")],
                          statsLabel: "Career")
    }

    // MARK: U1 size and order

    func testEverySideIsTheCardSizeWithBleed() {
        XCTAssertEqual(TradingCardProduct.pixelSize, CGSize(width: 825, height: 1125))
        XCTAssertEqual(TradingCardProduct.pageSize.width, 2.75 * 72, accuracy: 0.01)
        XCTAssertEqual(TradingCardProduct.pageSize.height, 3.75 * 72, accuracy: 0.01)
        for template in TradingCardTemplate.allCases {
            let front = TradingCardRenderer.renderFront(design(template), photo: nil)
            let back = TradingCardRenderer.renderBack(design(template))
            for (side, image) in [("front", front), ("back", back)] {
                XCTAssertEqual(image.size.width * image.scale, 825, "\(template) \(side) width")
                XCTAssertEqual(image.size.height * image.scale, 1125, "\(template) \(side) height")
            }
        }
    }

    func testATeamOrderPrintsEachSetByNumberFrontThenBack() {
        let cards = [
            TeamCardSetPlan.Card(id: "c", playerName: "Cara", jerseyNumber: ""),
            TeamCardSetPlan.Card(id: "b", playerName: "Bea", jerseyNumber: "22"),
            TeamCardSetPlan.Card(id: "a", playerName: "Ava", jerseyNumber: "7")
        ]
        let pages = TeamCardSetPlan.pages(cards, sets: 2)
        XCTAssertEqual(pages.count, 2 * 3 * 2)
        let firstSet = pages.prefix(6).map { "\($0.id)\($0.isFront ? "F" : "B")" }
        XCTAssertEqual(firstSet, ["aF", "aB", "bF", "bB", "cF", "cB"], "by number (7, 22), numberless last, front then back")
        XCTAssertEqual(pages.prefix(6).map(\.set), Array(repeating: 0, count: 6))
        XCTAssertEqual(pages.suffix(6).map(\.set), Array(repeating: 1, count: 6))
        XCTAssertEqual(pages.suffix(6).map(\.id), pages.prefix(6).map(\.id), "every set is the same cards")
    }

    /// Siblings (2026-11-20): one family's two entries are two cards.
    func testOneFamilysTwoPlayersAreTwoCards() {
        let consented: (String) -> [String: Any] = { name in
            ["ownerUid": "smiths", "playerName": name, "jerseyNumber": "", "consent": true,
             "frontPath": "f", "backPath": "b"]
        }
        let ava = TeamCardEntry(id: "ava-card", data: consented("Ava"))
        let bea = TeamCardEntry(id: "bea-card", data: consented("Bea"))
        XCTAssertEqual(ava?.ownerUid, "smiths")
        let pages = TeamCardSetPlan.pages([ava, bea].compactMap { $0?.planCard }, sets: 1)
        XCTAssertEqual(Set(pages.map(\.id)), ["ava-card", "bea-card"])
        XCTAssertNil(TeamCardEntry(id: "x", data: ["playerName": "No owner", "consent": true]), "an entry with no owner")
        XCTAssertNil(TeamCardEntry(id: "y", data: ["ownerUid": "smiths", "playerName": "No consent"]), "an entry with no consent")
    }

    func testTheTeamSetPDFHasOneCardSizedPagePerSide() throws {
        let cards = [TeamCardSetPlan.Card(id: "a", playerName: "Ava", jerseyNumber: "7"),
                     TeamCardSetPlan.Card(id: "b", playerName: "Bea", jerseyNumber: "22")]
        let art = Dictionary(uniqueKeysWithValues: cards.map { card in
            (card.id, (front: TradingCardRenderer.renderFront(design(.classic, name: card.playerName), photo: nil),
                        back: TradingCardRenderer.renderBack(design(.classic, name: card.playerName))))
        })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("team-cards-test.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let written = try TeamCardSetPlan.writePDF(cards, sets: 3, art: art, to: url)
        XCTAssertEqual(written, 12)
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(document.numberOfPages, 12)
        for number in 1...document.numberOfPages {
            let box = try XCTUnwrap(document.page(at: number)).getBoxRect(.mediaBox)
            XCTAssertEqual(box.width, 2.75 * 72, accuracy: 0.01)
            XCTAssertEqual(box.height, 3.75 * 72, accuracy: 0.01)
        }
    }

    func testPricesMatchTheServer() {
        XCTAssertEqual(TradingCardProduct.FamilyPack.twelve.priceCents, 1499)
        XCTAssertEqual(TradingCardProduct.FamilyPack.twentyFour.priceCents, 1999)
        XCTAssertEqual(TradingCardProduct.FamilyPack.twelve.retailProductId, "card_family_12")
        XCTAssertEqual(TradingCardProduct.teamSetPriceCents(sets: 13), 13 * 1299)
        XCTAssertEqual(TradingCardProduct.maxSets, 60)
        XCTAssertEqual(TradingCardProduct.minPlayers, 2)
    }

    // MARK: U2 text fits

    func testLongNamesAndNumbersNeverOverflowAnyTemplate() {
        let longName = "Maximiliana Montgomery-Fitzgerald"
        let longTeam = "North County Thunder Lightning 14U Gold"
        for template in TradingCardTemplate.allCases {
            let layout = template.front
            let checks: [(String, String, CGRect, CGFloat, CGFloat)] = [
                ("name", longName, layout.name, 72, 30),
                ("number", "#9999", layout.number, template == .bold ? 150 : 84, 36),
                ("team", longTeam, layout.team, 42, 22),
                ("position", "P / C / 1B / SS / CF", layout.position, 40, 22)
            ]
            for (part, text, box, base, min) in checks {
                let fitted = TradingCardText.fit(text, width: box.width, base: base, min: min)
                let width = TradingCardText.measure(fitted.text, fitted.font)
                XCTAssertLessThanOrEqual(width, box.width, "\(template) \(part) overflows: \(fitted.text)")
                XCTAssertGreaterThanOrEqual(fitted.font.pointSize, min, "\(template) \(part) shrank below its floor")
                XCTAssertLessThanOrEqual(fitted.font.lineHeight, box.height + 1, "\(template) \(part) taller than its box")
                let full = CGRect(origin: .zero, size: TradingCardProduct.pixelSize)
                XCTAssertTrue(full.contains(box), "\(template) \(part) box is off the card")
            }
        }
    }

    /// Found on the first look at real renders: the fit test passed while
    /// Diamond's name ran into its number. No two text boxes may overlap.
    func testNoTwoTextBoxesOverlapOnAnyTemplate() {
        for template in TradingCardTemplate.allCases {
            let layout = template.front
            let boxes = [("name", layout.name), ("number", layout.number), ("team", layout.team), ("position", layout.position)]
            for i in boxes.indices {
                for j in boxes.indices where j > i {
                    XCTAssertFalse(boxes[i].1.intersects(boxes[j].1),
                                   "\(template): \(boxes[i].0) overlaps \(boxes[j].0)")
                }
            }
        }
    }

    func testTextThatCantFitIsShortenedNotSpilled() {
        let fitted = TradingCardText.fit(String(repeating: "W", count: 80), width: 200, base: 40, min: 30)
        XCTAssertTrue(fitted.text.hasSuffix("…"))
        XCTAssertLessThanOrEqual(TradingCardText.measure(fitted.text, fitted.font), 200)
        let short = TradingCardText.fit("Ava", width: 600, base: 72, min: 30)
        XCTAssertEqual(short.text, "Ava")
        XCTAssertEqual(short.font.pointSize, 72, "short text keeps the full size")
    }

    // MARK: U3 stats

    func testTheBackShowsTheStatsScreensNumbers() {
        var line = HittingStatLine()
        line.plateAppearances = 14
        line.atBats = 11
        line.hits = 5
        line.doubles = 2
        line.homeRuns = 1
        line.walks = 2
        line.hitByPitch = 1
        line.runsBattedIn = 4
        line.stolenBases = 3
        let stats = Dictionary(uniqueKeysWithValues: TradingCardStats.lines(from: line).map { ($0.label, $0.value) })
        // The same calls HitterStatsView's grid makes.
        XCTAssertEqual(stats["AVG"], HittingStatLine.formatRate(line.average))
        XCTAssertEqual(stats["OBP"], HittingStatLine.formatRate(line.onBase))
        XCTAssertEqual(stats["AVG"], ".455")
        XCTAssertEqual(stats["H"], "5")
        XCTAssertEqual(stats["2B"], "2")
        XCTAssertEqual(stats["HR"], "1")
        XCTAssertEqual(stats["RBI"], "4")
        XCTAssertEqual(stats["BB"], "2")
        XCTAssertEqual(stats["SB"], "3")
        XCTAssertEqual(TradingCardStats.lines(from: line).map(\.label), TradingCardStats.labels)
    }

    func testNoAtBatsShowsADashLikeTheStatsScreen() {
        let stats = TradingCardStats.lines(from: HittingStatLine())
        XCTAssertEqual(stats.first { $0.label == "AVG" }?.value, "—")
    }

    // MARK: Saved design

    func testASavedDesignHoldsNoBirthdateSchoolOrHometown() {
        let data = design(.bold).firestoreData
        let allowed: Set<String> = ["templateId", "teamId", "teamName", "teamPlayerId", "hitterId", "playerName",
                                    "jerseyNumber", "position", "batsThrows", "favoritePlayer", "funFact",
                                    "stats", "statsLabel", "createdAt", "updatedAt"]
        XCTAssertEqual(Set(data.keys), allowed)
        XCTAssertNotNil(data["stats"] as? [[String: Any]], "stats are an array of maps")
        let loaded = TradingCardDesign(id: "d1", data: data)
        XCTAssertEqual(loaded?.playerName, "Ava Smith")
        XCTAssertEqual(loaded?.template, .bold)
        XCTAssertEqual(loaded?.stats, [TradingCardStat(label: "AVG", value: ".412")])
    }
}
