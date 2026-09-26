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
//  No persistence yet: `overlays` lives only in this screen's @State for
//  the preview session. There's nothing worth saving until step 4's real
//  gesture-driven edits exist - that step is what adds a Moment.overlays
//  field and its encode/decode path.
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
    let videoURL: URL
    let libraryAssets: [LibraryAsset]

    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer
    @State private var overlays: [OverlayItem] = []
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var naturalSize: CGSize = .zero
    @State private var isPlaying = false
    @State private var timeObserverToken: Any?

    init(videoURL: URL, libraryAssets: [LibraryAsset]) {
        self.videoURL = videoURL
        self.libraryAssets = libraryAssets
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    PlayerContainerView(player: player)

                    let videoRect = videoDisplayRect(containerSize: geometry.size, naturalSize: naturalSize)
                    ForEach(visibleOverlays(), id: \.item.id) { entry in
                        overlayView(for: entry.item, transform: entry.transform, in: videoRect)
                    }
                }
            }
            .background(Color.black)

            transportControls

            AssetThumbnailStrip(assets: libraryAssets) { asset in
                addDemoOverlay(for: asset)
            }
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
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
    private func overlayView(for item: OverlayItem, transform: OverlayTransform, in videoRect: CGRect) -> some View {
        if videoRect != .zero, let asset = libraryAssets.first(where: { $0.id == item.assetID }), let image = asset.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .opacity(transform.opacity)
                .rotationEffect(.radians(transform.rotation))
                .scaleEffect(transform.scale)
                .position(
                    x: videoRect.minX + transform.position.x * videoRect.width,
                    y: videoRect.minY + transform.position.y * videoRect.height
                )
        }
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

    /// Scaffolding for step 3's verification, standing in for step 4's
    /// real drag-onto-video placement: adds a small animated overlay for
    /// the tapped asset so there's something concrete to watch track
    /// position/scale/rotation/opacity in sync with playback and
    /// scrubbing. Not persisted.
    private func addDemoOverlay(for asset: LibraryAsset) {
        let clipDuration = duration > 0 ? duration : 5
        let start = OverlayKeyframe(time: 0, position: CGPoint(x: 0.5, y: 0.5), scale: 1, rotation: 0, opacity: 1)
        let end = OverlayKeyframe(time: clipDuration, position: CGPoint(x: 0.85, y: 0.2), scale: 1.6, rotation: .pi / 4, opacity: 0.6)
        let item = OverlayItem(assetID: asset.id, startTime: 0, endTime: clipDuration, keyframes: [start, end])
        overlays.append(item)
    }
}
