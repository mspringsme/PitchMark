import SwiftUI
import UIKit

/// The coach's calling card for a Batting Bases & Fielding card
/// (2026-11-10): every call on the armband card, A to Z, with the number
/// of every cell it's in. A number is the cell's column header + its row
/// header, read from its own grid ("13" + "2" = "132"), so edited headers
/// carry through. A cell with no header number has no number to call.
struct SignGridCallingCard: Hashable {
    struct Call: Hashable {
        let label: String
        /// Ascending, no repeats.
        let codes: [String]
    }

    let title: String
    let calls: [Call]
    /// Cells with a call but no column or row number - nothing to call
    /// them by.
    let unnumberedCount: Int

    init(grid: SignGrid) {
        var codesByLabel: [String: Set<String>] = [:]
        var unnumbered = 0
        for index in 0..<grid.gridCount {
            for row in 1..<max(grid.rows, 1) {
                let rowHeader = grid.text(row: row, column: 0, in: index).trimmingCharacters(in: .whitespacesAndNewlines)
                for column in 1..<max(grid.columns, 1) {
                    let label = grid.text(row: row, column: column, in: index).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !label.isEmpty else { continue }
                    let columnHeader = grid.text(row: 0, column: column, in: index)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !rowHeader.isEmpty, !columnHeader.isEmpty else {
                        unnumbered += 1
                        continue
                    }
                    codesByLabel[label, default: []].insert(columnHeader + rowHeader)
                }
            }
        }
        title = grid.name
        calls = codesByLabel
            .map { Call(label: $0.key, codes: $0.value.sorted { $0.localizedStandardCompare($1) == .orderedAscending }) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        unnumberedCount = unnumbered
    }

    var isEmpty: Bool { calls.isEmpty }
}

/// The card itself: a box per call, its label on a black band and its
/// numbers under it, like a printed coach's card. On screen and in the PDF.
struct SignGridCallingCardView: View {
    let card: SignGridCallingCard
    var columns: Int = 3
    var scale: CGFloat = 1
    /// The card's width when it's known (print and preview): every label
    /// then shares one size, the largest that fits the longest one.
    var width: CGFloat? = nil

    private var baseLabelSize: CGFloat { 16 * scale }

    /// One size for every label on the card, so the bands match.
    var labelSize: CGFloat {
        guard let width, columns > 0 else { return baseLabelSize }
        let room = width / CGFloat(columns) - 6 * scale - 4
        let font = UIFont.systemFont(ofSize: baseLabelSize, weight: .bold)
        let widest = card.calls.map { ($0.label as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        guard widest > room, widest > 0 else { return baseLabelSize }
        return max(baseLabelSize * 0.5, baseLabelSize * room / widest)
    }

    /// Every band the same height, whatever its label.
    var bandHeight: CGFloat { (baseLabelSize * 1.25 + 8 * scale).rounded(.up) }

    private var codeSize: CGFloat { 16 * scale }

    /// How many numbers fit on one line of a box, when the width is known.
    var codesPerLine: Int? {
        guard let width, columns > 0 else { return nil }
        return Self.codesPerLine(boxWidth: width / CGFloat(columns), codeSize: codeSize, padding: 5 * scale)
    }

    static func codesPerLine(boxWidth: CGFloat, codeSize: CGFloat, padding: CGFloat) -> Int {
        let font = UIFont.monospacedSystemFont(ofSize: codeSize, weight: .regular)
        let char = ("0" as NSString).size(withAttributes: [.font: font]).width
        let longest = 3   // typical "132"; longer codes still wrap by line count
        let room = boxWidth - padding * 2 - 2
        return max(1, Int(((room + char) / (CGFloat(longest + 1) * char)).rounded(.down)))
    }

    /// A call's numbers in lines of `perLine`, padded with blank lines to
    /// `lines` so every box on the card is the same height.
    static func codeLines(_ codes: [String], perLine: Int, lines: Int) -> [String] {
        let perLine = max(perLine, 1)
        var result = stride(from: 0, to: codes.count, by: perLine).map {
            codes[$0..<min($0 + perLine, codes.count)].joined(separator: " ")
        }
        while result.count < lines { result.append(" ") }
        return result
    }

    /// The card's height laid out `width` wide (scale 1), worked out from
    /// the same sizes the view uses - every box is one height, so it's
    /// rows x box. Instant, unlike rendering to measure; the print tests
    /// check the drawing against it.
    static func height(of card: SignGridCallingCard, columns: Int, width: CGFloat) -> CGFloat {
        let view = SignGridCallingCardView(card: card, columns: columns, width: width)
        let title = UIFont.systemFont(ofSize: 22, weight: .bold).lineHeight
        let spacing: CGFloat = 10
        func textHeight(_ text: String, size: CGFloat) -> CGFloat {
            (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                                            attributes: [.font: UIFont.systemFont(ofSize: size)], context: nil).height.rounded(.up)
        }
        var total = title
        if card.isEmpty {
            total += spacing + textHeight(emptyText, size: 15)
        } else {
            let perLine = view.codesPerLine ?? 1
            let lines = CGFloat(lineCount(for: card, perLine: perLine))
            let line = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular).lineHeight
            let box = view.bandHeight + lines * line + 10
            let rows = CGFloat((card.calls.count + columns - 1) / max(columns, 1))
            total += spacing + rows * box
        }
        if card.unnumberedCount > 0 {
            total += spacing + textHeight(unnumberedText(card.unnumberedCount), size: 13)
        }
        return total.rounded(.up)
    }

    static let emptyText = "No calls yet. Put calls in the grid's cells and they show up here with their numbers."

    static func unnumberedText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "cell has" : "cells have") a call but no column or row number, so \(count == 1 ? "it isn't" : "they aren't") listed."
    }

