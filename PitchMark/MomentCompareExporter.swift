//
//  MomentCompareExporter.swift
//  PitchMark
//
//  Saving a Compare (2026-11-15) as one video: both clips, each framed the
//  way the coach zoomed and dragged it, stacked or side by side, locked at
//  their sync points, from the chosen start to end, at the chosen speed.
//  A custom compositor (same shape as MomentFilterCompositor) draws each
//  frame with Core Image, so the framing math is one function shared by
//  the preview and the file (`ComparePaneMath`).
//

import Foundation
import AVFoundation
import CoreImage

/// How one clip sits in its pane: zoom about the pane's center, then a
/// shift as a fraction of the pane (y down, as on screen).
struct ComparePaneFraming: Equatable {
    var zoom: Double = 1
    var offset: CGSize = .zero

    static let zoomRange: ClosedRange<Double> = 1...5
}

enum CompareLayout: Equatable {
    case stacked
    case sideBySide

    /// The saved video's size.
    var renderSize: CGSize {
        self == .stacked ? CGSize(width: 1080, height: 1920) : CGSize(width: 1920, height: 1080)
    }

    var paneSize: CGSize {
        self == .stacked ? CGSize(width: 1080, height: 960) : CGSize(width: 960, height: 1080)
    }

    /// Width / height of a pane - the preview uses it so it matches.
    var paneAspect: CGFloat { paneSize.width / paneSize.height }

    /// Pane origins in Core Image space (y up): A on top or left.
    func paneOrigin(isA: Bool) -> CGPoint {
        switch self {
        case .stacked: return CGPoint(x: 0, y: isA ? paneSize.height : 0)
        case .sideBySide: return CGPoint(x: isA ? 0 : paneSize.width, y: 0)
        }
    }
}

/// A video track's `preferredTransform` as an image orientation. Applying
/// the transform itself in Core Image (y up) turns a portrait clip the
/// wrong way - it saved upside down (2026-11-15) - so frames are uprighted
/// with `CIImage.oriented` instead.
enum CompareOrientation {
    static func orientation(for t: CGAffineTransform) -> CGImagePropertyOrientation {
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.01 }
        switch (t.a, t.b, t.c, t.d) {
        case let (a, b, c, d) where near(a, 0) && near(b, 1) && near(c, -1) && near(d, 0): return .right
        case let (a, b, c, d) where near(a, 0) && near(b, -1) && near(c, 1) && near(d, 0): return .left
        case let (a, b, c, d) where near(a, -1) && near(b, 0) && near(c, 0) && near(d, -1): return .down
        case let (a, b, c, d) where near(a, -1) && near(b, 0) && near(c, 0) && near(d, 1): return .upMirrored
        case let (a, b, c, d) where near(a, 1) && near(b, 0) && near(c, 0) && near(d, -1): return .downMirrored
        case let (a, b, c, d) where near(a, 0) && near(b, 1) && near(c, 1) && near(d, 0): return .leftMirrored
        case let (a, b, c, d) where near(a, 0) && near(b, -1) && near(c, -1) && near(d, 0): return .rightMirrored
        default: return .up
        }
    }
}

enum ComparePaneMath {
    /// Where an upright image of `imageSize` lands inside a pane, in the
    /// pane's own y-up space: fitted whole, zoomed about the center, then
    /// shifted - the same as the on-screen preview.
    static func placement(imageSize: CGSize, pane: CGSize, framing: ComparePaneFraming) -> CGAffineTransform {
        guard imageSize.width > 0, imageSize.height > 0 else { return .identity }
        let fit = min(pane.width / imageSize.width, pane.height / imageSize.height)
        let scale = fit * CGFloat(framing.zoom)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let x = (pane.width - drawn.width) / 2 + framing.offset.width * pane.width
        // Down on screen is down in y-up space too: subtract.
        let y = (pane.height - drawn.height) / 2 - framing.offset.height * pane.height
        return CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: x, y: y))
    }
}

final class CompareInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    var timeRange: CMTimeRange
    var enablePostProcessing = false
    var containsTweening = true
    var requiredSourceTrackIDs: [NSValue]?
    var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let trackA: CMPersistentTrackID
    let trackB: CMPersistentTrackID
    let transformA: CGAffineTransform
    let transformB: CGAffineTransform
    let framingA: ComparePaneFraming
    let framingB: ComparePaneFraming
    let layout: CompareLayout

    init(timeRange: CMTimeRange, trackA: CMPersistentTrackID, trackB: CMPersistentTrackID,
         transformA: CGAffineTransform, transformB: CGAffineTransform,
         framingA: ComparePaneFraming, framingB: ComparePaneFraming, layout: CompareLayout) {
        self.timeRange = timeRange
        self.trackA = trackA
        self.trackB = trackB
        self.transformA = transformA
        self.transformB = transformB
        self.framingA = framingA
        self.framingB = framingB
        self.layout = layout
        self.requiredSourceTrackIDs = [NSNumber(value: trackA), NSNumber(value: trackB)]
        super.init()
    }
}

