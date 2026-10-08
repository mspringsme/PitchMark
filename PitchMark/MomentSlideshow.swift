//
//  MomentSlideshow.swift
//  PitchMark
//
//  2026-09-30: combine a Moment's attached photos together with its video
//  into one export - a user-arranged sequence of segments (each either
//  "show this photo for N seconds" or "play the video"), exported as a
//  single file via MomentSlideshowExporter.swift. Pure data model only;
//  no UI, no AVFoundation dependency, so this stays standalone-verifiable
//  the same way every other timing-sensitive model in this feature set is.
//
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this.
//

import Foundation

enum SlideshowSegmentKind: String, Codable {
    case photo
    case video
}

/// One entry in the user-arranged sequence. There's always exactly one
/// `.video` segment (the Moment's whole video, in its current edited
/// state - Trim/Speed/Zoom/Overlay/Audio have already baked into it by
/// the time this runs) and zero or more `.photo` segments, one per
/// attached photo. The array's own order *is* the export order - this
/// struct carries no separate position field, so reordering is just
/// reordering the array (`MomentSlideshowEditorView`'s `.onMove`).
struct SlideshowSegment: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: SlideshowSegmentKind
    /// Set only for `.photo` segments - which of the Moment's attached
    /// photos (`localMomentPhotoURL(momentId:index:)`) this segment
    /// shows. Always nil for `.video`.
    var photoIndex: Int?
    /// Set only for `.photo` segments - how long to display it, in
    /// seconds. `.video` segments use the video's own full duration,
    /// which isn't a value this type stores (it isn't known until the
    /// video asset is actually loaded).
    var photoDuration: Double?

    init(id: UUID = UUID(), kind: SlideshowSegmentKind, photoIndex: Int? = nil, photoDuration: Double? = nil) {
        self.id = id
        self.kind = kind
        self.photoIndex = photoIndex
        self.photoDuration = photoDuration
    }
}

/// Default/floor/ceiling for a photo segment's display duration - the
/// editor's per-photo slider range, and the fallback whenever a photo
/// segment's own `photoDuration` is somehow nil.
let defaultSlideshowPhotoDuration: Double = 2.5
let minSlideshowPhotoDuration: Double = 0.5
let maxSlideshowPhotoDuration: Double = 10.0

/// The starting arrangement the first time a Moment's slideshow editor
/// opens with nothing saved yet: every attached photo, in index order,
/// followed by the one video block - "photos first, then video," a
/// sensible default the user is then free to rearrange via `.onMove`.
func defaultSlideshowSegments(photoCount: Int) -> [SlideshowSegment] {
    var segments = (0..<max(photoCount, 0)).map { SlideshowSegment(kind: .photo, photoIndex: $0, photoDuration: defaultSlideshowPhotoDuration) }
    segments.append(SlideshowSegment(kind: .video))
    return segments
}

/// Reconciles a previously-saved segment list against the Moment's
/// *current* photo count: ensures exactly one `.video` segment exists,
/// and drops any segment referencing a photo index that no longer
/// exists. Photos in this app are append-only (no delete), so the latter
/// is defensive rather than expected in practice.
///
/// Deliberately does NOT auto-append a segment for every photo not
/// currently referenced - the first version of this function did, which
/// meant a photo the user explicitly removed from the arrangement
/// (`MomentSlideshowEditorView`'s edit-mode delete) silently reappeared
/// the next time this function ran. Once a list has been saved, absence
/// of a photo index is the user's own choice, not "not yet seen." A
/// photo added to the Moment after the slideshow was last configured (or
/// one the user removed) simply isn't in `segments` - `MomentSlideshowEditorView`
/// surfaces every such photo in its own "Available Photos" strip so the
/// user can add it back deliberately, rather than it being silently
/// reinserted on their behalf. Pure, verified standalone the same way as
/// every other function here.
func reconciledSlideshowSegments(_ saved: [SlideshowSegment], photoCount: Int) -> [SlideshowSegment] {
    var segments = saved.filter { segment in
        guard segment.kind == .photo else { return true }
        guard let index = segment.photoIndex else { return false }
        return index >= 0 && index < photoCount
    }

    if !segments.contains(where: { $0.kind == .video }) {
        segments.append(SlideshowSegment(kind: .video))
    }

    return segments
}

/// Fixed crossfade length between adjacent segments when transitions are
/// on - same "fixed quick default, not a per-transition slider" shape
/// `momentFadeDuration`/`freezeZoomQuickOutDuration` already settled on
/// elsewhere in this feature set.
let defaultSlideshowTransitionDuration: Double = 0.5

