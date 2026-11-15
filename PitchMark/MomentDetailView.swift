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
import FirebaseFirestore

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
    /// The game open in the tracker right now, for a Moment that wasn't
    /// recorded during one (MomentGameCaption.swift).
    var currentGameContext: (() -> MomentGameContext?)? = nil

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

    @State private var shareRequest: MomentShareRequest? = nil
    @State private var showNothingToShare = false
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
    // The ⋯ menu (2026-11-15): Move, Duplicate, Revert, Delete were only
    // in the library's tap list before.
    @State private var showMoveSheet = false
    @State private var showDeleteConfirm = false
    @State private var showRevertConfirm = false
    @State private var actionMessage: String? = nil
    // Game Info (MomentGameCaption.swift).
    @State private var captionSheet: CaptionContextBox? = nil
    @State private var showNoGameInfo = false
    @State private var isApplyingCaption = false
    @State private var showTagPlayers = false
    /// Lets the preview expand to full screen from right here in the
    /// edit screen - with every editor a fullScreenCover of its own,
    /// the user is repeatedly bounced back to this screen to check an
    /// edit, and previously had no way to see it full screen without
    /// leaving to re-open the Moment from the library.
    @State private var showFullScreenPlayback = false

    init(moment: Moment, allMoments: [Moment], currentGameContext: (() -> MomentGameContext?)? = nil) {
        _moment = State(initialValue: moment)
        self.allMoments = allMoments
        self.currentGameContext = currentGameContext
        _isFavorite = State(initialValue: moment.isFavorite ?? false)
        _title = State(initialValue: moment.title ?? "")
        _photoCount = State(initialValue: moment.photoCount ?? 0)
        _fadeInEnabled = State(initialValue: moment.fadeInEnabled ?? false)
        _fadeOutEnabled = State(initialValue: moment.fadeOutEnabled ?? false)
    }

    private var momentId: String { moment.id ?? "" }

    /// False when this Moment's Firestore metadata synced to this device
    /// but its video never did - recorded on a different signed-in device
    /// (see `momentVideoExistsLocally`'s doc comment, Moment.swift). Drives
    /// whether `playbackSection` shows a player or an explanatory banner,
    /// and whether `editActionsSection`'s video editors are even offered -
    /// every one of them bakes into a video file that doesn't exist here.
    private var hasLocalMedia: Bool {
        momentVideoExistsLocally(for: momentId)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    playbackSection
                    if hasLocalMedia {
                        editActionsSection
                    }
                    playersSection
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        shareRequest = MomentShare.prepare(moment)
                        if shareRequest == nil { showNothingToShare = true }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                    if hasLocalMedia { moreMenu }
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $captionSheet) { box in
            GameCaptionSheet(
                context: box.context,
                initialOptions: moment.gameCaption,
                canRemove: moment.gameCaption != nil,
                onApply: { options in
                    captionSheet = nil
                    applyCaption(options, context: box.context)
                },
                onRemove: {
                    captionSheet = nil
                    applyCaption(nil, context: box.context)
                },
                onSkip: { captionSheet = nil }
            )
        }
        .appConfirmationDialog(
            isPresented: $showNoGameInfo,
            title: "No Game Info",
            message: "This Moment wasn't recorded during a game, and no game is open. Open a game first to use its inning, count, score and players.",
            primaryTitle: "OK",
            primaryAction: {},
            secondaryTitle: "Cancel"
        )
        .overlay {
            if isApplyingCaption {
                GameCaptionWorkingOverlay(text: "Adding game info…")
            }
        }
        .sheet(isPresented: $showTagPlayers) {
            MomentPlayerTagSheet(
                initialTags: moment.playerTags ?? [],
                onSave: { tags in
                    showTagPlayers = false
                    saveTags(tags)
                },
                onCancel: { showTagPlayers = false }
            )
            .environmentObject(authManager)
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveMomentToFolderView(moment: moment, onMoved: refreshMoment)
                .environmentObject(authManager)
        }
        .appConfirmationDialog(
            isPresented: $showDeleteConfirm,
            title: "Delete \(moment.displayTitle)?",
            message: "This removes it from PitchMark. The video can't be recovered afterward unless you save a copy first.",
            primaryTitle: "Delete",
            primaryRole: .destructive,
            primaryAction: { deleteThisMoment(saveFirst: false) },
            secondaryTitle: "Cancel",
            alternateTitle: "Save to Camera Roll, then Delete",
            alternateAction: { deleteThisMoment(saveFirst: true) }
        )
        .appConfirmationDialog(
            isPresented: $showRevertConfirm,
            title: "Revert to Original?",
            message: "Every edit on \(moment.displayTitle) is removed - trim, speed, zoom, crop, freeze frame, filters, overlays, markup, audio and fades - and it goes back to the video as recorded. Its photos stay. Duplicate it first to keep this version.",
            primaryTitle: "Revert",
            primaryRole: .destructive,
            primaryAction: { revertThisMoment() },
            secondaryTitle: "Cancel"
        )
        .sheet(item: $shareRequest) { request in
            ShareSheet(items: request.items)
                .presentationDetents([.medium, .large])
        }
        .appConfirmationDialog(
            isPresented: $showNothingToShare,
            title: "Nothing to Share Here",
            message: "This Moment's video and photos are on the device that recorded it.",
            primaryTitle: "OK",
            primaryAction: {},
            secondaryTitle: "Cancel"
        )
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

    private var moreMenu: some View {
        Menu {
            Button { showMoveSheet = true } label: { Label("Move to Folder…", systemImage: "folder") }
            Button { duplicateThisMoment(fromOriginal: false) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            if momentHasEdits(momentId) {
                Button { duplicateThisMoment(fromOriginal: true) } label: { Label("Duplicate Original", systemImage: "film") }
                Button { showRevertConfirm = true } label: { Label("Revert to Original", systemImage: "arrow.uturn.backward") }
            }
            Divider()
            Button(role: .destructive) { showDeleteConfirm = true } label: { Label("Delete", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("momentDetail.more")
    }

    /// Who this Moment is about (PlayerMoments.swift) - shows on their
    /// stats sheets and in the library's Player filter.
    private var playersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Players")
                    .font(.headline)
                Spacer()
                Button {
                    showTagPlayers = true
                } label: {
                    Label((moment.playerTags ?? []).isEmpty ? "Tag Players" : "Edit", systemImage: "person.badge.plus")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityIdentifier("momentDetail.tagPlayers")
            }
            let tags = moment.playerTags ?? []
            if tags.isEmpty {
                Text("Tag the players in this Moment to find it on their stats.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Label(tag.name, systemImage: tag.pitcherId != nil && tag.hitterId == nil ? "baseball" : "person.fill")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.pitchMarkActiveGray.opacity(0.14)))
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }

    private func saveTags(_ tags: [MomentPlayerTag]) {
        moment.playerTags = tags
        let value: Any = tags.isEmpty ? FieldValue.delete() : tags.compactMap { try? Firestore.Encoder().encode($0) }
        authManager.updateMomentFields(momentId: momentId, fields: ["playerTags": value]) { error in
            if let error { actionMessage = "Couldn't save the players: \(error.localizedDescription)" }
            refreshMoment()
        }
    }

    private struct CaptionContextBox: Identifiable {
        let id = UUID()
        let context: MomentGameContext
    }

    /// The game saved with the Moment, else the one open now.
    private func openGameInfo() {
        player?.pause()
        if let context = moment.gameContext ?? currentGameContext?() {
            captionSheet = CaptionContextBox(context: context)
        } else {
            showNoGameInfo = true
        }
    }

    /// nil options removes the caption.
    private func applyCaption(_ options: GameCaptionOptions?, context: MomentGameContext) {
        isApplyingCaption = true
        actionMessage = nil
        let needsTags = (moment.playerTags ?? []).isEmpty
        GameCaptionApplier.apply(momentId: momentId, context: context, options: options, authManager: authManager) { error in
            isApplyingCaption = false
            if let error {
                actionMessage = "Couldn't update the game info: \(error.localizedDescription)"
            }
            // A Moment given the open game's info is about its players too.
            let tags = GameCaption.playerTags(from: context)
            if needsTags, !tags.isEmpty {
                let encoded = tags.compactMap { try? Firestore.Encoder().encode($0) }
                authManager.updateMomentFields(momentId: momentId, fields: ["playerTags": encoded]) { _ in refreshMoment() }
            }
            reloadPlayer()
            refreshMoment()
        }
    }

    private func duplicateThisMoment(fromOriginal: Bool) {
        actionMessage = nil
        MomentActions.duplicate(moment, fromOriginal: fromOriginal, authManager: authManager) { result in
            switch result {
            case .success: actionMessage = fromOriginal ? "Duplicated the original into your library." : "Duplicated into your library."
            case .failure(let error): actionMessage = "Couldn't duplicate: \(error.localizedDescription)"
            }
        }
    }

    private func revertThisMoment() {
        actionMessage = nil
        MomentActions.revertToOriginal(moment, authManager: authManager) { error in
            if let error {
                actionMessage = "Couldn't revert: \(error.localizedDescription)"
            }
            fadeInEnabled = false
            fadeOutEnabled = false
            reloadPlayer()
            refreshMoment()
        }
    }

    private func deleteThisMoment(saveFirst: Bool) {
        actionMessage = nil
        let done: (Error?) -> Void = { error in
            if let error {
                actionMessage = error.localizedDescription
            } else {
                dismiss()
            }
        }
        if saveFirst {
            MomentActions.saveThenDelete(moment, authManager: authManager, completion: done)
        } else {
            MomentActions.delete(moment, authManager: authManager, completion: done)
        }
    }

    @ViewBuilder
    private var playbackSection: some View {
        if let player {
            VideoPlayer(player: player)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        // The fullscreen cover builds its OWN separate
                        // AVPlayer (MomentPlaybackView) from the same
                        // file - if this inline player was already
                        // playing, nothing stopped it once hidden behind
                        // the cover, so both played audio at once.
                        // Reported by the user as two overlapping audio
                        // tracks during Freeze Frame review.
                        player.pause()
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
        } else if !hasLocalMedia {
            // Explains the gap rather than leaving a blank space where the
            // player would be - this Moment's metadata synced here via
            // Firestore, but its video is local-only to whatever device
            // recorded it (see `hasLocalMedia`'s doc comment).
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.icloud")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("This Moment was recorded on another device")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Its video isn't available here. Open it on the device it was recorded on to view or edit it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        Text(moment.createdAt.formatted(date: .abbreviated, time: .shortened))
            .font(.caption)
            .foregroundStyle(.secondary)
        if let actionMessage {
            Text(actionMessage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
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

    // E (2026-11-15): grouped, with icons, and every applied edit marked.
    private var speedApplied: Bool { !(moment.speedKeyframes ?? []).isEmpty }
    private var zoomApplied: Bool { !(moment.zoomRegions ?? []).isEmpty }
    private var overlaysApplied: Bool { !(moment.overlays ?? []).isEmpty }
    private var audioApplied: Bool {
        !(moment.audioOverlays ?? []).isEmpty
            || (moment.originalAudioVolume.map { $0 != 1 } ?? false)
            || !(moment.originalVolumeKeyframes ?? []).isEmpty
            || !(moment.originalMuteRegions ?? []).isEmpty
    }

    private func editGroupHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 4)
    }

    private var editActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            editGroupHeader("Clip")
            LazyVGrid(columns: editActionColumns, spacing: 10) {
                editActionButton("Trim", icon: "scissors") { startTrimEditor() }
                editActionButton("Speed", icon: "speedometer", caption: speedApplied ? "On" : nil) { showSpeedEditor = true }
                editActionButton("Zoom", icon: "plus.magnifyingglass", caption: zoomApplied ? "On" : nil) { showZoomEditor = true }
                editActionButton("Crop", icon: "crop", caption: cropCaption) { showCropEditor = true }
                editActionButton("Freeze Frame", icon: "pause.rectangle", caption: moment.freezeFrame != nil ? "On" : nil) {
                    player?.pause()
                    showFreezeEditor = true
                }
            }
            editGroupHeader("Look")
            LazyVGrid(columns: editActionColumns, spacing: 10) {
                editActionButton("Filters", icon: "camera.filters", caption: filterCaption) { showFilterEditor = true }
                fadeGridCell
            }
            editGroupHeader("Add")
            LazyVGrid(columns: editActionColumns, spacing: 10) {
                editActionButton("Overlays", icon: "textformat", caption: overlaysApplied ? "\(moment.overlays?.count ?? 0) added" : nil) {
                    authManager.loadLibraryAssets { assets in
                        overlayEditorAssets = assets
                        showOverlayEditor = true
                    }
                }
                editActionButton("Markup", icon: "pencil.tip.crop.circle", caption: markupCaption) { showMarkupEditor = true }
                editActionButton("Audio", icon: "music.note", caption: audioApplied ? "On" : nil) { showAudioEditor = true }
                editActionButton("Game Info", icon: "sportscourt", caption: moment.gameCaption != nil ? "On" : nil) {
                    openGameInfo()
                }
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
    private func editActionButton(_ title: String, icon: String, caption: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if let caption {
                        Text(caption)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.pitchMarkActiveGray)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if caption != nil {
                    Circle()
                        .fill(Color.pitchMarkActiveGray)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel("Applied")
                }
            }
            .actionTileStyle()
        }
        .buttonStyle(.plain)
    }

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
        // `resolvedMomentPlaybackURL` always resolves to SOME path, even
        // when nothing was ever saved to this device - see
        // `momentVideoExistsLocally`'s doc comment (Moment.swift). Without
        // this guard, a Moment synced from another device got handed to
        // AVPlayer anyway, which just failed async and sat stuck mid-load
        // with no explanation - `hasLocalMedia` is what drives
        // `playbackSection`'s banner instead.
        // Pause whatever's already here BEFORE replacing it. Freeze's own
        // export path calls `onExported` (= this) twice in quick
        // succession by design - once immediately, once again when an
        // async fade rebake lands (see MomentAudioEditorView.swift's
        // identical comment on why) - and reassigning `player` doesn't
        // guarantee the OLD AVPlayer instance stops producing audio the
        // instant it loses this reference. Reported by the user as two
        // overlapping audio tracks right around a freeze's hold-end.
        player?.pause()
        guard hasLocalMedia, let url = resolvedMomentPlaybackURL(for: momentId) else {
            player = nil
            return
        }
        player = AVPlayer(url: cacheBustedPlaybackURL(url))
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
