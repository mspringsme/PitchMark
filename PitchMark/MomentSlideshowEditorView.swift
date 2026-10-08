//
//  MomentSlideshowEditorView.swift
//  PitchMark
//
//  2026-09-30: the editing screen for MomentSlideshow.swift's segments -
//  combine a Moment's attached photos together with its video into one
//  export, in whatever order the user arranges them.
//
//  Shape deliberately differs from every other editor in this feature
//  set: there's no AVPlayer scrubbing/timeline to drag against here, just
//  a reorderable list of segments (each attached photo, plus the one
//  video block) with a per-photo duration slider. A plain SwiftUI `List`
//  with `.onMove` is the native, well-tested mechanism for this - no
//  custom drag gesture needed, unlike Zoom/Overlay's canvas-based
//  dragging.
//
//  This is also the one editor in the set presented inside a
//  `NavigationView` rather than a bare `.fullScreenCover` with manual
//  overlay buttons - a deliberate exception to
//  [[feedback-toolbar-needs-navigation-container]]'s usual workaround:
//  every other editor avoids NavigationView specifically to keep its
//  video full-bleed, but this screen's content is a plain list, so a real
//  nav bar (and its working `.toolbar`) is simply the right tool here,
//  not a regression toward the bug that feedback describes.
//
//  Reuses `slideshowBaseVideoURL`/`invalidateMomentSlideshowBase`
//  (Moment.swift) - same frozen-base technique the overlay/audio/zoom
//  editors already use, so re-opening this screen after a prior combined
//  export treats "the video segment" as the pre-slideshow video, never a
//  stacked re-splice of its own last output.
//
//  2026-09-30: a photo can be removed from the arrangement via an
//  always-visible trash button on its own row (not the List's edit-mode
//  delete control) - the first version used `.onDelete`/`.deleteDisabled`,
//  which requires tapping a small red circle to reveal a second "Delete"
//  button before anything happens; reported by the user as "there's no
//  way to save it," i.e. the two-tap gesture didn't read as having done
//  anything. A single always-visible button removes that ambiguity. A
//  removed photo - or one newly added to the Moment after this screen
//  last saved - surfaces in `availablePhotosStrip` ("Available Photos")
//  instead of being silently auto-included; see
//  `reconciledSlideshowSegments`'s doc comment (MomentSlideshow.swift)
//  for why membership is fully user-driven now rather than "every
//  attached photo, always."
//
//  2026-09-30: reordering, deleting, adding, or changing a photo's
//  duration all persist to `segments` immediately, but - same as every
//  other editor in this app - none of that touches the actual video file
//  until "Export Combined Video" is tapped; it only bakes whatever
//  `segments` holds *at that moment*. The user read "I deleted a photo"
//  as "the final video no longer has it," then found the old photo still
//  in the exported file - they had tapped Cancel (or just hadn't
//  re-exported) after deleting, not realizing a fresh bake was still
//  required. `hasUnexportedChanges` now drives a visible reminder next
//  to the Export button for exactly this reason, rather than leaving the
//  requirement implicit the way it was.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI
import AVFoundation

struct MomentSlideshowEditorView: View {
    let momentId: String
    let videoURL: URL
    let photoCount: Int
    var onExported: () -> Void = {}

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var segments: [SlideshowSegment]
    @State private var transitionsEnabled: Bool
    @State private var photoImages: [Int: UIImage] = [:]
    @State private var videoDuration: Double = 0
    /// The frozen slideshow-bake base (`slideshowBaseVideoURL`,
    /// Moment.swift) - what `startExport()` treats as "the video
    /// segment," never `videoURL` directly once a prior combined export
    /// exists for this Moment. Resolved asynchronously in `.onAppear`
    /// (`prepareSourceVideoURL`) rather than `init` - the first time this
    /// runs for a Moment it does a real file copy (freezing the base),
    /// and doing that synchronously in `init` blocked the main thread
    /// with zero way to show any loading state (the view hadn't even
    /// mounted yet) - reported by the user as a real delay with no
    /// indicator at all after opening "Combine Photos + Video."
    @State private var sourceVideoURL: URL? = nil

    @State private var isExporting = false
    @State private var exportErrorMessage: String? = nil
    /// True whenever `segments` has changed (reorder, delete, add, or a
    /// duration edit) since the last successful export - drives a
    /// reminder next to the Export button, since none of those changes
    /// touch the actual video file until Export bakes them. Starts
    /// false: the seeded/reconciled initial state is what a prior
    /// export (if any) already reflects.
    @State private var hasUnexportedChanges = false

