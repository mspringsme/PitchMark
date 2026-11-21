//
//  SponsorSlotTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-19 (Team Sponsors):
//  - HIGH RISK: a sponsor badge never renders on a protected screen (clip
//    playback, editors, the slideshow, the tracker, Display). Checked two
//    ways: the badge itself refuses a protected surface, and the source is
//    read so no badge can be placed on one. Broken on purpose to prove it.
//  - the label always says "Sponsored by", and an expired slot never shows
//  - the app's limits match the server's (functions/src/sponsorSlot.ts)
//

import XCTest
import UIKit
import FirebaseFirestore
@testable import PitchMark

final class SponsorSlotTests: XCTestCase {

    private func slot(startsIn: TimeInterval = -86_400, endsIn: TimeInterval = 86_400 * 100) -> SponsorSlot {
        SponsorSlot(id: "s1", teamId: "t1", name: "Main St Pizza", link: "https://pizza.example",
                    startsAt: Date().addingTimeInterval(startsIn), endsAt: Date().addingTimeInterval(endsIn),
                    purchasedByUid: "coach")
    }

    // MARK: Placement

    func testProtectedSurfacesNeverShowABadge() {
        let protected: [SponsorSurface] = [.clipPlayback, .momentEditor, .homeSlideshow, .tracker, .display]
        for surface in protected {
            XCTAssertFalse(SponsorPlacement.allows(surface), "\(surface) allows sponsors")
            XCTAssertFalse(SponsorBadge.isVisible(slot(), on: surface), "a badge showed on \(surface)")
        }
        XCTAssertEqual(SponsorPlacement.allowed, [.teamRoster, .tourneyPage, .sharedTourneyPage, .seasonBook])
    }

    /// Reads the app's source: every `SponsorBadge(` names an allowed
    /// surface, and none sits in a protected screen's file or in Display.
    func testNoBadgeIsPlacedOnAProtectedScreen() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let folders = ["PitchMark", "PitchMarkDisplay"]
        var badgeCalls = 0
        for folder in folders {
            let directory = root.appendingPathComponent(folder)
            let files = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" }
            XCTAssertFalse(files.isEmpty, "no source found in \(folder) - the test can't see the code")
            for file in files {
                let source = try String(contentsOf: file, encoding: .utf8)
                let calls = source.components(separatedBy: "SponsorBadge(").dropFirst()
                guard !calls.isEmpty else { continue }
                let name = file.lastPathComponent
                XCTAssertNotEqual(folder, "PitchMarkDisplay", "a sponsor badge in Display: \(name)")
                XCTAssertFalse(SponsorPlacement.protectedSourceFiles.contains(name), "a sponsor badge in \(name)")
                for call in calls {
                    badgeCalls += 1
                    let window = String(call.prefix(600))
                    let match = try XCTUnwrap(window.range(of: #"surface:\s*\.(\w+)"#, options: .regularExpression),
                                              "a SponsorBadge in \(name) names no surface")
                    let caseName = String(window[match]).components(separatedBy: ".").last ?? ""
                    let surface = try XCTUnwrap(SponsorSurface(rawValue: caseName), "unknown surface \(caseName) in \(name)")
                    XCTAssertTrue(SponsorPlacement.allows(surface), "a SponsorBadge in \(name) is on protected \(surface)")
                }
            }
        }
        XCTAssertGreaterThan(badgeCalls, 0, "found no badges at all - the scan is broken")
    }

    // MARK: Badge

    func testTheLabelAlwaysSaysSponsoredBy() {
        XCTAssertEqual(SponsorSlot.label(for: "Main St Pizza"), "Sponsored by Main St Pizza")
    }

    func testOnlyARunningSlotShows() {
        XCTAssertTrue(SponsorBadge.isVisible(slot(), on: .teamRoster))
        XCTAssertFalse(SponsorBadge.isVisible(slot(startsIn: -86_400 * 200, endsIn: -1), on: .teamRoster), "expired")
        XCTAssertFalse(SponsorBadge.isVisible(slot(startsIn: 3_600), on: .teamRoster), "not started")
    }

    // MARK: Details sent to checkout (match the server)

    func testSponsorDetailsAreChecked() {
        let ok = SponsorSnapshot(teamId: "t1", name: " Main St Pizza ", link: "https://pizza.example", logo: "")
        XCTAssertNil(ok.problem)
        XCTAssertEqual(ok.trimmed.name, "Main St Pizza")

        let bad = [
            SponsorSnapshot(teamId: "t1", name: "", link: "", logo: ""),
            SponsorSnapshot(teamId: "t1", name: String(repeating: "x", count: 61), link: "", logo: ""),
            SponsorSnapshot(teamId: "t1", name: "Pizza", link: "http://pizza.example", logo: ""),
            SponsorSnapshot(teamId: "t1", name: "Pizza", link: "https://", logo: ""),
            SponsorSnapshot(teamId: "t1", name: "Pizza", link: "", logo: String(repeating: "A", count: 100_001))
        ]
        for snapshot in bad {
            XCTAssertNotNil(snapshot.problem, "accepted \(snapshot.name.prefix(20)) / \(snapshot.link)")
        }
    }

    func testTheSnapshotHoldsOnlyTeamNameLinkAndLogo() throws {
        let json = SponsorSnapshot(teamId: "t1", name: "Pizza", link: "", logo: "").json
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["teamId", "name", "link", "logo"])
    }

    func testALargeLogoIsShrunkToFit() throws {
        let big = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000)).image { context in
            for i in 0..<60 {
                UIColor(hue: CGFloat(i) / 60, saturation: 1, brightness: 1, alpha: 1).setFill()
                context.fill(CGRect(x: i * 50, y: 0, width: 50, height: 2000))
            }
        }
        let encoded = try XCTUnwrap(SponsorSnapshot.encodeLogo(big))
        XCTAssertLessThanOrEqual(encoded.count, SponsorSlotProduct.logoMax)
        let image = try XCTUnwrap(UIImage(data: try XCTUnwrap(Data(base64Encoded: encoded))))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height) * image.scale, SponsorSlotProduct.logoPixels + 1)
    }

    func testASavedSlotLoads() {
        let data: [String: Any] = [
            "teamId": "t1", "name": "Pizza", "link": "", "logo": "",
            "startsAt": Timestamp(date: Date(timeIntervalSince1970: 0)),
            "endsAt": Timestamp(date: Date(timeIntervalSince1970: 86_400)),
            "purchasedByUid": "coach"
        ]
        let loaded = SponsorSlot(id: "s1", data: data)
        XCTAssertEqual(loaded?.name, "Pizza")
        XCTAssertEqual(loaded?.purchasedByUid, "coach")
        XCTAssertNil(SponsorSlot(id: "s1", data: ["name": "x"]))
    }

    func testPriceAndLimitsMatchTheServer() {
        XCTAssertEqual(SponsorSlotProduct.priceCents, 2500)
        XCTAssertEqual(SponsorSlotProduct.durationDays, 183)
        XCTAssertEqual(SponsorSlotProduct.nameMax, 60)
        XCTAssertEqual(SponsorSlotProduct.linkMax, 200)
        XCTAssertEqual(SponsorSlotProduct.logoMax, 100_000)
    }
}
