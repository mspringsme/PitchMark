//
//  HomeSlideshow.swift
//  PitchMark
//
//  Home's slideshow (2026-11-18): fills the space under Home's collapsed
//  sections with stills - the coach's own Moments (their attached photos,
//  else a frame of the clip) mixed with stills shipped in the app.
//
//  What plays: every still has one ♥ (`HomeFavorites`). A clip's frame
//  and a photo Moment's picture use the Moment's own Favorite (the
//  library's ♥); any other photo - a still saved from a video, say - has
//  its own. Single stills can be hidden from Home.
//
//  Shipped stills: drop imagesets named `home-slide-01`, `home-slide-02`,
//  ... into `Assets 2.xcassets/Home Slideshow/`. They're found by name,
//  in order, until the first missing number - adding one needs no code.
//
//  Its own view with its own state, so Home's type doesn't grow (see
//  CLAUDE.md, "Home (SettingsView) has its own depth limit").
//

import SwiftUI
import ImageIO
import UIKit
import FirebaseFirestore
import FirebaseAuth
import Combine

/// One still in the slideshow.
enum HomeSlide: Hashable, Identifiable {
    /// A photo attached to a Moment.
    case momentPhoto(momentId: String, index: Int)
    /// A frame of a Moment's video (Moments with no photo).
    case momentFrame(momentId: String)
    /// A still shipped in the app's asset catalog.
    case bundled(name: String)

    var id: String {
        switch self {
        case .momentPhoto(let id, let index): return "p-\(id)-\(index)"
        case .momentFrame(let id): return "f-\(id)"
        case .bundled(let name): return "b-\(name)"
        }
    }

    /// The slide an `id` names (hidden stills are saved as ids).
    init?(id: String) {
        if id.hasPrefix("b-") {
            let name = String(id.dropFirst(2))
            guard !name.isEmpty else { return nil }
            self = .bundled(name: name)
        } else if id.hasPrefix("f-") {
            let momentId = String(id.dropFirst(2))
            guard !momentId.isEmpty else { return nil }
            self = .momentFrame(momentId: momentId)
        } else if id.hasPrefix("p-") {
            let rest = id.dropFirst(2)
            guard let dash = rest.lastIndex(of: "-"),
                  let index = Int(rest[rest.index(after: dash)...]), index >= 0 else { return nil }
            let momentId = String(rest[..<dash])
            guard !momentId.isEmpty else { return nil }
            self = .momentPhoto(momentId: momentId, index: index)
        } else {
            return nil
        }
    }

    var momentId: String? {
        switch self {
        case .momentPhoto(let id, _), .momentFrame(let id): return id
        case .bundled: return nil
        }
    }
}

/// What the slideshow plays, in order. Plain rules, kept out of the view.
enum HomeSlideshowPlaylist {
    /// Most Moment stills picked automatically (newest first).
    static let maxMomentSlides = 24
    /// Photos taken from any one Moment when picking automatically, so one
    /// big photo set doesn't crowd out the rest.
    static let maxPhotosPerMoment = 3
    /// Most stills from favorite Moments.
    static let maxFavoriteSlides = 60
    /// A shipped still after every this many Moment stills.
    static let bundledEvery = 3

    /// - Parameters:
    ///   - moments: newest first (`loadMoments` order).
    ///   - photoExists: whether photo `index` of a Moment is on this device.
    ///   - videoExists: whether a Moment's video is on this device.
    ///   - bundled: shipped still names, in order.
    ///   - prefs: the coach's hidden stills.
    ///
    /// Hidden stills never play. When any ♥ still can play, the Moment
    /// part is the ♥ stills (newest Moment first); otherwise it's the newest Moments,
    /// up to `maxPhotosPerMoment` each. Shipped stills go between, one
    /// after every `bundledEvery`.
    static func build(
        moments: [Moment],
        photoExists: (String, Int) -> Bool,
        videoExists: (String) -> Bool,
        bundled: [String],
        prefs: HomeSlideshowPrefs = HomeSlideshowPrefs()
    ) -> [HomeSlide] {
        let hidden = Set(prefs.hidden)
        let favoriteSlides = Array(favoriteStills(moments: moments, prefs: prefs,
                                                  photoExists: photoExists, videoExists: videoExists)
            .filter { !hidden.contains($0.id) }
            .prefix(maxFavoriteSlides))
        let mainSlides = favoriteSlides.isEmpty
            ? stills(of: moments, perMoment: maxPhotosPerMoment, limit: maxMomentSlides,
                     hidden: hidden, photoExists: photoExists, videoExists: videoExists)
            : favoriteSlides
        let bundledSlides = bundled
            .map { HomeSlide.bundled(name: $0) }
            .filter { !hidden.contains($0.id) }
        return interleave(mainSlides, bundledSlides)
    }

