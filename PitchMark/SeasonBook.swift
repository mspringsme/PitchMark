//
//  SeasonBook.swift
//  PitchMark
//
//  Season Book (2026-11-19): a printed hardcover of a family's Moments.
//  The family picks a season's stills (favorites ♥ first), orders them,
//  adds captions, and orders the book from Team Supplies.
//
//  The book's layout (which stills, in what order, their captions) is saved
//  to the account at users/{uid}/seasonBooks/{id}. The photos themselves
//  stay on the phone until an order: then one print-ready PDF is uploaded
//  for that order only (bookUploads/{uid}/{orderKey}/interior.pdf), the
//  server prices it from its page count, and after payment it goes to the
//  print partner exactly once (functions/src/seasonBook.ts - keep the page
//  limits and price here identical).
//
//  Plain types up top so they can be unit tested; the views are in
//  SeasonBookViews.swift.
//

import Foundation
import UIKit
import AVFoundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage

// MARK: - Product

enum SeasonBookProduct {
    static let retailProductId = "season_book_hardcover"
    static let itemKind = "seasonBook"

    static let minPages = 30
    static let maxPages = 200
    static let includedPages = 30
    static let baseCents = 4900
    /// Each 2 pages past the included 30.
    static let extraPagePairCents = 100

    /// A square 20 x 20 cm hardcover, printed with 1/8 in bleed on every
    /// side. Confirm against the print partner's spec before launch.
    static let trimInches: CGFloat = 20 / 2.54
    static let bleedInches: CGFloat = 0.125

    /// One PDF page, bleed included. A PDF page is 72 pt per inch.
    static var pageSize: CGSize {
        let side = (trimInches + bleedInches * 2) * 72
        return CGSize(width: side, height: side)
    }

    /// The print-safe area inside the trim (1/2 in in from the cut).
    static var safeInset: CGFloat { (bleedInches + 0.5) * 72 }

    static func isValidPageCount(_ pageCount: Int) -> Bool {
        pageCount >= minPages && pageCount <= maxPages && pageCount % 2 == 0
    }

    /// Same as the server's seasonBookPriceCents.
    static func priceCents(pageCount: Int) -> Int? {
        guard isValidPageCount(pageCount) else { return nil }
        let extraPairs = max(0, pageCount - includedPages) / 2
        return baseCents + extraPairs * extraPagePairCents
    }

    /// The printed page count for a book with this many pages of its own:
    /// at least the minimum, always even (blank pages fill the end). Nil
    /// when it's more than the book can hold.
    static func printedPageCount(contentPages: Int) -> Int? {
        let even = contentPages + (contentPages % 2)
        let count = max(minPages, even)
        return count <= maxPages ? count : nil
    }
}

// MARK: - Model

struct SeasonBookPage: Hashable, Identifiable {
    /// A `HomeSlide` id: a Moment's photo ("p-…") or its clip's frame ("f-…").
    var slideId: String
    var caption: String = ""

    var id: String { slideId }
    var slide: HomeSlide? { HomeSlide(id: slideId) }

    static let captionMax = 120
}

struct SeasonBook: Identifiable, Equatable {
    var id: String
    var name: String
    var pages: [SeasonBookPage]
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date? = nil

    static let nameMax = 60
    /// The title page, then one page per still.
    var contentPageCount: Int { 1 + pages.count }
    var printedPageCount: Int? { SeasonBookProduct.printedPageCount(contentPages: contentPageCount) }
    var priceCents: Int? { printedPageCount.flatMap { SeasonBookProduct.priceCents(pageCount: $0) } }

    init(id: String = UUID().uuidString, name: String, pages: [SeasonBookPage] = [], now: Date = Date()) {
        self.id = id
        self.name = name
        self.pages = pages
        self.createdAt = now
        self.updatedAt = now
    }

    /// Pages are an array of maps - Firestore can't hold nested arrays.
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "name": name,
            "pages": pages.map { ["slide": $0.slideId, "caption": $0.caption] },
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
        data["archivedAt"] = archivedAt.map { Timestamp(date: $0) } ?? NSNull()
        return data
    }

    init?(id: String, data: [String: Any]) {
        guard let name = data["name"] as? String else { return nil }
        self.id = id
        self.name = name
        self.pages = (data["pages"] as? [[String: Any]] ?? []).compactMap { row in
            guard let slide = row["slide"] as? String, HomeSlide(id: slide) != nil else { return nil }
            return SeasonBookPage(slideId: slide, caption: row["caption"] as? String ?? "")
        }
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
        self.archivedAt = (data["archivedAt"] as? Timestamp)?.dateValue()
    }
}

// MARK: - Suggestion

