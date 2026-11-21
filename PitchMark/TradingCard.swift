//
//  TradingCard.swift
//  PitchMark
//
//  Trading cards (2026-11-19): a family designs their player's baseball /
//  softball card - front and back, one of several original templates - and
//  orders a Family Pack (12 or 24 of their card) or adds it to a Team Set:
//  an organizer (the coach or any team member) gathers every family's card
//  and buys one set per family, shipped to the organizer to hand out, like
//  school photos.
//
//  - A design (fields, template, stats) is saved at users/{uid}/cardDesigns;
//    its photo stays on the phone (Documents/TradingCardPhotos).
//  - Team sets: teams/{teamId}/cardSets/{setId}, one entry per card
//    (entries/{entryId} = the design's id, owned by ownerUid - siblings each
//    get one) carrying consent; the two rendered sides are at
//    cardArt/{teamId}/{setId}/{ownerUid}/{entryId}-front.png|-back.png. Locking freezes them
//    (firestore.rules / storage.rules); checkout copies them for the order.
//  - Prices, pack sizes and set limits are the server's
//    (functions/src/tradingCards.ts) - keep them identical.
//  - No birthdate, school or hometown fields, ever: these are kids.
//
//  Plain types first, for unit tests; screens are in TradingCardViews.swift.
//

import Foundation
import UIKit
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage

// MARK: - Product

enum TradingCardProduct {
    enum FamilyPack: Int, CaseIterable, Identifiable {
        case twelve = 12
        case twentyFour = 24

        var id: Int { rawValue }
        var retailProductId: String { "card_family_\(rawValue)" }
        var priceCents: Int { self == .twelve ? 1499 : 1999 }
    }

    static let familyPackItemKind = "cardFamilyPack"
    static let teamSetItemKind = "cardTeamSet"
    static let teamSetProductId = "card_team_set"
    static let teamSetPriceCents = 1299

    static let minPlayers = 2
    static let maxPlayers = 40
    static let minSets = 1
    static let maxSets = 60

    static func teamSetPriceCents(sets: Int) -> Int { sets * teamSetPriceCents }

    /// A standard 2.5 x 3.5 in card, with 1/8 in bleed on every side.
    static let trimSize = CGSize(width: 2.5, height: 3.5)
    static let bleedInches: CGFloat = 0.125
    static let dpi: CGFloat = 300

    /// One rendered side, bleed included: 825 x 1125 pixels.
    static var pixelSize: CGSize {
        CGSize(width: (trimSize.width + bleedInches * 2) * dpi,
               height: (trimSize.height + bleedInches * 2) * dpi)
    }

    /// A PDF page of one side: 72 pt per inch.
    static var pageSize: CGSize {
        CGSize(width: (trimSize.width + bleedInches * 2) * 72,
               height: (trimSize.height + bleedInches * 2) * 72)
    }

    /// Text stays this far inside the cut (bleed + 1/8 in).
    static var safeInset: CGFloat { (bleedInches * 2) * dpi }
}

// MARK: - Templates (original designs)