    /// The most lines any box needs - every box gets that many.
    static func lineCount(for card: SignGridCallingCard, perLine: Int) -> Int {
        card.calls.map { ($0.codes.count + max(perLine, 1) - 1) / max(perLine, 1) }.max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            Text(card.title.isEmpty ? "Calling Card" : card.title)
                .font(.system(size: 22 * scale, weight: .bold))
            if card.isEmpty {
                Text(Self.emptyText)
                    .font(.system(size: 15 * scale))
                    .foregroundStyle(Color.gray)
            } else {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(Array(stride(from: 0, to: card.calls.count, by: columns)), id: \.self) { start in
                        GridRow {
                            ForEach(0..<columns, id: \.self) { offset in
                                let index = start + offset
                                if index < card.calls.count {
                                    box(card.calls[index])
                                } else {
                                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                }
                            }
                        }
                    }
                }
            }
            if card.unnumberedCount > 0 {
                Text(Self.unnumberedText(card.unnumberedCount))
                    .font(.system(size: 13 * scale))
                    .foregroundStyle(Color.gray)
            }
        }
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
    }

    private func box(_ call: SignGridCallingCard.Call) -> some View {
        VStack(spacing: 0) {
            // One line at the card's one label size, on a band the same
            // height as every other.
            Text(call.label)
                .font(.system(size: labelSize, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 3 * scale)
                .frame(maxWidth: .infinity)
                .frame(height: bandHeight)
                .background(Color.black)
            if let perLine = codesPerLine {
                // Even lines, and every box as tall as the tallest one.
                let lines = Self.codeLines(call.codes, perLine: perLine,
                                           lines: Self.lineCount(for: card, perLine: perLine))
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: codeSize, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(height: UIFont.monospacedSystemFont(ofSize: codeSize, weight: .regular).lineHeight)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(5 * scale)
            } else {
                Text(call.codes.joined(separator: " "))
                    .font(.system(size: codeSize, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(5 * scale)
            }
        }
        .overlay(Rectangle().stroke(Color.black, lineWidth: 0.75 * scale))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("callingCard.call.\(call.label)")
    }
}

enum SignGridCallingCardPrint {
    /// What a calling card prints as (2026-11-10).
    enum Format: String, CaseIterable, Identifiable {
        /// One US letter page.
        case fullPage
        /// A quarter of a letter sheet, 4 1/4 x 5 1/2 in - the size the
        /// waterproof cards are cut to (user's call).
        case pocket

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fullPage: return "Full Page (8 1/2 x 11 in)"
            case .pocket: return "Pocket (4 1/4 x 5 1/2 in)"
            }
        }

        /// 72 pt per inch.
        var size: CGSize {
            switch self {
            case .fullPage: return CGSize(width: 612, height: 792)
            case .pocket: return CGSize(width: 306, height: 396)
            }
        }

        var margin: CGFloat { self == .fullPage ? 36 : 18 }
        var columns: Int { self == .fullPage ? 4 : 3 }
        var fileSuffix: String { self == .fullPage ? "Calling_Card" : "Pocket_Calling_Card" }
    }

    /// Store product: 4 waterproof pocket cards, cut from one letter
    /// sheet, $8 (user's call, 2026-11-10).
    static let waterproofProductId = "calling_card_waterproof"
    static let waterproofPrice: Decimal = 8
    static let letterSize = Format.fullPage.size

    /// Where each of the 4 pocket cards sits on the waterproof sheet, in
    /// top-down page coordinates: the sheet's four quarters. No cut guides
    /// (user's call).
    static var sheetQuarters: [CGRect] {
        let quarter = Format.pocket.size
        return [CGPoint(x: 0, y: 0), CGPoint(x: quarter.width, y: 0),
                CGPoint(x: 0, y: quarter.height), CGPoint(x: quarter.width, y: quarter.height)]
            .map { CGRect(origin: $0, size: quarter) }
    }

    /// How a card sits on its page: how many columns, how wide it's laid
    /// out, and how much that's shrunk. Shrinking keeps the card's full
    /// width: a card too tall for the page is laid out wider (so its boxes
    /// hold more numbers per line) and shrunk back to the page's width,
    /// never left narrow with the side empty. The print and the store
    /// preview both use it, so the preview shows what prints.
    struct Layout: Equatable {
        let columns: Int
        /// The width the card is laid out at, before shrinking.
        let width: CGFloat
        let fit: CGFloat
    }

    static func innerSize(_ format: Format) -> CGSize {
        CGSize(width: format.size.width - format.margin * 2, height: format.size.height - format.margin * 2)
    }

    /// The card's natural size laid out `width` wide.
    static func contentSize(of card: SignGridCallingCard, columns: Int, width: CGFloat) -> CGSize {
        CGSize(width: width, height: SignGridCallingCardView.height(of: card, columns: columns, width: width))
    }

    @MainActor private static var layoutCache: [String: Layout] = [:]

    /// The format's columns when the card fits; otherwise whichever of
    /// up to 2 more columns prints biggest (fewer win a tie).
    @MainActor
    static func layout(for card: SignGridCallingCard, format: Format) -> Layout {
        let key = "\(format.rawValue)|\(card.hashValue)"
        if let cached = layoutCache[key] { return cached }
        let inner = innerSize(format)
        var best: Layout? = nil
        for columns in format.columns...(format.columns + 2) {
            // Fits without shrinking: nothing prints bigger than that.
            if contentSize(of: card, columns: columns, width: inner.width).height <= inner.height {
                best = Layout(columns: columns, width: inner.width, fit: 1)
                break
            }
            // Largest shrink at which the card, laid out inner.width / fit
            // wide, is no taller than the page once shrunk.
            var low: CGFloat = 0.02, high: CGFloat = 1
            for _ in 0..<20 {
                let mid = (low + high) / 2
                let height = contentSize(of: card, columns: columns, width: inner.width / mid).height
                if height * mid <= inner.height { low = mid } else { high = mid }
            }
            if best == nil || low > best!.fit + 0.001 {
                best = Layout(columns: columns, width: inner.width / low, fit: low)
            }
        }
        let result = best ?? Layout(columns: format.columns, width: inner.width, fit: 1)
        layoutCache[key] = result
        return result
    }

    @MainActor
    static func fitScale(for card: SignGridCallingCard, format: Format) -> CGFloat {
        layout(for: card, format: format).fit
    }

    /// Draws one calling card into `rect` (top-down page coordinates) of
    /// the open page, inside the format's margin, shrunk to fit if it has
    /// a lot of calls. Vector, so the numbers can be read back out.
    @MainActor
    private static func drawCard(_ card: SignGridCallingCard, format: Format, in rect: CGRect,
                                 pageHeight: CGFloat, context: CGContext) {
        let layout = layout(for: card, format: format)
        let renderer = ImageRenderer(content: SignGridCallingCardView(card: card, columns: layout.columns, width: layout.width)
            .frame(width: layout.width, alignment: .topLeading))
        renderer.proposedSize = ProposedViewSize(width: layout.width, height: nil)
        renderer.render { size, draw in
            let fit = layout.fit
            context.saveGState()
            // PDF space is bottom-up: the card's top at the rect's top margin.
            context.translateBy(x: rect.minX + format.margin,
                                y: pageHeight - rect.minY - format.margin - size.height * fit)
            context.scaleBy(x: fit, y: fit)
            draw(context)
            context.restoreGState()
        }
    }

    private static func beginPage(_ size: CGSize, in context: CGContext) {
        var mediaBox = CGRect(origin: .zero, size: size)
        let info = [kCGPDFContextMediaBox as String: Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)]
        context.beginPDFPage(info as CFDictionary)
    }

    /// Adds one page holding the calling card at `format`'s size.
    @MainActor
    static func drawPage(for grid: SignGrid, format: Format = .fullPage, in context: CGContext) -> Bool {
        let size = format.size
        beginPage(size, in: context)
        drawCard(SignGridCallingCard(grid: grid), format: format, in: CGRect(origin: .zero, size: size),
                 pageHeight: size.height, context: context)
        context.endPDFPage()
        return true
    }

    /// Adds the waterproof sheet: one letter page, the pocket card in each
    /// quarter.
    @MainActor
    static func drawWaterproofSheet(for grid: SignGrid, in context: CGContext) -> Bool {
        let card = SignGridCallingCard(grid: grid)
        beginPage(letterSize, in: context)
        for quarter in sheetQuarters {
            drawCard(card, format: .pocket, in: quarter, pageHeight: letterSize.height, context: context)
        }
        context.endPDFPage()
        return true
    }

    @MainActor
    private static func write(to url: URL, firstPage: CGSize, _ draw: (CGContext) -> Bool) -> Bool {
        var mediaBox = CGRect(origin: .zero, size: firstPage)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return false }
        let drew = draw(context)
        context.closePDF()
        return drew
    }

    @MainActor
    static func writePDF(for grid: SignGrid, format: Format = .fullPage, to url: URL) -> Bool {
        write(to: url, firstPage: format.size) { drawPage(for: grid, format: format, in: $0) }
    }

    /// The fulfillment PDF for a waterproof order: the card saved with the
    /// order, 4 to a letter sheet.
    @MainActor
    static func writeWaterproofOrderPDF(snapshotJson: String, to url: URL) -> Bool {
        guard let data = snapshotJson.data(using: .utf8),
              let grid = try? JSONDecoder().decode(SignGrid.self, from: data) else { return false }
        return write(to: url, firstPage: letterSize) { drawWaterproofSheet(for: grid, in: $0) }
    }

    static func fileURL(for grid: SignGrid, format: Format = .fullPage) -> URL {
        let safeName = grid.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("PitchMark_\(safeName.isEmpty ? "Grid" : safeName)_\(format.fileSuffix).pdf")
    }
}

