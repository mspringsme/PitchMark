//
//  MomentFilterEditorView.swift
//  PitchMark
//
//  The editing screen for MomentFilter.swift's color/brightness filter
//  presets - static per-preset thumbnail swatches (one extracted frame,
//  filtered per preset) rather than a live-filtered video preview, per
//  the user's own confirmed choice: much lower implementation risk, and
//  the Simulator's CoreImage rendering can differ from on-device anyway,
//  so a live preview wouldn't be fully trustworthy here regardless.
//
//  Reuses `filterBaseVideoURL`/`invalidateMomentFilterBase` (Moment.swift)
//  - same frozen-base technique Zoom/Overlay/Audio/Slideshow/Crop
//  already use, so the swatch thumbnails and the real export both
//  always start from the pre-filter pixels, never a prior filter bake's
//  own output.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI
import AVFoundation
import CoreImage
import Combine

struct MomentFilterEditorView: View {
    let momentId: String
    let videoURL: URL
    private let previewBaseURL: URL
    var onExported: () -> Void = {}

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPreset: FilterPreset?
    @State private var baseFrameImage: UIImage? = nil
    @State private var swatches: [FilterPreset: UIImage] = [:]
    @State private var isLoadingSwatches = true

    @State private var isExporting = false
    @State private var exportErrorMessage: String? = nil

    // Live preview (2026-11-16): the clip plays with the chosen look, and
    // can be scrubbed - it used to be one still frame.
    @StateObject private var preview = FilterLivePreview()

    init(momentId: String, videoURL: URL, initialFilterPreset: FilterPreset?, onExported: @escaping () -> Void = {}) {
        self.momentId = momentId
        self.videoURL = videoURL
        self.previewBaseURL = filterBaseVideoURL(momentId: momentId, sourceVideoURL: videoURL)
        self.onExported = onExported
        _selectedPreset = State(initialValue: initialFilterPreset)
    }

