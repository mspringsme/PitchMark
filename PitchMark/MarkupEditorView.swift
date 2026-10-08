//
//  MarkupEditorView.swift
//  PitchMark
//
//  2026-10-07: the Moment-specific shell around MarkupCanvasView.swift's
//  reusable engine - a new sibling editor (not an extension of
//  OverlayEditorView.swift) because OverlayItem/OverlayKeyframe are a
//  single position+scale+rotation anchor, which doesn't fit a line's two
//  INDEPENDENT endpoints or an angle's three. Follows the exact same
//  shell shape every other Moment editor uses (own frozen base, own
//  Export, wired into MomentDetailView via an identical section/sheet
//  pair), just simpler than OverlayEditorView's - Phase 1 markup is
//  static geometry (no position/scale/rotation keyframes), so there's no
//  Overlay-style timeline/animation UI here.
//
//  2026-10-06: a scrub slider + frame-step buttons WERE missing at
//  first - reported by the user as "stuck in the frame and can't drag
//  the video to a different time to markup there." A coach needs to
//  find the exact frame (release point, foot plant) before drawing on
//  it, not just frame zero. This does NOT change Phase 1's scope - a
//  markup's own `startTime`/`endTime` still spans the whole clip
//  regardless of where this scrubber sits; it only changes which frame
//  is shown as the backdrop while placing/adjusting markup. Mirrors
//  MomentFreezeEditorView.swift's own scrub pattern exactly (same
//  zero-tolerance `seek(to:)` for frame-accurate landing, same
//  slider-bound-directly-to-timestamp shape - that file's own comment
//  documents why a separate "scrub here, then commit" step is a bug
//  waiting to happen, not a simplification).
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI
import AVFoundation

private let markupColorOptions: [(name: String, hex: String)] = [
    ("White", "#FFFFFF"),
    ("Black", "#000000"),
    ("Red", "#FF3B30"),
    ("Yellow", "#FFCC00"),
    ("Blue", "#007AFF"),
    ("Green", "#34C759")
]

struct MarkupEditorView: View {
    let momentId: String
    let videoURL: URL
    var onExported: () -> Void = {}

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer
    @State private var markups: [MarkupOverlay]
    @State private var selectedMarkupID: UUID? = nil
    @State private var duration: Double = 0
    @State private var naturalSize: CGSize = .zero
    @State private var timestamp: Double = 0
    /// The source track's own nominal frame rate - loaded in
    /// `setUpPlayer()`, defaulting to 30 until that resolves, same as
    /// `MomentFreezeEditorView.swift`'s identical field.
    @State private var frameRate: Double = 30

    @State private var isExporting = false
    @State private var exportErrorMessage: String? = nil

    /// Toggled by the Draw tool button - while true, every touch on the
    /// canvas is captured as a new freehand stroke instead of
    /// selecting/moving an existing markup (`MarkupCanvasView`'s
    /// `isDrawingActive`). Stays on after one stroke completes so the
    /// user can draw several in a row without re-tapping Draw each time.
    @State private var isDrawingMode = false
    /// Non-nil while the text-entry sheet is open for an EXISTING text
    /// markup ("edit text again after placement"); nil means the sheet,
    /// if open, is creating a brand new one instead. Tracked separately
    /// from `showTextEntrySheet` because `MomentNamePromptSheet` only
    /// needs an initial string, not which markup (if any) it's for.
    @State private var textMarkupPendingEditID: UUID? = nil
    @State private var showTextEntrySheet = false

    /// The frozen markup-bake base (`markupBaseVideoURL`, Moment.swift) -
    /// same "never edit on top of your own prior export" discipline
    /// every sibling editor's frozen base uses. Resolved asynchronously
    /// in `.onAppear` rather than `init` - `markupBaseVideoURL` does a
    /// real `FileManager.copyItem` the first time it runs for a Moment,
    /// and doing that synchronously in `init` is exactly the main-thread
    /// freeze `MomentSlideshowEditorView.swift`'s `sourceVideoURL` had
    /// (same underlying operation - a plain file copy, not a transcode -
    /// "not a real transcode" does NOT mean "safe to do synchronously,"
    /// which the first draft of this comment wrongly assumed). `player`
    /// starts on the raw `videoURL` immediately so something plays with
    /// no delay, then gets swapped to the real frozen base once resolved.
    @State private var previewBaseURL: URL? = nil

