//
//  MomentFreezeEditorView.swift
//  PitchMark
//
//  The editing screen for MomentFreeze.swift's freeze-frame/replay
//  callout - scrub to a point, set a hold duration, optionally zoom in
//  and/or show a text callout, then Apply bakes it in via
//  MomentFreezeExporter.swift. Single freeze point per Moment for V1 -
//  confirmed scope with the user.
//
//  Unlike Zoom/Overlay/Audio/Slideshow, this reads `videoURL`
//  (resolvedMomentVideoURL) directly, never a frozen base - Freeze is a
//  direct-chain editor, a sibling of Trim/Speed, not a frozen-base ring
//  member (see MomentFreezeExporter.swift's header comment for why).
//
//  Reuses `PlayerContainerView` (OverlayEditorView.swift) for the video
//  surface, and the same TextField/ColorPicker/template-button shape
//  OverlayEditorView already uses for editing an `OverlayTextContent`,
//  since the callout is that exact same model.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI
import AVFoundation

struct MomentFreezeEditorView: View {
    let momentId: String
    let videoURL: URL
    var onExported: () -> Void = {}

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer
    @State private var duration: Double = 0
    /// The source track's own nominal frame rate - loaded in
    /// `setUpPlayer()`, defaulting to 30 until that resolves (and if the
    /// track never reports one) so `stepFrame` always has a sane value
    /// to step by rather than needing an Optional threaded through every
    /// caller.
    @State private var frameRate: Double = 30
    /// Preferred-transform-aware natural size, loaded in `setUpPlayer()`
    /// the same way every other editor in this feature does - needed to
    /// map the callout's normalized position into the actual on-screen
    /// video rect via `videoDisplayRect` (OverlayEditorView.swift).
    @State private var naturalSize: CGSize = .zero

    @State private var timestamp: Double
    @State private var holdDuration: Double
    @State private var zoomEnabled: Bool
    @State private var zoomScale: Double
    /// Normalized 0...1 - where the zoom centers by the hold's end,
    /// adjustable via a draggable marker in `videoArea`. Previously
    /// hardcoded to dead-center in the exporter with no way to change it
    /// at all - the user asked directly "is the end zoom point
    /// adjustable?" and it wasn't.
    @State private var zoomCenterX: Double
    @State private var zoomCenterY: Double
    @State private var calloutEnabled: Bool
    @State private var calloutLine1: String
    @State private var calloutLine2: String
    @State private var calloutColor: Color
    @State private var calloutTemplateID: String
    private let hadExistingFreeze: Bool

    @State private var isExporting = false
    @State private var exportErrorMessage: String? = nil

    init(momentId: String, videoURL: URL, initialFreezeFrame: FreezeFrame?, onExported: @escaping () -> Void = {}) {
        self.momentId = momentId
        self.videoURL = videoURL
        self.onExported = onExported
        _player = State(initialValue: AVPlayer(url: videoURL))
        _timestamp = State(initialValue: initialFreezeFrame?.timestamp ?? 0)
        _holdDuration = State(initialValue: initialFreezeFrame?.holdDuration ?? 2.0)
        _zoomEnabled = State(initialValue: initialFreezeFrame?.zoomEnabled ?? false)
        _zoomScale = State(initialValue: initialFreezeFrame?.zoomScale ?? 1.4)
        _zoomCenterX = State(initialValue: Double(initialFreezeFrame?.zoomCenter.x ?? 0.5))
        _zoomCenterY = State(initialValue: Double(initialFreezeFrame?.zoomCenter.y ?? 0.5))
        let callout = initialFreezeFrame?.callout
        _calloutEnabled = State(initialValue: callout != nil)
        _calloutLine1 = State(initialValue: callout?.line1 ?? "TITLE")
        _calloutLine2 = State(initialValue: callout?.line2 ?? "Subtitle")
        _calloutColor = State(initialValue: hexToColor(callout?.colorHex ?? "#FFFFFF") ?? .white)
        _calloutTemplateID = State(initialValue: callout?.templateID ?? overlayTextTemplates[0].id)
        hadExistingFreeze = initialFreezeFrame != nil
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                videoArea
                    .background(Color.black)
                    .frame(maxHeight: .infinity)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Freeze point: \(formattedTime(timestamp)) / \(formattedTime(duration))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            // Bound directly to `timestamp` - no separate
                            // "scrub here, then commit" step. The video
                            // this freezes IS wherever this slider (and
                            // the frame-step buttons below) currently
                            // sit; there used to be a "Set Freeze Point
                            // Here" button decoupling the two, which made
                            // it easy to scrub somewhere, forget to tap
                            // it, and export a freeze at time zero
                            // (whatever `timestamp` defaulted to) instead
                            // - exactly the bug the user hit.
                            Slider(value: Binding(
                                get: { timestamp },
                                set: { seek(to: $0) }
                            ), in: 0...max(duration, 0.01))

                            // The slider alone is too coarse to land on a
                            // specific frame once the clip runs more than
                            // a few seconds - one point of drag can skip
                            // many frames. These step by exactly one
                            // frame (from the track's own nominal frame
                            // rate, not a hardcoded 1/30s) for the fine
                            // adjustment the slider can't give.
                            HStack(spacing: 16) {
                                Button {
                                    stepFrame(by: -1)
                                } label: {
                                    Image(systemName: "backward.frame.fill")
                                }
                                Text("Frame \(currentFrameIndex) • \(String(format: "%.2fs", timestamp))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Button {
                                    stepFrame(by: 1)
                                } label: {
                                    Image(systemName: "forward.frame.fill")
                                }
                            }
                            .buttonStyle(.bordered)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Hold \(String(format: "%.1f", holdDuration))s")
                                .font(.subheadline.weight(.semibold))
                            Slider(value: $holdDuration, in: 0.5...5)
                        }

