//
//  MomentsLibraryView.swift
//  PitchMark
//
//  Phase 6 - the real Moments screen, replacing the
//  ComingSoonSheetView(area: .moments, ...) placeholder wired up in Phase 2
//  step 2. "Capture now, create later": recording ends with one mandatory
//  action (save), nothing else required before the clip lands in the
//  library. Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this UI.
//

import SwiftUI

struct MomentsLibraryView: View {
    /// When opened from inside the Parent Game Shell for a specific child,
    /// new recordings auto-tag that child. When opened from the general
    /// tab bar (no child in context), they save untagged rather than
    /// blocking recording on a picker first - nothing else is mandatory.
    var contextPlayer: TeamPlayer? = nil
    var contextTeamId: String? = nil
    var onSwitchToArea: ((HomeArea) -> Void)? = nil

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var moments: [Moment] = []
    @State private var showCameraPicker = false
    @State private var showCameraDeniedDialog = false
    @State private var selectedMomentForDetail: Moment? = nil
    @State private var isSaving = false

    @State private var momentPendingDelete: Moment? = nil
    @State private var showDeleteDialog = false
    @State private var deleteErrorMessage: String? = nil

    var body: some View {
        NavigationView {
            // List, not ScrollView/VStack, specifically so swipe-to-delete
            // (.swipeActions) is available - it's a List row modifier only.
            List {
                Section {
                    recordButton

                    if let player = contextPlayer {
                        Text("New Moments will be tagged with \(player.name).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let deleteErrorMessage {
                        Text(deleteErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                Section {
                    if moments.isEmpty {
                        Text("No Moments yet. Record one above.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(moments) { moment in
                            Button {
                                selectedMomentForDetail = moment
                            } label: {
                                momentRow(moment)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    momentPendingDelete = moment
                                    showDeleteDialog = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Moments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HomeAreaTabBar(current: .moments) { selected in
                    onSwitchToArea?(selected)
                    dismiss()
                }
            }
        }
        .onAppear { refreshMoments() }
        .sheet(isPresented: $showCameraPicker) {
            MomentCameraPicker { url, duration, photos in
                showCameraPicker = false
                if let url {
                    saveRecordedMoment(from: url, duration: duration, capturedPhotos: photos)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $selectedMomentForDetail, onDismiss: { refreshMoments() }) { moment in
            MomentDetailView(moment: moment, allMoments: moments)
        }
        .appConfirmationDialog(
            isPresented: $showCameraDeniedDialog,
            title: "Camera Access Needed",
            message: "Enable Camera access in Settings to record Moments.",
            primaryTitle: "Open Settings",
            primaryAction: {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            },
            secondaryTitle: "Cancel"
        )
        // A 3-option destructive action sheet doesn't fit
        // appConfirmationDialog's primary/secondary shape (that component
        // exists specifically to avoid SwiftUI's .alert(), which squeezes
        // horizontally at large accessibility text sizes - see CLAUDE.md).
        // .confirmationDialog presents as a bottom action sheet with
        // stacked buttons instead, so it doesn't have that problem.
        .confirmationDialog(
            "Delete \(momentPendingDelete?.displayTitle ?? "this Moment")?",
            isPresented: $showDeleteDialog,
            titleVisibility: .visible
        ) {
            Button("Save to Camera Roll, then Delete") {
                saveToCameraRollThenDelete()
            }
            Button("Delete", role: .destructive) {
                deletePendingMoment()
            }
            Button("Cancel", role: .cancel) {
                momentPendingDelete = nil
            }
        } message: {
            Text("This removes it from PitchMark. The video can't be recovered afterward unless you save a copy first.")
        }
    }

    private var recordButton: some View {
        Button {
            requestMomentCameraAccess { authorization in
                switch authorization {
                case .ready: showCameraPicker = true
                case .denied: showCameraDeniedDialog = true
                }
            }
        } label: {
            HStack {
                Image(systemName: "video.fill")
                Text(isSaving ? "Saving…" : "Record a Moment")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    @ViewBuilder
    private var libraryList: some View {
        if moments.isEmpty {
            Text("No Moments yet. Record one above.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(moments) { moment in
                    Button {
                        selectedMomentForDetail = moment
                    } label: {
                        momentRow(moment)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func momentRow(_ moment: Moment) -> some View {
        HStack {
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(moment.displayTitle)
                        .font(.subheadline.weight(.semibold))
                    if moment.isFavorite == true {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(Color.red)
                    }
                }
                Text(moment.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let duration = moment.durationSeconds {
                Text(formattedDuration(duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func refreshMoments() {
        authManager.loadMoments { moments = $0 }
    }

    private func deletePendingMoment() {
        guard let moment = momentPendingDelete, let id = moment.id else { return }
        momentPendingDelete = nil
        deleteErrorMessage = nil
        authManager.deleteMoment(momentId: id) { error in
            if let error {
                deleteErrorMessage = "Couldn't delete: \(error.localizedDescription)"
                return
            }
            removeAllLocalMomentFiles(momentId: id, photoCount: moment.photoCount ?? 0)
            refreshMoments()
        }
    }

    private func saveToCameraRollThenDelete() {
        guard let moment = momentPendingDelete, let id = moment.id else { return }
        deleteErrorMessage = nil
        saveMomentVideoToCameraRoll(momentId: id) { result in
            switch result {
            case .success:
                deletePendingMoment()
            case .failure(let error):
                momentPendingDelete = nil
                deleteErrorMessage = "Couldn't save to Camera Roll, so nothing was deleted: \(error.localizedDescription)"
            }
        }
    }

    private func saveRecordedMoment(from tempURL: URL, duration: Double?, capturedPhotos: [Data]) {
        isSaving = true
        let moment = Moment(
            createdAt: Date(),
            teamId: contextTeamId,
            playerId: contextPlayer?.id,
            playerName: contextPlayer?.name,
            durationSeconds: duration,
            photoCount: capturedPhotos.count
        )
        authManager.saveMoment(moment) { result in
            isSaving = false
            switch result {
            case .success(let saved):
                if let id = saved.id {
                    saveLocalMomentVideo(from: tempURL, momentId: id)
                    for (index, data) in capturedPhotos.enumerated() {
                        saveLocalMomentPhoto(data, momentId: id, index: index)
                    }
                }
                refreshMoments()
            case .failure(let error):
                debugLog("❌ saveMoment failed:", error.localizedDescription)
            }
        }
    }
}
