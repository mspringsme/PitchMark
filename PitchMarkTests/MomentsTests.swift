//
//  MomentsTests.swift
//  PitchMarkTests
//
//  Approved 2026-11-15: Moments - the game caption, player clips, Compare
//  (timing, Sync/Start/End toggles, framing, orientation of the saved
//  video), the library's filter chips and Photos backup on by default.
//

import XCTest
import CoreGraphics
import ImageIO
@testable import PitchMark

final class MomentsTests: XCTestCase {

    private func game() -> MomentGameContext {
        var c = MomentGameContext()
        c.gameName = "Reds 10U vs. MHJ Fastpitch"
        c.gameDate = DateComponents(calendar: .current, year: 2026, month: 11, day: 14).date
        c.inning = 3
        c.balls = 1
        c.strikes = 2
        c.outs = 2
        c.ourName = "Reds"
        c.theirName = "MHJ"
        c.ourScore = 3
        c.theirScore = 2
        c.batterName = "Kenzie"
        c.batterHitterId = "h1"
        c.pitcherName = "Lauren"
        c.pitcherId = "p1"
        return c
    }

    // MARK: Game caption

    func testThePlayGoesOnTopAndTheGameUnderIt() {
        var o = GameCaptionOptions()
        o.pitcher = true
        o.count = true
        o.outs = true
        o.score = true
        let lines = GameCaption.lines(context: game(), options: o)
        XCTAssertEqual(lines?.line1, "Kenzie · P: Lauren · Inn 3 · 1-2 · 2 Outs")
        XCTAssertEqual(lines?.line2.hasPrefix("Reds 10U vs. MHJ Fastpitch · Reds 3, MHJ 2 · Nov 14"), true)
    }

    /// What's on after a recording or photo (user's picks, 2026-11-16).
    func testTheDefaultsAreBatterInningGameAndDateForThreeSecondsFadingOut() {
        let o = GameCaptionOptions()
        XCTAssertTrue(o.batter && o.inning && o.gameName && o.date)
        XCTAssertFalse(o.pitcher || o.count || o.outs || o.score)
        XCTAssertEqual(o.seconds, 3)
        XCTAssertTrue(o.fadeOut)
        let lines = GameCaption.lines(context: game(), options: o)
        XCTAssertEqual(lines?.line1, "Kenzie · Inn 3")
        XCTAssertEqual(lines?.line2.hasPrefix("Reds 10U vs. MHJ Fastpitch · Nov 14"), true)
    }

    func testOneOutIsSingular() {
        var c = game()
        c.outs = 1
        let outs = GameCaption.items(for: c).first { $0.id == "outs" }
        XCTAssertEqual(outs?.value, "1 Out")
    }

    func testMissingValuesAreSkippedAndNothingChosenIsNoCaption() {
        var c = MomentGameContext()
        c.inning = 4
        let lines = GameCaption.lines(context: c, options: GameCaptionOptions())
        XCTAssertEqual(lines?.line1, "Inn 4")
        XCTAssertEqual(lines?.line2, "")

        var none = GameCaptionOptions()
        for item in GameCaption.items(for: game()) { GameCaption.set(item.id, false, in: &none) }
        XCTAssertNil(GameCaption.lines(context: game(), options: none))
        XCTAssertNil(GameCaption.overlay(context: game(), options: none, clipDuration: 10))
    }

    func testOnlyGameItemsMoveUpToTheFirstLine() {
        var o = GameCaptionOptions()
        o.batter = false; o.inning = false; o.count = false
        let lines = GameCaption.lines(context: game(), options: o)
        XCTAssertEqual(lines?.line1.hasPrefix("Reds 10U vs. MHJ Fastpitch"), true)
        XCTAssertEqual(lines?.line2, "")
    }

    func testCaptionTimingFitsTheClip() {
        var o = GameCaptionOptions()
        o.seconds = 5
        XCTAssertEqual(GameCaption.overlay(context: game(), options: o, clipDuration: 12)?.endTime, 5)
        XCTAssertEqual(GameCaption.overlay(context: game(), options: o, clipDuration: 3)?.endTime, 3, "never past the clip")
        o.seconds = 0
        XCTAssertEqual(GameCaption.overlay(context: game(), options: o, clipDuration: 12)?.endTime, 12, "whole clip")
        o.fadeOut = false
        let caption = GameCaption.overlay(context: game(), options: o, clipDuration: 12)
        XCTAssertEqual(caption?.fadeOutEnabled, false)
        XCTAssertEqual(caption?.startTime, 0)
        XCTAssertEqual(caption?.assetID, GameCaption.overlayAssetID)
        XCTAssertNil(GameCaption.overlay(context: game(), options: GameCaptionOptions(), clipDuration: 0))
    }

