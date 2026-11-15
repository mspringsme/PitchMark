//
//  CallSheetTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-14: the Call Sheet. A call never gets the same code
//  twice in a row, every code is used evenly, the codes are the armband's
//  (the calling card's numbers; the printed key's codes for that pitch and
//  spot), and Recent keeps the last 8.
//

import XCTest
@testable import PitchMark

final class CallSheetTests: XCTestCase {

    // MARK: Rotation

    func testACallNeverGetsTheSameCodeTwiceInARow() {
        for count in 2...6 {
            var rotation = CodeRotation()
            let codes = (1...count).map { "C\($0)" }
            var last: String?
            for _ in 0..<300 {
                let code = rotation.next(for: "STEAL", from: codes)
                XCTAssertNotNil(code)
                XCTAssertNotEqual(code, last, "\(count) codes")
                last = code
            }
        }
    }

    func testEveryCodeIsUsedWithinOneOfTheOthers() {
        var rotation = CodeRotation()
        let codes = ["111", "232", "313", "424"]
        var counts: [String: Int] = [:]
        for _ in 0..<101 {
            let code = rotation.next(for: "BUNT", from: codes)!
            counts[code, default: 0] += 1
            let values = codes.map { counts[$0] ?? 0 }
            XCTAssertLessThanOrEqual(values.max()! - values.min()!, 1)
        }
    }

    func testAOneCodeCallAlwaysGetsItAndANoCodeCallGetsNothing() {
        var rotation = CodeRotation()
        for _ in 0..<5 {
            XCTAssertEqual(rotation.next(for: "TAKE", from: ["212"]), "212")
        }
        XCTAssertNil(rotation.next(for: "NONE", from: []))
    }

    func testEachCallRotatesOnItsOwn() {
        var rotation = CodeRotation()
        let first = rotation.next(for: "A", from: ["1", "2"], pick: { $0.first })
        _ = rotation.next(for: "B", from: ["1", "2"], pick: { $0.first })
        XCTAssertEqual(first, "1")
        XCTAssertEqual(rotation.next(for: "A", from: ["1", "2"], pick: { $0.first }), "2",
                       "B's call doesn't count against A")
    }

    // MARK: Batting & Fielding

    private func card() -> SignGridCallingCard {
        var grid = SignGrid(name: "Signs", rows: 4, columns: 4, gridCount: 2)
        grid.setText("STEAL", row: 1, column: 1, in: 0)
        grid.setText("STEAL", row: 2, column: 3, in: 0)
        grid.setText("STEAL", row: 3, column: 2, in: 1)
        grid.setText("BUNT", row: 2, column: 2, in: 1)
        return SignGridCallingCard(grid: grid)
    }

    func testEveryNumberGivenIsThatCallsNumberOnTheCard() {
        let card = card()
        var caller = SignGridCaller(card: card)
        let steal = Set(card.calls.first { $0.label == "STEAL" }!.codes)
        XCTAssertEqual(steal.count, 3)
        var seen: Set<String> = []
        for _ in 0..<30 {
            let called = caller.call("STEAL")!
            XCTAssertTrue(steal.contains(called.code))
            seen.insert(called.code)
        }
        XCTAssertEqual(seen, steal, "every number gets used")
        XCTAssertEqual(caller.call("BUNT")?.code, card.calls.first { $0.label == "BUNT" }!.codes.first)
        XCTAssertNil(caller.call("SQUEEZE"), "not on the card")
    }

    func testRecentKeepsTheLastEightNewestFirst() {
        var caller = SignGridCaller(card: card())
        var made: [SignGridCaller.Called] = []
        for i in 0..<12 {
            made.append(caller.call(i.isMultiple(of: 2) ? "STEAL" : "BUNT")!)
        }
        XCTAssertEqual(caller.recent.count, SignGridCaller.recentLimit)
        XCTAssertEqual(caller.recent, Array(made.suffix(8).reversed()))
    }

    // MARK: Pitching

