//
//  MomentDetailView.swift
//  PitchMark
//
//  Phase 7a - the real Moment detail/edit screen. Replaces
//  MomentsLibraryView's old behavior of opening VideoPlayer directly on
//  tap; this view owns playback plus everything editable about a Moment.
//  "Capture now, create later" extends to editing too: nothing here is
//  required, every field commits immediately on its own rather than
//  needing a separate Save step. Deliberately kept out of the Pitchmark
//  Display target's membershipExceptions; Display has no use for this UI.
//

import SwiftUI
import AVKit
import PhotosUI

private struct FullScreenPhoto: Identifiable {
    let id: Int
    let image: UIImage
}

/// The tile look shared by every single-title action button on this
/// screen (Trim/Speed/Zoom/etc., Add Photos, Combine Photos + Video) -
/// one definition so they all read as the same kind of control.
/// `fillWidth: false` lets a short-text button (like "Photos") hug its
/// own content instead of stretching to match its row's widest sibling.
private struct ActionTileStyle: ViewModifier {
    var fillWidth: Bool = true

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color.primary)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: fillWidth ? .infinity : nil, minHeight: 44)
            .background(Color.pitchMarkActiveGray.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.pitchMarkActiveGray.opacity(0.4), lineWidth: 1)
            )
    }
}

private extension View {
    func actionTileStyle(fillWidth: Bool = true) -> some View {
        modifier(ActionTileStyle(fillWidth: fillWidth))
    }
}

struct MomentDetailView: View {
    /// `@State`, not `let` - every editor's `initial...` parameter
    /// (overlays/speed keyframes/zoom regions/slideshow segments/mute
    /// regions) seeds from this. Each editor persists its own changes to
    /// Firestore immediately, but a `let` here would keep showing
    /// whatever `moment` looked like when THIS view was first opened, no
    /// matter how many Firestore writes happened since - every editor
    /// reopened afterward (including the same one again) would silently
    /// re-seed from that stale snapshot, discarding anything persisted in
    /// between. `refreshMoment()` re-fetches this fresh after every
    /// editor dismisses - see its own doc comment and
    /// `AuthManager.loadMoment`'s for the bug this fixes.
    @State private var moment: Moment
    /// All the user's Moments, newest first (already loaded by
    /// MomentsLibraryView) - passed through to MomentPhotoGalleryPickerView
    /// so the "From Moments Library" photo source can offer every other
    /// Moment to pick a photo from.
    let allMoments: [Moment]

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var isFavorite: Bool
    @State private var title: String

    @State private var photoCount: Int
    @State private var photoSelections: [PhotosPickerItem] = []
    @State private var showSystemPhotoPicker = false
    @State private var showMomentGalleryPicker = false
    @State private var photosPendingLibraryPrompt: [Data] = []
    @State private var showAddToMomentsLibraryPrompt = false
    @State private var fullScreenPhoto: FullScreenPhoto? = nil
    /// Decoded once and cached, same reasoning as `player` below: every
    /// re-render of this view (e.g. a keystroke in Opponent/Score) used
    /// to call photoThumbnail(index:), which re-read the file and ran
    /// UIImage(data:) fresh each time - reported as a "pulsating"/
    /// flashing artifact on the thumbnails. Loaded once in onAppear and
    /// whenever photoCount changes, not decoded inline in the view body.
    @State private var photoImages: [Int: UIImage] = [:]

    @State private var showTrimEditor = false
    @State private var trimErrorMessage: String? = nil

    @State private var showOverlayEditor = false
    @State private var overlayEditorAssets: [LibraryAsset] = []

    @State private var showMarkupEditor = false

    @State private var showAudioEditor = false

    @State private var showSpeedEditor = false

    @State private var showZoomEditor = false
    @State private var showCropEditor = false
    @State private var showFreezeEditor = false
    @State private var showFilterEditor = false

    @State private var showSlideshowEditor = false

