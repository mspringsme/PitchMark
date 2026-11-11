//
//  GridKeyPrint.swift
//  PitchMark
//
//  The one place that knows how big a printed grid key is and how it is
//  drawn onto that size. The store preview, the free preview PDF and the
//  fulfillment PDF all go through here, so a card can't preview at one size
//  and print at another.
//
import SwiftUI
import UIKit
import CryptoKit

/// What the store sends to `createRetailCheckoutSession`.
struct RetailCheckoutRequest {
    let retailProductId: String
    let itemKind: String
    let templateId: String
    let templateName: String
    let storeTemplateName: String
    let templateSnapshotJson: String
    let printSize: GridKeyPrintSize?

    /// Identifies a repeat of the same checkout, which reuses its
    /// idempotency key and so its Stripe session - and the server hands back
    /// that session's saved copy of the design. So the size and the design
    /// itself are part of it: an edited key or grid ordered again must not
    /// print the copy from the first checkout.
    var fingerprint: String {
        let size = printSize.map { "\($0.widthInches)x\($0.heightInches)" } ?? ""
        let design = SHA256.hash(data: Data(templateSnapshotJson.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return [retailProductId, itemKind, templateId, storeTemplateName, size, design].joined(separator: "|")
    }

    /// The design copy sent with an order. Sorted keys, so the same design
    /// always gives the same text (and the same fingerprint).
    /// A pitching key order: always `grid_custom`, at the key's own size
    /// (2026-11-10). Nil when that size can't be printed.
    static func gridKey(_ template: PitchTemplate, storeTemplateName: String) -> RetailCheckoutRequest? {
        guard let size = template.printSize else { return nil }
        return RetailCheckoutRequest(
            retailProductId: GridKeyProduct.customProductId,
            itemKind: "gridKey",
            templateId: template.id.uuidString,
            templateName: template.name,
            storeTemplateName: storeTemplateName,
            templateSnapshotJson: snapshotJson(template),
            printSize: size
        )
    }

    static func snapshotJson<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func payload(idempotencyKey: String) -> [String: Any] {
        var payload: [String: Any] = [
            "retailProductId": retailProductId,
            "itemKind": itemKind,
            "templateId": templateId,
            "templateName": templateName,
            "storeTemplateName": storeTemplateName,
            "templateSnapshotJson": templateSnapshotJson,
            "idempotencyKey": idempotencyKey
        ]
        if let printSize {
            payload["printWidthInches"] = printSize.widthInches
            payload["printHeightInches"] = printSize.heightInches
        }
        return payload
    }
}

/// Lays a grid key out on a card and writes it to image or PDF.
enum GridKeyPrint {
    static let outerPadding: CGFloat = 24
    static let textScale: CGFloat = 1.5

    static func view(for template: PitchTemplate, scale: CGFloat) -> PrintableEncryptedGridsView {
        PrintableEncryptedGridsView(
            grid: template.pitchGridValues,
            pitchHeaders: template.pitchGridHeaders,
            strikeTopRow: template.strikeTopRow,
            strikeRows: template.strikeRows,
            ballsTopRow: template.ballsTopRow,
            ballsRows: template.ballsRows,
            pitchFirstColors: template.pitchFirstColors,
            locationFirstColors: template.locationFirstColors,
            outerPadding: outerPadding,
            scale: scale,
            textScale: textScale,
            codeMode: template.codeMode,
            strikeLocationCells: template.strikeLocationCells,
            ballsLocationCells: template.ballsLocationCells
        )
    }

    /// The scale that makes the whole key fit the card. Starts from the
    /// layout estimate, then measures the real render and shrinks until it
    /// fits - text and rounding don't scale perfectly linearly, and an
    /// estimate alone let content run past the card's edge.
    @MainActor
    static func fitScale(for template: PitchTemplate, on target: CGSize) -> CGFloat {
        let base = PrintableEncryptedGridsView.baseContentSize(for: template.pitchGridValues)
        let estimated = CGSize(width: base.width + outerPadding * 2,
                               height: base.height + outerPadding * 2)
        var scale = min(target.width / max(estimated.width, 1),
                        target.height / max(estimated.height, 1))
        for _ in 0..<4 {
            let rendered = renderedSize(view(for: template, scale: scale))
            guard rendered.width > target.width + 0.01 || rendered.height > target.height + 0.01 else { break }
            scale *= min(target.width / rendered.width, target.height / rendered.height) * 0.995
        }
        return scale
    }

    /// The key's natural size, measured at quarter-point precision.
    @MainActor
    static func renderedSize(_ content: some View) -> CGSize {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 4
        guard let image = renderer.uiImage else { return .zero }
        return image.size
    }

    @MainActor
    static func image(for template: PitchTemplate, size: GridKeyPrintSize, pixelScale: CGFloat) -> UIImage? {
        let target = size.points
        let scale = fitScale(for: template, on: target)
        return view(for: template, scale: scale)
            .renderAsPNG(size: target, scale: pixelScale, alignment: .center)
    }

    /// One PDF page exactly `size` big, holding the card edge to edge.
    @MainActor
    static func writePDF(for template: PitchTemplate, size: GridKeyPrintSize, to url: URL) -> Bool {
        guard let image = image(for: template, size: size, pixelScale: 3.0) else { return false }
        let pageRect = CGRect(origin: .zero, size: size.points)
        do {
            try UIGraphicsPDFRenderer(bounds: pageRect).writePDF(to: url) { context in
                context.beginPage()
                image.draw(in: pageRect)
            }
            return true
        } catch {
            debugLog("❌ Failed to write grid key PDF:", error.localizedDescription)
            return false
        }
    }
}