    /// Each Moment's photos on this device (up to `perMoment`), or a frame
    /// of its clip when it has none; hidden ones left out.
    static func stills(
        of moments: [Moment],
        perMoment: Int,
        limit: Int,
        hidden: Set<String>,
        photoExists: (String, Int) -> Bool,
        videoExists: (String) -> Bool
    ) -> [HomeSlide] {
        var picked: [HomeSlide] = []
        for moment in moments {
            guard picked.count < limit, let id = moment.id, !id.isEmpty else { continue }
            let onDevice = (0..<max(moment.photoCount ?? 0, 0)).filter { photoExists(id, $0) }
            if onDevice.isEmpty {
                let frame = HomeSlide.momentFrame(momentId: id)
                if videoExists(id), !hidden.contains(frame.id) { picked.append(frame) }
                continue
            }
            let shown = onDevice
                .filter { !hidden.contains(HomeSlide.momentPhoto(momentId: id, index: $0).id) }
                .prefix(perMoment)
            for index in shown where picked.count < limit {
                picked.append(.momentPhoto(momentId: id, index: index))
            }
        }
        return picked
    }

    /// Every ♥ still on this device, newest Moment first: a favorite
    /// Moment's own still (a photo Moment's picture, else its clip's
    /// frame), then that Moment's ♥ photos.
    static func favoriteStills(
        moments: [Moment],
        prefs: HomeSlideshowPrefs,
        photoExists: (String, Int) -> Bool,
        videoExists: (String) -> Bool
    ) -> [HomeSlide] {
        var result: [HomeSlide] = []
        for moment in moments {
            guard let id = moment.id, !id.isEmpty else { continue }
            let own = HomeFavorites.momentStill(moment)
            if moment.isFavorite == true {
                switch own {
                case .momentPhoto(_, let index) where photoExists(id, index): result.append(own)
                case .momentFrame where videoExists(id): result.append(own)
                default: break
                }
            }
            for index in 0..<max(moment.photoCount ?? 0, 0) {
                let photo = HomeSlide.momentPhoto(momentId: id, index: index)
                guard photo != own, prefs.isFavoritePhoto(photo.id), photoExists(id, index) else { continue }
                result.append(photo)
            }
        }
        return result
    }

    /// A shipped still after every `bundledEvery` main stills; any left
    /// over go at the end.
    static func interleave(_ main: [HomeSlide], _ bundled: [HomeSlide]) -> [HomeSlide] {
        guard !main.isEmpty else { return bundled }
        guard !bundled.isEmpty else { return main }
        var result: [HomeSlide] = []
        var nextBundled = 0
        for (offset, slide) in main.enumerated() {
            result.append(slide)
            if (offset + 1) % bundledEvery == 0, nextBundled < bundled.count {
                result.append(bundled[nextBundled])
                nextBundled += 1
            }
        }
        result.append(contentsOf: bundled[nextBundled...])
        return result
    }

    /// Every still the coach could pick from (the Manage screen): each
    /// Moment's own still (a clip's frame, or a photo Moment's picture),
    /// then its other photos on this device; then the shipped stills.
    static func allStills(
        moments: [Moment],
        photoExists: (String, Int) -> Bool,
        videoExists: (String) -> Bool,
        bundled: [String]
    ) -> [HomeSlide] {
        var result: [HomeSlide] = []
        for moment in moments {
            guard let id = moment.id, !id.isEmpty else { continue }
            let own = HomeFavorites.momentStill(moment)
            if case .momentFrame = own, videoExists(id) { result.append(own) }
            for index in 0..<max(moment.photoCount ?? 0, 0) where photoExists(id, index) {
                result.append(.momentPhoto(momentId: id, index: index))
            }
        }
        return result + bundled.map { .bundled(name: $0) }
    }
}