    @State private var fadeInEnabled: Bool
    @State private var fadeOutEnabled: Bool
    @State private var isApplyingFade = false
    @State private var fadeErrorMessage: String? = nil
    /// Created once and reused, never rebuilt inline in the view body -
    /// on-device testing showed the video "flash the first frame, only
    /// play about a second" when it was constructed inline
    /// (`VideoPlayer(player: AVPlayer(url: url))` directly in a computed
    /// property): SwiftUI re-evaluates that property on every body
    /// re-render (e.g. every keystroke in the Opponent/Score fields
    /// below), and each re-render built a brand-new AVPlayer pointed at
    /// the same URL, discarding playback position back to frame 0. Only
    /// reloaded explicitly, when the underlying file actually changes.
    @State private var player: AVPlayer? = nil
    /// Lets the preview expand to full screen from right here in the
    /// edit screen - with every editor a fullScreenCover of its own,
    /// the user is repeatedly bounced back to this screen to check an
    /// edit, and previously had no way to see it full screen without
    /// leaving to re-open the Moment from the library.
    @State private var showFullScreenPlayback = false

    init(moment: Moment, allMoments: [Moment]) {
        _moment = State(initialValue: moment)
        self.allMoments = allMoments
        _isFavorite = State(initialValue: moment.isFavorite ?? false)
        _title = State(initialValue: moment.title ?? "")
        _photoCount = State(initialValue: moment.photoCount ?? 0)
        _fadeInEnabled = State(initialValue: moment.fadeInEnabled ?? false)
        _fadeOutEnabled = State(initialValue: moment.fadeOutEnabled ?? false)
    }

