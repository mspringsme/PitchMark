//
//  MomentsLibraryView.swift
//  PitchMark
//
//  Phase 6 - the real Moments screen, replacing the
//  ComingSoonSheetView(area: .moments, ...) placeholder wired up in Phase 2
//  step 2. "Capture now, create later": recording ends with one mandatory
//  action (save), nothing else required before the clip lands in the
//  library. Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this UI.
//
//  "Import from Photos" (2026-09-28) covers the case where a user
//  recorded with the system Camera app instead of the in-app record
//  button - picks an existing video via PhotosPicker and runs it through
//  the exact same saveRecordedMoment path a fresh recording uses, so it
//  becomes a real Moment (owner-copy sync, overlays, trim, export, all
//  of it) rather than a second, lesser way to add one.
//
//  2026-10-03: the picker now also accepts photos, and multiple items at
//  once - previously photos could only be attached *after* a Moment
//  already existed (MomentDetailView's own PhotosPicker), which forced
//  "add a video first" even when the user just wanted a photo slideshow.
//  Picking only photos builds a real video out of them
//  (`buildVideoFromPhotos`, MomentPhotoVideoBuilder.swift) so the rest of
//  the app keeps working exactly as before - it's still a Moment with a
//  real backing video, just one this screen generated instead of the
//  user recording it. `Moment.momentKind` records which case happened.
//
//  2026-10-06: picking more than one item now asks whether to combine
//  everything into one Moment (`importMedia`, the original behavior) or
//  import each item as its own separate Moment (`importMediaSeparately`)
//  - a single item has nothing to combine with, so that choice is only
//  asked when it's actually ambiguous.
//

import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

/// Bridges a PhotosPicker-selected video into a local temp file PitchMark
/// owns - `FileRepresentation` streams the asset to disk rather than
/// loading it into memory as `Data`, the standard Transferable shape for
/// picking video (as opposed to the plain `Data` transferable
/// `AssetLibraryView`'s Photos import uses for still images, which are
/// small enough not to need this).
private struct MomentVideoTransfer: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { transfer in
            SentTransferredFile(transfer.url)
        } importing: { received in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination)
        }
    }
}

struct MomentsLibraryView: View {
    /// When opened from inside the Parent Game Shell for a specific child,
    /// new recordings auto-tag that child. When opened from the general
    /// tab bar (no child in context), they save untagged rather than
    /// blocking recording on a picker first - nothing else is mandatory.
    var contextPlayer: TeamPlayer? = nil
    var contextTeamId: String? = nil
    var onSwitchToArea: ((HomeArea) -> Void)? = nil

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var moments: [Moment] = []
    @State private var showAssetLibrary = false
    @State private var showCameraPicker = false
    @State private var showCameraDeniedDialog = false
    @State private var selectedMomentForDetail: Moment? = nil
    @State private var isSaving = false
    /// Default-on; persisted so the user's choice carries across launches.
    /// Read by `saveRecordedMoment` to decide whether to ask
    /// `MomentLocationTagger` for a city name before saving.
    @AppStorage("momentsTagLocationEnabled") private var tagLocation = true

    @State private var momentPendingAction: Moment? = nil
    @State private var showMomentActionsDialog = false
    @State private var momentForPlayback: Moment? = nil
    @State private var duplicateErrorMessage: String? = nil
    @State private var momentPendingMove: Moment? = nil

    private enum MomentsLibraryTab {
        case all
        case folders
    }
    @State private var libraryTab: MomentsLibraryTab = .folders
    @State private var showCreateFolder = false

    @State private var mediaPickerSelections: [PhotosPickerItem] = []
    @State private var isImportingMedia = false
    @State private var importMediaErrorMessage: String? = nil
    /// Set only while asking "combine or import separately" - cleared
    /// (by whichever button, Cancel included) once that's answered.
    /// Asked only for a multi-item pick; a single item has no such
    /// choice to make.
    @State private var mediaItemsPendingImportChoice: [PhotosPickerItem] = []
    @State private var showImportCombineDialog = false

    @State private var momentPendingDelete: Moment? = nil
    @State private var showDeleteDialog = false
    @State private var deleteErrorMessage: String? = nil