/// The coach's ♥ photos and stills hidden from Home, saved as slide ids.
/// A still is ♥ or hidden, never both - the latest choice wins.
struct HomeSlideshowPrefs: Equatable {
    var hidden: [String] = []
    /// Photos with their own ♥ (`HomeFavorites`); newest first.
    var favoritePhotos: [String] = []

    func isHidden(_ id: String) -> Bool { hidden.contains(id) }
    func isFavoritePhoto(_ id: String) -> Bool { favoritePhotos.contains(id) }

    mutating func setHidden(_ id: String, _ on: Bool) {
        hidden.removeAll { $0 == id }
        if on {
            hidden.append(id)
            favoritePhotos.removeAll { $0 == id }
        }
    }

    mutating func setFavoritePhoto(_ id: String, _ on: Bool) {
        favoritePhotos.removeAll { $0 == id }
        if on {
            favoritePhotos.insert(id, at: 0)
            hidden.removeAll { $0 == id }
        }
    }

    /// After photo `index` is removed from a Moment, its later photos
    /// move down one - so do their saved ids. The removed one's go.
    mutating func removingPhoto(momentId: String, index: Int) {
        func remap(_ ids: [String]) -> [String] {
            var seen = Set<String>()
            return ids.compactMap { id -> String? in
                guard case .momentPhoto(let mid, let i)? = HomeSlide(id: id), mid == momentId else { return id }
                if i == index { return nil }
                return HomeSlide.momentPhoto(momentId: mid, index: i > index ? i - 1 : i).id
            }.filter { seen.insert($0).inserted }
        }
        hidden = remap(hidden)
        favoritePhotos = remap(favoritePhotos)
    }

    /// Every still a Moment can show: each photo, and its clip's frame.
    static func stillIds(momentId: String, photoCount: Int) -> [String] {
        (0..<max(photoCount, 0)).map { HomeSlide.momentPhoto(momentId: momentId, index: $0).id }
            + [HomeSlide.momentFrame(momentId: momentId).id]
    }

    /// Every one of the Moment's stills is hidden.
    func isMomentHidden(momentId: String, photoCount: Int) -> Bool {
        Self.stillIds(momentId: momentId, photoCount: photoCount).allSatisfy { isHidden($0) }
    }

    /// Hides (or shows) all of the Moment's stills.
    mutating func setMomentHidden(momentId: String, photoCount: Int, _ on: Bool) {
        for id in Self.stillIds(momentId: momentId, photoCount: photoCount) { setHidden(id, on) }
    }

    init(hidden: [String] = [], favoritePhotos: [String] = []) {
        self.hidden = hidden
        self.favoritePhotos = favoritePhotos
    }

    init(firestoreData data: [String: Any]) {
        hidden = data["hidden"] as? [String] ?? []
        favoritePhotos = data["favoritePhotos"] as? [String] ?? []
    }

    var firestoreData: [String: Any] {
        ["hidden": hidden, "favoritePhotos": favoritePhotos]
    }
}

/// Hidden stills, kept on the account (`users/{uid}/meta/homeSlideshow`,
/// the meta rule) so they follow the coach to another phone.
final class HomeSlideshowPrefsStore: ObservableObject {
    static let shared = HomeSlideshowPrefsStore()

    @Published private(set) var prefs = HomeSlideshowPrefs()

    private var uid: String? = nil
    private var listener: ListenerRegistration? = nil

