//
//  MomentCapture.swift
//  PitchMark
//
//  Phase 6 built this on UIImagePickerController, same shape as
//  PitcherImagePicker/CameraPicker (SettingsView.swift,
//  PitchTrackerView.swift). That picker can only drive one capture
//  pipeline at a time, so there's no way to fire a still through it while
//  a video recording is in progress. This rewrite drives AVCaptureSession
//  directly instead, following the one other custom-capture precedent in
//  this codebase - QRScannerViewController (PitchTrackerView.swift) -
//  same shape: a plain UIViewController owning the session, UIKit
//  controls laid out over an AVCaptureVideoPreviewLayer, start/stop tied
//  to viewWillAppear/viewWillDisappear.
//
//  Flipping the camera mid-recording went through several single-camera
//  approaches before this one, all documented for posterity because the
//  failures were informative: (1) an inline AVCaptureSession input swap -
//  crashed, (2) the same swap hardened onto a background queue per
//  Apple's own guidance - crashed identically, proving it wasn't a
//  threading issue but that AVCaptureMovieFileOutput simply won't
//  tolerate its input being torn down while it has an active recording,
//  full stop, (3) a stop-current-segment/restart-on-the-other-camera/
//  stitch-afterward scheme - worked, but dropped whatever audio happened
//  during each stop/restart gap, clipping words mid-sentence on a flip,
//  and (4) AVCaptureMultiCamSession with both cameras' inputs added once
//  and never removed, but flip still re-wiring the *connections* (preview
//  + photo output) to the other camera on every tap - also crashed
//  during recording. That last failure means even a session
//  reconfiguration transaction that never touches the movie outputs'
//  own connections isn't safe while they're actively recording - a
//  beginConfiguration/commitConfiguration pair appears to briefly disturb
//  the whole session's frame delivery, not just the connections being
//  directly changed.
//
//  This version removes ALL session reconfiguration from the flip path.
//  Both cameras get their own preview layer and their own photo output,
//  all wired once at setup and never touched again - flipping is now a
//  pure UI operation (toggle which preview layer is visible, remember
//  which photo output to fire the shutter at) with zero AVCaptureSession
//  involvement. Both movie outputs still record continuously for the
//  whole clip regardless of which camera is "active," exactly as in (4),
//  so a flip still costs no audio and no video gap - only how the
//  cameras are *displayed* changed. AVCaptureMultiCamSession.isMultiCamSupported
//  requires iPhone XS or later, which this app's iOS 17.6 deployment
//  target already requires, so the single-camera fallback below is
//  defensive, not expected to actually run. Session reconfiguration
//  (inputs/outputs/connections, startRunning/stopRunning) - what little
//  of it happens, all just once at setup - is dispatched onto a
//  dedicated sessionQueue rather than the main thread, per Apple's
//  guidance. Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this UI.
//

import SwiftUI
import AVFoundation
import AVKit
import CoreMedia

struct MomentCameraPicker: UIViewControllerRepresentable {
    /// The temp video file URL, its duration (seconds), and any stills
    /// captured during the session (JPEG data, in capture order) - or
    /// nil/nil/[] if the user cancelled without finishing a recording.
    let onComplete: (URL?, Double?, [Data]) -> Void

    func makeUIViewController(context: Context) -> MomentCaptureViewController {
        let controller = MomentCaptureViewController()
        controller.onComplete = onComplete
        return controller
    }

    func updateUIViewController(_ uiViewController: MomentCaptureViewController, context: Context) {
    }
}

enum MomentCaptureAuthorization {
    case ready
    case denied
}

/// Camera-availability/authorization check, extended from the original
/// (SettingsView.swift:778 / PitchTrackerView.swift:2957) to also request
/// microphone access - UIImagePickerController used to prompt for that
/// itself, but a hand-built AVCaptureSession needs it requested
/// explicitly before the session is configured, or recording proceeds
/// with no audio track. NSMicrophoneUsageDescription was already added
/// to Info.plist in Phase 6 for this exact reason.
func requestMomentCameraAccess(completion: @escaping (MomentCaptureAuthorization) -> Void) {
    guard AVCaptureDevice.default(for: .video) != nil else {
        completion(.denied)
        return
    }

    func resolveMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(.ready)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
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

    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
        resolveMicrophone()
    case .notDetermined:
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted {
                    resolveMicrophone()
                } else {
                    completion(.denied)
                }
            }
        }
    case .denied, .restricted:
        completion(.denied)
    @unknown default:
        completion(.denied)
    }
}

final class MomentCaptureViewController: UIViewController, AVCaptureFileOutputRecordingDelegate, AVCapturePhotoCaptureDelegate {
    var onComplete: ((URL?, Double?, [Data]) -> Void)?

    private let session = AVCaptureMultiCamSession()
    /// All AVCaptureSession configuration (adding inputs/outputs/
    /// connections, begin/commitConfiguration, startRunning/stopRunning)
    /// is dispatched here rather than run inline on the main thread, per
    /// Apple's guidance and its own AVCam/multi-cam sample code. Only
    /// used for the one-time setup and start/stop now - flipping no
    /// longer touches the session at all (see the type-level comment).
    private let sessionQueue = DispatchQueue(label: "com.pitchmark.moments.captureSession")

