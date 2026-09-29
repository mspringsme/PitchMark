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
//  2026-09-30: `params.radius` used to be a UI-authored value in points,
//  requiring a caller-supplied `referenceSize` to convert into the
//  source image's own pixel space before blurring, plus two separate
//  caps (one on the point value, one on the converted pixel value) to
//  stay sane across a huge range of source image sizes. Both the
//  points-vs-pixels conversion and the two-cap scheme were each the
//  root of a real, separately-reported silent-export-failure bug. Now
//  that glow has no user-adjustable radius (GlowSettings.swift), the
//  radius is defined directly as a fraction of the source image's own
//  pixel size - there is no other unit to convert to or from, and
//  nothing external to fall out of sync with.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

struct GlowRenderParams {
    var intensity: Double        // 0...1
    var radiusFraction: Double   // 0...1 - fraction of the source's own longest pixel dimension
}

/// `image` may be rendered at a *smaller* pixel resolution than
/// `sourceImage` (see `maxWorkingDimension`) - `sizeRatio` is the
/// intended display size relative to the source's own extent (padded
/// canvas / source canvas, e.g. ~1.3), computed directly from the
/// padding math rather than by comparing `image`'s actual pixel
/// dimensions against the source's - those two are no longer
/// comparable 1:1 once the output resolution is capped independently
/// of the source's size. Callers size the glow layer/view as
/// `mainOverlaySize * sizeRatio`, then let normal CALayer/SwiftUI image
/// scaling stretch the (possibly lower-res) `image` to fit - free for a
/// glow, since it's inherently soft.
struct GlowRenderResult {
    var image: CGImage
    var sizeRatio: CGFloat
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
    /// this every frame of a shimmering overlay, and constructing a
    /// CIContext (compiling the Metal/GPU pipeline) is too expensive to
    /// repeat that often. Unlike AssetCreationFlow.swift's Smart Cutout,
    /// which creates a `CIContext()` fresh per one-off call - fine for
    /// something that runs once per photo import, wrong for something
    /// that can run several times a second.
    static let sharedContext = CIContext(options: [.workingColorSpace: colorSpace])

    /// The one glow color every enabled overlay gets, now that color is
    /// no longer a per-overlay setting - a warm gold-white reads as an
    /// actual "glow"/sparkle rather than a plain soft-focus highlight a
    /// neutral white can look like against bright footage.
    static let color = CIColor(red: 1.0, green: 0.92, blue: 0.62, alpha: 1)

    /// Long-side cap for the resolution this actually renders at,
    /// independent of the source image's real pixel size or the video's
    /// resolution - glows are inherently soft, so rendering at a capped
    /// working resolution and scaling the result back up costs nothing
    /// visually and a lot less on a 4K frame.
    static let maxWorkingDimension: CGFloat = 512

