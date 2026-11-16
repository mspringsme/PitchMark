//
//  AssetLibraryTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-15: the built-in overlay icons (every icon in all six
//  weights, color and weight on an overlay, the export using both) and
//  the built-in sounds (every file present, a known group, a credit, and
//  Kevin MacLeod's required CC BY credit with the change noted).
//

import XCTest
import UIKit
@testable import PitchMark

final class AssetLibraryTests: XCTestCase {

    // MARK: Icons

    func testEveryIconIsInTheAppInAllSixWeights() {
        XCTAssertFalse(overlayIcons.isEmpty)
        for icon in overlayIcons {
            let id = OverlayIconImages.libraryId(for: icon)
            for weight in OverlayIconWeight.allCases {
                let name = OverlayIconImages.imageName(forAssetId: id, weight: weight.rawValue)
                XCTAssertNotNil(name.flatMap { UIImage(named: $0) }, "\(icon.name) \(weight.rawValue)")
            }
        }
    }

    func testIconsHaveUniqueIdsAndNamesAndAKnownCategory() {
        let ids = overlayIcons.map(OverlayIconImages.libraryId(for:))
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate id")
        XCTAssertEqual(Set(overlayIcons.map(\.name)).count, overlayIcons.count, "duplicate name")
        XCTAssertEqual(bundledAssets.count, overlayIcons.count, "the library lists every icon")
        XCTAssertTrue(bundledAssets.allSatisfy { a in OverlayIconCategory.allCases.contains { $0.rawValue == a.category } })
    }

    func testAnOverlayWithNoWeightUsesTheIconsDefault() {
        XCTAssertEqual(OverlayIconImages.imageName(forAssetId: "icon-ph-circle-bold", weight: nil), "ph-circle-bold")
        XCTAssertEqual(OverlayIconImages.imageName(forAssetId: "icon-ph-circle-bold", weight: "thin"), "ph-circle-thin")
        XCTAssertEqual(OverlayIconImages.imageName(forAssetId: "icon-ph-baseball-fill", weight: "duotone"), "ph-baseball-duotone")
        XCTAssertEqual(OverlayIconImages.imageName(forAssetId: "icon-ph-baseball-fill", weight: "nonsense"), "ph-baseball-fill")
        XCTAssertNil(OverlayIconImages.imageName(forAssetId: "user-photo-123", weight: "bold"), "not an icon")
        XCTAssertEqual(OverlayIconImages.defaultWeight(of: "icon-ph-arrow-up-bold"), .bold)
    }

    /// The middle pixel, read through a context with a fixed RGBA byte
    /// order (an image's own buffer is often BGRA).
    private func centerPixel(_ image: UIImage) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        guard let cg = image.cgImage else { return (0, 0, 0, 0) }
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (0, 0, 0, 0) }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        context.draw(cg, in: CGRect(x: -w / 2 + 0.5, y: -h / 2 + 0.5, width: w, height: h))
        return (CGFloat(bytes[0]) / 255, CGFloat(bytes[1]) / 255, CGFloat(bytes[2]) / 255, CGFloat(bytes[3]) / 255)
    }

    func testIconsAreWhiteUntilTintedAndTakeTheChosenColor() throws {
        let white = try XCTUnwrap(OverlayIconImages.image(forAssetId: "icon-ph-circle-bold", weight: "fill"))
        XCTAssertEqual(white.size, CGSize(width: 512, height: 512))
        let w = centerPixel(white)
        XCTAssertGreaterThan(w.a, 0.9)
        XCTAssertGreaterThan(min(w.r, w.g, w.b), 0.9, "white")

        let red = centerPixel(OverlayIconImages.tinted(white, hex: "#FF0000"))
        XCTAssertGreaterThan(red.r, 0.9)
        XCTAssertLessThan(max(red.g, red.b), 0.1, "red")
        XCTAssertTrue(OverlayIconImages.tinted(white, hex: nil) === white, "no color = untouched")
    }

    func testTheExportUsesTheOverlaysWeightAndColorButNeverTintsAPhoto() throws {
        var item = OverlayItem(assetID: "icon-ph-circle-bold", startTime: 0, endTime: 1)
        item.iconWeight = "fill"
        item.tintHex = "#00FF00"
        let exported = try XCTUnwrap(overlayExportImage(for: item, resolveImage: { _ in nil }))
        let g = centerPixel(exported)
        XCTAssertGreaterThan(g.g, 0.9, "filled, so the middle is colored - the bold ring's middle is empty")
        XCTAssertLessThan(max(g.r, g.b), 0.1)

        let photo = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { ctx in
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        var photoItem = OverlayItem(assetID: "user-photo", startTime: 0, endTime: 1)
        photoItem.tintHex = "#FF0000"
        XCTAssertTrue(overlayExportImage(for: photoItem, resolveImage: { _ in photo }) === photo, "photos are never tinted")
    }

    func testOverlaysSavedBeforeColorAndWeightLoadPlainAndTheyRoundTrip() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","assetID":"icon-ph-circle-bold","startTime":0,"endTime":2,"keyframes":[]}"#
        let decoded = try JSONDecoder().decode(OverlayItem.self, from: Data(old.utf8))
        XCTAssertNil(decoded.tintHex)
        XCTAssertNil(decoded.iconWeight)

        var item = decoded
        item.tintHex = "#FFD60A"
        item.iconWeight = "thin"
        let again = try JSONDecoder().decode(OverlayItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(again.tintHex, "#FFD60A")
        XCTAssertEqual(again.iconWeight, "thin")
    }

    func testThePhosphorLicenseShipsWithTheApp() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PHOSPHOR-LICENSE", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("MIT License"))
        XCTAssertTrue(text.contains("Phosphor Icons"))
    }

    // MARK: Sounds

    func testEverySoundIsInTheAppInAKnownGroupWithACredit() {
        XCTAssertFalse(bundledAudioAssets.isEmpty, "sounds.json decoded")
        XCTAssertEqual(Set(bundledAudioAssets.map(\.id)).count, bundledAudioAssets.count, "duplicate id")
        for sound in bundledAudioAssets {
            let url = bundledAudioAssetURL(for: sound)
            XCTAssertNotNil(url, "\(sound.name) file")
            if let url { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), sound.name) }
            XCTAssertTrue(BundledSoundGroup.order.contains(sound.category), "\(sound.name): \(sound.category)")
            XCTAssertFalse((sound.author ?? "").isEmpty, "\(sound.name) author")
            XCTAssertFalse((sound.license ?? "").isEmpty, "\(sound.name) license")
            XCTAssertNotNil(sound.sourceURL.flatMap(URL.init(string:)), "\(sound.name) link")
            XCTAssertGreaterThan(sound.durationSeconds, 0, sound.name)
        }
        for group in BundledSoundGroup.order {
            XCTAssertTrue(bundledAudioAssets.contains { $0.category == group }, "\(group) has sounds")
        }
    }

    func testKevinMacLeodTracksCarryTheirCreditAndSayWhenShortened() {
        let tracks = bundledAudioAssets.filter { ($0.author ?? "").contains("Kevin MacLeod") }
        XCTAssertFalse(tracks.isEmpty)
        for track in tracks {
            let license = track.license ?? ""
            XCTAssertTrue(license.contains("By Attribution 4.0"), track.name)
            XCTAssertEqual(license.contains("shortened"), track.durationSeconds >= 59.9,
                           "\(track.name): a shortened track says so, a whole one doesn't")
            XCTAssertLessThanOrEqual(track.durationSeconds, 60.5, "\(track.name) is at most a minute")
        }
    }
}
