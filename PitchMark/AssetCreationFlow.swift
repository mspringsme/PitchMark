//
//  AssetCreationFlow.swift
//  PitchMark
//
//  Step 7 of the 2026-09-26 Asset + Video Overlay Keyframe Editor spec:
//  the real "Create Asset" flow - a dedicated single-photo camera screen
//  (no multi-cam, no video, unlike MomentCapture.swift's recorder),
//  Choose Crop Mode (circle/square/rounded square; Smart Cutout is step
//  8, not built here), pan/zoom to position the subject, save as a
//  transparent PNG. Bundles capture UI + crop UI + a scoped permission
//  check together, matching how MomentCapture.swift already bundles
//  capture + permission-check.
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

struct AssetCropView: View {
    let sourceImage: UIImage
    let onSave: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var shape: AssetCropShape = .circle
    @State private var offset: CGSize = .zero
    @State private var committedScale: CGFloat = 1
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1
    @State private var isSaving = false

    private let cropDiameter: CGFloat = 280

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

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

            Picker("Shape", selection: $shape) {
                ForEach(AssetCropShape.allCases) { option in
                    Label(option.label, systemImage: option.icon).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Spacer()

            HStack {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)
                    .tint(.white)
                Spacer()
                Button(isSaving ? "Saving…" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
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

    /// Renders via ImageRenderer - the spec's own suggested simpler path
    /// over hand-rolled Core Graphics crop-rect math. Preserves
    /// transparency outside the clip shape by default, satisfying "must
    /// be a transparent PNG, never JPEG" with no extra work. EXIF
    /// orientation needs no separate fix: `sourceImage.imageOrientation`
    /// is already respected by `Image(uiImage:)` here exactly as it is
    /// live above.
    private func save() {
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
