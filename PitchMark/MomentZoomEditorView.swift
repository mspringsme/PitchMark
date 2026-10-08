//
//  MomentZoomEditorView.swift
//  PitchMark
//
//  2026-09-30: the editing screen for MomentZoom.swift's zoom regions -
//  zoom in and out onto an area of a Moment's video, Ken Burns-style, for
//  export. UI shape deliberately mirrors MomentAudioEditorView's "mute a
//  section" regions, per the user's own direction: add a zoom *area* to
//  the timeline (a bar, like a mute section), select it, then adjust its
//  two ends - Start/End time via sliders exactly like a mute region's
//  own Start/End, and separately which *edge's* framing (Start or End)
//  the pan-drag-on-video and Zoom slider currently edit.
//
//  Live preview never bakes anything - it applies the exact same
//  `zoomTransform(at:)` this screen edits directly to the on-screen video
//  view via SwiftUI's `scaleEffect(anchor:)`, synced to the player's
//  periodic time observer. That's the same "preview draws live off the
//  shared interpolation function, only export burns pixels" discipline
//  OverlayEditorView already established.
//
//  Zoom amount is a slider, not a pinch gesture - OverlayEditorView
//  already tried pinch/rotate for its own transform controls and the
//  user found it hard to control by touch; this follows that same
//  lesson from the start rather than relearning it. Position stays a
//  direct drag on the video itself (a large touch target, same as
//  Overlay's drag-to-reposition).
//
//  Reuses `zoomBaseVideoURL`/`invalidateMomentZoomBase` (Moment.swift) -
//  same frozen-base technique the overlay/audio editors already use (see
//  `localMomentOverlayBaseVideoURL`'s doc comment), so re-opening this
//  screen after a prior zoom export edits against the pre-zoom pixels,
//  never a stacked re-zoom of its own last bake.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI
import AVFoundation

/// Which of a selected zoom region's two ends the pan-drag gesture and
/// Zoom slider currently edit. Mirrors how `MomentAudioEditorView`'s
/// Start/End sliders each edit one field of the selected mute region,
/// except here both "fields" (center + scale) are edited together per
/// edge via direct canvas manipulation rather than their own sliders.
private enum ZoomRegionEdge {
    case start
    case end
}

struct MomentZoomEditorView: View {
    let momentId: String
    let videoURL: URL
    /// The frozen zoom-bake base (`zoomBaseVideoURL` in Moment.swift) -
    /// both the live preview player and `startExport()` use this, never
    /// `videoURL` directly once a prior zoom export exists for this
    /// Moment. See `localMomentOverlayBaseVideoURL`'s doc comment in
    /// Moment.swift for why - same bug class, mirrored for zoom.
    private let previewBaseURL: URL
    var onExported: () -> Void = {}

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer
    @State private var regions: [ZoomRegion]

    @State private var duration: Double = 0
    @State private var currentTime: Double = 0
    @State private var naturalSize: CGSize = .zero
    @State private var isPlaying = false
    @State private var timeObserverToken: Any?

    @State private var selectedRegionID: UUID? = nil
    @State private var editingEdge: ZoomRegionEdge = .start
    @GestureState private var dragTranslation: CGSize = .zero

    /// The live zoom amount for whichever edge is being edited -
    /// resynced by `syncScaleSlider` whenever the selection, edge, or a
    /// region's own values change, same "touching a control never jumps
    /// from a stale value" discipline as OverlayEditorView's own scale
    /// slider.
    @State private var scaleSliderValue: Double = minZoomScale

    @State private var isExporting = false
    @State private var exportErrorMessage: String? = nil

    /// Minimum span enforced on a zoom region's Start/End, same role
    /// `minimumMuteRegionSpan` plays for a mute section
    /// (MomentAudioEditorView).
    private let minimumRegionSpan: Double = 0.2

    init(momentId: String, videoURL: URL, initialRegions: [ZoomRegion], onExported: @escaping () -> Void = {}) {
        self.momentId = momentId
        self.videoURL = videoURL
        let baseURL = zoomBaseVideoURL(momentId: momentId, sourceVideoURL: videoURL)
        self.previewBaseURL = baseURL
        self.onExported = onExported
        _player = State(initialValue: AVPlayer(url: baseURL))
        _regions = State(initialValue: initialRegions)
    }

