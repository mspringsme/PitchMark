//
//  AudioAssetLibraryView.swift
//  PitchMark
//
//  2026-09-28: mirrors AssetLibraryView.swift's list/rename/delete
//  structure for audio instead of images, plus a "picker mode" (onPick
//  set) MomentAudioEditorView's "Add Audio" flow uses - tapping an asset
//  adds it directly instead of opening the tap-menu dialog every other
//  library screen in this app uses (per the same "swipe stays Delete-
//  only, tap opens a menu" feedback already applied to the image
//  library).
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI
import AVFoundation

struct AudioAssetLibraryView: View {
    var onPick: ((AudioAssetItem) -> Void)? = nil
    /// true when hosted inside `AssetLibraryHubView`'s own NavigationView
    /// + segmented switcher - skips this view's own NavigationView/title/
    /// Done button so there's only ever one nav bar on screen. false (the
    /// default) keeps this view fully self-contained, e.g. the "Add
    /// Audio" picker sheet MomentAudioEditorView presents.
    var embedded: Bool = false

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var audioAssets: [AudioAssetItem] = []
    @State private var showRecorder = false
    @State private var showMicDeniedDialog = false

    @State private var assetPendingAction: AudioAssetItem? = nil
    @State private var showAudioActionsDialog = false

    @State private var renamingAsset: AudioAssetItem? = nil
    @State private var renameText = ""

    @State private var assetPendingDelete: AudioAssetItem? = nil
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
                Button("Rename") {
                    renamingAsset = asset
                    renameText = asset.name
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
            }

            Section("Library") {
                if audioAssets.isEmpty {
                    Text("No audio yet. Record one above.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(audioAssets) { asset in
                        assetRow(asset)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    assetPendingDelete = asset
                                    showDeleteDialog = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }

                if let deleteErrorMessage {
                    Text(deleteErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private func assetRow(_ asset: AudioAssetItem) -> some View {
        Button {
            if let onPick {
                onPick(asset)
                dismiss()
            } else {
                assetPendingAction = asset
                showAudioActionsDialog = true
            }
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
        authManager.loadAudioAssets { audioAssets = $0 }
    }

    private func togglePreview(_ asset: AudioAssetItem) {
        if playingAssetId == asset.id {
            previewPlayer?.stop()
            previewPlayer = nil
            playingAssetId = nil
            return
        }
        guard let id = asset.id, let url = localAudioAssetURL(for: id) else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.play()
            previewPlayer = player
            playingAssetId = id
        } catch {
            debugLog("❌ audio preview failed:", error.localizedDescription)
        }
    }

    private func commitRename() {
        guard let asset = renamingAsset, let assetId = asset.id else {
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
        guard let asset = assetPendingDelete, let assetId = asset.id else { return }
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
