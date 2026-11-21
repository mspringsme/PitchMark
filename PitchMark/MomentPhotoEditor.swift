//
//  MomentPhotoEditor.swift
//  PitchMark
//
//  Edit Photo (2026-11-18): crop, rotate and filter a Moment's photo -
//  mostly for stills saved from a video (Save a Still), which usually
//  need framing. The first edit keeps the photo as it was
//  (`localMomentPhotoOriginalURL`) and every edit starts again from that
//  original with the last settings (`localMomentPhotoEditURL`), so edits
//  never stack up quality loss and can always be reverted.
//

import SwiftUI
import UIKit
import CoreImage

/// Crop shapes for a photo.
enum PhotoCropAspect: String, Codable, CaseIterable, Identifiable {
    case original, square, fourByFive, sixteenByNine, nineBySixteen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .square: return "Square"
        case .fourByFive: return "4:5"
        case .sixteenByNine: return "16:9"
        case .nineBySixteen: return "9:16"
        }
    }

    /// Width / height; nil keeps the photo's own shape.
    var ratio: CGFloat? {
        switch self {
        case .original: return nil
        case .square: return 1
        case .fourByFive: return 4.0 / 5.0
        case .sixteenByNine: return 16.0 / 9.0
        case .nineBySixteen: return 9.0 / 16.0
        }
    }
}

/// One photo's edit: rotation, crop window and filter. Plain math, kept
/// out of the view.
struct PhotoEdit: Codable, Equatable {
    /// Clockwise quarter turns, 0...3.
    var quarterTurns: Int = 0
    var aspect: PhotoCropAspect = .original
    /// 1 = the biggest window of `aspect` that fits; up to `maxZoom`.
    var zoom: Double = 1
    /// Window center, 0...1 of the rotated photo.
    var centerX: Double = 0.5
    var centerY: Double = 0.5
    var filter: FilterPreset? = nil

    static let maxZoom: Double = 5

    var isIdentity: Bool {
        quarterTurns % 4 == 0 && aspect == .original && zoom <= 1 && filter == nil
    }

    /// The photo's size after rotation.
    func rotatedSize(_ size: CGSize) -> CGSize {
        quarterTurns % 2 == 0 ? size : CGSize(width: size.height, height: size.width)
    }

    /// The crop window, 0...1 of the rotated photo, always inside it.
    func normalizedCropRect(rotatedSize size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let photoRatio = size.width / size.height
        let ratio = aspect.ratio ?? photoRatio
        var width = size.width
        var height = size.height
        if photoRatio > ratio {
            width = height * ratio
        } else {
            height = width / ratio
        }
        let z = CGFloat(min(max(zoom, 1), Self.maxZoom))
        let nw = width / z / size.width
        let nh = height / z / size.height
        let cx = min(max(CGFloat(centerX), nw / 2), 1 - nw / 2)
        let cy = min(max(CGFloat(centerY), nh / 2), 1 - nh / 2)
        return CGRect(x: cx - nw / 2, y: cy - nh / 2, width: nw, height: nh)
    }

    /// The crop window in pixels of the rotated photo.
    func cropRect(rotatedSize size: CGSize) -> CGRect {
        let n = normalizedCropRect(rotatedSize: size)
        return CGRect(x: n.minX * size.width, y: n.minY * size.height,
                      width: n.width * size.width, height: n.height * size.height).integral
            .intersection(CGRect(origin: .zero, size: size))
    }

    /// Keeps the stored center where the window actually is, so a later
    /// drag starts from what's on screen.
    mutating func settleCenter(rotatedSize size: CGSize) {
        let n = normalizedCropRect(rotatedSize: size)
        centerX = Double(n.midX)
        centerY = Double(n.midY)
    }

    mutating func rotateClockwise() {
        quarterTurns = (quarterTurns + 1) % 4
        centerX = 0.5
        centerY = 0.5
    }

