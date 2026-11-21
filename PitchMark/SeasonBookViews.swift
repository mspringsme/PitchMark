//
//  SeasonBookViews.swift
//  PitchMark
//
//  Season Book screens (2026-11-19), reached from Team Supplies. Rules,
//  print and order code live in SeasonBook.swift.
//

import SwiftUI
import UIKit
import FirebaseAuth

/// The account's books, and New Book.
struct SeasonBooksView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var store = SeasonBookStore()
    @ObservedObject private var momentsIndex = PlayerMomentsIndex.shared
    @ObservedObject private var prefsStore = HomeSlideshowPrefsStore.shared
    @State private var editing: SeasonBook? = nil
    @State private var archiving: SeasonBook? = nil
    @State private var showArchiveDialog = false

    var body: some View {
        List {
            Section {
                Text("A printed hardcover of your Moments: favorites first, your captions, one photo a page. Your photos stay on this phone until you order.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    editing = newBook()
                } label: {
                    Label("New Season Book", systemImage: "book.closed")
                }
                .accessibilityIdentifier("seasonBook.new")
            }

            if !store.books.isEmpty {
                Section("Your Books") {
                    ForEach(store.books) { book in
                        Button {
                            editing = book
                        } label: {
                            SeasonBookRow(book: book)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Archive") {
                                archiving = book
                                showArchiveDialog = true
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Season Books")
        .onAppear {
            store.start(uid: authManager.user?.uid)
            prefsStore.start(uid: authManager.user?.uid)
            momentsIndex.refresh(authManager)
        }
        .appSheet(item: $editing, chrome: .handle) { book in
            NavigationStack {
                SeasonBookEditorView(book: book, store: store)
            }
            .fixedAppDynamicType()
        }
        .appConfirmationDialog(
            isPresented: $showArchiveDialog,
            title: "Archive this book?",
            message: "It leaves this list. Nothing is ordered or printed.",
            primaryTitle: "Archive",
            primaryAction: {
                if let archiving { store.archive(archiving) }
                archiving = nil
            },
            secondaryTitle: "Cancel",
            secondaryAction: { archiving = nil }
        )
    }

    private func newBook() -> SeasonBook {
        let year = Calendar.current.component(.year, from: Date())
        let pages = SeasonBookSuggestion.pages(
            moments: momentsIndex.moments,
            prefs: prefsStore.prefs,
            photoExists: HomeSlideFiles.photoExists,
            videoExists: HomeSlideFiles.videoExists
        )
        return SeasonBook(name: "\(year) Season", pages: pages)
    }
}

private struct SeasonBookRow: View {
    let book: SeasonBook

    var body: some View {
        HStack(spacing: 12) {
            SeasonBookThumbnail(slideId: book.pages.first?.slideId)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.name).font(.headline)
                Text("\(book.pages.count) photos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let cents = book.priceCents {
                Text(Decimal(cents) / 100, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.semibold))
            }
        }
        .contentShape(Rectangle())
    }
}

/// A still from this phone's Moments, square-cropped.
struct SeasonBookThumbnail: View {
    let slideId: String?
    @State private var image: UIImage? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.15))
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .allowsHitTesting(false)
            .task(id: slideId) {
                guard let slideId, let slide = HomeSlide(id: slideId) else { image = nil; return }
                HomeSlideImages.load(slide) { image = $0 }
            }
    }
}