/// The pages a new book starts with: every ♥ still first (newest Moment
/// first), then the rest of the coach's stills, never a hidden one and never
/// a still twice. Moments only - shipped slideshow art isn't theirs to print.
enum SeasonBookSuggestion {
    static func pages(
        moments: [Moment],
        prefs: HomeSlideshowPrefs,
        photoExists: (String, Int) -> Bool,
        videoExists: (String) -> Bool,
        limit: Int = SeasonBookProduct.maxPages - 1
    ) -> [SeasonBookPage] {
        let hidden = Set(prefs.hidden)
        let favorites = HomeSlideshowPlaylist.favoriteStills(
            moments: moments, prefs: prefs, photoExists: photoExists, videoExists: videoExists)
        let everything = HomeSlideshowPlaylist.allStills(
            moments: moments, photoExists: photoExists, videoExists: videoExists, bundled: [])
        var seen = Set<String>()
        var result: [SeasonBookPage] = []
        for slide in favorites + everything {
            guard result.count < limit, slide.momentId != nil,
                  !hidden.contains(slide.id), seen.insert(slide.id).inserted else { continue }
            result.append(SeasonBookPage(slideId: slide.id))
        }
        return result
    }
}

// MARK: - Print

enum SeasonBookPrint {
    /// Longest side of a printed photo: 8 in at 300 dpi.
    static let printPixels: CGFloat = 2400

    enum PrintError: LocalizedError {
        case tooManyPages
        case missingImage(String)

        var errorDescription: String? {
            switch self {
            case .tooManyPages:
                return "A season book holds up to \(SeasonBookProduct.maxPages - 1) photos."
            case .missingImage:
                return "A photo in this book isn't on this phone any more. Remove it and try again."
            }
        }
    }

    /// Writes the book's interior: a title page, one still per page with
    /// its caption, then blank pages up to the printed page count. Every
    /// page is exactly `SeasonBookProduct.pageSize`. Returns the page count.
    @discardableResult
    static func writePDF(
        _ book: SeasonBook,
        to url: URL,
        image: (SeasonBookPage) -> UIImage?
    ) throws -> Int {
        guard let pageCount = book.printedPageCount else { throw PrintError.tooManyPages }
        let size = SeasonBookProduct.pageSize
        let bounds = CGRect(origin: .zero, size: size)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: book.name, kCGPDFContextCreator as String: "PitchMark"]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)

        var missing: String? = nil
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            drawTitlePage(book, in: bounds)
            for page in book.pages {
                guard let photo = image(page) else {
                    missing = page.slideId
                    break
                }
                context.beginPage()
                drawPhotoPage(photo, caption: page.caption, in: bounds)
            }
            for _ in book.contentPageCount..<pageCount where missing == nil {
                context.beginPage()
            }
        }
        if let missing { throw PrintError.missingImage(missing) }
        return pageCount
    }

    private static func drawTitlePage(_ book: SeasonBook, in bounds: CGRect) {
        UIColor.white.setFill()
        UIRectFill(bounds)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let inset = SeasonBookProduct.safeInset
        let title = NSAttributedString(string: book.name, attributes: [
            .font: UIFont.systemFont(ofSize: 34, weight: .bold),
            .foregroundColor: UIColor.black,
            .paragraphStyle: style
        ])
        let titleBox = bounds.insetBy(dx: inset, dy: 0)
        let height = title.boundingRect(with: CGSize(width: titleBox.width, height: .greatestFiniteMagnitude),
                                        options: [.usesLineFragmentOrigin], context: nil).height
        title.draw(with: CGRect(x: titleBox.minX, y: bounds.midY - height / 2, width: titleBox.width, height: height),
                   options: [.usesLineFragmentOrigin], context: nil)
    }

    private static func drawPhotoPage(_ photo: UIImage, caption: String, in bounds: CGRect) {
        UIColor.white.setFill()
        UIRectFill(bounds)
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let captionHeight: CGFloat = trimmedCaption.isEmpty ? 0 : 64
        // The photo fills the page edge to edge (into the bleed), above the
        // caption band.
        let photoArea = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - captionHeight)
        drawAspectFill(photo, in: photoArea)
        guard !trimmedCaption.isEmpty else { return }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: trimmedCaption, attributes: [
            .font: UIFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: UIColor.darkGray,
            .paragraphStyle: style
        ])
        let inset = SeasonBookProduct.safeInset
        text.draw(with: CGRect(x: inset, y: photoArea.maxY + 18, width: bounds.width - inset * 2, height: 40),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }

    private static func drawAspectFill(_ image: UIImage, in rect: CGRect) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        let origin = CGPoint(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2)
        UIGraphicsGetCurrentContext()?.saveGState()
        UIRectClip(rect)
        image.draw(in: CGRect(origin: origin, size: drawn))
        UIGraphicsGetCurrentContext()?.restoreGState()
    }

    /// A still at print size, read from this phone's Moments.
    static func printImage(for page: SeasonBookPage) -> UIImage? {
        switch page.slide {
        case .momentPhoto(let id, let index):
            guard let url = localMomentPhotoURL(momentId: id, index: index) else { return nil }
            return HomeSlideImages.downsampled(url, maxPixel: printPixels)
        case .momentFrame(let id):
            guard let url = localMomentVideoURL(for: id), FileManager.default.fileExists(atPath: url.path) else { return nil }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: printPixels, height: printPixels)
            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            return (try? generator.copyCGImage(at: time, actualTime: nil)).map { UIImage(cgImage: $0) }
        case .bundled, .none:
            return nil
        }
    }
}

