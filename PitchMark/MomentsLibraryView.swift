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
import FirebaseFirestore

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
    /// The game open in the tracker, as it stands right now - nil when no
    /// game is open (MomentGameCaption.swift).
    var currentGameContext: (() -> MomentGameContext?)? = nil

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
    /// Off by default - unlike location tagging, this triggers a Photos
    /// permission prompt and writes a copy of every newly-recorded/
    /// imported Moment's video into a dedicated "PitchMark" Photos album,
    /// so it shouldn't turn on silently. Read by
    /// `autoBackupMomentVideoToPhotosIfEnabled` (Moment.swift) via the
    /// exact same UserDefaults key string - that's a plain free function,
    /// not a View, so it can't use this `@AppStorage` property directly.
    @AppStorage("momentsAutoBackupToPhotosEnabled") private var autoBackupToPhotos = true
    @State private var showMomentsSettings = false

    @State private var momentForPlayback: Moment? = nil
    /// Tapping a Moment whose video never synced to this device (see
    /// `momentVideoExistsLocally`'s doc comment, Moment.swift) shows this
    /// instead of the normal Play/Edit/Duplicate/Move/Delete action sheet -
    /// every one of those actions needs the local file, Delete most
    /// dangerously: it would remove the Firestore record entirely (the
    /// shared source of truth every device reads), orphaning the video
    /// that's still sitting on whichever device actually has it, with
    /// nothing left pointing to it anywhere.
    @State private var momentPendingOtherDeviceNotice: Moment? = nil
    @State private var showOtherDeviceNotice = false
    @State private var duplicateErrorMessage: String? = nil
    @State private var momentPendingMove: Moment? = nil
    @State private var momentShareRequest: MomentShareRequest? = nil

    private enum MomentsLibraryTab {
        case all
        case folders
    }
    /// Opens on All (2026-11-15): on Folders, a coach with no folders saw
    /// "No folders yet" and their unfiled recordings looked missing.
    @State private var libraryTab: MomentsLibraryTab = .all
    @State private var libraryFilter: MomentLibraryFilter = .all
    /// The Player filter: a tagged player's name, or nil for everyone.
    @State private var playerFilterName: String? = nil
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

    /// After a capture during a game: which new Moments to caption.
    struct CaptionPrompt: Identifiable {
        let id = UUID()
        let momentIds: [String]
        let context: MomentGameContext
    }
    @State private var captionPrompt: CaptionPrompt? = nil

    /// What picking clips is for: a Mixtape, or Compare (exactly two).
    enum SelectIntent { case mixtape, compare }
    @State private var selectIntent: SelectIntent = .mixtape
    struct CompareRequest: Identifiable {
        let id = UUID()
        let a: Moment
        let b: Moment
        let urlA: URL
        let urlB: URL
    }
    @State private var compareRequest: CompareRequest? = nil
    @State private var isApplyingCaption = false
    @State private var captionErrorMessage: String? = nil

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        recordButton
                        importVideoButton
                        assetsButton
                    }

                    // Mixtape (was Highlight Reel) and Compare, 2026-11-15 -
                    // their own buttons rather than only behind Select.
                    if !isSelectingForReel {
                        HStack(spacing: 10) {
                            makeButton("Mixtape", systemImage: "film.stack", id: "moments.mixtape", disabled: moments.isEmpty) {
                                startSelecting(.mixtape)
                            }
                            makeButton("Compare", systemImage: "rectangle.split.2x1", id: "moments.compare", disabled: moments.count < 2) {
                                startSelecting(.compare)
                            }
                        }
                    }

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
                    if let captionErrorMessage {
                        Text(captionErrorMessage)
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
                        .padding(.bottom, libraryTab == .all ? 8 : 16)

                        if libraryTab == .all {
                            HStack(spacing: 8) {
                                playerFilterMenu
                                MomentFilterChips(selection: $libraryFilter)
                            }
                            .padding(.bottom, 8)
                        }

                        Divider()
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Group {
                    if libraryTab == .all || isSelectingForReel {
                        MomentGridView(
                            moments: gridMoments,
                            isSelecting: isSelectingForReel,
                            selectedMomentIds: selectedMomentIdsForReel,
                            emptyMessage: gridEmptyMessage,
                            onTap: { moment in
                                if isSelectingForReel {
                                    guard let id = moment.id, momentVideoExistsLocally(for: id) else {
                                        momentPendingOtherDeviceNotice = moment
                                        showOtherDeviceNotice = true
                                        return
                                    }
                                    toggleReelSelection(moment)
                                } else {
                                    handleMomentTap(moment)
                                }
                            }
                        )
                    } else {
                        MomentFoldersView(
                            moments: moments,
                            onOpenMoment: { moment in
                                handleMomentTap(moment)
                            },
                            onMomentsNeedRefresh: refreshMoments,
                            showCreateFolder: $showCreateFolder
                        )
                        .environmentObject(authManager)
                    }
                }
                .environment(\.momentQuickAction, { moment, action in performQuickAction(action, on: moment) })
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
                } else {
                    // Moved here, out of the main screen's VStack where
                    // they used to sit as always-visible checkboxes - the
                    // user found them too small (plain .caption text
                    // under a custom checkbox icon, not a native control)
                    // and unnecessary to show every time the screen is
                    // open, since both are set-once-and-forget toggles.
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showMomentsSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    if isSelectingForReel {
                        Text(selectIntent == .compare ? "Pick 2 to Compare" : "Pick Mixtape Clips")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSelectingForReel {
                        if selectIntent == .compare {
                            Button("Compare (\(selectedMomentIdsForReel.count)/2)") { openCompare() }
                                .disabled(selectedMomentIdsForReel.count != 2)
                                .accessibilityIdentifier("moments.compare.go")
                        } else {
                            Button("Make Mixtape (\(selectedMomentIdsForReel.count))") {
                                showHighlightReelEditor = true
                            }
                            .disabled(selectedMomentIdsForReel.isEmpty)
                        }
                    }
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
        .appSheet(isPresented: $showAssetLibrary, chrome: .handle) {
            AssetLibraryHubView()
                .environmentObject(authManager)
        }
        .appSheet(isPresented: $showMomentsSettings, chrome: .handle) {
            MomentsSettingsView(tagLocation: $tagLocation, autoBackupToPhotos: $autoBackupToPhotos)
        }
        .appSheet(isPresented: $showCameraPicker, chrome: .none) {
            // Shutter photos always become their own individual
            // `.photoCreation` Moments (saveCapturedPhotosAsIndividualMoments
            // below), never attached to the recorded video directly -
            // attaching an existing Moments-gallery photo to a specific
            // video is instead a deliberate action taken from that
            // video's own Photos section (MomentDetailView's "From
            // Moments Library" picker).
            MomentCameraPicker { url, duration, photos in
                showCameraPicker = false
                // The game as it stood when recording stopped.
                let context = currentGameContext?()
                Task {
                    var ids: [String] = []
                    if let url, let id = await saveRecordedMomentAndWait(
                        from: url, duration: duration, capturedPhotos: [], momentKind: nil,
                        fromCamera: true, gameContext: context
                    ) {
                        ids.append(id)
                    }
                    ids += await saveCapturedPhotosAsIndividualMoments(photos, gameContext: context)
                    guard let context, !ids.isEmpty else { return }
                    // After the camera sheet has finished going away.
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    await MainActor.run {
                        captionPrompt = CaptionPrompt(momentIds: ids, context: context)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .appSheet(item: $selectedMomentForDetail, onDismiss: { refreshMoments() }, chrome: .handle) { moment in
            MomentDetailView(moment: moment, allMoments: moments, currentGameContext: currentGameContext)
        }
        .appSheet(item: $captionPrompt, chrome: .none) { prompt in
            GameCaptionSheet(
                context: prompt.context,
                initialOptions: nil,
                momentCount: prompt.momentIds.count,
                onApply: { options, links in
                    captionPrompt = nil
                    linkPlayers(links, to: prompt.momentIds)
                    applyCaption(options, to: prompt)
                },
                onSkip: { links in
                    captionPrompt = nil
                    linkPlayers(links, to: prompt.momentIds)
                }
            )
            .interactiveDismissDisabled()
        }
        .overlay {
            if isApplyingCaption {
                GameCaptionWorkingOverlay(text: "Updating game info…")
            }
        }
        .appSheet(item: $momentShareRequest, chrome: .none) { request in
            ShareSheet(items: request.items)
                .presentationDetents([.medium, .large])
        }
        .appSheet(item: $momentPendingMove, chrome: .handle) { moment in
            MoveMomentToFolderView(moment: moment, onMoved: refreshMoments)
                .environmentObject(authManager)
        }
        .appSheet(isPresented: $showHighlightReelEditor, onDismiss: {
            isSelectingForReel = false
            selectedMomentIdsForReel = []
        }, chrome: .handle) {
            HighlightReelEditorView(initialMoments: momentsSelectedForReel, onCreated: refreshMoments)
                .environmentObject(authManager)
        }
        .fullScreenCover(item: $compareRequest) { request in
            MomentCompareView(momentA: request.a, momentB: request.b, urlA: request.urlA, urlB: request.urlB) {
                compareRequest = nil
                refreshMoments()
            }
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
        .appConfirmationDialog(
            isPresented: $showOtherDeviceNotice,
            title: "On Another Device",
            message: "\(momentPendingOtherDeviceNotice?.displayTitle ?? "This Moment") was recorded on another device signed into this account. Its video lives only on that device, so it can't be played, edited, moved, or deleted from here. Open PitchMark on the device it was recorded on to work with it.",
            primaryTitle: "OK",
            primaryAction: { momentPendingOtherDeviceNotice = nil },
            secondaryTitle: "Cancel",
            secondaryAction: { momentPendingOtherDeviceNotice = nil }
        )
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

    private func makeButton(_ title: String, systemImage: String, id: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityIdentifier(id)
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

    /// The All tab's clips, after its filter chip (selecting ignores it).
    private var gridMoments: [Moment] {
        if isSelectingForReel { return moments }
        let filtered = libraryFilter.apply(to: moments)
        guard let name = playerFilterName else { return filtered }
        return filtered.filter { PlayerMoments.isTagged($0, name: name) }
    }

    /// Only shown once some Moment is tagged with a player.
    @ViewBuilder
    private var playerFilterMenu: some View {
        let names = PlayerMoments.taggedNames(in: moments)
        if !names.isEmpty {
            Menu {
                Button("Everyone") { playerFilterName = nil }
                ForEach(names, id: \.self) { name in
                    Button(name) { playerFilterName = name }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.caption)
                    Text(playerFilterName ?? "Player")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(playerFilterName == nil ? Color.primary : Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(playerFilterName == nil ? Color(.secondarySystemBackground) : Color.pitchMarkActiveGray))
            }
            .accessibilityIdentifier("moments.filter.player")
        }
    }

    private var gridEmptyMessage: String {
        if moments.isEmpty { return "No Moments yet. Record one above." }
        if let playerFilterName { return "No \(libraryFilter == .all ? "" : libraryFilter.title + " ")Moments of \(playerFilterName)." }
        return "No Moments match \(libraryFilter.title)."
    }

    private func isMomentSelectedForReel(_ moment: Moment) -> Bool {
        guard let id = moment.id else { return false }
        return selectedMomentIdsForReel.contains(id)
    }

    /// Single choke point for every "a Moment tile was tapped" path (the
    /// "All" grid and every Folder/Bucket screen underneath
    /// `MomentFoldersView`, which all funnel through this same
    /// `onOpenMoment` closure) - shows the normal Play/Edit/Duplicate/
    /// Move/Delete action sheet, unless the Moment's video never synced
    /// to this device, in which case it shows `showOtherDeviceNotice`
    /// instead and never reaches the action sheet (Delete included) at
    /// all. See `momentPendingOtherDeviceNotice`'s doc comment above.
    private func handleMomentTap(_ moment: Moment) {
        guard let id = moment.id, momentVideoExistsLocally(for: id) else {
            momentPendingOtherDeviceNotice = moment
            showOtherDeviceNotice = true
            return
        }
        selectedMomentForDetail = moment
    }

    /// A tile's long-press menu (MomentQuickActionMenu).
    private func performQuickAction(_ action: MomentQuickAction, on moment: Moment) {
        // Works for a Moment from another device too - it's only a flag.
        if action == .toggleFavorite {
            guard let id = moment.id else { return }
            let on = !(moment.isFavorite ?? false)
            if let i = moments.firstIndex(where: { $0.id == id }) { moments[i].isFavorite = on }
            MomentFavorite.set(momentId: id, on, authManager: authManager)
            return
        }
        guard let id = moment.id, momentVideoExistsLocally(for: id) else {
            momentPendingOtherDeviceNotice = moment
            showOtherDeviceNotice = true
            return
        }
        switch action {
        case .play:
            momentForPlayback = moment
        case .share:
            DispatchQueue.main.async { momentShareRequest = MomentShare.prepare(moment) }
        case .duplicate:
            duplicateMoment(moment, fromOriginal: false)
        case .duplicateOriginal:
            duplicateMoment(moment, fromOriginal: true)
        case .move:
            momentPendingMove = moment
        case .delete:
            momentPendingDelete = moment
            showDeleteDialog = true
        case .toggleFavorite:
            break
        }
    }

    private func toggleReelSelection(_ moment: Moment) {
        guard let id = moment.id else { return }
        if selectedMomentIdsForReel.contains(id) {
            selectedMomentIdsForReel.remove(id)
        } else if selectIntent == .mixtape || selectedMomentIdsForReel.count < 2 {
            selectedMomentIdsForReel.insert(id)
        }
    }

    /// Picking always works on the whole library, never a folder.
    private func startSelecting(_ intent: SelectIntent) {
        selectIntent = intent
        libraryTab = .all
        selectedMomentIdsForReel = []
        isSelectingForReel = true
    }

    private func openCompare() {
        let picked = momentsSelectedForReel
        guard picked.count == 2,
              let idA = picked[0].id, let idB = picked[1].id,
              let urlA = resolvedMomentPlaybackURL(for: idA),
              let urlB = resolvedMomentPlaybackURL(for: idB) else { return }
        compareRequest = CompareRequest(a: picked[0], b: picked[1], urlA: urlA, urlB: urlB)
        isSelectingForReel = false
        selectedMomentIdsForReel = []
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
        guard let moment = momentPendingDelete else { return }
        momentPendingDelete = nil
        deleteErrorMessage = nil
        MomentActions.delete(moment, authManager: authManager) { error in
            if let error { deleteErrorMessage = "Couldn't delete: \(error.localizedDescription)" }
            refreshMoments()
        }
    }

    private func saveToCameraRollThenDelete() {
        guard let moment = momentPendingDelete else { return }
        momentPendingDelete = nil
        deleteErrorMessage = nil
        MomentActions.saveThenDelete(moment, authManager: authManager) { error in
            if let error { deleteErrorMessage = error.localizedDescription }
            refreshMoments()
        }
    }

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

    @discardableResult
    private func saveRecordedMomentAndWait(
        from tempURL: URL, duration: Double?, capturedPhotos: [Data], momentKind: MomentKind?,
        fromCamera: Bool = false, gameContext: MomentGameContext? = nil
    ) async -> String? {
        await withCheckedContinuation { continuation in
            saveRecordedMoment(from: tempURL, duration: duration, capturedPhotos: capturedPhotos, momentKind: momentKind,
                               fromCamera: fromCamera, gameContext: gameContext) { id in
                continuation.resume(returning: id)
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
    private func saveCapturedPhotosAsIndividualMoments(_ photos: [Data], gameContext: MomentGameContext?) async -> [String] {
        var ids: [String] = []
        for data in photos {
            guard let image = UIImage(data: data) else { continue }
            let built: URL? = await withCheckedContinuation { continuation in
                buildVideoFromPhotos([image]) { result in
                    continuation.resume(returning: try? result.get())
                }
            }
            guard let built else { continue }
            if let id = await saveRecordedMomentAndWait(
                from: built, duration: defaultSlideshowPhotoDuration, capturedPhotos: [data],
                momentKind: .photoCreation, fromCamera: true, gameContext: gameContext
            ) {
                ids.append(id)
            }
        }
        return ids
    }

    /// The players switched on in the Add Game Info sheet.
    private func linkPlayers(_ tags: [MomentPlayerTag], to momentIds: [String]) {
        guard !tags.isEmpty else { return }
        let encoded = tags.compactMap { try? Firestore.Encoder().encode($0) }
        for id in momentIds {
            authManager.updateMomentFields(momentId: id, fields: ["playerTags": encoded]) { _ in }
        }
        refreshMoments()
    }

    /// Bakes the chosen caption into each new Moment, one at a time.
    private func applyCaption(_ options: GameCaptionOptions, to prompt: CaptionPrompt) {
        isApplyingCaption = true
        captionErrorMessage = nil
        Task {
            var failed = 0
            for id in prompt.momentIds {
                let error: Error? = await withCheckedContinuation { continuation in
                    GameCaptionApplier.apply(momentId: id, context: prompt.context, options: options,
                                             authManager: authManager) { continuation.resume(returning: $0) }
                }
                if error != nil { failed += 1 }
            }
            await MainActor.run {
                isApplyingCaption = false
                if failed > 0 {
                    captionErrorMessage = "Couldn't add the game info to \(failed) Moment\(failed == 1 ? "" : "s")."
                }
                refreshMoments()
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
    /// The copy keeps the title, favorite, folder, photos, game and
    /// players (2026-11-15, MomentActions.duplicate); its edit settings
    /// aren't copied - their result is already in the copied video.
    private func duplicateMoment(_ moment: Moment, fromOriginal: Bool) {
        duplicateErrorMessage = nil
        MomentActions.duplicate(moment, fromOriginal: fromOriginal, authManager: authManager) { result in
            if case .failure(let error) = result {
                duplicateErrorMessage = "Couldn't duplicate: \(error.localizedDescription)"
            }
            refreshMoments()
        }
    }

    /// `fromCamera`: recorded or taken in PitchMark, so it's backed up to
    /// Photos (when that's on). Imports came from Photos and aren't copied
    /// back; a photo is backed up as the photo, not its built video.
    private func saveRecordedMoment(
        from tempURL: URL, duration: Double?, capturedPhotos: [Data], momentKind: MomentKind? = nil,
        fromCamera: Bool = false, gameContext: MomentGameContext? = nil,
        completion: @escaping (String?) -> Void = { _ in }
    ) {
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
            var tagged = moment
            if let gameContext {
                // Players aren't linked until the coach switches them on in
                // the Add Game Info sheet (2026-11-16, user's call).
                tagged.gameContext = gameContext
            }
            authManager.saveMoment(tagged) { result in
                isSaving = false
                switch result {
                case .success(let saved):
                    defer { completion(saved.id) }
                    if tagLocation, let id = saved.id {
                        MomentLocationTagger.shared.fetchCityName { city in
                            guard let city else { return }
                            authManager.updateMomentFields(momentId: id, fields: ["cityName": city]) { _ in
                                refreshMoments()
                            }
                        }
                    }
                    if let id = saved.id {
                        saveLocalMomentVideo(from: tempURL, momentId: id,
                                             autoBackupToPhotos: fromCamera && momentKind != .photoCreation)
                        for (index, data) in capturedPhotos.enumerated() {
                            saveLocalMomentPhoto(data, momentId: id, index: index)
                            if fromCamera { autoBackupMomentPhotoToPhotosIfEnabled(data) }
                        }
                    }
                    refreshMoments()
                case .failure(let error):
                    debugLog("❌ saveMoment failed:", error.localizedDescription)
                    completion(nil)
                }
            }
        }

        // Saved now; the city follows when the phone finds it (up to 10s).
        // Waiting for it first held every new clip back (2026-11-16).
        finishSaving(cityName: nil)
    }
}

/// The set-once-and-forget Moments toggles (location tagging, automatic
/// Photos backup) - moved out of the main library screen's always-visible
/// VStack, where they were small custom-drawn checkboxes under `.caption`
/// text (reported by the user as too small, and as clutter that didn't
/// need to be visible every time the screen opened). A native `Toggle` in
/// a `Form` gets normal system sizing/contrast and standard Dynamic Type
/// support for free, which a custom checkbox+Text button didn't.
struct MomentsSettingsView: View {
    @Binding var tagLocation: Bool
    @Binding var autoBackupToPhotos: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("Tag Moments with the nearest city", isOn: $tagLocation)
                } footer: {
                    Text("Uses your location only while recording or importing a Moment.")
                }

                Section {
                    Toggle("Back up new Moments to Photos", isOn: $autoBackupToPhotos)
                } footer: {
                    Text("Saves a copy of each newly recorded or imported Moment's video to your Photos library, so it isn't lost if this phone is. Later edits aren't re-saved - share or save a specific Moment for that.")
                }
            }
            .navigationTitle("Moments Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
