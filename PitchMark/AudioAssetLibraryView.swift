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
    /// The group chip that's on; nil = All.
    @State private var shownGroup: String? = nil

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

            // Built-in sounds by group (2026-11-15), with chips to show
            // one group at a time, like the overlay icons.
            if groupNames.count > 1 {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            groupChip(nil, title: "All")
                            ForEach(groupNames, id: \.self) { name in
                                groupChip(name, title: name)
                            }
                            groupChip(Self.myRecordingsGroup, title: "My Recordings")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            }

            ForEach(groupNames, id: \.self) { name in
                if shownGroup == nil || shownGroup == name {
                    Section(name) {
                        assetRows(audioAssets.filter { $0.category == name })
                    }
                }
            }

            if shownGroup == nil || shownGroup == Self.myRecordingsGroup {
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
    }

    /// Bundled clips are grouped by the manifest's `category` - a group
    /// name like "Hits & Impacts" (2026-11-15; was just sfx/music).
    /// User-recorded ones (no category) are My Recordings.
    private var myRecordings: [LibraryAudioAsset] { audioAssets.filter { $0.category == nil } }

    static let myRecordingsGroup = "__mine"

    /// Known groups in this order, then any other the manifest names.
    private var groupNames: [String] {
        let present = Set(audioAssets.compactMap(\.category))
        let known = BundledSoundGroup.order.filter { present.contains($0) }
        return known + present.subtracting(known).sorted()
    }

    private func groupChip(_ group: String?, title: String) -> some View {
        let isOn = shownGroup == group
        return Button {
            shownGroup = group
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(isOn ? Color.pitchMarkActiveGray : Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("audioLibrary.group.\(title)")
    }

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

    /// A play/stop button on every row and, when picking audio for a
    /// Moment, an Add button - no pop-up per row (2026-11-16). In the
    /// plain library a row tap still opens Rename and the rest.
    @ViewBuilder
    private func assetRow(_ asset: LibraryAudioAsset) -> some View {
        let isPlaying = playingAssetId == asset.id
        HStack(spacing: 12) {
            Button {
                togglePreview(asset)
            } label: {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.pitchMarkActiveGray)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isPlaying ? "Stop \(asset.name)" : "Play \(asset.name)")
            .accessibilityIdentifier("audioRow.play.\(asset.name)")

            Button {
                if onPick != nil {
                    togglePreview(asset)
                } else {
                    assetPendingAction = asset
                    showAudioActionsDialog = true
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.name)
                            .font(.subheadline.weight(.semibold))
                        Text(formattedDuration(asset.durationSeconds))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if onPick == nil, !asset.isDeletable {
                        Text("Bundled")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onPick {
                Button {
                    previewPlayer?.stop()
                    onPick(asset)
                    dismiss()
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.bold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.pitchMarkActiveGray)
                .accessibilityIdentifier("audioRow.add.\(asset.name)")
            }
        }
        .padding(.vertical, 2)
    }

    private func formattedDuration(_ seconds: Double) -> String {
        // Most built-in effects are under a second - "0:00" said nothing.
        if seconds < 10 { return String(format: "%.1fs", seconds) }
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