enum TradingCardTemplate: String, CaseIterable, Identifiable {
    case classic
    case diamond
    case nightGame
    case chalkLine
    case bold

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .diamond: return "Diamond"
        case .nightGame: return "Night Game"
        case .chalkLine: return "Chalk Line"
        case .bold: return "Bold"
        }
    }

    var primary: UIColor {
        switch self {
        case .classic: return UIColor(red: 0.75, green: 0.11, blue: 0.13, alpha: 1)
        case .diamond: return UIColor(red: 0.10, green: 0.32, blue: 0.62, alpha: 1)
        case .nightGame: return UIColor(red: 0.07, green: 0.10, blue: 0.22, alpha: 1)
        case .chalkLine: return UIColor(red: 0.13, green: 0.42, blue: 0.22, alpha: 1)
        case .bold: return UIColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1)
        }
    }

    var accent: UIColor {
        switch self {
        case .nightGame: return UIColor(red: 0.93, green: 0.76, blue: 0.29, alpha: 1)
        default: return .white
        }
    }

    /// Where each part of the front goes, in pixels of the 825 x 1125 side.
    struct FrontLayout {
        var photo: CGRect
        var name: CGRect
        var number: CGRect
        var team: CGRect
        var position: CGRect
    }

    var front: FrontLayout {
        let size = TradingCardProduct.pixelSize
        let inset = TradingCardProduct.safeInset
        let full = CGRect(origin: .zero, size: size)
        let textWidth = size.width - inset * 2
        switch self {
        case .classic:
            return FrontLayout(
                photo: full.insetBy(dx: 70, dy: 70).divided(atDistance: 220, from: .maxYEdge).remainder,
                name: CGRect(x: inset, y: size.height - 250, width: textWidth, height: 90),
                number: CGRect(x: size.width - inset - 150, y: inset, width: 150, height: 120),
                team: CGRect(x: inset, y: size.height - 160, width: textWidth * 0.62, height: 60),
                position: CGRect(x: inset + textWidth * 0.64, y: size.height - 160, width: textWidth * 0.36, height: 60))
        case .diamond:
            return FrontLayout(
                photo: full,
                name: CGRect(x: inset, y: size.height - 270, width: textWidth - 180, height: 90),
                number: CGRect(x: size.width - inset - 160, y: size.height - 300, width: 160, height: 140),
                team: CGRect(x: inset, y: inset, width: textWidth, height: 60),
                position: CGRect(x: inset, y: size.height - 170, width: textWidth * 0.6, height: 56))
        case .nightGame:
            return FrontLayout(
                photo: full.insetBy(dx: 80, dy: 80).divided(atDistance: 240, from: .maxYEdge).remainder,
                name: CGRect(x: inset, y: size.height - 255, width: textWidth, height: 90),
                number: CGRect(x: size.width - 110 - 150, y: 110, width: 150, height: 110),
                team: CGRect(x: inset, y: size.height - 160, width: textWidth * 0.62, height: 56),
                position: CGRect(x: inset + textWidth * 0.64, y: size.height - 160, width: textWidth * 0.36, height: 56))
        case .chalkLine:
            return FrontLayout(
                photo: full.insetBy(dx: 75, dy: 75),
                name: CGRect(x: inset + 20, y: size.height - 235, width: textWidth - 40, height: 84),
                number: CGRect(x: size.width - inset - 140, y: inset + 10, width: 140, height: 110),
                team: CGRect(x: inset + 20, y: size.height - 138, width: textWidth * 0.6, height: 44),
                position: CGRect(x: inset + 20 + textWidth * 0.62, y: size.height - 138, width: textWidth * 0.38 - 40, height: 44))
        case .bold:
            return FrontLayout(
                photo: full,
                name: CGRect(x: inset, y: size.height - 220, width: textWidth, height: 100),
                number: CGRect(x: size.width - inset - 240, y: size.height - 470, width: 240, height: 220),
                team: CGRect(x: inset, y: inset, width: textWidth * 0.7, height: 64),
                position: CGRect(x: size.width - inset - textWidth * 0.28, y: inset, width: textWidth * 0.28, height: 64))
        }
    }
}

// MARK: - Design

struct TradingCardStat: Hashable, Codable {
    var label: String
    var value: String
}

struct TradingCardDesign: Identifiable, Equatable {
    var id: String
    var templateId: String
    var teamId: String
    var teamName: String
    var teamPlayerId: String
    var hitterId: String
    var playerName: String
    var jerseyNumber: String
    var position: String
    var batsThrows: String
    var favoritePlayer: String
    var funFact: String
    var stats: [TradingCardStat]
    var statsLabel: String
    var createdAt: Date
    var updatedAt: Date

    static let nameMax = 40
    static let shortMax = 24
    static let funFactMax = 120

    var template: TradingCardTemplate { TradingCardTemplate(rawValue: templateId) ?? .classic }

