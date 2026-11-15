//
//  MomentGameCaption.swift
//  PitchMark
//
//  Moments that know their game (2026-11-15). A clip recorded or a photo
//  taken while a game is open remembers that moment of the game
//  (`MomentGameContext`: game, inning, count, outs, score, batter,
//  pitcher, date) and who was in it (`MomentPlayerTag`). The coach is then
//  asked whether to put some of it as text along the bottom of the video
//  (`GameCaptionOptions` - which items, how long, fade out), and can change
//  that any time from the Moment's Game Info button.
//
//  The caption is an ordinary text overlay (marked by
//  `GameCaption.overlayAssetID`) baked in through the same path the
//  Overlays editor uses, so it also shows - and can be moved or edited -
//  there.
//

import Foundation
import CoreGraphics

/// The game, as it stood when the clip was captured.
struct MomentGameContext: Codable, Equatable {
    var gameId: String? = nil
    /// "Reds 10U vs. MHJ Fastpitch"
    var gameName: String? = nil
    var gameDate: Date? = nil
    var inning: Int? = nil
    var balls: Int? = nil
    var strikes: Int? = nil
    var outs: Int? = nil
    var ourName: String? = nil
    var theirName: String? = nil
    var ourScore: Int? = nil
    var theirScore: Int? = nil
    var batterName: String? = nil
    var batterHitterId: String? = nil
    var pitcherName: String? = nil
    var pitcherId: String? = nil
}

/// A player a Moment is about - from the game it was recorded in, or
/// tagged by hand. Matched to a player through their Hitter or Pitcher
/// record, the same ids stats use.
struct MomentPlayerTag: Codable, Equatable, Hashable {
    var name: String
    var hitterId: String? = nil
    var pitcherId: String? = nil
}

/// Which game items go in the caption, and how it shows.
struct GameCaptionOptions: Codable, Equatable {
    var batter = true
    var pitcher = false
    var inning = true
    var count = true
    var outs = false
    var score = true
    var gameName = true
    var date = true
    /// 0 = the whole clip.
    var seconds: Double = 5
    var fadeOut = true

    static let durationChoices: [Double] = [3, 5, 10, 0]
}

enum GameCaption {
    /// Marks the caption among a Moment's overlays.
    static let overlayAssetID = "game-caption"
    /// Centered near the bottom of the frame.
    static let position = CGPoint(x: 0.5, y: 0.86)

    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        /// nil when the game didn't have it.
        let value: String?
    }

    /// Every item the sheet offers, with the game's value for it.
    static func items(for context: MomentGameContext) -> [Item] {
        [
            Item(id: "batter", title: "Batter", value: clean(context.batterName)),
            Item(id: "pitcher", title: "Pitcher", value: clean(context.pitcherName).map { "P: \($0)" }),
            Item(id: "inning", title: "Inning", value: context.inning.map { "Inn \($0)" }),
            Item(id: "count", title: "Count", value: count(context)),
            Item(id: "outs", title: "Outs", value: context.outs.map { $0 == 1 ? "1 Out" : "\($0) Outs" }),
            Item(id: "score", title: "Score", value: score(context)),
            Item(id: "gameName", title: "Game", value: clean(context.gameName)),
            Item(id: "date", title: "Date", value: context.gameDate.map { $0.formatted(.dateTime.month(.abbreviated).day().year()) })
        ]
    }

    static func isOn(_ id: String, in options: GameCaptionOptions) -> Bool {
        switch id {
        case "batter": return options.batter
        case "pitcher": return options.pitcher
        case "inning": return options.inning
        case "count": return options.count
        case "outs": return options.outs
        case "score": return options.score
        case "gameName": return options.gameName
        case "date": return options.date
        default: return false
        }
    }

    static func set(_ id: String, _ on: Bool, in options: inout GameCaptionOptions) {
        switch id {
        case "batter": options.batter = on
        case "pitcher": options.pitcher = on
        case "inning": options.inning = on
        case "count": options.count = on
        case "outs": options.outs = on
        case "score": options.score = on
        case "gameName": options.gameName = on
        case "date": options.date = on
        default: break
        }
    }

    /// The two lines: the play (batter, pitcher, inning, count, outs) on
    /// top, the game (name, score, date) under it. Nil when nothing chosen
    /// has a value. A single line moves up.
    static func lines(context: MomentGameContext, options: GameCaptionOptions) -> (line1: String, line2: String)? {
        let all = items(for: context)
        func chosen(_ ids: [String]) -> String {
            ids.compactMap { id in
                guard isOn(id, in: options) else { return nil }
                return all.first { $0.id == id }?.value
            }
            .joined(separator: " · ")
        }
        let play = chosen(["batter", "pitcher", "inning", "count", "outs"])
        let game = chosen(["gameName", "score", "date"])
        if play.isEmpty && game.isEmpty { return nil }
        if play.isEmpty { return (game, "") }
        return (play, game)
    }

    /// The caption as a text overlay for a clip `clipDuration` long.
    static func overlay(context: MomentGameContext, options: GameCaptionOptions, clipDuration: Double) -> OverlayItem? {
        guard let lines = lines(context: context, options: options), clipDuration > 0 else { return nil }
        let end = options.seconds > 0 ? min(options.seconds, clipDuration) : clipDuration
        return OverlayItem(
            assetID: overlayAssetID,
            startTime: 0,
            endTime: end,
            keyframes: [OverlayKeyframe(time: 0, position: position)],
            fadeInEnabled: false,
            fadeOutEnabled: options.fadeOut,
            textContent: OverlayTextContent(templateID: "bold", line1: lines.line1, line2: lines.line2)
        )
    }

    /// The Moment's overlays with its caption replaced (or removed).
    static func replacingCaption(in overlays: [OverlayItem], with caption: OverlayItem?) -> [OverlayItem] {
        overlays.filter { $0.assetID != overlayAssetID } + [caption].compactMap { $0 }
    }

    /// Who the clip is about, from the game.
    static func playerTags(from context: MomentGameContext) -> [MomentPlayerTag] {
        var tags: [MomentPlayerTag] = []
        if let name = clean(context.batterName), context.batterHitterId != nil {
            tags.append(MomentPlayerTag(name: name, hitterId: context.batterHitterId))
        }
        if let name = clean(context.pitcherName), context.pitcherId != nil {
            tags.append(MomentPlayerTag(name: name, pitcherId: context.pitcherId))
        }
        return tags
    }

    private static func clean(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func count(_ c: MomentGameContext) -> String? {
        guard let balls = c.balls, let strikes = c.strikes else { return nil }
        return "\(balls)-\(strikes)"
    }

    private static func score(_ c: MomentGameContext) -> String? {
        guard let ours = c.ourScore, let theirs = c.theirScore else { return nil }
        let us = clean(c.ourName) ?? "Us"
        let them = clean(c.theirName) ?? "Them"
        return "\(us) \(ours), \(them) \(theirs)"
    }
}
