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

    init(momentId: String, videoURL: URL, initialFilterPreset: FilterPreset?, onExported: @escaping () -> Void = {}) {
        self.momentId = momentId
        self.videoURL = videoURL
        self.previewBaseURL = filterBaseVideoURL(momentId: momentId, sourceVideoURL: videoURL)
        self.onExported = onExported
        _selectedPreset = State(initialValue: initialFilterPreset)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Group {
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxHeight: .infinity)
                .background(Color.black)

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
                    .padding(.horizontal)
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
                        Text(isExporting ? "Applying…" : "Apply")
                            .font(.headline)
                        Spacer()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
                .disabled(isExporting || isLoadingSwatches)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isExporting)
                }
            }
        }
        .onAppear { loadFrameAndSwatches() }
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