    private func currentTransform() -> ZoomTransform {
        zoomTransform(at: currentTime, regions: regions)
    }

    var body: some View {
        VStack(spacing: 0) {
            videoArea
                .background(Color.black)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(formattedTime(currentTime)) / \(formattedTime(duration))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                timelineTrack

                HStack {
                    Text("Zoom Areas")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        addZoomRegion()
                    } label: {
                        Label("Add Zoom Area", systemImage: "arrow.up.left.and.arrow.down.right.circle.fill")
                            .font(.caption)
                    }
                }

                regionDetailPanel

                if let exportErrorMessage {
                    Text(exportErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
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
            .disabled(isExporting || regions.isEmpty)
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
            if isExporting {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("Exporting…")
                            .foregroundStyle(.white)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .onChange(of: currentTime) { _, _ in syncScaleSlider() }
        .onChange(of: selectedRegionID) { _, _ in editingEdge = .start; syncScaleSlider() }
        .onChange(of: editingEdge) { _, newEdge in
            syncScaleSlider()
            // Keeps the playhead inside the region being edited, so
            // `isEditingSelectedEdge` stays true and the preview actually
            // shows the frame for the edge just selected - without this,
            // switching to "End Framing" left the playhead wherever it
            // was (often still at the region's own start), so dragging
            // would be silently disabled until the user also scrubbed
            // there manually.
            if let region = regions.first(where: { $0.id == selectedRegionID }) {
                seek(to: newEdge == .start ? region.startTime : region.endTime)
            }
        }
        .onAppear { setUpPlayer() }
        .onDisappear { tearDownPlayer() }
    }

    // MARK: Video + pan/zoom gesture

    /// Whether the pan-drag gesture and Zoom slider are live right now -
    /// a region is selected, playback is paused (same gate OverlayEditorView
    /// uses - selecting pauses playback; see `selectRegion`), AND the
    /// playhead is actually within that region's own `[startTime, endTime]`.
    ///
    /// That last check was missing originally: `selectedEdgeTransform()`
    /// reads the selected region's own stored field regardless of
    /// `currentTime`, by design (see its own doc comment - the point was
    /// to stop depending on `currentTime` for *which region* to read
    /// from). But without also gating on the playhead being inside that
    /// region at all, the live preview kept showing the selected region's
    /// zoom everywhere on the timeline the instant it was selected -
    /// scrubbed all the way to the very start or end of the whole clip
    /// still showed it. Reported by the user as the zoom "applying all
    /// the way to the beginning of the track or to the end" instead of
    /// staying confined to the region being edited.
    private func isWithinSelectedRegion() -> Bool {
        guard let selectedRegionID, let region = regions.first(where: { $0.id == selectedRegionID }) else { return false }
        return currentTime >= region.startTime && currentTime <= region.endTime
    }

    private var isEditingSelectedEdge: Bool {
        !isPlaying && isWithinSelectedRegion()
    }

    /// The selected region's own stored framing for whichever edge
    /// (`editingEdge`) is being edited - read directly off the region,
    /// never through `zoomTransform(at: currentTime, regions:)`. That
    /// global function picks whichever region's span contains
    /// `currentTime` (first match wins on overlap, per its own doc
    /// comment) - with two regions whose spans are close together or
    /// touching, `currentTime` can land in a spot where it resolves to a
    /// *different* region than the one actually selected, so the drag
    /// gesture's base silently came from the wrong region's framing.
    /// That showed up as the preview "snapping" and dragging feeling
    /// broken as soon as a second region existed. Reading the selected
    /// region's own field for the edge being edited sidesteps the
    /// ambiguity entirely, regardless of `currentTime`.
    private func selectedEdgeTransform() -> ZoomTransform? {
        guard let selectedRegionID, let region = regions.first(where: { $0.id == selectedRegionID }) else { return nil }
        switch editingEdge {
        case .start: return ZoomTransform(center: region.startCenter, scale: region.startScale)
        case .end: return ZoomTransform(center: region.endCenter, scale: region.endScale)
        }
    }

    @ViewBuilder
    private var videoArea: some View {
        GeometryReader { geometry in
            let videoRect = videoDisplayRect(containerSize: geometry.size, naturalSize: naturalSize)
            // Only reads the selected region's own stored edge value while
            // actually "editing" it (isEditingSelectedEdge: paused,
            // selected, playhead inside that region) - everywhere else
            // (playing, no selection, or scrubbed outside the region)
            // this MUST fall back to the real time-varying
            // `currentTransform()`. Reading `selectedEdgeTransform()`
            // unconditionally here (what this did before) meant the
            // preview froze at the selected edge's zoom for the entire
            // rest of playback the moment any region was selected,
            // instead of animating through the actual Ken Burns motion -
            // reported by the user as the whole video zooming, or not,
            // seemingly at random.
            let base = isEditingSelectedEdge ? (selectedEdgeTransform() ?? currentTransform()) : currentTransform()
            let liveCenter = isEditingSelectedEdge
                ? composeZoomCenter(base: base.center, dragTranslation: dragTranslation, videoRectSize: videoRect.size, scale: scaleSliderValue)
                : base.center
            let liveScale = isEditingSelectedEdge ? scaleSliderValue : base.scale

            if videoRect != .zero {
                ZStack {
                    PlayerContainerView(player: player)
                        .frame(width: videoRect.width, height: videoRect.height)
                        .scaleEffect(liveScale, anchor: UnitPoint(x: liveCenter.x, y: liveCenter.y))
                        .clipped()

                    // The drag gesture lives on this plain, transparent
                    // SwiftUI view stacked over the video, not on
                    // PlayerContainerView itself - same reasoning
                    // OverlayEditorView's own drag gestures are attached
                    // to its overlay sprite views rather than the video
                    // layer: a `UIViewRepresentable`-hosted AVPlayerLayer
                    // view (PlayerContainerView) doesn't reliably forward
                    // touches into a SwiftUI `.gesture()` attached
                    // directly to it, which silently made this region's
                    // pan-to-reposition undraggable.
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: videoRect.width, height: videoRect.height)
                        .gesture(
                            DragGesture()
                                .updating($dragTranslation) { value, state, _ in
                                    guard isEditingSelectedEdge else { return }
                                    state = value.translation
                                }
                                .onEnded { value in
                                    guard isEditingSelectedEdge else { return }
                                    commitDrag(translation: value.translation, videoRectSize: videoRect.size)
                                }
                        )
                }
                .position(x: videoRect.midX, y: videoRect.midY)
            }
        }
    }

    private func commitDrag(translation: CGSize, videoRectSize: CGSize) {
        guard let index = regions.firstIndex(where: { $0.id == selectedRegionID }) else { return }
        let base = selectedEdgeTransform() ?? currentTransform()
        let resolvedCenter = composeZoomCenter(base: base.center, dragTranslation: translation, videoRectSize: videoRectSize, scale: scaleSliderValue)
        applyEdge(center: resolvedCenter, scale: scaleSliderValue, to: &regions[index])
        persistRegions()
    }

    private func applyEdge(center: CGPoint, scale: Double, to region: inout ZoomRegion) {
        let clampedScale = min(max(scale, minZoomScale), maxZoomScale)
        let clampedCenter = CGPoint(x: min(max(center.x, 0), 1), y: min(max(center.y, 0), 1))
        switch editingEdge {
        case .start:
            region.startCenterX = clampedCenter.x
            region.startCenterY = clampedCenter.y
            region.startScale = clampedScale
        case .end:
            region.endCenterX = clampedCenter.x
            region.endCenterY = clampedCenter.y
            region.endScale = clampedScale
        }
    }

    // MARK: Region list / timeline

    /// A newly-added region starts at the current playhead, spans a
    /// short default 1.5s (clamped to the clip's own remaining length),
    /// at the default "no zoom at Start, 2x at End" framing - same
    /// "quick, fixed default, user adjusts after" shape
    /// `MomentAudioEditorView.addMuteRegion` already establishes.
    private func addZoomRegion() {
        let start = min(max(currentTime, 0), max(duration, 0.01))
        let end = min(start + 1.5, max(duration, 0.01))
        let region = ZoomRegion(startTime: start, endTime: max(end, start + 0.01))
        regions.append(region)
        regions.sort { $0.startTime < $1.startTime }
        selectRegion(region.id)
        persistRegions()
    }

    private func selectRegion(_ id: UUID) {
        selectedRegionID = id
        editingEdge = .start
        if isPlaying { togglePlayback() }
        if let region = regions.first(where: { $0.id == id }) {
            seek(to: region.startTime)
        }
    }

    private var timelineTrack: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(width: width, height: 28)
                    .position(x: width / 2, y: 20)

                ForEach(regions) { region in
                    regionBar(region, trackWidth: width)
                }

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: 36)
                    .position(x: timeToX(time: currentTime, duration: duration, trackWidth: width), y: 20)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isPlaying else { return }
                        currentTime = min(max(xToTime(x: value.location.x, duration: duration, trackWidth: width), 0), duration)
                        player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    }
            )
        }
        .frame(height: 40)
    }

    /// Bar spanning `region`'s own time range, same visual shape as
    /// `MomentAudioEditorView.MuteRegionStrip`'s own bar.
    private func regionBar(_ region: ZoomRegion, trackWidth: CGFloat) -> some View {
        let x = timeToX(time: region.startTime, duration: max(duration, 0.01), trackWidth: trackWidth)
        let endX = timeToX(time: region.endTime, duration: max(duration, 0.01), trackWidth: trackWidth)
        let blockWidth = max(endX - x, 4)
        let isSelected = region.id == selectedRegionID

        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(isSelected ? Color.yellow.opacity(0.7) : Color.yellow.opacity(0.35))
            .frame(width: blockWidth, height: 28)
            .position(x: x + blockWidth / 2, y: 20)
            .onTapGesture { selectRegion(region.id) }
    }

    // MARK: Selected region detail panel

    /// Start/End use the same fixed, non-interdependent range
    /// (`0...duration` for both) with the minimum-span constraint
    /// enforced only on commit - not each other's live value - for the
    /// exact reason MomentAudioEditorView's own mute-region Start/End
    /// sliders are shaped this way. See
    /// [[feedback-swiftui-slider-interdependent-range]].
    @ViewBuilder
    private var regionDetailPanel: some View {
        if let id = selectedRegionID, let index = regions.firstIndex(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Selected Zoom Area")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        regions.remove(at: index)
                        selectedRegionID = nil
                        persistRegions()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.caption2)
                    }
                }

                regionSlider(
                    "Start", value: Binding(
                        get: { regions.indices.contains(index) ? regions[index].startTime : 0 },
                        set: { if regions.indices.contains(index) { regions[index].startTime = $0 } }
                    ),
                    range: 0...max(duration, 0.01), format: formattedTime,
                    onEditingChanged: { editing in if !editing { commitRegionStart(index) } }
                )
                regionSlider(
                    "End", value: Binding(
                        get: { regions.indices.contains(index) ? regions[index].endTime : 0 },
                        set: { if regions.indices.contains(index) { regions[index].endTime = $0 } }
                    ),
                    range: 0...max(duration, 0.01), format: formattedTime,
                    onEditingChanged: { editing in if !editing { commitRegionEnd(index) } }
                )

                Picker("Editing", selection: $editingEdge) {
                    Text("Start Framing").tag(ZoomRegionEdge.start)
                    Text("End Framing").tag(ZoomRegionEdge.end)
                }
                .pickerStyle(.segmented)

                HStack {
                    Image(systemName: "minus.magnifyingglass")
                        .foregroundStyle(.secondary)
                    Slider(
                        value: $scaleSliderValue,
                        in: minZoomScale...maxZoomScale,
                        onEditingChanged: { editing in
                            if !editing { commitScale(index) }
                        }
                    )
                    Image(systemName: "plus.magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1fx", scaleSliderValue))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                .disabled(!isWithinSelectedRegion())

                if isWithinSelectedRegion() {
                    Text("Drag the video above to position the \(editingEdge == .start ? "start" : "end") framing.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Playhead is outside this zoom area - seek back into it to edit the \(editingEdge == .start ? "start" : "end") framing.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func regionSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, format: (Double) -> String, onEditingChanged: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .frame(width: 40, alignment: .leading)
            Slider(value: value, in: range, onEditingChanged: onEditingChanged)
            Text(format(value.wrappedValue))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    /// Commit path for Start's release - mirrors
    /// MomentAudioEditorView's commitMuteRegionStart: if Start was
    /// dragged past (or too close to) the current End, push End forward
    /// just enough to restore the minimum span.
    private func commitRegionStart(_ index: Int) {
        guard regions.indices.contains(index) else { return }
        if regions[index].startTime > regions[index].endTime - minimumRegionSpan {
            regions[index].endTime = min(regions[index].startTime + minimumRegionSpan, max(duration, 0.01))
        }
        seek(to: regions[index].startTime)
        persistRegions()
    }

    /// Commit path for End's release - mirrors commitRegionStart,
    /// nudging Start backward instead when End was dragged past (or too
    /// close to) it.
    private func commitRegionEnd(_ index: Int) {
        guard regions.indices.contains(index) else { return }
        if regions[index].endTime < regions[index].startTime + minimumRegionSpan {
            regions[index].startTime = max(regions[index].endTime - minimumRegionSpan, 0)
        }
        seek(to: regions[index].endTime)
        persistRegions()
    }

    private func commitScale(_ index: Int) {
        guard regions.indices.contains(index) else { return }
        let base = selectedEdgeTransform() ?? currentTransform()
        applyEdge(center: base.center, scale: scaleSliderValue, to: &regions[index])
        persistRegions()
    }

    /// Resyncs the zoom slider to whichever edge (`editingEdge`) of the
    /// selected region is currently being edited, or to the plain
    /// interpolated value at the playhead when nothing is selected -
    /// without this, dragging the slider right after the selection, edge,
    /// or playhead changed would start from whatever it happened to show
    /// last rather than the value actually in effect.
    private func syncScaleSlider() {
        guard let selectedRegionID, let region = regions.first(where: { $0.id == selectedRegionID }) else {
            scaleSliderValue = currentTransform().scale
            return
        }
        switch editingEdge {
        case .start: scaleSliderValue = region.startScale
        case .end: scaleSliderValue = region.endScale
        }
    }

    private func formattedTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Playback

    private func seek(to time: Double) {
        guard !isPlaying else { return }
        let clamped = min(max(time, 0), duration)
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
                // OverlayEditorView.swift's setUpPlayer for why
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

    // MARK: Persistence

    private func persistRegions() {
        guard !momentId.isEmpty else { return }
        authManager.updateMomentZoomRegions(momentId: momentId, regions: regions) { error in
            if let error {
                debugLog("❌ updateMomentZoomRegions failed:", error.localizedDescription)
            }
        }
    }

    // MARK: Export

    /// Burns the current `regions` into `previewBaseURL` (the frozen
    /// zoom-bake base), which composites on top of any prior trim/speed/
    /// overlay/audio edit exactly once, the first time this editor
    /// exports on this Moment, then stays fixed so every later export
    /// re-bakes the *current* region list from that same clean source
    /// instead of stacking on a previous bake. On success, copies the
    /// result into the edited slot so every existing consumer (playback,
    /// share, save-to-Camera-Roll) picks it up automatically.
    private func startExport() {
        guard !momentId.isEmpty else { return }
        let sourceURL = previewBaseURL
        if isPlaying { togglePlayback() }
        exportErrorMessage = nil
        isExporting = true

        exportZoomedMoment(sourceURL: sourceURL, regions: regions) { result in
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
                    // Every other frozen-base ring member now misses
                    // this zoom - see Moment.swift's
                    // invalidateOtherFrozenBases doc comment.
                    invalidateOtherFrozenBases(momentId: momentId, except: [.zoom])
                    // See MomentAudioEditorView.swift's identical comment.
                    refreshFadeIfNeeded(momentId: momentId, authManager: authManager) { onExported() }
                    onExported()
                    dismiss()
                } catch {
                    exportErrorMessage = "Couldn't save the exported video: \(error.localizedDescription)"
                }
            case .failure(let error):
                debugLog("❌ exportZoomedMoment failed:", debugErrorDetail(error))
                exportErrorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}