    // Highlight Reel multi-select - MomentsLibraryView had no multi-select
    // of any kind before this; a reel's clip order defaults to whatever
    // order they're selected in here (library display order, newest-first
    // per loadMoments), then HighlightReelEditorView lets the user drag to
    // reorder before exporting.
    @State private var isSelectingForReel = false
    @State private var selectedMomentIdsForReel: Set<String> = []
    @State private var showHighlightReelEditor = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        recordButton
                        importVideoButton
                        assetsButton
                    }

                    Button {
                        tagLocation.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tagLocation ? "checkmark.square.fill" : "square")
                                .foregroundStyle(tagLocation ? Color.pitchMarkActiveGray : Color.secondary)
                            Text("Tag Moments with the nearest city")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let player = contextPlayer {
                        Text("New Moments will be tagged with \(player.name).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let deleteErrorMessage {
                        Text(deleteErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let importMediaErrorMessage {
                        Text(importMediaErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let duplicateErrorMessage {
                        Text(duplicateErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if !isSelectingForReel {
                        HStack(spacing: 24) {
                            CapsuleSegmentedControl(
                                options: [("All", MomentsLibraryTab.all), ("Folders", MomentsLibraryTab.folders)],
                                selection: $libraryTab
                            )

                            Button {
                                showCreateFolder = true
                            } label: {
                                Image(systemName: "folder.badge.plus")
                                    .font(.title3)
                            }
                            .disabled(libraryTab != .folders)
                            .foregroundStyle(libraryTab == .folders ? Color.pitchMarkActiveGray : Color.secondary)
                            .opacity(libraryTab == .folders ? 1 : 0.4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 16)

                        Divider()
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Group {
                    if libraryTab == .all || isSelectingForReel {
                        MomentGridView(
                            moments: moments,
                            isSelecting: isSelectingForReel,
                            selectedMomentIds: selectedMomentIdsForReel,
                            emptyMessage: "No Moments yet. Record one above.",
                            onTap: { moment in
                                if isSelectingForReel {
                                    toggleReelSelection(moment)
                                } else {
                                    momentPendingAction = moment
                                    showMomentActionsDialog = true
                                }
                            }
                        )
                    } else {
                        MomentFoldersView(
                            moments: moments,
                            onOpenMoment: { moment in
                                momentPendingAction = moment
                                showMomentActionsDialog = true
                            },
                            onMomentsNeedRefresh: refreshMoments,
                            showCreateFolder: $showCreateFolder
                        )
                        .environmentObject(authManager)
                    }
                }
            }
            .navigationTitle("Moments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isSelectingForReel {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            isSelectingForReel = false
                            selectedMomentIdsForReel = []
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSelectingForReel {
                        Button("Create Reel (\(selectedMomentIdsForReel.count))") {
                            showHighlightReelEditor = true
                        }
                        .disabled(selectedMomentIdsForReel.isEmpty)
                    } else {
                        Button("Select") {
                            // Reel multi-select always operates on the
                            // flat list, never a Folder/Bucket subset.
                            libraryTab = .all
                            isSelectingForReel = true
                        }
                        .disabled(moments.isEmpty)
                    }
                }
                if !isSelectingForReel {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HomeAreaTabBar(current: .moments) { selected in
                    onSwitchToArea?(selected)
                    dismiss()
                }
            }
        }
        .onAppear { refreshMoments() }
        .onChange(of: mediaPickerSelections) { _, items in
            guard !items.isEmpty else { return }
            // Only a multi-item pick is actually ambiguous - one item
            // has nothing to combine with, so there's nothing to ask.
            if items.count > 1 {
                mediaItemsPendingImportChoice = items
                showImportCombineDialog = true
            } else {
                importMedia(items)
            }
        }
        .confirmationDialog(
            "Combine these \(mediaItemsPendingImportChoice.count) items into one Moment, or import each separately?",
            isPresented: $showImportCombineDialog,
            titleVisibility: .visible
        ) {
            Button("Combine into One Moment") {
                importMedia(mediaItemsPendingImportChoice)
                mediaItemsPendingImportChoice = []
            }
            Button("Import Separately") {
                importMediaSeparately(mediaItemsPendingImportChoice)
                mediaItemsPendingImportChoice = []
            }
            Button("Cancel", role: .cancel) {
                mediaPickerSelections = []
                mediaItemsPendingImportChoice = []
            }
        }
        .sheet(isPresented: $showAssetLibrary) {
            AssetLibraryHubView()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showCameraPicker) {
            // Shutter photos always become their own individual
            // `.photoCreation` Moments (saveCapturedPhotosAsIndividualMoments
            // below), never attached to the recorded video directly -
            // attaching an existing Moments-gallery photo to a specific
            // video is instead a deliberate action taken from that
            // video's own Photos section (MomentDetailView's "From
            // Moments Library" picker).
            MomentCameraPicker { url, duration, photos in
                showCameraPicker = false
                if let url {
                    saveRecordedMoment(from: url, duration: duration, capturedPhotos: [])
                }
                if !photos.isEmpty {
                    saveCapturedPhotosAsIndividualMoments(photos)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $selectedMomentForDetail, onDismiss: { refreshMoments() }) { moment in
            MomentDetailView(moment: moment, allMoments: moments)
        }
        .sheet(item: $momentPendingMove) { moment in
            MoveMomentToFolderView(moment: moment, onMoved: refreshMoments)
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showHighlightReelEditor, onDismiss: {
            isSelectingForReel = false
            selectedMomentIdsForReel = []
        }) {
            HighlightReelEditorView(initialMoments: momentsSelectedForReel, onCreated: refreshMoments)
                .environmentObject(authManager)
        }
        .fullScreenCover(item: $momentForPlayback) { moment in
            if let id = moment.id, let url = resolvedMomentPlaybackURL(for: id) {
                MomentPlaybackView(videoURL: url)
            }
        }
        // Tapping a row asks Play-or-Edit rather than jumping straight
        // into MomentDetailView - Play is a dedicated, landscape-capable
        // full-bleed viewer (MomentPlaybackView) with none of
        // MomentDetailView's editing chrome.
        .confirmationDialog(
            momentPendingAction?.displayTitle ?? "Moment",
            isPresented: $showMomentActionsDialog,
            titleVisibility: .visible
        ) {
            Button("Play") {
                momentForPlayback = momentPendingAction
            }
            Button("Edit / View Details") {
                selectedMomentForDetail = momentPendingAction
            }
            if let moment = momentPendingAction {
                Button("Duplicate") {
                    duplicateMoment(moment, fromOriginal: false)
                }
                // Only offered when an edited file actually exists -
                // otherwise "current" and "original" are the same file,
                // and a second, identical option would just be confusing.
                if let id = moment.id, let editedURL = localMomentEditedVideoURL(for: id), FileManager.default.fileExists(atPath: editedURL.path) {
                    Button("Duplicate to Original") {
                        duplicateMoment(moment, fromOriginal: true)
                    }
                }
            }
            Button("Move to Folder…") {
                momentPendingMove = momentPendingAction
            }
            // Grid cells have no swipe-to-delete (a List-only affordance) -
            // Delete lives here instead, reusing the same confirmation
            // flow swipe-to-delete already triggers.
            if let moment = momentPendingAction {
                Button("Delete", role: .destructive) {
                    momentPendingDelete = moment
                    showDeleteDialog = true
                }
            }
            Button("Cancel", role: .cancel) {
                momentPendingAction = nil
            }
        }
        .appConfirmationDialog(
            isPresented: $showCameraDeniedDialog,
            title: "Camera Access Needed",
            message: "Enable Camera access in Settings to record Moments.",
            primaryTitle: "Open Settings",
            primaryAction: {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            },
            secondaryTitle: "Cancel"
        )
        // A 3-option destructive action sheet doesn't fit
        // appConfirmationDialog's primary/secondary shape (that component
        // exists specifically to avoid SwiftUI's .alert(), which squeezes
        // horizontally at large accessibility text sizes - see CLAUDE.md).
        // .confirmationDialog presents as a bottom action sheet with
        // stacked buttons instead, so it doesn't have that problem.
        .confirmationDialog(
            "Delete \(momentPendingDelete?.displayTitle ?? "this Moment")?",
            isPresented: $showDeleteDialog,
            titleVisibility: .visible
        ) {
            Button("Save to Camera Roll, then Delete") {
                saveToCameraRollThenDelete()
            }
            Button("Delete", role: .destructive) {
                deletePendingMoment()
            }
            Button("Cancel", role: .cancel) {
                momentPendingDelete = nil
            }
        } message: {
            Text("This removes it from PitchMark. The video can't be recovered afterward unless you save a copy first.")
        }
    }

    private var recordButton: some View {
        Button {
            requestMomentCameraAccess { authorization in
                switch authorization {
                case .ready: showCameraPicker = true
                case .denied: showCameraDeniedDialog = true
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "video.fill")
                Image(systemName: "slash")
                Image(systemName: "camera.fill")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.pitchMarkActiveGray, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    /// Covers both: a Moment recorded with the system Camera app instead
    /// of `recordButton` above, and a Moment made from photos alone -
    /// `.any(of: [.images, .videos])` lets the picker return either or
    /// both at once. `importMedia` sorts out what was actually picked.
    private var importVideoButton: some View {
        PhotosPicker(selection: $mediaPickerSelections, matching: .any(of: [.images, .videos])) {
            HStack {
                Image(systemName: "square.and.arrow.down")
                Text(isImportingMedia ? "Importing…" : "Import")
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isImportingMedia)
    }

    private var assetsButton: some View {
        Button {
            showAssetLibrary = true
        } label: {
            HStack {
                Image(systemName: "square.3.layers.3d.down.right")
                Text("Assets")
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func isMomentSelectedForReel(_ moment: Moment) -> Bool {
        guard let id = moment.id else { return false }
        return selectedMomentIdsForReel.contains(id)
    }

    private func toggleReelSelection(_ moment: Moment) {
        guard let id = moment.id else { return }
        if selectedMomentIdsForReel.contains(id) {
            selectedMomentIdsForReel.remove(id)
        } else {
            selectedMomentIdsForReel.insert(id)
        }
    }

    /// `moments` is already ordered (newest-first, per loadMoments) -
    /// filtering it preserves that order, which is what seeds
    /// HighlightReelEditorView's initial clip order before the user drags
    /// to reorder.
    private var momentsSelectedForReel: [Moment] {
        moments.filter { isMomentSelectedForReel($0) }
    }

    private func refreshMoments() {
        authManager.loadMoments { moments = $0 }
    }

    private func deletePendingMoment() {
        guard let moment = momentPendingDelete, let id = moment.id else { return }
        momentPendingDelete = nil
        deleteErrorMessage = nil
        authManager.deleteMoment(momentId: id) { error in
            if let error {
                deleteErrorMessage = "Couldn't delete: \(error.localizedDescription)"
                return
            }
            removeAllLocalMomentFiles(momentId: id, photoCount: moment.photoCount ?? 0)
            refreshMoments()
        }
    }

    private func saveToCameraRollThenDelete() {
        guard let moment = momentPendingDelete, let id = moment.id else { return }
        deleteErrorMessage = nil
        saveMomentVideoToCameraRoll(momentId: id) { result in
            switch result {
            case .success:
                deletePendingMoment()
            case .failure(let error):
                momentPendingDelete = nil
                deleteErrorMessage = "Couldn't save to Camera Roll, so nothing was deleted: \(error.localizedDescription)"
            }
        }
    }

    /// Sorts a mixed picker selection into at most one video (first one
    /// found; `FileRepresentation` streams it to a temp file rather than
    /// loading it into memory, the same standard pattern used anywhere
    /// PhotosPicker hands back video) plus any number of photos, then
    /// decides what kind of Moment that makes:
    /// - video (+ maybe photos) -> the existing saveRecordedMoment path,
    ///   `.mixedCreation` if photos came along, else plain `.video`.
    /// - photos only -> `buildVideoFromPhotos` turns them into a real
    ///   video first (MomentPhotoVideoBuilder.swift), so this still ends
    ///   up a completely ordinary Moment to every other screen.
    private func importMedia(_ items: [PhotosPickerItem]) {
        isImportingMedia = true
        importMediaErrorMessage = nil
        Task {
            var videoURL: URL? = nil
            var videoSeconds: Double? = nil
            var photoDatas: [Data] = []
            var photoImages: [UIImage] = []

            for item in items {
                if videoURL == nil, let transfer = try? await item.loadTransferable(type: MomentVideoTransfer.self) {
                    videoURL = transfer.url
                    let asset = AVURLAsset(url: transfer.url)
                    let loadedDuration = try? await asset.load(.duration)
                    videoSeconds = loadedDuration?.seconds.isFinite == true ? loadedDuration!.seconds : nil
                    continue
                }
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    photoDatas.append(data)
                    photoImages.append(image)
                }
            }

            if let videoURL {
                await MainActor.run {
                    isImportingMedia = false
                    mediaPickerSelections = []
                    saveRecordedMoment(from: videoURL, duration: videoSeconds, capturedPhotos: photoDatas, momentKind: photoDatas.isEmpty ? nil : .mixedCreation)
                }
                return
            }

            guard !photoImages.isEmpty else {
                await MainActor.run {
                    isImportingMedia = false
                    importMediaErrorMessage = "Couldn't load that from Photos."
                    mediaPickerSelections = []
                }
                return
            }

            buildVideoFromPhotos(photoImages) { result in
                Task { @MainActor in
                    isImportingMedia = false
                    mediaPickerSelections = []
                    switch result {
                    case .success(let builtURL):
                        saveRecordedMoment(from: builtURL, duration: Double(photoImages.count) * defaultSlideshowPhotoDuration, capturedPhotos: photoDatas, momentKind: .photoCreation)
                    case .failure:
                        importMediaErrorMessage = "Couldn't build a video from those photos."
                    }
                }
            }
        }
    }

    /// The "Import Separately" counterpart to `importMedia` - every
    /// video becomes its own plain Moment, every photo becomes its own
    /// single-photo Moment (`buildVideoFromPhotos` with just that one
    /// image), processed one at a time (not concurrently) so
    /// `isImportingMedia` stays true for the whole batch instead of
    /// flipping false the instant the first item finishes.
    private func importMediaSeparately(_ items: [PhotosPickerItem]) {
        isImportingMedia = true
        importMediaErrorMessage = nil
        Task {
            var anyFailed = false
            for item in items {
                if let transfer = try? await item.loadTransferable(type: MomentVideoTransfer.self) {
                    let asset = AVURLAsset(url: transfer.url)
                    let loadedDuration = try? await asset.load(.duration)
                    let seconds = loadedDuration?.seconds.isFinite == true ? loadedDuration!.seconds : nil
                    await saveRecordedMomentAndWait(from: transfer.url, duration: seconds, capturedPhotos: [], momentKind: nil)
                    continue
                }
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                    anyFailed = true
                    continue
                }
                let built: URL? = await withCheckedContinuation { continuation in
                    buildVideoFromPhotos([image]) { result in
                        continuation.resume(returning: try? result.get())
                    }
                }
                guard let built else {
                    anyFailed = true
                    continue
                }
                await saveRecordedMomentAndWait(from: built, duration: defaultSlideshowPhotoDuration, capturedPhotos: [data], momentKind: .photoCreation)
            }
            await MainActor.run {
                isImportingMedia = false
                mediaPickerSelections = []
                if anyFailed {
                    importMediaErrorMessage = "One or more items couldn't be imported."
                }
            }
        }
    }

    private func saveRecordedMomentAndWait(from tempURL: URL, duration: Double?, capturedPhotos: [Data], momentKind: MomentKind?) async {
        await withCheckedContinuation { continuation in
            saveRecordedMoment(from: tempURL, duration: duration, capturedPhotos: capturedPhotos, momentKind: momentKind) {
                continuation.resume()
            }
        }
    }

    /// Each shutter-captured photo from the live Record screen becomes
    /// its own `.photoCreation` Moment - same `buildVideoFromPhotos` +
    /// `.photoCreation` pattern `importMediaSeparately` uses for picked
    /// photos - so every photo taken via the record button shows up as
    /// its own tile in the catalog. Processed one at a time (not
    /// concurrently), matching `importMediaSeparately`, so `isSaving`
    /// stays true for the whole batch instead of flipping false after
    /// the first photo finishes.
    private func saveCapturedPhotosAsIndividualMoments(_ photos: [Data]) {
        Task {
            for data in photos {
                guard let image = UIImage(data: data) else { continue }
                let built: URL? = await withCheckedContinuation { continuation in
                    buildVideoFromPhotos([image]) { result in
                        continuation.resume(returning: try? result.get())
                    }
                }
                guard let built else { continue }
                await saveRecordedMomentAndWait(from: built, duration: defaultSlideshowPhotoDuration, capturedPhotos: [data], momentKind: .photoCreation)
            }
        }
    }

    /// `fromOriginal: false` copies whatever's currently playing back
    /// (the faded version if a fade is applied, else the edited file,
    /// else the original - via `resolvedMomentPlaybackURL`, matching
    /// what `MomentPlaybackView`/share/save-to-Camera-Roll show);
    /// `fromOriginal: true` copies
    /// the untouched original instead, discarding any trim/overlays/
    /// speed changes baked into an edited file - a way to start fresh
    /// editing again while leaving the current Moment exactly as it is.
    /// Metadata is deliberately NOT cloned (title/favorite/game info/
    /// photos/overlays/speed keyframes) - only player/team context
    /// carries over, matching "capture now, create later": the new
    /// Moment starts as plain, undecorated footage, same as any other
    /// freshly-added one.
    private func duplicateMoment(_ moment: Moment, fromOriginal: Bool) {
        duplicateErrorMessage = nil
        guard let id = moment.id else { return }
        let sourceURL = fromOriginal ? localMomentVideoURL(for: id) : resolvedMomentPlaybackURL(for: id)
        guard let sourceURL, FileManager.default.fileExists(atPath: sourceURL.path) else {
            duplicateErrorMessage = "Couldn't duplicate: video file not found."
            return
        }

        Task {
            let asset = AVURLAsset(url: sourceURL)
            let loadedDuration = try? await asset.load(.duration)
            let seconds = loadedDuration?.seconds.isFinite == true ? loadedDuration!.seconds : moment.durationSeconds

            await MainActor.run {
                let newMoment = Moment(
                    teamId: moment.teamId,
                    playerId: moment.playerId,
                    playerName: moment.playerName,
                    durationSeconds: seconds
                )
                authManager.saveMoment(newMoment) { result in
                    switch result {
                    case .success(let saved):
                        if let newId = saved.id {
                            saveLocalMomentVideo(from: sourceURL, momentId: newId)
                        }
                        refreshMoments()
                    case .failure(let error):
                        duplicateErrorMessage = "Couldn't duplicate: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func saveRecordedMoment(from tempURL: URL, duration: Double?, capturedPhotos: [Data], momentKind: MomentKind? = nil, completion: @escaping () -> Void = {}) {
        isSaving = true

        func finishSaving(cityName: String?) {
            let moment = Moment(
                createdAt: Date(),
                teamId: contextTeamId,
                playerId: contextPlayer?.id,
                playerName: contextPlayer?.name,
                durationSeconds: duration,
                photoCount: capturedPhotos.count,
                momentKind: momentKind,
                cityName: cityName
            )
            authManager.saveMoment(moment) { result in
                isSaving = false
                defer { completion() }
                switch result {
                case .success(let saved):
                    if let id = saved.id {
                        saveLocalMomentVideo(from: tempURL, momentId: id)
                        for (index, data) in capturedPhotos.enumerated() {
                            saveLocalMomentPhoto(data, momentId: id, index: index)
                        }
                    }
                    refreshMoments()
                case .failure(let error):
                    debugLog("❌ saveMoment failed:", error.localizedDescription)
                }
            }
        }

        if tagLocation {
            MomentLocationTagger.shared.fetchCityName { city in
                finishSaving(cityName: city)
            }
        } else {
            finishSaving(cityName: nil)
        }
    }
}
