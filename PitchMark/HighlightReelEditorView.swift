//
//  HighlightReelEditorView.swift
//  PitchMark
//
//  Opened from MomentsLibraryView's multi-select mode with the Moments the
//  user picked, already in library display order. Lets the user reorder
//  before exporting, then builds one concatenated video via
//  HighlightReelExporter.swift. Full-clip concatenation only - no
//  per-clip trim-to-range of its own; a clip's pencil button opens that
//  Moment's own MomentDetailView in place instead (2026-10-05), so
//  trim/speed/filter/etc. all happen through the existing editors rather
//  than a second, parallel in-reel editing surface. Added specifically
//  because backing all the way out to the library to edit a clip, then
//  re-doing the whole Select -> Create Reel flow from scratch, was real
//  friction once a clip needed editing after it was already in a reel.
//  `refreshOrderedMoments` re-fetches every clip after that sheet closes
//  so a just-trimmed duration (etc.) shows up immediately.
//
//  2026-10-05: a finished reel is now a real Moment, auto-filed into the
//  "Highlight Reels" folder (`getOrCreateHighlightReelsFolder`,
//  MomentFolder.swift) - previously it was its own separate entity (a
//  `HighlightReel` Firestore doc + its own local-video storage,
//  HighlightReel.swift, now deleted) with its own dedicated browse-back
//  screen (HighlightReelsLibraryView.swift, also deleted) reachable only
//  via a second toolbar button. Making it an ordinary Moment means it
//  just shows up in the regular grid/folders UI, gets a real thumbnail
//  for free, and can be moved to any other folder the same way any other
//  Moment can - which is the whole point, not a side effect.
//
//  Export flow mirrors MomentsLibraryView.saveRecordedMoment's shape:
//  export to a temp file first, create the Firestore Moment doc (so a
//  real id exists), then move the temp file into that id's local storage
//  - never the other way around, so a failed export never leaves an
//  orphaned Firestore doc with no video behind it.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI
import AVFoundation

struct HighlightReelEditorView: View {
    let initialMoments: [Moment]
    /// Called once the new Moment is actually saved - lets the caller
    /// refresh its own `moments` array so the reel shows up without
    /// needing a manual pull-to-refresh.
    var onCreated: () -> Void = {}

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var orderedMoments: [Moment]
    @State private var isExporting = false
    @State private var exportErrorMessage: String? = nil
    @State private var momentPendingEdit: Moment? = nil
    /// 2026-10-06 - on by default per explicit request ("default to
    /// adding a very fast fade transition"); the Toggle is what lets the
    /// user turn it off, same "Fade Between Segments" shape
    /// MomentSlideshowEditorView already uses, not a duration slider -
    /// the transition length itself is fixed
    /// (`defaultHighlightReelTransitionDuration`, HighlightReelExporter.swift).
    @State private var transitionsEnabled = true