    var body: some View {
        // Shared editor frame (MomentEditorChrome.swift, 2026-11-16).
            VStack(spacing: 0) {
                MomentEditorTopBar(
                    title: "Filters", systemImage: "camera.filters",
                    saveTitle: isExporting ? "Saving…" : "Save",
                    saveEnabled: !isExporting && !isLoadingSwatches,
                    onCancel: { dismiss() },
                    onSave: { startExport() }
                )
                ZStack {
                    PlayerContainerView(player: preview.player)
                    // Paused or scrubbing: the exact frame through the
                    // look, drawn the way the swatches are - always right,
                    // even where live filtered video can't draw (it's
                    // black in the simulator).
                    if !preview.isPlaying, let still = preview.stillFrame {
                        Image(uiImage: still)
                            .resizable()
                            .scaledToFit()
                    }
                }
                .frame(maxHeight: .infinity)
                .background(Color.black)
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 10) {
                    EditorScrubBar(
                        currentTime: preview.currentTime, duration: preview.duration, isPlaying: preview.isPlaying,
                        onTogglePlay: { preview.togglePlay() },
                        onSeek: { preview.seek(to: $0) }
                    )

                    Text("Pick a look")
                        .font(.subheadline.weight(.semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            swatchButton(title: "None", image: baseFrameImage, isSelected: selectedPreset == nil) {
                                selectedPreset = nil
                            }
                            ForEach(FilterPreset.allCases, id: \.self) { preset in
                                swatchButton(title: preset.displayName, image: swatches[preset], isSelected: selectedPreset == preset) {
                                    selectedPreset = preset
                                }
                            }
                        }
                    }
                    if let exportErrorMessage {
                        Text(exportErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .editorControlsPanel()
            }
            .background(Color.black.ignoresSafeArea())
        .onAppear {
            loadFrameAndSwatches()
            preview.load(url: previewBaseURL, preset: selectedPreset)
        }
        .onDisappear { preview.pause() }
        .onChange(of: selectedPreset) { _, newPreset in preview.setPreset(newPreset) }
    }

    private var previewImage: UIImage? {
        guard let selectedPreset else { return baseFrameImage }
        return swatches[selectedPreset] ?? baseFrameImage
    }

    private func swatchButton(title: String, image: UIImage?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                )
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    /// Extracts one frame from the frozen pre-filter base and renders a
    /// CIColorControls swatch per preset, off the main thread - both the
    /// extraction (AVAssetImageGenerator) and the filtering
    /// (CIContext.createCGImage) can take real time for a full-res frame.
    private func loadFrameAndSwatches() {
        let url = previewBaseURL
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVURLAsset(url: url)
            let duration = asset.duration
            guard duration.isValid, duration > .zero else {
                DispatchQueue.main.async { isLoadingSwatches = false }
                return
            }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let midpoint = CMTimeMultiplyByRatio(duration, multiplier: 1, divisor: 2)
            guard let cgImage = try? generator.copyCGImage(at: midpoint, actualTime: nil) else {
                DispatchQueue.main.async { isLoadingSwatches = false }
                return
            }

            let baseImage = UIImage(cgImage: cgImage)
            let baseCIImage = CIImage(cgImage: cgImage)
            let ciContext = CIContext()
            var generatedSwatches: [FilterPreset: UIImage] = [:]
            for preset in FilterPreset.allCases {
                let adjustment = filterAdjustment(for: preset)
                let filter = CIFilter(name: "CIColorControls")
                filter?.setValue(baseCIImage, forKey: kCIInputImageKey)
                filter?.setValue(adjustment.brightness, forKey: kCIInputBrightnessKey)
                filter?.setValue(adjustment.contrast, forKey: kCIInputContrastKey)
                filter?.setValue(adjustment.saturation, forKey: kCIInputSaturationKey)
                if let output = filter?.outputImage, let rendered = ciContext.createCGImage(output, from: baseCIImage.extent) {
                    generatedSwatches[preset] = UIImage(cgImage: rendered)
                }
            }

            DispatchQueue.main.async {
                baseFrameImage = baseImage
                swatches = generatedSwatches
                isLoadingSwatches = false
            }
        }
    }

    private func startExport() {
        exportErrorMessage = nil
        guard let destination = localMomentEditedVideoURL(for: momentId) else { return }
        isExporting = true

        guard let selectedPreset else {
            // "None" - removing a previously-applied filter is just
            // restoring the frozen pre-filter base unchanged, no real
            // export needed (mirrors how re-selecting "no crop" would
            // work, had Crop needed the same escape hatch).
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: previewBaseURL, to: destination)
                invalidateOtherFrozenBases(momentId: momentId, except: [.filter])
                // See MomentAudioEditorView.swift's identical comment.
                refreshFadeIfNeeded(momentId: momentId, authManager: authManager) { onExported() }
                authManager.updateMomentFilterPreset(momentId: momentId, filterPreset: nil) { _ in }
                isExporting = false
                onExported()
                dismiss()
            } catch {
                isExporting = false
                exportErrorMessage = "Couldn't remove the filter: \(error.localizedDescription)"
            }
            return
        }

        exportFilteredMoment(sourceURL: previewBaseURL, preset: selectedPreset) { result in
            switch result {
            case .failure(let error):
                isExporting = false
                exportErrorMessage = "Couldn't apply the filter: \(error.localizedDescription)"
            case .success(let tempURL):
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: tempURL, to: destination)
                    try? FileManager.default.removeItem(at: tempURL)
                    invalidateOtherFrozenBases(momentId: momentId, except: [.filter])
                    // See MomentAudioEditorView.swift's identical comment.
                    refreshFadeIfNeeded(momentId: momentId, authManager: authManager) { onExported() }
                    authManager.updateMomentFilterPreset(momentId: momentId, filterPreset: selectedPreset) { _ in }
                    isExporting = false
                    onExported()
                    dismiss()
                } catch {
                    isExporting = false
                    exportErrorMessage = "Couldn't save the filtered video: \(error.localizedDescription)"
                }
            }
        }
    }
}

/// The Filters editor's playing preview: the clip through the chosen look,
/// via a CI-filter video composition, so changing the look shows at once.
final class FilterLivePreview: ObservableObject {
    let player = AVPlayer()
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false
    /// The paused frame through the current look.
    @Published var stillFrame: UIImage? = nil

