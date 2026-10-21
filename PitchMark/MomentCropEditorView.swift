//
//  MomentCropEditorView.swift
//  PitchMark
//
//  The editing screen for MomentCrop.swift's aspect-ratio crop/reframe -
//  pick a target aspect, then drag to move the crop WINDOW itself over a
//  fixed, never-moving video (the opposite of the "drag the photo under a
//  fixed frame" convention some crop tools use) - so the window has to
//  track the finger directly, same direction, no negated delta in
//  `cropOffsetAfterDrag`. A prior version negated it, which visually
//  moved the window backwards relative to the drag - reported by the
//  user as the crop box moving "reverse" to the touch. Zoom is a Slider,
//  not a pinch gesture, same lesson MomentZoomEditorView's header comment
//  already documents from OverlayEditorView's own pinch/rotate attempt.
//  Static setting for the whole clip, no timeline - confirmed scope with
//  the user, unlike MomentZoomEditorView's draggable/resizable timeline
//  regions.
//
//  Doesn't autoplay on appear, and has an explicit play/pause button
//  (same `isPlaying`/`togglePlayback` shape as MomentZoomEditorView) - a
//  prior version called `player.play()` in `onAppear` with no way to
//  stop it, reported by the user as "the clip plays and there are no
//  controls to stop it."
//
//  Reuses `PlayerContainerView`/`videoDisplayRect` (OverlayEditorView.swift)
//  for the aspect-fit video surface - both already generic, same reuse
//  MomentSpeedEditorView.swift's own header comment calls out.
//
//  Reuses `cropBaseVideoURL`/`invalidateMomentCropBase` (Moment.swift) -
//  same frozen-base technique Zoom/Overlay/Audio/Slideshow already use,
//  so re-opening this screen after a prior crop export edits against the
//  pre-crop pixels, never a stacked re-crop of its own last bake.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI
import AVFoundation

struct MomentCropEditorView: View {
    let momentId: String
    let videoURL: URL
    /// The frozen crop-bake base - both the live preview player and
    /// `startExport()` use this, never `videoURL` directly once a prior
    /// crop export exists for this Moment.
    private let previewBaseURL: URL
    var onExported: () -> Void = {}

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer
    @State private var cropSettings: CropSettings
    @State private var naturalSize: CGSize = .zero
    @GestureState private var dragTranslation: CGSize = .zero
    @State private var isPlaying = false
    @State private var duration: Double = 0
    @State private var currentTime: Double = 0
    @State private var timeObserverToken: Any?

    @State private var isExporting = false
    @State private var exportErrorMessage: String? = nil