    init(id: String = UUID().uuidString, template: TradingCardTemplate = .classic,
         teamId: String = "", teamName: String = "", teamPlayerId: String = "", hitterId: String = "",
         playerName: String = "", jerseyNumber: String = "", position: String = "", batsThrows: String = "",
         favoritePlayer: String = "", funFact: String = "", stats: [TradingCardStat] = [], statsLabel: String = "",
         now: Date = Date()) {
        self.id = id
        self.templateId = template.rawValue
        self.teamId = teamId
        self.teamName = teamName
        self.teamPlayerId = teamPlayerId
        self.hitterId = hitterId
        self.playerName = playerName
        self.jerseyNumber = jerseyNumber
        self.position = position
        self.batsThrows = batsThrows
        self.favoritePlayer = favoritePlayer
        self.funFact = funFact
        self.stats = stats
        self.statsLabel = statsLabel
        self.createdAt = now
        self.updatedAt = now
    }

    /// A card for one roster row.
    static func forPlayer(_ player: TeamPlayer, team: Team) -> TradingCardDesign {
        let bats = player.battingSide.map { "Bats \($0.displayName)" } ?? ""
        return TradingCardDesign(
            teamId: team.id ?? "", teamName: team.name, teamPlayerId: player.id ?? "",
            hitterId: player.hitterId ?? "",
            playerName: NumberOnlyName.number(in: player.name) != nil ? "" : player.name,
            jerseyNumber: player.jerseyNumber ?? "",
            position: (player.positions ?? []).map(\.rawValue).joined(separator: " / "),
            batsThrows: bats)
    }

    var firestoreData: [String: Any] {
        [
            "templateId": templateId, "teamId": teamId, "teamName": teamName,
            "teamPlayerId": teamPlayerId, "hitterId": hitterId,
            "playerName": playerName, "jerseyNumber": jerseyNumber, "position": position,
            "batsThrows": batsThrows, "favoritePlayer": favoritePlayer, "funFact": funFact,
            "stats": stats.map { ["label": $0.label, "value": $0.value] },
            "statsLabel": statsLabel,
            "createdAt": Timestamp(date: createdAt), "updatedAt": Timestamp(date: updatedAt)
        ]
    }

    init?(id: String, data: [String: Any]) {
        guard let name = data["playerName"] as? String else { return nil }
        self.init(id: id)
        templateId = data["templateId"] as? String ?? TradingCardTemplate.classic.rawValue
        teamId = data["teamId"] as? String ?? ""
        teamName = data["teamName"] as? String ?? ""
        teamPlayerId = data["teamPlayerId"] as? String ?? ""
        hitterId = data["hitterId"] as? String ?? ""
        playerName = name
        jerseyNumber = data["jerseyNumber"] as? String ?? ""
        position = data["position"] as? String ?? ""
        batsThrows = data["batsThrows"] as? String ?? ""
        favoritePlayer = data["favoritePlayer"] as? String ?? ""
        funFact = data["funFact"] as? String ?? ""
        stats = (data["stats"] as? [[String: Any]] ?? []).compactMap { row in
            guard let label = row["label"] as? String, let value = row["value"] as? String else { return nil }
            return TradingCardStat(label: label, value: value)
        }
        statsLabel = data["statsLabel"] as? String ?? ""
        createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
    }

    /// The photo file on this phone.
    var photoURL: URL? { TradingCardPhotos.url(for: id) }
}