    private var asset: AVURLAsset?
    private var stillGeneration = 0
    private let ciContext = CIContext()

    /// Read by the composition on its own thread for every frame.
    private let lock = NSLock()
    private var preset: FilterPreset?
    private var observer: Any?
    private var endObserver: NSObjectProtocol?

    deinit {
        if let observer { player.removeTimeObserver(observer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func load(url: URL, preset: FilterPreset?) {
        setPresetValue(preset)
        let asset = AVURLAsset(url: url)
        self.asset = asset
        let item = AVPlayerItem(asset: asset)
        let composition = AVMutableVideoComposition(asset: asset, applyingCIFiltersWithHandler: { [weak self] request in
            guard let preset = self?.currentPreset() else {
                request.finish(with: request.sourceImage, context: nil)
                return
            }
            let source = request.sourceImage.clampedToExtent()
            let adjustment = filterAdjustment(for: preset)
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(source, forKey: kCIInputImageKey)
            filter?.setValue(adjustment.brightness, forKey: kCIInputBrightnessKey)
            filter?.setValue(adjustment.contrast, forKey: kCIInputContrastKey)
            filter?.setValue(adjustment.saturation, forKey: kCIInputSaturationKey)
            let output = (filter?.outputImage ?? source).cropped(to: request.sourceImage.extent)
            request.finish(with: output, context: nil)
        })
        item.videoComposition = composition
        player.replaceCurrentItem(with: item)
        // A paused player with a composition can sit black until a frame
        // is asked for - ask for the first one.
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
            self?.player.seek(to: .zero)
        }
        Task { @MainActor in
            let seconds = (try? await asset.load(.duration).seconds) ?? 0
            duration = seconds.isFinite ? seconds : 0
        }
        refreshStill()
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
    }

    private func currentPreset() -> FilterPreset? {
        lock.lock(); defer { lock.unlock() }
        return preset
    }

    private func setPresetValue(_ value: FilterPreset?) {
        lock.lock(); preset = value; lock.unlock()
    }

    /// A new look shows on the paused frame too - re-seeking redraws it.
    func setPreset(_ value: FilterPreset?) {
        setPresetValue(value)
        refreshStill()
        if !isPlaying {
            // A seek to the very same time can skip the redraw; a tiny
            // step forces the frame through the new look.
            let nudged = CMTimeAdd(player.currentTime(), CMTime(value: 1, timescale: 600))
            player.seek(to: nudged, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func togglePlay() {
        if isPlaying { pause() } else { player.play(); isPlaying = true }
    }

    func pause() {
        player.pause()
        isPlaying = false
        refreshStill()
    }

    /// The frame at the playhead through the current look. A newer request
    /// wins over one still in flight (scrubbing fires many).
    private func refreshStill() {
        guard let asset else { return }
        stillGeneration += 1
        let generation = stillGeneration
        let time = CMTime(seconds: currentTime, preferredTimescale: 600)
        let preset = currentPreset()
        let context = ciContext
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            generator.maximumSize = CGSize(width: 1280, height: 1280)
            guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { return }
            var image = UIImage(cgImage: cg)
            if let preset {
                let adjustment = filterAdjustment(for: preset)
                let input = CIImage(cgImage: cg)
                let filter = CIFilter(name: "CIColorControls")
                filter?.setValue(input, forKey: kCIInputImageKey)
                filter?.setValue(adjustment.brightness, forKey: kCIInputBrightnessKey)
                filter?.setValue(adjustment.contrast, forKey: kCIInputContrastKey)
                filter?.setValue(adjustment.saturation, forKey: kCIInputSaturationKey)
                if let output = filter?.outputImage, let rendered = context.createCGImage(output, from: input.extent) {
                    image = UIImage(cgImage: rendered)
                }
            }
            DispatchQueue.main.async {
                guard let self, generation == self.stillGeneration else { return }
                self.stillFrame = image
            }
        }
    }

    func seek(to seconds: Double) {
        if isPlaying { pause() }
        currentTime = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        refreshStill()
    }
}
