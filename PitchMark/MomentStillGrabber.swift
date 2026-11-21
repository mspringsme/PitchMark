//
//  MomentStillGrabber.swift
//  PitchMark
//
//  Save a Still (2026-11-18): pick one frame of a clip and keep it as a
//  photo on the same Moment - so it shows in the Moment's Photos, in
//  Combine Photos + Video, and in Home's slideshow. Built on the shared editor frame
//  (MomentEditorChrome.swift) and Freeze Frame's exact-frame seeking.
//

import SwiftUI
import AVFoundation
import UIKit

enum MomentStillGrab {
    /// The exact frame at `seconds`, upright, full size, as JPEG data.
    static func jpegData(videoURL: URL, seconds: Double) async -> Data? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        guard let cgImage = try? await generator.image(at: time).image else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.92)
    }
}

struct MomentStillGrabberView: View {
    let videoURL: URL
    /// Hands back the still's JPEG and whether to ♥ it for Home.
    let onSave: (Data, Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer
    @State private var duration: Double = 0
    @State private var frameRate: Double = 30
    @State private var timestamp: Double = 0
    @State private var isSaving = false
    @State private var favorite = true
    @State private var errorMessage: String? = nil

    init(videoURL: URL, onSave: @escaping (Data, Bool) -> Void) {
        self.videoURL = videoURL
        self.onSave = onSave
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    private var frameDuration: Double { 1.0 / max(frameRate, 1) }

    var body: some View {
        VStack(spacing: 0) {
            MomentEditorTopBar(
                title: "Save a Still", systemImage: "camera.viewfinder",
                saveTitle: isSaving ? "Saving…" : "Save",
                saveEnabled: !isSaving && duration > 0,
                onCancel: { dismiss() },
                onSave: { save() }
            )

            PlayerContainerView(player: player)
                .allowsHitTesting(false)
                .background(Color.black)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                Text("Pick the frame to keep")
                    .font(.subheadline.weight(.semibold))
                EditorScrubBar(
                    currentTime: timestamp, duration: duration, isPlaying: false,
                    showsPlayButton: false,
                    onTogglePlay: {},
                    onSeek: { seek(to: $0) }
                )
                HStack(spacing: 14) {
                    Button {
                        seek(to: timestamp - frameDuration)
                    } label: {
                        Label("Back", systemImage: "backward.frame.fill")
                            .frame(minWidth: 90, minHeight: 36)
                    }
                    Spacer()
                    Text(String(format: "%.2fs", timestamp))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        seek(to: timestamp + frameDuration)
                    } label: {
                        Label("Next", systemImage: "forward.frame.fill")
                            .frame(minWidth: 90, minHeight: 36)
                    }
                }
                .buttonStyle(.bordered)
                .tint(Color.pitchMarkActiveGray)

                Toggle(isOn: $favorite) {
                    Label("Favorite - plays on Home", systemImage: favorite ? "heart.fill" : "heart")
                }
                .tint(.red)
                .accessibilityIdentifier("stillGrabber.favorite")

                Text("The still is added to this Moment's Photos, where its ♥ and a long press (Edit, Hide, Remove) are.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.systemBackground))
        }
        .background(Color.black.ignoresSafeArea())
        .overlay {
            if isSaving {
                ZStack {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    ProgressView().tint(.white).scaleEffect(1.4)
                }
            }
        }
        .onAppear { setUpPlayer() }
        .onDisappear { player.pause() }
    }

    /// Exact-frame seeks, same as Freeze Frame.
    private func seek(to time: Double) {
        let clamped = min(max(time, 0), duration)
        timestamp = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func setUpPlayer() {
        let asset = AVURLAsset(url: videoURL)
        Task {
            let loadedDuration = try? await asset.load(.duration)
            let track = try? await asset.loadTracks(withMediaType: .video).first
            let rate = try? await track?.load(.nominalFrameRate)
            await MainActor.run {
                let seconds = loadedDuration?.seconds ?? 0
                duration = seconds.isFinite ? seconds : 0
                if let rate, rate > 0 { frameRate = Double(rate) }
                seek(to: 0)
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        let seconds = timestamp
        let favorite = self.favorite
        Task {
            let data = await MomentStillGrab.jpegData(videoURL: videoURL, seconds: seconds)
            await MainActor.run {
                isSaving = false
                guard let data else {
                    errorMessage = "Couldn't save that frame. Try another spot."
                    return
                }
                onSave(data, favorite)
                dismiss()
            }
        }
    }
}

/// Removing one photo from a Moment (2026-11-18). Photos are files
/// numbered 0..<photoCount, so the later ones move down one; anything that
/// names a photo by number (Combine Photos + Video's order, Home's
/// favorites/hidden) is renumbered the same way.
enum MomentPhotoRemoval {
    /// Where photo `old` ends up; nil for the removed one.
    static func newIndex(_ old: Int, removing index: Int) -> Int? {
        if old == index { return nil }
        return old > index ? old - 1 : old
    }

    /// Combine Photos + Video's order without the removed photo.
    static func segments(_ segments: [SlideshowSegment], removing index: Int) -> [SlideshowSegment] {
        segments.compactMap { segment in
            guard segment.kind == .photo, let photo = segment.photoIndex else { return segment }
            guard let moved = newIndex(photo, removing: index) else { return nil }
            var copy = segment
            copy.photoIndex = moved
            return copy
        }
    }

    /// Deletes the photo's files (photo, pre-edit original, edit
    /// settings) and moves the later photos' files down one.
    @discardableResult
    static func removeFiles(momentId: String, index: Int, photoCount: Int) -> Bool {
        let fm = FileManager.default
        guard index >= 0, index < photoCount else { return false }
        for url in localMomentPhotoFileURLs(momentId: momentId, index: index) {
            try? fm.removeItem(at: url)
        }
        for old in (index + 1)..<max(photoCount, index + 1) {
            let froms = localMomentPhotoFileURLs(momentId: momentId, index: old)
            let tos = localMomentPhotoFileURLs(momentId: momentId, index: old - 1)
            for (from, to) in zip(froms, tos) {
                try? fm.removeItem(at: to)
                guard fm.fileExists(atPath: from.path) else { continue }
                do {
                    try fm.moveItem(at: from, to: to)
                } catch {
                    debugLog("❌ removeMomentPhoto move failed:", error.localizedDescription)
                    return false
                }
            }
        }
        HomeSlideImages.forgetAll()
        return true
    }
}