    init(momentId: String, videoURL: URL, initialMarkups: [MarkupOverlay], onExported: @escaping () -> Void = {}) {
        self.momentId = momentId
        self.videoURL = videoURL
        self.onExported = onExported
        _player = State(initialValue: AVPlayer(url: videoURL))
        _markups = State(initialValue: initialMarkups)
    }

    private var selectedMarkup: MarkupOverlay? {
        markups.first { $0.id == selectedMarkupID }
    }

    var body: some View {
        GeometryReader { screenGeometry in
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    ZStack {
                        PlayerContainerView(player: player)
                            .onTapGesture { selectedMarkupID = nil }

                        let videoRect = videoDisplayRect(containerSize: geometry.size, naturalSize: naturalSize)
                        MarkupCanvasView(
                            markups: $markups,
                            selectedID: $selectedMarkupID,
                            videoRect: videoRect,
                            currentTime: timestamp,
                            isDrawingActive: isDrawingMode,
                            onStrokeCompleted: addFreehandStroke
                        )
                    }
                }
                .background(Color.black)

                bottomArea
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding(.top, 50)
            .padding(.leading, 20)
        }
        // Same full-screen dim-plus-white-spinner overlay every other
        // exporting state in this app uses
        // ([[feedback-loading-spinner-convention]]).
        .overlay {
            if isExporting || previewBaseURL == nil {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text(isExporting ? "Exporting…" : "Preparing…")
                            .foregroundStyle(.white)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .onAppear(perform: setUpPlayer)
        .sheet(isPresented: $showTextEntrySheet) {
            MomentNamePromptSheet(
                title: textMarkupPendingEditID == nil ? "Add Text" : "Edit Text",
                initialName: textMarkupPendingEditID.flatMap { id in markups.first(where: { $0.id == id })?.text } ?? ""
            ) { text in
                if let id = textMarkupPendingEditID {
                    updateMarkup(id: id) { $0.text = text }
                } else {
                    addTextMarkup(text: text)
                }
            }
        }
    }

    private var bottomArea: some View {
        VStack(spacing: 10) {
            scrubArea
            toolPicker

            if let exportErrorMessage {
                Text(exportErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if selectedMarkup != nil {
                stylePanel
            }

            Button {
                startExport()
            } label: {
                // Static text - the full-screen overlay communicates
                // "Preparing…"/"Exporting…", same convention every
                // sibling editor's exporting state uses.
                Text("Export")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExporting || previewBaseURL == nil)
        }
        .padding()
        .background(.bar)
    }

    /// Find the moment to markup first, then draw on it - same order
    /// MomentFreezeEditorView.swift's own scrub-then-place flow uses.
    /// The slider is bound directly to `timestamp` (no separate "scrub
    /// here, then commit" step - see that file's own comment on why
    /// that shape is a bug waiting to happen), and the frame-step
    /// buttons give the fine adjustment a slider alone can't once a
    /// clip runs more than a few seconds.
    private var scrubArea: some View {
        VStack(spacing: 4) {
            Text("\(formattedTime(timestamp)) / \(formattedTime(duration))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(get: { timestamp }, set: { seek(to: $0) }),
                in: 0...max(duration, 0.01)
            )
            HStack(spacing: 20) {
                Button { stepFrame(by: -1) } label: {
                    Image(systemName: "backward.frame.fill")
                }
                Button { stepFrame(by: 1) } label: {
                    Image(systemName: "forward.frame.fill")
                }
            }
            .font(.subheadline)
        }
        .disabled(isExporting || previewBaseURL == nil)
    }

    private var toolPicker: some View {
        HStack(spacing: 20) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    toolButton(type: .line, systemImage: "line.diagonal", label: "Line")
                    toolButton(type: .arrow, systemImage: "arrow.up.right", label: "Arrow")
                    toolButton(type: .ellipse, systemImage: "circle", label: "Circle")
                    toolButton(type: .angle, systemImage: "angle", label: "Angle")
                    drawToolButton
                    textToolButton
                }
            }

            if markups.contains(where: { $0.type == .freehand }) {
                Button {
                    undoLastStroke()
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.title2)
                }
                .disabled(isExporting)
            }
        }
    }

    private func toolButton(type: MarkupType, systemImage: String, label: String) -> some View {
        Button {
            isDrawingMode = false
            addMarkup(type: type)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(label)
                    .font(.caption2)
            }
        }
        .disabled(isExporting)
    }

    /// Unlike every other tool, Draw has no default shape to insert -
    /// the shape IS whatever gets drawn - so this toggles draw mode
    /// (`MarkupCanvasView`'s drawing-capture layer) rather than creating
    /// anything itself. Stays on across multiple strokes; tap again (or
    /// pick a different tool) to go back to selecting/editing existing
    /// markup.
    private var drawToolButton: some View {
        Button {
            isDrawingMode.toggle()
            selectedMarkupID = nil
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "pencil.tip")
                    .font(.title2)
                Text("Draw")
                    .font(.caption2)
            }
        }
        .foregroundStyle(isDrawingMode ? Color.accentColor : .primary)
        .disabled(isExporting)
    }

    private var textToolButton: some View {
        Button {
            isDrawingMode = false
            textMarkupPendingEditID = nil
            showTextEntrySheet = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "textformat")
                    .font(.title2)
                Text("Text")
                    .font(.caption2)
            }
        }
        .disabled(isExporting)
    }

    private var stylePanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(markupColorOptions, id: \.hex) { option in
                    Button {
                        setSelectedColor(option.hex)
                    } label: {
                        Circle()
                            .fill(hexToColor(option.hex) ?? .white)
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.primary.opacity(selectedMarkup?.colorHex == option.hex ? 0.8 : 0.15), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }

                // "Edit text again after placement" - placed right next
                // to the color circles (reported as "too small and out
                // of place" when it was a plain icon off by the trash
                // button) rather than separated by the Spacer, same
                // circular size as the color swatches it now sits among.
                if selectedMarkup?.type == .text {
                    Button {
                        textMarkupPendingEditID = selectedMarkupID
                        showTextEntrySheet = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Color.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(role: .destructive) {
                    deleteSelectedMarkup()
                } label: {
                    Image(systemName: "trash")
                }
            }

            if selectedMarkup?.type == .text {
                HStack(spacing: 10) {
                    ForEach(MarkupTextSize.allCases, id: \.self) { size in
                        Button(size.rawValue.capitalized) {
                            setSelectedTextSize(size)
                        }
                        .font(.caption.weight((selectedMarkup?.textSize ?? .medium) == size ? .bold : .regular))
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { selectedMarkup?.opacity ?? 1 },
                            set: { setSelectedOpacity($0) }
                        ),
                        in: 0.2...1
                    )
                    .frame(maxWidth: 110)
                }
            } else {
                // Thickness doesn't apply to text - this row is Size
                // instead for that one type (above).
                HStack(spacing: 10) {
                    ForEach(MarkupLineWidth.allCases, id: \.self) { width in
                        Button(width.rawValue.capitalized) {
                            setSelectedLineWidth(width)
                        }
                        .font(.caption.weight(selectedMarkup?.lineWidth == width ? .bold : .regular))
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { selectedMarkup?.opacity ?? 1 },
                            set: { setSelectedOpacity($0) }
                        ),
                        in: 0.2...1
                    )
                    .frame(maxWidth: 140)
                }
            }
        }
    }

    private func addMarkup(type: MarkupType) {
        let newMarkup = defaultMarkupOverlay(type: type, at: 0)
        var markup = newMarkup
        markup.endTime = max(duration, newMarkup.endTime)
        markups.append(markup)
        selectedMarkupID = markup.id
    }

    /// `MarkupCanvasView`'s `onStrokeCompleted` callback - stays in draw
    /// mode afterward (unlike every other tool, which doesn't have a
    /// "mode" at all) so drawing several strokes in a row doesn't need
    /// re-tapping Draw each time.
    private func addFreehandStroke(points: [CGPoint]) {
        let markup = MarkupOverlay(type: .freehand, startTime: 0, endTime: duration, freehandPoints: points.map(MarkupPoint.init))
        markups.append(markup)
        selectedMarkupID = markup.id
    }

    private func addTextMarkup(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let markup = MarkupOverlay(type: .text, startTime: 0, endTime: duration, pointA: CGPoint(x: 0.5, y: 0.5), text: trimmed)
        markups.append(markup)
        selectedMarkupID = markup.id
    }

    /// "Undo last stroke" - the most recently added `.freehand` markup,
    /// regardless of what's currently selected (drawing several strokes
    /// then undoing the last one shouldn't require re-selecting it
    /// first).
    private func undoLastStroke() {
        guard let index = markups.lastIndex(where: { $0.type == .freehand }) else { return }
        let removed = markups.remove(at: index)
        if selectedMarkupID == removed.id { selectedMarkupID = nil }
    }

    private func updateSelectedMarkup(_ transform: (inout MarkupOverlay) -> Void) {
        guard let id = selectedMarkupID else { return }
        updateMarkup(id: id, transform)
    }

    private func updateMarkup(id: UUID, _ transform: (inout MarkupOverlay) -> Void) {
        guard let index = markups.firstIndex(where: { $0.id == id }) else { return }
        transform(&markups[index])
    }

    private func setSelectedColor(_ hex: String) {
        updateSelectedMarkup { $0.colorHex = hex }
    }

    private func setSelectedLineWidth(_ width: MarkupLineWidth) {
        updateSelectedMarkup { $0.lineWidth = width }
    }

    private func setSelectedTextSize(_ size: MarkupTextSize) {
        updateSelectedMarkup { $0.textSize = size }
    }

    private func setSelectedOpacity(_ opacity: Double) {
        updateSelectedMarkup { $0.opacity = opacity }
    }

    private func deleteSelectedMarkup() {
        guard let id = selectedMarkupID else { return }
        markups.removeAll { $0.id == id }
        selectedMarkupID = nil
    }

    private func setUpPlayer() {
        DispatchQueue.global(qos: .userInitiated).async { [momentId, videoURL] in
            let resolved = markupBaseVideoURL(momentId: momentId, sourceVideoURL: videoURL)
            let asset = AVURLAsset(url: resolved)
            Task {
                let loadedDuration = try? await asset.load(.duration)
                let tracks = try? await asset.loadTracks(withMediaType: .video)
                let track = tracks?.first
                let loadedFrameRate = try? await track?.load(.nominalFrameRate)
                let rawSize = try? await track?.load(.naturalSize)
                let transform = try? await track?.load(.preferredTransform)
                await MainActor.run {
                    let seconds = loadedDuration?.seconds.isFinite == true ? loadedDuration!.seconds : 0
                    duration = seconds
                    if let loadedFrameRate, loadedFrameRate > 0 {
                        frameRate = Double(loadedFrameRate)
                    }
                    if let rawSize, let transform {
                        let transformedSize = rawSize.applying(transform)
                        naturalSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
                    } else {
                        naturalSize = rawSize ?? .zero
                    }
                    for index in markups.indices where markups[index].endTime < seconds {
                        markups[index].endTime = seconds
                    }
                    previewBaseURL = resolved
                    // Swapped from the raw `videoURL` the player started
                    // on, now that the real frozen base is ready.
                    player.replaceCurrentItem(with: AVPlayerItem(url: resolved))
                    seek(to: timestamp)
                }
            }
        }
    }

    /// Zero tolerance on both sides - same reasoning as
    /// MomentFreezeEditorView.swift's identical function: the plain
    /// `seek(to:)` this would otherwise be lets AVPlayer snap to the
    /// nearest keyframe instead of the exact requested time, which
    /// would make landing on a specific frame to markup unreliable.
    private func seek(to time: Double) {
        let clamped = min(max(time, 0), duration)
        timestamp = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func stepFrame(by count: Int) {
        seek(to: timestamp + Double(count) * frameDuration)
    }

    private var frameDuration: Double {
        frameRate > 0 ? 1.0 / frameRate : 1.0 / 30.0
    }

    private func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func startExport() {
        guard !momentId.isEmpty, let previewBaseURL else { return }
        exportErrorMessage = nil
        isExporting = true

        exportMarkupMoment(videoSourceURL: previewBaseURL, markups: markups) { result in
            isExporting = false
            switch result {
            case .success(let tempURL):
                guard let destination = localMomentEditedVideoURL(for: momentId) else {
                    exportErrorMessage = "Couldn't save the markup."
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: tempURL, to: destination)
                    try? FileManager.default.removeItem(at: tempURL)
                    authManager.updateMomentMarkupOverlays(momentId: momentId, markupOverlays: markups) { _ in }
                    invalidateOtherFrozenBases(momentId: momentId, except: [.markup])
                    refreshFadeIfNeeded(momentId: momentId, authManager: authManager) { onExported() }
                    onExported()
                    dismiss()
                } catch {
                    exportErrorMessage = "Couldn't save the markup: \(error.localizedDescription)"
                }
            case .failure(let error):
                exportErrorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}
