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
    /// "New folder" lives as a button next to MomentsLibraryView's All/Folders
    /// capsule control rather than in this view's own toolbar, so the parent
    /// owns the trigger and passes it down.
    @Binding var showCreateFolder: Bool

    @EnvironmentObject var authManager: AuthManager

    @State private var folders: [MomentFolder] = []
    @State private var folderPendingRename: MomentFolder? = nil
    @State private var folderPendingDelete: MomentFolder? = nil
    @State private var showDeleteDialog = false
    @State private var errorMessage: String? = nil

    /// The one auto-created, un-deletable-from-here folder Highlight Reel
    /// exports file into (MomentFolder.swift's `isHighlightReelsFolder`) -
    /// pinned above the scrolling list of every other folder rather than
    /// sorted in with them.
    private var highlightReelsFolder: MomentFolder? {
        folders.first { $0.isHighlightReelsFolder == true }
    }

    private var otherFolders: [MomentFolder] {
        folders.filter { $0.isHighlightReelsFolder != true }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let highlightReelsFolder {
                NavigationLink {
                    MomentFolderDetailView(folder: highlightReelsFolder, moments: moments, onOpenMoment: onOpenMoment, onMomentsNeedRefresh: onMomentsNeedRefresh)
                        .environmentObject(authManager)
                } label: {
                    MomentFolderRow(
                        name: highlightReelsFolder.name,
                        representativeMoment: momentsInFolder(highlightReelsFolder).first,
                        count: momentsInFolder(highlightReelsFolder).count
                    )
                }
                .buttonStyle(.plain)
                .background(Color(.systemBackground))

                Divider()
            }

            ScrollView {
                if otherFolders.isEmpty {
                    Text("No folders yet. Tap + to create one, like \u{201C}2026 Reds 16U.\u{201D}")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(otherFolders) { folder in
                            NavigationLink {
                                MomentFolderDetailView(folder: folder, moments: moments, onOpenMoment: onOpenMoment, onMomentsNeedRefresh: onMomentsNeedRefresh)
                                    .environmentObject(authManager)
                            } label: {
                                MomentFolderRow(
                                    name: folder.name,
                                    representativeMoment: momentsInFolder(folder).first,
                                    count: momentsInFolder(folder).count
                                )
                            }
                            .buttonStyle(.plain)
                            .background(Color(.systemBackground))
                            .contextMenu {
                                Button("Rename") { folderPendingRename = folder }
                                Button("Delete", role: .destructive) {
                                    folderPendingDelete = folder
                                    showDeleteDialog = true
                                }
                            }

                            Divider()
                                .padding(.leading, 120)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
            .background(Color(.secondarySystemBackground))
        }
        // No .navigationTitle here - this view is swapped in inline
        // (MomentsLibraryView's segmented control), not NavigationLink-
        // pushed, so it shares the ambient "Moments" title/toolbar rather
        // than fighting it for one. The segmented control itself already
        // shows which tab is active.
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

/// A Folder/Bucket row - smaller thumbnail on the left (roughly half the
/// old grid tile's size), larger title text to its right. Replaces
/// `MomentCollectionTile`'s card layout for this screen's list of
/// Folders, and (not `private`, so MomentFolderDetailView.swift can use
/// it too) for its own Bucket list.
struct MomentFolderRow: View {
    let name: String
    let representativeMoment: Moment?
    let count: Int

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(Color(.secondarySystemBackground))
                .aspectRatio(1.3, contentMode: .fit)
                .frame(width: 90)
                .overlay {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "folder.fill")
                            .font(.title2)
                            .foregroundStyle(Color.pitchMarkActiveGray)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text("\(count) Moment\(count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onAppear {
            guard thumbnail == nil, let representativeMoment else { return }
            momentThumbnail(for: representativeMoment) { thumbnail = $0 }
        }
    }
}