enum TradingCardPhotos {
    static func url(for designId: String) -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let folder = documents.appendingPathComponent("TradingCardPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(designId).jpg")
    }

    static func save(_ image: UIImage, for designId: String) {
        guard let url = url(for: designId), let data = image.jpegData(compressionQuality: 0.92) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load(for designId: String) -> UIImage? {
        guard let url = url(for: designId) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

// MARK: - Stats (the back)

/// The card back's numbers - the same values and formatting as the stats
/// screens (HitterStatsView's grid: `HittingStatLine.formatRate`, counts).
enum TradingCardStats {
    static let labels = ["AVG", "OBP", "H", "2B", "HR", "RBI", "BB", "SB"]

    static func lines(from line: HittingStatLine) -> [TradingCardStat] {
        [
            TradingCardStat(label: "AVG", value: HittingStatLine.formatRate(line.average)),
            TradingCardStat(label: "OBP", value: HittingStatLine.formatRate(line.onBase)),
            TradingCardStat(label: "H", value: "\(line.hits)"),
            TradingCardStat(label: "2B", value: "\(line.doubles)"),
            TradingCardStat(label: "HR", value: "\(line.homeRuns)"),
            TradingCardStat(label: "RBI", value: "\(line.runsBattedIn)"),
            TradingCardStat(label: "BB", value: "\(line.walks)"),
            TradingCardStat(label: "SB", value: "\(line.stolenBases)")
        ]
    }

    /// The player's whole record (the stats screens' "All").
    @MainActor
    static func load(hitterId: String, authManager: AuthManager, completion: @escaping ([TradingCardStat]) -> Void) {
        guard !hitterId.isEmpty else { completion([]); return }
        var pitches: [PitchEvent] = []
        var runs: [RunnerEvent] = []
        let group = DispatchGroup()
        group.enter()
        authManager.loadHitterEvents(hitterId: hitterId) { events in
            DispatchQueue.main.async { pitches = events; group.leave() }
        }
        group.enter()
        RunnerEventStore.loadForHitters([hitterId]) { events in
            DispatchQueue.main.async { runs = events; group.leave() }
        }
        group.notify(queue: .main) {
            completion(lines(from: HittingStatLine(events: pitches, runnerEvents: runs)))
        }
    }
}

// MARK: - Fitting text

enum TradingCardText {
    /// The largest font from `base` down to `min` at which `text` fits
    /// `width`; below that the text is shortened with "…". Never wider.
    static func fit(_ text: String, width: CGFloat, base: CGFloat, min: CGFloat,
                    weight: UIFont.Weight = .bold) -> (text: String, font: UIFont) {
        var size = base
        var font = UIFont.systemFont(ofSize: size, weight: weight)
        while size > min, measure(text, font) > width {
            size -= 1
            font = UIFont.systemFont(ofSize: size, weight: weight)
        }
        var shown = text
        while measure(shown, font) > width, shown.count > 1 {
            shown = String(shown.dropLast(shown.hasSuffix("…") ? 2 : 1)) + "…"
        }
        return (shown, font)
    }

    static func measure(_ text: String, _ font: UIFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

// MARK: - Rendering

enum TradingCardRenderer {
    private static var format: UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return format
    }

    static func renderFront(_ design: TradingCardDesign, photo: UIImage?) -> UIImage {
        let size = TradingCardProduct.pixelSize
        let template = design.template
        let layout = template.front
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let full = CGRect(origin: .zero, size: size)
            template.primary.setFill()
            context.fill(full)
            if template == .classic || template == .chalkLine {
                UIColor.white.setFill()
                context.fill(full.insetBy(dx: 50, dy: 50))
                template.primary.setFill()
                context.fill(full.insetBy(dx: 50, dy: 50).divided(atDistance: 260, from: .maxYEdge).slice)
            }
            drawPhoto(photo, in: layout.photo, context: context.cgContext)
            switch template {
            case .classic:
                break
            case .diamond:
                let band = UIBezierPath()
                band.move(to: CGPoint(x: 0, y: size.height - 120))
                band.addLine(to: CGPoint(x: size.width, y: size.height - 380))
                band.addLine(to: CGPoint(x: size.width, y: size.height))
                band.addLine(to: CGPoint(x: 0, y: size.height))
                band.close()
                template.primary.withAlphaComponent(0.92).setFill()
                band.fill()
            case .nightGame:
                template.accent.setStroke()
                let line = UIBezierPath(rect: layout.photo.insetBy(dx: -12, dy: -12))
                line.lineWidth = 6
                line.stroke()
            case .chalkLine:
                UIColor.white.setStroke()
                let line = UIBezierPath(roundedRect: full.insetBy(dx: 64, dy: 64), cornerRadius: 24)
                line.lineWidth = 8
                line.stroke()
                UIColor.white.setFill()
                UIBezierPath(roundedRect: layout.name.insetBy(dx: -16, dy: -6), cornerRadius: 14).fill()
            case .bold:
                template.primary.setFill()
                context.fill(CGRect(x: 0, y: 0, width: size.width, height: layout.team.maxY + 20))
                context.fill(CGRect(x: 0, y: layout.name.minY - 20, width: size.width, height: size.height - layout.name.minY + 20))
            }
            let nameColor: UIColor = template == .chalkLine ? template.primary : template.accent
            draw(design.playerName.isEmpty ? "#\(design.jerseyNumber)" : design.playerName,
                 in: layout.name, base: 72, min: 30, color: nameColor)
            if !design.jerseyNumber.isEmpty {
                draw("#\(design.jerseyNumber)", in: layout.number, base: template == .bold ? 150 : 84, min: 36,
                     color: template.accent, alignment: .right, shadow: true)
            }
            draw(design.teamName, in: layout.team, base: 42, min: 22,
                 color: template.accent, weight: .semibold, shadow: template == .diamond)
            draw(design.position, in: layout.position, base: 40, min: 22,
                 color: template.accent, weight: .semibold, alignment: .right, shadow: template == .diamond)
        }
    }

    static func renderBack(_ design: TradingCardDesign) -> UIImage {
        let size = TradingCardProduct.pixelSize
        let template = design.template
        let inset = TradingCardProduct.safeInset
        let width = size.width - inset * 2
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let full = CGRect(origin: .zero, size: size)
            UIColor.white.setFill()
            context.fill(full)
            template.primary.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: 230))
            context.fill(CGRect(x: 0, y: size.height - 110, width: size.width, height: 110))

            let header = design.playerName.isEmpty ? "#\(design.jerseyNumber)" : design.playerName
            draw(header, in: CGRect(x: inset, y: inset, width: width * 0.72, height: 80), base: 60, min: 28, color: template.accent)
            if !design.jerseyNumber.isEmpty {
                draw("#\(design.jerseyNumber)", in: CGRect(x: inset + width * 0.74, y: inset, width: width * 0.26, height: 80),
                     base: 60, min: 28, color: template.accent, alignment: .right)
            }
            draw(design.teamName, in: CGRect(x: inset, y: inset + 90, width: width, height: 50),
                 base: 36, min: 20, color: template.accent, weight: .semibold)

            var y: CGFloat = 270
            for line in [design.position, design.batsThrows] where !line.isEmpty {
                draw(line, in: CGRect(x: inset, y: y, width: width, height: 50), base: 36, min: 20,
                     color: .darkGray, weight: .semibold)
                y += 58
            }

            if !design.stats.isEmpty {
                y += 16
                if !design.statsLabel.isEmpty {
                    draw(design.statsLabel.uppercased(), in: CGRect(x: inset, y: y, width: width, height: 40),
                         base: 28, min: 18, color: template.primary, weight: .heavy)
                    y += 46
                }
                let columns = design.stats.count
                let cell = width / CGFloat(columns)
                for (index, stat) in design.stats.enumerated() {
                    let x = inset + CGFloat(index) * cell
                    draw(stat.label, in: CGRect(x: x, y: y, width: cell, height: 36), base: 26, min: 14,
                         color: .gray, weight: .bold, alignment: .center)
                    draw(stat.value, in: CGRect(x: x, y: y + 40, width: cell, height: 44), base: 34, min: 16,
                         color: .black, weight: .bold, alignment: .center)
                }
                y += 110
            }

            if !design.favoritePlayer.isEmpty {
                draw("Favorite player: \(design.favoritePlayer)", in: CGRect(x: inset, y: y, width: width, height: 44),
                     base: 30, min: 18, color: .darkGray, weight: .regular)
                y += 56
            }
            if !design.funFact.isEmpty {
                drawWrapped(design.funFact, in: CGRect(x: inset, y: y, width: width, height: size.height - 140 - y),
                            size: 30, color: .darkGray)
            }
            draw("PitchMark", in: CGRect(x: inset, y: size.height - 95, width: width, height: 44), base: 30, min: 18,
                 color: template.accent, weight: .heavy, alignment: .center)
        }
    }

    private static func drawPhoto(_ photo: UIImage?, in rect: CGRect, context: CGContext) {
        guard let photo, photo.size.width > 0, photo.size.height > 0 else {
            UIColor(white: 0.85, alpha: 1).setFill()
            context.fill(rect)
            return
        }
        let scale = max(rect.width / photo.size.width, rect.height / photo.size.height)
        let drawn = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
        context.saveGState()
        context.clip(to: rect)
        photo.draw(in: CGRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                              width: drawn.width, height: drawn.height))
        context.restoreGState()
    }

    private static func draw(_ text: String, in box: CGRect, base: CGFloat, min: CGFloat, color: UIColor,
                             weight: UIFont.Weight = .bold, alignment: NSTextAlignment = .left, shadow: Bool = false) {
        guard !text.isEmpty else { return }
        let fitted = TradingCardText.fit(text, width: box.width, base: base, min: min, weight: weight)
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byClipping
        var attributes: [NSAttributedString.Key: Any] = [.font: fitted.font, .foregroundColor: color, .paragraphStyle: style]
        if shadow {
            let textShadow = NSShadow()
            textShadow.shadowColor = UIColor.black.withAlphaComponent(0.6)
            textShadow.shadowBlurRadius = 6
            textShadow.shadowOffset = CGSize(width: 0, height: 2)
            attributes[.shadow] = textShadow
        }
        let height = fitted.font.lineHeight
        (fitted.text as NSString).draw(in: CGRect(x: box.minX, y: box.midY - height / 2, width: box.width, height: height),
                                       withAttributes: attributes)
    }

    private static func drawWrapped(_ text: String, in box: CGRect, size: CGFloat, color: UIColor) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(string: text, attributes: [
            .font: UIFont.italicSystemFont(ofSize: size), .foregroundColor: color, .paragraphStyle: style
        ])
        attributed.draw(with: box, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }
}

