//
//  MomentFoldersView.swift
//  PitchMark
//
//  2026-10-04: the "Folders" tab of MomentsLibraryView - a grid of
//  user-created Folders (MomentFolder.swift), each pushing into
//  MomentFolderDetailView. Plain content view, not its own NavigationView -
//  it's embedded inside MomentsLibraryView's NavigationView, so pushes
//  from here share that same nav stack.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI

struct MomentFoldersView: View {
    let moments: [Moment]
    let onOpenMoment: (Moment) -> Void
    /// Called after a folder delete (or anything else here that changes
    /// a Moment's placement) actually lands - `moments` is a plain
    /// snapshot passed down from `MomentsLibraryView`, not reactive, so
    /// the parent has to reload it for this screen's own tiles/grids to
    /// reflect the change.
    let onMomentsNeedRefresh: () -> Void

    @EnvironmentObject var authManager: AuthManager

    @State private var folders: [MomentFolder] = []
    @State private var showCreateFolder = false
    @State private var folderPendingRename: MomentFolder? = nil
    @State private var folderPendingDelete: MomentFolder? = nil
    @State private var showDeleteDialog = false
    @State private var errorMessage: String? = nil

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 12)]

    var body: some View {
        ScrollView {
            if folders.isEmpty {
                Text("No folders yet. Tap + to create one, like \u{201C}2026 Reds 16U.\u{201D}")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(folders) { folder in
                        NavigationLink {
                            MomentFolderDetailView(folder: folder, moments: moments, onOpenMoment: onOpenMoment, onMomentsNeedRefresh: onMomentsNeedRefresh)
                                .environmentObject(authManager)
                        } label: {
                            MomentCollectionTile(
                                name: folder.name,
                                representativeMoment: momentsInFolder(folder).first,
                                count: momentsInFolder(folder).count
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Rename") { folderPendingRename = folder }
                            Button("Delete", role: .destructive) {
                                folderPendingDelete = folder
                                showDeleteDialog = true
                            }
                        }
                    }
                }
                .padding()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
        // No .navigationTitle here - this view is swapped in inline
        // (MomentsLibraryView's segmented control), not NavigationLink-
        // pushed, so it shares the ambient "Moments" title/toolbar rather
        // than fighting it for one. The segmented control itself already
        // shows which tab is active.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }
        }
        .onAppear(perform: refreshFolders)
        .sheet(isPresented: $showCreateFolder) {
            MomentNamePromptSheet(title: "New Folder") { name in
                authManager.createMomentFolder(name: name) { result in
                    switch result {
                    case .success:
                        refreshFolders()
                    case .failure(let error):
                        errorMessage = "Couldn't create folder: \(error.localizedDescription)"
                    }
                }
            }
        }
        .sheet(item: $folderPendingRename) { folder in
            MomentNamePromptSheet(title: "Rename Folder", initialName: folder.name) { name in
                guard let id = folder.id else { return }
                authManager.renameMomentFolder(folderId: id, name: name) { error in
                    if let error {
                        errorMessage = "Couldn't rename: \(error.localizedDescription)"
                    } else {
                        refreshFolders()
                    }
                }
            }
        }
        .appConfirmationDialog(
            isPresented: $showDeleteDialog,
            title: "Delete \u{201C}\(folderPendingDelete?.name ?? "this folder")\u{201D}?",
            message: "Its buckets go with it, but every Moment inside becomes unfiled rather than deleted.",
            primaryTitle: "Delete",
            primaryRole: .destructive,
            primaryAction: { deletePendingFolder() },
            secondaryTitle: "Cancel",
            secondaryAction: { folderPendingDelete = nil }
        )
    }

    private func momentsInFolder(_ folder: MomentFolder) -> [Moment] {
        moments.filter { $0.momentFolderId == folder.id }
    }

    private func refreshFolders() {
        authManager.loadMomentFolders { folders = $0 }
    }

    private func deletePendingFolder() {
        guard let folder = folderPendingDelete, let id = folder.id else { return }
        folderPendingDelete = nil
        errorMessage = nil
        authManager.deleteMomentFolder(folderId: id) { error in
            if let error {
                errorMessage = "Couldn't delete: \(error.localizedDescription)"
                return
            }
            refreshFolders()
            onMomentsNeedRefresh()
        }
    }
}
