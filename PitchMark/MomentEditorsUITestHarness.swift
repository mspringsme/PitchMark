//
//  MomentEditorsUITestHarness.swift
//  PitchMark
//
//  `-UITestMomentEditors` (2026-11-16): a Moment's real details screen on a
//  generated 6-second test video saved on this phone, so UI tests and
//  screenshots can open every editor exactly the way a coach does. Nothing
//  is written to Firestore (the demo isn't signed in).
//

import SwiftUI
import UIKit

struct MomentEditorsUITestHarness: View {
    static let momentId = "uitest-moment"

    @State private var moment: Moment? = nil
    @State private var failed = false

    var body: some View {
        Group {
            if let moment {
                MomentDetailView(moment: moment, allMoments: [moment])
            } else if failed {
                Text("Couldn't build the test video.")
            } else {
                ProgressView("Building test video…")
            }
        }
        .onAppear(perform: build)
    }

    private func build() {
        guard moment == nil else { return }
        let colors: [UIColor] = [.systemGreen, .systemBlue, .systemOrange]
        let images = colors.enumerated().map { index, color in
            UIGraphicsImageRenderer(size: CGSize(width: 1080, height: 1920)).image { ctx in
                color.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 1080, height: 1920))
                let text = "\(index + 1)" as NSString
                text.draw(at: CGPoint(x: 420, y: 760), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 360, weight: .heavy), .foregroundColor: UIColor.white
                ])
            }
        }
        buildVideoFromPhotos(images, photoDuration: 2) { result in
            DispatchQueue.main.async {
                guard case .success(let url) = result else { failed = true; return }
                removeAllLocalMomentFiles(momentId: Self.momentId, photoCount: 0)
                saveLocalMomentVideo(from: url, momentId: Self.momentId, autoBackupToPhotos: false)
                var m = Moment(durationSeconds: 6)
                m.id = Self.momentId
                m.title = "Test Clip"
                moment = m
            }
        }
    }
}
