//
//  MomentFilterCompositor.swift
//  PitchMark
//
//  The genuinely new piece Color Filters needed: a custom
//  AVVideoCompositing class that runs CIColorControls on each decoded
//  frame via CoreImage, since CIFilters don't bake into
//  AVVideoCompositionCoreAnimationTool (every other exporter in this
//  feature's pipeline) - see MomentFilter.swift's header comment.
//
//  Real correctness point specific to a CUSTOM compositor, one level
//  deeper than the ordinary "AVMutableCompositionTrack doesn't inherit
//  preferredTransform" lesson this codebase already learned the hard way
//  (see [[feedback-compositiontrack-preferredtransform]]): every OTHER
//  exporter hands AVFoundation a `layerInstruction.setTransform`, and the
//  standard CALayer-based rendering path applies that rotation for you.
//  A custom compositor's `sourceFrame(byTrackID:)` hands back the RAW
//  decoded pixel buffer in the track's native (pre-rotation) orientation
//  instead - nothing rotates it automatically, so this file has to apply
//  `preferredTransform` itself, via `CIImage.transformed(by:)`, or a
//  portrait-recorded clip comes out sideways in the filtered output even
//  though `MomentFilterExporter.swift` set the composition track's
//  `preferredTransform` correctly (that line matters for anything that
//  reads presentation metadata, e.g. a still frame extractor, but not for
//  what a custom compositor's raw pixel buffer access sees).
//
//  Unverifiable in this sandbox (no CoreImage/GPU rendering, no video
//  decoding) - flagged explicitly rather than claimed working from code
//  review. Needs an on-device check, ideally in isolation (one preset,
//  one short clip, confirm the exported file visibly differs from the
//  source) before relying on this for real editing, per the plan's
//  go/no-go checkpoint for this specific feature.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation
import AVFoundation
import CoreImage

/// Carries the one color-controls instruction (there's only ever one -
/// Filter has no per-time-range variation, unlike Zoom/Overlay) plus
/// which composition track to read from and which CIColorControls
/// parameters to apply. `AVMutableVideoCompositionInstruction` (the
/// built-in type every other exporter in this feature uses) has no slot
/// for either, hence this small custom type.
final class MomentFilterInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    var timeRange: CMTimeRange
    var enablePostProcessing: Bool = false
    var containsTweening: Bool = false
    var requiredSourceTrackIDs: [NSValue]?
    var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let sourceTrackID: CMPersistentTrackID
    let adjustment: FilterAdjustment
    /// Baked in once here rather than re-read from the track inside the
    /// compositor - `startRequest` has no convenient access to the
    /// original `AVAssetTrack` (only composition track IDs), and this
    /// value never changes across the single instruction's whole span.
    let transform: CGAffineTransform

    init(timeRange: CMTimeRange, sourceTrackID: CMPersistentTrackID, adjustment: FilterAdjustment, transform: CGAffineTransform) {
        self.timeRange = timeRange
        self.sourceTrackID = sourceTrackID
        self.adjustment = adjustment
        self.transform = transform
        self.requiredSourceTrackIDs = [NSNumber(value: sourceTrackID)]
        super.init()
    }
}

enum MomentFilterCompositorError: Error {
    case missingInstruction
    case missingSourceFrame
    case filterFailed
    case missingOutputBuffer
}

final class MomentFilterCompositor: NSObject, AVVideoCompositing {
    var sourcePixelBufferAttributes: [String: Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)
    ]
    var requiredPixelBufferAttributesForRenderContext: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)
    ]

    /// One shared context, not one per request - CIContext is
    /// documented as expensive to create and safe/intended to be reused
    /// across many renders.
    private let ciContext = CIContext()

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func cancelAllPendingVideoCompositionRequests() {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? MomentFilterInstruction else {
            request.finish(with: MomentFilterCompositorError.missingInstruction)
            return
        }
        guard let sourceBuffer = request.sourceFrame(byTrackID: instruction.sourceTrackID) else {
            request.finish(with: MomentFilterCompositorError.missingSourceFrame)
            return
        }

        let renderSize = request.renderContext.size
        // `transformed(by:)` rotates/translates the raw decoded frame
        // into display orientation - see this file's header comment for
        // why that's this file's own job, not something inherited free.
        let rotated = CIImage(cvPixelBuffer: sourceBuffer).transformed(by: instruction.transform)

        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(rotated, forKey: kCIInputImageKey)
        filter?.setValue(instruction.adjustment.brightness, forKey: kCIInputBrightnessKey)
        filter?.setValue(instruction.adjustment.contrast, forKey: kCIInputContrastKey)
        filter?.setValue(instruction.adjustment.saturation, forKey: kCIInputSaturationKey)
        guard let outputImage = filter?.outputImage else {
            request.finish(with: MomentFilterCompositorError.filterFailed)
            return
        }

        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: MomentFilterCompositorError.missingOutputBuffer)
            return
        }

        // Explicit bounds, not the image's own (possibly larger/offset
        // after the rotation transform) extent - `outputBuffer` is
        // exactly `renderSize`, and rendering past that would either
        // clip incorrectly or leave undefined pixels at the edges.
        ciContext.render(outputImage, to: outputBuffer, bounds: CGRect(origin: .zero, size: renderSize), colorSpace: CGColorSpaceCreateDeviceRGB())
        request.finish(withComposedVideoFrame: outputBuffer)
    }
}
