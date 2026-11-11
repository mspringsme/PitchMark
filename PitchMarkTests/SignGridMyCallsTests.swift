import XCTest
@testable import PitchMark

/// My Calls and Randomize (approved 2026-11-10).
@MainActor
final class SignGridMyCallsTests: XCTestCase {

    /// Repeatable randomness, so a failure can be replayed.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    // MARK: My Calls

    func testAddingATypedCallPutsItInMyCallsOnce() {
        var calls = SignGridMyCalls()
        XCTAssertTrue(calls.add("  Squeeze  "))
        XCTAssertEqual(calls.labels, ["Squeeze"], "trimmed")
        XCTAssertFalse(calls.add("squeeze"), "no repeats, ignoring case")
        XCTAssertFalse(calls.add("   "), "blank is ignored")
        XCTAssertFalse(calls.add(""))
        XCTAssertFalse(calls.add("h&r"), "already in the built-in list")
        XCTAssertTrue(calls.contains("H&R"))
        XCTAssertTrue(calls.add(String(repeating: "x", count: 40)))
        XCTAssertEqual(calls.labels.last?.count, SignGrid.maxCellLength, "no longer than a cell")
        XCTAssertEqual(calls.labels.count, 2)
    }

    func testMyCallsSaveLoadAndRemove() {
        var calls = SignGridMyCalls()
        calls.add("Squeeze")
        calls.add("Wheel")
        calls.add("Slash")
        let back = SignGridMyCalls(firestoreData: calls.firestoreData)
        XCTAssertEqual(back, calls)
        XCTAssertEqual(back.labels, ["Squeeze", "Wheel", "Slash"], "in the order added")
        XCTAssertFalse((calls.firestoreData["items"] as? [Any])?.contains { $0 is [Any] } ?? true, "no nested arrays")

        var removed = back
        removed.remove("Wheel")
        XCTAssertEqual(removed.labels, ["Squeeze", "Slash"])
        XCTAssertTrue(removed.add("Wheel"), "a removed call can be added again")

        let messy = SignGridMyCalls(firestoreData: ["items": [["label": "A"], ["label": "a"], ["nope": 1], ["label": " "]]])
        XCTAssertEqual(messy.labels, ["A"])
        XCTAssertTrue(SignGridMyCalls(firestoreData: [:]).labels.isEmpty)
    }

    func testTheStoreAddsAndRemoves() {
        let store = SignGridMyCallsStore(inMemory: true)
        store.add("Squeeze")
        store.add("SQUEEZE")
        XCTAssertEqual(store.calls.labels, ["Squeeze"])
        store.remove("Squeeze")
        XCTAssertTrue(store.calls.labels.isEmpty)
    }

    // MARK: Randomize

    func testRandomizeFillsOnlyEmptyCallCellsWithThePickedCalls() {
        var grid = SignGrid(rows: 5, columns: 5, gridCount: 3)
        grid.setText("KEEP", row: 2, column: 2, in: 1)
        grid.setText("Mine", row: 4, column: 4, in: 0)
        let before = grid
        var generator = SeededGenerator(state: 7)
        let filled = grid.randomFill(with: ["TAKE", "STEAL"], using: &generator)
        XCTAssertEqual(filled, 3 * 4 * 4 - 2)
        XCTAssertTrue(grid.emptyCallCells.isEmpty)
        for g in 0..<3 {
            for r in 0..<5 {
                for c in 0..<5 {
                    let now = grid.text(row: r, column: c, in: g), was = before.text(row: r, column: c, in: g)
                    if r == 0 || c == 0 {
                        XCTAssertEqual(now, was, "numbers untouched at \(g).\(r).\(c)")
                    } else if !was.isEmpty {
                        XCTAssertEqual(now, was, "typed cell kept at \(g).\(r).\(c)")
                    } else {
                        XCTAssertTrue(["TAKE", "STEAL"].contains(now), "\(now) wasn't picked")
                    }
                }
            }
        }
        var again = grid
        XCTAssertEqual(again.randomFill(with: ["BUNT"], using: &generator), 0, "nothing left to fill")
        XCTAssertEqual(again, grid)
        var none = before
        XCTAssertEqual(none.randomFill(with: [], using: &generator), 0, "no picks, no change")
        XCTAssertEqual(none, before)
    }

    func testRandomizeSpreadsEvenlyAndUsesEveryPick() {
        let picks = ["TAKE", "SWING", "H&R", "STEAL", "BUNT"]
        for seed in UInt64(1)...25 {
            var grid = SignGrid(rows: 6, columns: 6, gridCount: 2)   // 50 call cells
            var generator = SeededGenerator(state: seed)
            grid.randomFill(with: picks, using: &generator)
            var counts: [String: Int] = [:]
            for g in 0..<2 { for r in 1..<6 { for c in 1..<6 { counts[grid.text(row: r, column: c, in: g), default: 0] += 1 } } }
            XCTAssertEqual(Set(counts.keys), Set(picks), "seed \(seed): every pick lands somewhere")
            XCTAssertLessThanOrEqual(counts.values.max()! - counts.values.min()!, 1, "seed \(seed): evenly \(counts)")
        }
        // Random spots: different seeds give different layouts.
        var a = SignGrid(rows: 6, columns: 6), b = a
        var ga = SeededGenerator(state: 1), gb = SeededGenerator(state: 2)
        a.randomFill(with: picks, using: &ga)
        b.randomFill(with: picks, using: &gb)
        XCTAssertNotEqual(a, b)
    }

    func testFewerCellsThanPicksStillFillsEveryCellWithoutRepeats() {
        var grid = SignGrid(rows: 2, columns: 3)   // 2 call cells
        var generator = SeededGenerator(state: 3)
        XCTAssertEqual(grid.randomFill(with: ["A", "B", "C", "D", "A"], using: &generator), 2)
        let used = [grid.text(row: 1, column: 1), grid.text(row: 1, column: 2)]
        XCTAssertEqual(Set(used).count, 2, "no call twice while others are unused")
        XCTAssertTrue(Set(used).isSubset(of: ["A", "B", "C", "D"]))
    }
}
