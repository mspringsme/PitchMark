//
//  TourneyMeetSpot.swift
//  PitchMark
//
//  Tourney Info's meet spots (2026-11-16): pick part of the complex on a
//  satellite map, then mark it up - a pin, text, a bullet list, arrows and
//  lines - and share it as an image so families find the team on day one.
//
//  The image is never saved to Firestore, only the region and the marks
//  (`TourneyMeetSpot`). `TourneySnapshotter` re-makes the satellite image
//  and keeps a copy on the phone, so a spot already opened still shows at
//  a field with no signal. The editor and the shared image draw the marks
//  with the same view (`TourneyMarkLayer`), so what's placed is what's sent.
//

import SwiftUI
import MapKit
import UIKit

// MARK: - Satellite image

enum TourneySnapshotter {
    /// The image's size in points (4:5); rendered at 3x.
    static let pointSize = CGSize(width: 400, height: 500)

    private static var memory = NSCache<NSString, UIImage>()

    private static func cacheURL(for spot: TourneyMeetSpot) -> URL? {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TourneyMeetSpots", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = spot.regionKey.replacingOccurrences(of: "-", with: "m").replacingOccurrences(of: ".", with: "p")
        return dir.appendingPathComponent("\(safe).jpg")
    }

    static func cachedImage(for spot: TourneyMeetSpot) -> UIImage? {
        if let image = memory.object(forKey: spot.regionKey as NSString) { return image }
        guard let url = cacheURL(for: spot), let image = UIImage(contentsOfFile: url.path) else { return nil }
        memory.setObject(image, forKey: spot.regionKey as NSString)
        return image
    }

    @MainActor
    static func image(for spot: TourneyMeetSpot) async throws -> UIImage {
        if let cached = cachedImage(for: spot) { return cached }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: spot.centerLatitude, longitude: spot.centerLongitude),
            span: MKCoordinateSpan(latitudeDelta: spot.latitudeDelta, longitudeDelta: spot.longitudeDelta)
        )
        options.size = pointSize
        options.scale = 3
        options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        let snapshot = try await MKMapSnapshotter(options: options).start()
        let image = snapshot.image
        memory.setObject(image, forKey: spot.regionKey as NSString)
        if let url = cacheURL(for: spot), let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: url, options: .atomic)
        }
        return image
    }

    /// The satellite image with the marks drawn on it, at the image's own
    /// pixel size - what gets shared.
    @MainActor
    static func renderShareImage(spot: TourneyMeetSpot, base: UIImage) -> UIImage? {
        let content = TourneyMeetSpotImage(base: base, spot: spot, selectedId: nil)
            .frame(width: pointSize.width, height: pointSize.height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        return renderer.uiImage
    }
}

// MARK: - Marks drawn over the image

/// The satellite image plus every mark. Used by the editor (with a
/// selection ring) and by the share render (without).
struct TourneyMeetSpotImage: View {
    let base: UIImage?
    let spot: TourneyMeetSpot
    var selectedId: String?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let base {
                    Image(uiImage: base)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Color.black.opacity(0.85)
                }
                TourneyMarkLayer(marks: spot.marks, size: geo.size, selectedId: selectedId)
            }
        }
        .aspectRatio(TourneyMeetSpot.aspect, contentMode: .fit)
        .clipped()
    }
}

struct TourneyMarkLayer: View {
    let marks: [TourneyMark]
    let size: CGSize
    var selectedId: String?