    init(momentId: String, videoURL: URL, photoCount: Int, initialSegments: [SlideshowSegment], initialTransitionsEnabled: Bool = false, onExported: @escaping () -> Void = {}) {
        self.momentId = momentId
        self.videoURL = videoURL
        self.photoCount = photoCount
        self.onExported = onExported
        let seed = initialSegments.isEmpty ? defaultSlideshowSegments(photoCount: photoCount) : initialSegments
        _segments = State(initialValue: reconciledSlideshowSegments(seed, photoCount: photoCount))
        _transitionsEnabled = State(initialValue: initialTransitionsEnabled)
    }

    /// Every attached photo not currently represented anywhere in
    /// `segments` - surfaced in `availablePhotosSection` so the user can
    /// add it (or add it back, after removing it) deliberately. See
    /// `reconciledSlideshowSegments`'s doc comment for why this replaced
    /// auto-appending every unreferenced photo.
    private var excludedPhotoIndices: [Int] {
        let referenced = Set(segments.compactMap { $0.kind == .photo ? $0.photoIndex : nil })
        return (0..<max(photoCount, 0)).filter { !referenced.contains($0) }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(segments) { segment in
                        segmentRow(segment)
                    }
                    .onMove { indices, newOffset in
                        segments.move(fromOffsets: indices, toOffset: newOffset)
                        persistSegments()
                    }
                } footer: {
                    Text("Drag to reorder, tap the trash icon to remove a photo. The video always plays in full and can't be removed; photos display for their own duration.")
                }