// MARK: - Team set print order

/// The order a team set prints in: each family's set in turn, players by
/// jersey number (numberless last, by name), each card front then back.
enum TeamCardSetPlan {
    struct Card: Hashable {
        /// The entry id.
        var id: String
        var playerName: String
        var jerseyNumber: String
    }

    struct Page: Hashable {
        var set: Int
        var id: String
        var isFront: Bool
    }

    static func sorted(_ cards: [Card]) -> [Card] {
        cards.sorted { a, b in
            switch (Int(a.jerseyNumber), Int(b.jerseyNumber)) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default:
                let byName = a.playerName.localizedCaseInsensitiveCompare(b.playerName)
                return byName == .orderedSame ? a.id < b.id : byName == .orderedAscending
            }
        }
    }

    static func pages(_ cards: [Card], sets: Int) -> [Page] {
        let order = sorted(cards)
        return (0..<max(sets, 0)).flatMap { set in
            order.flatMap { card in [Page(set: set, id: card.id, isFront: true), Page(set: set, id: card.id, isFront: false)] }
        }
    }

    /// A PDF of the whole order (one side a page, each page one card with
    /// bleed) - the organizer's preview, and a print file.
    @discardableResult
    static func writePDF(_ cards: [Card], sets: Int, art: [String: (front: UIImage, back: UIImage)], to url: URL) throws -> Int {
        let bounds = CGRect(origin: .zero, size: TradingCardProduct.pageSize)
        let plan = pages(cards, sets: sets)
        try UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: url) { context in
            for page in plan {
                context.beginPage()
                guard let images = art[page.id] else { continue }
                (page.isFront ? images.front : images.back).draw(in: bounds)
            }
        }
        return plan.count
    }
}