    /// Rotated, then cropped (unless `crop` is false), then filtered.
    /// Works in pixels whatever the image's scale.
    static func render(_ image: UIImage, edit: PhotoEdit, crop: Bool = true) -> UIImage? {
        let source = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard source.width > 0, source.height > 0 else { return nil }
        let rotated = edit.rotatedSize(source)
        let rect = crop ? edit.cropRect(rotatedSize: rotated) : CGRect(origin: .zero, size: rotated)
        guard rect.width >= 1, rect.height >= 1 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let drawn = UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
            let cg = context.cgContext
            cg.translateBy(x: -rect.minX, y: -rect.minY)
            cg.translateBy(x: rotated.width / 2, y: rotated.height / 2)
            cg.rotate(by: CGFloat(edit.quarterTurns % 4) * .pi / 2)
            image.draw(in: CGRect(x: -source.width / 2, y: -source.height / 2,
                                  width: source.width, height: source.height))
        }
        guard let filter = edit.filter else { return drawn }
        return filtered(drawn, preset: filter) ?? drawn
    }

    private static let ciContext = CIContext()

    /// The same brightness/contrast/saturation the clip Filters use.
    static func filtered(_ image: UIImage, preset: FilterPreset) -> UIImage? {
        guard let input = CIImage(image: image),
              let controls = CIFilter(name: "CIColorControls") else { return nil }
        let adjustment = filterAdjustment(for: preset)
        controls.setValue(input, forKey: kCIInputImageKey)
        controls.setValue(adjustment.brightness, forKey: kCIInputBrightnessKey)
        controls.setValue(adjustment.contrast, forKey: kCIInputContrastKey)
        controls.setValue(adjustment.saturation, forKey: kCIInputSaturationKey)
        guard let output = controls.outputImage,
              let cg = ciContext.createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Reading and writing one photo's edit on disk.
enum MomentPhotoEditFiles {
    /// The photo to edit from: the pre-edit original if there is one.
    static func sourceURL(momentId: String, index: Int) -> URL? {
        if let original = localMomentPhotoOriginalURL(momentId: momentId, index: index),
           FileManager.default.fileExists(atPath: original.path) {
            return original
        }
        return localMomentPhotoURL(momentId: momentId, index: index)
    }

    static func hasOriginal(momentId: String, index: Int) -> Bool {
        localMomentPhotoOriginalURL(momentId: momentId, index: index)
            .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    static func savedEdit(momentId: String, index: Int) -> PhotoEdit {
        guard let url = localMomentPhotoEditURL(momentId: momentId, index: index),
              let data = try? Data(contentsOf: url),
              let edit = try? JSONDecoder().decode(PhotoEdit.self, from: data) else { return PhotoEdit() }
        return edit
    }

    /// Applies `edit` to the original and saves it as the photo. An edit
    /// that changes nothing puts the original back and forgets the edit.
    static func save(_ edit: PhotoEdit, momentId: String, index: Int) -> Bool {
        let fm = FileManager.default
        guard let photoURL = localMomentPhotoURL(momentId: momentId, index: index),
              let originalURL = localMomentPhotoOriginalURL(momentId: momentId, index: index),
              let editURL = localMomentPhotoEditURL(momentId: momentId, index: index) else { return false }

        if edit.isIdentity {
            if fm.fileExists(atPath: originalURL.path) {
                try? fm.removeItem(at: photoURL)
                do { try fm.moveItem(at: originalURL, to: photoURL) } catch { return false }
            }
            try? fm.removeItem(at: editURL)
            HomeSlideImages.forgetAll()
            return true
        }

        if !fm.fileExists(atPath: originalURL.path) {
            do { try fm.copyItem(at: photoURL, to: originalURL) } catch { return false }
        }
        guard let data = try? Data(contentsOf: originalURL),
              let source = UIImage(data: data),
              let rendered = PhotoEdit.render(source, edit: edit),
              let jpeg = rendered.jpegData(compressionQuality: 0.92) else { return false }
        do {
            try jpeg.write(to: photoURL, options: [.atomic])
            try JSONEncoder().encode(edit).write(to: editURL, options: [.atomic])
        } catch {
            debugLog("❌ photo edit save failed:", error.localizedDescription)
            return false
        }
        HomeSlideImages.forgetAll()
        return true
    }
}

struct MomentPhotoEditorView: View {
    let momentId: String
    let index: Int
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var edit = PhotoEdit()
    /// The original, shrunk for the screen.
    @State private var base: UIImage? = nil
    /// `base` rotated and filtered (not cropped - the window shows that).
    @State private var preview: UIImage? = nil
    @State private var dragStart: CGPoint? = nil
    @State private var zoomStart: Double? = nil
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @State private var hasOriginal = false

    var body: some View {
        VStack(spacing: 0) {
            MomentEditorTopBar(
                title: "Edit Photo", systemImage: "crop",
                saveTitle: isSaving ? "Saving…" : "Save",
                saveEnabled: !isSaving && base != nil,
                onCancel: { dismiss() },
                onSave: { save() }
            )

            photoArea
                .frame(maxHeight: .infinity)
                .background(Color.black)

            controls
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
        .onAppear(perform: load)
        .onChange(of: edit.quarterTurns) { _ in refreshPreview() }
        .onChange(of: edit.filter) { _ in refreshPreview() }
    }

    private var photoArea: some View {
        GeometryReader { geometry in
            if let preview {
                let shown = fitted(preview.size, in: geometry.size)
                let origin = CGPoint(x: (geometry.size.width - shown.width) / 2,
                                     y: (geometry.size.height - shown.height) / 2)
                let n = edit.normalizedCropRect(rotatedSize: preview.size)
                let window = CGRect(x: origin.x + n.minX * shown.width, y: origin.y + n.minY * shown.height,
                                    width: n.width * shown.width, height: n.height * shown.height)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: preview)
                        .resizable()
                        .frame(width: shown.width, height: shown.height)
                        .offset(x: origin.x, y: origin.y)
                    Path { path in
                        path.addRect(CGRect(origin: origin, size: shown))
                        path.addRect(window)
                    }
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    Path { path in path.addRect(window) }
                        .stroke(Color.white, lineWidth: 2)
                    thirds(in: window)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(shown: shown, rotated: preview.size))
                .simultaneousGesture(pinchGesture(rotated: preview.size))
            } else {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
    }

    private func thirds(in window: CGRect) -> some View {
        Path { path in
            for i in 1...2 {
                let x = window.minX + window.width * CGFloat(i) / 3
                let y = window.minY + window.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: window.minY)); path.addLine(to: CGPoint(x: x, y: window.maxY))
                path.move(to: CGPoint(x: window.minX, y: y)); path.addLine(to: CGPoint(x: window.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(0.35), lineWidth: 1)
        .allowsHitTesting(false)
    }

    private func dragGesture(shown: CGSize, rotated: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragStart ?? CGPoint(x: edit.centerX, y: edit.centerY)
                if dragStart == nil { dragStart = start }
                edit.centerX = Double(start.x + value.translation.width / max(shown.width, 1))
                edit.centerY = Double(start.y + value.translation.height / max(shown.height, 1))
                edit.settleCenter(rotatedSize: rotated)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func pinchGesture(rotated: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let start = zoomStart ?? edit.zoom
                if zoomStart == nil { zoomStart = start }
                edit.zoom = min(max(start * Double(scale), 1), PhotoEdit.maxZoom)
                edit.settleCenter(rotatedSize: rotated)
            }
            .onEnded { _ in zoomStart = nil }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    edit.rotateClockwise()
                } label: {
                    Label("Rotate", systemImage: "rotate.right")
                }
                Button {
                    edit = PhotoEdit()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .disabled(edit.isIdentity)
                Spacer()
                Text("Drag to move · pinch to zoom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.bordered)
            .tint(Color.pitchMarkActiveGray)

            chipRow(title: "Crop") {
                ForEach(PhotoCropAspect.allCases) { aspect in
                    chip(aspect.title, isOn: edit.aspect == aspect) {
                        edit.aspect = aspect
                        if let size = preview?.size { edit.settleCenter(rotatedSize: size) }
                    }
                }
            }

            chipRow(title: "Filter") {
                chip("None", isOn: edit.filter == nil) { edit.filter = nil }
                ForEach(FilterPreset.allCases, id: \.self) { preset in
                    chip(preset.displayName, isOn: edit.filter == preset) { edit.filter = preset }
                }
            }

            if hasOriginal {
                Text("Reset and Save puts the photo back the way it was.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func chipRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { content() }
            }
        }
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(Capsule().fill(isOn ? Color.pitchMarkActiveGray : Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }

    private func fitted(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func load() {
        hasOriginal = MomentPhotoEditFiles.hasOriginal(momentId: momentId, index: index)
        edit = MomentPhotoEditFiles.savedEdit(momentId: momentId, index: index)
        guard let url = MomentPhotoEditFiles.sourceURL(momentId: momentId, index: index) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let image = HomeSlideImages.downsampled(url, maxPixel: 1600)
            DispatchQueue.main.async {
                base = image
                refreshPreview()
            }
        }
    }

    private func refreshPreview() {
        guard let base else { return }
        preview = PhotoEdit.render(base, edit: edit, crop: false)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        let edit = self.edit
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = MomentPhotoEditFiles.save(edit, momentId: momentId, index: index)
            DispatchQueue.main.async {
                isSaving = false
                if ok {
                    onSaved()
                    dismiss()
                } else {
                    errorMessage = "Couldn't save the photo. Try again."
                }
            }
        }
    }
}
