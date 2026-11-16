//
//  OverlayIcons.swift
//  PitchMark
//
//  The built-in overlay icons (2026-11-15): a picked set of Phosphor
//  icons (MIT license - PHOSPHOR-LICENSE.txt, credited in Sound Credits'
//  "Icons" section), replacing the old Circle/Arrow placeholders. They're
//  vector images in the asset catalog ("Overlay Icons" folder, template
//  rendering), drawn white for overlays and tinted per overlay
//  (`OverlayItem.tintHex`) in the editor's preview and in the export.
//
//  Every icon ships in all six Phosphor weights (`ph-<name>-<weight>`:
//  thin, light, regular, bold, fill, duotone) so each overlay can pick its
//  own (`OverlayItem.iconWeight`). To add one: copy its six SVGs from
//  Phosphor into new imagesets in that folder (template rendering,
//  preserve vector data; Phosphor's "regular" files have no suffix) and
//  add a line below naming its default weight.
//

import UIKit

struct OverlayIcon {
    let name: String
    let imageName: String
    let category: OverlayIconCategory
}

/// An icon's line weight (2026-11-15) - every icon ships in all six; each
/// list entry below names its default.
enum OverlayIconWeight: String, CaseIterable, Identifiable {
    case thin, light, regular, bold, fill, duotone

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum OverlayIconCategory: String, CaseIterable {
    case highlight = "Highlight"
    case arrows = "Arrows"
    case ballGame = "Ball Game"
    case marks = "Marks"
    case hype = "Hype"
}

let overlayIcons: [OverlayIcon] = {
    func icons(_ category: OverlayIconCategory, _ list: [(String, String)]) -> [OverlayIcon] {
        list.map { OverlayIcon(name: $0.0, imageName: $0.1, category: category) }
    }
    return icons(.highlight, [
        ("Circle", "ph-circle-bold"), ("Dashed Circle", "ph-circle-dashed-bold"), ("Square", "ph-square-bold"),
        ("Triangle", "ph-triangle-bold"), ("Hexagon", "ph-hexagon-bold"), ("Star Outline", "ph-star-bold"),
        ("Scribble", "ph-scribble-loop-bold"), ("Crosshair", "ph-crosshair-bold"), ("Target", "ph-target-fill"),
        ("Pointing Hand", "ph-hand-pointing-fill"), ("Tap", "ph-cursor-click-fill"),
    ]) + icons(.arrows, [
        ("Up", "ph-arrow-up-bold"), ("Down", "ph-arrow-down-bold"), ("Left", "ph-arrow-left-bold"),
        ("Right", "ph-arrow-right-bold"), ("Up Right", "ph-arrow-up-right-bold"), ("Down Right", "ph-arrow-down-right-bold"),
        ("Bend", "ph-arrow-bend-up-right-bold"), ("Arc", "ph-arrow-arc-right-bold"), ("U-Turn", "ph-arrow-u-up-left-bold"),
        ("Around", "ph-arrow-clockwise-bold"), ("Elbow", "ph-arrow-elbow-right-bold"), ("Fast Forward", "ph-caret-double-right-bold"),
    ]) + icons(.ballGame, [
        ("Baseball", "ph-baseball-fill"), ("Helmet", "ph-baseball-helmet-fill"), ("Cap", "ph-baseball-cap-fill"),
        ("Trophy", "ph-trophy-fill"), ("Medal", "ph-medal-fill"), ("Pennant", "ph-flag-pennant-fill"),
        ("Flag", "ph-flag-fill"), ("Cleat", "ph-sneaker-move-fill"), ("Runner", "ph-person-simple-run-fill"),
        ("Thrower", "ph-person-simple-throw-fill"), ("Fist", "ph-hand-fist-fill"), ("Timer", "ph-timer-fill"),
        ("Megaphone", "ph-megaphone-fill"), ("Siren", "ph-siren-fill"),
    ]) + icons(.marks, [
        ("Check Circle", "ph-check-circle-fill"), ("X Circle", "ph-x-circle-fill"), ("Check", "ph-check-fill"),
        ("X", "ph-x-fill"), ("Warning", "ph-warning-fill"), ("Alert", "ph-warning-circle-fill"),
        ("Question", "ph-question-fill"), ("Exclamation", "ph-exclamation-mark-fill"), ("Plus", "ph-plus-fill"),
        ("Minus", "ph-minus-fill"), ("Eye", "ph-eye-fill"), ("One", "ph-number-circle-one-fill"),
        ("Two", "ph-number-circle-two-fill"), ("Three", "ph-number-circle-three-fill"),
    ]) + icons(.hype, [
        ("Fire", "ph-fire-fill"), ("Lightning", "ph-lightning-fill"), ("Sparkle", "ph-sparkle-fill"),
        ("Star", "ph-star-fill"), ("Crown", "ph-crown-fill"), ("Simple Crown", "ph-crown-simple-fill"),
        ("Confetti", "ph-confetti-fill"), ("Rocket", "ph-rocket-launch-fill"), ("Thumbs Up", "ph-thumbs-up-fill"),
        ("Thumbs Down", "ph-thumbs-down-fill"), ("Clapping", "ph-hands-clapping-fill"), ("Heart", "ph-heart-fill"),
        ("Smiley", "ph-smiley-fill"), ("Wink", "ph-smiley-wink-fill"), ("Wave", "ph-hand-waving-fill"),
        ("Music", "ph-music-notes-fill"),
    ])
}()

enum OverlayIconImages {
    /// Library ids for icons start with this - it's how the editor knows an
    /// overlay can be tinted.
    static let idPrefix = "icon-"
    /// Overlay images are drawn this many pixels square - sharp at the
    /// biggest an overlay gets on a 4K frame.
    static let renderSize: CGFloat = 512

