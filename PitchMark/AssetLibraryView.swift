//
//  AssetLibraryView.swift
//  PitchMark
//
//  Step 2 of the 2026-09-26 Asset + Video Overlay Keyframe Editor spec.
//  AssetThumbnailStrip is the reusable "adjacent to the video editor"
//  component the spec calls for - step 3+ wires it into the editor.
//  AssetLibraryView hosts it as a full screen for now, since the editor
//  doesn't exist yet, plus a PhotosPicker "Add from Photos" import (the
//  spec's own sanctioned secondary path - the camera + shape-crop +
//  Smart Cutout flow is step 7) and rename/delete for user-created
//  assets. Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI
import PhotosUI

/// Horizontally-scrolling thumbnail strip - the component the spec wants
/// "adjacent to the video editor." Takes a plain array + selection
/// closure so it has no dependency on where its assets came from.
struct AssetThumbnailStrip: View {
    let assets: [LibraryAsset]
    var onSelect: ((LibraryAsset) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(assets) { asset in
                    Button {
                        onSelect?(asset)
                    } label: {
                        VStack(spacing: 4) {
                            thumbnail(for: asset)
                            Text(asset.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func thumbnail(for asset: LibraryAsset) -> some View {
        Group {
            if let image = asset.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 64)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Which asset's file gets overwritten when `AssetCropView`'s `onSave`
/// fires, plus the image to seed that screen with - the asset's
/// *current* saved image, not the original unedited one, so repeated
/// edits (circle crop, then later Smart Cutout on the result) compose.
private struct AssetEditingTarget: Identifiable {
    let id: String
    let image: UIImage
}

struct AssetLibraryView: View {
    /// true when hosted inside `AssetLibraryHubView`'s own NavigationView
    /// + segmented switcher - skips this view's own NavigationView/title/
    /// Done button so there's only ever one nav bar on screen. false (the
    /// default) keeps this view fully self-contained, its original shape
    /// before the combined hub existed.
    var embedded: Bool = false

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var libraryAssets: [LibraryAsset] = []
    @State private var photoSelection: PhotosPickerItem? = nil
    @State private var isImporting = false
    @State private var importErrorMessage: String? = nil

    @State private var showCreateAssetFlow = false
    @State private var showCameraDeniedDialog = false

    @State private var renamingAsset: LibraryAsset? = nil
    @State private var renameText = ""

    @State private var assetPendingDelete: LibraryAsset? = nil
    @State private var showDeleteDialog = false
    @State private var deleteErrorMessage: String? = nil

    @State private var editingTarget: AssetEditingTarget? = nil
    @State private var actionErrorMessage: String? = nil

    @State private var assetPendingAction: LibraryAsset? = nil
    @State private var showActionsDialog = false

    var body: some View {
        Group {
            if embedded {
                listContent
            } else {
                NavigationView {
                    listContent
                        .navigationTitle("Asset Library")
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
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            importPhoto(item)
        }
        .alert("Rename Asset", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameText)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) { renamingAsset = nil }
        }
        // Tapping a row is the entry point for everything except Delete
        // (which stays a swipe action, deliberately, so it's never one
        // tap away by accident). A 3-option-plus-Cancel sheet doesn't fit
        // appConfirmationDialog's primary/secondary shape, same reasoning
        // as MomentsLibraryView's own delete-flow dialog.
        .confirmationDialog(
            assetPendingAction?.name ?? "Asset",
            isPresented: $showActionsDialog,
            titleVisibility: .visible
        ) {
            if let asset = assetPendingAction {
                if asset.isRenamable {
                    Button("Rename") {
                        renamingAsset = asset
                        renameText = asset.name
                    }
                }
                // Editing overwrites the asset's own file in place, so it
                // only makes sense for a real user asset with somewhere
                // writable to overwrite - not a bundled one.
                if asset.isDeletable {
                    Button("Edit") { startEditing(asset) }
                }
                // Duplicate has no such restriction: it always creates a
                // brand-new user asset, so it's offered for bundled
                // assets too (the way to turn a bundled starter into a
                // customizable copy).
                Button("Duplicate") { duplicateAsset(asset) }
            }
            Button("Cancel", role: .cancel) { assetPendingAction = nil }
        }
        .appConfirmationDialog(
            isPresented: $showDeleteDialog,
            title: "Delete \(assetPendingDelete?.name ?? "this asset")?",
            message: "This removes it from your library. Any overlay already using it will lose the image.",
            primaryTitle: "Delete",
            primaryRole: .destructive,
            primaryAction: { deletePendingAsset() },
            secondaryTitle: "Cancel",
            secondaryAction: { assetPendingDelete = nil }
        )
        .appConfirmationDialog(
            isPresented: $showCameraDeniedDialog,
            title: "Camera Access Needed",
            message: "Enable Camera access in Settings to create an asset from a photo.",
            primaryTitle: "Open Settings",
            primaryAction: {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            },
            secondaryTitle: "Cancel"
        )
        .fullScreenCover(isPresented: $showCreateAssetFlow, onDismiss: { refreshAssets() }) {
            AssetCreationFlow()
                .environmentObject(authManager)
        }
        // Re-presents the same AssetCropView the Create Asset flow uses,
        // seeded from the asset's *current* saved image rather than a
        // fresh capture - lets a circle-cropped asset later also go
        // through Smart Cutout (or vice versa), any number of times.
        // Saving here overwrites that asset's file in place rather than
        // creating a new AssetItem; Duplicate (below) is the explicit,
        // user-requested way to keep the original instead.
        .fullScreenCover(item: $editingTarget, onDismiss: { refreshAssets() }) { target in
            AssetCropView(
                sourceImage: target.image,
                onSave: { updated in
                    if let pngData = updated.pngData() {
                        saveLocalAssetImage(pngData, assetId: target.id)
                    }
                    editingTarget = nil
                },
                onCancel: { editingTarget = nil }
            )
            .environmentObject(authManager)
        }
    }

    private var listContent: some View {
        List {
            Section {
                Button {
                    requestAssetCameraAccess { authorization in
                        switch authorization {
                        case .ready: showCreateAssetFlow = true
                        case .denied: showCameraDeniedDialog = true
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "camera.badge.plus")
                        Text("Create Asset")
                    }
                }

                PhotosPicker(selection: $photoSelection, matching: .images) {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                        Text(isImporting ? "Adding…" : "Add from Photos")
                    }
                }
                .disabled(isImporting)

                if let importErrorMessage {
                    Text(importErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Library") {
                ForEach(libraryAssets) { asset in
                    Button {
                        assetPendingAction = asset
                        showActionsDialog = true
                    } label: {
                        assetRow(asset)
                    }
                    .buttonStyle(.plain)
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

                if let deleteErrorMessage {
                    Text(deleteErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let actionErrorMessage {
                    Text(actionErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private func assetRow(_ asset: LibraryAsset) -> some View {
        HStack(spacing: 12) {
            Group {
                if let image = asset.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(asset.name)
                .font(.subheadline)

            Spacer()

            if !asset.isDeletable {
                Text("Bundled")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// `.alert(_:isPresented:)` needs a plain Bool binding; this wraps the
    /// optional `renamingAsset` so dismissing the alert (Cancel, tap
    /// outside, or after Save) clears it consistently from one place.
    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingAsset != nil },
            set: { newValue in if !newValue { renamingAsset = nil } }
        )
    }

    private func refreshAssets() {
        authManager.loadLibraryAssets { libraryAssets = $0 }
    }

    private func importPhoto(_ item: PhotosPickerItem) {
        isImporting = true
        importErrorMessage = nil
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    isImporting = false
                    importErrorMessage = "Couldn't load that photo."
                    photoSelection = nil
                }
                return
            }

            let name = "New Asset"
            authManager.saveAsset(AssetItem(name: name)) { result in
                switch result {
                case .success(let saved):
                    if let id = saved.id {
                        saveLocalAssetImage(data, assetId: id)
                    }
                    isImporting = false
                    photoSelection = nil
                    refreshAssets()
                case .failure(let error):
                    isImporting = false
                    photoSelection = nil
                    importErrorMessage = "Couldn't save: \(error.localizedDescription)"
                }
            }
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
        authManager.updateAssetFields(assetId: assetId, fields: ["name": trimmed]) { _ in
            refreshAssets()
        }
    }

    private func startEditing(_ asset: LibraryAsset) {
        actionErrorMessage = nil
        guard let assetId = asset.backingAssetId, let image = localAssetImage(for: assetId) else {
            actionErrorMessage = "Couldn't open \"\(asset.name)\" for editing."
            return
        }
        editingTarget = AssetEditingTarget(id: assetId, image: image)
    }

    /// Works for bundled assets too (they have `asset.image` but no
    /// `backingAssetId`) - always creates a brand-new user AssetItem, so
    /// there's no "write to a bundled file" problem to avoid. Opens the
    /// new copy for editing immediately, since the whole point of
    /// duplicating (per the user's own request) is to edit it
    /// differently right away while the original stays untouched.
    private func duplicateAsset(_ asset: LibraryAsset) {
        actionErrorMessage = nil
        guard let image = asset.image, let pngData = image.pngData() else {
            actionErrorMessage = "Couldn't duplicate \"\(asset.name)\"."
            return
        }
        authManager.saveAsset(AssetItem(name: "\(asset.name) copy")) { result in
            switch result {
            case .success(let saved):
                guard let newId = saved.id else { return }
                saveLocalAssetImage(pngData, assetId: newId)
                refreshAssets()
                editingTarget = AssetEditingTarget(id: newId, image: image)
            case .failure(let error):
                actionErrorMessage = "Couldn't duplicate: \(error.localizedDescription)"
            }
        }
    }

    private func deletePendingAsset() {
        guard let asset = assetPendingDelete, let assetId = asset.backingAssetId else { return }
        assetPendingDelete = nil
        deleteErrorMessage = nil
        authManager.deleteAsset(assetId: assetId) { error in
            if let error {
                deleteErrorMessage = "Couldn't delete: \(error.localizedDescription)"
                return
            }
            removeLocalAssetImage(assetId: assetId)
            refreshAssets()
        }
    }
}

/// 2026-09-28: the one "Asset Library" entry point, replacing the old
/// visual-only screen `MomentsLibraryView`'s toolbar button opened. A
/// segmented switcher swaps between the two already-built libraries
/// (`AssetLibraryView`, `AudioAssetLibraryView`) hosted `embedded` so
/// only this view's NavigationView/title/Done button ever shows - never
/// two nav bars stacked. Neither library's own internals changed;
/// `embedded` just skips each one's own NavigationView wrapper when
/// hosted here.
struct AssetLibraryHubView: View {
    private enum Kind: String, CaseIterable, Identifiable {
        case visual = "Visual"
        case audio = "Audio"
        var id: String { rawValue }
    }

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: Kind = .visual

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Asset Kind", selection: $selectedKind) {
                    ForEach(Kind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                switch selectedKind {
                case .visual:
                    AssetLibraryView(embedded: true)
                        .environmentObject(authManager)
                case .audio:
                    AudioAssetLibraryView(embedded: true)
                        .environmentObject(authManager)
                }
            }
            .navigationTitle("Asset Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
