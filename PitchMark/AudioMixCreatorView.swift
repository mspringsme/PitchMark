//
//  AudioMixCreatorView.swift
//  PitchMark
//
//  Combine several existing audio assets (bundled sfx/music or user
//  recordings) into one new flattened mix, then save that mix as a
//  brand-new AudioAssetItem - so a mix shows up in the Audio Asset
//  Library exactly like any other clip and can be placed on a Moment
//  the same way.
//
//  Deliberately list-based, not a full drag-on-timeline editor like
//  MomentAudioEditorView - there's no video to scrub against here, just
//  a handful of clips being layered together, so a plain list of
//  stepper/slider controls per clip covers this without re-deriving that
//  file's much larger timeline/waveform/gesture machinery. New clips
//  default to startTime 0 (layered together, like a music bed + sfx) -
//  the Start stepper is there specifically for the user who wants them
//  sequenced instead.
//
//  Reuses AudioOverlayItem (AudioOverlay.swift) as the per-clip model
//  and AudioMixExporter.swift's exportAudioMix for the actual flatten -
//  both already exist for a Moment's own audio overlays; a mix's clips
//  have the identical trim/volume shape, just with no original track to
//  layer onto.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI
import AVFoundation

private struct MixClipDraft: Identifiable {
    let id: UUID
    var assetId: String
    var assetName: String
    var assetDurationSeconds: Double
    var startTime: Double
    var volume: Double
    var trimStart: Double
    var trimEnd: Double

    func toOverlayItem() -> AudioOverlayItem {
        AudioOverlayItem(
            id: id,
            assetId: assetId,
            startTime: startTime,
            volume: volume,
            trimStart: trimStart,
            trimEnd: trimEnd >= assetDurationSeconds - 0.01 ? nil : trimEnd
        )
    }
}

struct AudioMixCreatorView: View {
    var onSaved: () -> Void = {}

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var drafts: [MixClipDraft] = []
    @State private var audioAssetsById: [String: LibraryAudioAsset] = [:]
    @State private var showAddClipPicker = false

