import XCTest
import UIKit
@testable import PitchMark

/// Home's row of three and the signed-in line (approved 2026-11-10).
final class HomeActionsTests: XCTestCase {

    func testTheBottomLineFollowsTheSignedInAccount() {
        XCTAssertEqual(HomeSignedInLine.text(email: "coach@example.com"), "Signed in as coach@example.com")
        XCTAssertEqual(HomeSignedInLine.text(email: "assistant@example.com"), "Signed in as assistant@example.com",
                       "a different account shows its own email")
        XCTAssertEqual(HomeSignedInLine.text(email: nil), "Not signed in", "signed out")
        XCTAssertEqual(HomeSignedInLine.text(email: ""), "Not signed in", "an account with no email")
    }

    func testTheButtonArtShipsWithTheApp() throws {
        let image = try XCTUnwrap(UIImage(named: HomeActionTile.imageName), "SoftballAndBaseball is missing")
        XCTAssertNotNil(image.cgImage?.alphaInfo)
        XCTAssertNotEqual(image.cgImage?.alphaInfo, CGImageAlphaInfo.none, "the art needs its transparent background")
    }

    func testTheLogoAtTheTopShipsWithTheApp() {
        XCTAssertNotNil(UIImage(named: SettingsView.logoImageName), "Home's header logo is missing")
    }
}
