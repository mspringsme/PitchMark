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
//  2026-09-29: `startExport()` now bakes onto a frozen snapshot
//  (`ensureOverlayBase()`/`localMomentOverlayBaseVideoURL`) instead of a
//  fresh `resolvedMomentVideoURL` lookup - fixes the same ghost-content
//  bug class `MomentAudioEditorView` had: once this editor had exported
//  even once, `resolvedMomentVideoURL` *was* that prior export's own
//  output, so moving or deleting an overlay left its old position
//  permanently burned into that prior bake while a fresh copy
//  composited on top. Never affected the live preview - overlays are
//  drawn as plain SwiftUI views on top of whatever's already playing,
//  never re-derived from a possibly-baked file - only export did.
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

/// Which group of per-overlay controls `selectedOverlayPanel` shows -
/// see `OverlayEditorView.selectedControlCategory`'s doc comment.
private enum OverlayControlCategory: String, CaseIterable, Identifiable {
    case transform = "Position"
    case timing = "Timing"
    case glow = "Glow"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .transform: return "arrow.up.and.down.and.arrow.left.and.right"
        case .timing: return "clock"
        case .glow: return "sparkles"
        }
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

    /// 2026-09-30 - which category of per-overlay controls
    /// `selectedOverlayPanel` currently shows. Before this, Position/
    /// Timing/Glow all stacked at once below the video, and the video
    /// shrank to whatever was left as that stack grew (Glow's controls
    /// especially) - reported by the user as making an overlay hard to
    /// edit precisely. Showing one category at a time in a fixed-height
    /// budget (`controlPanelHeight`) keeps the control area's height
    /// constant regardless of category or content, so the video's own
    /// share of the screen no longer shrinks as more controls exist.
    @State private var selectedControlCategory: OverlayControlCategory = .transform

    /// Minimum start/end span for an overlay - also the smallest visible
    /// duration `selectedOverlayPanel`'s Start/End sliders will allow.
    private let minimumSpan: Double = 0.15

    /// Fixed regardless of which category is showing, and regardless of
    /// how tall that category's own content is (Glow's, especially, with
    /// pulse enabled) - content that doesn't fit scrolls within this
    /// budget instead of growing the panel and shrinking the video.
    private let controlPanelHeight: CGFloat = 170

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
            .frame(maxHeight: .infinity)
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
        .onChange(of: selectedOverlayID) { _, _ in
            syncSliders()
            selectedControlCategory = .transform
        }
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
            let centerX = videoRect.minX + liveTransform.position.x * videoRect.width
            let centerY = videoRect.minY + liveTransform.position.y * videoRect.height

            ZStack {
                // Glow, rendered behind the overlay itself - see
                // GlowEffect.swift for why this needs no whole-frame
                // Core Image pipeline: it only ever depends on the
                // overlay's own image, never the video underneath, so it
                // composites via the same screen-blend feature SwiftUI
                // already exposes rather than a rewritten preview path.
                // `currentTime` here is the synced AVPlayer's own
                // position, not wall-clock, so a pulsing glow already
                // reads "frame time" for free.
                if let glowParams = resolvedGlow(item.glow, at: currentTime),
                   let sourceCG = image.cgImage,
                   let glowCG = GlowEffect.render(sourceImage: sourceCG, params: glowParams, referenceSize: baseSize) {
                    let glowSizeRatio = CGFloat(glowCG.width) / CGFloat(max(sourceCG.width, 1))
                    Image(decorative: glowCG, scale: 1)
                        .resizable()
                        .frame(width: baseSize * glowSizeRatio, height: baseSize * glowSizeRatio)
                        .opacity(liveTransform.opacity)
                        .rotationEffect(.radians(liveTransform.rotation))
                        .scaleEffect(liveTransform.scale)
                        .blendMode(.screen)
                        .position(x: centerX, y: centerY)
                        .allowsHitTesting(false)
                }

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
                    .position(x: centerX, y: centerY)
                    .onTapGesture {
                        selectOverlay(item.id)
                    }
                    .gesture(dragGesture(for: item, isSelected: isSelected, baseTransform: baseTransform, videoRectSize: videoRectSize))
            }
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

    /// The selected overlay's controls, one category at a time (see
    /// `selectedControlCategory`'s doc comment for why): delete (always
    /// visible, not gated behind a category), then a segmented switcher
    /// over Position (Scale/Rotate - auto-keyframed at the current
    /// playhead, same as the drag gesture), Timing (Start/End, direct
    /// fields, no keyframe involved), and Glow. All of these replaced a
    /// small-target gesture (pinch/rotate on the canvas, drag handles on
    /// the timeline) the user found hard to control by touch on a small
    /// portrait screen.
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

                Picker("", selection: $selectedControlCategory) {
                    ForEach(OverlayControlCategory.allCases) { category in
                        Label(category.rawValue, systemImage: category.systemImage)
                            .tag(category)
                    }
                }
                .pickerStyle(.segmented)

                // Fixed height regardless of category or content - the
                // point of this redesign. A category shorter than the
                // budget just leaves empty space below it rather than
                // shrinking the video when a taller one (Glow) is picked.
                ScrollView {
                    switch selectedControlCategory {
                    case .transform:
                        transformControls
                    case .timing:
                        timingControls(index: index, item: item)
                    case .glow:
                        glowSection(index: index)
                    }
                }
                .frame(height: controlPanelHeight)
            }
            .padding(.horizontal)
            .padding(.top, 4)
        }
    }

    private var transformControls: some View {
        VStack(alignment: .leading, spacing: 6) {
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
        }
    }

    private func timingControls(index: Int, item: OverlayItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
    }

    /// Binds directly into `overlays[index].glow`, substituting a fresh
    /// `GlowSettings()` for a nil value on read - the same "materialize
    /// a default on first touch" shape `overlayVolumeKeyframesBinding`
    /// uses in MomentAudioEditorView for an analogous Optional-field
    /// binding. Setting doesn't persist by itself - matches how Start/
    /// End's direct `$overlays[index].foo` bindings work: the slider's
    /// own binding updates local state (and so the live preview) on
    /// every drag tick, while `labeledSlider`'s `onEditingChanged`
    /// defers the actual Firestore write to release.
    /// Unlike the native `$overlays[index].startTime`-style projections
    /// this panel's other sliders use, a hand-rolled `Binding(get:set:)`
    /// has no built-in bounds safety - `overlays[index]` traps if `index`
    /// goes stale. That happens exactly when it matters most: deleting
    /// the selected overlay (the trash button, `removeSelectedOverlay()`)
    /// shrinks `overlays` and clears `selectedOverlayID` in the same
    /// state update, and if any Glow control still holds this closure
    /// mid-teardown - SwiftUI can re-invoke a Binding's get/set while
    /// reconciling the view tree for a state change, not only cleanly
    /// after it - an unguarded index crashed with "Index out of range."
    /// Real bug, reported by the user, fixed here (2026-09-30).
    private func glowBinding(index: Int) -> Binding<GlowSettings> {
        Binding(
            get: { overlays.indices.contains(index) ? (overlays[index].glow ?? GlowSettings()) : GlowSettings() },
            set: { newValue in
                guard overlays.indices.contains(index) else { return }
                overlays[index].glow = newValue
            }
        )
    }

    @ViewBuilder
    private func glowSection(index: Int) -> some View {
        let glow = glowBinding(index: index)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Glow")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { glow.wrappedValue.isEnabled },
                    set: { glow.wrappedValue.isEnabled = $0; persistOverlays() }
                ))
                .labelsHidden()
            }

            if glow.wrappedValue.isEnabled {
                HStack {
                    Text("Color")
                        .font(.caption)
                        .frame(width: 44, alignment: .leading)
                    ColorPicker("", selection: Binding(
                        get: { glow.wrappedValue.color.color },
                        set: { glow.wrappedValue.color = GlowColor(color: $0); persistOverlays() }
                    ))
                    .labelsHidden()
                    Spacer()
                }

                labeledSlider(
                    "Intensity", value: glow.intensity, range: 0...1,
                    format: { String(format: "%.0f%%", $0 * 100) },
                    onEditingChanged: { editing in if !editing { persistOverlays() } }
                )
                labeledSlider(
                    "Radius", value: glow.radius, range: 0...40,
                    format: { String(format: "%.0fpt", $0) },
                    onEditingChanged: { editing in if !editing { persistOverlays() } }
                )

                HStack {
                    Text("Pulse")
                        .font(.caption)
                        .frame(width: 44, alignment: .leading)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { glow.wrappedValue.pulse.isEnabled },
                        set: { glow.wrappedValue.pulse.isEnabled = $0; persistOverlays() }
                    ))
                    .labelsHidden()
                }

                if glow.wrappedValue.pulse.isEnabled {
                    labeledSlider(
                        "Speed", value: glow.pulse.speed, range: 0.1...5,
                        format: { String(format: "%.1f/s", $0) },
                        onEditingChanged: { editing in if !editing { persistOverlays() } }
                    )
                    labeledSlider(
                        "Amount", value: glow.pulse.amount, range: 0...1,
                        format: { String(format: "%.0f%%", $0 * 100) },
                        onEditingChanged: { editing in if !editing { persistOverlays() } }
                    )
                }
            }
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

    /// Burns the current `overlays` into the frozen overlay-bake base
    /// (`ensureOverlayBase()` - see `localMomentOverlayBaseVideoURL`'s
    /// doc comment for why this is never a fresh `resolvedMomentVideoURL`
    /// lookup), which composites on top of any prior trim/speed edit
    /// exactly once, the first time this editor exports on this Moment,
    /// then stays fixed so every later export re-bakes the *current*
    /// overlay list from that same clean source instead of stacking on
    /// a previous bake. On success, copies the result into the edited
    /// slot so every existing consumer (playback, share, save-to-
    /// Camera-Roll) picks it up automatically, then calls `onExported`
    /// and dismisses.
    private func startExport() {
        guard !momentId.isEmpty else { return }
        let sourceURL = ensureOverlayBase()
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

    /// Snapshots `videoURL` into the frozen overlay-bake base the first
    /// time this editor exports on a Moment (the base file persists
    /// between sessions - see `localMomentOverlayBaseVideoURL`). Every
    /// later export reads from that snapshot, never from a fresh
    /// `resolvedMomentVideoURL` lookup again - see `startExport()`'s doc
    /// comment for why.
    private func ensureOverlayBase() -> URL {
        guard let baseURL = localMomentOverlayBaseVideoURL(for: momentId) else {
            return videoURL
        }
        if !FileManager.default.fileExists(atPath: baseURL.path) {
            try? FileManager.default.copyItem(at: videoURL, to: baseURL)
        }
        return FileManager.default.fileExists(atPath: baseURL.path) ? baseURL : videoURL
    }
}