    /// Everything scales with the image's width, so a 400 pt editor and a
    /// 1200 px export look the same.
    private var unit: CGFloat { size.width / 400 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Each mark sits in a fixed full-size frame, so .position()
            // measures from the image's corner.
            ForEach(marks) { mark in
                Color.clear
                    .frame(width: size.width, height: size.height)
                    .overlay { markView(mark) }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func color(_ mark: TourneyMark) -> Color { hexToColor(mark.colorHex) ?? .yellow }
    private func scale(_ mark: TourneyMark) -> CGFloat { [0.75, 1.0, 1.4][max(0, min(2, mark.size - 1))] }

    private func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }

    @ViewBuilder
    private func markView(_ mark: TourneyMark) -> some View {
        let selected = mark.id == selectedId
        switch mark.kind {
        case .arrow, .line:
            let a = point(mark.x, mark.y), b = point(mark.x2, mark.y2)
            let width = 4 * unit * scale(mark)
            TourneyStrokeShape(start: a, end: b, arrowHead: mark.kind == .arrow, headLength: 16 * unit * scale(mark))
                .stroke(color(mark), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                .shadow(color: .black.opacity(0.7), radius: 2 * unit)
                .overlay {
                    if selected {
                        TourneyStrokeShape(start: a, end: b, arrowHead: false, headLength: 0)
                            .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5 * unit, dash: [5 * unit, 4 * unit]))
                    }
                }
        case .pin:
            let p = point(mark.x, mark.y)
            let iconSize = 34 * unit * scale(mark)
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: iconSize))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, color(mark))
                .shadow(color: .black.opacity(0.6), radius: 3 * unit)
                .frame(width: iconSize, height: iconSize)
                // The label sits just above the pin.
                .overlay(alignment: .bottom) {
                    if !mark.text.trimmingCharacters(in: .whitespaces).isEmpty {
                        label(mark.text, mark: mark, font: .system(size: 13 * unit * scale(mark), weight: .bold))
                            .fixedSize()
                            .offset(y: -iconSize - 2 * unit)
                    }
                }
                .overlay { selectionRing(selected) }
                // The pin's bottom sits on the point.
                .position(x: p.x, y: p.y - iconSize / 2)
        case .text:
            let p = point(mark.x, mark.y)
            label(mark.text.isEmpty ? "Text" : mark.text, mark: mark,
                  font: .system(size: 17 * unit * scale(mark), weight: .heavy))
                .overlay { selectionRing(selected) }
                .fixedSize()
                .position(p)
        case .bullets:
            let p = point(mark.x, mark.y)
            let lines = TourneyMark.bulletLines(mark.text)
            VStack(alignment: .leading, spacing: 3 * unit) {
                ForEach(Array((lines.isEmpty ? ["• List"] : lines).enumerated()), id: \.offset) { _, line in
                    Text(line)
                }
            }
            .font(.system(size: 14 * unit * scale(mark), weight: .bold))
            .foregroundStyle(color(mark))
            .padding(.horizontal, 8 * unit)
            .padding(.vertical, 6 * unit)
            .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8 * unit))
            .overlay { selectionRing(selected) }
            .fixedSize()
            .position(p)
        }
    }

    private func label(_ text: String, mark: TourneyMark, font: Font) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(color(mark))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 7 * unit)
            .padding(.vertical, 4 * unit)
            .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 7 * unit))
    }

    @ViewBuilder
    private func selectionRing(_ selected: Bool) -> some View {
        if selected {
            RoundedRectangle(cornerRadius: 8 * unit)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5 * unit, dash: [5 * unit, 4 * unit]))
                .padding(-4 * unit)
        }
    }
}

struct TourneyStrokeShape: Shape {
    var start: CGPoint
    var end: CGPoint
    var arrowHead: Bool
    var headLength: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: start)
        p.addLine(to: end)
        guard arrowHead else { return p }
        let angle = atan2(end.y - start.y, end.x - start.x)
        let spread: CGFloat = .pi / 7
        for side in [-1.0, 1.0] {
            let a = angle + .pi + spread * side
            p.move(to: end)
            p.addLine(to: CGPoint(x: end.x + cos(a) * headLength, y: end.y + sin(a) * headLength))
        }
        return p
    }
}

// MARK: - Pick the area

/// A satellite map the coach pans and zooms to the part of the complex
/// the team meets at. The visible frame is the image's 4:5, so the region
/// read back is exactly what the snapshot shows.
struct TourneyMeetAreaPicker: View {
    let start: TourneyPlace
    let onPick: (MKCoordinateRegion) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition
    @State private var region: MKCoordinateRegion? = nil
    @State private var searchText = ""
    @State private var searching = false
    @State private var searchError: String? = nil