                if !excludedPhotoIndices.isEmpty {
                    Section("Available Photos") {
                        availablePhotosStrip
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Combine Photos + Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                exportBar
            }
        }
        // Same full-screen dim-plus-white-spinner overlay every other
        // editor's exporting state already uses (MomentZoomEditorView,
        // MomentSpeedEditorView, MomentAudioEditorView, OverlayEditorView)
        // - a bare inline ProgressView on a colored .borderedProminent
        // button (the first version of this) was reported as "too faint,
        // not noticeable." This is the established, already-proven-visible
        // pattern instead of a new one.
        .overlay {
            if isExporting || sourceVideoURL == nil {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text(isExporting ? "Exporting…" : "Preparing…")
                            .foregroundStyle(.white)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .onAppear {
            loadPhotoImages()
            prepareSourceVideoURL()
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func segmentRow(_ segment: SlideshowSegment) -> some View {
        switch segment.kind {
        case .photo:
            if let photoIndex = segment.photoIndex {
                photoRow(photoIndex: photoIndex, segmentID: segment.id)
            }
        case .video:
            videoRow
        }
    }

    private func photoRow(photoIndex: Int, segmentID: UUID) -> some View {
        HStack(spacing: 12) {
            thumbnail(for: photoIndex)
            VStack(alignment: .leading, spacing: 4) {
                Text("Photo \(photoIndex + 1)")
                    .font(.subheadline)
                HStack {
                    Slider(
                        value: durationBinding(for: segmentID),
                        in: minSlideshowPhotoDuration...maxSlideshowPhotoDuration,
                        onEditingChanged: { editing in if !editing { persistSegments() } }
                    )
                    Text(String(format: "%.1fs", durationBinding(for: segmentID).wrappedValue))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
            Spacer(minLength: 0)
            Button {
                removeSegment(segmentID)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    /// Always-visible, single-tap removal - see the file header comment
    /// for why this replaced the List's two-tap edit-mode delete control.
    private func removeSegment(_ segmentID: UUID) {
        segments.removeAll { $0.id == segmentID }
        persistSegments()
    }

    private var videoRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(.systemGray5))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "film.fill")
                        .foregroundStyle(.secondary)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Video")
                    .font(.subheadline)
                Text(formattedTime(videoDuration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func thumbnail(for photoIndex: Int) -> some View {
        if let image = photoImages[photoIndex] {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(.systemGray5))
                .frame(width: 44, height: 44)
        }
    }

    /// A horizontal strip of every attached photo not currently in
    /// `segments` (`excludedPhotoIndices`) - tapping one appends it to
    /// the end of the arrangement. Mirrors `AssetThumbnailStrip`'s
    /// tap-to-add shape (OverlayEditorView.swift) rather than inventing a
    /// new interaction for the same "browse then add" need.
    private var availablePhotosStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(excludedPhotoIndices, id: \.self) { index in
                    Button {
                        addPhoto(index: index)
                    } label: {
                        thumbnail(for: index)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white, Color.accentColor)
                                    .background(Circle().fill(.white))
                                    .offset(x: 4, y: 4)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func addPhoto(index: Int) {
        segments.append(SlideshowSegment(kind: .photo, photoIndex: index, photoDuration: defaultSlideshowPhotoDuration))
        persistSegments()
    }

    private func durationBinding(for segmentID: UUID) -> Binding<Double> {
        Binding(
            get: { segments.first(where: { $0.id == segmentID })?.photoDuration ?? defaultSlideshowPhotoDuration },
            set: { newValue in
                guard let index = segments.firstIndex(where: { $0.id == segmentID }) else { return }
                segments[index].photoDuration = newValue
            }
        )
    }

    private func formattedTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Export bar

    private var exportBar: some View {
        VStack(spacing: 6) {
            Toggle("Fade Between Segments", isOn: $transitionsEnabled)
                .onChange(of: transitionsEnabled) { _, _ in
                    hasUnexportedChanges = true
                }
            if hasUnexportedChanges {
                Text("Changes not yet in the video - tap Export to apply them.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let exportErrorMessage {
                Text(exportErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button {
                startExport()
            } label: {
                // Static text - the full-screen overlay (attached to the
                // whole screen, see `body`) is what actually communicates
                // "Preparing…"/"Exporting…", same as every sibling editor.
                Text("Export Combined Video")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExporting || sourceVideoURL == nil)
        }
        .padding()
        .background(.bar)
    }

    // MARK: Loading

    private func loadPhotoImages() {
        var images: [Int: UIImage] = [:]
        for index in 0..<max(photoCount, 0) {
            if let url = localMomentPhotoURL(momentId: momentId, index: index),
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                images[index] = image
            }
        }
        photoImages = images
    }

    /// Resolves `sourceVideoURL` off the main thread (see its own doc
    /// comment for why this can't happen in `init`), then loads its
    /// duration once it's ready.
    private func prepareSourceVideoURL() {
        DispatchQueue.global(qos: .userInitiated).async { [momentId, videoURL] in
            let resolved = slideshowBaseVideoURL(momentId: momentId, sourceVideoURL: videoURL)
            DispatchQueue.main.async {
                sourceVideoURL = resolved
                loadVideoDuration()
            }
        }
    }

    private func loadVideoDuration() {
        guard let sourceVideoURL else { return }
        let asset = AVURLAsset(url: sourceVideoURL)
        Task {
            let loadedDuration = try? await asset.load(.duration)
            await MainActor.run {
                videoDuration = loadedDuration?.seconds.isFinite == true ? loadedDuration!.seconds : 0
            }
        }
    }

    // MARK: Persistence

    private func persistSegments() {
        hasUnexportedChanges = true
        guard !momentId.isEmpty else { return }
        authManager.updateMomentSlideshowSegments(momentId: momentId, segments: segments) { error in
            if let error {
                debugLog("❌ updateMomentSlideshowSegments failed:", error.localizedDescription)
            }
        }
    }

    // MARK: Export

    /// Builds the combined export from `sourceVideoURL` (the frozen
    /// slideshow-bake base) and the current `segments`, which composites
    /// on top of any prior trim/speed/zoom/overlay/audio edit exactly
    /// once, the first time this editor exports on this Moment, then
    /// stays fixed so every later export re-splices the *current*
    /// segment arrangement from that same clean source instead of
    /// stacking on a previous splice. On success, copies the result into
    /// the edited slot so every existing consumer (playback, share,
    /// save-to-Camera-Roll) picks it up automatically.
    private func startExport() {
        guard !momentId.isEmpty, let sourceVideoURL else { return }
        exportErrorMessage = nil
        isExporting = true

        exportSlideshowMoment(
            videoSourceURL: sourceVideoURL,
            segments: segments,
            transitionsEnabled: transitionsEnabled,
            resolvePhoto: { index in photoImages[index] }
        ) { result in
            isExporting = false
            switch result {
            case .success(let tempURL):
                guard let destination = localMomentEditedVideoURL(for: momentId) else {
                    exportErrorMessage = "Couldn't save the exported video."
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: tempURL, to: destination)
                    try? FileManager.default.removeItem(at: tempURL)
                    hasUnexportedChanges = false
                    authManager.updateMomentFields(momentId: momentId, fields: ["slideshowTransitionsEnabled": transitionsEnabled]) { _ in }
                    authManager.refreshMomentDuration(momentId: momentId, videoURL: destination)
                    // Every other frozen-base ring member now misses
                    // these spliced-in photos - see Moment.swift's
                    // invalidateOtherFrozenBases doc comment.
                    invalidateOtherFrozenBases(momentId: momentId, except: [.slideshow])
                    // See MomentAudioEditorView.swift's identical comment.
                    refreshFadeIfNeeded(momentId: momentId, authManager: authManager) { onExported() }
                    onExported()
                    dismiss()
                } catch {
                    exportErrorMessage = "Couldn't save the exported video: \(error.localizedDescription)"
                }
            case .failure(let error):
                debugLog("❌ exportSlideshowMoment failed:", debugErrorDetail(error))
                exportErrorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}