/// One segment's timing, with transitions folded in - the pure math
/// `MomentSlideshowExporter.swift` builds its actual composition from.
/// `nominalDuration` is the segment's own full configured length (a
/// photo's `photoDuration`, or the video's real duration) - unaffected
/// by transitions. `leadingTransitionDuration`/`trailingTransitionDuration`
/// are the (clamped) crossfade lengths shared with the previous/next
/// segment - 0 on whichever side has no neighbor, or when transitions
/// are off.
///
/// Only a segment's TRAILING edge ever shortens what actually gets
/// inserted onto the shared composition track (see
/// MomentSlideshowExporter.swift's header comment for why only the
/// trailing side needs to, and why video is never shortened at all) -
/// this struct just reports the lengths; the exporter decides what to do
/// with them.
struct PositionedSlideshowSegment: Equatable {
    let segment: SlideshowSegment
    let nominalDuration: Double
    let leadingTransitionDuration: Double
    let trailingTransitionDuration: Double
}

/// Computes each segment's nominal duration plus the (clamped) crossfade
/// shared with each neighbor. Pure, no AVFoundation dependency -
/// standalone-verifiable the same way as every other timing function in
/// this feature set.
///
/// Each shared transition is clamped to at most half of EACH of the two
/// segments it sits between, so a transition can never make one segment
/// "disappear" or invert the ordering of a run of very short photos -
/// same clamp-to-avoid-collision shape `MomentFreezeExporter.swift`'s
/// zoom-out and `MomentFadeExporter.swift`'s fadeIn/fadeOut already use
/// for an analogous reason.
func positionedSlideshowSegments(
    _ segments: [SlideshowSegment],
    videoDuration: Double,
    transitionDuration: Double = defaultSlideshowTransitionDuration,
    transitionsEnabled: Bool
) -> [PositionedSlideshowSegment] {
    func nominalDuration(_ segment: SlideshowSegment) -> Double {
        segment.kind == .video
            ? max(videoDuration, 0.01)
            : max(segment.photoDuration ?? defaultSlideshowPhotoDuration, 0.01)
    }

    let durations = segments.map(nominalDuration)

    guard transitionsEnabled, segments.count > 1, transitionDuration > 0 else {
        return segments.indices.map { index in
            PositionedSlideshowSegment(segment: segments[index], nominalDuration: durations[index], leadingTransitionDuration: 0, trailingTransitionDuration: 0)
        }
    }

    // sharedTransition[i] is the crossfade between segment i and i+1.
    let sharedTransition: [Double] = (0..<(segments.count - 1)).map { i in
        min(transitionDuration, durations[i] / 2, durations[i + 1] / 2)
    }

    return segments.indices.map { index in
        PositionedSlideshowSegment(
            segment: segments[index],
            nominalDuration: durations[index],
            leadingTransitionDuration: index > 0 ? sharedTransition[index - 1] : 0,
            trailingTransitionDuration: index < sharedTransition.count ? sharedTransition[index] : 0
        )
    }
}

/// The opacity keyframes for one photo segment's sprite, as fractions
/// (0...1) of its own ANIMATION window - which starts
/// `leadingTransitionDuration` seconds before the segment's own track
/// insertion (still legitimately showing the previous segment's content,
/// which a crossfade-in plays over) and ends exactly at
/// `nominalDuration` past the segment's own track-insertion start (into
/// where the next segment's content has already begun, which a
/// crossfade-out reveals). Values are plain opacity (0...1); the caller
/// scales `keyTimes` by the window's own total length
/// (`nominalDuration + leadingTransitionDuration`) and positions
/// `beginTime` at `segmentStart - leadingTransitionDuration`.
///
/// With both transitions 0 (today's default/disabled case), this
/// collapses to exactly `times: [0, 1], values: [1, 1]` - the original
/// discrete "stay visible" animation, confirming no behavior change when
/// transitions are off.
func slideshowSpriteOpacityKeyframes(
    leadingTransitionDuration: Double,
    nominalDuration: Double,
    trailingTransitionDuration: Double
) -> (times: [Double], values: [Double]) {
    let totalWindow = max(nominalDuration + leadingTransitionDuration, 0.01)
    var times: [Double] = [0]
    var values: [Double] = [leadingTransitionDuration > 0 ? 0 : 1]

    if leadingTransitionDuration > 0 {
        times.append(leadingTransitionDuration / totalWindow)
        values.append(1)
    }

    let steadyEnd = leadingTransitionDuration + (nominalDuration - trailingTransitionDuration)
    let steadyEndFraction = steadyEnd / totalWindow
    if trailingTransitionDuration > 0, steadyEndFraction > times[times.count - 1] {
        times.append(steadyEndFraction)
        values.append(1)
    }

    times.append(1)
    values.append(trailingTransitionDuration > 0 ? 0 : 1)

    return (times, values)
}
