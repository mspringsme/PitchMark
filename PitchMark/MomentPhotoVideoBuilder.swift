//
//  MomentPhotoVideoBuilder.swift
//  PitchMark
//
//  2026-10-03: lets a Moment be created from photos alone, with no
//  recorded/imported video at all - "Import from Photos" previously
//  forced a video first (`.videos`-only PhotosPicker filter), and photos
//  could only be attached afterward, inside an existing Moment.
//
//  MomentSlideshowExporter.swift already mixes photos into an export, but
//  it always loops real frames from the Moment's OWN video underneath
//  each photo's opaque sprite (see that file's header comment) - there's
//  no video to loop here, so that machinery doesn't apply. This writes a
//  genuine video file directly with AVAssetWriter instead: one real
//  frame, held for `photoDuration` seconds per photo. The result becomes
//  that Moment's ordinary backing video via the existing
//  `saveLocalMomentVideo` - every other screen (playback, export, every
//  editor's "frozen base") keeps assuming a real video file exists on
//  disk, which stays true.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import AVFoundation
import UIKit

enum PhotoVideoBuildError: Error {
    case noPhotos
    case writerSetupFailed
    case writeFailed
}

/// Renders `photos` into one video, each shown for `photoDuration`
/// seconds in the order given. Letterboxed onto a single shared canvas
/// sized to the largest photo (after orientation-normalizing all of
/// them) so no photo gets upscaled - same "pick a canvas the content
/// dictates, then letterbox everything else into it" intent as
/// `HighlightReelExporter.swift`'s `fitTransform`, just computed once at
/// write time instead of per-clip at export time, since there's no
/// composition track here to attach a layer instruction to.
func buildVideoFromPhotos(
    _ photos: [UIImage],
    photoDuration: Double = defaultSlideshowPhotoDuration,
    completion: @escaping (Result<URL, Error>) -> Void
) {
    guard !photos.isEmpty else {
        DispatchQueue.main.async { completion(.failure(PhotoVideoBuildError.noPhotos)) }
        return
    }

    DispatchQueue.global(qos: .userInitiated).async {
        let normalized = photos.map { $0.normalizedUpOrientation().resizedToFit(maxDimension: 1920) }
        let maxWidth = normalized.map { $0.size.width }.max() ?? 1080
        let maxHeight = normalized.map { $0.size.height }.max() ?? 1920
        // H.264 wants even dimensions.
        let renderSize = CGSize(
            width: (max(maxWidth, 2) / 2).rounded(.up) * 2,
            height: (max(maxHeight, 2) / 2).rounded(.up) * 2
        )

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else {
            DispatchQueue.main.async { completion(.failure(PhotoVideoBuildError.writerSetupFailed)) }
            return
        }

        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: renderSize.width,
            AVVideoHeightKey: renderSize.height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: renderSize.width,
            kCVPixelBufferHeightKey as String: renderSize.height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: pixelBufferAttributes)

        guard writer.canAdd(input) else {
            DispatchQueue.main.async { completion(.failure(PhotoVideoBuildError.writerSetupFailed)) }
            return
        }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameRate: Int32 = 30
        let frameDuration = CMTime(value: 1, timescale: frameRate)
        let framesPerPhoto = max(Int((photoDuration * Double(frameRate)).rounded()), 1)

        var frameIndex: Int64 = 0
        var writeFailed = false

        for photo in normalized {
            guard let pixelBuffer = pixelBuffer(for: photo, renderSize: renderSize, pool: adaptor.pixelBufferPool) else {
                writeFailed = true
                break
            }
            for _ in 0..<framesPerPhoto {
                while !input.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
                if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                    writeFailed = true
                    break
                }
                frameIndex += 1
            }
            if writeFailed { break }
        }

        input.markAsFinished()
        writer.finishWriting {
            DispatchQueue.main.async {
                if writeFailed || writer.status != .completed {
                    completion(.failure(writer.error ?? PhotoVideoBuildError.writeFailed))
                } else {
                    completion(.success(outputURL))
                }
            }
        }
    }
}

/// Draws `image` letterboxed (black bars, never cropped or distorted)
/// onto a freshly-allocated pixel buffer sized `renderSize` - same
/// opaque-black-backing-plus-aspect-fit letterbox convention
/// `MomentSlideshowExporter.swift`'s photo sprite uses, just drawn with
/// CoreGraphics directly instead of a CALayer, since there's no
/// AVVideoCompositionCoreAnimationTool pass happening here.
private func pixelBuffer(for image: UIImage, renderSize: CGSize, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
    var pixelBufferOut: CVPixelBuffer?
    if let pool {
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBufferOut)
    }
    guard let pixelBuffer = pixelBufferOut else { return nil }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    guard let context = CGContext(
        data: CVPixelBufferGetBaseAddress(pixelBuffer),
        width: CVPixelBufferGetWidth(pixelBuffer),
        height: CVPixelBufferGetHeight(pixelBuffer),
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo
    ) else { return nil }

    context.setFillColor(UIColor.black.cgColor)
    context.fill(CGRect(origin: .zero, size: renderSize))

    guard let cgImage = image.cgImage else { return pixelBuffer }
    let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
    guard imageSize.width > 0, imageSize.height > 0 else { return pixelBuffer }
    let scale = min(renderSize.width / imageSize.width, renderSize.height / imageSize.height)
    let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    let origin = CGPoint(x: (renderSize.width - drawSize.width) / 2, y: (renderSize.height - drawSize.height) / 2)
    context.draw(cgImage, in: CGRect(origin: origin, size: drawSize))

    return pixelBuffer
}