// MARK: - Stores

@MainActor
final class TradingCardDesignStore: ObservableObject {
    @Published private(set) var designs: [TradingCardDesign] = []
    private var listener: ListenerRegistration? = nil
    private var uid: String? = nil

    private static func collection(_ uid: String) -> CollectionReference {
        Firestore.firestore().collection("users").document(uid).collection("cardDesigns")
    }

    func start(uid: String?) {
        guard uid != self.uid else { return }
        listener?.remove()
        listener = nil
        self.uid = uid
        designs = []
        guard let uid, !uid.isEmpty else { return }
        listener = Self.collection(uid).addSnapshotListener { [weak self] snapshot, _ in
            let loaded = (snapshot?.documents ?? [])
                .compactMap { TradingCardDesign(id: $0.documentID, data: $0.data()) }
                .sorted { $0.updatedAt > $1.updatedAt }
            Task { @MainActor in self?.designs = loaded }
        }
    }

    static func save(_ design: TradingCardDesign) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var saved = design
        saved.updatedAt = Date()
        collection(uid).document(saved.id).setData(saved.firestoreData)
    }

    deinit { listener?.remove() }
}

struct TeamCardSet: Identifiable, Equatable {
    enum Status: String { case open, locked, ordered }

    var id: String
    var name: String
    var organizerUid: String
    var status: Status

