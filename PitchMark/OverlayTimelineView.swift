//
//  OverlayTimelineView.swift
//  PitchMark
//
//  Step 5 of the 2026-09-26 Asset + Video Overlay Keyframe Editor spec:
//  a real timeline, replacing the plain Slider steps 3/4 used as a
//  placeholder scrubber. One track per overlay with draggable start/end
//  handles (how long that overlay is visible) and per-keyframe markers
//  (tap to select, drag to retime, delete to remove).
//
//  Deliberately diverges from OverlayEditorView's step 4 @GestureState
//  pattern: step 4 had exactly one "selected item" gesture slot, which is
//  what made per-instance @GestureState practical. This view has an
//  arbitrary, dynamic number of draggable elements (two handles per
//  overlay, one marker per keyframe) - @GestureState can't express that
//  (it must be declared statically on the view, never per loop
//  iteration). Instead, every handle/marker's DragGesture writes straight
//  into the bound `overlays` array during `.onChanged`, looked up by id
//  (never array index, so retiming a keyframe past another one can't
//  scramble which marker is being dragged) - the row re-renders from that
//  same live state, so visual feedback is immediate with no separate
//  preview layer. `.onEnded` calls `onCommit()` once per completed drag,
//  not once per pixel.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI

/// Time -> horizontal position within a track of `trackWidth`, given the
/// clip's total `duration`. Pure geometry, no SwiftUI dependency beyond
/// CGFloat/CGSize (re-exported by SwiftUI's own Foundation/CoreGraphics
/// imports), verified standalone the same way as `videoDisplayRect` and
/// `applyGestureDelta`.
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

    private let trackHeight: CGFloat = 32
    private let minimumSpan: Double = 0.15
    private let maxTracksHeight: CGFloat = 140

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
                keyframeDeleteRow(selectedKeyframe)
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

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(item.id == selectedOverlayID ? Color.accentColor.opacity(0.45) : Color.accentColor.opacity(0.22))
                    .frame(width: max(endX - startX, 2), height: trackHeight - 10)
                    .offset(x: startX)
                    .onTapGesture { selectedOverlayID = item.id }

                handleView()
                    .position(x: startX, y: midY)
                    .gesture(startHandleDrag(for: item, trackWidth: width))

                handleView()
                    .position(x: endX, y: midY)
                    .gesture(endHandleDrag(for: item, trackWidth: width))

                ForEach(item.keyframes) { keyframe in
                    keyframeMarker(for: keyframe, in: item, trackWidth: width, midY: midY)
                }
            }
        }
        .frame(height: trackHeight)
    }

    private func handleView() -> some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 6, height: trackHeight - 6)
            .shadow(color: .black.opacity(0.3), radius: 1)
    }

    private func startHandleDrag(for item: OverlayItem, trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard let index = overlays.firstIndex(where: { $0.id == item.id }) else { return }
                let proposed = xToTime(x: value.location.x, duration: duration, trackWidth: trackWidth)
                let maxStart = max(overlays[index].endTime - minimumSpan, 0)
                overlays[index].startTime = min(max(proposed, 0), maxStart)
            }
            .onEnded { _ in onCommit() }
    }

    private func endHandleDrag(for item: OverlayItem, trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard let index = overlays.firstIndex(where: { $0.id == item.id }) else { return }
                let proposed = xToTime(x: value.location.x, duration: duration, trackWidth: trackWidth)
                let minEnd = min(overlays[index].startTime + minimumSpan, duration)
                overlays[index].endTime = max(min(proposed, duration), minEnd)
            }
            .onEnded { _ in onCommit() }
    }

    @ViewBuilder
    private func keyframeMarker(for keyframe: OverlayKeyframe, in item: OverlayItem, trackWidth: CGFloat, midY: CGFloat) -> some View {
        let x = timeToX(time: keyframe.time, duration: duration, trackWidth: trackWidth)
        let isSelected = selectedKeyframe == SelectedKeyframe(overlayID: item.id, keyframeID: keyframe.id)

        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(isSelected ? Color.yellow : Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.35), lineWidth: 1)
            )
            .frame(width: 9, height: 9)
            .rotationEffect(.degrees(45))
            .position(x: x, y: midY)
            .onTapGesture {
                selectedOverlayID = item.id
                selectedKeyframe = SelectedKeyframe(overlayID: item.id, keyframeID: keyframe.id)
            }
            .gesture(keyframeDrag(for: item, keyframeID: keyframe.id, trackWidth: trackWidth))
    }

    private func keyframeDrag(for item: OverlayItem, keyframeID: UUID, trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard let overlayIndex = overlays.firstIndex(where: { $0.id == item.id }),
                      let keyframeIndex = overlays[overlayIndex].keyframes.firstIndex(where: { $0.id == keyframeID }) else { return }
                let proposed = xToTime(x: value.location.x, duration: duration, trackWidth: trackWidth)
                let clamped = min(max(proposed, overlays[overlayIndex].startTime), overlays[overlayIndex].endTime)
                overlays[overlayIndex].keyframes[keyframeIndex].time = clamped
            }
            .onEnded { _ in
                if let overlayIndex = overlays.firstIndex(where: { $0.id == item.id }) {
                    overlays[overlayIndex].keyframes.sort { $0.time < $1.time }
                }
                onCommit()
            }
    }

    @ViewBuilder
    private func keyframeDeleteRow(_ selection: SelectedKeyframe) -> some View {
        if let overlayIndex = overlays.firstIndex(where: { $0.id == selection.overlayID }) {
            let canDelete = overlays[overlayIndex].keyframes.count > 1
            HStack {
                Text("Keyframe selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    overlays[overlayIndex].keyframes.removeAll { $0.id == selection.keyframeID }
                    selectedKeyframe = nil
                    onCommit()
                } label: {
                    Label("Delete Keyframe", systemImage: "trash")
                        .font(.caption)
                }
                .disabled(!canDelete)
            }
        }
    }
}
