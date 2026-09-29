//
//  MomentSpeedEditorView.swift
//  PitchMark
//
//  2026-09-28: the editing screen for MomentSpeedRamp.swift's keyframes -
//  mark points in a Moment's video and assign each a playback speed.
//
//  Reuses PlayerContainerView/PlayerLayerContainerUIView
//  (OverlayEditorView.swift) and timeToX/xToTime (OverlayTimelineView.swift)
//  as-is - both are generic, with no overlay-specific coupling.
//
//  Key design point, worth restating here since it drives this file's
//  structure: once any segment's speed isn't 1x, the *retimed* timeline
//  no longer matches the *original* one-to-one. Keyframes are authored
//  in source time; this screen's ruler/scrubber is *always* source time
//  too, matching how a user thinks about "my original clip." Play
//  builds the actual retimed composition (the same one export uses) and
//  plays it from the equivalent starting point (one-way source ->
//  composite conversion via `sourceTimeToCompositeTime`), then switches
//  back to plain source-time playback on pause or at the end. There is
//  no attempt to keep a single live playhead in sync across both time
//  spaces during playback - that needs a harder inverse mapping this
//  screen deliberately doesn't build.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI
import AVFoundation

struct MomentSpeedEditorView: View {
    let momentId: String
    let videoURL: URL
    var onExported: () -> Void = {}

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer
    @State private var keyframes: [SpeedKeyframe]

    @State private var totalDuration: Double = 0
    @State private var currentSourceTime: Double = 0
    @State private var isPlayingComposite = false
    @State private var isBuildingPreview = false
    @State private var compositeEndObserver: NSObjectProtocol?

    @State private var selectedKeyframeID: UUID? = nil

    @State private var isExporting = false
    @State private var exportErrorMessage: String? = nil
    @State private var previewErrorMessage: String? = nil

    init(momentId: String, videoURL: URL, initialKeyframes: [SpeedKeyframe], onExported: @escaping () -> Void = {}) {
        self.momentId = momentId
        self.videoURL = videoURL
        self.onExported = onExported
        _player = State(initialValue: AVPlayer(url: videoURL))
        _keyframes = State(initialValue: initialKeyframes)
    }

    private var ranges: [(start: Double, end: Double, speed: Double)] {
        speedRanges(keyframes: keyframes, totalDuration: max(totalDuration, 0.01))
    }