    @State private var isExporting = false
    @State private var exportedMixURL: URL? = nil
    @State private var mixName = "New Mix"
    @State private var player: AVPlayer? = nil
    @State private var isPlaying = false
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationView {
            List {
                if let exportedMixURL {
                    previewSection(exportedMixURL)
                } else {
                    Section {
                        if drafts.isEmpty {
                            Text("Add a few clips, then create a mix. Clips start layered together at time 0 by default - adjust Start to sequence them instead.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach($drafts) { $draft in
                                clipRow($draft)
                            }
                            .onDelete { indices in
                                drafts.remove(atOffsets: indices)
                            }
                        }
                        Button {
                            showAddClipPicker = true
                        } label: {
                            Label("Add Clip", systemImage: "plus.circle.fill")
                        }
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage)
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
                                Text(isExporting ? "Creating Mix…" : "Create Mix")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                        .disabled(isExporting || drafts.isEmpty)
                    }
                }
            }
            .navigationTitle("Audio Mix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isExporting || isSaving)
                }
            }
        }
        .sheet(isPresented: $showAddClipPicker) {
            AudioAssetLibraryView { asset in
                addClip(asset)
                showAddClipPicker = false
            }
            .environmentObject(authManager)
        }
        .onDisappear { player?.pause() }
    }

    private func clipRow(_ draft: Binding<MixClipDraft>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(draft.wrappedValue.assetName)
                .font(.subheadline.weight(.semibold))

            Stepper(
                "Start: \(String(format: "%.1f", draft.wrappedValue.startTime))s",
                value: draft.startTime,
                in: 0...300,
                step: 0.1
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Volume: \(Int(draft.wrappedValue.volume * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: draft.volume, in: 0...1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Trim: \(String(format: "%.1f", draft.wrappedValue.trimStart))s – \(String(format: "%.1f", draft.wrappedValue.trimEnd))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Fixed, independent ranges - not each depending on the
                // other's live value - same shape
                // [[feedback-swiftui-slider-interdependent-range]]
                // already fixed elsewhere in this app; ordering is only
                // enforced on release, not mid-drag.
                Slider(value: draft.trimStart, in: 0...draft.wrappedValue.assetDurationSeconds) { editing in
                    guard !editing else { return }
                    if draft.wrappedValue.trimStart > draft.wrappedValue.trimEnd {
                        draft.wrappedValue.trimStart = draft.wrappedValue.trimEnd
                    }
                }
                Slider(value: draft.trimEnd, in: 0...draft.wrappedValue.assetDurationSeconds) { editing in
                    guard !editing else { return }
                    if draft.wrappedValue.trimEnd < draft.wrappedValue.trimStart {
                        draft.wrappedValue.trimEnd = draft.wrappedValue.trimStart
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func previewSection(_ url: URL) -> some View {
        Section {
            Button {
                togglePlayback()
            } label: {
                Label(isPlaying ? "Pause" : "Play Mix", systemImage: isPlaying ? "pause.fill" : "play.fill")
            }

            TextField("Mix name", text: $mixName)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                saveMix(sourceURL: url)
            } label: {
                HStack {
                    Spacer()
                    Text(isSaving ? "Saving…" : "Save to Library")
                        .font(.headline)
                    Spacer()
                }
            }
            .disabled(isSaving)

            Button("Discard and Keep Editing", role: .destructive) {
                player?.pause()
                player = nil
                isPlaying = false
                exportedMixURL = nil
                errorMessage = nil
            }
            .disabled(isSaving)
        }
    }

    private func resolveAudioURL(_ assetId: String) -> URL? {
        audioAssetsById[assetId]?.fileURL
    }

    private func addClip(_ asset: LibraryAudioAsset) {
        audioAssetsById[asset.id] = asset
        let duration = asset.durationSeconds > 0 ? asset.durationSeconds : 1
        drafts.append(MixClipDraft(
            id: UUID(),
            assetId: asset.id,
            assetName: asset.name,
            assetDurationSeconds: duration,
            startTime: 0,
            volume: 1.0,
            trimStart: 0,
            trimEnd: duration
        ))
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            // `seek(to:)` is asynchronous - calling `play()` immediately
            // after it (the previous code) can start playback before the
            // seek actually lands, perceived as a stray delay/stutter at
            // the very start. Playing only from the seek's own completion
            // handler guarantees playback genuinely starts at zero.
            isPlaying = true
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [player] _ in
                player.play()
            }
        }
    }

    private func startExport() {
        errorMessage = nil
        isExporting = true
        let overlays = drafts.map { $0.toOverlayItem() }
        exportAudioMix(overlays: overlays, resolveAudioURL: resolveAudioURL) { result in
            isExporting = false
            switch result {
            case .failure(let error):
                errorMessage = "Couldn't create the mix: \(error.localizedDescription)"
            case .success(let url):
                exportedMixURL = url
                player = AVPlayer(url: url)
            }
        }
    }

    private func saveMix(sourceURL: URL) {
        isSaving = true
        errorMessage = nil
        let trimmedName = mixName.trimmingCharacters(in: .whitespaces)
        let finalName = trimmedName.isEmpty ? "New Mix" : trimmedName

        Task {
            let asset = AVURLAsset(url: sourceURL)
            let loadedDuration = try? await asset.load(.duration)
            let seconds = loadedDuration?.seconds.isFinite == true ? loadedDuration!.seconds : 0

            await MainActor.run {
                authManager.saveAudioAsset(AudioAssetItem(name: finalName, durationSeconds: seconds)) { result in
                    isSaving = false
                    switch result {
                    case .success(let saved):
                        if let id = saved.id {
                            saveLocalAudioAsset(from: sourceURL, assetId: id)
                        }
                        onSaved()
                        dismiss()
                    case .failure(let error):
                        errorMessage = "Couldn't save: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