    init(momentId: String, videoURL: URL, initialCropSettings: CropSettings?, onExported: @escaping () -> Void = {}) {
        self.momentId = momentId
        self.videoURL = videoURL
        let baseURL = cropBaseVideoURL(momentId: momentId, sourceVideoURL: videoURL)
        self.previewBaseURL = baseURL
        self.onExported = onExported
        _player = State(initialValue: AVPlayer(url: baseURL))
        _cropSettings = State(initialValue: initialCropSettings ?? CropSettings())
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                videoArea
                    .background(Color.black)
                    .frame(maxHeight: .infinity)

                scrubberRow
                    .padding(.horizontal)
                    .padding(.top, 8)

                HStack {
                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 32))
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 10)

                VStack(alignment: .leading, spacing: 12) {
                    Picker("Aspect", selection: $cropSettings.aspect) {
                        ForEach(CropAspect.allCases, id: \.self) { aspect in
                            Text(aspect.displayName).tag(aspect)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Zoom is available on every aspect, Original included -
                    // zooming into the original aspect is a real "zoom crop"
                    // on its own, not just a pan-position aid for the other
                    // two. Only the drag hint is aspect-conditional, since
                    // Original has no pan slack to speak of until zoomed in.
                    HStack {
                        Image(systemName: "minus.magnifyingglass")
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { cropSettings.resolvedScale },
                                set: { cropSettings.scale = $0 }
                            ),
                            in: minCropZoomScale...maxCropZoomScale
                        )
                        Image(systemName: "plus.magnifyingglass")
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1fx", cropSettings.resolvedScale))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }

                    if cropSettings.aspect != .original || cropSettings.resolvedScale > minCropZoomScale {
                        Text("Drag the video to reposition the crop window.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let exportErrorMessage {
                        Text(exportErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        startExport()
                    } label: {
                        HStack {
                            Spacer()
                            Text(isExporting ? "Applying Crop…" : "Apply Crop")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(isExporting)
                }
                .padding()
            }
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isExporting)
                }
            }
        }
        .onAppear {
            setUpPlayer()
        }
        .onDisappear {
            tearDownPlayer()
        }
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    /// Same ruler shape as `OverlayTimelineView`'s `rulerRow` (reusing its
    /// already-generic `timeToX`/`xToTime`), minus the overlay-specific
    /// tracks/keyframes Crop has no use for: a time label, a draggable
    /// playhead over a capsule track, and drag-to-seek with zero
    /// tolerance so the preview lands frame-accurately while scrubbing.
    private var scrubberRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(formattedTime(currentTime)) / \(formattedTime(duration))")
                .font(.caption2)
                .foregroundStyle(.secondary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray4))
                        .frame(height: 4)

                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                        .offset(x: timeToX(time: currentTime, duration: duration, trackWidth: geometry.size.width) - 5)
                }
                .frame(height: 16, alignment: .top)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            seek(to: xToTime(x: value.location.x, duration: duration, trackWidth: geometry.size.width))
                        }
                )
            }
            .frame(height: 20)
        }
    }

    private func formattedTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func seek(to time: Double) {
        let clamped = min(max(time, 0), duration)
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private var videoArea: some View {
        GeometryReader { geometry in
            let renderSize = cropRenderSize(sourceSize: naturalSize, aspect: cropSettings.aspect)
            let videoRect = videoDisplayRect(containerSize: geometry.size, naturalSize: naturalSize)
            let liveOffset = cropOffsetAfterDrag(
                base: cropSettings.offset,
                dragTranslation: dragTranslation,
                displayedVideoSize: videoRect.size,
                sourceSize: naturalSize,
                renderSize: renderSize,
                scale: cropSettings.resolvedScale
            )
            let windowRect = cropWindowRect(
                sourceSize: naturalSize,
                renderSize: renderSize,
                offset: liveOffset,
                displayedVideoSize: videoRect.size,
                scale: cropSettings.resolvedScale
            ).offsetBy(dx: videoRect.minX, dy: videoRect.minY)

            ZStack {
                PlayerContainerView(player: player)
                if naturalSize.width > 0 {
                    CropMaskOverlay(containerSize: geometry.size, windowRect: windowRect)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($dragTranslation) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        guard naturalSize.width > 0 else { return }
                        let newOffset = cropOffsetAfterDrag(
                            base: cropSettings.offset,
                            dragTranslation: value.translation,
                            displayedVideoSize: videoRect.size,
                            sourceSize: naturalSize,
                            renderSize: renderSize,
                            scale: cropSettings.resolvedScale
                        )
                        cropSettings.offsetX = newOffset.x
                        cropSettings.offsetY = newOffset.y
                    }
            )
        }
    }

    private func setUpPlayer() {
        let asset = AVURLAsset(url: previewBaseURL)
        Task {
            let loadedDuration = try? await asset.load(.duration)
            let tracks = try? await asset.loadTracks(withMediaType: .video)
            let track = tracks?.first
            let rawSize = try? await track?.load(.naturalSize)
            let transform = try? await track?.load(.preferredTransform)
            await MainActor.run {
                duration = loadedDuration?.seconds.isFinite == true ? loadedDuration!.seconds : 0
                // Same preferredTransform-aware natural size every
                // preview/export in this feature uses - see
                // MomentZoomEditorView.swift's setUpPlayer for why
                // naturalSize alone isn't enough for a portrait recording.
                if let rawSize, let transform {
                    let transformedSize = rawSize.applying(transform)
                    naturalSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
                } else {
                    naturalSize = rawSize ?? .zero
                }
            }
        }

        timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { time in
            currentTime = time.seconds
        }
    }

    private func tearDownPlayer() {
        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }
        timeObserverToken = nil
        player.pause()
    }

    private func startExport() {
        exportErrorMessage = nil
        guard let destination = localMomentEditedVideoURL(for: momentId) else { return }
        isExporting = true
        exportCroppedMoment(sourceURL: previewBaseURL, cropSettings: cropSettings) { result in
            switch result {
            case .failure(let error):
                isExporting = false
                exportErrorMessage = "Couldn't apply the crop: \(error.localizedDescription)"
            case .success(let tempURL):
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: tempURL, to: destination)
                    try? FileManager.default.removeItem(at: tempURL)
                    // Every other frozen-base ring member now misses
                    // this crop - see Moment.swift's
                    // invalidateOtherFrozenBases doc comment.
                    invalidateOtherFrozenBases(momentId: momentId, except: [.crop])
                    // See MomentAudioEditorView.swift's identical comment.
                    refreshFadeIfNeeded(momentId: momentId, authManager: authManager) { onExported() }
                    authManager.updateMomentCropSettings(momentId: momentId, cropSettings: cropSettings) { _ in }
                    isExporting = false
                    onExported()
                    dismiss()
                } catch {
                    isExporting = false
                    exportErrorMessage = "Couldn't save the cropped video: \(error.localizedDescription)"
                }
            }
        }
    }
}

/// Dims everything outside `windowRect` within `containerSize` - the
/// standard "punch a hole" SwiftUI mask technique
/// (`.blendMode(.destinationOut)` inside a `.compositingGroup()`), plus a
/// white border tracing the live crop window.
private struct CropMaskOverlay: View {
    let containerSize: CGSize
    let windowRect: CGRect

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .frame(width: containerSize.width, height: containerSize.height)
            Rectangle()
                .frame(width: windowRect.width, height: windowRect.height)
                .position(x: windowRect.midX, y: windowRect.midY)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .overlay(
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: windowRect.width, height: windowRect.height)
                .position(x: windowRect.midX, y: windowRect.midY)
        )
    }
}
