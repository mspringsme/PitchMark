//
//  MomentEditorChrome.swift
//  PitchMark
//
//  The frame every Moment editor shares (2026-11-16, after "too generic,
//  too squished, some controls too close to the safe area, scrubbers hard
//  to grab"): a top bar inside the safe area with Cancel, the editor's
//  name and Save, and one big scrub bar - a large play button, a tall
//  touch area and a thick track with a big thumb you can grab anywhere.
//  Editors keep their own tools below it.
//

import SwiftUI

/// Cancel · ✂︎ Trim · Save - the same in every editor.
struct MomentEditorTopBar: View {
    let title: String
    let systemImage: String
    var saveTitle: String = "Save"
    var saveEnabled: Bool = true
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Cancel", action: onCancel)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Capsule().fill(Color.white.opacity(0.18)))
                .accessibilityIdentifier("editor.cancel")
            Spacer(minLength: 4)
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            Button(saveTitle, action: onSave)
                .font(.body.weight(.bold))
                .foregroundStyle(saveEnabled ? Color.black : Color.white.opacity(0.5))
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(Capsule().fill(saveEnabled ? Color.white : Color.white.opacity(0.18)))
                .disabled(!saveEnabled)
                .accessibilityIdentifier("editor.save")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black)
        // Drawn over the video below it, so nothing enlarged there (a
        // zoomed preview) can sit on top of Save/Cancel.
        .zIndex(10)
    }
}

/// Play/pause plus a scrubber big enough to grab with a thumb: the whole
/// 44pt-tall strip takes the drag, not just the thin line.
struct EditorScrubBar: View {
    let currentTime: Double
    let duration: Double
    let isPlaying: Bool
    var playDisabled: Bool = false
    /// Off for editors that pick a moment rather than play (Freeze Frame).
    var showsPlayButton: Bool = true
    let onTogglePlay: () -> Void
    let onSeek: (Double) -> Void
    /// true when a drag starts, false when it ends.
    var onScrubbing: (Bool) -> Void = { _ in }

    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 12) {
            if showsPlayButton {
            Button(action: onTogglePlay) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.pitchMarkActiveGray))
            }
            .buttonStyle(.plain)
            .disabled(playDisabled)
            .opacity(playDisabled ? 0.5 : 1)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("editor.play")
            }

            VStack(spacing: 2) {
                track
                HStack {
                    Text(EditorTime.format(currentTime))
                    Spacer()
                    Text(EditorTime.format(duration))
                }
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var fraction: Double {
        duration > 0 ? min(max(currentTime / duration, 0), 1) : 0
    }

    private var track: some View {
        GeometryReader { proxy in
            // The thumb's center travels inside the ends, so it never
            // hangs off the track onto the play button.
            let inset: CGFloat = 15
            let usable = max(proxy.size.width - inset * 2, 1)
            let thumb: CGFloat = isDragging ? 30 : 26
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 8)
                Capsule()
                    .fill(Color.pitchMarkActiveGray)
                    .frame(width: inset + usable * fraction, height: 8)
                Circle()
                    .fill(Color.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .overlay(Circle().stroke(Color.pitchMarkActiveGray, lineWidth: 2))
                    .offset(x: inset + usable * fraction - thumb / 2)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onScrubbing(true)
                        }
                        let x = min(max(value.location.x - inset, 0), usable)
                        onSeek(duration * Double(x / usable))
                    }
                    .onEnded { _ in
                        isDragging = false
                        onScrubbing(false)
                    }
            )
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel("Playhead")
        .accessibilityValue(EditorTime.format(currentTime))
        .accessibilityAdjustableAction { direction in
            let step = max(duration / 20, 0.1)
            onSeek(min(max(currentTime + (direction == .increment ? step : -step), 0), duration))
        }
        .accessibilityIdentifier("editor.scrubber")
    }
}

enum EditorTime {
    /// "0:04.2" under a minute's worth of precision a coach needs.
    static func format(_ seconds: Double) -> String {
        let s = max(seconds.isFinite ? seconds : 0, 0)
        let minutes = Int(s) / 60
        let rest = s - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, rest)
    }
}

extension View {
    /// The editor's tools below the video: comfortable padding, and never
    /// on top of the home indicator.
    func editorControlsPanel() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
    }
}
