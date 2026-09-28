//
//  OverlayEditorView.swift
//  PitchMark
//
//  Step 3 of the 2026-09-26 Asset + Video Overlay Keyframe Editor spec:
//  overlay preview synced to AVPlayer. Step 4 (drag/scale/rotate gestures
//  + auto-keyframe on move) and step 5 (timeline UI) build on top of this
//  screen rather than replacing it - it's the eventual editor's shell.
//
//  Built on a custom AVPlayerLayer host rather than SwiftUI's VideoPlayer
//  because step 4/5 both need to place custom gesture-driven views and a
//  custom timeline precisely over the video, and VideoPlayer's built-in
//  transport controls would fight for the same taps - better to settle on
//  the lower-level layer now than swap later.
//
//  Step 4 extends this same screen in place: real overlay creation (tap a
//  library thumbnail to add one, centered, at the current playhead - the
//  spec's own sanctioned fallback to dragging from the strip), drag on
//  the selected overlay to reposition with auto-keyframe on gesture end
//  (upsertKeyframe, no explicit "add keyframe" control), and persistence
//  via Moment.overlays now that real edits exist worth saving.
//
//  Scale/rotation were originally a pinch/two-finger-rotate gesture too,
//  but the user found both that and the timeline's tiny drag handles
//  (OverlayTimelineView) hard to control by touch on a small portrait
//  screen. Only position stays a direct canvas gesture (a reasonably
//  large touch target - the overlay image itself); scale and rotation
//  moved to sliders in `selectedOverlayPanel`, which edit the same
//  transform-at-the-current-playhead via the same upsertKeyframe path.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI
import AVFoundation

/// Centered aspect-fit ("letterbox") rect for a video's natural size
/// inside a container of `containerSize`. Pure geometry, no UIKit/
/// AVFoundation dependency, so it can be verified standalone (see
/// scratchpad's video_display_rect assertions during development) and so
/// the future export compositor can share this exact math with live
/// preview - overlay normalized (0...1) coordinates must map into this
/// rect, never into the raw container bounds.
func videoDisplayRect(containerSize: CGSize, naturalSize: CGSize) -> CGRect {
    guard containerSize.width > 0, containerSize.height > 0,
          naturalSize.width > 0, naturalSize.height > 0 else {
        return .zero
    }

    let containerAspect = containerSize.width / containerSize.height
    let videoAspect = naturalSize.width / naturalSize.height

    var fitSize = containerSize
    if videoAspect > containerAspect {
        fitSize.height = containerSize.width / videoAspect
    } else {
        fitSize.width = containerSize.height * videoAspect
    }

    let origin = CGPoint(
        x: (containerSize.width - fitSize.width) / 2,
        y: (containerSize.height - fitSize.height) / 2
    )
    return CGRect(origin: origin, size: fitSize)
}

/// Combines a selected overlay's base transform (from `item.transform(at:
/// currentTime)`, frozen while playback is paused for editing) with a
/// drag gesture's live position delta *and* the Scale/Rotation sliders'
/// current absolute values into the transform to render *and*, on
/// gesture/slider-release, to commit via `upsertKeyframe`. Pure geometry,
/// no SwiftUI/UIKit dependency, verified standalone the same way as
/// `videoDisplayRect`.
///
/// Position is the one piece still edited by continuous touch, so it
/// stays delta-based: `dragTranslation` is in points (a SwiftUI
/// `DragGesture`'s `.translation`), and dividing by `videoRectSize` puts
/// it into the same normalized 0...1 space `videoDisplayRect` establishes,
/// clamped to 0...1. `scale`/`rotation` are absolute target values
/// (already resolved from a slider, not a delta) - scale is clamped to
/// 0.2...5 as a sanity bound the spec doesn't set one for, guarding
/// against an absurdly tiny or huge overlay; rotation is left unclamped
/// since wrapping past 2π is harmless.
func composeOverlayTransform(
    to base: OverlayTransform,
    dragTranslation: CGSize,
    videoRectSize: CGSize,
    scale: Double,
    rotation: Double
) -> OverlayTransform {
    let dx = videoRectSize.width > 0 ? dragTranslation.width / videoRectSize.width : 0
    let dy = videoRectSize.height > 0 ? dragTranslation.height / videoRectSize.height : 0

    let position = CGPoint(
        x: min(max(base.position.x + dx, 0), 1),
        y: min(max(base.position.y + dy, 0), 1)
    )
    let clampedScale = min(max(scale, 0.2), 5)

    return OverlayTransform(position: position, scale: clampedScale, rotation: rotation, opacity: base.opacity)
}