    /// Safe to call often; only a new account restarts the listener.
    func start(uid: String?) {
        guard uid != self.uid else { return }
        listener?.remove()
        listener = nil
        self.uid = uid
        prefs = HomeSlideshowPrefs()
        guard let uid, !uid.isEmpty else { return }
        listener = document(uid).addSnapshotListener { [weak self] snapshot, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    debugLog("❌ homeSlideshow listener:", error.localizedDescription)
                    return
                }
                self.prefs = HomeSlideshowPrefs(firestoreData: snapshot?.data() ?? [:])
            }
        }
    }

    /// Starts on the signed-in account if nothing has yet (a Moment's
    /// screen can be used before Home ever appears).
    func ensureStarted() {
        if uid == nil { start(uid: Auth.auth().currentUser?.uid) }
    }

    func setHidden(_ slide: HomeSlide, _ on: Bool) {
        prefs.setHidden(slide.id, on)
        save()
    }

    func setFavoritePhoto(_ slide: HomeSlide, _ on: Bool) {
        prefs.setFavoritePhoto(slide.id, on)
        save()
    }

    func setMomentHidden(momentId: String, photoCount: Int, _ on: Bool) {
        prefs.setMomentHidden(momentId: momentId, photoCount: photoCount, on)
        save()
    }

    func photoRemoved(momentId: String, index: Int) {
        let before = prefs
        prefs.removingPhoto(momentId: momentId, index: index)
        if prefs != before { save() }
    }

    private func save() {
        ensureStarted()
        guard let uid else { return }
        document(uid).setData(prefs.firestoreData) { error in
            if let error { debugLog("❌ homeSlideshow save:", error.localizedDescription) }
        }
    }

    private func document(_ uid: String) -> DocumentReference {
        Firestore.firestore().collection("users").document(uid).collection("meta").document("homeSlideshow")
    }
}

/// A Moment's Favorite (♥) from anywhere outside its own screen - saved,
/// and the shared index updated at once so Home doesn't wait on a reload.
enum MomentFavorite {
    static func set(momentId: String, _ on: Bool, authManager: AuthManager) {
        PlayerMomentsIndex.shared.setFavorite(momentId: momentId, on)
        authManager.updateMomentFields(momentId: momentId, fields: ["isFavorite": on]) { _ in }
    }
}

/// Which ♥ a still's heart is. Each still has exactly one: a clip's frame
/// and a photo Moment's picture (photo 1) are the Moment's own Favorite;
/// every other photo has its own, saved in `HomeSlideshowPrefs`.
enum HomeFavorites {
    /// The still that stands for the Moment itself.
    static func momentStill(_ moment: Moment) -> HomeSlide {
        let id = moment.id ?? ""
        return moment.momentKind == .photoCreation
            ? .momentPhoto(momentId: id, index: 0)
            : .momentFrame(momentId: id)
    }

    /// True when the still's heart is the Moment's Favorite.
    static func usesMomentFavorite(_ slide: HomeSlide, moment: Moment?) -> Bool {
        switch slide {
        case .momentFrame: return true
        case .momentPhoto(_, let index): return index == 0 && moment?.momentKind == .photoCreation
        case .bundled: return false
        }
    }

    static func isFavorite(_ slide: HomeSlide, moments: [Moment], prefs: HomeSlideshowPrefs) -> Bool {
        guard let id = slide.momentId else { return false }
        let moment = moments.first { $0.id == id }
        return usesMomentFavorite(slide, moment: moment)
            ? moment?.isFavorite == true
            : prefs.isFavoritePhoto(slide.id)
    }

    static func set(_ slide: HomeSlide, _ on: Bool, moments: [Moment], authManager: AuthManager) {
        guard let id = slide.momentId else { return }
        let store = HomeSlideshowPrefsStore.shared
        store.ensureStarted()
        if usesMomentFavorite(slide, moment: moments.first { $0.id == id }) {
            MomentFavorite.set(momentId: id, on, authManager: authManager)
            if on, store.prefs.isHidden(slide.id) { store.setHidden(slide, false) }
        } else {
            store.setFavoritePhoto(slide, on)
        }
    }
}

/// The shipped stills, found by name in the asset catalog.
enum HomeSlideshowStills {
    static let namePrefix = "home-slide-"
    static let maxCount = 99