final class CompareCompositor: NSObject, AVVideoCompositing {
    var sourcePixelBufferAttributes: [String: Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)
    ]
    var requiredPixelBufferAttributesForRenderContext: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)
    ]

    private let ciContext = CIContext()

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    func cancelAllPendingVideoCompositionRequests() {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? CompareInstruction,
              let output = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "Compare", code: -1))
            return
        }
        let renderRect = CGRect(origin: .zero, size: request.renderContext.size)
        var image = CIImage(color: .black).cropped(to: renderRect)
        for isA in [true, false] {
            let trackID = isA ? instruction.trackA : instruction.trackB
            // A clip that's shorter at either end shows black there.
            guard let buffer = request.sourceFrame(byTrackID: trackID) else { continue }
            var frame = CIImage(cvPixelBuffer: buffer)
                .oriented(CompareOrientation.orientation(for: isA ? instruction.transformA : instruction.transformB))
            frame = frame.transformed(by: CGAffineTransform(translationX: -frame.extent.minX, y: -frame.extent.minY))
            let pane = instruction.layout.paneSize
            let origin = instruction.layout.paneOrigin(isA: isA)
            let placed = frame
                .transformed(by: ComparePaneMath.placement(imageSize: frame.extent.size, pane: pane,
                                                           framing: isA ? instruction.framingA : instruction.framingB))
                .transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
                .cropped(to: CGRect(origin: origin, size: pane))
            image = placed.composited(over: image)
        }
        ciContext.render(image, to: output, bounds: renderRect, colorSpace: CGColorSpaceCreateDeviceRGB())
        request.finish(withComposedVideoFrame: output)
    }
}

enum MomentCompareExporter {
    struct Settings {
        var timeline: CompareTimeline
        var framingA: ComparePaneFraming
        var framingB: ComparePaneFraming
        var layout: CompareLayout
        /// 1 = real time; 0.5 saves it at half speed.
        var rate: Double
        /// Clip A's sound - only at real time.
        var includeSound: Bool
    }

    static func export(urlA: URL, urlB: URL, settings: Settings, completion: @escaping (Result<URL, Error>) -> Void) {
        Task {
            do {
                let url = try await exportAsync(urlA: urlA, urlB: urlB, settings: settings)
                await MainActor.run { completion(.success(url)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    private static func exportAsync(urlA: URL, urlB: URL, settings: Settings) async throws -> URL {
        let assetA = AVURLAsset(url: urlA)
        let assetB = AVURLAsset(url: urlB)
        guard let videoA = try await assetA.loadTracks(withMediaType: .video).first,
              let videoB = try await assetB.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "Compare", code: -2, userInfo: [NSLocalizedDescriptionKey: "A clip has no video."])
        }
        let range = settings.timeline.playRange
        let length = range.upperBound - range.lowerBound
        guard length > 0.05 else {
            throw NSError(domain: "Compare", code: -3, userInfo: [NSLocalizedDescriptionKey: "Pick a longer stretch to save."])
        }
        let startA = settings.timeline.times(at: range.lowerBound).a
        let startB = settings.timeline.times(at: range.lowerBound).b
        func cm(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

        let composition = AVMutableComposition()
        guard let trackA = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let trackB = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "Compare", code: -4)
        }
        // Each clip's own length caps its range - the other may run on
        // past it (shown black) only at the very ends.
        let durA = try await assetA.load(.duration).seconds
        let durB = try await assetB.load(.duration).seconds
        try trackA.insertTimeRange(CMTimeRange(start: cm(startA), duration: cm(min(length, durA - startA))), of: videoA, at: .zero)
        try trackB.insertTimeRange(CMTimeRange(start: cm(startB), duration: cm(min(length, durB - startB))), of: videoB, at: .zero)
        let transformA = try await videoA.load(.preferredTransform)
        let transformB = try await videoB.load(.preferredTransform)
        trackA.preferredTransform = transformA

        let realTime = abs(settings.rate - 1) < 0.001
        if settings.includeSound, realTime, let audioA = try await assetA.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try audioTrack.insertTimeRange(CMTimeRange(start: cm(startA), duration: cm(min(length, durA - startA))), of: audioA, at: .zero)
        }
        if !realTime, settings.rate > 0 {
            composition.scaleTimeRange(CMTimeRange(start: .zero, duration: composition.duration),
                                       toDuration: cm(composition.duration.seconds / settings.rate))
        }

        let instruction = CompareInstruction(
            timeRange: CMTimeRange(start: .zero, duration: composition.duration),
            trackA: trackA.trackID, trackB: trackB.trackID,
            transformA: transformA, transformB: transformB,
            framingA: settings.framingA, framingB: settings.framingB,
            layout: settings.layout
        )
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = settings.layout.renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]
        videoComposition.customVideoCompositorClass = CompareCompositor.self

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "Compare", code: -5)
        }
        session.outputURL = outputURL
        session.outputFileType = .mov
        session.videoComposition = videoComposition
        await session.export()
        guard session.status == .completed else {
            throw session.error ?? NSError(domain: "Compare", code: -6, userInfo: [NSLocalizedDescriptionKey: "Couldn't save the video."])
        }
        return outputURL
    }
}
