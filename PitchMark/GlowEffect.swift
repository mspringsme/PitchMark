//
//  GlowEffect.swift
//  PitchMark
//
//  2026-09-29: the Core Image rendering behind the overlay Glow modifier
//  (GlowSettings.swift). One function, called identically by the live
//  preview (OverlayEditorView) and the export compositor
//  (OverlayExporter.swift), so the two produce the same pixels - the
//  same discipline this codebase already applies to every shared
//  interpolation/timing function (OverlayItem.transform(at:),
//  speedRanges, volumeAt, etc.), just for a pixel effect instead of
//  numeric math this time.
//
//  Deliberately does NOT unify the underlying video-rendering
//  technology (SwiftUI/AVPlayerLayer for preview, Core Animation for
//  export - see the approved plan for why that's unnecessary here): the
//  glow only ever needs the overlay's own alpha channel, never the
//  video frame, so it's rendered once as a standalone image and each
//  renderer composites it using whatever blend-mode feature it already
//  has - SwiftUI's `.blendMode(.screen)` for preview,
//  `CALayer.compositingFilter` for export.
//
//  Stays in Core Image's native premultiplied-alpha convention
//  throughout - every filter below operates on premultiplied RGBA and
//  nothing here ever unpremultiplies - so scaling the whole image by a
//  scalar (the intensity step) is a correct opacity reduction with no
//  dark fringing, and the two composite technologies above (both of
//  which also expect premultiplied CGImages, the same convention the
//  existing plain overlay images already use as `layer.contents`) get
//  exactly the input they expect.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

struct GlowRenderParams {
    var color: CIColor
    var intensity: Double   // 0...1
    var radius: Double      // points
}

enum GlowEffect {
    /// A concrete (non-Optional) sRGB space, reused for both the shared
    /// context's working space and every `createCGImage` output below -
    /// one source of truth rather than boxing an `Optional<CGColorSpace>`
    /// into `Any` for the context's options dictionary (which risks the
    /// options lookup silently not finding what it expects) and letting
    /// `createCGImage` calls each re-derive it separately. `CGColorSpace(name:)`
    /// returning nil for sRGB is not realistically reachable, but the
    /// guard keeps this a real `CGColorSpace`, never an implicit force-unwrap.
    static let colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// Created once, reused for every glow render - preview can call
    /// this every frame of a pulsing overlay, and constructing a
    /// CIContext (compiling the Metal/GPU pipeline) is too expensive to
    /// repeat that often. Unlike AssetCreationFlow.swift's Smart Cutout,
    /// which creates a `CIContext()` fresh per one-off call - fine for
    /// something that runs once per photo import, wrong for something
    /// that can run 30 times a second.
    static let sharedContext = CIContext(options: [.workingColorSpace: colorSpace])

    /// Hard cap independent of the UI slider or whatever a pulse might
    /// scale a radius up to - keeps a large/pulsed radius from ever
    /// triggering a pathologically expensive blur. In UI points, applied
    /// before the point-to-pixel conversion below.
    static let maxRadius: Double = 60

    /// A second cap, applied *after* converting to the source image's
    /// own pixel space - see the comment at that conversion for why
    /// `maxRadius` alone isn't enough. In source pixels.
    static let maxPixelRadius: Double = 120

    /// Long-side cap for the resolution this actually renders at,
    /// independent of the source image's real pixel size or the video's
    /// resolution - glows are inherently soft, so rendering at a capped
    /// working resolution and scaling the result back up costs nothing
    /// visually and a lot less on a 4K frame.
    static let maxWorkingDimension: CGFloat = 512

