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

    /// "Mine" or an icon category (2026-11-15) - 67 icons in one row was
    /// too long to scroll.
    @State private var section: String? = nil

    static let mineSection = "Mine"

    private var sections: [String] {
        let mine = assets.contains { $0.category == nil } ? [Self.mineSection] : []
        let categories = OverlayIconCategory.allCases.map(\.rawValue).filter { name in assets.contains { $0.category == name } }
        return mine + categories
    }

    private var shown: [LibraryAsset] {
        let current = section ?? sections.first
        return assets.filter { ($0.category ?? Self.mineSection) == current }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if sections.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(sections, id: \.self) { name in
                            let isOn = name == (section ?? sections.first)
                            Button {
                                section = name
                            } label: {
                                Text(name == Self.mineSection ? "My Assets" : name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(isOn ? Color.white : Color.primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(isOn ? Color.pitchMarkActiveGray : Color(.secondarySystemBackground)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("assetStrip.section.\(name)")
                        }
                    }
                    .padding(.horizontal)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(shown) { asset in
                        Button {
                            onSelect?(asset)
                        } label: {
                            VStack(spacing: 4) {
                                assetThumbnail(asset, size: 64, padding: 10)
                                Text(asset.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 70)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// A library thumbnail. Built-in icons are white images, so they're drawn
/// in the text color here to show on any background.
@ViewBuilder
func assetThumbnail(_ asset: LibraryAsset, size: CGFloat, padding: CGFloat) -> some View {
    Group {
        if let image = asset.image {
            Image(uiImage: image)
                .renderingMode(asset.isTintable ? .template : .original)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.primary)
                .padding(padding)
        } else {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }
    .frame(width: size, height: size)
    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
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

            Section("My Assets") {
                let mine = libraryAssets.filter { $0.category == nil }
                if mine.isEmpty {
                    Text("Nothing here yet. Import a photo or create one above.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(mine) { asset in
                    libraryRow(asset)
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

            // Built-in icons (OverlayIcons.swift), by category.
            ForEach(OverlayIconCategory.allCases, id: \.self) { category in
                let icons = libraryAssets.filter { $0.category == category.rawValue }
                if !icons.isEmpty {
                    Section("Icons: \(category.rawValue)") {
                        ForEach(icons) { asset in
                            libraryRow(asset)
                        }
                    }
                }
            }
        }
    }

    private func libraryRow(_ asset: LibraryAsset) -> some View {
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

    @ViewBuilder
    private func assetRow(_ asset: LibraryAsset) -> some View {
        HStack(spacing: 12) {
            assetThumbnail(asset, size: 44, padding: 8)

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
                CapsuleSegmentedControl(
                    options: Kind.allCases.map { ($0.rawValue, $0) },
                    selection: $selectedKind
                )
                .frame(maxWidth: .infinity)
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