    init(initialMoments: [Moment], onCreated: @escaping () -> Void = {}) {
        self.initialMoments = initialMoments
        self.onCreated = onCreated
        _orderedMoments = State(initialValue: initialMoments)
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Drag to reorder. The reel plays each clip in this order, full-length. Tap \u{270F}\u{FE0F} to trim, speed up, or otherwise edit a clip before it's combined.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)

                Section {
                    ForEach(orderedMoments) { moment in
                        HStack {
                            Image(systemName: "film")
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(moment.displayTitle)
                                    .font(.subheadline.weight(.semibold))
                                if let duration = moment.durationSeconds {
                                    Text(formattedDuration(duration))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button {
                                momentPendingEdit = moment
                            } label: {
                                Image(systemName: "pencil.circle")
                            }
                            .buttonStyle(.plain)
                            .disabled(isExporting)
                        }
                    }
                    .onMove { indices, newOffset in
                        orderedMoments.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }

                Section {
                    Toggle("Fade Between Clips", isOn: $transitionsEnabled)
                        .disabled(isExporting)
                } footer: {
                    Text("A quick crossfade where one clip ends and the next begins.")
                }

                if let exportErrorMessage {
                    Section {
                        Text(exportErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        startExport()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Create Highlight Reel")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(isExporting || orderedMoments.isEmpty)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("New Highlight Reel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isExporting)
                }
            }
        }
        // Same full-screen dim-plus-white-spinner overlay every other
        // exporting state in this app uses
        // ([[feedback-loading-spinner-convention]]) - this editor
        // previously had no loading indicator at all beyond the button's
        // own text swap.
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("Creating Reel…")
                            .foregroundStyle(.white)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .sheet(item: $momentPendingEdit, onDismiss: refreshOrderedMoments) { moment in
            MomentDetailView(moment: moment, allMoments: orderedMoments)
                .environmentObject(authManager)
        }
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Re-fetches every clip still in the list after the edit sheet
    /// closes - cheap at reel-sized clip counts, and simpler than
    /// tracking which one field actually changed. Keeps the displayed
    /// duration (and anything else shown here) in step with whatever was
    /// just trimmed/sped-up/etc.; `startExport` itself always resolves
    /// each clip's video fresh from its id regardless, so this is purely
    /// about what the list shows, not export correctness.
    private func refreshOrderedMoments() {
        for moment in orderedMoments {
            guard let id = moment.id else { continue }
            authManager.loadMoment(momentId: id) { refreshed in
                guard let refreshed, let index = orderedMoments.firstIndex(where: { $0.id == id }) else { return }
                orderedMoments[index] = refreshed
            }
        }
    }

    private func startExport() {
        exportErrorMessage = nil
        let urls = orderedMoments.compactMap { moment -> URL? in
            guard let id = moment.id else { return nil }
            return resolvedMomentPlaybackURL(for: id)
        }
        guard urls.count == orderedMoments.count, !urls.isEmpty else {
            exportErrorMessage = "Couldn't find video for one or more selected Moments."
            return
        }

        isExporting = true
        exportHighlightReel(momentVideoURLs: urls, transitionsEnabled: transitionsEnabled) { result in
            switch result {
            case .failure(let error):
                isExporting = false
                exportErrorMessage = "Couldn't create the reel: \(error.localizedDescription)"
            case .success(let tempURL):
                let asset = AVURLAsset(url: tempURL)
                Task {
                    let loadedDuration = try? await asset.load(.duration)
                    let seconds = loadedDuration?.seconds.isFinite == true ? loadedDuration!.seconds : nil
                    await MainActor.run {
                        finishExport(tempURL: tempURL, durationSeconds: seconds)
                    }
                }
            }
        }
    }

    private func finishExport(tempURL: URL, durationSeconds: Double?) {
        // `title` isn't one of Moment's init parameters (every other
        // caller sets it later, via updateMomentFields, same as here) -
        // "Highlight Reel" is set in that same follow-up write, alongside
        // filing it into its folder, rather than needing a second round
        // trip.
        let moment = Moment(durationSeconds: durationSeconds)
        authManager.saveMoment(moment) { result in
            switch result {
            case .failure(let error):
                isExporting = false
                exportErrorMessage = "Couldn't save the reel: \(error.localizedDescription)"
            case .success(let saved):
                guard let id = saved.id else {
                    isExporting = false
                    exportErrorMessage = "Couldn't save the reel."
                    return
                }
                saveLocalMomentVideo(from: tempURL, momentId: id)
                authManager.getOrCreateHighlightReelsFolder { folderResult in
                    isExporting = false
                    var fields: [String: Any] = ["title": "Highlight Reel"]
                    if case .success(let folder) = folderResult, let folderId = folder.id {
                        fields["momentFolderId"] = folderId
                    }
                    authManager.updateMomentFields(momentId: id, fields: fields) { _ in
                        onCreated()
                        dismiss()
                    }
                }
            }
        }
    }
}