extension RetailCheckoutRequest {
    /// The waterproof calling cards: the card's design rides the order,
    /// like a Batting Bases & Fielding order, with no size (they're always
    /// pocket cards).
    static func waterproofCallingCards(_ grid: SignGrid, storeTemplateName: String) -> RetailCheckoutRequest {
        RetailCheckoutRequest(
            retailProductId: SignGridCallingCardPrint.waterproofProductId,
            itemKind: "signGrid",
            templateId: grid.id,
            templateName: grid.name,
            storeTemplateName: storeTemplateName,
            templateSnapshotJson: snapshotJson(grid),
            printSize: nil
        )
    }
}

/// A printed page of the calling card, drawn the way it prints (same
/// margins, same shrink-to-fit) and zoomed to the space it's given. The
/// store's pocket preview: laying the card out freely let a big card run
/// past the box.
struct SignGridCallingCardPagePreview: View {
    let card: SignGridCallingCard
    let format: SignGridCallingCardPrint.Format

    var body: some View {
        let page = format.size
        let layout = SignGridCallingCardPrint.layout(for: card, format: format)
        GeometryReader { proxy in
            SignGridCallingCardView(card: card, columns: layout.columns, width: layout.width)
                .frame(width: layout.width, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .scaleEffect(layout.fit, anchor: .topLeading)
                .frame(width: page.width - format.margin * 2, alignment: .topLeading)
                .padding(format.margin)
                .frame(width: page.width, height: page.height, alignment: .topLeading)
                .background(Color.white)
                .scaleEffect(proxy.size.width / page.width, anchor: .topLeading)
        }
        .aspectRatio(page.width / page.height, contentMode: .fit)
        .clipped()
        .accessibilityIdentifier("callingCard.pagePreview")
    }
}

/// The calling card on screen, with Share/Print.
struct SignGridCallingCardSheet: View {
    let grid: SignGrid
    let onDone: () -> Void