    var body: some View {
        VStack(spacing: 0) {
            PlayerContainerView(player: player)
                .background(Color.black)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(formattedTime(currentSourceTime)) / \(formattedTime(totalDuration))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                timelineTrack

                if let previewErrorMessage {
                    Text(previewErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                selectedKeyframeRow
            }
            .padding(.horizontal)
            .padding(.top, 8)

            HStack {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlayingComposite ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                }
                .disabled(isBuildingPreview)

                Spacer()

                Button {
                    addKeyframeAtCurrentTime()
                } label: {
                    Label("Add Speed Point", systemImage: "plus.circle.fill")
                }
                .disabled(isPlayingComposite)
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
                        Text(isExporting ? "Exporting…" : "Preparing preview…")
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
        .onAppear { loadDuration() }
        .onDisappear {
            player.pause()
            if let compositeEndObserver {
                NotificationCenter.default.removeObserver(compositeEndObserver)
            }
        }
    }

    // MARK: Timeline

    private var timelineTrack: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                ForEach(Array(ranges.enumerated()), id: \.offset) { _, range in
                    let x = timeToX(time: range.start, duration: totalDuration, trackWidth: width)
                    let endX = timeToX(time: range.end, duration: totalDuration, trackWidth: width)
                    let blockWidth = max(endX - x, 2)
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(colorForSpeed(range.speed))
                        if blockWidth > 28 {
                            Text(labelForSpeed(range.speed))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: blockWidth, height: 28)
                    .position(x: x + blockWidth / 2, y: 20)
                }

                ForEach(keyframes) { keyframe in
                    keyframeMarker(keyframe, trackWidth: width)
                }

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: 36)
                    .position(x: timeToX(time: currentSourceTime, duration: totalDuration, trackWidth: width), y: 20)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        seekSource(to: xToTime(x: value.location.x, duration: totalDuration, trackWidth: width))
                    }
            )
        }
        .frame(height: 40)
    }

    /// 34x34pt tap target around the small visual diamond - the same
    /// enlarged-target fix already applied to every other keyframe
    /// marker in this app (OverlayTimelineView, AssetCreationFlow's
    /// Smart Cutout picker).
    private func keyframeMarker(_ keyframe: SpeedKeyframe, trackWidth: CGFloat) -> some View {
        let x = timeToX(time: keyframe.time, duration: totalDuration, trackWidth: trackWidth)
        let isSelected = keyframe.id == selectedKeyframeID

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
            .position(x: x, y: 20)
            .onTapGesture {
                selectedKeyframeID = keyframe.id
            }
    }

    @ViewBuilder
    private var selectedKeyframeRow: some View {
        if let selectedKeyframeID, let index = keyframes.firstIndex(where: { $0.id == selectedKeyframeID }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Speed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        keyframes.remove(at: index)
                        self.selectedKeyframeID = nil
                        persistKeyframes()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.caption)
                    }
                }
                HStack {
                    Slider(
                        value: Binding(
                            get: { keyframes[index].speed },
                            set: { keyframes[index].speed = snappedSpeed($0) }
                        ),
                        in: 0.25...4,
                        onEditingChanged: { editing in
                            if !editing { persistKeyframes() }
                        }
                    )
                    Text(labelForSpeed(keyframes[index].speed))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }

    /// "Snap to every 0.25x while still allowing in-between speeds" -
    /// a magnetic assist, not a hard `step` (which would remove
    /// in-between values entirely): within `tolerance` of a 0.25
    /// multiple, round to it; otherwise pass the dragged value through
    /// unchanged, so a precise drag can still land on e.g. 1.4x.
    private func snappedSpeed(_ raw: Double) -> Double {
        let step = 0.25
        let tolerance = 0.03
        let nearest = (raw / step).rounded() * step
        return abs(raw - nearest) <= tolerance ? nearest : raw
    }

    private func labelForSpeed(_ speed: Double) -> String {
        if abs(speed - 1.0) < 0.001 { return "1x" }
        return String(format: "%gx", speed)
    }

    private func colorForSpeed(_ speed: Double) -> Color {
        if speed < 1.0 { return Color.blue.opacity(0.55) }
        if speed > 1.0 { return Color.orange.opacity(0.55) }
        return Color(.systemGray4)
    }

    private func formattedTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Playback

    private func loadDuration() {
        let asset = AVURLAsset(url: videoURL)
        Task {
            let loadedDuration = try? await asset.load(.duration)
            await MainActor.run {
                totalDuration = loadedDuration?.seconds.isFinite == true ? loadedDuration!.seconds : 0
            }
        }
    }

    private func seekSource(to time: Double) {
        guard !isPlayingComposite else { return }
        let clamped = min(max(time, 0), totalDuration)
        currentSourceTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func togglePlayback() {
        if isPlayingComposite {
            stopCompositePlayback()
            return
        }

        isBuildingPreview = true
        previewErrorMessage = nil
        buildSpeedRampedComposition(sourceURL: videoURL, keyframes: keyframes) { result in
            isBuildingPreview = false
            switch result {
            case .success(let composition):
                let compositeTime = sourceTimeToCompositeTime(currentSourceTime, ranges: ranges)
                let item = AVPlayerItem(asset: composition)
                if let compositeEndObserver {
                    NotificationCenter.default.removeObserver(compositeEndObserver)
                }
                compositeEndObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { _ in
                    stopCompositePlayback()
                }
                player.replaceCurrentItem(with: item)
                player.seek(to: CMTime(seconds: compositeTime, preferredTimescale: 600))
                player.play()
                isPlayingComposite = true
            case .failure(let error):
                debugLog("❌ buildSpeedRampedComposition (preview) failed:", debugErrorDetail(error))
                previewErrorMessage = "Couldn't preview: \(error.localizedDescription)"
            }
        }
    }

    private func stopCompositePlayback() {
        player.pause()
        if let compositeEndObserver {
            NotificationCenter.default.removeObserver(compositeEndObserver)
            self.compositeEndObserver = nil
        }
        player.replaceCurrentItem(with: AVPlayerItem(url: videoURL))
        player.seek(to: CMTime(seconds: currentSourceTime, preferredTimescale: 600))
        isPlayingComposite = false
    }

    // MARK: Editing

    private func addKeyframeAtCurrentTime() {
        let currentSpeed = speed(at: currentSourceTime, keyframes: keyframes)
        let newKeyframe = SpeedKeyframe(time: currentSourceTime, speed: currentSpeed)
        keyframes.append(newKeyframe)
        keyframes.sort { $0.time < $1.time }
        selectedKeyframeID = newKeyframe.id
        persistKeyframes()
    }

    private func persistKeyframes() {
        guard !momentId.isEmpty else { return }
        authManager.updateMomentSpeedKeyframes(momentId: momentId, keyframes: keyframes) { error in
            if let error {
                debugLog("❌ updateMomentSpeedKeyframes failed:", error.localizedDescription)
            }
        }
    }

    // MARK: Export

    private func startExport() {
        guard !momentId.isEmpty else { return }
        if isPlayingComposite { stopCompositePlayback() }
        exportErrorMessage = nil
        isExporting = true

        exportSpeedRampedMoment(sourceURL: videoURL, keyframes: keyframes) { result in
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
                    authManager.refreshMomentDuration(momentId: momentId, videoURL: destination)
                    // The audio-mix and overlay-bake bases (if either
                    // exists) now miss this retime - see Moment.swift's
                    // localMomentAudioBaseVideoURL/localMomentOverlayBaseVideoURL
                    // doc comments.
                    invalidateMomentAudioBase(momentId: momentId)
                    invalidateMomentOverlayBase(momentId: momentId)
                    onExported()
                    dismiss()
                } catch {
                    exportErrorMessage = "Couldn't save the exported video: \(error.localizedDescription)"
                }
            case .failure(let error):
                debugLog("❌ exportSpeedRampedMoment failed:", debugErrorDetail(error))
                exportErrorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}