    init?(id: String, data: [String: Any]) {
        guard let organizer = data["organizerUid"] as? String else { return nil }
        self.id = id
        self.name = data["name"] as? String ?? "Team Cards"
        self.organizerUid = organizer
        self.status = Status(rawValue: data["status"] as? String ?? "") ?? .open
    }
}

struct TeamCardEntry: Identifiable, Equatable {
    var id: String
    var ownerUid: String
    var playerName: String
    var jerseyNumber: String
    var frontPath: String
    var backPath: String

    init?(id: String, data: [String: Any]) {
        guard data["consent"] as? Bool == true, let owner = data["ownerUid"] as? String else { return nil }
        self.id = id
        ownerUid = owner
        playerName = data["playerName"] as? String ?? ""
        jerseyNumber = data["jerseyNumber"] as? String ?? ""
        frontPath = data["frontPath"] as? String ?? ""
        backPath = data["backPath"] as? String ?? ""
    }

    var planCard: TeamCardSetPlan.Card {
        TeamCardSetPlan.Card(id: id, playerName: playerName, jerseyNumber: jerseyNumber)
    }
}

/// A team's card sets, live.
@MainActor
final class TeamCardSetStore: ObservableObject {
    @Published private(set) var sets: [TeamCardSet] = []
    private var listener: ListenerRegistration? = nil
    private(set) var teamId: String? = nil

    static func setsCollection(_ teamId: String) -> CollectionReference {
        Firestore.firestore().collection("teams").document(teamId).collection("cardSets")
    }

    func start(teamId: String?) {
        guard teamId != self.teamId else { return }
        listener?.remove()
        listener = nil
        self.teamId = teamId
        sets = []
        guard let teamId, !teamId.isEmpty else { return }
        listener = Self.setsCollection(teamId).addSnapshotListener { [weak self] snapshot, _ in
            let loaded = (snapshot?.documents ?? []).compactMap { TeamCardSet(id: $0.documentID, data: $0.data()) }
            Task { @MainActor in self?.sets = loaded }
        }
    }

    deinit { listener?.remove() }
}

/// One set's entries, live.
@MainActor
final class TeamCardEntriesStore: ObservableObject {
    @Published private(set) var entries: [TeamCardEntry] = []
    private var listener: ListenerRegistration? = nil

    func start(teamId: String, setId: String) {
        listener?.remove()
        listener = TeamCardSetStore.setsCollection(teamId).document(setId).collection("entries")
            .addSnapshotListener { [weak self] snapshot, _ in
                let loaded = (snapshot?.documents ?? []).compactMap { TeamCardEntry(id: $0.documentID, data: $0.data()) }
                Task { @MainActor in self?.entries = loaded }
            }
    }

    deinit { listener?.remove() }
}

// MARK: - Orders and submissions

enum TradingCardOrders {
    enum OrderError: LocalizedError {
        case signedOut, noCheckout, notReady

        var errorDescription: String? {
            switch self {
            case .signedOut: return "Sign in first."
            case .noCheckout: return "Checkout link was not returned."
            case .notReady: return "Couldn't make the card. Try again."
            }
        }
    }

    private static func png(_ image: UIImage) throws -> Data {
        guard let data = image.pngData() else { throw OrderError.notReady }
        return data
    }

    private static func upload(_ data: Data, to path: String) async throws {
        let metadata = StorageMetadata()
        metadata.contentType = "image/png"
        _ = try await Storage.storage().reference(withPath: path).putDataAsync(data, metadata: metadata)
    }

    private static func checkout(_ payload: [String: Any]) async throws -> URL {
        let result = try await Functions.functions().httpsCallable("createRetailCheckoutSession").call(payload)
        guard let data = result.data as? [String: Any],
              let string = data["checkoutUrl"] as? String,
              let url = URL(string: string) else { throw OrderError.noCheckout }
        return url
    }

