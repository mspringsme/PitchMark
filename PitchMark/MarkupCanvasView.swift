//
//  MarkupCanvasView.swift
//  PitchMark
//
//  2026-10-07: the reusable rendering/gesture surface for MarkupOverlay.swift's
//  model - draws each markup with SwiftUI Path/Shape (never a rasterized
//  image), handles selection, and handles the two distinct gesture
//  shapes the spec calls for: dragging the shape's BODY moves every
//  point together, dragging an endpoint HANDLE moves just that point.
//
//  Zero Moment dependency - takes only a `markups` binding, a
//  `selectedID` binding, and the already-computed `videoRect`
//  (`videoDisplayRect`, OverlayEditorView.swift). This is what a future
//  Training section would consume directly; MarkupEditorView.swift is
//  the Moment-specific shell around it.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI

private func clamp01(_ value: CGFloat) -> CGFloat {
    min(max(value, 0), 1)
}

private func clamp01Point(_ point: CGPoint) -> CGPoint {
    CGPoint(x: clamp01(point.x), y: clamp01(point.y))
}

struct MarkupCanvasView: View {
    @Binding var markups: [MarkupOverlay]
    @Binding var selectedID: UUID?
    let videoRect: CGRect
    let currentTime: Double
    /// Freehand's creation gesture is fundamentally different from every
    /// other tool's "insert a default shape, then adjust handles" -
    /// there's no default shape, the shape IS whatever's drawn. While
    /// true, an invisible capture layer sits on TOP of every existing
    /// markup (so starting a new stroke never gets mistaken for
    /// grabbing an existing one) and reports the finished stroke's
    /// normalized points back to the caller, which decides what to do
    /// with them (MarkupEditorView.swift creates a new `.freehand`
    /// markup from it).
    var isDrawingActive: Bool = false
    var onStrokeCompleted: ([CGPoint]) -> Void = { _ in }

    var body: some View {
        if videoRect != .zero {
            ForEach($markups) { $markup in
                if markup.isVisible(at: currentTime) {
                    MarkupItemView(
                        markup: $markup,
                        isSelected: markup.id == selectedID,
                        videoRect: videoRect,
                        onSelect: { selectedID = markup.id }
                    )
                }
            }
            if isDrawingActive {
                MarkupDrawingCaptureView(videoRect: videoRect, onStrokeCompleted: onStrokeCompleted)
            }
        }
    }
}

/// Captures one continuous drag as a freehand stroke - sized/positioned
/// to exactly `videoRect`, so `value.location` (the gesture's default
/// `.local` coordinate space) already matches this view's own frame
/// one-to-one; dividing by that frame's size is all that's needed to
/// normalize, no origin offset math required.
private struct MarkupDrawingCaptureView: View {
    let videoRect: CGRect
    let onStrokeCompleted: ([CGPoint]) -> Void

    @State private var liveViewPoints: [CGPoint] = []