/// Thin AVPlayerLayer host - no transport controls, so overlay gesture
/// handling (step 4) and a custom timeline (step 5) have a clean surface
/// to sit on top of.
struct PlayerContainerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerContainerUIView {
        let view = PlayerLayerContainerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerLayerContainerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerLayerContainerUIView: UIView {
    let playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        layer.addSublayer(playerLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

struct OverlayEditorView: View {
    let momentId: String
    let videoURL: URL
    let libraryAssets: [LibraryAsset]
    /// Called after a successful export, before this screen dismisses -
    /// wired by MomentDetailView to reload its own player so it picks up
    /// the newly-burned-in edited file, the same completion shape
    /// MomentTrimEditor's saveTrimResult already uses.
    var onExported: () -> Void = {}

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var isExporting = false
    @State private var exportErrorMessage: String? = nil

    @State private var player: AVPlayer
    @State private var overlays: [OverlayItem]
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var naturalSize: CGSize = .zero
    @State private var isPlaying = false
    @State private var timeObserverToken: Any?

    @State private var selectedOverlayID: UUID? = nil
    @State private var selectedKeyframe: SelectedKeyframe? = nil
    @GestureState private var dragTranslation: CGSize = .zero

    // Scale/rotation for the selected overlay, edited via sliders rather
    // than a gesture (see the type-level comment). Mirrors the selected
    // overlay's transform at the current playhead - resynced by
    // `syncSliders()` whenever the selection or playhead time changes, so
    // touching a slider never jumps from a stale value.
    @State private var scaleSliderValue: Double = 1
    @State private var rotationDegrees: Double = 0

    /// Minimum start/end span for an overlay - also the smallest visible
    /// duration `selectedOverlayPanel`'s Start/End sliders will allow.
    private let minimumSpan: Double = 0.15

    init(momentId: String, videoURL: URL, libraryAssets: [LibraryAsset], initialOverlays: [OverlayItem], onExported: @escaping () -> Void = {}) {
        self.momentId = momentId
        self.videoURL = videoURL
        self.libraryAssets = libraryAssets
        self.onExported = onExported
        _player = State(initialValue: AVPlayer(url: videoURL))
        _overlays = State(initialValue: initialOverlays)
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    PlayerContainerView(player: player)
                        .onTapGesture {
                            selectedOverlayID = nil
                            selectedKeyframe = nil
                        }

                    let videoRect = videoDisplayRect(containerSize: geometry.size, naturalSize: naturalSize)
                    ForEach(visibleOverlays(), id: \.item.id) { entry in
                        overlayView(for: entry.item, transform: entry.transform, in: videoRect, videoRectSize: videoRect.size)
                    }
                }
            }
            .background(Color.black)

            transportControls

            // Sits directly above the asset strip rather than floating
            // over the video - keeps every selected-overlay control clear
            // of the video area and out of the way of the drag gesture.
            selectedOverlayPanel

            AssetThumbnailStrip(assets: libraryAssets) { asset in
                addOverlay(for: asset)
            }
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .onChange(of: selectedOverlayID) { _, _ in syncSliders() }
        .onChange(of: currentTime) { _, _ in syncSliders() }
        // A plain `.toolbar` renders nothing here - this view has no
        // NavigationView/NavigationStack to host a nav bar, since it's
        // presented as a bare .fullScreenCover (deliberately, to keep the
        // video full-bleed rather than losing height to a nav bar, the
        // same choice MomentCameraPicker's full-bleed recording screen
        // makes with its own manual close button). A visible overlay
        // button is the only way to actually dismiss this screen. Pulled
        // down and inward from the exact top-right corner - this whole
        // view ignores the safe area (see MomentDetailView's
        // .ignoresSafeArea() on the fullScreenCover), so a bare `.padding()`
        // landed the button right under the notch/Dynamic Island, where
        // it was effectively untappable.
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
        // Same top-inset reasoning as the close button - this whole
        // screen ignores the safe area, so a bare `.padding()` would land
        // under the notch/Dynamic Island.
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
            .disabled(isExporting || overlays.isEmpty)
        }
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Exporting…")
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
        .onAppear { setUpPlayer() }
        .onDisappear { tearDownPlayer() }
    }

