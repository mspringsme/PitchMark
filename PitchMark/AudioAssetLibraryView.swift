//
//  AudioAssetLibraryView.swift
//  PitchMark
//
//  2026-09-28: mirrors AssetLibraryView.swift's list/rename/delete
//  structure for audio instead of images, plus a "picker mode" (onPick
//  set) MomentAudioEditorView's "Add Audio" flow uses.
//
//  2026-09-30: picker mode used to add an asset immediately on tap, with
//  no way to hear it first. Now every mode routes through the same
//  tap-opens-a-dialog convention this app already uses elsewhere (per
//  the "swipe stays Delete-only, tap opens a menu" feedback) - Play is
//  always offered, and picker mode adds one more explicit option, Add,
//  so previewing and committing are two separate steps instead of one.
//
//  Works from `[LibraryAudioAsset]` (AudioAssetItem.swift), not
//  `[AudioAssetItem]` directly, so bundled default sounds (added later
//  the same day) show up identically to user-recorded ones - `Rename`
//  and swipe-to-delete are gated on `isRenamable`/`isDeletable`, false
//  for anything bundled, same as AssetLibraryView's own bundled Circle/
//  Arrow handling.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI
import AVFoundation

struct AudioAssetLibraryView: View {
    var onPick: ((LibraryAudioAsset) -> Void)? = nil
    /// true when hosted inside `AssetLibraryHubView`'s own NavigationView
    /// + segmented switcher - skips this view's own NavigationView/title/
    /// Done button so there's only ever one nav bar on screen. false (the
    /// default) keeps this view fully self-contained, e.g. the "Add
    /// Audio" picker sheet MomentAudioEditorView presents.
    var embedded: Bool = false

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var audioAssets: [LibraryAudioAsset] = []
    @State private var showRecorder = false
    @State private var showMicDeniedDialog = false
    @State private var showMixCreator = false

    @State private var assetPendingAction: LibraryAudioAsset? = nil
    @State private var showAudioActionsDialog = false

    @State private var renamingAsset: LibraryAudioAsset? = nil
    @State private var renameText = ""

    @State private var assetPendingDelete: LibraryAudioAsset? = nil
    @State private var showDeleteDialog = false
    @State private var deleteErrorMessage: String? = nil

    @State private var playingAssetId: String? = nil
    @State private var previewPlayer: AVAudioPlayer? = nil