    /// Renders a standalone glow "halo" image for `sourceImage` (an
    /// overlay's own asset image) at `params`. `params.radiusFraction`
    /// is relative to `sourceImage`'s own longest pixel dimension, so no
    /// external size/unit is needed to make sense of it - the caller's
    /// own `.scaleEffect` (applied to both the glow and the main overlay
    /// image identically) then scales the already-correct-looking glow
    /// right along with the overlay, so a scaled-up overlay gets a
    /// proportionally scaled-up glow for free.
    ///
    /// Returns nil when there's nothing to render (zero radius/intensity
    /// after clamping, or a degenerate source) - callers should skip
    /// adding a glow layer entirely rather than composite a no-op result.
    ///
    /// Pipeline: mask a solid `color` fill by the source's own alpha (a
    /// tinted silhouette matching its shape) -> blur it with two stacked
    /// CIGaussianBlur passes at different radii, screen-blended together
    /// for a softer inner+outer falloff than one blur -> scale by
    /// intensity (a CIColorMatrix multiplying every premultiplied
    /// channel uniformly, the correct premultiplied way to reduce
    /// opacity) -> add a very low-amplitude, glow-shape-masked noise
    /// layer to break up 8-bit banding after re-compression -> expand
    /// the extent by the blur radius so nothing clips -> render through
    /// `sharedContext` to a plain 8-bit CGImage (every filter above
    /// still runs at full internal Core Image precision regardless of
    /// this final output format - see the format-choice comment at the
    /// bottom of this function for why it isn't half-float).
    static func render(sourceImage: CGImage, params: GlowRenderParams) -> GlowRenderResult? {
        let intensity = min(max(params.intensity, 0), 1)
        guard intensity > 0 else { return nil }

        var sourceCI = CIImage(cgImage: sourceImage)
        let sourceExtent = sourceCI.extent
        guard sourceExtent.width > 0, sourceExtent.height > 0 else { return nil }

        let sourcePixelSize = max(sourceExtent.width, sourceExtent.height)
        let radius = min(max(params.radiusFraction, 0), 1) * sourcePixelSize
        guard radius > 0 else { return nil }

        let longSide = sourcePixelSize
        let workingScale = longSide > maxWorkingDimension ? maxWorkingDimension / longSide : 1
        if workingScale < 1 {
            sourceCI = sourceCI.transformed(by: CGAffineTransform(scaleX: workingScale, y: workingScale))
        }
        let workingExtent = sourceCI.extent
        let workingRadius = radius * workingScale

        let colorFill = CIImage(color: color).cropped(to: workingExtent)
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
        let finalImage = glow.cropped(to: expandedExtent)

        // Deliberately NOT scaled back up to the source's own
        // resolution here (this function used to do that, via
        // `finalImage.transformed(by: 1/workingScale)`) - `sizeRatio`
        // below already tells callers the *intended* display size, and
        // a CALayer/SwiftUI Image scales lower-res `contents` up to fit
        // for free, invisibly for something this soft. Scaling back up
        // only mattered for a naive caller that inferred display size
        // by comparing `image.width` against the source's own width -
        // both callers now use `sizeRatio` instead (see its doc comment).
        //
        // This matters far more than it looks: a *static* glow is one
        // image, so the old upscale only cost one large allocation. A
        // *pulsing* glow (every enabled glow, now that it's always
        // animated - GlowSettings.swift) needs export to hold dozens of
        // full-resolution samples simultaneously in one
        // CAKeyframeAnimation.values array for its whole duration - for
        // a large Smart Cutout or shape-cropped photo (up to 1024px per
        // the asset spec), that upscale made each sample ~1.3x1024px,
        // multiplied by ~8-30 samples/second for however many seconds
        // the overlay spans - hundreds of megabytes held at once by
        // AVVideoCompositionCoreAnimationTool's offline compositor,
        // which the live preview never does (it renders and discards
        // one glow image at a time as the playhead moves). Bundled
        // placeholder assets are tiny, so they never approached this and
        // always "worked"; a real user-created asset's export silently
        // dropped the glow entirely - the same silent-nil failure shape
        // as this feature's two previous bugs, just triggered by array
        // memory pressure instead of a single oversized allocation or an
        // unsupported pixel format. Reported by the user as glow still
        // not baking in "on user created assets" after both those fixes
        // already shipped. Capping the *output* resolution the same way
        // `maxWorkingDimension` already caps the *blur computation*
        // keeps every sample small regardless of source size.

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
        guard let outputImage = sharedContext.createCGImage(
            finalImage,
            from: finalImage.extent,
            format: .RGBA8,
            colorSpace: colorSpace
        ) else { return nil }

        // Scale-invariant by construction - `workingExtent`/`expandInset`
        // are both already in the same (possibly downscaled) working
        // space, so their ratio equals what it would be at full source
        // resolution too. Computed from geometry, never from comparing
        // `outputImage`'s actual pixel size against the source's own -
        // see this function's "Deliberately NOT scaled back up" comment
        // above for why those two are no longer interchangeable.
        let sizeRatio = expandedExtent.width / max(workingExtent.width, 1)
        return GlowRenderResult(image: outputImage, sizeRatio: sizeRatio)
    }
}
