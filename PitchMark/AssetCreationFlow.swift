//
//  AssetCreationFlow.swift
//  PitchMark
//
//  Step 7 of the 2026-09-26 Asset + Video Overlay Keyframe Editor spec:
//  the real "Create Asset" flow - a dedicated single-photo camera screen
//  (no multi-cam, no video, unlike MomentCapture.swift's recorder),
//  Choose Crop Mode (circle/square/rounded square), pan/zoom to position
//  the subject, save as a transparent PNG. Bundles capture UI + crop UI
//  + a scoped permission check together, matching how MomentCapture.swift
//  already bundles capture + permission-check.
//
//  Step 8 extends AssetCropView with a second crop mode, Smart Cutout:
//  Vision (VNGenerateForegroundInstanceMaskRequest, iOS 17+ - already
//  covered by this app's 17.6 deployment target) isolates the subject
//  automatically instead of a manual shape mask. It's a mode fork, not a
//  fourth AssetCropShape case, since its mask follows the subject's own
//  silhouette and it replaces pan/zoom entirely rather than combining
//  with it.
//
//  Design note: step 2's "Add from Photos" button on AssetLibraryView
//  saves a picked photo as-is, uncropped - a deliberate simplification
//  before this crop UI existed, left untouched here as a fast quick-add
//  path. This flow's own "Choose from Library" is a *different*, second
//  Photos entry point that - per the spec's literal flow, where
//  PhotosPicker is just an alternate *source* feeding the same crop step
//  - routes through the same Choose Crop Mode/pan-zoom/save steps as the
//  camera does, rather than skipping them.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI
import AVFoundation
import PhotosUI
import Vision
import CoreImage

enum AssetCameraAuthorization {
    case ready
    case denied
}

/// Camera-only authorization check - no microphone request, since this
/// flow never records sound. Same shape as MomentCapture.swift's
/// requestMomentCameraAccess minus its audio branch.
/// NSCameraUsageDescription already exists in Info.plist.
func requestAssetCameraAccess(completion: @escaping (AssetCameraAuthorization) -> Void) {
    guard AVCaptureDevice.default(for: .video) != nil else {
        completion(.denied)
        return
    }

    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
        completion(.ready)
    case .notDetermined:
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                completion(granted ? .ready : .denied)
            }
        }
    case .denied, .restricted:
        completion(.denied)
    @unknown default:
        completion(.denied)
    }
}

struct AssetCameraCapture: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> AssetCameraCaptureViewController {
        let controller = AssetCameraCaptureViewController()
        controller.onCapture = onCapture
        controller.onCancel = onCancel
        return controller
    }

    func updateUIViewController(_ uiViewController: AssetCameraCaptureViewController, context: Context) {
    }
}

/// Single back-camera, photo-only capture - modeled on
/// QRScannerViewController's simplicity (one AVCaptureSession, one
/// preview layer, PitchTrackerView.swift) for structure, borrowing
/// MomentCaptureViewController's shutter-button styling and
/// AVCapturePhotoCaptureDelegate mechanics for the actual capture,
/// rather than its multi-cam complexity, which a single still photo
/// doesn't need.
final class AssetCameraCaptureViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var onCapture: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "com.pitchmark.assetCapture.session")

    private let shutterButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configurePreviewLayer()
        configureControls()
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configurePreviewLayer() {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else { return }
        session.addOutput(photoOutput)

        DispatchQueue.main.async { [weak self] in
            self?.shutterButton.isEnabled = true
        }
    }

    private func configureControls() {
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        var shutterConfig = UIButton.Configuration.filled()
        shutterConfig.image = UIImage(systemName: "camera.fill")
        shutterConfig.baseForegroundColor = .black
        shutterConfig.baseBackgroundColor = .white
        shutterConfig.cornerStyle = .capsule
        shutterButton.configuration = shutterConfig
        shutterButton.layer.shadowColor = UIColor.black.cgColor
        shutterButton.layer.shadowOpacity = 0.35
        shutterButton.layer.shadowRadius = 3
        shutterButton.layer.shadowOffset = CGSize(width: 0, height: 1)
        // Disabled until configureSession()'s async setup actually wires
        // the input/output, closing the window where a fast tap right
        // after the screen opens could fire before capture is ready.
        shutterButton.isEnabled = false
        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        view.addSubview(shutterButton)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        var closeConfig = UIButton.Configuration.filled()
        closeConfig.image = UIImage(systemName: "xmark")
        closeConfig.baseForegroundColor = .white
        closeConfig.baseBackgroundColor = UIColor.black.withAlphaComponent(0.5)
        closeConfig.cornerStyle = .capsule
        closeButton.configuration = closeConfig
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            shutterButton.widthAnchor.constraint(equalToConstant: 68),
            shutterButton.heightAnchor.constraint(equalToConstant: 68),

            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func shutterTapped() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @objc private func closeTapped() {
        onCancel?()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onCapture?(image)
        }
    }
}

