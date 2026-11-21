//
//  MomentGridView.swift
//  PitchMark
//
//  2026-10-04: the shared thumbnail-grid rendering used by MomentsLibraryView's
//  "All" tab and by every Folder/Bucket detail screen (MomentFoldersView,
//  MomentFolderDetailView, MomentBucketDetailView) - built as one shared
//  view from the start specifically so those don't copy-paste it.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI

/// Which relative time bucket `date` falls into, relative to `now`. Pure,
/// no AVFoundation/Firestore dependency - standalone-verifiable the same
/// way every other pure timing function in this app is (CLAUDE.md's
/// verification-constraints section).
func timeSectionTitle(for date: Date, now: Date) -> String {
    let calendar = Calendar.current
    // `Calendar.isDateInToday` always compares against the real wall
    // clock, ignoring `now` entirely - confirmed via the standalone
    // verification script (a fictitious `now` still got bucketed against
    // today's real date). `isDate(_:inSameDayAs:)` actually respects the
    // `now` passed in, which is what makes this function genuinely pure
    // and testable; in production `now` is always `Date()` anyway, so
    // this is a correctness fix with no behavior change there.
    if calendar.isDate(date, inSameDayAs: now) { return "Today" }
    if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date >= weekAgo { return "This Week" }
    if let monthAgo = calendar.date(byAdding: .day, value: -30, to: now), date >= monthAgo { return "This Month" }
    return "Older"
}

/// Plain `.video` (including nil, the legacy default) gets the original
/// play-button icon; `.mixedCreation`/`.photoCreation` get a distinct one
/// so the kind is visible at a glance, ahead of any further taxonomy UI.
func momentKindIconName(_ moment: Moment) -> String {
    switch moment.momentKind {
    case .photoCreation: return "photo.on.rectangle.angled"
    case .mixedCreation: return "photo.stack"
    case .video, nil: return "play.circle.fill"
    }
}

func formattedMomentDuration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}

/// The time-range options the grid's header capsule lets you jump to. A
/// `nil` selection (not a case here) means "no filter" - show every bucket
/// stacked, same as the grid's original always-on behavior.
enum MomentTimeFilter: String, CaseIterable, Identifiable {
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case older = "Older"
    var id: String { rawValue }
}

/// A scrolling thumbnail grid of `moments`, sectioned under sticky
/// relative-time headers. `moments` is expected pre-sorted newest-first
/// (as `loadMoments` already returns it) - sections fall out of that
/// order for free, since a time-sorted array is already section-
/// contiguous for any subset of it.
struct MomentGridView: View {
    let moments: [Moment]
    var isSelecting: Bool = false
    var selectedMomentIds: Set<String> = []
    var emptyMessage: String = "No Moments yet."
    let onTap: (Moment) -> Void

    /// The library's long-press actions (MomentActions.swift); nil = none.
    @Environment(\.momentQuickAction) private var quickAction

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 10)]

    private struct TimeSection {
        let title: String
        let moments: [Moment]
    }

    private var sections: [TimeSection] {
        let now = Date()
        var order: [String] = []
        var grouped: [String: [Moment]] = [:]
        for moment in moments {
            let title = timeSectionTitle(for: moment.createdAt, now: now)
            if grouped[title] == nil {
                grouped[title] = []
                order.append(title)
            }
            grouped[title]?.append(moment)
        }
        return order.map { TimeSection(title: $0, moments: grouped[$0] ?? []) }
    }

    var body: some View {
        if moments.isEmpty {
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemBackground))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections, id: \.title) { section in
                        Section {
                            if section.moments.isEmpty {
                                Text("No Moments in \(section.title).")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)
                            } else {
                                LazyVGrid(columns: columns, spacing: 10) {
                                    ForEach(section.moments) { moment in
                                        MomentGridCell(
                                            moment: moment,
                                            isSelecting: isSelecting,
                                            isSelected: selectedMomentIds.contains(moment.id ?? "")
                                        )
                                        .onTapGesture { onTap(moment) }
                                        .contextMenu {
                                            if !isSelecting, let quickAction {
                                                MomentQuickActionMenu(moment: moment, perform: quickAction)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        } header: {
                            Text(section.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground))
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Color(.secondarySystemBackground))
        }
    }
}

/// A Folder or Bucket tile - name, Moment count, and a thumbnail from
/// whichever Moment is filed there most recently (nil shows a plain
/// folder icon instead, same as an empty grid cell showing its kind
/// icon). Shared since Folders and Buckets are the same shape tile.
struct MomentCollectionTile: View {
    let name: String
    let representativeMoment: Moment?
    let count: Int

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color(.secondarySystemBackground))
                .aspectRatio(1.3, contentMode: .fit)
                .overlay {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "folder.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Color.pitchMarkActiveGray)
                    }
                }
                .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text("\(count) Moment\(count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .momentCardStyle()
        .contentShape(Rectangle())
        .onAppear {
            guard thumbnail == nil, let representativeMoment else { return }
            momentThumbnail(for: representativeMoment) { thumbnail = $0 }
        }
    }
}

private struct MomentGridCell: View {
    let moment: Moment
    var isSelecting: Bool
    var isSelected: Bool

    @Environment(\.momentQuickAction) private var quickAction
    @State private var thumbnail: UIImage? = nil