    /// Renders a standalone glow "halo" image for `sourceImage` (an
    /// overlay's own asset image) at `params`. `referenceSize` is the
    /// point size the overlay is actually rendered at (`baseSize` in
    /// `OverlayEditorView`, `overlayBaseSize` in `OverlayExporter`) *at
    /// its own scale = 1* - `params.radius` is defined in those same UI
    /// points (what the Glow slider shows), not in the source asset's
    /// own raw pixel dimensions, which can be arbitrary (a 2000x2000
    /// bundled PNG shown at 60pt would make a "12pt" radius invisible if
    /// blurred directly in source-pixel space). This converts the
    /// point-based radius into the source image's own pixel space before
    /// any blur runs; the caller's own `.scaleEffect` (applied to both
    /// the glow and the main overlay image identically) then scales the
    /// already-correct-looking glow right along with the overlay, so a
    /// scaled-up overlay gets a proportionally scaled-up glow for free.
    ///
    /// Returns nil when there's nothing to render (zero radius/intensity
    /// after capping, or a degenerate source) - callers should skip
    /// adding a glow layer entirely rather than composite a no-op result.
    ///
    /// Pipeline: mask a solid `params.color` fill by the source's own
    /// alpha (a tinted silhouette matching its shape) -> blur it with
    /// two stacked CIGaussianBlur passes at different radii, screen-
    /// blended together for a softer inner+outer falloff than one blur
    /// - -> scale by intensity (a CIColorMatrix multiplying every
    /// premultiplied channel uniformly, the correct premultiplied way to
    /// reduce opacity) -> add a very low-amplitude, glow-shape-masked
    /// noise layer to break up 8-bit banding after re-compression ->
    /// expand the extent by the blur radius so nothing clips -> render
    /// through `sharedContext` to a plain 8-bit CGImage (every filter
    /// above still runs at full internal Core Image precision regardless
    /// of this final output format - see the format-choice comment at
    /// the bottom of this function for why it isn't half-float).
    static func render(sourceImage: CGImage, params: GlowRenderParams, referenceSize: CGFloat) -> CGImage? {
        let intensity = min(max(params.intensity, 0), 1)
        guard intensity > 0 else { return nil }

        var sourceCI = CIImage(cgImage: sourceImage)
        let sourceExtent = sourceCI.extent
        guard sourceExtent.width > 0, sourceExtent.height > 0, referenceSize > 0 else { return nil }

        // Points -> this source image's own pixel space. `maxRadius`
        // bounds the *point* value, but a source image's own pixel size
        // is arbitrary - a Smart Cutout asset (per the spec, downsized
        // to as much as ~1024px) is far larger in raw pixels than a
        // small bundled shape, and `pixelsPerPoint` scales directly with
        // that. Capping only the point value before this multiplication
        // left the *pixel* radius effectively unbounded: a large cutout
        // at a typical small on-screen referenceSize could multiply an
        // already-capped 60pt radius into several hundred pixels, which
        // cascades into an enormous padded output image a few lines down
        // (`expandInset` scales with this radius, then the whole image
        // scales back up by `1/workingScale`) - expensive and slow
        // enough to plausibly fail `createCGImage` outright during an
        // export already under memory/CPU pressure from video encoding,
        // while a small bundled asset never gets close to those numbers.
        // Real bug, reported by the user as "glow doesn't bake in... on
        // cutout assets" specifically - `maxPixelRadius` bounds the
        // worst case regardless of source size or referenceSize.
        let sourcePixelSize = max(sourceExtent.width, sourceExtent.height)
        let pixelsPerPoint = sourcePixelSize / referenceSize
        let rawRadius = min(max(params.radius, 0), maxRadius) * pixelsPerPoint
        let radius = min(rawRadius, maxPixelRadius)
        guard radius > 0 else { return nil }

        let longSide = sourcePixelSize
        let workingScale = longSide > maxWorkingDimension ? maxWorkingDimension / longSide : 1
        if workingScale < 1 {
            sourceCI = sourceCI.transformed(by: CGAffineTransform(scaleX: workingScale, y: workingScale))
        }
        let workingExtent = sourceCI.extent
        let workingRadius = radius * workingScale

        let colorFill = CIImage(color: params.color).cropped(to: workingExtent)
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: workingExtent)
        let silhouette = colorFill.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: sourceCI
        ])

        let blurWide = silhouette.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: workingRadius])
        let blurTight = silhouette.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: workingRadius * 0.4])
        var glow = blurTight.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: blurWide])

        glow = glow.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(intensity), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(intensity), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(intensity), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(intensity))
        ])

        // Low-amplitude noise, masked to the glow's own shape (so it
        // never introduces visible specks outside the blurred
        // silhouette) and added on top - this only needs to survive one
        // more lossy re-encode (iMessage/Instagram/TikTok), not hold up
        // under close inspection.
        let ditherAmount: CGFloat = 0.02
        let noise = CIFilter.randomGenerator().outputImage ?? CIImage.empty()
        let scaledNoise = noise
            .cropped(to: glow.extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: ditherAmount, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: ditherAmount, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: ditherAmount, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        let maskedNoise = scaledNoise.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: glow.extent),
            kCIInputMaskImageKey: glow
        ])
        glow = maskedNoise.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: glow])

        let expandInset = workingRadius * 2.5
        let expandedExtent = workingExtent.insetBy(dx: -expandInset, dy: -expandInset)
        var finalImage = glow.cropped(to: expandedExtent)
        if workingScale < 1 {
            finalImage = finalImage.transformed(by: CGAffineTransform(scaleX: 1 / workingScale, y: 1 / workingScale))
        }

        // .RGBA8, not the half-float .RGBAh this originally used: every
        // Core Image filter above still runs at full internal precision
        // regardless of the *output* format asked for here, so this
        // doesn't lose the "stay in float while compositing" intent -
        // but the CGImage this produces gets consumed as plain
        // CALayer.contents by both SwiftUI's Image and, more
        // importantly, AVVideoCompositionCoreAnimationTool's offline
        // export compositor, and half-float CGImage content is not
        // reliably supported there. createCGImage silently returning
        // nil for that combination - not a crash, not an error, just no
        // glow layer ever added - is the likely cause of a real bug:
        // the glow rendering correctly in the live preview but never
        // appearing in an exported video ("doesn't bake in").
        return sharedContext.createCGImage(
            finalImage,
            from: finalImage.extent,
            format: .RGBA8,
            colorSpace: colorSpace
        )
    }
}