    init(start: TourneyPlace, onPick: @escaping (MKCoordinateRegion) -> Void) {
        self.start = start
        self.onPick = onPick
        if let c = start.coordinate {
            _position = State(initialValue: .region(MKCoordinateRegion(center: c, latitudinalMeters: 500, longitudinalMeters: 400)))
        } else {
            _position = State(initialValue: .userLocation(fallback: .automatic))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    TextField("Search a park or address", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                    Button {
                        Task { await search() }
                    } label: {
                        if searching { ProgressView() } else { Image(systemName: "magnifyingglass") }
                    }
                    .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty || searching)
                }
                if let searchError {
                    Text(searchError).font(.footnote).foregroundStyle(.red)
                }

                Map(position: $position)
                    .mapStyle(.imagery(elevation: .flat))
                    .mapControls { MapCompass(); MapScaleView() }
                    .onMapCameraChange(frequency: .onEnd) { context in
                        region = context.region
                    }
                    .aspectRatio(TourneyMeetSpot.aspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .center) {
                        Image(systemName: "plus")
                            .font(.title3.weight(.light))
                            .foregroundStyle(.white.opacity(0.8))
                            .allowsHitTesting(false)
                    }

                Text("Pan and zoom until the meet spot and the way in from parking are in the frame.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Meet Spot Area")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use This View") {
                        if let region { onPick(region) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(region == nil)
                }
            }
            .onAppear { if searchText.isEmpty { searchText = start.searchText } }
        }
    }

    private func search() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        searching = true
        searchError = nil
        defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        do {
            let response = try await MKLocalSearch(request: request).start()
            if let item = response.mapItems.first {
                position = .region(MKCoordinateRegion(center: item.placemark.coordinate, latitudinalMeters: 500, longitudinalMeters: 400))
            } else {
                searchError = "Nothing found for \"\(query)\"."
            }
        } catch {
            searchError = "Couldn't search. Check your connection."
        }
    }
}

// MARK: - Mark it up

/// The markup editor: a tool row, the image (tap or drag on it), and the
/// selected mark's text, color and size. Saves the spot back through
/// `onSave`; Share renders the image with the marks.
struct TourneyMeetSpotEditor: View {
    let onSave: (TourneyMeetSpot) -> Void
    let onChangeArea: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var spot: TourneyMeetSpot
    @State private var base: UIImage? = nil
    @State private var loadError: String? = nil
    @State private var tool: Tool = .select
    @State private var selectedId: String? = nil
    @State private var dragStart: CGPoint? = nil
    @State private var dragOriginal: TourneyMark? = nil
    @State private var drawingId: String? = nil
    @State private var undoStack: [[TourneyMark]] = []
    @State private var shareItems: [Any]? = nil
    @State private var currentColor: String = TourneyMark.palette[1]
    @State private var currentSize: Int = 2
    @FocusState private var textFocused: Bool

    enum Tool: Hashable {
        case select
        case add(TourneyMarkKind)
    }

    init(spot: TourneyMeetSpot, onChangeArea: (() -> Void)? = nil, onSave: @escaping (TourneyMeetSpot) -> Void) {
        _spot = State(initialValue: spot)
        self.onChangeArea = onChangeArea
        self.onSave = onSave
    }

