//
//  MomentCapture.swift
//  PitchMark
//
//  Phase 6 - the record flow. Same UIViewControllerRepresentable/
//  UIImagePickerController shape as PitcherImagePicker/CameraPicker
//  (SettingsView.swift, PitchTrackerView.swift), just video instead of a
//  still image, and the same camera-authorization check already used at
//  SettingsView.swift:778 / PitchTrackerView.swift:2957 (openCameraForJoin),
//  reused rather than re-invented. Deliberately kept out of the Pitchmark
//  Display target's membershipExceptions; Display has no use for this UI.
//

import SwiftUI
import AVFoundation
import AVKit

struct MomentCameraPicker: UIViewControllerRepresentable {
    /// The temp file URL and duration (seconds), or nil if the user
    /// cancelled without recording anything.
    let onComplete: (URL?, Double?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.movie"]
        picker.cameraCaptureMode = .video
        picker.videoQuality = .typeMedium
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onComplete: (URL?, Double?) -> Void

        init(onComplete: @escaping (URL?, Double?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil, nil)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let videoURL = info[.mediaURL] as? URL else {
                onComplete(nil, nil)
                return
            }
            let duration = AVURLAsset(url: videoURL).duration.seconds
            onComplete(videoURL, duration.isFinite ? duration : nil)
        }
    }
}

enum MomentCaptureAuthorization {
    case ready
    case denied
}

/// Same camera-availability/authorization check as `openCameraForJoin()`
/// (`SettingsView.swift:778-804`, `PitchTrackerView.swift:2957-2984`),
/// reused verbatim rather than duplicated a third time. Microphone
/// permission (needed for recording audio) is handled by
/// `UIImagePickerController` itself once presented - no separate
/// pre-check for it, same as every other app that uses this picker for
/// video.
func requestMomentCameraAccess(completion: @escaping (MomentCaptureAuthorization) -> Void) {
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
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
