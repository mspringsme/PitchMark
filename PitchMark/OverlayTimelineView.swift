//
//  OverlayTimelineView.swift
//  PitchMark
//
//  Step 5 of the 2026-09-26 Asset + Video Overlay Keyframe Editor spec:
//  a real timeline, replacing the plain Slider steps 3/4 used as a
//  placeholder scrubber. One track per overlay shows its start/end span
//  and per-keyframe markers; tapping a track or marker selects it.
//
//  Freehand-dragging the small start/end handles and keyframe markers
//  directly on this timeline was the original design here, but the user
//  found both too fiddly to hit/drag precisely by touch on a small
//  portrait screen. All actual editing of those values now happens via
//  sliders instead: start/end live in OverlayEditorView's
//  selectedOverlayPanel (they're plain fields on the selected OverlayItem,
//  no keyframe involved), and a selected keyframe's time gets its own
//  slider right here in `keyframeDetailRow`, since retiming an existing
//  keyframe is specific to this file's data. This view keeps only tap-
//  to-select (a far more forgiving touch interaction than drag-to-retime)
//  plus delete.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI

/// Time -> horizontal position within a track of `trackWidth`, given the
/// clip's total `duration`. Pure geometry, no SwiftUI dependency beyond
/// CGFloat/CGSize (re-exported by SwiftUI's own Foundation/CoreGraphics
/// imports), verified standalone the same way as `videoDisplayRect` and
/// `composeOverlayTransform`.
func timeToX(time: Double, duration: Double, trackWidth: CGFloat) -> CGFloat {
    guard duration > 0, trackWidth > 0 else { return 0 }
    let fraction = min(max(time / duration, 0), 1)
    return CGFloat(fraction) * trackWidth
}

/// Inverse of `timeToX` - horizontal position -> time.
func xToTime(x: CGFloat, duration: Double, trackWidth: CGFloat) -> Double {
    guard duration > 0, trackWidth > 0 else { return 0 }
    let fraction = min(max(Double(x / trackWidth), 0), 1)
    return fraction * duration
}

struct SelectedKeyframe: Equatable {
    let overlayID: UUID
    let keyframeID: UUID
}

struct OverlayTimelineView: View {
    @Binding var overlays: [OverlayItem]
    let duration: Double
    @Binding var currentTime: Double
    @Binding var selectedOverlayID: UUID?
    @Binding var selectedKeyframe: SelectedKeyframe?
    let onCommit: () -> Void

    private let trackHeight: CGFloat = 40
    private let maxTracksHeight: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            rulerRow

            if !overlays.isEmpty {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(overlays) { item in
                            trackRow(for: item)
                        }
                    }
                }
                .frame(maxHeight: maxTracksHeight)
            }

            if let selectedKeyframe {
                keyframeDetailRow(selectedKeyframe)
            }
        }
    }

    private var rulerRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(formattedTime(currentTime)) / \(formattedTime(duration))")
                .font(.caption2)
                .foregroundStyle(.secondary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray4))
                        .frame(height: 4)

                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                        .offset(x: timeToX(time: currentTime, duration: duration, trackWidth: geometry.size.width) - 5)
                }
                .frame(height: 16, alignment: .top)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            currentTime = xToTime(x: value.location.x, duration: duration, trackWidth: geometry.size.width)
                        }
                )
            }
            .frame(height: 20)
        }
    }

    private func formattedTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @ViewBuilder
    private func trackRow(for item: OverlayItem) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let startX = timeToX(time: item.startTime, duration: duration, trackWidth: width)
            let endX = timeToX(time: item.endTime, duration: duration, trackWidth: width)
            let midY = trackHeight / 2

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))
                    .frame(height: 6)

                // Tapping anywhere in the active range selects the whole
                // overlay - a wide, forgiving target. Start/End are edited
                // via sliders in OverlayEditorView's selectedOverlayPanel,
                // not by dragging this rect's edges.
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(item.id == selectedOverlayID ? Color.accentColor.opacity(0.45) : Color.accentColor.opacity(0.22))
                    .frame(width: max(endX - startX, 2), height: trackHeight - 10)
                    .offset(x: startX)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedOverlayID = item.id }

                ForEach(item.keyframes) { keyframe in
                    keyframeMarker(for: keyframe, in: item, trackWidth: width, midY: midY)
                }
            }
        }
        .frame(height: trackHeight)
    }

    /// A 34x34pt tap target around the small visual diamond - close to
    /// Apple's ~44pt touch-target guidance and as large as this row can
    /// give without bleeding into a neighboring track. Tap-to-select only;
    /// retiming happens via `keyframeDetailRow`'s slider, not a drag here.
    @ViewBuilder
    private func keyframeMarker(for keyframe: OverlayKeyframe, in item: OverlayItem, trackWidth: CGFloat, midY: CGFloat) -> some View {
        let x = timeToX(time: keyframe.time, duration: duration, trackWidth: trackWidth)
        let isSelected = selectedKeyframe == SelectedKeyframe(overlayID: item.id, keyframeID: keyframe.id)

        Color.clear
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isSelected ? Color.yellow : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.35), lineWidth: 1)
                    )
                    .frame(width: 9, height: 9)
                    .rotationEffect(.degrees(45))
            )
            .position(x: x, y: midY)
            .onTapGesture {
                selectedOverlayID = item.id
                selectedKeyframe = SelectedKeyframe(overlayID: item.id, keyframeID: keyframe.id)
            }
    }

    /// Selected keyframe's controls: a Time slider (bounded to its
    /// overlay's start/end - the only retiming mechanism now, replacing
    /// the old drag-the-marker interaction) and delete, disabled on an
    /// overlay's last remaining keyframe (removing the whole overlay is
    /// `selectedOverlayPanel`'s trash button's job).
    @ViewBuilder
    private func keyframeDetailRow(_ selection: SelectedKeyframe) -> some View {
        if let overlayIndex = overlays.firstIndex(where: { $0.id == selection.overlayID }),
           let keyframeIndex = overlays[overlayIndex].keyframes.firstIndex(where: { $0.id == selection.keyframeID }) {
            let item = overlays[overlayIndex]
            let canDelete = item.keyframes.count > 1

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Keyframe Time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        overlays[overlayIndex].keyframes.removeAll { $0.id == selection.keyframeID }
                        selectedKeyframe = nil
                        onCommit()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.caption)
                    }
                    .disabled(!canDelete)
                }

                HStack {
                    Slider(
                        value: Binding(
                            get: { overlays[overlayIndex].keyframes[keyframeIndex].time },
                            set: { newValue in
                                overlays[overlayIndex].keyframes[keyframeIndex].time = min(max(newValue, item.startTime), item.endTime)
                            }
                        ),
                        in: item.startTime...max(item.endTime, item.startTime + 0.01),
                        onEditingChanged: { editing in
                            if !editing {
                                overlays[overlayIndex].keyframes.sort { $0.time < $1.time }
                                onCommit()
                            }
                        }
                    )
                    Text(formattedTime(item.keyframes[keyframeIndex].time))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
}