    private var selectedIndex: Int? {
        guard let selectedId else { return nil }
        return spot.marks.firstIndex { $0.id == selectedId }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    TextField("Name (e.g. Day 1 warmups)", text: $spot.title)
                        .textFieldStyle(.roundedBorder)

                    toolRow

                    canvas

                    if let loadError {
                        Label(loadError, systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    selectedPanel

                    HStack {
                        Button {
                            if let last = undoStack.popLast() {
                                spot.marks = last
                                if selectedIndex == nil { selectedId = nil }
                            }
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(undoStack.isEmpty)
                        Spacer()
                        if let onChangeArea {
                            Button {
                                onSave(spot)
                                dismiss()
                                onChangeArea()
                            } label: {
                                Label("Change Area", systemImage: "map")
                            }
                        }
                    }
                    .font(.subheadline)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Meet Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(spot)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        share()
                    } label: {
                        Label("Share Image", systemImage: "square.and.arrow.up")
                    }
                    .disabled(base == nil)
                }
                ToolbarItem(placement: .keyboard) {
                    HStack { Spacer(); Button("Done") { textFocused = false } }
                }
            }
            .task { await loadBase() }
            .appSheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } }), chrome: .none) {
                ShareSheet(items: shareItems ?? [])
            }
        }
    }

    // MARK: Tools

    private var toolRow: some View {
        HStack(spacing: 6) {
            toolButton(.select, title: "Move", systemImage: "hand.point.up.left")
            ForEach(TourneyMarkKind.allCases) { kind in
                toolButton(.add(kind), title: kind.title, systemImage: kind.systemImage)
            }
        }
    }

    private func toolButton(_ t: Tool, title: String, systemImage: String) -> some View {
        let on = tool == t
        return Button {
            tool = t
            if t != .select { textFocused = false }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage).font(.body.weight(.semibold))
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(on ? Color.pitchMarkActiveGray : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(on ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var hint: String {
        switch tool {
        case .select: return "Tap a mark to edit it, drag to move it."
        case .add(let kind) where kind.isStroke: return "Drag on the image to draw."
        case .add: return "Tap the image to place it."
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                TourneyMeetSpotImage(base: base, spot: spot, selectedId: selectedId)
                    .overlay {
                        if base == nil && loadError == nil {
                            ProgressView().tint(.white)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(dragGesture(size: geo.size))
            }
            .aspectRatio(TourneyMeetSpot.aspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                let sx = Double(value.startLocation.x / size.width), sy = Double(value.startLocation.y / size.height)
                let cx = min(1, max(0, Double(value.location.x / size.width)))
                let cy = min(1, max(0, Double(value.location.y / size.height)))
                if dragStart == nil {
                    dragStart = value.startLocation
                    beginDrag(x: sx, y: sy, size: size)
                }
                continueDrag(sx: sx, sy: sy, x: cx, y: cy)
            }
            .onEnded { value in
                defer { dragStart = nil; dragOriginal = nil; drawingId = nil }
                let moved = hypot(value.translation.width, value.translation.height)
                let x = min(1, max(0, Double(value.location.x / size.width)))
                let y = min(1, max(0, Double(value.location.y / size.height)))
                if case .add(let kind) = tool {
                    if kind.isStroke {
                        // A tap with a stroke tool draws nothing.
                        if moved < 8, let drawingId, let i = spot.marks.firstIndex(where: { $0.id == drawingId }) {
                            spot.marks.remove(at: i)
                            _ = undoStack.popLast()
                            selectedId = nil
                        } else if drawingId != nil {
                            tool = .select
                        }
                    } else if moved < 12 {
                        place(kind, x: x, y: y)
                    }
                }
            }
    }

    private func beginDrag(x: Double, y: Double, size: CGSize) {
        switch tool {
        case .select:
            let aspect = Double(size.height / size.width)
            let hit = spot.marks.enumerated()
                .map { ($0.element, $0.element.distance(toX: x, y: y, aspect: aspect)) }
                .filter { $0.1 < 0.09 }
                .min { $0.1 < $1.1 }?.0
            selectedId = hit?.id
            dragOriginal = hit
            if hit != nil { undoStack.append(spot.marks) }
        case .add(let kind) where kind.isStroke:
            undoStack.append(spot.marks)
            let mark = TourneyMark(kind: kind, x: x, y: y, x2: x, y2: y, colorHex: currentColor, size: currentSize)
            spot.marks.append(mark)
            drawingId = mark.id
            selectedId = mark.id
        case .add:
            break
        }
    }

    private func continueDrag(sx: Double, sy: Double, x: Double, y: Double) {
        if let original = dragOriginal, let i = spot.marks.firstIndex(where: { $0.id == original.id }) {
            spot.marks[i] = original.moved(dx: x - sx, dy: y - sy)
        } else if let drawingId, let i = spot.marks.firstIndex(where: { $0.id == drawingId }) {
            spot.marks[i].x2 = x
            spot.marks[i].y2 = y
        }
    }

    private func place(_ kind: TourneyMarkKind, x: Double, y: Double) {
        undoStack.append(spot.marks)
        let defaultText: String
        switch kind {
        case .pin: defaultText = "Meet here"
        case .text: defaultText = ""
        case .bullets: defaultText = ""
        default: defaultText = ""
        }
        let mark = TourneyMark(kind: kind, x: x, y: y, text: defaultText,
                               colorHex: kind == .pin ? TourneyMark.palette[2] : currentColor, size: currentSize)
        spot.marks.append(mark)
        selectedId = mark.id
        tool = .select
        if kind == .text || kind == .bullets { textFocused = true }
    }

    // MARK: Selected mark

    @ViewBuilder
    private var selectedPanel: some View {
        if let i = selectedIndex {
            let kind = spot.marks[i].kind
            VStack(alignment: .leading, spacing: 10) {
                if kind.hasText {
                    if kind == .bullets {
                        Text("One item per line").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $spot.marks[i].text)
                            .focused($textFocused)
                            .frame(minHeight: 90)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        TextField(kind == .pin ? "Label (optional)" : "Text", text: $spot.marks[i].text, axis: .vertical)
                            .focused($textFocused)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                HStack(spacing: 10) {
                    ForEach(TourneyMark.palette, id: \.self) { hex in
                        let on = spot.marks[i].colorHex == hex
                        Circle()
                            .fill(hexToColor(hex) ?? .white)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Color.primary.opacity(on ? 1 : 0.25), lineWidth: on ? 3 : 1))
                            .onTapGesture {
                                spot.marks[i].colorHex = hex
                                currentColor = hex
                            }
                            .accessibilityLabel("Color \(hex)")
                    }
                    Spacer(minLength: 0)
                }
                HStack {
                    Picker("Size", selection: Binding(
                        get: { spot.marks[i].size },
                        set: { spot.marks[i].size = $0; currentSize = $0 }
                    )) {
                        Text("S").tag(1)
                        Text("M").tag(2)
                        Text("L").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                    Spacer()
                    Button(role: .destructive) {
                        undoStack.append(spot.marks)
                        spot.marks.remove(at: i)
                        selectedId = nil
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: Image

    private func loadBase() async {
        if let cached = TourneySnapshotter.cachedImage(for: spot) {
            base = cached
            return
        }
        do {
            base = try await TourneySnapshotter.image(for: spot)
        } catch {
            loadError = "The satellite image needs a connection the first time. Marks are saved either way."
        }
    }

    private func share() {
        guard let base, let image = TourneySnapshotter.renderShareImage(spot: spot, base: base) else { return }
        var items: [Any] = [image]
        let title = spot.title.trimmingCharacters(in: .whitespaces)
        var caption = title.isEmpty ? "Meet spot" : title
        if let url = TourneyMapApp.apple.directionsURL(to: spot.meetPlace) {
            caption += "\nDirections: \(url.absoluteString)"
        }
        items.append(caption)
        shareItems = items
    }
}

/// A meet spot's thumbnail in lists: the cached image with its marks, or a
/// placeholder until it's been loaded once.
struct TourneyMeetSpotThumbnail: View {
    let spot: TourneyMeetSpot
    @State private var base: UIImage? = nil

    var body: some View {
        TourneyMeetSpotImage(base: base, spot: spot, selectedId: nil)
            .frame(width: 64)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .task(id: spot.regionKey) {
                base = TourneySnapshotter.cachedImage(for: spot)
                if base == nil { base = try? await TourneySnapshotter.image(for: spot) }
            }
    }
}

/// A shared tourney's meet spot, read-only: the image with its marks,
/// Share Image and Directions.
struct TourneyMeetSpotViewer: View {
    let spot: TourneyMeetSpot

    @Environment(\.dismiss) private var dismiss
    @State private var base: UIImage? = nil
    @State private var loadError = false
    @State private var shareItems: [Any]? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TourneyMeetSpotImage(base: base, spot: spot, selectedId: nil)
                        .overlay { if base == nil && !loadError { ProgressView().tint(.white) } }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    if loadError {
                        Label("The satellite image needs a connection the first time.", systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    TourneyDirectionsRow(place: spot.meetPlace)
                }
                .padding()
            }
            .navigationTitle(spot.title.isEmpty ? "Meet Spot" : spot.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        guard let base, let image = TourneySnapshotter.renderShareImage(spot: spot, base: base) else { return }
                        shareItems = [image]
                    } label: {
                        Label("Share Image", systemImage: "square.and.arrow.up")
                    }
                    .disabled(base == nil)
                }
            }
            .task {
                do { base = try await TourneySnapshotter.image(for: spot) } catch { loadError = true }
            }
            .appSheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } }), chrome: .none) {
                ShareSheet(items: shareItems ?? [])
            }
        }
    }
}