    private struct VisibleOverlay {
        let item: OverlayItem
        let transform: OverlayTransform
    }

    private func visibleOverlays() -> [VisibleOverlay] {
        overlays.compactMap { item in
            guard item.isVisible(at: currentTime), let transform = item.transform(at: currentTime) else { return nil }
            return VisibleOverlay(item: item, transform: transform)
        }
    }

    @ViewBuilder
    private func overlayView(for item: OverlayItem, transform baseTransform: OverlayTransform, in videoRect: CGRect, videoRectSize: CGSize) -> some View {
        if videoRect != .zero, let asset = libraryAssets.first(where: { $0.id == item.assetID }), let image = asset.image {
            let isSelected = item.id == selectedOverlayID
            // While selected, the drag gesture's live position delta and
            // the Scale/Rotation sliders' current values ride on top of
            // the committed base transform for both rendering and (on
            // gesture end / slider release) the value that gets upserted
            // as a keyframe - one function, so what's on screen always
            // matches what's about to be saved.
            let liveTransform = isSelected
                ? composeOverlayTransform(to: baseTransform, dragTranslation: dragTranslation, videoRectSize: videoRectSize, scale: scaleSliderValue, rotation: rotationDegrees * .pi / 180)
                : baseTransform

            let baseSize = overlayBaseSizeFraction * min(videoRect.width, videoRect.height)

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: baseSize, height: baseSize)
                .opacity(liveTransform.opacity)
                .rotationEffect(.radians(liveTransform.rotation))
                .scaleEffect(liveTransform.scale)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.yellow, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                            .rotationEffect(.radians(liveTransform.rotation))
                            .scaleEffect(liveTransform.scale)
                    }
                }
                .position(
                    x: videoRect.minX + liveTransform.position.x * videoRect.width,
                    y: videoRect.minY + liveTransform.position.y * videoRect.height
                )
                .onTapGesture {
                    selectOverlay(item.id)
                }
                .gesture(dragGesture(for: item, isSelected: isSelected, baseTransform: baseTransform, videoRectSize: videoRectSize))
        }
    }

    // Every overlay view gets the drag recognizer attached (SwiftUI
    // doesn't support cleanly attaching-or-not an opaque `some Gesture`
    // via a ternary) - `isSelected` is captured per-view from the
    // ForEach's own `item`, so only the actually-selected overlay's
    // closures ever mutate the shared @GestureState or commit anything.
    // An unselected overlay's recognizer fires but no-ops.

    private func dragGesture(for item: OverlayItem, isSelected: Bool, baseTransform: OverlayTransform, videoRectSize: CGSize) -> some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                guard isSelected else { return }
                state = value.translation
            }
            .onEnded { value in
                guard isSelected else { return }
                commitTransform(for: item, baseTransform: baseTransform, videoRectSize: videoRectSize, dragTranslation: value.translation)
            }
    }

    /// Commit path for the drag gesture's `.onEnded` - folds in whatever
    /// the Scale/Rotation sliders currently show, so dragging right after
    /// adjusting a slider (without an intervening playhead move) doesn't
    /// discard that pending value.
    private func commitTransform(for item: OverlayItem, baseTransform: OverlayTransform, videoRectSize: CGSize, dragTranslation: CGSize) {
        let resolved = composeOverlayTransform(to: baseTransform, dragTranslation: dragTranslation, videoRectSize: videoRectSize, scale: scaleSliderValue, rotation: rotationDegrees * .pi / 180)
        guard let index = overlays.firstIndex(where: { $0.id == item.id }) else { return }
        overlays[index].upsertKeyframe(time: currentTime, transform: resolved, tolerance: 0.2)
        persistOverlays()
    }

    private func selectOverlay(_ id: UUID) {
        selectedOverlayID = id
        if isPlaying { togglePlayback() }
    }

    private func removeSelectedOverlay() {
        guard let selectedOverlayID else { return }
        overlays.removeAll { $0.id == selectedOverlayID }
        self.selectedOverlayID = nil
        self.selectedKeyframe = nil
        persistOverlays()
    }

    /// Resyncs the Scale/Rotation sliders to the selected overlay's
    /// transform at the current playhead, so touching a slider never
    /// jumps from a stale value left over from a different overlay or a
    /// different point in time.
    private func syncSliders() {
        guard let selectedOverlayID,
              let item = overlays.first(where: { $0.id == selectedOverlayID }),
              let base = item.transform(at: currentTime) else {
            scaleSliderValue = 1
            rotationDegrees = 0
            return
        }
        scaleSliderValue = base.scale
        rotationDegrees = base.rotation * 180 / .pi
    }

    /// Commit path for the Scale/Rotation sliders' `onEditingChanged`
    /// (fires once, on release) - position is left untouched (`.zero`
    /// drag, `.zero` videoRectSize is safe since `composeOverlayTransform`
    /// guards divide-by-zero and a zero delta leaves position unchanged).
    private func commitScaleRotation() {
        guard let selectedOverlayID,
              let index = overlays.firstIndex(where: { $0.id == selectedOverlayID }),
              let base = overlays[index].transform(at: currentTime) else { return }
        let resolved = composeOverlayTransform(to: base, dragTranslation: .zero, videoRectSize: .zero, scale: scaleSliderValue, rotation: rotationDegrees * .pi / 180)
        overlays[index].upsertKeyframe(time: currentTime, transform: resolved, tolerance: 0.2)
        persistOverlays()
    }

    /// The selected overlay's controls: delete, Scale/Rotation (auto-
    /// keyframed at the current playhead, same as the drag gesture) and
    /// Start/End (direct fields on the overlay, no keyframe involved).
    /// All four replaced a small-target gesture (pinch/rotate on the
    /// canvas, drag handles on the timeline) that the user found hard to
    /// control by touch on a small portrait screen.
    @ViewBuilder
    private var selectedOverlayPanel: some View {
        if let index = overlays.firstIndex(where: { $0.id == selectedOverlayID }) {
            let item = overlays[index]
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Selected Overlay")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        removeSelectedOverlay()
                    } label: {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white, .red)
                    }
                }

                labeledSlider(
                    "Scale", value: $scaleSliderValue, range: 0.2...5,
                    format: { String(format: "%.1fx", $0) },
                    onEditingChanged: { editing in if !editing { commitScaleRotation() } }
                )
                labeledSlider(
                    "Rotate", value: $rotationDegrees, range: -180...180,
                    format: { String(format: "%.0f°", $0) },
                    onEditingChanged: { editing in if !editing { commitScaleRotation() } }
                )
                labeledSlider(
                    "Start", value: $overlays[index].startTime,
                    range: 0...max(item.endTime - minimumSpan, 0),
                    format: formattedTime,
                    onEditingChanged: { editing in if !editing { persistOverlays() } }
                )
                labeledSlider(
                    "End", value: $overlays[index].endTime,
                    range: min(item.startTime + minimumSpan, duration)...max(duration, minimumSpan),
                    format: formattedTime,
                    onEditingChanged: { editing in if !editing { persistOverlays() } }
                )
            }
            .padding(.horizontal)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func labeledSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, format: (Double) -> String, onEditingChanged: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 44, alignment: .leading)
            Slider(value: value, in: range, onEditingChanged: onEditingChanged)
            Text(format(value.wrappedValue))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func formattedTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var transportControls: some View {
        VStack(spacing: 4) {
            OverlayTimelineView(
                overlays: $overlays,
                duration: duration,
                currentTime: Binding(
                    get: { currentTime },
                    set: { newValue in
                        currentTime = newValue
                        player.seek(to: CMTime(seconds: newValue, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                ),
                selectedOverlayID: $selectedOverlayID,
                selectedKeyframe: $selectedKeyframe,
                onCommit: persistOverlays
            )

            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 32))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func setUpPlayer() {
        let asset = AVURLAsset(url: videoURL)
        Task {
            let loadedDuration = try? await asset.load(.duration)
            let tracks = try? await asset.loadTracks(withMediaType: .video)
            let track = tracks?.first
            let rawSize = try? await track?.load(.naturalSize)
            let transform = try? await track?.load(.preferredTransform)
            await MainActor.run {
                duration = loadedDuration?.seconds.isFinite == true ? loadedDuration!.seconds : 0
                // naturalSize is the raw encoded pixel size before rotation
                // metadata is applied - for a portrait-recorded video that
                // can be the landscape dimensions, with preferredTransform
                // carrying the rotation needed for correct display. Same
                // technique MomentCapture.swift's stitchMultiCam already
                // uses for exactly this reason.
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

    /// Tapping a library thumbnail adds one real overlay, centered, that
    /// "starts at the current playhead time" (the spec's own sanctioned
    /// fallback to dragging a thumbnail onto the video). Selecting it
    /// immediately and pausing playback lets the user drag it into place
    /// right away.
    private func addOverlay(for asset: LibraryAsset) {
        let clipDuration = duration > 0 ? duration : 5
        let startTime = min(currentTime, clipDuration)
        let keyframe = OverlayKeyframe(time: startTime, position: CGPoint(x: 0.5, y: 0.5), scale: 1, rotation: 0, opacity: 1)
        let item = OverlayItem(assetID: asset.id, startTime: startTime, endTime: clipDuration, keyframes: [keyframe])
        overlays.append(item)
        selectOverlay(item.id)
        persistOverlays()
    }

    private func persistOverlays() {
        guard !momentId.isEmpty else { return }
        authManager.updateMomentOverlays(momentId: momentId, overlays: overlays) { error in
            if let error {
                debugLog("❌ updateMomentOverlays failed:", error.localizedDescription)
            }
        }
    }

    /// Burns the current `overlays` into whatever video is currently
    /// playing (`resolvedMomentVideoURL` - so this composites on top of
    /// any prior trim, matching how `MomentTrimEditor` already treats the
    /// edited slot as an evolving committed derivative, not a one-shot
    /// diff off the original). On success, copies the result into that
    /// same slot so every existing consumer (playback, share, save-to-
    /// Camera-Roll) picks it up automatically, then calls `onExported`
    /// and dismisses.
    private func startExport() {
        guard !momentId.isEmpty, let sourceURL = resolvedMomentVideoURL(for: momentId) else { return }
        if isPlaying { togglePlayback() }
        exportErrorMessage = nil
        isExporting = true

        exportMomentWithOverlays(
            sourceURL: sourceURL,
            overlays: overlays,
            resolveImage: { assetID in libraryAssets.first(where: { $0.id == assetID })?.image }
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
                    // The audio-mix base (if any) now misses these
                    // overlay pixels - see Moment.swift's
                    // localMomentAudioBaseVideoURL doc comment.
                    invalidateMomentAudioBase(momentId: momentId)
                    onExported()
                    dismiss()
                } catch {
                    exportErrorMessage = "Couldn't save the exported video: \(error.localizedDescription)"
                }
            case .failure(let error):
                debugLog("❌ exportMomentWithOverlays failed:", error.localizedDescription)
                exportErrorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}