    func testANewCaptionReplacesTheOldOneAndLeavesOtherOverlaysAlone() {
        let sticker = OverlayItem(assetID: "logo", startTime: 0, endTime: 4)
        let text = OverlayItem(assetID: "", startTime: 1, endTime: 2, textContent: OverlayTextContent(templateID: "modern"))
        let old = GameCaption.overlay(context: game(), options: GameCaptionOptions(), clipDuration: 9)!
        let new = GameCaption.overlay(context: game(), options: GameCaptionOptions(), clipDuration: 9)!
        let result = GameCaption.replacingCaption(in: [sticker, old, text], with: new)
        XCTAssertEqual(result.map(\.id), [sticker.id, text.id, new.id])
        XCTAssertEqual(GameCaption.replacingCaption(in: result, with: nil).map(\.id), [sticker.id, text.id], "remove")
    }

    // MARK: Player clips

    func testAClipIsAboutTheGamesBatterAndPitcher() {
        let tags = GameCaption.playerTags(from: game())
        XCTAssertEqual(tags, [MomentPlayerTag(name: "Kenzie", hitterId: "h1"), MomentPlayerTag(name: "Lauren", pitcherId: "p1")])
        var jerseyOnly = game()
        jerseyOnly.batterHitterId = nil
        XCTAssertEqual(GameCaption.playerTags(from: jerseyOnly).map(\.name), ["Lauren"], "a jersey-only batter isn't a player")
    }

    func testAPlayersClipsMatchAnyOfTheirRecords() {
        var clip = Moment()
        clip.playerTags = [MomentPlayerTag(name: "Kenzie", hitterId: "h2")]
        XCTAssertTrue(PlayerMoments.matches(clip, hitterIds: ["h1", "h2"], pitcherIds: []), "a merged player's second record")
        XCTAssertFalse(PlayerMoments.matches(clip, hitterIds: ["h9"], pitcherIds: ["h2"]), "a hitter id isn't a pitcher id")
        clip.playerTags = [MomentPlayerTag(name: "Lauren", pitcherId: "p1")]
        XCTAssertTrue(PlayerMoments.matches(clip, hitterIds: [], pitcherIds: ["p1"]))
        XCTAssertFalse(PlayerMoments.matches(Moment(), hitterIds: ["h1"], pitcherIds: ["p1"]), "untagged")
    }

    func testThePlayerFilterListsEachTaggedNameOnce() {
        var a = Moment(); a.playerTags = [MomentPlayerTag(name: "kenzie"), MomentPlayerTag(name: "Lauren")]
        var b = Moment(); b.playerTags = [MomentPlayerTag(name: "Lauren")]
        XCTAssertEqual(PlayerMoments.taggedNames(in: [a, b, Moment()]), ["kenzie", "Lauren"])
    }

    // MARK: Compare timing

    private func timeline() -> CompareTimeline {
        CompareTimeline(durationA: 10, durationB: 6)
    }

    func testTogetherTheyPlayUntilEitherClipRunsOut() {
        var t = timeline()
        t.setSync(a: 4, b: 1)
        XCTAssertEqual(t.jointRange, -1...5)
        XCTAssertEqual(t.times(at: 0).a, 4)
        XCTAssertEqual(t.times(at: 0).b, 1)
        XCTAssertEqual(t.times(at: 2).a, 6)
        XCTAssertEqual(t.times(at: 2).b, 3)
        XCTAssertEqual(t.times(at: 99).b, 6, "clamped")
    }

    func testSyncPointsStayInsideTheirClips() {
        var t = timeline()
        t.setSync(a: -3, b: 50)
        XCTAssertEqual(t.syncA, 0)
        XCTAssertEqual(t.syncB, 6)
    }

    func testSetSyncHereIsAToggle() {
        var t = timeline()
        XCTAssertFalse(t.isSyncSetA)
        t.setSync(a: 2.5)
        XCTAssertTrue(t.isSyncSetA)
        XCTAssertFalse(t.isSyncSetB, "only the clip it was set on")
        t.clearSync(a: true)
        XCTAssertFalse(t.isSyncSetA)
        XCTAssertEqual(t.syncA, 0, "back to the clip's start")
    }

    func testStartAndEndCutWhatPlaysAndStayInOrder() {
        var t = timeline()
        XCTAssertEqual(t.playRange, t.jointRange)
        t.setStart(1)
        t.setEnd(4)
        XCTAssertEqual(t.playRange, 1...4)
        t.setEnd(0.5)
        XCTAssertNil(t.trimStart, "an End before the Start clears the Start")
        XCTAssertEqual(t.playRange, 0...0.5)
        t.setStart(2)
        XCTAssertNil(t.trimEnd, "a Start after the End clears the End")
        t.trimEnd = 99
        XCTAssertEqual(t.playRange.upperBound, t.jointRange.upperBound, "never past the clips")
    }

