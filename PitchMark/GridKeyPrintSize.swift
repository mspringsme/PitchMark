//
//  GridKeyPrintSize.swift
//  PitchMark
//
//  The size rules for printed cards - shared with Pitchmark Display,
//  because AuthManager (compiled into both) saves and loads a pitching
//  key's size. Drawing stays in GridKeyPrint.swift (PitchMark only).
//
import Foundation
import CoreGraphics

/// A printed card's physical size, in inches.
struct GridKeyPrintSize: Equatable, Hashable {
    let widthInches: Double
    let heightInches: Double

    static let pointsPerInch: CGFloat = 72

    /// PDF/page size in points. A PDF page is 72 points per inch, so a page
    /// this size prints at exactly `widthInches` x `heightInches`.
    var points: CGSize {
        CGSize(width: CGFloat(widthInches) * Self.pointsPerInch,
               height: CGFloat(heightInches) * Self.pointsPerInch)
    }

    /// "5 x 3 in", "4 1/4 x 2 1/2 in".
    var label: String {
        "\(Self.inchText(widthInches)) x \(Self.inchText(heightInches)) in"
    }

    static func inchText(_ value: Double) -> String {
        let quarters = Int((value * 4).rounded())
        let whole = quarters / 4
        switch quarters % 4 {
        case 1: return "\(whole) 1/4"
        case 2: return "\(whole) 1/2"
        case 3: return "\(whole) 3/4"
        default: return "\(whole)"
        }
    }
}

/// Which size each printed card product prints at. Mirrors
/// functions/src/gridKeyPrintSize.ts - the server checks the same rules
/// before an order is accepted.
enum GridKeyProduct {
    static let customProductId = "grid_custom"
    /// Batter & Runner Grid (SignGrid.swift): always the size the coach
    /// chose, with the same limits as a custom grid key.
    static let signGridProductId = "sign_grid_custom"
    static let customSizedProductIds: Set<String> = [customProductId, signGridProductId]
    static let customWidthRange: ClosedRange<Double> = 3.0...7.0
    static let customHeightRange: ClosedRange<Double> = 2.0...5.0
    static let customStep: Double = 0.25

    static let fixedSizes: [String: GridKeyPrintSize] = [
        "grid_5x3": GridKeyPrintSize(widthInches: 5.0, heightInches: 3.0),
        "grid_3_5x2_75": GridKeyPrintSize(widthInches: 3.5, heightInches: 2.75)
    ]

    static var customWidthOptions: [Double] {
        Array(stride(from: customWidthRange.lowerBound, through: customWidthRange.upperBound, by: customStep))
    }

    static var customHeightOptions: [Double] {
        Array(stride(from: customHeightRange.lowerBound, through: customHeightRange.upperBound, by: customStep))
    }

    static func isCustom(_ productId: String) -> Bool {
        customSizedProductIds.contains(productId)
    }

    /// Products printed on a card (not the 8.5 x 11 sheet).
    static func printsOnCard(_ productId: String) -> Bool {
        fixedSizes[productId] != nil || isCustom(productId)
    }

    static func isValidCustom(_ size: GridKeyPrintSize) -> Bool {
        func onStep(_ value: Double) -> Bool {
            let steps = value / customStep
            return abs(steps - steps.rounded()) < 0.0001
        }
        return customWidthRange.contains(size.widthInches)
            && customHeightRange.contains(size.heightInches)
            && onStep(size.widthInches)
            && onStep(size.heightInches)
    }

    /// The size a grid key product prints at. A custom product uses the
    /// chosen size and returns nil when there isn't a valid one - callers
    /// must not fall back to a standard size, that is how custom orders used
    /// to ship at 5 x 3.
    static func printSize(productId: String, custom: GridKeyPrintSize?) -> GridKeyPrintSize? {
        if isCustom(productId) {
            guard let custom, isValidCustom(custom) else { return nil }
            return custom
        }
        return fixedSizes[productId]
    }

    /// Why an order can't be printed at the size the customer bought, or nil.
    /// Custom orders from before sizes were saved with the order have none.
    static func printSizeProblem(productId: String, orderedSize: GridKeyPrintSize?) -> String? {
        guard printsOnCard(productId),
              printSize(productId: productId, custom: orderedSize) == nil else { return nil }
        return "No print size was saved with this custom order. Ask the customer for the size before printing."
    }

    /// Reads the size saved on a `retailOrders` document.
    static func orderPrintSize(_ data: [String: Any]) -> GridKeyPrintSize? {
        guard let width = (data["printWidthInches"] as? NSNumber)?.doubleValue,
              let height = (data["printHeightInches"] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }
        return GridKeyPrintSize(widthInches: width, heightInches: height)
    }
}

/// A pitching key's own print size (2026-11-10): chosen in its editor, the
/// same way and with the same limits as a Batting Bases & Fielding card,
/// and what the store prints - there are no set sizes to pick any more.
extension PitchTemplate {
    /// Keys saved before keys had a size, and new keys (user's call).
    static let defaultPrintSize = GridKeyPrintSize(widthInches: 5, heightInches: 3)

    var chosenPrintSize: GridKeyPrintSize {
        guard let width = printWidthInches, let height = printHeightInches else { return Self.defaultPrintSize }
        return GridKeyPrintSize(widthInches: width, heightInches: height)
    }

    /// The size the key prints at, or nil when the chosen size is outside
    /// the limits. Never falls back to another size.
    var printSize: GridKeyPrintSize? {
        GridKeyProduct.printSize(productId: GridKeyProduct.customProductId, custom: chosenPrintSize)
    }

    /// Sets the size if it's one a key can print at; otherwise no change.
    mutating func setPrintSize(_ size: GridKeyPrintSize) {
        guard GridKeyProduct.isValidCustom(size) else { return }
        printWidthInches = size.widthInches
        printHeightInches = size.heightInches
    }

    /// The fields saved on a template document.
    var printSizeFirestoreFields: [String: Any] {
        ["printWidthInches": chosenPrintSize.widthInches, "printHeightInches": chosenPrintSize.heightInches]
    }

    /// The size saved on a template document, or nil (the default applies).
    static func savedPrintSize(_ data: [String: Any]) -> GridKeyPrintSize? {
        guard let width = (data["printWidthInches"] as? NSNumber)?.doubleValue,
              let height = (data["printHeightInches"] as? NSNumber)?.doubleValue else { return nil }
        let size = GridKeyPrintSize(widthInches: width, heightInches: height)
        return GridKeyProduct.isValidCustom(size) ? size : nil
    }
}
