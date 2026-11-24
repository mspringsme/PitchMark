//
//  PracticeUITests.swift
//  PitchMarkUITests
//
//  Approved 2026-11-20 (T11), on the real Home in demo mode (Skip for Now -
//  practice stays in memory, nothing written): New Game → Practice → pick
//  the player from the shared list → check one pitch of the full list → Start; the tracker shows the practice
//  screen (no at-bat view) with only that pitch as a chip - a pitch on no
//  key; tap the target then where it went (saved, no result buttons), Undo
//  Last; End shows the accuracy review; the session
//  is listed under Home's Practice, and no game was created.
//

import XCTest

@MainActor
final class PracticeUITests: XCTestCase {

    func testAPracticeSessionFromNewGameToReview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Skip for Now"].waitForExistence(timeout: 10) { app.buttons["Skip for Now"].tap() }
        if app.buttons["Home"].waitForExistence(timeout: 10) { app.buttons["Home"].tap() }

        let add = app.buttons["home.games.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        // Practice is one of + 's three choices now (2026-11-24).
        let practice = app.segmentedControls["newGame.kindOfNew"].buttons["Practice"]
        XCTAssertTrue(practice.waitForExistence(timeout: 5))
        // + opened the Games section: count its games now.
        let gamesBefore = app.staticTexts.matching(NSPredicate(format: "label == 'Demo Game'")).count
        practice.tap()
        XCTAssertFalse(app.buttons["Save"].exists, "teams, opponent and Save are gone in practice")
        app.buttons["newGame.practiceNext"].tap()

        // A player is required, from the shared player list.
        let start = app.buttons["practice.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertFalse(start.isEnabled, "can't start without a player")
        app.buttons["practice.player"].tap()
        let demo = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Demo Pitcher'")).firstMatch
        XCTAssertTrue(demo.waitForExistence(timeout: 5), "the shared player list, on Pitchers")
        demo.tap()

        // Every pitch type is listed, none checked; check one.
        let pitchRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'practice.pitch.'"))
        XCTAssertTrue(pitchRows.firstMatch.waitForExistence(timeout: 5))
        let names = (0..<pitchRows.count).map { pitchRows.element(boundBy: $0).identifier.replacingOccurrences(of: "practice.pitch.", with: "") }
        for expected in ["2 Seam", "4 Seam", "Change", "Curve", "Drop", "Rise"] {
            XCTAssertTrue(names.contains(expected), "\(expected) is offered")
        }
        XCTAssertFalse(start.isEnabled, "can't start with no pitch checked")
        // Screw isn't on the demo key - practice isn't linked to any key.
        let kept = "Screw"
        app.buttons["practice.pitch.\(kept)"].tap()
        XCTAssertTrue(start.isEnabled)
        start.tap()

        // The practice screen: header, only the checked pitch, no at-bat view.
        XCTAssertTrue(app.staticTexts["practice.title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["practice.title"].label, "Practice · Demo Pitcher")
        XCTAssertTrue(app.buttons[kept].exists, "the checked pitch is a chip")
        for name in names where name != kept {
            XCTAssertFalse(app.buttons[name].exists, "\(name) wasn't checked, so it isn't a chip")
        }
        XCTAssertFalse(app.buttons["Catcher"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["atBat.1"].exists, "no at-bat view in practice")

        // Two taps per pitch: the target, then where it went - every spot
        // tappable for a pitch on no key, no code, no result buttons.
        let prompt = app.staticTexts["practice.prompt"]
        let count = app.staticTexts["practice.count"]
        func throwPitch(target: String, went: String) {
            let targetButton = app.buttons[target].firstMatch
            XCTAssertTrue(targetButton.waitForExistence(timeout: 5), "\(target) can be tapped for a pitch on no key")
            targetButton.tap()
            let aimed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Target: \(target)'"), object: prompt)
            XCTAssertEqual(XCTWaiter().wait(for: [aimed], timeout: 5), .completed, "the prompt shows the target")
            XCTAssertFalse(app.descendants(matching: .any)["tracker.codePanel"].exists, "no codes in practice")
            XCTAssertFalse(app.buttons["Swinging"].exists, "no result buttons - there's no batter")
            app.buttons[went].firstMatch.tap()
        }
        func waitForCount(_ label: String) {
            let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: count)
            XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: 5), .completed, label)
        }

        throwPitch(target: "Strike Up", went: "Ball Up")
        waitForCount("1 pitch")
        app.buttons["practice.undo"].tap()
        waitForCount("0 pitches")
        throwPitch(target: "Strike Up", went: "Strike Up")
        waitForCount("1 pitch")
        throwPitch(target: "Strike Middle", went: "Ball ↓")
        waitForCount("2 pitches")

        // End → the review: accuracy against the target.
        app.buttons["practice.end"].tap()
        let total = app.descendants(matching: .any)["practiceReview.total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5), "the session's review opens")
        XCTAssertTrue(total.label.contains("2"), "two pitches after the undo")
        let onTarget = app.descendants(matching: .any)["practiceReview.onTarget"]
        XCTAssertTrue(onTarget.label.contains("50%"), "one of two on target")
        app.swipeDown(velocity: .fast)

        // Home lists it under Practice; no game was made. Home opens with
        // its sections collapsed - open Games.
        app.buttons["Home"].tap()
        let games = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Games'")).firstMatch
        if games.waitForExistence(timeout: 5) { games.tap() }
        XCTAssertTrue(app.descendants(matching: .any)["home.practice.Demo Pitcher"].waitForExistence(timeout: 8),
                      "listed under Home's Practice")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'Demo Game'")).count, gamesBefore,
                       "practice didn't create a game")
    }

    /// P5 (approved 2026-11-20): the running log and suggestion fill the
    /// space under the zone as pitches save; on Home a session archives,
    /// restores and deletes.
    func testRunningLogAndArchiveDelete() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Skip for Now"].waitForExistence(timeout: 10) { app.buttons["Skip for Now"].tap() }
        if app.buttons["Home"].waitForExistence(timeout: 10) { app.buttons["Home"].tap() }

        let add = app.buttons["home.games.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        app.segmentedControls["newGame.kindOfNew"].buttons["Practice"].tap()
        app.buttons["newGame.practiceNext"].tap()
        let player = app.buttons["practice.player"]
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        player.tap()
        let demo = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Demo Pitcher'")).firstMatch
        XCTAssertTrue(demo.waitForExistence(timeout: 5))
        demo.tap()
        app.buttons["practice.pitch.Screw"].tap()
        app.buttons["practice.start"].tap()
        XCTAssertTrue(app.staticTexts["practice.title"].waitForExistence(timeout: 10))

        let log = app.descendants(matching: .any)["practiceLog"]
        XCTAssertTrue(log.waitForExistence(timeout: 5), "the running log sits under the zone")

        // 1 on target, 4 missing high.
        let throwsList = [("Strike ↓", "Strike ↓")] + Array(repeating: ("Strike ↓", "Strike Middle"), count: 4)
        for (target, went) in throwsList {
            app.buttons[target].firstMatch.tap()
            app.buttons[went].firstMatch.tap()
        }
        let session = app.staticTexts["practiceLog.session"]
        let five = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH '5 thrown · 20% on target'"), object: session)
        XCTAssertEqual(XCTWaiter().wait(for: [five], timeout: 5), .completed, "the log updates as pitches save")
        let suggestion = app.descendants(matching: .any)["practiceLog.suggestion"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        XCTAssertTrue(suggestion.label.contains("Work on the Screw: 1 of 5"), suggestion.label)
        XCTAssertTrue(suggestion.label.contains("Most of its misses go high"), suggestion.label)
        let latest = app.descendants(matching: .any)["practiceLog.latest"]
        XCTAssertTrue(latest.label.contains("Screw → Strike ↓, went Strike Middle (high)"), latest.label)

        app.buttons["practice.end"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["practiceReview.total"].waitForExistence(timeout: 5))
        app.swipeDown(velocity: .fast)

        // Home: archive, show archived, restore, delete.
        app.buttons["Home"].tap()
        let games = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Games'")).firstMatch
        if games.waitForExistence(timeout: 5) { games.tap() }
        let menu = app.buttons["home.practice.menu.Demo Pitcher"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 8))
        menu.tap()
        app.buttons["Archive"].tap()
        let showArchived = app.buttons["home.practice.showArchived"]
        XCTAssertTrue(showArchived.waitForExistence(timeout: 5), "archived sessions sit behind Show Archived")
        XCTAssertFalse(app.descendants(matching: .any)["home.practice.Demo Pitcher"].exists, "hidden from the list")
        showArchived.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["Restore"].tap()
        XCTAssertTrue(showArchived.waitForNonExistence(timeout: 5), "restored - nothing archived")
        XCTAssertTrue(app.descendants(matching: .any)["home.practice.Demo Pitcher"].exists)

        menu.tap()
        app.buttons["Delete…"].tap()
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "delete asks first")
        confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.practice.Demo Pitcher"].waitForNonExistence(timeout: 5),
                      "deleted")
    }
}