enum AssetCropShape: String, CaseIterable, Identifiable {
    case circle
    case square
    case roundedSquare

    var id: String { rawValue }

    /// Easy to extend with another preset - one case, one Shape.
    var shape: AnyShape {
        switch self {
        case .circle: return AnyShape(Circle())
        case .square: return AnyShape(Rectangle())
        case .roundedSquare: return AnyShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
    }

    var label: String {
        switch self {
        case .circle: return "Circle"
        case .square: return "Square"
        case .roundedSquare: return "Rounded"
        }
    }

    var icon: String {
        switch self {
        case .circle: return "circle"
        case .square: return "square"
        case .roundedSquare: return "square.on.square"
        }
    }
}

/// Step 8: Smart Cutout is a mode fork alongside the manual shape crop,
/// not a fourth AssetCropShape case - unlike a preset shape, its mask
/// follows the subject's own silhouette rather than a fixed geometric
/// shape, and it replaces pan/zoom entirely rather than combining with
/// it.
enum AssetCropMode: String, CaseIterable, Identifiable {
    case shape
    case smartCutout

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shape: return "Shape"
        case .smartCutout: return "Smart Cutout"
        }
    }
}

enum SmartCutoutError: Error {
    case noImage
    case noSubjectFound
}

struct AssetCropView: View {
    let sourceImage: UIImage
    let onSave: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var mode: AssetCropMode = .shape

    @State private var shape: AssetCropShape = .circle
    @State private var offset: CGSize = .zero
    @State private var committedScale: CGFloat = 1
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1
    @State private var isSaving = false

    // Smart Cutout state - separate from the shape-crop state above,
    // since the two modes don't share any of it.
    @State private var isProcessingCutout = false
    @State private var cutoutCandidates: [UIImage] = []
    @State private var selectedCutoutIndex: Int = 0
    @State private var cutoutErrorMessage: String? = nil

    private let cropDiameter: CGFloat = 280
    private let smartCutoutAvailable = {
        if #available(iOS 17.0, *) { return true }
        return false
    }()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if mode == .shape {
                shapeCropContent
            } else {
                smartCutoutContent
            }