    var body: some View {
        Group {
            if embedded {
                listContent
            } else {
                NavigationView {
                    listContent
                        .navigationTitle(onPick != nil ? "Add Audio" : "Audio Library")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { dismiss() }
                            }
                        }
                }
            }
        }
        .onAppear { refreshAssets() }
        .onDisappear { previewPlayer?.stop() }
        .sheet(isPresented: $showRecorder) {
            AudioRecorderView(
                onSave: {
                    showRecorder = false
                    refreshAssets()
                },
                onCancel: { showRecorder = false }
            )
            .environmentObject(authManager)
        }
        .sheet(isPresented: $showMixCreator) {
            AudioMixCreatorView(onSaved: { refreshAssets() })
                .environmentObject(authManager)
        }
        .appConfirmationDialog(
            isPresented: $showMicDeniedDialog,
            title: "Microphone Access Needed",
            message: "Enable Microphone access in Settings to record audio.",
            primaryTitle: "Open Settings",
            primaryAction: {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            },
            secondaryTitle: "Cancel"
        )
        .confirmationDialog(
            assetPendingAction?.name ?? "Audio",
            isPresented: $showAudioActionsDialog,
            titleVisibility: .visible
        ) {
            if let asset = assetPendingAction {
                Button(playingAssetId == asset.id ? "Stop" : "Play") {
                    togglePreview(asset)
                }
                // Picker mode (Add Audio from MomentAudioEditorView) -
                // 2026-09-30: tapping a row used to add it immediately
                // with no way to hear it first. Routing through this
                // same dialog (already used for non-picker mode) lets
                // Play run first; tapping Add is now the explicit
                // second step that actually commits it.
                if let onPick {
                    Button("Add") {
                        onPick(asset)
                        dismiss()
                    }
                }
                if asset.isRenamable {
                    Button("Rename") {
                        renamingAsset = asset
                        renameText = asset.name
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                assetPendingAction = nil
            }
        }
        .alert("Rename Audio", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameText)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) { renamingAsset = nil }
        }
        .appConfirmationDialog(
            isPresented: $showDeleteDialog,
            title: "Delete \(assetPendingDelete?.name ?? "this audio")?",
            message: "This removes it from your library. Any Moment already using it will lose the clip.",
            primaryTitle: "Delete",
            primaryRole: .destructive,
            primaryAction: { deletePendingAsset() },
            secondaryTitle: "Cancel"
        )
    }

    private var listContent: some View {
        List {
            Section {
                Button {
                    requestAudioRecordingAccess { authorization in
                        switch authorization {
                        case .ready: showRecorder = true
                        case .denied: showMicDeniedDialog = true
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "mic.badge.plus")
                        Text("Record Audio")
                    }
                }

                // Not offered in picker mode (onPick set) - picking a
                // clip for a mix-in-progress shouldn't surface a nested
                // "start another mix" option.
                if onPick == nil {
                    Button {
                        showMixCreator = true
                    } label: {
                        HStack {
                            Image(systemName: "waveform.badge.plus")
                            Text("Create Mix")
                        }
                    }
                }
            }

            if !sfxAssets.isEmpty {
                Section("SFX") {
                    assetRows(sfxAssets)
                }
            }

            if !musicAssets.isEmpty {
                Section("Music") {
                    assetRows(musicAssets)
                }
            }

            Section("My Recordings") {
                if myRecordings.isEmpty {
                    Text("No recordings yet. Record one above.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    assetRows(myRecordings)
                }

                if let deleteErrorMessage {
                    Text(deleteErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    /// Bundled clips are grouped by category (from the manifest);
    /// user-recorded ones (no category) get their own section - same
    /// row/dialog/swipe-delete behavior in every section, just grouped.
    private var sfxAssets: [LibraryAudioAsset] { audioAssets.filter { $0.category == "sfx" } }
    private var musicAssets: [LibraryAudioAsset] { audioAssets.filter { $0.category == "music" } }
    private var myRecordings: [LibraryAudioAsset] { audioAssets.filter { $0.category == nil } }

    private func assetRows(_ assets: [LibraryAudioAsset]) -> some View {
        ForEach(assets) { asset in
            assetRow(asset)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if asset.isDeletable {
                        Button(role: .destructive) {
                            assetPendingDelete = asset
                            showDeleteDialog = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private func assetRow(_ asset: LibraryAudioAsset) -> some View {
        Button {
            // Same dialog either way now (see the confirmationDialog's
            // own comment) - picker mode used to add on tap immediately,
            // with no way to hear the sound first.
            assetPendingAction = asset
            showAudioActionsDialog = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: playingAssetId == asset.id ? "waveform.circle.fill" : "waveform.circle")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name)
                        .font(.subheadline.weight(.semibold))
                    Text(formattedDuration(asset.durationSeconds))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !asset.isDeletable {
                    Text("Bundled")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// `.alert(_:isPresented:)` needs a plain Bool binding; this wraps the
    /// optional `renamingAsset` so dismissing the alert clears it
    /// consistently from one place.
    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingAsset != nil },
            set: { newValue in if !newValue { renamingAsset = nil } }
        )
    }

    private func refreshAssets() {
        authManager.loadLibraryAudioAssets { audioAssets = $0 }
    }

    private func togglePreview(_ asset: LibraryAudioAsset) {
        if playingAssetId == asset.id {
            previewPlayer?.stop()
            previewPlayer = nil
            playingAssetId = nil
            return
        }
        guard let url = asset.fileURL else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.play()
            previewPlayer = player
            playingAssetId = asset.id
        } catch {
            debugLog("❌ audio preview failed:", error.localizedDescription)
        }
    }

    private func commitRename() {
        guard let asset = renamingAsset, let assetId = asset.backingAssetId else {
            renamingAsset = nil
            return
        }
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        renamingAsset = nil
        guard !trimmed.isEmpty else { return }
        authManager.updateAudioAssetFields(assetId: assetId, fields: ["name": trimmed]) { _ in
            refreshAssets()
        }
    }

    private func deletePendingAsset() {
        guard let asset = assetPendingDelete, let assetId = asset.backingAssetId else { return }
        assetPendingDelete = nil
        deleteErrorMessage = nil
        authManager.deleteAudioAsset(assetId: assetId) { error in
            if let error {
                deleteErrorMessage = "Couldn't delete: \(error.localizedDescription)"
                return
            }
            removeLocalAudioAsset(assetId: assetId)
            refreshAssets()
        }
    }
}