    func testMovingASyncPointClearsStartAndEnd() {
        var t = timeline()
        t.setStart(1); t.setEnd(3)
        t.setSync(b: 2)
        XCTAssertNil(t.trimStart)
        XCTAssertNil(t.trimEnd)
        t.setStart(1); t.setEnd(3)
        t.clearSync(b: true)
        XCTAssertNil(t.trimStart)
        XCTAssertNil(t.trimEnd)
    }

    // MARK: Compare framing and the saved video

    func testAnUnzoomedClipFitsWholeAndCentered() {
        let pane = CGSize(width: 1080, height: 960)
        let image = CGSize(width: 1080, height: 1920)   // a portrait clip
        let t = ComparePaneMath.placement(imageSize: image, pane: pane, framing: ComparePaneFraming())
        let rect = CGRect(origin: .zero, size: image).applying(t)
        XCTAssertEqual(rect.height, 960, accuracy: 0.5, "fits the pane's height")
        XCTAssertEqual(rect.midX, 540, accuracy: 0.5)
        XCTAssertEqual(rect.midY, 480, accuracy: 0.5)
    }

    func testZoomGrowsFromTheCenterAndDragMovesLikeTheScreen() {
        let pane = CGSize(width: 1000, height: 1000)
        let image = CGSize(width: 1000, height: 1000)
        let zoomed = CGRect(origin: .zero, size: image)
            .applying(ComparePaneMath.placement(imageSize: image, pane: pane, framing: ComparePaneFraming(zoom: 2)))
        XCTAssertEqual(zoomed.width, 2000, accuracy: 0.5)
        XCTAssertEqual(zoomed.midX, 500, accuracy: 0.5)
        XCTAssertEqual(zoomed.midY, 500, accuracy: 0.5)

        // Dragged right and down on screen. The saved frame is y-up, so
        // down on screen is a lower y.
        let moved = CGRect(origin: .zero, size: image)
            .applying(ComparePaneMath.placement(imageSize: image, pane: pane,
                                                framing: ComparePaneFraming(zoom: 1, offset: CGSize(width: 0.1, height: 0.2))))
        XCTAssertEqual(moved.midX, 600, accuracy: 0.5)
        XCTAssertEqual(moved.midY, 300, accuracy: 0.5)
    }

    func testTheSavedVideosPanesAreThePreviewsShape() {
        XCTAssertEqual(CompareLayout.stacked.renderSize, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(CompareLayout.stacked.paneAspect, 1080.0 / 960.0, accuracy: 0.0001)
        XCTAssertEqual(CompareLayout.stacked.paneOrigin(isA: true), CGPoint(x: 0, y: 960), "A on top")
        XCTAssertEqual(CompareLayout.sideBySide.paneOrigin(isA: false), CGPoint(x: 960, y: 0), "B on the right")
    }

    /// A portrait iPhone clip carries a 90° turn; it must come out upright,
    /// not upside down (2026-11-15).
    func testEachClipIsSavedTheRightWayUp() {
        XCTAssertEqual(CompareOrientation.orientation(for: .identity), .up)
        XCTAssertEqual(CompareOrientation.orientation(for: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)), .right, "portrait")
        XCTAssertEqual(CompareOrientation.orientation(for: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1920)), .left)
        XCTAssertEqual(CompareOrientation.orientation(for: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1920, ty: 1080)), .down)
        XCTAssertEqual(CompareOrientation.orientation(for: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1920, ty: 0)), .upMirrored)
    }

    func testAPortraitFrameComesOutUprightAndTall() {
        // A landscape buffer (wide) with a portrait clip's turn: the
        // upright frame is tall, with the buffer's top row on the right.
        let buffer = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let upright = buffer.oriented(CompareOrientation.orientation(for: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)))
        XCTAssertEqual(upright.extent.width, 1080)
        XCTAssertEqual(upright.extent.height, 1920)
    }

    // MARK: Library

    func testFilterChipsPickTheRightClips() {
        let now = Date()
        var fav = Moment(createdAt: now.addingTimeInterval(-86_400 * 30)); fav.isFavorite = true
        let photo = Moment(createdAt: now, photoCount: 1, momentKind: .photoCreation)
        let video = Moment(createdAt: now.addingTimeInterval(-3_600))
        let all = [fav, photo, video]
        func count(_ f: MomentLibraryFilter) -> Int { f.apply(to: all, now: now).count }
        XCTAssertEqual(count(.all), 3)
        XCTAssertEqual(count(.favorites), 1)
        XCTAssertEqual(count(.photos), 1)
        XCTAssertEqual(count(.videos), 2)
        XCTAssertEqual(count(.thisWeek), 2, "the favorite is a month old")
    }

    func testPhotosBackupIsOnUnlessTurnedOff() {
        let key = "momentsAutoBackupToPhotosEnabled"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(momentsAutoBackupToPhotosEnabled, "never set = on")
        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(momentsAutoBackupToPhotosEnabled)
    }

    func testRevertClearsEveryEditSetting() {
        // Every edit the Moment model stores is in the list Revert clears.
        let edits = ["overlays", "markupOverlays", "speedKeyframes", "audioOverlays", "originalAudioVolume",
                     "originalVolumeKeyframes", "originalMuteRegions", "zoomRegions", "slideshowSegments",
                     "slideshowTransitionsEnabled", "fadeInEnabled", "fadeOutEnabled", "cropSettings",
                     "freezeFrame", "filterPreset", "gameCaption"]
        XCTAssertEqual(Set(MomentActions.editFieldNames), Set(edits))
        XCTAssertFalse(MomentActions.editFieldNames.contains("photoCount"), "photos stay")
        XCTAssertFalse(MomentActions.editFieldNames.contains("playerTags"), "players stay")
    }
}