    private var momentId: String { moment.id ?? "" }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    playbackSection
                    editActionsSection
                    photosSection
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        toggleFavorite()
                    } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(isFavorite ? Color.red : Color.secondary)
                    }
                }
                // Replaces a separate "Name" field below the video -
                // tapping where the title normally reads is intuitive
                // enough to edit it, and freeing that row gives the
                // video preview above the buttons more room. Wrapped in
                // its own outlined rectangle (rather than reading as
                // plain nav-bar text) so it's visually obvious it's
                // tappable, not just a label.
                ToolbarItem(placement: .principal) {
                    TextField(moment.playerName ?? "Moment", text: $title)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .onSubmit { commitTitle() }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 14)
                        .background(Color.pitchMarkActiveGray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.pitchMarkActiveGray.opacity(0.4), lineWidth: 1)
                        )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $fullScreenPhoto) { photo in
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFit()
                .background(Color.black)
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showSystemPhotoPicker, selection: $photoSelections, matching: .images)
        .onChange(of: photoSelections) { _, items in
            guard !items.isEmpty else { return }
            addPhotos(items)
        }
        .sheet(isPresented: $showMomentGalleryPicker) {
            MomentPhotoGalleryPickerView(moments: allMoments, excludingMomentId: moment.id) { datas in
                addMomentGalleryPhotos(datas)
            }
        }
        .appConfirmationDialog(
            isPresented: $showAddToMomentsLibraryPrompt,
            title: "Add to Moments Library?",
            message: photosPendingLibraryPrompt.count == 1
                ? "Also save this photo as its own Moment in your library?"
                : "Also save these \(photosPendingLibraryPrompt.count) photos as their own Moments in your library?",
            primaryTitle: "Add",
            primaryAction: {
                addPendingPhotosToMomentsLibrary()
            },
            secondaryTitle: "Not Now",
            secondaryAction: {
                photosPendingLibraryPrompt = []
            }
        )
        .fullScreenCover(isPresented: $showFullScreenPlayback) {
            if let url = resolvedMomentPlaybackURL(for: momentId) {
                MomentPlaybackView(videoURL: url)
            }
        }
        .fullScreenCover(isPresented: $showTrimEditor) {
            if let path = resolvedMomentVideoURL(for: momentId)?.path {
                MomentTrimEditor(videoPath: path) { editedPath in
                    showTrimEditor = false
                    if let editedPath {
                        saveTrimResult(editedPath)
                    }
                }
                .ignoresSafeArea()
            }
        }
        .fullScreenCover(isPresented: $showOverlayEditor) {
            if let url = resolvedMomentVideoURL(for: momentId) {
                OverlayEditorView(
                    momentId: momentId,
                    videoURL: url,
                    libraryAssets: overlayEditorAssets,
                    initialOverlays: moment.overlays ?? [],
                    onExported: { reloadPlayer(); refreshMoment() }
                )
                    .environmentObject(authManager)
                    .ignoresSafeArea()
            }
        }
        .fullScreenCover(isPresented: $showMarkupEditor) {
            if let url = resolvedMomentVideoURL(for: momentId) {
                MarkupEditorView(
                    momentId: momentId,
                    videoURL: url,
                    initialMarkups: moment.markupOverlays ?? [],
                    onExported: { reloadPlayer(); refreshMoment() }
                )
                    .environmentObject(authManager)
                    .ignoresSafeArea()
            }
        }
        .fullScreenCover(isPresented: $showSpeedEditor) {
            if let url = resolvedMomentVideoURL(for: momentId) {
                MomentSpeedEditorView(
                    momentId: momentId,
                    videoURL: url,
                    initialKeyframes: moment.speedKeyframes ?? [],
                    onExported: { reloadPlayer(); refreshMoment() }
                )
                    .environmentObject(authManager)
                    .ignoresSafeArea()
            }
        }
        .fullScreenCover(isPresented: $showZoomEditor) {
            if let url = resolvedMomentVideoURL(for: momentId) {
                MomentZoomEditorView(
                    momentId: momentId,
                    videoURL: url,
                    initialRegions: moment.zoomRegions ?? [],
                    onExported: { reloadPlayer(); refreshMoment() }
                )
                    .environmentObject(authManager)
                    .ignoresSafeArea()
            }
        }
        .fullScreenCover(isPresented: $showCropEditor) {
            if let url = resolvedMomentVideoURL(for: momentId) {
                MomentCropEditorView(
                    momentId: momentId,
                    videoURL: url,
                    initialCropSettings: moment.cropSettings,
                    onExported: { reloadPlayer(); refreshMoment() }
                )
                    .environmentObject(authManager)
            }
        }
        .fullScreenCover(isPresented: $showFreezeEditor) {
            if let url = resolvedMomentVideoURL(for: momentId) {
                MomentFreezeEditorView(
                    momentId: momentId,
                    videoURL: url,
                    initialFreezeFrame: moment.freezeFrame,
                    onExported: { reloadPlayer(); refreshMoment() }
                )
                    .environmentObject(authManager)
            }
        }
        .fullScreenCover(isPresented: $showFilterEditor) {
            if let url = resolvedMomentVideoURL(for: momentId) {
                MomentFilterEditorView(
                    momentId: momentId,
                    videoURL: url,
                    initialFilterPreset: moment.filterPreset,
                    onExported: { reloadPlayer(); refreshMoment() }
                )
                    .environmentObject(authManager)
            }
        }
        .fullScreenCover(isPresented: $showSlideshowEditor) {
            if let url = resolvedMomentVideoURL(for: momentId) {
                MomentSlideshowEditorView(
                    momentId: momentId,
                    videoURL: url,
                    photoCount: photoCount,
                    initialSegments: moment.slideshowSegments ?? [],
                    initialTransitionsEnabled: moment.slideshowTransitionsEnabled ?? false,
                    onExported: { reloadPlayer(); refreshMoment() }
                )
                    .environmentObject(authManager)
            }
        }
        .fullScreenCover(isPresented: $showAudioEditor) {
            if let url = resolvedMomentVideoURL(for: momentId) {
                MomentAudioEditorView(
                    momentId: momentId,
                    videoURL: url,
                    initialAudioOverlays: moment.audioOverlays ?? [],
                    initialOriginalVolume: moment.originalAudioVolume ?? 1.0,
                    initialOriginalVolumeKeyframes: moment.originalVolumeKeyframes ?? [],
                    initialOriginalMuteRegions: moment.originalMuteRegions ?? [],
                    onExported: { reloadPlayer(); refreshMoment() }
                )
                    .environmentObject(authManager)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            reloadPlayer()
            loadPhotoImages()
        }
        // commitTitle() only fired from the TextField's onSubmit (return
        // key), so tapping Done - or swiping the sheet away - with an
        // edited title still in the field and the keyboard still up
        // dismissed without ever saving it. onDisappear fires for both
        // exit paths, not just Done, so it's the one place that reliably
        // flushes whatever's currently in the field.
        .onDisappear { commitTitle() }
    }

    @ViewBuilder
    private var playbackSection: some View {
        if let player {
            VideoPlayer(player: player)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        showFullScreenPlayback = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    .padding(8)
                }
        }
        Text(moment.createdAt.formatted(date: .abbreviated, time: .shortened))
            .font(.caption)
            .foregroundStyle(.secondary)
    }


    /// All the one-tap-into-an-editor actions, as single-title buttons
    /// in a grid instead of each getting its own full-width row - nine
    /// of these stacked vertically (the old layout) pushed Game Info
    /// well below the fold. Fade and Photos keep their own sections
    /// below since they carry inline controls (toggles / thumbnails),
    /// not just a single action.
    private var editActionColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 140), spacing: 10),
            GridItem(.flexible(minimum: 140), spacing: 10)
        ]
    }

    private var cropCaption: String? {
        guard let aspect = moment.cropSettings?.aspect, aspect != .original else { return nil }
        return aspect.displayName
    }

    private var filterCaption: String? {
        moment.filterPreset?.displayName
    }

    private var markupCaption: String? {
        guard let count = moment.markupOverlays?.count, count > 0 else { return nil }
        return "\(count) added"
    }

    private var editActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: editActionColumns, spacing: 10) {
                editActionButton("Trim") { startTrimEditor() }
                editActionButton("Speed") { showSpeedEditor = true }
                editActionButton("Zoom") { showZoomEditor = true }
                editActionButton("Crop", caption: cropCaption) { showCropEditor = true }
                editActionButton("Freeze Frame", caption: moment.freezeFrame != nil ? "Applied" : nil) {
                    showFreezeEditor = true
                }
                editActionButton("Filters", caption: filterCaption) { showFilterEditor = true }
                editActionButton("Overlays") {
                    authManager.loadLibraryAssets { assets in
                        overlayEditorAssets = assets
                        showOverlayEditor = true
                    }
                }
                editActionButton("Markup", caption: markupCaption) { showMarkupEditor = true }
                editActionButton("Audio") { showAudioEditor = true }
                fadeGridCell
            }

            if isApplyingFade {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }

            if let trimErrorMessage {
                Text(trimErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let fadeErrorMessage {
                Text(fadeErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func editActionButton(_ title: String, caption: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .actionTileStyle()
        }
        .buttonStyle(.plain)
    }

    /// Fade In and Fade Out share a single grid cell (the tenth, next to
    /// Audio) rather than getting their own labeled section - there's no
    /// third state or extra chrome to justify a header, just two small
    /// toggles. Each applies on tap rather than waiting for a separate
    /// "Apply" button - there's no state where flipping one of these and
    /// not exporting makes sense. Deliberately NOT disabled just because
    /// both are off: that's exactly the state needed to remove a
    /// previously-applied fade (re-bake from the pre-fade base with
    /// neither fade active). Disabling that case once made an applied
    /// fade permanent - reported by the user as "unable to remove a fade
    /// in or out after Apply Fade."
    private var fadeGridCell: some View {
        HStack(spacing: 4) {
            fadeToggleButton("Fade In", isOn: fadeInEnabled) {
                fadeInEnabled.toggle()
                applyFade()
            }
            fadeToggleButton("Fade Out", isOn: fadeOutEnabled) {
                fadeOutEnabled.toggle()
                applyFade()
            }
        }
    }

    @ViewBuilder
    private func fadeToggleButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                }
            }
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                isOn ? Color.pitchMarkActiveGray : Color.pitchMarkActiveGray.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.pitchMarkActiveGray.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isApplyingFade)
    }

    @ViewBuilder
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photos")
                .font(.headline)

            // Two distinct sources, two distinct entry points - the
            // phone's camera roll (system PhotosPicker) and PitchMark's
            // own Moments catalog (MomentPhotoGalleryPickerView) have no
            // overlap, so picking "the wrong one" isn't possible by
            // construction.
            Menu {
                // A `PhotosPicker` used directly as a Menu row never
                // presents anything when tapped - Menu converts its
                // content into native UIMenu actions, which
                // PhotosPicker's own sheet-presentation logic doesn't
                // hook into (it needs to live in the plain SwiftUI
                // view tree, the way it does below). A plain Button
                // that flips `showSystemPhotoPicker` instead, paired
                // with the `.photosPicker(isPresented:...)` modifier
                // further down, is the supported way to trigger it
                // from inside a Menu.
                Button {
                    showSystemPhotoPicker = true
                } label: {
                    Label("From Photos Library", systemImage: "photo.on.rectangle")
                }
                Button {
                    showMomentGalleryPicker = true
                } label: {
                    Label("From Moments Library", systemImage: "rectangle.stack")
                }
            } label: {
                Label("Photos", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .actionTileStyle(fillWidth: false)
            }

            if photoCount > 0 {
                // `showsIndicators: false` plus horizontal scroll means
                // this only ever scrolls once the thumbnails overflow
                // the screen width - a row that fits needs no scrolling
                // at all, exactly as it already behaves.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<photoCount, id: \.self) { index in
                            photoThumbnail(index: index)
                        }
                    }
                }

                Button {
                    showSlideshowEditor = true
                } label: {
                    Text("Combine Photos + Video")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .actionTileStyle(fillWidth: false)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func photoThumbnail(index: Int) -> some View {
        if let image = photoImages[index] {
            Button {
                fullScreenPhoto = FullScreenPhoto(id: index, image: image)
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 90, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

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

    /// Trims whatever `resolvedMomentVideoURL` currently is - the
    /// combined/zoomed/overlaid/mixed/faded video if any of those have
    /// run, never the pristine original directly. Trim used to always
    /// reach past all of that to `localMomentVideoURL` (the untouched
    /// recording) and then overwrite the edited slot with a trim of
    /// *that*, silently discarding every other edit already baked in -
    /// every other editor in this family already operates on "whatever
    /// the current edited video is," so Trim was the one inconsistent
    /// case. Reported by the user as "buggy" after combining a photo,
    /// then zooming, then trying to trim.
    private func startTrimEditor() {
        trimErrorMessage = nil
        guard let path = resolvedMomentVideoURL(for: momentId)?.path,
              UIVideoEditorController.canEditVideo(atPath: path) else {
            trimErrorMessage = "This video can't be trimmed on this device."
            return
        }
        showTrimEditor = true
    }

    /// Native trim already produces a finished, playable file - copied
    /// straight to the edited slot, no separate "Apply" step needed since
    /// there's no further compositing to layer on top of the trim result
    /// itself. That's about the *trim output*, not about what it trimmed
    /// FROM - `startTrimEditor` points the native editor at
    /// `resolvedMomentVideoURL`, so this can just as easily be trimming
    /// an already-combined/zoomed/mixed video as the untouched original;
    /// either way the result here becomes the new edited video outright.
    private func saveTrimResult(_ editedPath: String) {
        guard let destination = localMomentEditedVideoURL(for: momentId) else { return }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: editedPath), to: destination)
            reloadPlayer()
            authManager.refreshMomentDuration(momentId: momentId, videoURL: destination)
            // Every frozen-base ring member now misses this trim - see
            // Moment.swift's invalidateOtherFrozenBases doc comment.
            invalidateOtherFrozenBases(momentId: momentId, except: [])
            refreshFadeIfNeeded(momentId: momentId, authManager: authManager) { [self] in reloadPlayer() }
            refreshMoment()
        } catch {
            trimErrorMessage = "Couldn't save the trimmed video: \(error.localizedDescription)"
        }
    }

    /// Fade is NOT a destructive bake onto the shared edited video -
    /// unlike every other editor, it writes its own separate file
    /// (`localMomentFadedVideoURL`), read fresh from `resolvedMomentVideoURL`
    /// (the fade-free timeline every other editor's own base/export logic
    /// still treats as ground truth) every single time, whether turning a
    /// fade on or off. There is no frozen "pre-fade" snapshot to go stale,
    /// so no other editor needs to invalidate anything for Fade's sake,
    /// and removing a previously-applied fade is always correct no matter
    /// what else happened in between.
    ///
    /// This replaced a frozen-base design (mirrored from Zoom/Overlay/
    /// Audio/Slideshow) that had a real, confirmed bug those editors
    /// don't: when another editor ran *after* a fade had been applied, it
    /// invalidated the fade's frozen base - which then got *recreated
    /// from the currently-faded video*, permanently baking the fade into
    /// what was supposed to be the "pre-fade" reference. Reported by the
    /// user as "applying removal, but the fade doesn't actually go away" -
    /// confirmed via an actual end-to-end render (brightness over time
    /// was genuinely flat after "removal," ruling out a stale-player
    /// theory) before concluding the frozen base itself was the bug.
    private func applyFade() {
        guard !momentId.isEmpty, let sourceURL = resolvedMomentVideoURL(for: momentId) else { return }
        let wantsFadeIn = fadeInEnabled
        let wantsFadeOut = fadeOutEnabled
        fadeErrorMessage = nil

        guard wantsFadeIn || wantsFadeOut else {
            // Removing the fade entirely - no export needed, just drop
            // the faded file so resolvedMomentPlaybackURL falls back to
            // the plain (fade-free) edited video.
            if let faded = localMomentFadedVideoURL(for: momentId) {
                try? FileManager.default.removeItem(at: faded)
            }
            authManager.updateMomentFields(momentId: momentId, fields: ["fadeInEnabled": false, "fadeOutEnabled": false]) { _ in }
            moment.fadeInEnabled = false
            moment.fadeOutEnabled = false
            reloadPlayer()
            return
        }

        isApplyingFade = true
        exportFadedMoment(sourceURL: sourceURL, fadeInEnabled: wantsFadeIn, fadeOutEnabled: wantsFadeOut) { result in
            isApplyingFade = false
            switch result {
            case .success(let tempURL):
                guard let destination = localMomentFadedVideoURL(for: momentId) else {
                    fadeErrorMessage = "Couldn't save the exported video."
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: tempURL, to: destination)
                    try? FileManager.default.removeItem(at: tempURL)
                    authManager.updateMomentFields(momentId: momentId, fields: [
                        "fadeInEnabled": wantsFadeIn,
                        "fadeOutEnabled": wantsFadeOut
                    ]) { _ in }
                    moment.fadeInEnabled = wantsFadeIn
                    moment.fadeOutEnabled = wantsFadeOut
                    reloadPlayer()
                } catch {
                    fadeErrorMessage = "Couldn't save the exported video: \(error.localizedDescription)"
                }
            case .failure(let error):
                debugLog("❌ exportFadedMoment failed:", debugErrorDetail(error))
                fadeErrorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    /// Resolves through `resolvedMomentPlaybackURL`, not
    /// `resolvedMomentVideoURL` directly - the in-app player should show
    /// the faded result when a fade is applied, same as share/save/
    /// duplicate elsewhere in the app.
    private func reloadPlayer() {
        guard let url = resolvedMomentPlaybackURL(for: momentId) else {
            player = nil
            return
        }
        player = AVPlayer(url: url)
    }

    /// Re-fetches `moment` fresh from Firestore - see its own `@State`
    /// doc comment above for the bug this fixes. Called after every
    /// editor dismisses, so the NEXT editor opened (including the same
    /// one again) always seeds from what was actually last saved, not
    /// from whatever `moment` looked like when this screen first opened.
    /// Fire-and-forget by design, matching every other small
    /// field-refresh call in this app - a late/failed refresh just means
    /// the next editor re-seeds from the previous value, same as before
    /// this existed, never from the WRONG Moment or corrupted data.
    private func refreshMoment() {
        guard !momentId.isEmpty else { return }
        authManager.loadMoment(momentId: momentId) { fresh in
            guard let fresh else { return }
            moment = fresh
        }
    }

    private func toggleFavorite() {
        isFavorite.toggle()
        authManager.updateMomentFields(momentId: momentId, fields: ["isFavorite": isFavorite]) { _ in }
    }

    private func commitTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        authManager.updateMomentFields(momentId: momentId, fields: ["title": trimmed.isEmpty ? NSNull() : trimmed]) { _ in }
    }

    private func addPhotos(_ items: [PhotosPickerItem]) {
        var nextIndex = photoCount
        Task {
            var addedDatas: [Data] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                saveLocalMomentPhoto(data, momentId: momentId, index: nextIndex)
                addedDatas.append(data)
                nextIndex += 1
            }
            await MainActor.run {
                photoCount = nextIndex
                photoSelections = []
                loadPhotoImages()
                authManager.updateMomentFields(momentId: momentId, fields: ["photoCount": photoCount]) { _ in }
                // Only a phone-library import prompts this - a photo
                // picked via "From Moments Library" (addMomentGalleryPhotos)
                // already has a Moment of its own, so asking to add it
                // again would just offer to duplicate it.
                if !addedDatas.isEmpty {
                    photosPendingLibraryPrompt = addedDatas
                    showAddToMomentsLibraryPrompt = true
                }
            }
        }
    }

    /// Same append-at-the-end shape as `addPhotos`, just fed raw photo
    /// Data already on disk (from another Moment in the catalog) instead
    /// of a fresh `PhotosPickerItem` from the system library - no async
    /// `loadTransferable` needed, the bytes are already local.
    private func addMomentGalleryPhotos(_ datas: [Data]) {
        guard !datas.isEmpty else { return }
        var nextIndex = photoCount
        for data in datas {
            saveLocalMomentPhoto(data, momentId: momentId, index: nextIndex)
            nextIndex += 1
        }
        photoCount = nextIndex
        loadPhotoImages()
        authManager.updateMomentFields(momentId: momentId, fields: ["photoCount": photoCount]) { _ in }
    }

    /// One standalone `.photoCreation` Moment per photo just attached
    /// from the phone's library, via `AuthManager.createPhotoCreationMoment` -
    /// so declining the prompt leaves this video's Photos section exactly
    /// as it already is (the photos are attached either way), and
    /// accepting only adds entries elsewhere, in the catalog.
    private func addPendingPhotosToMomentsLibrary() {
        let datas = photosPendingLibraryPrompt
        photosPendingLibraryPrompt = []
        for data in datas {
            authManager.createPhotoCreationMoment(
                photoData: data,
                teamId: moment.teamId,
                playerId: moment.playerId,
                playerName: moment.playerName
            ) {}
        }
    }
}