    /// Uploads the card's two sides for this order only, then checkout.
    static func orderFamilyPack(_ design: TradingCardDesign, photo: UIImage?, pack: TradingCardProduct.FamilyPack) async throws -> URL {
        guard let uid = Auth.auth().currentUser?.uid else { throw OrderError.signedOut }
        let key = "cards_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let front = "bookUploads/\(uid)/\(key)/card-front.png"
        let back = "bookUploads/\(uid)/\(key)/card-back.png"
        try await upload(png(TradingCardRenderer.renderFront(design, photo: photo)), to: front)
        try await upload(png(TradingCardRenderer.renderBack(design)), to: back)
        return try await checkout([
            "retailProductId": pack.retailProductId,
            "itemKind": TradingCardProduct.familyPackItemKind,
            "templateId": design.id,
            "templateName": design.playerName,
            "storeTemplateName": "Trading Cards",
            "templateSnapshotJson": "",
            "frontPath": front,
            "backPath": back,
            "idempotencyKey": key
        ])
    }

    static func startSet(teamId: String, name: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw OrderError.signedOut }
        try await TeamCardSetStore.setsCollection(teamId).document().setData([
            "organizerUid": uid, "status": "open", "name": name, "createdAt": Timestamp(date: Date())
        ])
    }

    static func artPath(teamId: String, setId: String, uid: String, entryId: String, side: String) -> String {
        "cardArt/\(teamId)/\(setId)/\(uid)/\(entryId)-\(side).png"
    }

    /// The card into the team set, with the parent's consent. One entry per
    /// design (its id), so a family with two players adds two cards.
    static func submit(_ design: TradingCardDesign, photo: UIImage?, teamId: String, setId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw OrderError.signedOut }
        let entryId = design.id
        let front = artPath(teamId: teamId, setId: setId, uid: uid, entryId: entryId, side: "front")
        let back = artPath(teamId: teamId, setId: setId, uid: uid, entryId: entryId, side: "back")
        try await upload(png(TradingCardRenderer.renderFront(design, photo: photo)), to: front)
        try await upload(png(TradingCardRenderer.renderBack(design)), to: back)
        let now = Timestamp(date: Date())
        try await TeamCardSetStore.setsCollection(teamId).document(setId).collection("entries").document(entryId).setData([
            "ownerUid": uid,
            "playerName": design.playerName.isEmpty ? "#\(design.jerseyNumber)" : design.playerName,
            "jerseyNumber": design.jerseyNumber,
            "templateId": design.templateId,
            "frontPath": front,
            "backPath": back,
            "consent": true,
            "consentedAt": now,
            "updatedAt": now
        ])
    }

    static func withdraw(teamId: String, setId: String, entry: TeamCardEntry) async throws {
        try await TeamCardSetStore.setsCollection(teamId).document(setId).collection("entries").document(entry.id).delete()
        if entry.ownerUid == Auth.auth().currentUser?.uid {
            for path in [entry.frontPath, entry.backPath] where !path.isEmpty {
                try? await Storage.storage().reference(withPath: path).delete()
            }
        }
    }

    static func setLocked(_ locked: Bool, teamId: String, setId: String) async throws {
        var update: [String: Any] = ["status": locked ? "locked" : "open"]
        if locked { update["lockedAt"] = Timestamp(date: Date()) }
        try await TeamCardSetStore.setsCollection(teamId).document(setId).updateData(update)
    }

    /// The organizer's order: one set per family, priced by the server.
    static func orderTeamSet(teamId: String, setId: String, sets: Int) async throws -> URL {
        let key = "teamcards_\(setId)_\(sets)".replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "", options: .regularExpression)
        return try await checkout([
            "retailProductId": TradingCardProduct.teamSetProductId,
            "itemKind": TradingCardProduct.teamSetItemKind,
            "templateId": setId,
            "templateName": "Team Set",
            "storeTemplateName": "Trading Cards",
            "templateSnapshotJson": "",
            "teamId": teamId,
            "setId": setId,
            "setCount": sets,
            "idempotencyKey": String(key.prefix(80))
        ])
    }

    static func downloadArt(_ path: String) async -> UIImage? {
        guard !path.isEmpty,
              let data = try? await Storage.storage().reference(withPath: path).data(maxSize: 10 * 1024 * 1024) else { return nil }
        return UIImage(data: data)
    }
}