    private func gridKey(_ mode: PitchCodeMode) -> PitchTemplate {
        let names = ["Fastball", "Change", "Curve"]
        var grid: [[String]] = [[""] + ["FB", "CH", "CU"]]
        for row in 0..<3 {
            grid.append(["AB"] + (0..<3).map { "\(($0 + row) % 9 + 1)" })
        }
        var t = PitchTemplate(id: UUID(), name: "Test Key", pitches: names, codeAssignments: [])
        t.pitchGridHeaders = names.map { PitchHeader(pitch: $0, abbreviation: String($0.prefix(2)).uppercased()) }
        t.pitchGridValues = grid
        t.strikeTopRow = ["A", "B", "C"]
        t.strikeRows = [["", "", ""], ["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]
        t.ballsTopRow = ["D", "E", "F"]
        t.ballsRows = t.strikeRows
        t.codeMode = mode
        t.strikeLocationCells = [["A", "B", "C"], ["D", "E", "F"], ["G", "H", "J"]]
        t.ballsLocationCells = [["K", "L", "M"], ["N", "", "P"], ["Q", "R", "S"]]
        return t
    }

    /// The store's printed location sheet lists codes per pitch for each of
    /// these spots; the pad's same spot must give the same codes.
    func testEverySpotGivesThePrintedSheetsCodesForThatPitchAndSpot() {
        for mode in [PitchCodeMode.advanced, .normal] {
            let key = gridKey(mode)
            let caller = PitchKeyCaller(template: key)
            XCTAssertTrue(caller.usesGrid)
            XCTAssertEqual(caller.pitches.map(\.name), ["Fastball", "Change", "Curve"])
            for pitch in caller.pitches {
                for location in strikePrintableLocations + ballPrintableLocations {
                    let spot = PitchKeySpot(isStrike: location.gridKind == .strikes, row: location.row, column: location.col)
                    XCTAssertTrue(spot.exists, location.title)
                    let printed = mode == .normal
                        ? EncryptedCodeGenerator.generateNormalCalls(template: key, selectedPitch: pitch.name,
                            gridKind: location.gridKind, columnIndex: location.col, rowIndex: location.row)
                        : EncryptedCodeGenerator.generateCalls(template: key, selectedPitch: pitch.name,
                            gridKind: location.gridKind, columnIndex: location.col, rowIndex: location.row)
                    let onScreen = caller.codes(for: pitch, at: spot)
                    XCTAssertFalse(onScreen.isEmpty, "\(mode) \(pitch.name) \(location.title)")
                    XCTAssertEqual(Set(onScreen), Set(printed.filter { !$0.isEmpty }), "\(mode) \(pitch.name) \(location.title)")
                }
            }
        }
    }

    func testThePadHasThePrintedSheetsSpotsAndNoBallMiddle() {
        let printed = Set((strikePrintableLocations + ballPrintableLocations).map {
            PitchKeySpot(isStrike: $0.gridKind == .strikes, row: $0.row, column: $0.col)
        })
        let pad = Set((PitchKeySpot.all(isStrike: true) + PitchKeySpot.all(isStrike: false)).filter(\.exists))
        XCTAssertEqual(pad, printed)
        let ballMiddle = PitchKeySpot(isStrike: false, row: 1, column: 1)
        XCTAssertFalse(ballMiddle.exists)
        let caller = PitchKeyCaller(template: gridKey(.advanced))
        XCTAssertTrue(caller.codes(for: caller.pitches[0], at: ballMiddle).isEmpty)
    }

    func testAPitchCallRotatesAndIsShownSplitLikeThePrint() {
        var caller = PitchKeyCaller(template: gridKey(.advanced))
        let pitch = caller.pitches[0]
        let spot = PitchKeySpot(isStrike: true, row: 0, column: 0)
        let codes = caller.codes(for: pitch, at: spot)
        XCTAssertGreaterThan(codes.count, 1)
        var last: String?
        for _ in 0..<20 {
            let called = caller.call(pitch, at: spot)!
            XCTAssertTrue(codes.contains(called.code))
            XCTAssertNotEqual(called.code, last)
            last = called.code
        }
        XCTAssertEqual(caller.recent.count, PitchKeyCaller.recentLimit)
        XCTAssertEqual(caller.display("4K7A"), "4K·7A")
    }

    func testAClassicKeyUsesItsTypedCodesForTheSpotsName() {
        let key = PitchTemplate(
            id: UUID(), name: "Classic", pitches: ["Fastball"],
            codeAssignments: [
                PitchCodeAssignment(code: "11", pitch: "Fastball", location: "Strike Up & In"),
                PitchCodeAssignment(code: "12", pitch: "Fastball", location: "Strike Up & In"),
                PitchCodeAssignment(code: "99", pitch: "Fastball", location: "Ball ↓")
            ]
        )
        let caller = PitchKeyCaller(template: key)
        XCTAssertFalse(caller.usesGrid)
        let fastball = caller.pitches[0]
        XCTAssertEqual(Set(caller.codes(for: fastball, at: PitchKeySpot(isStrike: true, row: 0, column: 2))), ["11", "12"])
        XCTAssertEqual(caller.codes(for: fastball, at: PitchKeySpot(isStrike: false, row: 2, column: 1)), ["99"])
        XCTAssertTrue(caller.codes(for: fastball, at: PitchKeySpot(isStrike: true, row: 1, column: 1)).isEmpty)
        XCTAssertEqual(caller.display("11"), "11", "typed codes aren't split")
    }

    func testAKeyWithNoPitchesHasNothingToCall() {
        let caller = PitchKeyCaller(template: PitchTemplate(id: UUID(), name: "Empty", pitches: [], codeAssignments: []))
        XCTAssertTrue(caller.pitches.isEmpty)
    }
}
