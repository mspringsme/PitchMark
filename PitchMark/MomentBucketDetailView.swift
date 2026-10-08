//
//  MomentBucketDetailView.swift
//  PitchMark
//
//  2026-10-04: pushed from a Bucket tile in MomentFolderDetailView.swift -
//  just this bucket's Moments as a grid. `moments` arrives already
//  filtered by the caller (it already has the full list in hand and
//  knows which bucket), so there's nothing else for this screen to do.
//
//  2026-10-06: Select -> Create Reel, same shape MomentsLibraryView's
//  own "All" tab already has - reported missing here ("the select
//  button is missing for creating reels"). Kept local to this screen
//  (own @State, own toolbar/sheet) rather than threading selection state
//  up through MomentFolderDetailView/MomentFoldersView/MomentsLibraryView -
//  HighlightReelEditorView is already a self-contained component
//  (initialMoments + onCreated), so every screen that shows a Moment
//  grid can just present it directly.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI

struct MomentBucketDetailView: View {
    let bucket: MomentBucket
    let moments: [Moment]
    let onOpenMoment: (Moment) -> Void
    let onMomentsNeedRefresh: () -> Void

    @EnvironmentObject var authManager: AuthManager

    @State private var isSelectingForReel = false
    @State private var selectedMomentIdsForReel: Set<String> = []
    @State private var showHighlightReelEditor = false

    private var momentsSelectedForReel: [Moment] {
        moments.filter { selectedMomentIdsForReel.contains($0.id ?? "") }
    }

    var body: some View {
        MomentGridView(
            moments: moments,
            isSelecting: isSelectingForReel,
            selectedMomentIds: selectedMomentIdsForReel,
            emptyMessage: "No Moments in \(bucket.name) yet.",
            onTap: { moment in
                if isSelectingForReel {
                    toggleReelSelection(moment)
                } else {
                    onOpenMoment(moment)
                }
            }
        )
        .navigationTitle(bucket.name)
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
                        .disabled(moments.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showHighlightReelEditor, onDismiss: {
            isSelectingForReel = false
            selectedMomentIdsForReel = []
        }) {
            HighlightReelEditorView(initialMoments: momentsSelectedForReel, onCreated: onMomentsNeedRefresh)
                .environmentObject(authManager)
        }
    }

    private func toggleReelSelection(_ moment: Moment) {
        guard let id = moment.id else { return }
        if selectedMomentIdsForReel.contains(id) {
            selectedMomentIdsForReel.remove(id)
        } else {
            selectedMomentIdsForReel.insert(id)
        }
    }
}