/// 2026-11-16: overlays are the top layer. Other editors work from the
/// video without them, so nothing bakes them in twice (the doubled
/// caption after a crop).
final class OverlayLayerTests: XCTestCase {
    private let id = "overlay-layer-test"

    override func tearDown() {
        removeAllLocalMomentFiles(momentId: id, photoCount: 0)
        if let base = localMomentOverlayBaseVideoURL(for: id) { try? FileManager.default.removeItem(at: base) }
    }

    private func write(_ url: URL?) {
        guard let url else { return XCTFail("no path") }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
    }

    func testOtherEditorsUseTheOverlaysCopyWheneverItExists() {
        write(localMomentEditedVideoURL(for: id))
        write(localMomentOverlayBaseVideoURL(for: id))
        XCTAssertEqual(videoBelowOverlays(momentId: id), localMomentOverlayBaseVideoURL(for: id))
    }

    func testWithoutTheCopyTheyUseTheCurrentVideo() {
        write(localMomentEditedVideoURL(for: id))
        XCTAssertEqual(videoBelowOverlays(momentId: id), resolvedMomentVideoURL(for: id))
    }

    /// Copies from older builds may hold the caption; the first open on
    /// this build drops them, once.
    func testTheOneTimeCleanupDropsOtherEditorsCopiesOnce() {
        if let marker = OverlayLayerMigration.markerURL(for: id) { try? FileManager.default.removeItem(at: marker) }
        write(localMomentCropBaseVideoURL(for: id))
        write(localMomentOverlayBaseVideoURL(for: id))
        OverlayLayerMigration.runIfNeeded(momentId: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localMomentCropBaseVideoURL(for: id)!.path), "Crop's old copy goes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: localMomentOverlayBaseVideoURL(for: id)!.path), "the overlays' copy stays")
        write(localMomentCropBaseVideoURL(for: id))
        OverlayLayerMigration.runIfNeeded(momentId: id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: localMomentCropBaseVideoURL(for: id)!.path), "only once")
        if let marker = OverlayLayerMigration.markerURL(for: id) { try? FileManager.default.removeItem(at: marker) }
        if let crop = localMomentCropBaseVideoURL(for: id) { try? FileManager.default.removeItem(at: crop) }
    }

    /// Another editor's save keeps the overlays' copy - the redraw
    /// replaces it. A missing copy then means the overlays are part of the
    /// video, and the redraw is skipped instead of doubling them.
    func testAnotherEditorsSaveKeepsTheOverlaysCopy() {
        write(localMomentOverlayBaseVideoURL(for: id))
        invalidateOtherFrozenBases(momentId: id, except: [.crop])
        invalidateOtherFrozenBases(momentId: id, except: [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: localMomentOverlayBaseVideoURL(for: id)!.path))
    }

    func testDeletingTheMomentRemovesTheOverlaysCopy() {
        write(localMomentOverlayBaseVideoURL(for: id))
        removeAllLocalMomentFiles(momentId: id, photoCount: 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localMomentOverlayBaseVideoURL(for: id)!.path))
    }

    func testRemovingGameInfoFromAVideoWithItBakedInSaysSo() {
        let baked = NSError(domain: "GameCaption", code: GameCaptionApplier.bakedInErrorCode)
        XCTAssertTrue(GameCaptionApplier.isBakedIn(baked))
        XCTAssertFalse(GameCaptionApplier.isBakedIn(NSError(domain: "GameCaption", code: -1)))
        XCTAssertFalse(GameCaptionApplier.isBakedIn(nil))
    }

}