    private static var cache: [String: UIImage] = [:]
    private static let lock = NSLock()

    static func libraryId(for icon: OverlayIcon) -> String { idPrefix + icon.imageName }

    static func isIcon(assetId: String) -> Bool { assetId.hasPrefix(idPrefix) }

    /// "icon-ph-circle-bold" -> ("ph-circle", .bold).
    static func parts(of assetId: String) -> (base: String, weight: OverlayIconWeight)? {
        guard isIcon(assetId: assetId) else { return nil }
        let imageName = String(assetId.dropFirst(idPrefix.count))
        for weight in OverlayIconWeight.allCases where imageName.hasSuffix("-" + weight.rawValue) {
            return (String(imageName.dropLast(weight.rawValue.count + 1)), weight)
        }
        return nil
    }

    /// The icon's own default weight, or nil for anything that isn't an icon.
    static func defaultWeight(of assetId: String) -> OverlayIconWeight? { parts(of: assetId)?.weight }

    /// The image name for an icon overlay at a weight (nil = its default).
    static func imageName(forAssetId assetId: String, weight: String?) -> String? {
        guard let parts = parts(of: assetId) else { return nil }
        let chosen = weight.flatMap(OverlayIconWeight.init(rawValue:)) ?? parts.weight
        return "\(parts.base)-\(chosen.rawValue)"
    }

    /// An icon overlay's white image at its weight.
    static func image(forAssetId assetId: String, weight: String?) -> UIImage? {
        imageName(forAssetId: assetId, weight: weight).flatMap { image(named: $0) }
    }

    /// The icon in white on clear, `renderSize` square.
    static func image(named imageName: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[imageName] { return cached }
        guard let template = UIImage(named: imageName) else { return nil }
        let rendered = draw(template, color: .white)
        cache[imageName] = rendered
        return rendered
    }

    /// `image` recolored - the editor's preview and the export both use it.
    static func tinted(_ image: UIImage, hex: String?) -> UIImage {
        guard let hex, let color = UIColor(hexString: hex) else { return image }
        return draw(image.withRenderingMode(.alwaysTemplate), color: color)
    }

    private static func draw(_ image: UIImage, color: UIColor) -> UIImage {
        let size = CGSize(width: renderSize, height: renderSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.withTintColor(color, renderingMode: .alwaysTemplate).draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

extension UIColor {
    /// "#RRGGBB" (or without the #).
    convenience init?(hexString: String) {
        var text = hexString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}
