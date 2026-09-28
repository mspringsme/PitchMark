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

    @State private var momentPendingAction: Moment? = nil
    @State private var showMomentActionsDialog = false
    @State private var momentForPlayback: Moment? = nil
    @State private var duplicateErrorMessage: String? = nil

    @State private var videoPickerSelection: PhotosPickerItem? = nil
    @State private var isImportingVideo = false
    @State private var importVideoErrorMessage: String? = nil

    @State private var momentPendingDelete: Moment? = nil
    @State private var showDeleteDialog = false
    @State private var deleteErrorMessage: String? = nil

    var body: some View {
        NavigationView {
            // List, not ScrollView/VStack, specifically so swipe-to-delete
            // (.swipeActions) is available - it's a List row modifier only.
            List {
                Section {
                    recordButton
                    importVideoButton

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
                    if let importVideoErrorMessage {
                        Text(importVideoErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let duplicateErrorMessage {
                        Text(duplicateErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                Section {
                    if moments.isEmpty {
                        Text("No Moments yet. Record one above.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(moments) { moment in
                            Button {
                                momentPendingAction = moment
                                showMomentActionsDialog = true
                            } label: {
                                momentRow(moment)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    momentPendingDelete = moment
                                    showDeleteDialog = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Moments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showAssetLibrary = true
                    } label: {
                        Image(systemName: "square.stack.3d.up")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
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
        .onChange(of: videoPickerSelection) { _, item in
            guard let item else { return }
            importVideo(item)
        }
        .sheet(isPresented: $showAssetLibrary) {
            AssetLibraryView()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showCameraPicker) {
            MomentCameraPicker { url, duration, photos in
                showCameraPicker = false
                if let url {
                    saveRecordedMoment(from: url, duration: duration, capturedPhotos: photos)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $selectedMomentForDetail, onDismiss: { refreshMoments() }) { moment in
            MomentDetailView(moment: moment, allMoments: moments)
        }
        .fullScreenCover(item: $momentForPlayback) { moment in
            if let id = moment.id, let url = resolvedMomentVideoURL(for: id) {
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
            HStack {
                Image(systemName: "video.fill")
                Text(isSaving ? "Saving…" : "Record a Moment")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    /// For a Moment recorded with the system Camera app instead of
    /// `recordButton` above - the `.videos` PhotosPicker filter keeps
    /// photos out of the picker entirely, so there's no wrong-media-type
    /// case to handle.
    private var importVideoButton: some View {
        PhotosPicker(selection: $videoPickerSelection, matching: .videos) {
            HStack {
                Image(systemName: "square.and.arrow.down")
                Text(isImportingVideo ? "Importing…" : "Import from Photos")
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isImportingVideo)
    }

    @ViewBuilder
    private var libraryList: some View {
        if moments.isEmpty {
            Text("No Moments yet. Record one above.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(moments) { moment in
                    Button {
                        selectedMomentForDetail = moment
                    } label: {
                        momentRow(moment)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func momentRow(_ moment: Moment) -> some View {
        HStack {
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(moment.displayTitle)
                        .font(.subheadline.weight(.semibold))
                    if moment.isFavorite == true {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(Color.red)
                    }
                }
                Text(moment.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let duration = moment.durationSeconds {
                Text(formattedDuration(duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
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

    /// Picked video content is best handled as a file, not `Data` -
    /// loading a whole video into memory just to write it back out again
    /// would be wasteful and slow for anything beyond a trivially short
    /// clip. `FileRepresentation` streams the picked asset straight to a
    /// temp file PitchMark owns, the same standard pattern used anywhere
    /// PhotosPicker hands back video.
    private func importVideo(_ item: PhotosPickerItem) {
        isImportingVideo = true
        importVideoErrorMessage = nil
        Task {
            guard let transfer = try? await item.loadTransferable(type: MomentVideoTransfer.self) else {
                await MainActor.run {
                    isImportingVideo = false
                    importVideoErrorMessage = "Couldn't load that video."
                    videoPickerSelection = nil
                }
                return
            }

            let asset = AVURLAsset(url: transfer.url)
            let loadedDuration = try? await asset.load(.duration)
            let seconds = loadedDuration?.seconds.isFinite == true ? loadedDuration!.seconds : nil

            await MainActor.run {
                isImportingVideo = false
                videoPickerSelection = nil
                saveRecordedMoment(from: transfer.url, duration: seconds, capturedPhotos: [])
            }
        }
    }

    /// `fromOriginal: false` copies whatever's currently playing back
    /// (the edited file if one exists, else the original - via
    /// `resolvedMomentVideoURL`, same source every other editor in this
    /// app treats as "the current state"); `fromOriginal: true` copies
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
        let sourceURL = fromOriginal ? localMomentVideoURL(for: id) : resolvedMomentVideoURL(for: id)
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

    private func saveRecordedMoment(from tempURL: URL, duration: Double?, capturedPhotos: [Data]) {
        isSaving = true
        let moment = Moment(
            createdAt: Date(),
            teamId: contextTeamId,
            playerId: contextPlayer?.id,
            playerName: contextPlayer?.name,
            durationSeconds: duration,
            photoCount: capturedPhotos.count
        )
        authManager.saveMoment(moment) { result in
            isSaving = false
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
}