    static func name(_ number: Int) -> String {
        namePrefix + String(format: "%02d", number)
    }

    /// `home-slide-01`, `-02`, ... up to the first missing number.
    static let names: [String] = {
        var found: [String] = []
        for number in 1...maxCount {
            let candidate = name(number)
            guard UIImage(named: candidate) != nil else { break }
            found.append(candidate)
        }
        return found
    }()
}

/// Loads (and caches) a slide's image, shrunk for display.
enum HomeSlideImages {
    private static let cache = NSCache<NSString, UIImage>()
    private static let maxPixel: CGFloat = 1200

    /// Photo numbers shift when one is removed, and an edit changes a
    /// photo in place; drop what's cached.
    static func forgetAll() { cache.removeAllObjects() }

    static func cached(_ slide: HomeSlide) -> UIImage? {
        if case .bundled(let name) = slide { return UIImage(named: name) }
        return cache.object(forKey: slide.id as NSString)
    }

    static func load(_ slide: HomeSlide, completion: @escaping (UIImage?) -> Void) {
        if let image = cached(slide) {
            completion(image)
            return
        }
        switch slide {
        case .bundled(let name):
            completion(UIImage(named: name))
        case .momentPhoto(let id, let index):
            guard let url = localMomentPhotoURL(momentId: id, index: index) else {
                completion(nil)
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let image = downsampled(url, maxPixel: maxPixel)
                if let image { cache.setObject(image, forKey: slide.id as NSString) }
                DispatchQueue.main.async { completion(image) }
            }
        case .momentFrame(let id):
            // `momentThumbnail` already caches by the video's mtime.
            var moment = Moment()
            moment.id = id
            momentThumbnail(for: moment) { completion($0) }
        }
    }