    var body: some View {
        ZStack {
            Color.clear
            if liveViewPoints.count > 1 {
                Path { path in
                    path.move(to: liveViewPoints[0])
                    for point in liveViewPoints.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                // Fixed preview style (not whatever's currently
                // selected, since nothing is selected yet mid-stroke) -
                // matches `defaultMarkupOverlay`'s own white/medium
                // defaults, so the live preview and the stroke that
                // actually gets created look identical.
                .stroke(Color.white, style: StrokeStyle(lineWidth: markupStrokeWidth(.medium, in: videoRect.size), lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: videoRect.width, height: videoRect.height)
        .position(x: videoRect.midX, y: videoRect.midY)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    liveViewPoints.append(value.location)
                }
                .onEnded { _ in
                    let points = liveViewPoints
                    liveViewPoints = []
                    guard points.count > 1, videoRect.width > 0, videoRect.height > 0 else { return }
                    let normalized = points.map {
                        CGPoint(x: min(max($0.x / videoRect.width, 0), 1), y: min(max($0.y / videoRect.height, 0), 1))
                    }
                    onStrokeCompleted(normalized)
                }
        )
    }
}

/// One markup's full interaction surface - owns its own gesture state
/// (via `@Binding var markup`, one instance per array element) rather
/// than a shared selection-wide gesture state, since up to 3 independent
/// drag targets (body, endpoint A, endpoint B) can exist per item and
/// Swift's property wrappers need fixed, named declarations - simplest
/// to just give each item its own small set rather than a shared
/// enum-keyed one.
private struct MarkupItemView: View {
    @Binding var markup: MarkupOverlay
    let isSelected: Bool
    let videoRect: CGRect
    let onSelect: () -> Void

    @GestureState private var bodyDrag: CGSize = .zero
    @GestureState private var pointADrag: CGSize = .zero
    @GestureState private var pointBDrag: CGSize = .zero
    @GestureState private var pointCDrag: CGSize = .zero
    @GestureState private var radiusXDrag: CGSize = .zero
    @GestureState private var radiusYDrag: CGSize = .zero

    private var color: Color { hexToColor(markup.colorHex) ?? .white }
    private var lineWidth: CGFloat { markupStrokeWidth(markup.lineWidth, in: videoRect.size) }

    private func toView(_ normalized: CGPoint) -> CGPoint {
        CGPoint(x: videoRect.minX + normalized.x * videoRect.width, y: videoRect.minY + normalized.y * videoRect.height)
    }

    private func normalizedDelta(_ translation: CGSize) -> CGPoint {
        guard videoRect.width > 0, videoRect.height > 0 else { return .zero }
        return CGPoint(x: translation.width / videoRect.width, y: translation.height / videoRect.height)
    }

    // Body-drag adds to every point at once; a point-specific drag adds
    // only to its own point. At most one of these GestureStates is ever
    // non-zero at a time (a touch is either on the body or on one
    // handle), so summing them for live rendering is safe.
    private var liveTotalBodyDelta: CGPoint { normalizedDelta(bodyDrag) }

    private var livePointA: CGPoint {
        guard let base = markup.pointA else { return .zero }
        let delta = normalizedDelta(CGSize(width: bodyDrag.width + pointADrag.width, height: bodyDrag.height + pointADrag.height))
        return clamp01Point(CGPoint(x: base.x + delta.x, y: base.y + delta.y))
    }

    private var livePointB: CGPoint {
        guard let base = markup.pointB else { return .zero }
        let delta = normalizedDelta(CGSize(width: bodyDrag.width + pointBDrag.width, height: bodyDrag.height + pointBDrag.height))
        return clamp01Point(CGPoint(x: base.x + delta.x, y: base.y + delta.y))
    }

    private var liveC: CGPoint {
        guard let base = markup.pointC else { return .zero }
        let delta = normalizedDelta(CGSize(width: bodyDrag.width + pointCDrag.width, height: bodyDrag.height + pointCDrag.height))
        return clamp01Point(CGPoint(x: base.x + delta.x, y: base.y + delta.y))
    }

    private var liveCenter: CGPoint {
        guard let base = markup.ellipseCenter else { return .zero }
        return clamp01Point(CGPoint(x: base.x + liveTotalBodyDelta.x, y: base.y + liveTotalBodyDelta.y))
    }

    // `markup.freehandPoints` is `[MarkupPoint]` (the Firestore-safe
    // storage shape - see that type's doc comment), converted to
    // `CGPoint` here via `.cgPoint` where real math is needed.
    private var liveFreehandPoints: [CGPoint] {
        guard let base = markup.freehandPoints else { return [] }
        let delta = liveTotalBodyDelta
        return base.map {
            let point = $0.cgPoint
            return clamp01Point(CGPoint(x: point.x + delta.x, y: point.y + delta.y))
        }
    }

    private var liveRadii: CGSize {
        guard let base = markup.ellipseRadii else { return .zero }
        let dx = normalizedDelta(radiusXDrag).x
        let dy = normalizedDelta(radiusYDrag).y
        return CGSize(width: max(base.width + dx, 0.02), height: max(base.height + dy, 0.02))
    }

    var body: some View {
        switch markup.type {
        case .line, .arrow:
            lineOrArrowBody
        case .ellipse:
            ellipseBody
        case .angle:
            angleBody
        case .freehand:
            freehandBody
        case .text:
            textBody
        }
    }

    @ViewBuilder
    private var lineOrArrowBody: some View {
        let a = toView(livePointA)
        let b = toView(livePointB)
        let hitPath = Path { path in
            path.move(to: a)
            path.addLine(to: b)
        }

        ZStack {
            Path { path in
                path.move(to: a)
                path.addLine(to: b)
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            if markup.type == .arrow {
                Path { path in
                    let head = arrowheadPoints(from: a, to: b, lineWidth: lineWidth)
                    path.move(to: head[0])
                    path.addLine(to: head[1])
                    path.addLine(to: head[2])
                    path.closeSubpath()
                }
                .fill(color)
            }
        }
        .opacity(markup.opacity)
        .contentShape(hitPath.strokedPath(StrokeStyle(lineWidth: max(lineWidth, 44), lineCap: .round)))
        .onTapGesture { onSelect() }
        .gesture(bodyDragGesture)
        .overlay {
            if isSelected {
                handleView(at: a, gesture: pointADragGesture)
                handleView(at: b, gesture: pointBDragGesture)
            }
        }
    }

    @ViewBuilder
    private var ellipseBody: some View {
        let center = toView(liveCenter)
        let radii = CGSize(width: liveRadii.width * videoRect.width, height: liveRadii.height * videoRect.height)
        let rect = CGRect(x: center.x - radii.width, y: center.y - radii.height, width: radii.width * 2, height: radii.height * 2)

        Ellipse()
            .stroke(color, lineWidth: lineWidth)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .opacity(markup.opacity)
            .contentShape(Ellipse())
            .onTapGesture { onSelect() }
            .gesture(bodyDragGesture)
            .overlay {
                if isSelected {
                    handleView(at: CGPoint(x: rect.maxX, y: rect.midY), gesture: radiusXDragGesture)
                    handleView(at: CGPoint(x: rect.midX, y: rect.maxY), gesture: radiusYDragGesture)
                }
            }
    }

    @ViewBuilder
    private var angleBody: some View {
        let a = toView(livePointA)
        let vertex = toView(livePointB)
        let c = toView(liveC)
        let path = Path { p in
            p.move(to: a)
            p.addLine(to: vertex)
            p.addLine(to: c)
        }
        let degrees = angleDegrees(a: a, vertex: vertex, c: c)
        let labelCenter = angleLabelAnchor(a: a, vertex: vertex, c: c, distance: 28)
        // Frame-relative, not a fixed `.caption` point size - the same
        // proportion-safety `markupStrokeWidth`/`markupTextFontSize`
        // already apply elsewhere. A fixed size here read as readable
        // on a small on-screen videoRect but "extremely small" once
        // scaled up to a real export renderSize - reported by the user
        // directly off an actual export.
        let labelFontSize = markupTextFontSize(.medium, in: videoRect.size)

        ZStack {
            path.stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            // Always shown in Phase 2, per the spec's own "ok to always
            // show if it keeps the UI simpler for the first
            // implementation" - no hide toggle yet.
            Text("\(Int(degrees.rounded()))°")
                .font(.system(size: labelFontSize, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                .position(labelCenter)
        }
        .opacity(markup.opacity)
        .contentShape(path.strokedPath(StrokeStyle(lineWidth: max(lineWidth, 44), lineCap: .round, lineJoin: .round)))
        .onTapGesture { onSelect() }
        .gesture(bodyDragGesture)
        .overlay {
            if isSelected {
                handleView(at: a, gesture: pointADragGesture)
                handleView(at: vertex, gesture: pointBDragGesture)
                handleView(at: c, gesture: pointCDragGesture)
            }
        }
    }

    @ViewBuilder
    private var freehandBody: some View {
        let points = liveFreehandPoints.map { toView($0) }
        let path = Path { p in
            guard let first = points.first else { return }
            p.move(to: first)
            for point in points.dropFirst() {
                p.addLine(to: point)
            }
        }

        // A faint wider halo behind the real stroke is the only
        // selection indicator for freehand - there's no handle to show
        // (impractical at potentially hundreds of points), so without
        // this a selected stroke would look identical to an unselected
        // one.
        ZStack {
            if isSelected {
                path.stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: lineWidth + 8, lineCap: .round, lineJoin: .round))
            }
            path.stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .opacity(markup.opacity)
        .contentShape(path.strokedPath(StrokeStyle(lineWidth: max(lineWidth, 44), lineCap: .round, lineJoin: .round)))
        .onTapGesture { onSelect() }
        .gesture(bodyDragGesture)
    }

    @ViewBuilder
    private var textBody: some View {
        let position = toView(livePointA)
        let fontSize = markupTextFontSize(markup.textSize ?? .medium, in: videoRect.size)

        Text(markup.text?.isEmpty == false ? markup.text! : "Note")
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .opacity(markup.opacity)
            .position(position)
            .onTapGesture { onSelect() }
            .gesture(bodyDragGesture)
    }

    private func handleView(at point: CGPoint, gesture: some Gesture) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
            .frame(width: 14, height: 14)
            // Visible handle stays small; the actual tap/drag target is
            // padded out to a comfortable touch size, per the spec's own
            // "reasonably sized touch targets even if the visible handle
            // itself is small."
            .contentShape(Circle().inset(by: -15))
            .position(point)
            .gesture(gesture)
    }

    private var bodyDragGesture: some Gesture {
        DragGesture()
            .updating($bodyDrag) { value, state, _ in state = value.translation }
            .onEnded { value in
                onSelect()
                let delta = normalizedDelta(value.translation)
                if let a = markup.pointA {
                    markup.pointA = clamp01Point(CGPoint(x: a.x + delta.x, y: a.y + delta.y))
                }
                if let b = markup.pointB {
                    markup.pointB = clamp01Point(CGPoint(x: b.x + delta.x, y: b.y + delta.y))
                }
                if let c = markup.pointC {
                    markup.pointC = clamp01Point(CGPoint(x: c.x + delta.x, y: c.y + delta.y))
                }
                if let center = markup.ellipseCenter {
                    markup.ellipseCenter = clamp01Point(CGPoint(x: center.x + delta.x, y: center.y + delta.y))
                }
                if let points = markup.freehandPoints {
                    markup.freehandPoints = points.map {
                        let point = $0.cgPoint
                        return MarkupPoint(clamp01Point(CGPoint(x: point.x + delta.x, y: point.y + delta.y)))
                    }
                }
            }
    }

    private var pointADragGesture: some Gesture {
        DragGesture()
            .updating($pointADrag) { value, state, _ in state = value.translation }
            .onEnded { value in
                guard let base = markup.pointA else { return }
                let delta = normalizedDelta(value.translation)
                markup.pointA = clamp01Point(CGPoint(x: base.x + delta.x, y: base.y + delta.y))
            }
    }

    private var pointBDragGesture: some Gesture {
        DragGesture()
            .updating($pointBDrag) { value, state, _ in state = value.translation }
            .onEnded { value in
                guard let base = markup.pointB else { return }
                let delta = normalizedDelta(value.translation)
                markup.pointB = clamp01Point(CGPoint(x: base.x + delta.x, y: base.y + delta.y))
            }
    }

    private var pointCDragGesture: some Gesture {
        DragGesture()
            .updating($pointCDrag) { value, state, _ in state = value.translation }
            .onEnded { value in
                guard let base = markup.pointC else { return }
                let delta = normalizedDelta(value.translation)
                markup.pointC = clamp01Point(CGPoint(x: base.x + delta.x, y: base.y + delta.y))
            }
    }

    private var radiusXDragGesture: some Gesture {
        DragGesture()
            .updating($radiusXDrag) { value, state, _ in state = value.translation }
            .onEnded { value in
                guard let base = markup.ellipseRadii else { return }
                let dx = normalizedDelta(value.translation).x
                markup.ellipseRadii = CGSize(width: max(base.width + dx, 0.02), height: base.height)
            }
    }

    private var radiusYDragGesture: some Gesture {
        DragGesture()
            .updating($radiusYDrag) { value, state, _ in state = value.translation }
            .onEnded { value in
                guard let base = markup.ellipseRadii else { return }
                let dy = normalizedDelta(value.translation).y
                markup.ellipseRadii = CGSize(width: base.width, height: max(base.height + dy, 0.02))
            }
    }
}
