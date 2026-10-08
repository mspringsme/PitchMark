//
//  MomentFolderDetailView.swift
//  PitchMark
//
//  2026-10-04: pushed from a Folder tile in MomentFoldersView.swift - a
//  grid of this folder's Buckets (same create/rename/delete shape as
//  Folders) above a MomentGridView of whatever's filed directly in the
//  folder (no bucket).
//
//  2026-10-06: Select -> Create Reel, same shape MomentsLibraryView's
//  own "All" tab already has - reported missing here ("the select
//  button is missing for creating reels"). Scoped to `directMoments`
//  only (what this screen's own grid actually shows) - a Bucket's
//  moments get the identical entry point one level deeper, in
//  MomentBucketDetailView.swift.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI

struct MomentFolderDetailView: View {
    let folder: MomentFolder
    let moments: [Moment]
    let onOpenMoment: (Moment) -> Void
    let onMomentsNeedRefresh: () -> Void

    @EnvironmentObject var authManager: AuthManager

    @State private var buckets: [MomentBucket] = []
    @State private var showCreateBucket = false
    @State private var bucketPendingRename: MomentBucket? = nil
    @State private var bucketPendingDelete: MomentBucket? = nil
    @State private var showDeleteDialog = false
    @State private var errorMessage: String? = nil

    @State private var isSelectingForReel = false
    @State private var selectedMomentIdsForReel: Set<String> = []
    @State private var showHighlightReelEditor = false

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 12)]

    private var directMoments: [Moment] {
        moments.filter { $0.momentFolderId == folder.id && $0.momentBucketId == nil }
    }

    private func momentsInBucket(_ bucket: MomentBucket) -> [Moment] {
        moments.filter { $0.momentBucketId == bucket.id }
    }

    private var momentsSelectedForReel: [Moment] {
        directMoments.filter { selectedMomentIdsForReel.contains($0.id ?? "") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !buckets.isEmpty {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(buckets) { bucket in
                            NavigationLink {
                                MomentBucketDetailView(bucket: bucket, moments: momentsInBucket(bucket), onOpenMoment: onOpenMoment, onMomentsNeedRefresh: onMomentsNeedRefresh)
                            } label: {
                                MomentCollectionTile(
                                    name: bucket.name,
                                    representativeMoment: momentsInBucket(bucket).first,
                                    count: momentsInBucket(bucket).count
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Rename") { bucketPendingRename = bucket }
                                Button("Delete", role: .destructive) {
                                    bucketPendingDelete = bucket
                                    showDeleteDialog = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                MomentGridView(
                    moments: directMoments,
                    isSelecting: isSelectingForReel,
                    selectedMomentIds: selectedMomentIdsForReel,
                    emptyMessage: "No Moments directly in \(folder.name) yet.",
                    onTap: { moment in
                        if isSelectingForReel {
                            toggleReelSelection(moment)
                        } else {
                            onOpenMoment(moment)
                        }
                    }
                )
            }
            .padding(.vertical)
        }
        .navigationTitle(folder.name)
        .toolbar {
            if isSelectingForReel {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isSelectingForReel = false
                        selectedMomentIdsForReel = []
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create Reel (\(selectedMomentIdsForReel.count))") {
                        showHighlightReelEditor = true
                    }
                    .disabled(selectedMomentIdsForReel.isEmpty)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Select") { isSelectingForReel = true }
                        .disabled(directMoments.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateBucket = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
        }
        .onAppear(perform: refreshBuckets)
        .sheet(isPresented: $showHighlightReelEditor, onDismiss: {
            isSelectingForReel = false
            selectedMomentIdsForReel = []
        }) {
            HighlightReelEditorView(initialMoments: momentsSelectedForReel, onCreated: onMomentsNeedRefresh)
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showCreateBucket) {
            MomentNamePromptSheet(title: "New Bucket") { name in
                guard let folderId = folder.id else { return }
                authManager.createMomentBucket(folderId: folderId, name: name) { result in
                    switch result {
                    case .success:
                        refreshBuckets()
                    case .failure(let error):
                        errorMessage = "Couldn't create bucket: \(error.localizedDescription)"
                    }
                }
            }
        }
        .sheet(item: $bucketPendingRename) { bucket in
            MomentNamePromptSheet(title: "Rename Bucket", initialName: bucket.name) { name in
                guard let folderId = folder.id, let bucketId = bucket.id else { return }
                authManager.renameMomentBucket(folderId: folderId, bucketId: bucketId, name: name) { error in
                    if let error {
                        errorMessage = "Couldn't rename: \(error.localizedDescription)"
                    } else {
                        refreshBuckets()
                    }
                }
            }
        }
        .appConfirmationDialog(
            isPresented: $showDeleteDialog,
            title: "Delete \u{201C}\(bucketPendingDelete?.name ?? "this bucket")\u{201D}?",
            message: "Every Moment inside falls back to being filed directly in \(folder.name), not deleted.",
            primaryTitle: "Delete",
            primaryRole: .destructive,
            primaryAction: { deletePendingBucket() },
            secondaryTitle: "Cancel",
            secondaryAction: { bucketPendingDelete = nil }
        )
    }

    private func toggleReelSelection(_ moment: Moment) {
        guard let id = moment.id else { return }
        if selectedMomentIdsForReel.contains(id) {
            selectedMomentIdsForReel.remove(id)
        } else {
            selectedMomentIdsForReel.insert(id)
        }
    }

    private func refreshBuckets() {
        guard let folderId = folder.id else { return }
        authManager.loadMomentBuckets(folderId: folderId) { buckets = $0 }
    }

    private func deletePendingBucket() {
        guard let folderId = folder.id, let bucket = bucketPendingDelete, let bucketId = bucket.id else { return }
        bucketPendingDelete = nil
        errorMessage = nil
        authManager.deleteMomentBucket(folderId: folderId, bucketId: bucketId) { error in
            if let error {
                errorMessage = "Couldn't delete: \(error.localizedDescription)"
                return
            }
            refreshBuckets()
            onMomentsNeedRefresh()
        }
    }
}