    private var backCameraInput: AVCaptureDeviceInput?
    private var frontCameraInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private let backMovieOutput = AVCaptureMovieFileOutput()
    private let frontMovieOutput = AVCaptureMovieFileOutput()
    /// Each camera gets its own preview layer and its own photo output,
    /// wired once at setup and never touched again - flipping toggles
    /// which layer is visible and which output the shutter fires at,
    /// nothing more. Kept as separate, fixed pipelines specifically so a
    /// flip never has to add/remove an AVCaptureConnection while
    /// anything is recording.
    private var backPreviewLayer: AVCaptureVideoPreviewLayer?
    private var frontPreviewLayer: AVCaptureVideoPreviewLayer?
    private let backPhotoOutput = AVCapturePhotoOutput()
    private let frontPhotoOutput = AVCapturePhotoOutput()
    /// True once both cameras are live and wired - false only on the
    /// (practically unreachable) fallback path, in which case Record
    /// only ever drives backMovieOutput and flip stays disabled. Only
    /// ever read/written on the main thread (see configureSession's
    /// completion block) - it used to be set on sessionQueue while every
    /// read happened on main, a genuine data race that could plausibly
    /// let Record/Flip run before setup actually finished.
    private var isMultiCamActive = false
    /// Record/Flip/Shutter are disabled until this flips true, closing
    /// the window where a fast tap right after the screen opens could
    /// fire before configureSession()'s async setup has actually wired
    /// every connection.
    private var isCaptureReady = false

    private var currentPosition: AVCaptureDevice.Position = .back
    private var currentCameraInput: AVCaptureDeviceInput? {
        currentPosition == .back ? backCameraInput : frontCameraInput
    }
    private var currentPreviewLayer: AVCaptureVideoPreviewLayer? {
        currentPosition == .back ? backPreviewLayer : frontPreviewLayer
    }
    private var currentPhotoOutput: AVCapturePhotoOutput {
        currentPosition == .back ? backPhotoOutput : frontPhotoOutput
    }

    private var capturedPhotos: [Data] = []
    private var isRecording = false
    private var didFinish = false
    private var recordingStartDate: Date?
    private var recordingTimer: Timer?
    private var previousOrientationLockForCapture: UIInterfaceOrientationMask?

    private enum StopReason {
        case finish
        case cancel
    }
    private var pendingStopReason: StopReason?
    /// How many of the movie outputs we're still waiting to hear back
    /// from after stopRecording() - 2 in normal multi-cam operation, 1 on
    /// the single-camera fallback path.
    private var expectedStopCount = 0
    private var finishedBackURL: URL?
    private var finishedFrontURL: URL?
    private var activeExportSession: AVAssetExportSession?

    private struct CameraSwitch {
        let position: AVCaptureDevice.Position
        let elapsedSeconds: Double
    }
    /// Which camera was active, and when (seconds since recording
    /// started) - the log used to pick real footage from the right file
    /// for each stretch of the final video. Seeded with the starting
    /// camera the moment Record is tapped; flipTapped() appends to it
    /// while recording, but otherwise never touches a movie output.
    private var cameraSwitchLog: [CameraSwitch] = []

    private let maxZoomFactor: CGFloat = 6

    // MARK: Controls