// MARK: - Store

/// The account's books, live. Archived books are kept, never deleted.
@MainActor
final class SeasonBookStore: ObservableObject {
    @Published private(set) var books: [SeasonBook] = []
    private var listener: ListenerRegistration? = nil
    private var uid: String? = nil

    private static func collection(_ uid: String) -> CollectionReference {
        Firestore.firestore().collection("users").document(uid).collection("seasonBooks")
    }

    func start(uid: String?) {
        guard uid != self.uid else { return }
        listener?.remove()
        listener = nil
        self.uid = uid
        books = []
        guard let uid, !uid.isEmpty else { return }
        listener = Self.collection(uid).addSnapshotListener { [weak self] snapshot, _ in
            let loaded = (snapshot?.documents ?? [])
                .compactMap { SeasonBook(id: $0.documentID, data: $0.data()) }
                .filter { $0.archivedAt == nil }
                .sorted { $0.updatedAt > $1.updatedAt }
            Task { @MainActor in self?.books = loaded }
        }
    }

    func save(_ book: SeasonBook) {
        guard let uid else { return }
        var saved = book
        saved.updatedAt = Date()
        if let index = books.firstIndex(where: { $0.id == saved.id }) {
            books[index] = saved
        } else {
            books.insert(saved, at: 0)
        }
        Self.collection(uid).document(saved.id).setData(saved.firestoreData)
    }

    func archive(_ book: SeasonBook) {
        guard let uid else { return }
        books.removeAll { $0.id == book.id }
        Self.collection(uid).document(book.id).updateData(["archivedAt": Timestamp(date: Date())])
    }

    deinit { listener?.remove() }
}

// MARK: - Order

/// Uploads one book's PDF for its order, then asks the server for a Stripe
/// checkout. The server prices the book from `pageCount`; nothing here
/// sends a price.
enum SeasonBookOrder {
    static func makeOrderKey() -> String {
        "book_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
    }

    static func uploadPath(uid: String, orderKey: String) -> String {
        "bookUploads/\(uid)/\(orderKey)/interior.pdf"
    }

    static func checkoutPayload(book: SeasonBook, pageCount: Int, uploadPath: String, orderKey: String) -> [String: Any] {
        [
            "retailProductId": SeasonBookProduct.retailProductId,
            "itemKind": SeasonBookProduct.itemKind,
            "templateId": book.id,
            "templateName": book.name,
            "storeTemplateName": "Season Book",
            "templateSnapshotJson": "",
            "pageCount": pageCount,
            "uploadPath": uploadPath,
            "idempotencyKey": orderKey
        ]
    }

    /// Returns the Stripe checkout page to open.
    static func start(book: SeasonBook, pdfURL: URL, pageCount: Int,
                      progress: @escaping (Double) -> Void) async throws -> URL {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "SeasonBook", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sign in to order a book."])
        }
        let orderKey = makeOrderKey()
        let path = uploadPath(uid: uid, orderKey: orderKey)
        let metadata = StorageMetadata()
        metadata.contentType = "application/pdf"
        let reference = Storage.storage().reference(withPath: path)
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StorageMetadata, Error>) in
            let task = reference.putFile(from: pdfURL, metadata: metadata) { result in
                continuation.resume(with: result)
            }
            task.observe(.progress) { snapshot in
                let fraction = snapshot.progress?.fractionCompleted ?? 0
                DispatchQueue.main.async { progress(fraction) }
            }
        }
        let result = try await Functions.functions()
            .httpsCallable("createRetailCheckoutSession")
            .call(checkoutPayload(book: book, pageCount: pageCount, uploadPath: path, orderKey: orderKey))
        guard let data = result.data as? [String: Any],
              let urlString = data["checkoutUrl"] as? String,
              let url = URL(string: urlString) else {
            throw NSError(domain: "SeasonBook", code: 2, userInfo: [NSLocalizedDescriptionKey: "Checkout link was not returned."])
        }
        return url
    }
}
