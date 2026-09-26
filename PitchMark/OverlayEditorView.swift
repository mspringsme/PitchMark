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
//  spec's own sanctioned fallback to dragging from the strip), drag/
//  pinch/rotate on the selected overlay with auto-keyframe on gesture end
//  (upsertKeyframe, no explicit "add keyframe" control), and persistence
//  via Moment.overlays now that real edits exist worth saving.
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
/// drag/pinch/rotate gesture's live deltas into the transform to render
/// *and*, on gesture end, to commit via `upsertKeyframe`. Pure geometry,
/// no SwiftUI/UIKit dependency, verified standalone the same way as
/// `videoDisplayRect`.
///
/// `dragTranslation` is in points (a SwiftUI `DragGesture`'s
/// `.translation`); dividing by `videoRectSize` puts it into the same
/// normalized 0...1 space `videoDisplayRect` establishes for position.
/// Position is clamped to 0...1; scale is clamped to 0.2...5 as a sanity
/// bound the spec doesn't set one for, guarding against a pinch shrinking
/// an overlay to invisible or blowing it up absurdly; rotation is left
/// unclamped since wrapping past 2π is harmless.
func applyGestureDelta(
    to base: OverlayTransform,
    dragTranslation: CGSize,
    videoRectSize: CGSize,
    magnification: CGFloat,
    rotation: Double
) -> OverlayTransform {
    let dx = videoRectSize.width > 0 ? dragTranslation.width / videoRectSize.width : 0
    let dy = videoRectSize.height > 0 ? dragTranslation.height / videoRectSize.height : 0

    let position = CGPoint(
        x: min(max(base.position.x + dx, 0), 1),
        y: min(max(base.position.y + dy, 0), 1)
    )
    let scale = min(max(base.scale * magnification, 0.2), 5)
    let newRotation = base.rotation + rotation

    return OverlayTransform(position: position, scale: scale, rotation: newRotation, opacity: base.opacity)
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

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer
    @State private var overlays: [OverlayItem]
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var naturalSize: CGSize = .zero
    @State private var isPlaying = false
    @State private var timeObserverToken: Any?

    @State private var selectedOverlayID: UUID? = nil
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1
    @GestureState private var rotation: Angle = .zero

    init(momentId: String, videoURL: URL, libraryAssets: [LibraryAsset], initialOverlays: [OverlayItem]) {
        self.momentId = momentId
        self.videoURL = videoURL
        self.libraryAssets = libraryAssets
        _player = State(initialValue: AVPlayer(url: videoURL))
        _overlays = State(initialValue: initialOverlays)
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    PlayerContainerView(player: player)
                        .onTapGesture { selectedOverlayID = nil }

                    let videoRect = videoDisplayRect(containerSize: geometry.size, naturalSize: naturalSize)
                    ForEach(visibleOverlays(), id: \.item.id) { entry in
                        overlayView(for: entry.item, transform: entry.transform, in: videoRect, videoRectSize: videoRect.size)
                    }
                }
            }
            .background(Color.black)

            transportControls

            AssetThumbnailStrip(assets: libraryAssets) { asset in
                addOverlay(for: asset)
            }
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        // A plain `.toolbar` renders nothing here - this view has no
        // NavigationView/NavigationStack to host a nav bar, since it's
        // presented as a bare .fullScreenCover (deliberately, to keep the
        // video full-bleed rather than losing height to a nav bar, the
        // same choice MomentCameraPicker's full-bleed recording screen
        // makes with its own manual close button). A visible overlay
        // button is the only way to actually dismiss this screen.
        .overlay(alignment: .topLeading) {
            if selectedOverlayID != nil {
                Button {
                    removeSelectedOverlay()
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white, .red)
                }
                .padding()
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding()
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
            // While selected, live gesture deltas ride on top of the
            // committed base transform for both rendering and (on
            // gesture end) the value that gets upserted as a keyframe -
            // one function, so drag/pinch/rotate always render exactly
            // what upsertKeyframe is about to save.
            let liveTransform = isSelected
                ? applyGestureDelta(to: baseTransform, dragTranslation: dragTranslation, videoRectSize: videoRectSize, magnification: magnification, rotation: rotation.radians)
                : baseTransform

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
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
                .simultaneousGesture(magnificationGesture(for: item, isSelected: isSelected, baseTransform: baseTransform, videoRectSize: videoRectSize))
                .simultaneousGesture(rotationGesture(for: item, isSelected: isSelected, baseTransform: baseTransform, videoRectSize: videoRectSize))
        }
    }

    // Every overlay view gets all three gesture recognizers attached
    // (SwiftUI doesn't support cleanly attaching-or-not an opaque `some
    // Gesture` via a ternary) - `isSelected` is captured per-view from
    // the ForEach's own `item`, so only the actually-selected overlay's
    // closures ever mutate the shared @GestureState or commit anything.
    // An unselected overlay's recognizers fire but no-op.

    private func dragGesture(for item: OverlayItem, isSelected: Bool, baseTransform: OverlayTransform, videoRectSize: CGSize) -> some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                guard isSelected else { return }
                state = value.translation
            }
            .onEnded { value in
                guard isSelected else { return }
                commitGesture(for: item, baseTransform: baseTransform, videoRectSize: videoRectSize, dragTranslation: value.translation, magnification: magnification, rotation: rotation.radians)
            }
    }

    private func magnificationGesture(for item: OverlayItem, isSelected: Bool, baseTransform: OverlayTransform, videoRectSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .updating($magnification) { value, state, _ in
                guard isSelected else { return }
                state = value
            }
            .onEnded { value in
                guard isSelected else { return }
                commitGesture(for: item, baseTransform: baseTransform, videoRectSize: videoRectSize, dragTranslation: dragTranslation, magnification: value, rotation: rotation.radians)
            }
    }

    private func rotationGesture(for item: OverlayItem, isSelected: Bool, baseTransform: OverlayTransform, videoRectSize: CGSize) -> some Gesture {
        RotationGesture()
            .updating($rotation) { value, state, _ in
                guard isSelected else { return }
                state = value
            }
            .onEnded { value in
                guard isSelected else { return }
                commitGesture(for: item, baseTransform: baseTransform, videoRectSize: videoRectSize, dragTranslation: dragTranslation, magnification: magnification, rotation: value.radians)
            }
    }

    /// Shared commit path for all three gestures' `.onEnded` - each reads
    /// the other two gestures' still-current @GestureState values, so a
    /// two-finger pinch-and-rotate-while-dragging commits one coherent
    /// transform regardless of which recognizer's `.onEnded` happens to
    /// fire first. `upsertKeyframe`'s own tolerance absorbs the case
    /// where two of these end a few milliseconds apart.
    private func commitGesture(for item: OverlayItem, baseTransform: OverlayTransform, videoRectSize: CGSize, dragTranslation: CGSize, magnification: CGFloat, rotation: Double) {
        let resolved = applyGestureDelta(to: baseTransform, dragTranslation: dragTranslation, videoRectSize: videoRectSize, magnification: magnification, rotation: rotation)
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
        persistOverlays()
    }

    private var transportControls: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(
                get: { currentTime },
                set: { newValue in
                    currentTime = newValue
                    player.seek(to: CMTime(seconds: newValue, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }
            ), in: 0...max(duration, 0.01))

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
            let size = try? await tracks?.first?.load(.naturalSize)
            await MainActor.run {
                duration = loadedDuration?.seconds.isFinite == true ? loadedDuration!.seconds : 0
                naturalSize = size ?? .zero
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
}