    static func downsampled(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Whether a Moment's files are on this device.
enum HomeSlideFiles {
    static func photoExists(_ momentId: String, _ index: Int) -> Bool {
        localMomentPhotoURL(momentId: momentId, index: index)
            .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    static func videoExists(_ momentId: String) -> Bool {
        momentVideoExistsLocally(for: momentId)
    }
}

/// A small round icon toggle drawn on a photo (♥ favorite, eye hidden).
struct PhotoCornerToggle: View {
    let systemImage: String
    var tint: Color = .white
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.black.opacity(0.5)))
                // A finger-sized target around the small circle.
                .padding(5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Home's slideshow card. Swipe to move; it advances by itself every few
/// seconds while Home is on screen. Tapping a Moment's still plays it;
/// the ♥ in its corner favorites the Moment; a long press can hide it.
/// The corner button opens Manage.
struct HomeSlideshowView: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject private var index = PlayerMomentsIndex.shared
    @ObservedObject private var store = HomeSlideshowPrefsStore.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: String = ""
    @State private var isVisible = false
    @State private var playingMomentId: String? = nil
    @State private var showManage = false

    static let advanceSeconds: UInt64 = 5

    private var slides: [HomeSlide] {
        HomeSlideshowPlaylist.build(
            moments: index.moments,
            photoExists: HomeSlideFiles.photoExists,
            videoExists: HomeSlideFiles.videoExists,
            bundled: HomeSlideshowStills.names,
            prefs: store.prefs
        )
    }

    var body: some View {
        let slides = self.slides
        Group {
            if slides.isEmpty {
                emptyCard
            } else {
                carousel(slides)
            }
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .overlay(alignment: .topTrailing) { manageButton }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .padding(.horizontal)
        .onAppear {
            isVisible = true
            store.start(uid: authManager.user?.uid)
        }
        .onDisappear { isVisible = false }
        .task(id: AdvanceKey(running: isVisible && scenePhase == .active && slides.count > 1 && !showManage,
                             selection: selection)) {
            guard isVisible, scenePhase == .active, slides.count > 1, !showManage else { return }
            try? await Task.sleep(nanoseconds: Self.advanceSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            advance(in: slides)
        }
        .fullScreenCover(isPresented: Binding(
            get: { playingMomentId != nil },
            set: { if !$0 { playingMomentId = nil } }
        )) {
            if let id = playingMomentId, let url = resolvedMomentPlaybackURL(for: id) {
                MomentPlaybackView(videoURL: url)
            }
        }
        .appSheet(isPresented: $showManage) {
            HomeSlideshowManageView { showManage = false }
                .environmentObject(authManager)
        }
        .accessibilityIdentifier("home.slideshow")
    }

    private var manageButton: some View {
        Button {
            showManage = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
        .buttonStyle(.plain)
        .padding(10)
        .accessibilityLabel("Manage Slideshow")
        .accessibilityIdentifier("home.slideshow.manage")
    }

    /// Restarts the timer whenever the slide changes (a swipe included),
    /// so a swipe always gets a full look before the next advance.
    private struct AdvanceKey: Equatable {
        let running: Bool
        let selection: String
    }

    private func advance(in slides: [HomeSlide]) {
        let ids = slides.map(\.id)
        let next: String
        if let current = ids.firstIndex(of: selection) {
            next = ids[(current + 1) % ids.count]
        } else {
            next = ids.first ?? ""
        }
        withAnimation(.easeInOut(duration: 0.6)) { selection = next }
    }

    private func isFavorite(_ slide: HomeSlide) -> Bool {
        HomeFavorites.isFavorite(slide, moments: index.moments, prefs: store.prefs)
    }

    private func carousel(_ slides: [HomeSlide]) -> some View {
        TabView(selection: $selection) {
            ForEach(slides) { slide in
                HomeSlideTile(slide: slide) {
                    guard let id = slide.momentId, momentVideoExistsLocally(for: id) else { return }
                    playingMomentId = id
                }
                .overlay(alignment: .topLeading) {
                    if slide.momentId != nil {
                        let on = isFavorite(slide)
                        PhotoCornerToggle(systemImage: on ? "heart.fill" : "heart",
                                          tint: on ? .red : .white,
                                          label: on ? "Unfavorite" : "Favorite") {
                            HomeFavorites.set(slide, !on, moments: index.moments, authManager: authManager)
                        }
                        .padding(5)
                    }
                }
                .contextMenu { slideMenu(slide) }
                .tag(slide.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: slides.count > 1 ? .automatic : .never))
        .background(Color.black)
        .onAppear {
            if !slides.contains(where: { $0.id == selection }) {
                selection = slides.first?.id ?? ""
            }
        }
        .onChange(of: slides.map(\.id)) { ids in
            if !ids.contains(selection) { selection = ids.first ?? "" }
        }
    }

    @ViewBuilder
    private func slideMenu(_ slide: HomeSlide) -> some View {
        Button {
            store.setHidden(slide, true)
        } label: {
            Label("Hide from Home", systemImage: "eye.slash")
        }
        Button {
            showManage = true
        } label: {
            Label("Manage Slideshow…", systemImage: "slider.horizontal.3")
        }
    }

    private var emptyCard: some View {
        ZStack {
            Color(.secondarySystemBackground)
            VStack(spacing: 10) {
                Image("SoftballAndBaseball")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 90)
                    .accessibilityHidden(true)
                Text("Your Moments show up here")
                    .font(.headline)
                Text(store.prefs.hidden.isEmpty
                     ? "Capture a Moment and its photos play here on Home."
                     : "Every still is hidden. Tap the button in the corner to show some again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

/// Favorite Moments and hidden stills, all in one place.
struct HomeSlideshowManageView: View {
    let onClose: () -> Void

    @EnvironmentObject var authManager: AuthManager
    @ObservedObject private var index = PlayerMomentsIndex.shared
    @ObservedObject private var store = HomeSlideshowPrefsStore.shared

    enum Tab: String, CaseIterable, Identifiable {
        case all = "All Stills"
        case favorites = "Favorites"
        case hidden = "Hidden"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .all

    private var allStills: [HomeSlide] {
        HomeSlideshowPlaylist.allStills(
            moments: index.moments,
            photoExists: HomeSlideFiles.photoExists,
            videoExists: HomeSlideFiles.videoExists,
            bundled: HomeSlideshowStills.names
        )
    }

    private func isFavorite(_ slide: HomeSlide) -> Bool {
        HomeFavorites.isFavorite(slide, moments: index.moments, prefs: store.prefs)
    }

    private var shown: [HomeSlide] {
        let all = allStills
        switch tab {
        case .all: return all
        case .favorites: return all.filter { isFavorite($0) }
        case .hidden: return all.filter { store.prefs.isHidden($0.id) }
        }
    }

    private var hasFavorites: Bool { allStills.contains { isFavorite($0) } }

    private var explanation: String {
        switch tab {
        case .all:
            return hasFavorites
                ? "Home plays your ♥ stills, plus PitchMark's own. The eye hides a still."
                : "Home plays your newest Moments. Tap ♥ on stills to pick them instead; the eye hides a still."
        case .favorites:
            return "These play on Home. A clip's frame shares its Moment's ♥. Unheart them all to go back to your newest Moments."
        case .hidden:
            return "These never show on Home. Tap the eye to show one again."
        }
    }

    var body: some View {
        let stills = shown
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Show", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("slideshowManage.tab")

                    Text(explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if stills.isEmpty {
                        Text(emptyText)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                            ForEach(stills) { slide in
                                HomeSlideManageTile(
                                    slide: slide,
                                    isFavorite: isFavorite(slide),
                                    isHidden: store.prefs.isHidden(slide.id),
                                    onFavorite: {
                                        HomeFavorites.set(slide, !isFavorite(slide), moments: index.moments, authManager: authManager)
                                    },
                                    onHide: { store.setHidden(slide, !store.prefs.isHidden(slide.id)) }
                                )
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Home Slideshow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onClose)
                }
            }
        }
        .onAppear {
            store.ensureStarted()
            PlayerMomentsIndex.shared.refresh(authManager)
        }
    }

    private var emptyText: String {
        switch tab {
        case .all: return "No stills on this phone yet."
        case .favorites: return "No ♥ stills yet."
        case .hidden: return "Nothing hidden."
        }
    }
}

private struct HomeSlideManageTile: View {
    let slide: HomeSlide
    let isFavorite: Bool
    let isHidden: Bool
    let onFavorite: () -> Void
    let onHide: () -> Void

    @State private var image: UIImage? = nil

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .allowsHitTesting(false)
            } else {
                ProgressView()
            }
        }
        .frame(height: 104)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(isHidden ? 0.4 : 1)
        .overlay(alignment: .topLeading) {
            if slide.momentId != nil {
                PhotoCornerToggle(systemImage: isFavorite ? "heart.fill" : "heart",
                                  tint: isFavorite ? .red : .white,
                                  label: isFavorite ? "Unfavorite" : "Favorite",
                                  action: onFavorite)
            } else {
                Text("PitchMark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
                    .padding(6)
            }
        }
        .overlay(alignment: .topTrailing) {
            PhotoCornerToggle(systemImage: isHidden ? "eye.slash.fill" : "eye",
                              label: isHidden ? "Show on Home" : "Hide from Home",
                              action: onHide)
        }
        .onAppear {
            if image == nil { image = HomeSlideImages.cached(slide) }
            guard image == nil else { return }
            HomeSlideImages.load(slide) { image = $0 }
        }
    }
}

private struct HomeSlideTile: View {
    let slide: HomeSlide
    let onTap: () -> Void

    @State private var image: UIImage? = nil

    var body: some View {
        ZStack {
            Color.black
            if let image {
                // Fill the card, with the whole still behind it blurred so a
                // portrait photo doesn't leave black bars.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 24)
                    .opacity(0.6)
                    .allowsHitTesting(false)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .allowsHitTesting(false)
            } else {
                ProgressView().tint(.white)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement()
        .accessibilityLabel(slide.momentId == nil ? "PitchMark photo" : "Moment")
        .accessibilityAddTraits(slide.momentId == nil ? .isImage : [.isImage, .isButton])
        .onAppear {
            if image == nil { image = HomeSlideImages.cached(slide) }
            guard image == nil else { return }
            HomeSlideImages.load(slide) { image = $0 }
        }
    }
}