            if smartCutoutAvailable {
                Picker("Crop Mode", selection: $mode) {
                    ForEach(AssetCropMode.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }

            if mode == .shape {
                Picker("Shape", selection: $shape) {
                    ForEach(AssetCropShape.allCases) { option in
                        Label(option.label, systemImage: option.icon).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }

            Spacer()

            HStack {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)
                    .tint(.white)
                Spacer()
                Button(isSaving ? "Saving…" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || (mode == .smartCutout && cutoutCandidates.isEmpty))
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .onChange(of: mode) { _, newMode in
            if newMode == .smartCutout, cutoutCandidates.isEmpty, !isProcessingCutout {
                runSmartCutout()
            }
        }
    }

    // MARK: Shape crop (unchanged from before step 8)

    private var shapeCropContent: some View {
        croppedContent(scale: committedScale * magnifyBy, offset: liveOffset)
            .overlay(shape.shape.stroke(Color.white, lineWidth: 3))
            .frame(width: cropDiameter, height: cropDiameter)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($magnifyBy) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        committedScale = min(max(committedScale * value, 1), 5)
                    }
            )
    }

    private var liveOffset: CGSize {
        CGSize(width: offset.width + dragOffset.width, height: offset.height + dragOffset.height)
    }

    /// Shared by the live preview above and `save()` below, so the
    /// rendered PNG can never drift from what pan/zoom actually showed -
    /// the same "one function drives what's on screen and what gets
    /// saved" discipline the overlay editor itself uses throughout.
    @ViewBuilder
    private func croppedContent(scale: CGFloat, offset: CGSize) -> some View {
        Image(uiImage: sourceImage)
            .resizable()
            .scaledToFill()
            .frame(width: cropDiameter, height: cropDiameter)
            .scaleEffect(scale)
            .offset(offset)
            .clipShape(shape.shape)
    }

    // MARK: Smart Cutout

    @ViewBuilder
    private var smartCutoutContent: some View {
        VStack(spacing: 12) {
            ZStack {
                Color.white.opacity(0.06)
                if isProcessingCutout {
                    VStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Finding subject…")
                            .foregroundStyle(.white)
                            .font(.caption)
                    }
                } else if let error = cutoutErrorMessage {
                    VStack(spacing: 8) {
                        Text(error)
                            .foregroundStyle(.white)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { runSmartCutout() }
                            .font(.caption)
                    }
                    .padding()
                } else if !cutoutCandidates.isEmpty {
                    Image(uiImage: cutoutCandidates[selectedCutoutIndex])
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                }
            }
            .frame(width: cropDiameter, height: cropDiameter)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Multiple detected subjects show as separately-selectable
            // thumbnails rather than requiring a precise tap on the photo
            // itself (the spec's literal suggestion) - steps 4/5 already
            // found tap-targeting directly on an image doesn't hold up
            // well on a small screen, hence the sliders/enlarged-tap-
            // targets built there. Same fix, not a new pattern.
            if cutoutCandidates.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(cutoutCandidates.indices, id: \.self) { index in
                            Button {
                                selectedCutoutIndex = index
                            } label: {
                                Image(uiImage: cutoutCandidates[index])
                                    .resizable()
                                    .scaledToFit()
                                    .padding(4)
                                    .frame(width: 60, height: 60)
                                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(index == selectedCutoutIndex ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func runSmartCutout() {
        guard smartCutoutAvailable else { return }
        isProcessingCutout = true
        cutoutErrorMessage = nil
        cutoutCandidates = []
        selectedCutoutIndex = 0

        Task {
            let result = await generateCutoutCandidates(from: sourceImage)
            await MainActor.run {
                isProcessingCutout = false
                switch result {
                case .success(let images):
                    cutoutCandidates = images
                case .failure:
                    cutoutErrorMessage = "No clear subject found in this photo. Try Shape mode instead."
                }
            }
        }
    }

    /// Renders via ImageRenderer - the spec's own suggested simpler path
    /// over hand-rolled Core Graphics crop-rect math. Preserves
    /// transparency outside the clip shape by default, satisfying "must
    /// be a transparent PNG, never JPEG" with no extra work. EXIF
    /// orientation needs no separate fix: `sourceImage.imageOrientation`
    /// is already respected by `Image(uiImage:)` here exactly as it is
    /// live above.
    private func save() {
        if mode == .smartCutout {
            guard !cutoutCandidates.isEmpty else { return }
            // Vision's masked output is already the final transparent
            // image - no ImageRenderer pass needed for this mode.
            onSave(cutoutCandidates[selectedCutoutIndex])
            return
        }

        isSaving = true
        let content = croppedContent(scale: committedScale, offset: offset)
            .frame(width: cropDiameter, height: cropDiameter)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        guard let rendered = renderer.uiImage else {
            isSaving = false
            return
        }
        onSave(rendered)
    }
}

/// Isolated as a free function (rather than a method needing
/// `@available` on the whole type) since it's the one piece of this file
/// that actually calls iOS 17+-only Vision APIs.
@available(iOS 17.0, *)
private func generateCutoutCandidates(from image: UIImage) async -> Result<[UIImage], Error> {
    guard let cgImage = image.cgImage else { return .failure(SmartCutoutError.noImage) }
    let orientation = CGImagePropertyOrientation(image.imageOrientation)
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
    let request = VNGenerateForegroundInstanceMaskRequest()

    do {
        try handler.perform([request])
        guard let observation = request.results?.first else {
            return .failure(SmartCutoutError.noSubjectFound)
        }

        let instances = observation.allInstances
        guard !instances.isEmpty else {
            return .failure(SmartCutoutError.noSubjectFound)
        }

        var images: [UIImage] = []
        for index in instances {
            guard let pixelBuffer = try? observation.generateMaskedImage(
                ofInstances: [index],
                from: handler,
                croppedToInstancesExtent: true
            ) else { continue }
            if let uiImage = uiImage(from: pixelBuffer) {
                images.append(uiImage)
            }
        }

        guard !images.isEmpty else { return .failure(SmartCutoutError.noSubjectFound) }
        return .success(images)
    } catch {
        return .failure(error)
    }
}

/// Not an SDK-provided initializer - Vision's CGImagePropertyOrientation
/// and UIKit's UIImage.Orientation are different enums with matching
/// cases, and Apple's own sample code for exactly this Vision API
/// defines this same conversion by hand.
private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

private func uiImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    let context = CIContext()
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
    return UIImage(cgImage: cgImage)
}

struct AssetCreationFlow: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var capturedImage: UIImage? = nil
    @State private var photoSelection: PhotosPickerItem? = nil
    @State private var isLoadingPhoto = false
    @State private var saveErrorMessage: String? = nil

    var body: some View {
        Group {
            if let capturedImage {
                AssetCropView(
                    sourceImage: capturedImage,
                    onSave: { saveAsset($0) },
                    onCancel: { dismiss() }
                )
            } else {
                ZStack(alignment: .bottom) {
                    AssetCameraCapture(
                        onCapture: { self.capturedImage = $0 },
                        onCancel: { dismiss() }
                    )
                    .ignoresSafeArea()

                    PhotosPicker(selection: $photoSelection, matching: .images) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text(isLoadingPhoto ? "Loading…" : "Choose from Library")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.white, in: Capsule())
                    }
                    .disabled(isLoadingPhoto)
                    .padding(.bottom, 110)
                }
            }
        }
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            loadPickedPhoto(item)
        }
        .overlay(alignment: .bottom) {
            if let saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.bottom, 12)
                    .onTapGesture { self.saveErrorMessage = nil }
            }
        }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem) {
        isLoadingPhoto = true
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                await MainActor.run {
                    isLoadingPhoto = false
                    photoSelection = nil
                    saveErrorMessage = "Couldn't load that photo."
                }
                return
            }
            await MainActor.run {
                isLoadingPhoto = false
                photoSelection = nil
                capturedImage = image
            }
        }
    }

    private func saveAsset(_ image: UIImage) {
        guard let pngData = image.pngData() else {
            saveErrorMessage = "Couldn't prepare that image."
            return
        }
        authManager.saveAsset(AssetItem(name: "New Asset")) { result in
            switch result {
            case .success(let saved):
                if let id = saved.id {
                    saveLocalAssetImage(pngData, assetId: id)
                }
                dismiss()
            case .failure(let error):
                saveErrorMessage = "Couldn't save: \(error.localizedDescription)"
            }
        }
    }
}