    /// True when this Moment's Firestore metadata synced here but its
    /// video never did - it was recorded on a different signed-in device
    /// (see `momentVideoExistsLocally`'s doc comment, Moment.swift).
    /// Distinguishing this from "thumbnail just hasn't loaded yet" matters:
    /// without it, a Moment from another device looked identical to any
    /// other tile until tapped, where it opened a player/editor stuck
    /// against a file that was never on this device.
    private var isAvailableOnThisDevice: Bool {
        guard let id = moment.id else { return true }
        return momentVideoExistsLocally(for: id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Rectangle()
                    .fill(Color(.secondarySystemBackground))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else if !isAvailableOnThisDevice {
                            VStack(spacing: 4) {
                                Image(systemName: "exclamationmark.icloud")
                                    .font(.title3)
                                Text("Other device")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: momentKindIconName(moment))
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .clipped()

                if !isSelecting, let quickAction {
                    // Always shown, so favoriting is one tap (user's call).
                    let on = moment.isFavorite == true
                    PhotoCornerToggle(systemImage: on ? "heart.fill" : "heart",
                                      tint: on ? .red : .white,
                                      label: on ? "Unfavorite" : "Favorite") {
                        quickAction(moment, .toggleFavorite)
                    }
                } else if moment.isFavorite == true {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(6)
                }

                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .white)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }

                HStack(spacing: 3) {
                    Image(systemName: momentKindIconName(moment))
                        .font(.footnote.weight(.bold))
                    if let duration = moment.durationSeconds {
                        Text(formattedMomentDuration(duration))
                            .font(.caption2.weight(.semibold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                // A photo-only Moment has no "play" affordance - an extra,
                // more prominent badge at the opposite corner (rather than
                // just the small shared kind icon above, easy to miss next
                // to the duration text) makes "this tile is a photo, not a
                // video" legible at a glance across the grid.
                if moment.momentKind == .photoCreation {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Color.accentColor, in: Circle())
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(moment.displayTitle)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let cityName = moment.cityName {
                    Text(cityName)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .momentCardStyle()
        .contentShape(Rectangle())
        .onAppear {
            guard thumbnail == nil else { return }
            momentThumbnail(for: moment) { thumbnail = $0 }
        }
    }
}

/// A tile's long-press menu. Edit isn't here - tapping the tile opens it.
struct MomentQuickActionMenu: View {
    let moment: Moment
    let perform: (Moment, MomentQuickAction) -> Void

    var body: some View {
        Button { perform(moment, .play) } label: { Label("Play", systemImage: "play.fill") }
        if let id = moment.id, !MomentShare.sourceFiles(momentId: id, photoCount: moment.photoCount ?? 0).isEmpty {
            Button { perform(moment, .share) } label: { Label("Share…", systemImage: "square.and.arrow.up") }
        }
        Button { perform(moment, .move) } label: { Label("Move to Folder…", systemImage: "folder") }
        Button { perform(moment, .duplicate) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        if let id = moment.id, momentHasEdits(id) {
            Button { perform(moment, .duplicateOriginal) } label: { Label("Duplicate Original", systemImage: "film") }
        }
        if let id = moment.id {
            HomeSlideshowMomentMenu(momentId: id, photoCount: moment.photoCount ?? 0)
        }
        Divider()
        Button(role: .destructive) { perform(moment, .delete) } label: { Label("Delete", systemImage: "trash") }
    }
}

/// A whole Moment's Home slideshow choice (library long press). Favorite
/// is the ♥ on the tile itself.
struct HomeSlideshowMomentMenu: View {
    let momentId: String
    let photoCount: Int
    @ObservedObject private var store = HomeSlideshowPrefsStore.shared

    var body: some View {
        let isHidden = store.prefs.isMomentHidden(momentId: momentId, photoCount: photoCount)
        Button {
            store.ensureStarted()
            store.setMomentHidden(momentId: momentId, photoCount: photoCount, !isHidden)
        } label: {
            Label(isHidden ? "Show on Home" : "Hide from Home",
                  systemImage: isHidden ? "eye" : "eye.slash")
        }
    }
}

/// The All tab's filter chips (2026-11-15) - replaces the time filter
/// that was hidden inside the section headers.
enum MomentLibraryFilter: String, CaseIterable, Identifiable {
    case all, favorites, videos, photos, thisWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .videos: return "Videos"
        case .photos: return "Photos"
        case .thisWeek: return "This Week"
        }
    }

    func includes(_ moment: Moment, now: Date = Date()) -> Bool {
        switch self {
        case .all: return true
        case .favorites: return moment.isFavorite == true
        case .videos: return moment.momentKind != .photoCreation
        case .photos: return moment.momentKind == .photoCreation || (moment.photoCount ?? 0) > 0
        case .thisWeek:
            guard let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) else { return true }
            return moment.createdAt >= weekAgo
        }
    }

    func apply(to moments: [Moment], now: Date = Date()) -> [Moment] {
        moments.filter { includes($0, now: now) }
    }
}

struct MomentFilterChips: View {
    @Binding var selection: MomentLibraryFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MomentLibraryFilter.allCases) { filter in
                    let isOn = selection == filter
                    Button {
                        selection = filter
                    } label: {
                        HStack(spacing: 4) {
                            if filter == .favorites {
                                Image(systemName: "heart.fill")
                                    .font(.caption2)
                            }
                            Text(filter.title)
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(isOn ? Color.pitchMarkActiveGray : Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("moments.filter.\(filter.rawValue)")
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
