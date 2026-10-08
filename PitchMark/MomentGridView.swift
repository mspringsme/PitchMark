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

    @State private var selectedTimeFilter: MomentTimeFilter? = nil

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 10)]

    private struct TimeSection {
        let title: String
        let moments: [Moment]
    }

    private var sections: [TimeSection] {
        let now = Date()
        if let selectedTimeFilter {
            let filtered = moments.filter { timeSectionTitle(for: $0.createdAt, now: now) == selectedTimeFilter.rawValue }
            return [TimeSection(title: selectedTimeFilter.rawValue, moments: filtered)]
        }
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
                                    }
                                }
                                .padding(.horizontal)
                            }
                        } header: {
                            Menu {
                                Button("All Time") { selectedTimeFilter = nil }
                                ForEach(MomentTimeFilter.allCases) { filter in
                                    Button(filter.rawValue) { selectedTimeFilter = filter }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(section.title)
                                        .font(.subheadline.weight(.semibold))
                                    Image(systemName: "chevron.down")
                                        .font(.caption2.weight(.semibold))
                                }
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Capsule(style: .continuous).fill(Color(.secondarySystemBackground)))
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
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

    @State private var thumbnail: UIImage? = nil

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
                        } else {
                            Image(systemName: momentKindIconName(moment))
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .clipped()

                if moment.isFavorite == true {
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
