//
//  MomentPlaybackView.swift
//  PitchMark
//
//  2026-09-28: "Play" half of the tap-a-Moment dialog in
//  MomentsLibraryView (the other half opens the existing
//  MomentDetailView for editing). A dedicated, full-bleed, landscape-
//  capable viewer - just playback, no editing controls - using the same
//  orientation-unlock-while-presented technique MomentCaptureViewController
//  already uses for its recording screen (AppDelegate.orientationLock/
//  setOrientationLock), restored on dismiss.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import SwiftUI
import AVKit

struct MomentPlaybackView: View {
    let videoURL: URL

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var previousOrientationLock: UIInterfaceOrientationMask?

    init(videoURL: URL) {
        self.videoURL = videoURL
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .background(Color.black)
            // Same reasoning as OverlayEditorView's close button: this
            // screen ignores the safe area end to end, so a bare
            // `.padding()` here would land under the notch/Dynamic Island.
            .overlay(alignment: .topLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .padding(.top, 50)
                .padding(.leading, 20)
            }
            .onAppear {
                beginOrientationUnlock()
                player.play()
            }
            .onDisappear {
                player.pause()
                endOrientationUnlock()
            }
    }

    private func beginOrientationUnlock() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        guard previousOrientationLock == nil else { return }
        previousOrientationLock = AppDelegate.orientationLock
        AppDelegate.setOrientationLock(.allButUpsideDown)
    }

    private func endOrientationUnlock() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        guard let previous = previousOrientationLock else { return }
        previousOrientationLock = nil
        AppDelegate.setOrientationLock(previous)
    }
}
