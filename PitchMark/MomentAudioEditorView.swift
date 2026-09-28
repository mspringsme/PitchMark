//
//  MomentAudioEditorView.swift
//  PitchMark
//
//  2026-09-28: place recorded/library audio clips onto a Moment's video
//  at a chosen start time and volume, and turn down or mute the
//  Moment's own recorded audio - either flat, or varying at chosen
//  points along the timeline (same interaction model as
//  MomentSpeedEditorView's speed keyframes: Add Point, tap-to-select a
//  marker, adjust with a slider, delete).
//
//  Unlike MomentSpeedEditorView, audio mixing never changes the video's
//  own timeline (no retiming, just extra/adjusted audio tracks), so
//  there's no source-time-vs-composite-time split to work around here -
//  `player` always plays the *current* mixed composition directly
//  (rebuilt via `rebuildPreview()` whenever a volume or overlay changes,
//  keeping the playhead position across the rebuild), and a normal
//  periodic time observer drives a live playhead during playback.
//
//  Scrubbing lives on its own dedicated ruler (`scrubRuler`), never
//  sharing a gesture-recognizer parent with the audio-overlay bars
//  below it (`timelineTrack`) - the same split OverlayTimelineView.swift
//  uses (a plain rulerRow above track rows) and for the same reason: a
//  tap gesture on a child view (the overlay bar, here) wins the gesture
//  arena over an ancestor's drag gesture, so a single shared
//  ZStack+DragGesture covering both a wide tappable bar and the intended
//  scrub area silently ate scrubbing wherever a bar was drawn - worse
//  the longer the placed clip, up to blocking the whole timeline for a
//  clip as long as the video. Splitting them into separate views with
//  separate gesture recognizers removes the conflict entirely rather
//  than trying to out-prioritize it.
//
//  Reuses PlayerContainerView (OverlayEditorView.swift) and
//  timeToX/xToTime (OverlayTimelineView.swift) as-is.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI
import AVFoundation

struct MomentAudioEditorView: View {
    let momentId: String
    let videoURL: URL
    var onExported: () -> Void = {}

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var player = AVPlayer()
    @State private var totalDuration: Double = 0
    @State private var currentTime: Double = 0
    @State private var isPlaying = false
    @State private var timeObserverToken: Any?

    @State private var originalVolume: Double
    @State private var originalVolumeKeyframes: [VolumeKeyframe]
    @State private var selectedOriginalKeyframeID: UUID? = nil

    @State private var audioOverlays: [AudioOverlayItem]
    @State private var audioAssetsById: [String: AudioAssetItem] = [:]

    @State private var selectedOverlayID: UUID? = nil
    @State private var selectedOverlayKeyframeID: UUID? = nil
    @State private var showAssetPicker = false

    @State private var isBuildingPreview = false
    @State private var previewErrorMessage: String? = nil
    @State private var isExporting = false
    @State private var exportErrorMessage: String? = nil

    init(
        momentId: String,
        videoURL: URL,
        initialAudioOverlays: [AudioOverlayItem],
        initialOriginalVolume: Double,
        initialOriginalVolumeKeyframes: [VolumeKeyframe] = [],
        onExported: @escaping () -> Void = {}
    ) {
        self.momentId = momentId
        self.videoURL = videoURL
        self.onExported = onExported
        _audioOverlays = State(initialValue: initialAudioOverlays)
        _originalVolume = State(initialValue: initialOriginalVolume)
        _originalVolumeKeyframes = State(initialValue: initialOriginalVolumeKeyframes)
    }

