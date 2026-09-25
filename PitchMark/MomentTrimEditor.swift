//
//  MomentTrimEditor.swift
//  PitchMark
//
//  Phase 7b - native-UI trim for Moments (UIVideoEditorController, the
//  system's own yellow-handle trim control - the same one Camera/Photos
//  use). Operates directly on a local file path, no Photos library
//  involvement, which is why it fits editing a Moment's own sandboxed
//  video file. A first custom Slider-based trim UI, and a separate
//  from-scratch AVFoundation text-overlay compositing step, were both
//  tried and removed after on-device testing: the sliders' bounds were
//  seeded from a possibly-imprecise recorded duration (silently clipping
//  playback even untouched), and the text-overlay export path was
//  unreliable and not wanted. This file is now just the trim wrapper.
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this UI.
//

import SwiftUI
import UIKit

struct MomentTrimEditor: UIViewControllerRepresentable {
    let videoPath: String
    /// The edited file's path on success, nil on cancel or failure.
    let onComplete: (String?) -> Void

    func makeUIViewController(context: Context) -> UIVideoEditorController {
        let editor = UIVideoEditorController()
        editor.videoPath = videoPath
        editor.videoQuality = .typeMedium
        editor.delegate = context.coordinator
        return editor
    }

    func updateUIViewController(_ uiViewController: UIVideoEditorController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, UIVideoEditorControllerDelegate, UINavigationControllerDelegate {
        private let onComplete: (String?) -> Void

        init(onComplete: @escaping (String?) -> Void) {
            self.onComplete = onComplete
        }

        func videoEditorController(_ editor: UIVideoEditorController, didSaveEditedVideoToPath editedVideoPath: String) {
            onComplete(editedVideoPath)
        }

        func videoEditorControllerDidCancel(_ editor: UIVideoEditorController) {
            onComplete(nil)
        }

        func videoEditorController(_ editor: UIVideoEditorController, didFailWithError error: Error) {
            debugLog("❌ MomentTrimEditor failed:", error.localizedDescription)
            onComplete(nil)
        }
    }
}