    @State private var shareURL: SignGridCallingCardShare? = nil
    @State private var showFormats = false

    private func share(_ format: SignGridCallingCardPrint.Format) {
        let url = SignGridCallingCardPrint.fileURL(for: grid, format: format)
        if SignGridCallingCardPrint.writePDF(for: grid, format: format, to: url) {
            shareURL = SignGridCallingCardShare(url: url)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                SignGridCallingCardView(card: SignGridCallingCard(grid: grid), columns: 3)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
            }
            .background(Color.white)
            .navigationTitle("Calling Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDone)
                        .accessibilityIdentifier("callingCard.done")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showFormats = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share or print the calling card")
                    .accessibilityIdentifier("callingCard.share")
                }
            }
            .appConfirmationDialog(
                isPresented: $showFormats,
                title: "Save or Print",
                message: "Pick the calling card's size.",
                primaryTitle: SignGridCallingCardPrint.Format.fullPage.title,
                primaryAction: { share(.fullPage) },
                secondaryTitle: "Cancel",
                alternateTitle: SignGridCallingCardPrint.Format.pocket.title,
                alternateAction: { share(.pocket) }
            )
            .sheet(item: $shareURL) { share in
                ShareSheet(items: [share.url])
                    .fixedAppDynamicType()
            }
        }
    }
}

private struct SignGridCallingCardShare: Identifiable {
    let id = UUID()
    let url: URL
}
