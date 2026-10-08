//
//  MoveMomentToFolderView.swift
//  PitchMark
//
//  2026-10-04: "Move to Folder..." sheet, opened from MomentsLibraryView's
//  per-Moment actions dialog. Single-select list - an "Unfiled" row to
//  clear placement, then every Folder (tap to expand its Buckets inline,
//  one more single-select level within). Same checkmark-on-selected-row
//  shape CalledPitchRecord.swift's own filterSheetView/filterRow already
//  established for a sheet-hosted List filter picker.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI

struct MoveMomentToFolderView: View {
    let moment: Moment
    var onMoved: () -> Void = {}

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var folders: [MomentFolder] = []
    @State private var bucketsByFolderId: [String: [MomentBucket]] = [:]
    @State private var expandedFolderId: String? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    filterRow(title: "Unfiled", isSelected: moment.momentFolderId == nil) {
                        move(toFolderId: nil, bucketId: nil)
                    }
                }

                ForEach(folders) { folder in
                    Section {
                        DisclosureGroup(isExpanded: isExpanded(folder)) {
                            filterRow(
                                title: "Directly in \(folder.name)",
                                isSelected: moment.momentFolderId == folder.id && moment.momentBucketId == nil
                            ) {
                                move(toFolderId: folder.id, bucketId: nil)
                            }
                            ForEach(bucketsByFolderId[folder.id ?? ""] ?? []) { bucket in
                                filterRow(title: bucket.name, isSelected: moment.momentBucketId == bucket.id) {
                                    move(toFolderId: folder.id, bucketId: bucket.id)
                                }
                            }
                        } label: {
                            Text(folder.name).font(.subheadline.weight(.semibold))
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }
            .navigationTitle("Move to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear(perform: refreshFolders)
    }

    private func isExpanded(_ folder: MomentFolder) -> Binding<Bool> {
        Binding(
            get: { expandedFolderId == folder.id },
            set: { expandedFolderId = $0 ? folder.id : nil }
        )
    }

    private func filterRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
    }

    private func refreshFolders() {
        authManager.loadMomentFolders { loaded in
            folders = loaded
            let group = DispatchGroup()
            for folder in loaded {
                guard let folderId = folder.id else { continue }
                group.enter()
                authManager.loadMomentBuckets(folderId: folderId) { buckets in
                    bucketsByFolderId[folderId] = buckets
                    group.leave()
                }
            }
        }
    }

    private func move(toFolderId folderId: String?, bucketId: String?) {
        guard let momentId = moment.id else { return }
        errorMessage = nil
        authManager.moveMoment(momentId: momentId, toFolderId: folderId, bucketId: bucketId) { error in
            if let error {
                errorMessage = "Couldn't move: \(error.localizedDescription)"
                return
            }
            onMoved()
            dismiss()
        }
    }
}