    private let recordButton = UIButton(type: .system)
    private let shutterButton = UIButton(type: .system)
    private let flipButton = UIButton(type: .system)
    private let torchButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let photoCountLabel = UILabel()
    private let zoom1xButton = UIButton(type: .system)
    private let zoom2xButton = UIButton(type: .system)
    private let focusReticle = UIView()
    private let timerLabel = UILabel()
    private let finishingOverlay = UIView()
    private let finishingSpinner = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configurePreviewLayers()
        configureControls()
        configureGestures()
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backPreviewLayer?.frame = view.bounds
        frontPreviewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        beginCaptureOrientationUnlock()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            self.updateVideoOrientations()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        endCaptureOrientationUnlock()
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.sessionQueue.async {
                self?.updateVideoOrientations()
            }
        }
    }

    /// The app defaults to portrait-only (`AppDelegate.orientationLock`,
    /// set in `PitchMarkApp.swift`) and widens it per-screen where
    /// rotation is actually wanted - the same save/restore shape already
    /// used for the pitch-code display flow
    /// (`PitchTrackerView.beginCodeDisplayOrientationUnlock`). Recording
    /// screen needs the same treatment so landscape video is possible.
    private func beginCaptureOrientationUnlock() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        guard previousOrientationLockForCapture == nil else { return }
        let currentLock = AppDelegate.orientationLock
        guard currentLock == .portrait else { return }

        previousOrientationLockForCapture = currentLock
        AppDelegate.setOrientationLock(.allButUpsideDown)
    }

    private func endCaptureOrientationUnlock() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        guard let previousLock = previousOrientationLockForCapture else { return }

        previousOrientationLockForCapture = nil
        AppDelegate.setOrientationLock(previousLock)
    }

    /// Apple defines UIInterfaceOrientation and AVCaptureVideoOrientation
    /// with matching raw values by design - confirmed on-device that no
    /// manual remapping is needed (an earlier version of this function
    /// swapped landscapeLeft/Right, which produced upside-down landscape
    /// recording; that "inverted landscape naming" gotcha applies to
    /// UIDeviceOrientation, not UIInterfaceOrientation).
    private func currentVideoOrientation() -> AVCaptureVideoOrientation {
        guard let interfaceOrientation = view.window?.windowScene?.interfaceOrientation,
              let videoOrientation = AVCaptureVideoOrientation(rawValue: interfaceOrientation.rawValue) else {
            return .portrait
        }
        return videoOrientation
    }

    /// Every connection this controller owns - both preview layers, both
    /// photo outputs, both movie outputs - gets the same orientation,
    /// since they're all part of the same physical device and rotate
    /// together. Setting `.videoOrientation` on a connection is a live
    /// property, not a session reconfiguration, so this is safe to call
    /// anytime, including mid-recording. This is itself called from
    /// sessionQueue (viewWillAppear/viewWillTransition), but
    /// currentVideoOrientation() reads view/window/windowScene, which
    /// are UIKit and main-thread-only (Main Thread Checker flagged this
    /// on-device) - hopping to main just for that read, synchronously,
    /// is safe here since nothing on main ever blocks waiting on
    /// sessionQueue.
    private func updateVideoOrientations() {
        let orientation: AVCaptureVideoOrientation = Thread.isMainThread
            ? currentVideoOrientation()
            : DispatchQueue.main.sync { currentVideoOrientation() }
        backPreviewLayer?.connection?.videoOrientation = orientation
        frontPreviewLayer?.connection?.videoOrientation = orientation
        backPhotoOutput.connection(with: .video)?.videoOrientation = orientation
        frontPhotoOutput.connection(with: .video)?.videoOrientation = orientation
        backMovieOutput.connection(with: .video)?.videoOrientation = orientation
        frontMovieOutput.connection(with: .video)?.videoOrientation = orientation
    }

    // MARK: Session setup

    /// AVCaptureMultiCamSession doesn't use AVCaptureSession.sessionPreset
    /// - unlike a single-camera session, each device needs an explicit
    /// active format that's actually marked multi-cam-safe
    /// (`format.isMultiCamSupported`). A device's default format is
    /// generally tuned for single-camera bandwidth and isn't necessarily
    /// one of these; leaving it as-is can exceed the hardware's
    /// simultaneous-streaming budget the moment both cameras are actually
    /// producing frames together (i.e. exactly when recording starts,
    /// not when the session merely starts running/previewing one at a
    /// time) - picks the highest-resolution compatible format available.
    private func selectMultiCamFormat(for device: AVCaptureDevice) {
        guard let bestFormat = device.formats
            .filter({ $0.isMultiCamSupported })
            .max(by: {
                let a = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                let b = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
                return Int(a.width) * Int(a.height) < Int(b.width) * Int(b.height)
            })
        else { return }

        do {
            try device.lockForConfiguration()
            device.activeFormat = bestFormat
            device.unlockForConfiguration()
        } catch {
            // Leave the device's default format if this fails.
        }
    }

    private func configureSession() {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            configureSingleCameraFallback()
            return
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let backDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let backInput = try? AVCaptureDeviceInput(device: backDevice),
              session.canAddInput(backInput) else {
            finish(url: nil, duration: nil)
            return
        }
        selectMultiCamFormat(for: backDevice)
        session.addInputWithNoConnections(backInput)
        backCameraInput = backInput

        guard let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let frontInput = try? AVCaptureDeviceInput(device: frontDevice),
              session.canAddInput(frontInput) else {
            // Front camera unavailable for some reason - fall back to
            // back-only rather than a half-wired multi-cam session.
            configureSingleCameraFallbackLocked(backInput: backInput)
            return
        }
        selectMultiCamFormat(for: frontDevice)
        session.addInputWithNoConnections(frontInput)
        frontCameraInput = frontInput

        debugLog("🎙️ mic authorization:", AVCaptureDevice.authorizationStatus(for: .audio).rawValue)
        if let mic = AVCaptureDevice.default(for: .audio) {
            debugLog("🎙️ mic device found:", mic.localizedName)
            if let micInput = try? AVCaptureDeviceInput(device: mic) {
                debugLog("🎙️ mic input created, ports:", micInput.ports.map(\.mediaType), "canAddInput:", session.canAddInput(micInput))
                if session.canAddInput(micInput) {
                    session.addInputWithNoConnections(micInput)
                    audioInput = micInput
                    debugLog("🎙️ mic input added to session")
                }
            } else {
                debugLog("🎙️ ❌ AVCaptureDeviceInput(device: mic) failed")
            }
        } else {
            debugLog("🎙️ ❌ AVCaptureDevice.default(for: .audio) returned nil")
        }

        guard session.canAddOutput(backMovieOutput), session.canAddOutput(frontMovieOutput),
              session.canAddOutput(backPhotoOutput), session.canAddOutput(frontPhotoOutput) else {
            finish(url: nil, duration: nil)
            return
        }
        session.addOutputWithNoConnections(backMovieOutput)
        session.addOutputWithNoConnections(frontMovieOutput)
        session.addOutputWithNoConnections(backPhotoOutput)
        session.addOutputWithNoConnections(frontPhotoOutput)

        guard let backVideoPort = backInput.ports.first(where: { $0.mediaType == .video }),
              let frontVideoPort = frontInput.ports.first(where: { $0.mediaType == .video }) else {
            finish(url: nil, duration: nil)
            return
        }

        // The mic is wired only into the back camera's movie output - a
        // single audio source can't safely feed two simultaneously
        // active recordings at once (confirmed on-device: wiring the
        // same port into both outputs let setup succeed but crashed the
        // instant both outputs actually started recording together).
        // finalizeMultiCamRecording() always sources audio from the back
        // file, compositing it in whenever the front camera's own
        // (audio-less) video is what's actually needed.
        //
        // The audio port gets its OWN connection to backMovieOutput,
        // separate from the video port's connection, rather than one
        // connection carrying both ports. Bundling them into a single
        // AVCaptureConnection(inputPorts: [video, audio], ...) is what
        // this file did originally, and it's what this app's very first
        // (pre-multi-cam, plain auto-connected) recorder never did -  that
        // version's audio worked. Confirmed on-device that the bundled
        // form fails silently: canAddConnection/addConnection both
        // succeed and backMovieOutput.connection(with: .audio) reports
        // non-nil, but the audio hardware route itself never opens
        // (a repeating FigCaptureSourceRemote "err == 0" assertion fires
        // right as startRecording() is called), and the saved file has
        // zero audio tracks. Separate connections per media type is what
        // AVFoundation's own auto-connect does for a plain camera+mic
        // output, so that's what this mirrors instead.
        let backVideoConnection = AVCaptureConnection(inputPorts: [backVideoPort], output: backMovieOutput)
        let frontMovieConnection = AVCaptureConnection(inputPorts: [frontVideoPort], output: frontMovieOutput)
        let backPhotoConnection = AVCaptureConnection(inputPorts: [backVideoPort], output: backPhotoOutput)
        let frontPhotoConnection = AVCaptureConnection(inputPorts: [frontVideoPort], output: frontPhotoOutput)

        debugLog("🎙️ audioInput is nil?", audioInput == nil, "ports:", audioInput?.ports.map(\.mediaType) ?? [])
        let backAudioConnection: AVCaptureConnection? = {
            guard let audioInput, let audioPort = audioInput.ports.first(where: { $0.mediaType == .audio }) else {
                debugLog("🎙️ ❌ no audio port found on audioInput")
                return nil
            }
            return AVCaptureConnection(inputPorts: [audioPort], output: backMovieOutput)
        }()

        debugLog("🎙️ canAddConnection backVideo:", session.canAddConnection(backVideoConnection),
                  "backAudio:", backAudioConnection.map { session.canAddConnection($0) } as Any,
                  "frontMovie:", session.canAddConnection(frontMovieConnection),
                  "backPhoto:", session.canAddConnection(backPhotoConnection),
                  "frontPhoto:", session.canAddConnection(frontPhotoConnection))
        guard session.canAddConnection(backVideoConnection), session.canAddConnection(frontMovieConnection),
              session.canAddConnection(backPhotoConnection), session.canAddConnection(frontPhotoConnection) else {
            debugLog("🎙️ ❌ a connection couldn't be added - aborting multi-cam setup")
            finish(url: nil, duration: nil)
            return
        }
        session.addConnection(backVideoConnection)
        if let backAudioConnection, session.canAddConnection(backAudioConnection) {
            session.addConnection(backAudioConnection)
            debugLog("🎙️ backAudioConnection added")
        }
        session.addConnection(frontMovieConnection)
        session.addConnection(backPhotoConnection)
        session.addConnection(frontPhotoConnection)

        if let backPreviewLayer {
            let connection = AVCaptureConnection(inputPort: backVideoPort, videoPreviewLayer: backPreviewLayer)
            if session.canAddConnection(connection) {
                session.addConnection(connection)
            }
        }
        if let frontPreviewLayer {
            let connection = AVCaptureConnection(inputPort: frontVideoPort, videoPreviewLayer: frontPreviewLayer)
            if session.canAddConnection(connection) {
                session.addConnection(connection)
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentPosition = .back
            self.frontPreviewLayer?.isHidden = true
            self.isMultiCamActive = true
            self.isCaptureReady = true
            self.recordButton.isEnabled = true
            self.shutterButton.isEnabled = true
            self.flipButton.isEnabled = true
        }
    }

    /// Reached only if AVCaptureMultiCamSession.isMultiCamSupported is
    /// false or the front camera can't be added - practically
    /// unreachable given this app's iOS 17.6 deployment target already
    /// requires multi-cam-capable hardware, kept as a defensive fallback
    /// rather than assuming. Back camera only, flip permanently disabled -
    /// the same safe posture Apple's own Camera app takes.
    private func configureSingleCameraFallback() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let backDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let backInput = try? AVCaptureDeviceInput(device: backDevice),
              session.canAddInput(backInput) else {
            finish(url: nil, duration: nil)
            return
        }
        configureSingleCameraFallbackLocked(backInput: backInput)
    }

    /// Must be called from inside an already-open
    /// beginConfiguration/commitConfiguration pair (see the two call
    /// sites above).
    private func configureSingleCameraFallbackLocked(backInput: AVCaptureDeviceInput) {
        session.addInputWithNoConnections(backInput)
        backCameraInput = backInput

        if let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput) {
            session.addInputWithNoConnections(micInput)
            audioInput = micInput
        }

        guard session.canAddOutput(backMovieOutput), session.canAddOutput(backPhotoOutput) else {
            finish(url: nil, duration: nil)
            return
        }
        session.addOutputWithNoConnections(backMovieOutput)
        session.addOutputWithNoConnections(backPhotoOutput)

        guard let backVideoPort = backInput.ports.first(where: { $0.mediaType == .video }) else {
            finish(url: nil, duration: nil)
            return
        }

        // Separate connections per media type - see the matching comment
        // in configureSession() for why a single connection carrying
        // both the video and audio ports doesn't actually work.
        let backVideoConnection = AVCaptureConnection(inputPorts: [backVideoPort], output: backMovieOutput)
        let backPhotoConnection = AVCaptureConnection(inputPorts: [backVideoPort], output: backPhotoOutput)
        if session.canAddConnection(backVideoConnection) { session.addConnection(backVideoConnection) }
        if session.canAddConnection(backPhotoConnection) { session.addConnection(backPhotoConnection) }
        if let audioInput, let audioPort = audioInput.ports.first(where: { $0.mediaType == .audio }) {
            let backAudioConnection = AVCaptureConnection(inputPorts: [audioPort], output: backMovieOutput)
            if session.canAddConnection(backAudioConnection) { session.addConnection(backAudioConnection) }
        }

        if let backPreviewLayer {
            let connection = AVCaptureConnection(inputPort: backVideoPort, videoPreviewLayer: backPreviewLayer)
            if session.canAddConnection(connection) {
                session.addConnection(connection)
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentPosition = .back
            self.frontPreviewLayer?.isHidden = true
            self.isMultiCamActive = false
            self.isCaptureReady = true
            self.recordButton.isEnabled = true
            self.shutterButton.isEnabled = true
            self.flipButton.isEnabled = false
            self.flipButton.alpha = 0.35
        }
    }

    private func configurePreviewLayers() {
        let back = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        back.videoGravity = .resizeAspectFill
        back.frame = view.bounds
        view.layer.addSublayer(back)
        backPreviewLayer = back

        let front = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        front.videoGravity = .resizeAspectFill
        front.frame = view.bounds
        front.isHidden = true
        view.layer.addSublayer(front)
        frontPreviewLayer = front
    }

    // MARK: Controls layout

    private func configureControls() {
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.backgroundColor = .systemRed
        recordButton.layer.cornerRadius = 34
        recordButton.layer.borderWidth = 4
        recordButton.layer.borderColor = UIColor.white.cgColor
        recordButton.addTarget(self, action: #selector(recordTapped), for: .touchUpInside)
        // Disabled until configureSession()'s async setup actually
        // finishes wiring every connection - closes a race window where
        // a fast tap right after the screen opens could start recording
        // before, say, the audio connection exists.
        recordButton.isEnabled = false
        view.addSubview(recordButton)

        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        styleShutterButton(shutterButton)
        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        shutterButton.addTarget(self, action: #selector(shutterPressed), for: .touchDown)
        shutterButton.addTarget(self, action: #selector(shutterReleased), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        shutterButton.isEnabled = false
        view.addSubview(shutterButton)

        photoCountLabel.translatesAutoresizingMaskIntoConstraints = false
        photoCountLabel.textColor = .white
        photoCountLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        photoCountLabel.textAlignment = .center
        photoCountLabel.text = "0"
        photoCountLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        photoCountLabel.layer.cornerRadius = 10
        photoCountLabel.layer.masksToBounds = true
        photoCountLabel.isHidden = true
        view.addSubview(photoCountLabel)

        flipButton.translatesAutoresizingMaskIntoConstraints = false
        styleCircularButton(flipButton, systemImage: "camera.rotate.fill")
        flipButton.addTarget(self, action: #selector(flipTapped), for: .touchUpInside)
        flipButton.isEnabled = false
        view.addSubview(flipButton)

        torchButton.translatesAutoresizingMaskIntoConstraints = false
        styleCircularButton(torchButton, systemImage: "bolt.slash.fill")
        torchButton.addTarget(self, action: #selector(torchTapped), for: .touchUpInside)
        view.addSubview(torchButton)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        styleCircularButton(closeButton, systemImage: "xmark")
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        zoom1xButton.translatesAutoresizingMaskIntoConstraints = false
        styleZoomPill(zoom1xButton, title: "1x")
        zoom1xButton.addTarget(self, action: #selector(zoom1xTapped), for: .touchUpInside)
        view.addSubview(zoom1xButton)

        zoom2xButton.translatesAutoresizingMaskIntoConstraints = false
        styleZoomPill(zoom2xButton, title: "2x")
        zoom2xButton.addTarget(self, action: #selector(zoom2xTapped), for: .touchUpInside)
        view.addSubview(zoom2xButton)

        focusReticle.translatesAutoresizingMaskIntoConstraints = false
        focusReticle.frame = CGRect(x: 0, y: 0, width: 70, height: 70)
        focusReticle.layer.borderColor = UIColor.yellow.cgColor
        focusReticle.layer.borderWidth = 1.5
        focusReticle.layer.cornerRadius = 6
        focusReticle.alpha = 0
        view.addSubview(focusReticle)

        finishingOverlay.translatesAutoresizingMaskIntoConstraints = false
        finishingOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        finishingOverlay.isHidden = true
        view.addSubview(finishingOverlay)

        finishingSpinner.translatesAutoresizingMaskIntoConstraints = false
        finishingSpinner.color = .white
        finishingOverlay.addSubview(finishingSpinner)

        let finishingLabel = UILabel()
        finishingLabel.translatesAutoresizingMaskIntoConstraints = false
        finishingLabel.text = "Finishing…"
        finishingLabel.textColor = .white
        finishingLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        finishingOverlay.addSubview(finishingLabel)

        NSLayoutConstraint.activate([
            finishingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            finishingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            finishingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            finishingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            finishingSpinner.centerXAnchor.constraint(equalTo: finishingOverlay.centerXAnchor),
            finishingSpinner.centerYAnchor.constraint(equalTo: finishingOverlay.centerYAnchor, constant: -14),
            finishingLabel.centerXAnchor.constraint(equalTo: finishingOverlay.centerXAnchor),
            finishingLabel.topAnchor.constraint(equalTo: finishingSpinner.bottomAnchor, constant: 12)
        ])

        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.textColor = .white
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        timerLabel.textAlignment = .center
        timerLabel.text = "00:00"
        timerLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        timerLabel.layer.cornerRadius = 6
        timerLabel.layer.masksToBounds = true
        timerLabel.isHidden = true
        view.addSubview(timerLabel)

        NSLayoutConstraint.activate([
            recordButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            recordButton.widthAnchor.constraint(equalToConstant: 68),
            recordButton.heightAnchor.constraint(equalToConstant: 68),

            shutterButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            shutterButton.trailingAnchor.constraint(equalTo: recordButton.leadingAnchor, constant: -40),
            shutterButton.widthAnchor.constraint(equalToConstant: 60),
            shutterButton.heightAnchor.constraint(equalToConstant: 60),

            photoCountLabel.centerXAnchor.constraint(equalTo: shutterButton.trailingAnchor, constant: 4),
            photoCountLabel.topAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -6),
            photoCountLabel.widthAnchor.constraint(equalToConstant: 20),
            photoCountLabel.heightAnchor.constraint(equalToConstant: 20),

            flipButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            flipButton.leadingAnchor.constraint(equalTo: recordButton.trailingAnchor, constant: 40),
            flipButton.widthAnchor.constraint(equalToConstant: 52),
            flipButton.heightAnchor.constraint(equalToConstant: 52),

            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            torchButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            torchButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            torchButton.widthAnchor.constraint(equalToConstant: 44),
            torchButton.heightAnchor.constraint(equalToConstant: 44),

            zoom1xButton.trailingAnchor.constraint(equalTo: zoom2xButton.leadingAnchor, constant: -10),
            zoom1xButton.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -20),
            zoom1xButton.widthAnchor.constraint(equalToConstant: 40),
            zoom1xButton.heightAnchor.constraint(equalToConstant: 40),

            zoom2xButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            zoom2xButton.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -20),
            zoom2xButton.widthAnchor.constraint(equalToConstant: 40),
            zoom2xButton.heightAnchor.constraint(equalToConstant: 40),

            timerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            timerLabel.widthAnchor.constraint(equalToConstant: 64),
            timerLabel.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func styleCircularButton(_ button: UIButton, systemImage: String) {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: systemImage)
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.5)
        config.cornerStyle = .capsule
        button.configuration = config
    }

    /// A solid white disc with a dark outer ring, echoing the still-photo
    /// shutter in Apple's own Camera app - immediately reads as "the photo
    /// button" next to the red video Record button, rather than a generic
    /// icon pill indistinguishable from flip/torch/close.
    private func styleShutterButton(_ button: UIButton) {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "camera.fill")
        config.baseForegroundColor = .black
        config.baseBackgroundColor = .white
        config.cornerStyle = .capsule
        button.configuration = config
        button.layer.cornerRadius = 30
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.35
        button.layer.shadowRadius = 3
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    private func styleZoomPill(_ button: UIButton, title: String) {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.5)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        button.configuration = config
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
    }

    private func configureGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)
    }

    // MARK: Actions

    @objc private func recordTapped() {
        guard isCaptureReady else { return }
        if isRecording {
            pendingStopReason = .finish
            backMovieOutput.stopRecording()
            if isMultiCamActive { frontMovieOutput.stopRecording() }
        } else {
            finishedBackURL = nil
            finishedFrontURL = nil
            expectedStopCount = isMultiCamActive ? 2 : 1
            cameraSwitchLog = [CameraSwitch(position: currentPosition, elapsedSeconds: 0)]

            debugLog("🎙️ at record start, backMovieOutput.connections:", backMovieOutput.connections.count,
                      "audio connection present?", backMovieOutput.connection(with: .audio) != nil,
                      "video connection present?", backMovieOutput.connection(with: .video) != nil)

            let backURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            backMovieOutput.startRecording(to: backURL, recordingDelegate: self)
            if isMultiCamActive {
                let frontURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
                frontMovieOutput.startRecording(to: frontURL, recordingDelegate: self)
            }

            isRecording = true
            recordButton.layer.cornerRadius = 12
            startRecordingTimer()
        }
    }

    private func startRecordingTimer() {
        recordingStartDate = Date()
        timerLabel.text = "00:00"
        timerLabel.isHidden = false
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateRecordingTimerLabel()
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartDate = nil
        timerLabel.isHidden = true
    }

    private func updateRecordingTimerLabel() {
        guard let start = recordingStartDate else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        timerLabel.text = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }

    @objc private func shutterTapped() {
        guard isCaptureReady else { return }
        let settings = AVCapturePhotoSettings()
        currentPhotoOutput.capturePhoto(with: settings, delegate: self)
        flashShutterFeedback()
    }

    /// Physical shutter buttons visibly depress under your finger before
    /// the shot fires - a quick scale-down on touch-down/up mirrors that,
    /// on top of the existing full-screen flash, so the button itself
    /// looks and feels like it's "taking a pic."
    @objc private func shutterPressed() {
        UIView.animate(withDuration: 0.08) {
            self.shutterButton.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        }
    }

    @objc private func shutterReleased() {
        UIView.animate(withDuration: 0.12) {
            self.shutterButton.transform = .identity
        }
    }

    /// Purely a UI operation now - toggles which of the two always-live
    /// preview layers is visible and notes when/where the flip happened
    /// for finalizeMultiCamRecording() to use later. No AVCaptureSession
    /// call of any kind happens here; that's the entire point of wiring
    /// both cameras' preview/photo/movie pipelines once at setup instead
    /// of re-wiring connections on every flip (see the type-level
    /// comment - re-wiring connections mid-recording was tried and still
    /// crashed).
    @objc private func flipTapped() {
        guard isMultiCamActive else { return }
        let requestedPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        guard (requestedPosition == .back ? backCameraInput : frontCameraInput) != nil else { return }

        if isRecording, let start = recordingStartDate {
            cameraSwitchLog.append(CameraSwitch(position: requestedPosition, elapsedSeconds: Date().timeIntervalSince(start)))
        }

        currentPosition = requestedPosition
        backPreviewLayer?.isHidden = requestedPosition != .back
        frontPreviewLayer?.isHidden = requestedPosition != .front

        if requestedPosition == .front {
            setTorch(on: false)
            torchButton.isHidden = true
        } else {
            torchButton.isHidden = false
        }
    }

    @objc private func torchTapped() {
        guard let device = currentCameraInput?.device, device.hasTorch else { return }
        setTorch(on: device.torchMode != .on)
    }

    private func setTorch(on: Bool) {
        guard let device = currentCameraInput?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            var config = UIButton.Configuration.filled()
            config.image = UIImage(systemName: on ? "bolt.fill" : "bolt.slash.fill")
            config.baseForegroundColor = .white
            config.baseBackgroundColor = on ? UIColor.systemYellow.withAlphaComponent(0.8) : UIColor.black.withAlphaComponent(0.5)
            config.cornerStyle = .capsule
            torchButton.configuration = config
        } catch {
            // Torch lock can fail transiently (e.g. thermal state); leave
            // the toggle as-is rather than surfacing an error for a
            // non-essential control.
        }
    }

    @objc private func closeTapped() {
        if isRecording {
            pendingStopReason = .cancel
            backMovieOutput.stopRecording()
            if isMultiCamActive { frontMovieOutput.stopRecording() }
        }
        activeExportSession?.cancelExport()
        activeExportSession = nil
        stopRecordingTimer()
        // finish() is idempotent (guarded by didFinish), so a delegate or
        // export callback that lands after this is a harmless no-op. Any
        // temp files get cleaned up once those callbacks do land (see the
        // .cancel branch in the recording delegate below).
        finish(url: nil, duration: nil)
    }

    @objc private func zoom1xTapped() { setZoom(1) }
    @objc private func zoom2xTapped() { setZoom(2) }

    private func setZoom(_ factor: CGFloat) {
        guard let device = currentCameraInput?.device else { return }
        let clamped = min(factor, min(maxZoomFactor, device.activeFormat.videoMaxZoomFactor))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {
            // Non-essential control; ignore a transient lock failure.
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let device = currentCameraInput?.device else { return }
        switch gesture.state {
        case .changed:
            let maxAllowed = min(maxZoomFactor, device.activeFormat.videoMaxZoomFactor)
            let newFactor = min(max(device.videoZoomFactor * gesture.scale, 1), maxAllowed)
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = newFactor
                device.unlockForConfiguration()
            } catch {
                // Non-essential control; ignore a transient lock failure.
            }
            gesture.scale = 1
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let previewLayer = currentPreviewLayer, let device = currentCameraInput?.device, device.isFocusPointOfInterestSupported else { return }
        let point = gesture.location(in: view)
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)

        do {
            try device.lockForConfiguration()
            device.focusPointOfInterest = devicePoint
            device.focusMode = .autoFocus
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {
            return
        }

        focusReticle.center = point
        focusReticle.alpha = 1
        focusReticle.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        UIView.animate(withDuration: 0.25, animations: {
            self.focusReticle.transform = .identity
        }, completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 0.5, options: [], animations: {
                self.focusReticle.alpha = 0
            })
        })
    }

    private func flashShutterFeedback() {
        let flash = UIView(frame: view.bounds)
        flash.backgroundColor = .white
        flash.alpha = 0
        view.addSubview(flash)
        UIView.animate(withDuration: 0.08, animations: {
            flash.alpha = 0.6
        }, completion: { _ in
            UIView.animate(withDuration: 0.15, animations: {
                flash.alpha = 0
            }, completion: { _ in
                flash.removeFromSuperview()
            })
        })
    }

    // MARK: AVCaptureFileOutputRecordingDelegate

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if output === backMovieOutput {
            finishedBackURL = error == nil ? outputFileURL : nil
        } else if output === frontMovieOutput {
            finishedFrontURL = error == nil ? outputFileURL : nil
        }

        expectedStopCount -= 1
        guard expectedStopCount <= 0 else { return }

        let reason = pendingStopReason ?? .finish
        pendingStopReason = nil
        isRecording = false
        recordButton.layer.cornerRadius = 34
        stopRecordingTimer()

        switch reason {
        case .cancel:
            if let url = finishedBackURL { try? FileManager.default.removeItem(at: url) }
            if let url = finishedFrontURL { try? FileManager.default.removeItem(at: url) }
            finishedBackURL = nil
            finishedFrontURL = nil
        case .finish:
            finalizeMultiCamRecording()
        }
    }

    /// Turns whatever backMovieOutput/frontMovieOutput recorded into the
    /// one file a Moment actually stores. The common case - the camera
    /// was never flipped - is a direct, no-re-encode save exactly like
    /// before this feature existed; only an actual flip pays for a real
    /// export.
    private func finalizeMultiCamRecording() {
        let switches = cameraSwitchLog
        cameraSwitchLog = []
        let backURL = finishedBackURL
        let frontURL = finishedFrontURL
        finishedBackURL = nil
        finishedFrontURL = nil

        let neverFlipped = switches.count <= 1
        let onlyPosition = switches.first?.position ?? .back

        // Fast path: recorded on the back camera the whole time, never
        // flipped. Only the back camera's connection carries audio (see
        // configureSession's comment - a single mic port can't safely
        // feed two simultaneously active recordings), so this is the
        // only case where the saved file already has everything it needs
        // with no re-encode. Every other case - front-only for the whole
        // clip, or any flip at all - goes through the compositor below,
        // which is what knows how to pull the back file's audio in
        // alongside whichever camera's video was actually active.
        if neverFlipped, onlyPosition == .back, let backURL {
            let asset = AVURLAsset(url: backURL)
            let duration = asset.duration.seconds
            debugLog("🎙️ finalizing (fast path) backURL audio tracks:", asset.tracks(withMediaType: .audio).count,
                      "video tracks:", asset.tracks(withMediaType: .video).count)
            finish(url: backURL, duration: duration.isFinite ? duration : nil)
            if let frontURL { try? FileManager.default.removeItem(at: frontURL) }
            return
        }

        guard let backURL, let frontURL else {
            // One of the two outputs never produced a file (an error, or
            // the single-camera fallback path) - nothing to composite,
            // save whatever exists directly.
            let fallbackURL = backURL ?? frontURL
            guard let fallbackURL else {
                finish(url: nil, duration: nil)
                return
            }
            let duration = AVURLAsset(url: fallbackURL).duration.seconds
            finish(url: fallbackURL, duration: duration.isFinite ? duration : nil)
            return
        }

        let effectiveSwitches = switches.isEmpty ? [CameraSwitch(position: onlyPosition, elapsedSeconds: 0)] : switches

        finishingOverlay.isHidden = false
        finishingSpinner.startAnimating()

        stitchMultiCam(switches: effectiveSwitches, backURL: backURL, frontURL: frontURL) { [weak self] result in
            guard let self else { return }
            self.finishingSpinner.stopAnimating()
            self.finishingOverlay.isHidden = true

            switch result {
            case .success(let url, let duration):
                self.finish(url: url, duration: duration)
                try? FileManager.default.removeItem(at: backURL)
                try? FileManager.default.removeItem(at: frontURL)
            case .failure:
                // Combining failed - save the back-camera file (it has
                // the authoritative audio track) rather than losing the
                // recording entirely. Matches this file's existing
                // posture toward non-essential-path failures (torch/zoom
                // lock failures degrade silently too).
                debugLog("❌ stitchMultiCam failed; falling back to back-camera file")
                let duration = AVURLAsset(url: backURL).duration.seconds
                self.finish(url: backURL, duration: duration.isFinite ? duration : nil)
                try? FileManager.default.removeItem(at: frontURL)
            }
        }
    }

    private enum StitchResult {
        case success(URL, Double)
        case failure
    }

    /// Builds the final video from two continuous, complete recordings -
    /// one per camera - by pulling the real (not re-timed, not
    /// gap-padded) footage for each stretch between flips out of
    /// whichever file was active then, via AVMutableComposition. Each
    /// stretch gets its own composition video track and its own
    /// AVMutableVideoCompositionLayerInstruction/preferredTransform,
    /// since front- and back-camera footage can need different
    /// transforms - same orientation-per-range technique used elsewhere
    /// in this app's video-export code. Audio is a single insert of the
    /// entire back-camera file's audio track, unmodified, since the mic
    /// was recording continuously for the whole clip regardless of which
    /// camera was on screen - there's nothing to split or gap-fill.
    private func stitchMultiCam(switches: [CameraSwitch], backURL: URL, frontURL: URL, completion: @escaping (StitchResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let backAsset = AVURLAsset(url: backURL)
            let frontAsset = AVURLAsset(url: frontURL)
            guard let backVideoTrack = backAsset.tracks(withMediaType: .video).first,
                  let frontVideoTrack = frontAsset.tracks(withMediaType: .video).first,
                  let backAudioTrack = backAsset.tracks(withMediaType: .audio).first else {
                DispatchQueue.main.async { completion(.failure) }
                return
            }

            let composition = AVMutableComposition()
            guard let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                DispatchQueue.main.async { completion(.failure) }
                return
            }

            do {
                try compAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: backAsset.duration), of: backAudioTrack, at: .zero)
            } catch {
                DispatchQueue.main.async { completion(.failure) }
                return
            }

            var instructions: [AVMutableVideoCompositionInstruction] = []
            var cursor = CMTime.zero
            var renderSize: CGSize = .zero
            let totalDuration = max(backAsset.duration, frontAsset.duration)

            for (index, entry) in switches.enumerated() {
                let rangeStart = CMTime(seconds: entry.elapsedSeconds, preferredTimescale: 600)
                let rangeEnd = index + 1 < switches.count
                    ? CMTime(seconds: switches[index + 1].elapsedSeconds, preferredTimescale: 600)
                    : totalDuration
                let requestedDuration = CMTimeSubtract(rangeEnd, rangeStart)
                guard requestedDuration > .zero else { continue }

                let sourceTrack = entry.position == .back ? backVideoTrack : frontVideoTrack
                let sourceAssetDuration = entry.position == .back ? backAsset.duration : frontAsset.duration
                guard rangeStart < sourceAssetDuration else { continue }
                let clampedDuration = CMTimeMinimum(requestedDuration, CMTimeSubtract(sourceAssetDuration, rangeStart))
                guard clampedDuration > .zero else { continue }

                guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    DispatchQueue.main.async { completion(.failure) }
                    return
                }
                do {
                    try compVideoTrack.insertTimeRange(CMTimeRange(start: rangeStart, duration: clampedDuration), of: sourceTrack, at: cursor)
                } catch {
                    DispatchQueue.main.async { completion(.failure) }
                    return
                }

                let transform = sourceTrack.preferredTransform
                let transformedSize = sourceTrack.naturalSize.applying(transform)
                let segmentRenderSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
                if renderSize == .zero { renderSize = segmentRenderSize }

                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: cursor, duration: clampedDuration)
                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
                layerInstruction.setTransform(transform, at: cursor)
                instruction.layerInstructions = [layerInstruction]
                instructions.append(instruction)

                cursor = CMTimeAdd(cursor, clampedDuration)
            }

            guard renderSize != .zero, !instructions.isEmpty else {
                DispatchQueue.main.async { completion(.failure) }
                return
            }

            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = renderSize
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            videoComposition.instructions = instructions

            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                DispatchQueue.main.async { completion(.failure) }
                return
            }
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mov
            exportSession.videoComposition = videoComposition

            DispatchQueue.main.async { self?.activeExportSession = exportSession }

            exportSession.exportAsynchronously {
                DispatchQueue.main.async {
                    self?.activeExportSession = nil
                    if exportSession.status == .completed {
                        let duration = composition.duration.seconds
                        completion(.success(outputURL, duration.isFinite ? duration : cursor.seconds))
                    } else {
                        completion(.failure)
                    }
                }
            }
        }
    }

    // MARK: AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        capturedPhotos.append(data)
        photoCountLabel.text = "\(capturedPhotos.count)"
        photoCountLabel.isHidden = false
    }

    // MARK: Completion

    /// Can be called from sessionQueue (configureSession's failure path)
    /// as well as the main thread (every other call site) - onComplete
    /// flows straight into SwiftUI @State updates in MomentsLibraryView,
    /// which require the main thread, so this is the one place that
    /// guarantees it regardless of caller.
    private func finish(url: URL?, duration: Double?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.didFinish else { return }
            self.didFinish = true
            let photos = url != nil ? self.capturedPhotos : []
            self.onComplete?(url, duration, photos)
        }
    }
}