                        Toggle("Zoom In During Hold", isOn: $zoomEnabled)
                        if zoomEnabled {
                            Slider(value: $zoomScale, in: minZoomScale...maxZoomScale)
                            Text("Drag the yellow marker on the video above to set where it zooms in.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Toggle("Add Callout", isOn: $calloutEnabled)
                        if calloutEnabled {
                            calloutFields
                        }

                        if let exportErrorMessage {
                            Text(exportErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        if hadExistingFreeze {
                            Button("Remove Freeze Frame", role: .destructive) {
                                removeFreeze()
                            }
                            .disabled(isExporting)
                        }

                        Button {
                            startExport()
                        } label: {
                            HStack {
                                Spacer()
                                Text(isExporting ? "Applying…" : "Apply Freeze Frame")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                        .disabled(isExporting)
                    }
                    .padding()
                }
            }
            .navigationTitle("Freeze Frame")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isExporting)
                }
            }
        }
        .onAppear { setUpPlayer() }
        .onDisappear { tearDownPlayer() }
    }

    /// The callout preview lives here, not baked into the export's own
    /// pipeline - plain SwiftUI drawn on top of the player, same "live
    /// preview draws off a shared model, only export burns pixels"
    /// discipline every other editor in this feature uses. Previously
    /// missing entirely for this editor (reported by the user: the
    /// callout only ever appeared after saving, never while adjusting
    /// it), since this editor never positioned anything over the player
    /// at all until now.
    private var videoArea: some View {
        GeometryReader { geometry in
            let videoRect = videoDisplayRect(containerSize: geometry.size, naturalSize: naturalSize)
            ZStack {
                PlayerContainerView(player: player)
                if calloutEnabled, naturalSize.width > 0 {
                    overlayTextCardPreview(
                        OverlayTextContent(templateID: calloutTemplateID, line1: calloutLine1, line2: calloutLine2, colorHex: colorToHex(calloutColor) ?? "#FFFFFF"),
                        minDimension: min(videoRect.width, videoRect.height),
                        widthFraction: freezeCalloutWidthFraction,
                        heightFraction: freezeCalloutHeightFraction
                    )
                    .position(
                        x: videoRect.midX,
                        y: videoRect.minY + videoRect.height * freezeCalloutVerticalCenterFraction
                    )
                    .allowsHitTesting(false)
                }
                // Marks where the zoom centers by the hold's end -
                // draggable directly on the frame, the same
                // direct-manipulation convention MomentCropEditorView's
                // crop window and MomentZoomEditorView's own drag-to-pan
                // already use. Not a live zoomed preview (that would
                // need to show a magnified crop instead of a reference
                // point, which conflicts with placing a marker against
                // the UNZOOMED frame) - just where this will zoom into.
                if zoomEnabled, naturalSize.width > 0 {
                    Circle()
                        .strokeBorder(Color.yellow, lineWidth: 2)
                        .background(Circle().fill(Color.yellow.opacity(0.25)))
                        .frame(width: 28, height: 28)
                        .position(
                            x: videoRect.minX + zoomCenterX * videoRect.width,
                            y: videoRect.minY + zoomCenterY * videoRect.height
                        )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard zoomEnabled, videoRect.width > 0, videoRect.height > 0 else { return }
                        let raw = CGPoint(
                            x: (value.location.x - videoRect.minX) / videoRect.width,
                            y: (value.location.y - videoRect.minY) / videoRect.height
                        )
                        let clamped = clampedOffset(raw)
                        zoomCenterX = clamped.x
                        zoomCenterY = clamped.y
                    }
            )
        }
    }

    private var calloutFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Bold line", text: $calloutLine1)
                .textFieldStyle(.roundedBorder)
            TextField("Second line", text: $calloutLine2)
                .textFieldStyle(.roundedBorder)
            ColorPicker("Color", selection: $calloutColor)
            HStack {
                ForEach(overlayTextTemplates) { template in
                    Button(template.displayName) {
                        calloutTemplateID = template.id
                    }
                    .font(.caption.weight(calloutTemplateID == template.id ? .bold : .regular))
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var frameDuration: Double {
        frameRate > 0 ? 1.0 / frameRate : 1.0 / 30.0
    }

    private var currentFrameIndex: Int {
        Int((timestamp / frameDuration).rounded())
    }

    /// Zero tolerance on both sides - the plain `seek(to:)` this replaced
    /// lets AVPlayer snap to the nearest keyframe instead of the exact
    /// requested time (a performance optimization, documented AVFoundation
    /// behavior), which is exactly what made fine frame selection
    /// impossible: a drag or frame-step could land on the right time and
    /// still show the wrong frame. Precise seeking costs more decode work
    /// per seek, which is fine here - this editor isn't scrubbing
    /// continuously at 60fps, just on discrete slider/button taps.
    private func seek(to time: Double) {
        let clamped = min(max(time, 0), duration)
        timestamp = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func stepFrame(by count: Int) {
        seek(to: timestamp + Double(count) * frameDuration)
    }

    /// No periodic time observer - unlike Zoom/Audio/Overlay, this
    /// player never plays (there's no play/pause control here, only
    /// explicit seeks the slider/frame-step buttons already drive), so
    /// there's no independent playback position that could ever drift
    /// from `timestamp`.
    private func setUpPlayer() {
        let asset = AVURLAsset(url: videoURL)
        Task {
            let loadedDuration = try? await asset.load(.duration)
            let tracks = try? await asset.loadTracks(withMediaType: .video)
            let track = tracks?.first
            let loadedFrameRate = try? await track?.load(.nominalFrameRate)
            let rawSize = try? await track?.load(.naturalSize)
            let transform = try? await track?.load(.preferredTransform)
            await MainActor.run {
                duration = loadedDuration?.seconds.isFinite == true ? loadedDuration!.seconds : 0
                if let loadedFrameRate, loadedFrameRate > 0 {
                    frameRate = Double(loadedFrameRate)
                }
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
                if timestamp > duration {
                    timestamp = 0
                }
                // Show the initial freeze point immediately rather than
                // leaving the player on whatever frame it happened to
                // load with - important when re-opening an existing
                // freeze frame, where `timestamp` starts somewhere other
                // than zero.
                seek(to: timestamp)
            }
        }
    }

    private func tearDownPlayer() {
        player.pause()
    }

    private func buildFreezeFrame() -> FreezeFrame {
        FreezeFrame(
            timestamp: timestamp,
            holdDuration: holdDuration,
            zoomEnabled: zoomEnabled,
            zoomScale: zoomScale,
            zoomCenterX: zoomCenterX,
            zoomCenterY: zoomCenterY,
            callout: calloutEnabled
                ? OverlayTextContent(templateID: calloutTemplateID, line1: calloutLine1, line2: calloutLine2, colorHex: colorToHex(calloutColor) ?? "#FFFFFF")
                : nil
        )
    }

    private func removeFreeze() {
        exportErrorMessage = nil
        isExporting = true
        authManager.updateMomentFreezeFrame(momentId: momentId, freezeFrame: nil) { error in
            isExporting = false
            if let error {
                exportErrorMessage = "Couldn't remove the freeze frame: \(error.localizedDescription)"
                return
            }
            onExported()
            dismiss()
        }
    }

    private func startExport() {
        exportErrorMessage = nil
        guard let destination = localMomentEditedVideoURL(for: momentId) else { return }
        let freezeFrame = buildFreezeFrame()
        isExporting = true
        exportFrozenMoment(sourceURL: videoURL, freezeFrame: freezeFrame) { result in
            switch result {
            case .failure(let error):
                isExporting = false
                exportErrorMessage = "Couldn't apply the freeze frame: \(error.localizedDescription)"
            case .success(let tempURL):
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: tempURL, to: destination)
                    try? FileManager.default.removeItem(at: tempURL)
                    authManager.refreshMomentDuration(momentId: momentId, videoURL: destination)
                    // Every frozen-base ring member now misses this
                    // freeze - see Moment.swift's
                    // invalidateOtherFrozenBases doc comment.
                    invalidateOtherFrozenBases(momentId: momentId, except: [])
                    // See MomentAudioEditorView.swift's identical comment.
                    refreshFadeIfNeeded(momentId: momentId, authManager: authManager) { onExported() }
                    remapAllTimeBasedFields(momentId: momentId, authManager: authManager) {
                        freezeTimeToCompositeTime($0, freezeTimestamp: freezeFrame.timestamp, holdDuration: freezeFrame.holdDuration)
                    }
                    authManager.updateMomentFreezeFrame(momentId: momentId, freezeFrame: freezeFrame) { _ in }
                    isExporting = false
                    onExported()
                    dismiss()
                } catch {
                    isExporting = false
                    exportErrorMessage = "Couldn't save the exported video: \(error.localizedDescription)"
                }
            }
        }
    }
}