    var body: some View {
        VStack(spacing: 0) {
            PlayerContainerView(player: player)
                .background(Color.black)
                .frame(maxHeight: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(formattedTime(currentTime)) / \(formattedTime(totalDuration))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        scrubRuler
                    }

                    if let previewErrorMessage {
                        Text(previewErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    originalAudioSection

                    Divider()

                    overlaysSection
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            HStack {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                }

                Spacer()

                Button {
                    showAssetPicker = true
                } label: {
                    Label("Add Audio", systemImage: "waveform.badge.plus")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            Button {
                startExport()
            } label: {
                Text("Export")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white, in: Capsule())
            }
            .padding(.top, 50)
            .padding(.leading, 20)
            .disabled(isExporting)
        }
        .overlay(alignment: .topTrailing) {
            // This whole screen ignores the safe area (see
            // MomentDetailView's .ignoresSafeArea() on the
            // fullScreenCover) - a bare `.padding()` here would land
            // under the notch/Dynamic Island, same lesson as every other
            // full-bleed editor in this app.
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding(.top, 50)
            .padding(.trailing, 20)
        }
        .overlay {
            if isExporting || isBuildingPreview {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text(isExporting ? "Exporting…" : "Updating preview…")
                            .foregroundStyle(.white)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let exportErrorMessage {
                Text(exportErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.bottom, 12)
                    .onTapGesture { self.exportErrorMessage = nil }
            }
        }
        .sheet(isPresented: $showAssetPicker) {
            AudioAssetLibraryView(onPick: { asset in
                addOverlay(for: asset)
            })
            .environmentObject(authManager)
        }
        .onAppear { setUp() }
        .onDisappear { tearDown() }
    }

    // MARK: Scrubbing

    /// The only place a drag gesture lives in this screen - see the file
    /// header comment for why it's split out from `timelineTrack`.
    private var scrubRuler: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray4))
                    .frame(height: 4)
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
                    .offset(x: timeToX(time: currentTime, duration: totalDuration, trackWidth: width) - 5)
            }
            .frame(height: 16, alignment: .top)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        seek(to: xToTime(x: value.location.x, duration: totalDuration, trackWidth: width))
                    }
            )
        }
        .frame(height: 20)
    }

    // MARK: Original audio

    private var originalAudioSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Original Audio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if originalVolumeKeyframes.isEmpty {
                    Button {
                        toggleMute()
                    } label: {
                        Image(systemName: originalVolume <= 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                }
            }

            if originalVolumeKeyframes.isEmpty {
                Slider(
                    value: Binding(
                        get: { originalVolume },
                        set: { originalVolume = $0 }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if !editing { persistOriginalVolume() }
                    }
                )
            } else {
                VolumeKeyframeStrip(
                    rangeStart: 0,
                    rangeEnd: max(totalDuration, 0.01),
                    keyframes: originalVolumeKeyframes,
                    selectedID: selectedOriginalKeyframeID,
                    onSelect: { selectedOriginalKeyframeID = $0 }
                )
                volumeKeyframeDetailRow(
                    keyframes: $originalVolumeKeyframes,
                    selectedID: $selectedOriginalKeyframeID,
                    onCommit: { persistOriginalVolumeKeyframes() }
                )
            }

            Button {
                addVolumeKeyframe(
                    to: $originalVolumeKeyframes,
                    selectedID: $selectedOriginalKeyframeID,
                    at: currentTime,
                    flatFallback: originalVolume,
                    rangeStart: 0,
                    rangeEnd: max(totalDuration, 0.01)
                ) { persistOriginalVolumeKeyframes() }
            } label: {
                Label("Add Volume Point", systemImage: "plus.circle.fill")
                    .font(.caption)
            }
        }
    }

    private func toggleMute() {
        originalVolume = originalVolume <= 0.001 ? 1.0 : 0.0
        persistOriginalVolume()
    }

    private func persistOriginalVolume() {
        guard !momentId.isEmpty else { return }
        authManager.updateMomentFields(momentId: momentId, fields: ["originalAudioVolume": originalVolume]) { _ in }
        rebuildPreview()
    }

    private func persistOriginalVolumeKeyframes() {
        guard !momentId.isEmpty else { return }
        authManager.updateMomentOriginalVolumeKeyframes(momentId: momentId, keyframes: originalVolumeKeyframes) { _ in }
        rebuildPreview()
    }

    // MARK: Overlays

    private var overlaysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Added Audio")
                .font(.caption)
                .foregroundStyle(.secondary)

            timelineTrack

            selectedOverlayRow
        }
    }

    /// Tap-to-select only - deliberately no gesture attached here at
    /// all. Scrubbing happens on `scrubRuler` above.
    private var timelineTrack: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))
                    .frame(height: 6)

                ForEach(audioOverlays) { overlay in
                    overlayBar(overlay, trackWidth: width)
                }

                Rectangle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 2, height: 32)
                    .position(x: timeToX(time: currentTime, duration: totalDuration, trackWidth: width), y: 17)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 34)
    }

    private func overlayBar(_ overlay: AudioOverlayItem, trackWidth: CGFloat) -> some View {
        let assetDuration = audioAssetsById[overlay.assetId]?.durationSeconds ?? 1
        let endTime = min(overlay.startTime + assetDuration, max(totalDuration, overlay.startTime))
        let x = timeToX(time: overlay.startTime, duration: totalDuration, trackWidth: trackWidth)
        let endX = timeToX(time: endTime, duration: totalDuration, trackWidth: trackWidth)
        let blockWidth = max(endX - x, 4)
        let isSelected = overlay.id == selectedOverlayID

        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(isSelected ? Color.purple.opacity(0.75) : Color.purple.opacity(0.4))
            .frame(width: blockWidth, height: 24)
            .position(x: x + blockWidth / 2, y: 17)
            .onTapGesture {
                selectedOverlayID = overlay.id
                selectedOverlayKeyframeID = nil
            }
    }

    @ViewBuilder
    private var selectedOverlayRow: some View {
        if let selectedOverlayID, let index = audioOverlays.firstIndex(where: { $0.id == selectedOverlayID }) {
            let overlay = audioOverlays[index]
            let name = audioAssetsById[overlay.assetId]?.name ?? "Audio"
            let assetDuration = audioAssetsById[overlay.assetId]?.durationSeconds ?? 1
            let clipEnd = max(overlay.startTime + assetDuration, overlay.startTime + 0.01)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        audioOverlays.remove(at: index)
                        self.selectedOverlayID = nil
                        self.selectedOverlayKeyframeID = nil
                        persistOverlays()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.caption)
                    }
                }

                HStack {
                    Text("Start")
                        .font(.caption2)
                        .frame(width: 44, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { audioOverlays[index].startTime },
                            set: { audioOverlays[index].startTime = min(max($0, 0), totalDuration) }
                        ),
                        in: 0...max(totalDuration, 0.01),
                        onEditingChanged: { editing in
                            if !editing { persistOverlays() }
                        }
                    )
                    Text(formattedTime(audioOverlays[index].startTime))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Volume")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if (audioOverlays[index].volumeKeyframes ?? []).isEmpty {
                        Slider(
                            value: Binding(
                                get: { audioOverlays[index].volume },
                                set: { audioOverlays[index].volume = $0 }
                            ),
                            in: 0...1,
                            onEditingChanged: { editing in
                                if !editing { persistOverlays() }
                            }
                        )
                    } else {
                        VolumeKeyframeStrip(
                            rangeStart: overlay.startTime,
                            rangeEnd: clipEnd,
                            keyframes: audioOverlays[index].volumeKeyframes ?? [],
                            selectedID: selectedOverlayKeyframeID,
                            onSelect: { selectedOverlayKeyframeID = $0 }
                        )
                        volumeKeyframeDetailRow(
                            keyframes: overlayVolumeKeyframesBinding(index),
                            selectedID: $selectedOverlayKeyframeID,
                            onCommit: { persistOverlays() }
                        )
                    }

                    Button {
                        addVolumeKeyframe(
                            to: overlayVolumeKeyframesBinding(index),
                            selectedID: $selectedOverlayKeyframeID,
                            at: currentTime,
                            flatFallback: audioOverlays[index].volume,
                            rangeStart: overlay.startTime,
                            rangeEnd: clipEnd
                        ) { persistOverlays() }
                    } label: {
                        Label("Add Volume Point", systemImage: "plus.circle.fill")
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func overlayVolumeKeyframesBinding(_ index: Int) -> Binding<[VolumeKeyframe]> {
        Binding(
            get: { audioOverlays[index].volumeKeyframes ?? [] },
            set: { audioOverlays[index].volumeKeyframes = $0 }
        )
    }

    private func addOverlay(for asset: AudioAssetItem) {
        guard let id = asset.id else { return }
        audioAssetsById[id] = asset
        let overlay = AudioOverlayItem(assetId: id, startTime: currentTime, volume: 1.0)
        audioOverlays.append(overlay)
        selectedOverlayID = overlay.id
        selectedOverlayKeyframeID = nil
        persistOverlays()
    }

    private func persistOverlays() {
        guard !momentId.isEmpty else { return }
        authManager.updateMomentAudioOverlays(momentId: momentId, audioOverlays: audioOverlays) { _ in }
        rebuildPreview()
    }

    // MARK: Shared volume-keyframe controls

    /// Small tap-to-select strip of keyframe markers - reused for both
    /// the original track and whichever overlay is selected. No drag
    /// gesture of its own; see the file header comment.
    private struct VolumeKeyframeStrip: View {
        let rangeStart: Double
        let rangeEnd: Double
        let keyframes: [VolumeKeyframe]
        let selectedID: UUID?
        let onSelect: (UUID) -> Void

        var body: some View {
            GeometryReader { geometry in
                let width = geometry.size.width
                let span = max(rangeEnd - rangeStart, 0.01)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(height: 4)

                    ForEach(keyframes) { keyframe in
                        marker(keyframe, trackWidth: width, span: span)
                    }
                }
            }
            .frame(height: 34)
        }

        /// 34x34pt tap target around the small visual diamond - the same
        /// enlarged-target convention every other keyframe marker in
        /// this app uses (OverlayTimelineView, MomentSpeedEditorView).
        private func marker(_ keyframe: VolumeKeyframe, trackWidth: CGFloat, span: Double) -> some View {
            let x = timeToX(time: keyframe.time - rangeStart, duration: span, trackWidth: trackWidth)
            let isSelected = keyframe.id == selectedID

            return Color.clear
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isSelected ? Color.yellow : Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.35), lineWidth: 1)
                        )
                        .frame(width: 9, height: 9)
                        .rotationEffect(.degrees(45))
                )
                .position(x: x, y: 17)
                .onTapGesture { onSelect(keyframe.id) }
        }
    }

    @ViewBuilder
    private func volumeKeyframeDetailRow(keyframes: Binding<[VolumeKeyframe]>, selectedID: Binding<UUID?>, onCommit: @escaping () -> Void) -> some View {
        if let id = selectedID.wrappedValue, let index = keyframes.wrappedValue.firstIndex(where: { $0.id == id }) {
            HStack {
                Slider(
                    value: Binding(
                        get: { keyframes.wrappedValue[index].volume },
                        set: { keyframes.wrappedValue[index].volume = $0 }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if !editing { onCommit() }
                    }
                )
                Button(role: .destructive) {
                    keyframes.wrappedValue.remove(at: index)
                    selectedID.wrappedValue = nil
                    onCommit()
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }

    private func addVolumeKeyframe(
        to keyframes: Binding<[VolumeKeyframe]>,
        selectedID: Binding<UUID?>,
        at time: Double,
        flatFallback: Double,
        rangeStart: Double,
        rangeEnd: Double,
        onCommit: @escaping () -> Void
    ) {
        let clamped = min(max(time, rangeStart), rangeEnd)
        let currentVolume = volumeAt(clamped, keyframes: keyframes.wrappedValue, flat: flatFallback)
        let newKeyframe = VolumeKeyframe(time: clamped, volume: currentVolume)
        keyframes.wrappedValue.append(newKeyframe)
        keyframes.wrappedValue.sort { $0.time < $1.time }
        selectedID.wrappedValue = newKeyframe.id
        onCommit()
    }

    private func formattedTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Playback

    private func setUp() {
        let asset = AVURLAsset(url: videoURL)
        Task {
            let loadedDuration = try? await asset.load(.duration)
            await MainActor.run {
                totalDuration = loadedDuration?.seconds.isFinite == true ? loadedDuration!.seconds : 0
                authManager.loadAudioAssets { assets in
                    for asset in assets {
                        if let id = asset.id { audioAssetsById[id] = asset }
                    }
                    rebuildPreview()
                }
            }
        }

        timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { time in
            currentTime = time.seconds
        }
    }

    private func tearDown() {
        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }
        timeObserverToken = nil
        player.pause()
    }

    private func seek(to time: Double) {
        let clamped = min(max(time, 0), totalDuration)
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func resolveAudioURL(_ assetId: String) -> URL? {
        localAudioAssetURL(for: assetId)
    }

    /// Rebuilds the mixed composition and swaps it in, preserving
    /// playback position/state across the swap - called after every
    /// committed edit (slider release, add, delete), never on every
    /// intermediate drag tick.
    private func rebuildPreview() {
        isBuildingPreview = true
        previewErrorMessage = nil
        let wasPlaying = isPlaying
        let seekTime = currentTime

        buildAudioMixedComposition(
            sourceURL: videoURL,
            audioOverlays: audioOverlays,
            originalVolume: originalVolume,
            originalVolumeKeyframes: originalVolumeKeyframes,
            resolveAudioURL: resolveAudioURL
        ) { result in
            isBuildingPreview = false
            switch result {
            case .success(let built):
                let item = AVPlayerItem(asset: built.composition)
                item.audioMix = built.audioMix
                player.replaceCurrentItem(with: item)
                player.seek(to: CMTime(seconds: seekTime, preferredTimescale: 600))
                if wasPlaying { player.play() }
            case .failure(let error):
                previewErrorMessage = "Couldn't preview: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Export

    private func startExport() {
        guard !momentId.isEmpty else { return }
        if isPlaying { togglePlayback() }
        exportErrorMessage = nil
        isExporting = true

        exportAudioMixedMoment(
            sourceURL: videoURL,
            audioOverlays: audioOverlays,
            originalVolume: originalVolume,
            originalVolumeKeyframes: originalVolumeKeyframes,
            resolveAudioURL: resolveAudioURL
        ) { result in
            isExporting = false
            switch result {
            case .success(let tempURL):
                guard let destination = localMomentEditedVideoURL(for: momentId) else {
                    exportErrorMessage = "Couldn't save the exported video."
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: tempURL, to: destination)
                    try? FileManager.default.removeItem(at: tempURL)
                    onExported()
                    dismiss()
                } catch {
                    exportErrorMessage = "Couldn't save the exported video: \(error.localizedDescription)"
                }
            case .failure(let error):
                debugLog("❌ exportAudioMixedMoment failed:", error.localizedDescription)
                exportErrorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}