struct SeasonBookEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State var book: SeasonBook
    let store: SeasonBookStore
    @ObservedObject private var momentsIndex = PlayerMomentsIndex.shared
    @State private var showAddPhotos = false
    @State private var isOrdering = false
    @State private var orderStatus = ""
    @State private var orderError: String? = nil
    @State private var showOrderError = false

    var body: some View {
        List {
            Section {
                TextField("Book title", text: $book.name)
                    .onChange(of: book.name) { _, new in
                        if new.count > SeasonBook.nameMax { book.name = String(new.prefix(SeasonBook.nameMax)) }
                    }
                    .accessibilityIdentifier("seasonBook.name")
                summary
            }

            Section {
                ForEach($book.pages) { $page in
                    HStack(alignment: .top, spacing: 12) {
                        SeasonBookThumbnail(slideId: page.slideId)
                            .frame(width: 72, height: 72)
                        TextField("Caption (optional)", text: $page.caption, axis: .vertical)
                            .lineLimit(1...3)
                            .onChange(of: page.caption) { _, new in
                                if new.count > SeasonBookPage.captionMax {
                                    page.caption = String(new.prefix(SeasonBookPage.captionMax))
                                }
                            }
                    }
                }
                .onMove { book.pages.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { book.pages.remove(atOffsets: $0) }

                Button {
                    showAddPhotos = true
                } label: {
                    Label("Add Photos", systemImage: "plus")
                }
            } header: {
                Text("Pages (drag to reorder, swipe to remove)")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Season Book")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    store.save(book)
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Order") { order() }
                    .disabled(book.printedPageCount == nil || book.pages.isEmpty || isOrdering)
                    .accessibilityIdentifier("seasonBook.order")
            }
        }
        .appSheet(isPresented: $showAddPhotos, chrome: .handle) {
            SeasonBookAddPhotosView(alreadyIn: Set(book.pages.map(\.slideId))) { added in
                book.pages.append(contentsOf: added.map { SeasonBookPage(slideId: $0) })
            }
            .fixedAppDynamicType()
        }
        .overlay {
            if isOrdering {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text(orderStatus).foregroundStyle(.white).font(.subheadline)
                    }
                }
            }
        }
        .appConfirmationDialog(
            isPresented: $showOrderError,
            title: "Couldn't start the order",
            message: orderError ?? "",
            primaryTitle: "OK",
            primaryAction: {},
            secondaryTitle: "Close"
        )
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let printed = book.printedPageCount, let cents = book.priceCents {
                Text("\(book.pages.count) photos · \(printed) printed pages")
                    .font(.subheadline)
                Text(Decimal(cents) / 100, format: .currency(code: "USD"))
                    .font(.headline)
                if book.contentPageCount < SeasonBookProduct.minPages {
                    Text("Books start at \(SeasonBookProduct.minPages) pages; the rest print blank. Add photos to fill them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("A book holds up to \(SeasonBookProduct.maxPages - 1) photos. Remove some to order.")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
    }

    private func order() {
        store.save(book)
        let snapshot = book
        isOrdering = true
        orderStatus = "Making your book…"
        Task {
            do {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("season-book-\(snapshot.id).pdf")
                let pageCount = try await Task.detached(priority: .userInitiated) {
                    try SeasonBookPrint.writePDF(snapshot, to: url, image: SeasonBookPrint.printImage(for:))
                }.value
                orderStatus = "Uploading…"
                let checkout = try await SeasonBookOrder.start(book: snapshot, pdfURL: url, pageCount: pageCount) { fraction in
                    orderStatus = "Uploading… \(Int(fraction * 100))%"
                }
                try? FileManager.default.removeItem(at: url)
                isOrdering = false
                openURL(checkout)
            } catch {
                isOrdering = false
                orderError = error.localizedDescription
                showOrderError = true
            }
        }
    }
}

/// Every still on this phone not already in the book.
private struct SeasonBookAddPhotosView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var momentsIndex = PlayerMomentsIndex.shared
    @ObservedObject private var prefsStore = HomeSlideshowPrefsStore.shared
    let alreadyIn: Set<String>
    let onAdd: ([String]) -> Void
    @State private var picked: [String] = []

    private var candidates: [String] {
        let hidden = Set(prefsStore.prefs.hidden)
        return HomeSlideshowPlaylist.allStills(
            moments: momentsIndex.moments,
            photoExists: HomeSlideFiles.photoExists,
            videoExists: HomeSlideFiles.videoExists,
            bundled: []
        )
        .map(\.id)
        .filter { !alreadyIn.contains($0) && !hidden.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(candidates, id: \.self) { id in
                        Button {
                            if let index = picked.firstIndex(of: id) { picked.remove(at: index) } else { picked.append(id) }
                        } label: {
                            SeasonBookThumbnail(slideId: id)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(alignment: .topTrailing) {
                                    if picked.contains(id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.white, Color.pitchMarkActiveGray)
                                            .padding(4)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                if candidates.isEmpty {
                    Text("Every photo on this phone is already in the book.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .navigationTitle("Add Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(picked.count)") {
                        onAdd(picked)
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                }
            }
        }
    }
}
