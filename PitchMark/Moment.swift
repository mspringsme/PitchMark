//
//  Moment.swift
//  PitchMark
//
//  Phase 6 of the 2026-09-24 Coach/Parent/Family direction: Moments V1.
//  "Capture now, create later" - this file is deliberately minimal: a
//  Moment is just enough metadata to find a clip again later. Video files
//  stay on-device (mirrors Utilities.swift's local-portrait-storage
//  pattern exactly); only this small metadata record syncs to Firestore.
//  Deliberately kept out of the Pitchmark Display target's
//  membershipExceptions; Display has no use for this UI.
//

import Foundation
import UIKit
import AVFoundation
import Photos
import FirebaseFirestore
import FirebaseAuth

/// What a Moment was built from - see `Moment.momentKind`.
enum MomentKind: String, Codable {
    case video
    case mixedCreation
    case photoCreation
}

struct Moment: Identifiable, Codable {
    @DocumentID var id: String?
    var createdAt: Date = Date()
    var teamId: String? = nil
    var playerId: String? = nil
    var playerName: String? = nil
    var durationSeconds: Double? = nil
    /// User-set name for the clip, editable any time after recording -
    /// falls back to the player's name (then "Moment") wherever displayed
    /// when unset.
    var title: String? = nil
    // Stored as Optional deliberately, even though every write always sets
    // a real value - see the two custom-decoder attempts this replaced,
    // both wrong, in git history for why. Swift's synthesized Decodable
    // only skips a missing key without throwing for Optional-typed
    // properties; a non-optional `var photoCount: Int = 0` still throws on
    // decode when an older document has no "photoCount" field, and `try?`
    // at the call site then silently drops that whole document. Keeping
    // these Optional and relying on the plain synthesized Decodable (the
    // same mechanism @DocumentID already works correctly with elsewhere in
    // this codebase - Team.swift, TeamMembership, TeamPlayer) sidesteps
    // that without any custom init(from:) to get subtly wrong again.
    // Read via `moment.isFavorite ?? false` / `moment.photoCount ?? 0`.
    var isFavorite: Bool? = false
    var opponent: String? = nil
    var score: String? = nil
    var inning: Int? = nil
    var gameInfoUpdatedAt: Date? = nil
    var photoCount: Int? = 0
    /// Step 4 of the Asset + Overlay editor spec - Optional for the same
    /// reason every other field added after Phase 6 is: existing saved
    /// Moment documents have no "overlays" key.
    var overlays: [OverlayItem]? = nil
    /// 2026-09-28 speed ramp editor - same Optional reasoning as `overlays`.
    var speedKeyframes: [SpeedKeyframe]? = nil
    /// 2026-09-28 audio overlay editor - same Optional reasoning.
    var audioOverlays: [AudioOverlayItem]? = nil
    /// nil/1.0 = unchanged, 0 = muted. Same Optional reasoning.
    var originalAudioVolume: Double? = nil
    /// 2026-09-28 - lets the original track's volume vary over time
    /// instead of staying flat. Nil/empty means "flat `originalAudioVolume`,
    /// unchanged" - same Optional reasoning as every other field here.
    var originalVolumeKeyframes: [VolumeKeyframe]? = nil
    /// 2026-09-30 - "mute a section" regions on the original track, each
    /// with its own duck level and fade in/out. Nil/empty means "no
    /// regions" - same Optional reasoning as every other field here.
    var originalMuteRegions: [MuteRegion]? = nil
    /// 2026-09-30 - Ken Burns-style zoom/pan regions (MomentZoom.swift),
    /// same "draggable/resizable timeline range" shape as
    /// `originalMuteRegions`. Nil/empty means "no zoom" - same Optional
    /// reasoning as every other field here.
    var zoomRegions: [ZoomRegion]? = nil
    /// 2026-09-30 - combine the attached photos together with the video
    /// into one export (MomentSlideshow.swift) - the user-arranged order
    /// of photo/video segments. Nil/empty means "not configured yet," in
    /// which case the editor seeds `defaultSlideshowSegments` rather than
    /// starting from nothing - same Optional reasoning as every other
    /// field here.
    var slideshowSegments: [SlideshowSegment]? = nil
    /// Whether the slideshow's last export crossfaded between adjacent
    /// segments (MomentSlideshow.swift's positionedSlideshowSegments)
    /// rather than hard-cutting. Nil means "off," same convention as
    /// `fadeInEnabled` - plain `updateMomentFields` is enough to persist
    /// this (a flat Bool, no nested Codable wrapper needed).
    var slideshowTransitionsEnabled: Bool? = nil
    /// 2026-09-30 - whether the *last applied* fade in/out bake
    /// (MomentFadeExporter.swift) included a fade at the very start/end
    /// of the whole edited video. Nil means "off," same as false - these
    /// record what's currently baked in, not a pending unsaved choice;
    /// `MomentDetailView`'s toggles seed from these and only actually
    /// re-bake on an explicit "Apply Fade" tap, same discipline every
    /// other editor in this app uses (live local state, explicit Export).
    var fadeInEnabled: Bool? = nil
    var fadeOutEnabled: Bool? = nil
    /// Aspect-ratio crop/reframe (MomentCrop.swift) - nil means "no crop"
    /// (original framing), same convention as `fadeInEnabled`. Once the
    /// user applies any crop (even explicitly choosing "Original" again),
    /// this holds a concrete value rather than toggling back to nil -
    /// same "off is a real value, not a missing key" discipline
    /// `fadeInEnabled`/`fadeOutEnabled` already use, which sidesteps ever
    /// needing to write a literal nil through Firestore.Encoder.
    var cropSettings: CropSettings? = nil
    /// Freeze-frame / replay callout (MomentFreeze.swift) - nil means "no
    /// freeze frame," and unlike `cropSettings`/`fadeInEnabled`, removing
    /// it is a real, meaningful action (not just resetting to a concrete
    /// "off" value), so `updateMomentFreezeFrame` uses `FieldValue.delete()`
    /// rather than this codebase's usual "off is a concrete value" trick.
    var freezeFrame: FreezeFrame? = nil
    /// Color/brightness filter preset (MomentFilter.swift) - nil means
    /// "no filter," same convention as `cropSettings`. Unlike Crop,
    /// there's no `.none`/`.original` case to represent "off" as a
    /// concrete value - "don't run the filter compositor at all" is
    /// simpler and more direct, same shape `zoomRegions`/`overlays`
    /// being nil/empty already uses.
    var filterPreset: FilterPreset? = nil
    /// 2026-10-03 - what this Moment was built from: a plain recorded/
    /// imported video, a video with extra attached photos, or photos
    /// alone (built into a real video via `buildVideoFromPhotos` so every
    /// other screen - playback, export, every editor's "frozen base" -
    /// keeps assuming a real backing video file exists, which is still
    /// true). Nil means `.video` - every Moment created before this field
    /// existed really was a plain video, same "nil is a real legacy
    /// value" convention as every other field here. Foundation for the
    /// bucket/filter organization planned next; not yet read anywhere
    /// outside of `momentRow`'s icon.
    var momentKind: MomentKind? = nil
    /// 2026-10-04 - which user-created Folder/Bucket (MomentFolder.swift)
    /// this Moment is filed in, if any. Nil/nil means unfiled. A Moment
    /// filed in a bucket always has both set (the bucket's parent folder
    /// id too) so "every Moment in Folder X" is a single-field query
    /// regardless of whether it's filed directly in the folder or in one
    /// of its buckets - same Optional reasoning as every other field
    /// here. `AuthManager.moveMoment` is the only writer of either.
    var momentFolderId: String? = nil
    var momentBucketId: String? = nil
    /// 2026-10-07 - coaching Markup (lines/arrows/circles/...,
    /// MarkupOverlay.swift) - a deliberately separate array from
    /// `overlays` above, not another case of it, since `MarkupOverlay`'s
    /// multi-point geometry doesn't fit `OverlayItem`'s single
    /// position+scale+rotation anchor. Same Optional reasoning as every
    /// other field here; `AuthManager.updateMomentMarkupOverlays` is the
    /// only writer.
    var markupOverlays: [MarkupOverlay]? = nil

    init(
        createdAt: Date = Date(),
        teamId: String? = nil,
        playerId: String? = nil,
        playerName: String? = nil,
        durationSeconds: Double? = nil,
        isFavorite: Bool = false,
        opponent: String? = nil,
        score: String? = nil,
        inning: Int? = nil,
        gameInfoUpdatedAt: Date? = nil,
        photoCount: Int = 0,
        overlays: [OverlayItem]? = nil,
        speedKeyframes: [SpeedKeyframe]? = nil,
        audioOverlays: [AudioOverlayItem]? = nil,
        originalAudioVolume: Double? = nil,
        originalVolumeKeyframes: [VolumeKeyframe]? = nil,
        originalMuteRegions: [MuteRegion]? = nil,
        zoomRegions: [ZoomRegion]? = nil,
        slideshowSegments: [SlideshowSegment]? = nil,
        slideshowTransitionsEnabled: Bool? = nil,
        fadeInEnabled: Bool? = nil,
        fadeOutEnabled: Bool? = nil,
        cropSettings: CropSettings? = nil,
        freezeFrame: FreezeFrame? = nil,
        filterPreset: FilterPreset? = nil,
        momentKind: MomentKind? = nil,
        momentFolderId: String? = nil,
        momentBucketId: String? = nil,
        markupOverlays: [MarkupOverlay]? = nil
    ) {
        self.createdAt = createdAt
        self.teamId = teamId
        self.playerId = playerId
        self.playerName = playerName
        self.durationSeconds = durationSeconds
        self.isFavorite = isFavorite
        self.opponent = opponent
        self.score = score
        self.inning = inning
        self.gameInfoUpdatedAt = gameInfoUpdatedAt
        self.photoCount = photoCount
        self.overlays = overlays
        self.speedKeyframes = speedKeyframes
        self.audioOverlays = audioOverlays
        self.originalAudioVolume = originalAudioVolume
        self.originalVolumeKeyframes = originalVolumeKeyframes
        self.originalMuteRegions = originalMuteRegions
        self.zoomRegions = zoomRegions
        self.slideshowSegments = slideshowSegments
        self.slideshowTransitionsEnabled = slideshowTransitionsEnabled
        self.fadeInEnabled = fadeInEnabled
        self.fadeOutEnabled = fadeOutEnabled
        self.cropSettings = cropSettings
        self.freezeFrame = freezeFrame
        self.filterPreset = filterPreset
        self.momentKind = momentKind
        self.momentFolderId = momentFolderId
        self.momentBucketId = momentBucketId
        self.markupOverlays = markupOverlays
    }

    /// The user-set title if there is one, else the tagged player's name,
    /// else a generic fallback - the one place this fallback chain should
    /// be computed, used everywhere a Moment's name is displayed.
    var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespaces) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return playerName ?? "Moment"
    }
}

// MARK: - Local video storage (mirrors Utilities.swift's portrait pattern)

private func momentsDirectory() -> URL? {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return nil
    }
    return base.appendingPathComponent("PitchMark/Moments", isDirectory: true)
}

func localMomentVideoURL(for momentId: String) -> URL? {
    guard !momentId.isEmpty, let directory = momentsDirectory() else { return nil }
    return directory.appendingPathComponent("\(momentId).mov")
}

/// Copies a picker's temp file into the app's own sandbox - the temp URL
/// `UIImagePickerController` hands back does not survive past the current
/// launch.
@discardableResult
func saveLocalMomentVideo(from sourceURL: URL, momentId: String) -> Bool {
    guard let destinationURL = localMomentVideoURL(for: momentId) else { return false }
    do {
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return true
    } catch {
        debugLog("❌ saveLocalMomentVideo failed: \(error.localizedDescription)")
        return false
    }
}

func removeLocalMomentVideo(momentId: String) {
    guard let url = localMomentVideoURL(for: momentId) else { return }
    try? FileManager.default.removeItem(at: url)
}

/// The exported, edited video (Phase 7b) - separate from the original so
/// re-editing always starts from the untouched recording, never a prior
/// export.
func localMomentEditedVideoURL(for momentId: String) -> URL? {
    guard !momentId.isEmpty, let directory = momentsDirectory() else { return nil }
    return directory.appendingPathComponent("\(momentId)-edited.mov")
}

/// Playback and sharing should resolve a Moment's video through this,
/// not `localMomentVideoURL` directly - it prefers the edited file once
/// one exists, falling back to the original otherwise.
func resolvedMomentVideoURL(for momentId: String) -> URL? {
    if let edited = localMomentEditedVideoURL(for: momentId), FileManager.default.fileExists(atPath: edited.path) {
        return edited
    }
    return localMomentVideoURL(for: momentId)
}

/// Every frozen-base ring member (Audio/Overlay/Zoom/Slideshow/Crop, and
/// any added later). Each case name matches an `invalidateMoment{X}Base`
/// function below.
enum MomentEditorBase: CaseIterable {
    case audio, overlay, zoom, slideshow, crop, filter, markup
}

/// Invalidates every frozen-base ring member except the ones in `except`.
/// Centralizes what used to be a hand-rolled list of individual
/// `invalidateMoment*Base` calls duplicated at every editor's own export
/// success path (Trim/Speed/Overlay/Zoom/Audio/Slideshow) - a non-base
/// editor like Trim/Speed passes `except: []` (it has no base of its own,
/// same as calling every invalidate function directly, which is exactly
/// what it used to do); a ring member passes `except: [.itself]` so it
/// never invalidates its own base. Adding a new ring member only means
/// adding one case here plus one case in the switch below, instead of a
/// new line at every one of the other members' call sites.
///
/// Deliberately does NOT touch Fade - see `refreshFadeIfNeeded` below,
/// called separately at the same call sites. Keep this function pure/
/// synchronous (local file I/O only); Fade's own fix needs Firestore
/// access and an async re-export, which doesn't belong bolted onto this
/// one.
func invalidateOtherFrozenBases(momentId: String, except: Set<MomentEditorBase>) {
    for base in MomentEditorBase.allCases where !except.contains(base) {
        switch base {
        case .audio:
            invalidateMomentAudioBase(momentId: momentId)
        case .overlay:
            invalidateMomentOverlayBase(momentId: momentId)
        case .zoom:
            invalidateMomentZoomBase(momentId: momentId)
        case .slideshow:
            invalidateMomentSlideshowBase(momentId: momentId)
        case .crop:
            invalidateMomentCropBase(momentId: momentId)
        case .filter:
            invalidateMomentFilterBase(momentId: momentId)
        case .markup:
            invalidateMomentMarkupBase(momentId: momentId)
        }
    }
}

/// Keeps a previously-applied Fade in sync with a NEW edited video -
/// called alongside `invalidateOtherFrozenBases` at every editor's own
/// export success path (never from Moment deletion - see
/// `removeAllLocalMomentFiles`, which just deletes the faded file
/// outright since there's no Moment left to rebake it for).
///
/// Fade is deliberately NOT a frozen-base ring member and has no base of
/// its own to invalidate (see `localMomentFadedVideoURL`'s doc comment
/// for the "ghost fade" bug that design avoids) - it always rebuilds
/// fresh from `resolvedMomentVideoURL` (which never includes fade) on
/// its own "Apply Fade" tap. That's safe, but incomplete on its own: if
/// Fade is applied and then a LATER edit (e.g. adding audio) changes
/// `localMomentEditedVideoURL` without the user ever revisiting the Fade
/// screen, the OLD faded file - built from the PRE-that-edit video -
/// would otherwise keep winning in `resolvedMomentPlaybackURL` forever,
/// silently hiding the later edit (reported by the user as "adding a
/// fade in and out prevents audio from baking in" - the audio WAS
/// correctly baked into `localMomentEditedVideoURL`, it just never
/// surfaced anywhere). Simply deleting the stale file (the first fix
/// tried here) corrects that, but silently drops the fade the user
/// already applied and has no obvious reason to reapply (reported as
/// "after adding audio the fade was gone"). Re-baking it from the new
/// video instead, automatically, gives both: the later edit is visible
/// AND the fade the user already turned on keeps applying - matching how
/// every other time-based field in this app already gets kept in sync
/// by the editor that distorts it (see `remapAllTimeBasedFields`), just
/// via a re-export instead of a pure time-remap.
///
/// Fetches the Moment fresh (same reasoning as `remapAllTimeBasedFields`)
/// rather than trusting any locally-held state - no editor that calls
/// this has any reason to know Fade's own current toggle state.
/// Fire-and-forget: if this fails, the Moment is left exactly where the
/// old "just delete" fix would have left it (fade cleared, user can
/// reapply manually) - never worse.
func refreshFadeIfNeeded(momentId: String, authManager: AuthManager, completion: (() -> Void)? = nil) {
    guard !momentId.isEmpty else {
        completion?()
        return
    }
    // Delete the stale faded file immediately, synchronously - BEFORE
    // the async reload+re-export below even starts. Firestore round-trip
    // plus a real AVFoundation export can easily take several seconds;
    // leaving the OLD faded file in place for that whole window means
    // `resolvedMomentPlaybackURL` keeps serving content built from
    // BEFORE the edit that just landed (reported by the user: audio
    // added, then immediately checked, and the fade file - still the
    // pre-audio one, rebake not done yet - won the resolution) - the
    // exact bug this whole mechanism exists to prevent, just reintroduced
    // as a race instead of a permanent state. Deleting first means the
    // worst case during that window is "fade is briefly absent" (cosmetic,
    // self-heals once the rebake below lands), never "the edit that just
    // happened is invisible."
    if let faded = localMomentFadedVideoURL(for: momentId) {
        try? FileManager.default.removeItem(at: faded)
    }
    authManager.loadMoment(momentId: momentId) { fresh in
        guard let fresh else {
            debugLog("⚠️ refreshFadeIfNeeded: loadMoment returned nil for", momentId)
            completion?()
            return
        }
        let fadeIn = fresh.fadeInEnabled ?? false
        let fadeOut = fresh.fadeOutEnabled ?? false
        guard fadeIn || fadeOut else {
            debugLog("ℹ️ refreshFadeIfNeeded: no fade enabled on", momentId, "- nothing to rebake")
            completion?()
            return
        }
        guard let sourceURL = resolvedMomentVideoURL(for: momentId) else {
            debugLog("⚠️ refreshFadeIfNeeded: resolvedMomentVideoURL is nil for", momentId)
            completion?()
            return
        }

        exportFadedMoment(sourceURL: sourceURL, fadeInEnabled: fadeIn, fadeOutEnabled: fadeOut) { result in
            defer { completion?() }
            switch result {
            case .failure(let error):
                debugLog("❌ refreshFadeIfNeeded: exportFadedMoment failed for", momentId, "-", error.localizedDescription)
            case .success(let tempURL):
                guard let destination = localMomentFadedVideoURL(for: momentId) else {
                    debugLog("⚠️ refreshFadeIfNeeded: localMomentFadedVideoURL is nil for", momentId)
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: tempURL, to: destination)
                    try? FileManager.default.removeItem(at: tempURL)
                    debugLog("✅ refreshFadeIfNeeded: rebaked fade for", momentId)
                } catch {
                    debugLog("❌ refreshFadeIfNeeded: couldn't copy rebaked fade for", momentId, "-", error.localizedDescription)
                }
            }
        }
    }
}

/// The video `MomentAudioEditorView` always mixes from - snapshotted
/// once, the first time that editor touches this Moment, from whatever
/// `resolvedMomentVideoURL` was at that moment (untouched original, or
/// already trimmed/speed-ramped/overlaid, but never yet audio-mixed).
/// Every later audio-mix operation (live preview and export alike)
/// rebuilds fully from this same frozen file plus the *current* full
/// overlays/volume state - never from a *previous* audio-mix's own
/// output.
///
/// Without this, re-opening the audio editor after a previous audio
/// export would treat that prior export's already-mixed audio track as
/// if it were still a clean, unmixed source: moving or deleting a
/// placed clip added a fresh copy of the current overlay list on top of
/// a track that already permanently contained the old one, so a moved
/// clip "echoed" at both its old and new position, and deleting a clip
/// couldn't remove audio already flattened into that prior export - it
/// kept playing in both the live preview and every future export,
/// because both were built by re-mixing on top of an already-mixed
/// track instead of a clean one.
///
/// Invalidated by `invalidateMomentAudioBase` whenever Trim/Speed/
/// Overlay produce a new edited file, so the next audio edit
/// re-snapshots a fresh base instead of mixing on top of a stale one
/// (stale in the sense of missing that newer video content entirely,
/// not in the ghost-audio sense above).
func localMomentAudioBaseVideoURL(for momentId: String) -> URL? {
    guard !momentId.isEmpty, let directory = momentsDirectory() else { return nil }
    return directory.appendingPathComponent("\(momentId)-audio-base.mov")
}

/// Deletes the audio-mix base snapshot, if any. Call this whenever a
/// non-audio edit (Trim/Speed/Overlay) commits a new edited file - the
/// base's video would otherwise silently miss that newer edit the next
/// time audio is mixed, since the base only gets refreshed lazily.
func invalidateMomentAudioBase(momentId: String) {
    guard let url = localMomentAudioBaseVideoURL(for: momentId) else { return }
    try? FileManager.default.removeItem(at: url)
}

/// The video `OverlayEditorView` always bakes overlays onto -
/// snapshotted once, the first time that editor exports on this
/// Moment, from whatever `resolvedMomentVideoURL` was at that moment.
/// Exact same reasoning and same bug class as
/// `localMomentAudioBaseVideoURL` above, just for visual overlays
/// instead of audio: `OverlayEditorView.startExport()` used to
/// re-fetch `resolvedMomentVideoURL` fresh at export time, which - once
/// this editor had exported even once for a Moment - *is* a prior
/// overlay bake's own output. Moving or deleting a placed overlay after
/// that left its old position permanently burned into that prior
/// export's pixels (impossible to erase) while a fresh copy of the
/// current overlay list got composited on top, so a moved overlay
/// "ghosted" at both positions. (The live preview never had this bug -
/// it draws overlays as plain SwiftUI views on top of whatever's
/// already playing, never re-deriving from a possibly-baked file - only
/// export did.)
///
/// Invalidated by `invalidateMomentOverlayBase` whenever Trim/Speed/
/// Audio produce a new edited file, so the next overlay export
/// re-snapshots a fresh base instead of baking onto pixels that are
/// missing that newer edit entirely.
func localMomentOverlayBaseVideoURL(for momentId: String) -> URL? {
    guard !momentId.isEmpty, let directory = momentsDirectory() else { return nil }
    return directory.appendingPathComponent("\(momentId)-overlay-base.mov")
}

/// Resolves (creating on first use) the frozen overlay-bake base file -
/// `sourceVideoURL` is only consulted the moment the base doesn't exist
/// yet; every later call returns the existing base regardless of what
/// `sourceVideoURL` newly resolves to. Free function rather than a
/// method on `OverlayEditorView` so its `init` can call it with its raw
/// parameters before `self` is fully initialized - `OverlayEditorView`
/// needs the resolved base for its very first `AVPlayer(url:)`, not
/// just at export time.
///
/// 2026-09-30: `OverlayEditorView`'s live preview used to construct its
/// `AVPlayer` straight from the incoming `videoURL` - `resolvedMomentVideoURL`,
/// which *is* a prior overlay export's own output once one exists for a
/// Moment. Overlays are drawn as plain SwiftUI views on top of whatever's
/// playing, so re-opening this editor after any earlier export showed the
/// old overlay positions burned into the playing video's pixels *underneath*
/// a fresh, editable copy of the same overlays - moving one looked like it
/// left a duplicate behind, since the baked-in copy couldn't be moved.
/// Reported by the user as "the editing of added assets is glitchy." Same
/// bug class `startExport()` was already protected against (see
/// `localMomentOverlayBaseVideoURL`'s doc comment above) - the preview
/// player just wasn't pointed at the same frozen base yet.
func overlayBaseVideoURL(momentId: String, sourceVideoURL: URL) -> URL {
    guard let baseURL = localMomentOverlayBaseVideoURL(for: momentId) else {
        return sourceVideoURL
    }
    if !FileManager.default.fileExists(atPath: baseURL.path) {
        try? FileManager.default.copyItem(at: sourceVideoURL, to: baseURL)
    }
    return FileManager.default.fileExists(atPath: baseURL.path) ? baseURL : sourceVideoURL
}

/// Deletes the overlay-bake base snapshot, if any. Call this whenever a
/// non-overlay edit (Trim/Speed/Audio) commits a new edited file - same
/// reasoning as `invalidateMomentAudioBase`, mirrored for overlays.
func invalidateMomentOverlayBase(momentId: String) {
    guard let url = localMomentOverlayBaseVideoURL(for: momentId) else { return }
    try? FileManager.default.removeItem(at: url)
}

/// The video `MarkupEditorView` always bakes its lines/arrows/circles
/// onto - same frozen-snapshot trio as `localMomentOverlayBaseVideoURL`/
/// `overlayBaseVideoURL`/`invalidateMomentOverlayBase` above, mirrored
/// for Markup (MarkupOverlay.swift) rather than extending the overlay
/// ones - Markup is a separate frozen-base ring member
/// (`MomentEditorBase.markup` below), not another overlay kind.
func localMomentMarkupBaseVideoURL(for momentId: String) -> URL? {
    guard !momentId.isEmpty, let directory = momentsDirectory() else { return nil }
    return directory.appendingPathComponent("\(momentId)-markup-base.mov")
}

func markupBaseVideoURL(momentId: String, sourceVideoURL: URL) -> URL {
    guard let baseURL = localMomentMarkupBaseVideoURL(for: momentId) else {
        return sourceVideoURL
    }
    if !FileManager.default.fileExists(atPath: baseURL.path) {
        try? FileManager.default.copyItem(at: sourceVideoURL, to: baseURL)
    }
    return FileManager.default.fileExists(atPath: baseURL.path) ? baseURL : sourceVideoURL
}

func invalidateMomentMarkupBase(momentId: String) {
    guard let url = localMomentMarkupBaseVideoURL(for: momentId) else { return }
    try? FileManager.default.removeItem(at: url)
}

/// The video `MomentZoomEditorView` always bakes its pan/zoom onto -
/// same frozen-snapshot reasoning and same bug class as
/// `localMomentOverlayBaseVideoURL` just above, mirrored for zoom:
/// without a frozen base, re-opening the zoom editor after a prior zoom
/// export would treat that export's own already-zoomed pixels as the
/// "original" frame, so adjusting the zoom region a second time would
/// zoom into an already-zoomed-in video instead of the pre-zoom original.
///
/// Invalidated by `invalidateMomentZoomBase` whenever Trim/Speed/Audio/
/// Overlay produce a new edited file, so the next zoom export re-snapshots
/// a fresh base instead of baking onto pixels that are missing that newer
/// edit entirely.
func localMomentZoomBaseVideoURL(for momentId: String) -> URL? {
    guard !momentId.isEmpty, let directory = momentsDirectory() else { return nil }
    return directory.appendingPathComponent("\(momentId)-zoom-base.mov")
}

/// Resolves (creating on first use) the frozen zoom-bake base file - same
/// contract as `overlayBaseVideoURL` just above, mirrored for zoom.
func zoomBaseVideoURL(momentId: String, sourceVideoURL: URL) -> URL {
    guard let baseURL = localMomentZoomBaseVideoURL(for: momentId) else {
        return sourceVideoURL
    }
    if !FileManager.default.fileExists(atPath: baseURL.path) {
        try? FileManager.default.copyItem(at: sourceVideoURL, to: baseURL)
    }
    return FileManager.default.fileExists(atPath: baseURL.path) ? baseURL : sourceVideoURL
}

/// Deletes the zoom-bake base snapshot, if any. Call this whenever a
/// non-zoom edit (Trim/Speed/Audio/Overlay) commits a new edited file -
/// same reasoning as `invalidateMomentOverlayBase`, mirrored for zoom.
func invalidateMomentZoomBase(momentId: String) {
    guard let url = localMomentZoomBaseVideoURL(for: momentId) else { return }
    try? FileManager.default.removeItem(at: url)
}

/// The video `MomentSlideshowEditorView` always treats as "the video
/// segment" - same frozen-snapshot reasoning and same bug class as
/// `localMomentOverlayBaseVideoURL`/`localMomentZoomBaseVideoURL` above,
/// mirrored for the combined photos+video export: without a frozen base,
/// re-opening the slideshow editor after a prior combined export would
/// treat that export's own output (photos already spliced in) as "the
/// video," so re-exporting would splice the photos in a second time on
/// top of a video that already contains them once.
///
/// Invalidated by `invalidateMomentSlideshowBase` whenever Trim/Speed/
/// Zoom/Audio/Overlay produce a new edited file, so the next combined
/// export re-snapshots a fresh base instead of treating pixels that are
/// missing that newer edit entirely as "the video."
func localMomentSlideshowBaseVideoURL(for momentId: String) -> URL? {
    guard !momentId.isEmpty, let directory = momentsDirectory() else { return nil }
    return directory.appendingPathComponent("\(momentId)-slideshow-base.mov")
}

/// Resolves (creating on first use) the frozen slideshow-bake base file -
/// same contract as `overlayBaseVideoURL`/`zoomBaseVideoURL` above,
/// mirrored for the combined export.
func slideshowBaseVideoURL(momentId: String, sourceVideoURL: URL) -> URL {
    guard let baseURL = localMomentSlideshowBaseVideoURL(for: momentId) else {
        return sourceVideoURL
    }
    if !FileManager.default.fileExists(atPath: baseURL.path) {
        try? FileManager.default.copyItem(at: sourceVideoURL, to: baseURL)
    }
    return FileManager.default.fileExists(atPath: baseURL.path) ? baseURL : sourceVideoURL
}

/// Deletes the slideshow-bake base snapshot, if any. Call this whenever
/// a non-slideshow edit (Trim/Speed/Zoom/Audio/Overlay) commits a new
/// edited file - same reasoning as `invalidateMomentZoomBase`, mirrored
/// for the combined export.
func invalidateMomentSlideshowBase(momentId: String) {
    guard let url = localMomentSlideshowBaseVideoURL(for: momentId) else { return }
    try? FileManager.default.removeItem(at: url)
}

/// The video `MomentCropEditorView` always bakes its crop/reframe onto -
/// same frozen-snapshot reasoning and same bug class as
/// `localMomentZoomBaseVideoURL`/`localMomentOverlayBaseVideoURL` above:
/// without a frozen base, re-opening the crop editor after a prior crop
/// export would treat that export's own already-cropped pixels as the
/// "original" frame, so adjusting the crop a second time would crop an
/// already-cropped video instead of the pre-crop original.
///
/// Invalidated by every other frozen-base ring member whenever they
/// produce a new edited file - see `invalidateOtherFrozenBases`.
func localMomentCropBaseVideoURL(for momentId: String) -> URL? {
    guard !momentId.isEmpty, let directory = momentsDirectory() else { return nil }
    return directory.appendingPathComponent("\(momentId)-crop-base.mov")
}

/// Resolves (creating on first use) the frozen crop-bake base file - same
/// contract as `overlayBaseVideoURL`/`zoomBaseVideoURL` above, mirrored
/// for crop.
func cropBaseVideoURL(momentId: String, sourceVideoURL: URL) -> URL {
    guard let baseURL = localMomentCropBaseVideoURL(for: momentId) else {
        return sourceVideoURL
    }
    if !FileManager.default.fileExists(atPath: baseURL.path) {
        try? FileManager.default.copyItem(at: sourceVideoURL, to: baseURL)
    }
    return FileManager.default.fileExists(atPath: baseURL.path) ? baseURL : sourceVideoURL
}

/// Deletes the crop-bake base snapshot, if any - same reasoning as
/// `invalidateMomentZoomBase`, mirrored for crop.
func invalidateMomentCropBase(momentId: String) {
    guard let url = localMomentCropBaseVideoURL(for: momentId) else { return }
    try? FileManager.default.removeItem(at: url)
}

/// The video `MomentFilterEditorView` always bakes its color filter
/// onto - same frozen-snapshot reasoning as `localMomentCropBaseVideoURL`
/// above. Reading from this frozen base (rather than a possibly-already-
/// filtered file) also means every other visual effect is already
/// flattened to plain pixels by the time the custom color compositor
/// runs, so it never needs to coexist with a CALayer sprite tree in the
/// same pass - see MomentFilterExporter.swift's header comment.
func localMomentFilterBaseVideoURL(for momentId: String) -> URL? {
    guard !momentId.isEmpty, let directory = momentsDirectory() else { return nil }
    return directory.appendingPathComponent("\(momentId)-filter-base.mov")
}

/// Resolves (creating on first use) the frozen filter-bake base file -
/// same contract as `cropBaseVideoURL`/`zoomBaseVideoURL` above,
/// mirrored for color filters.
func filterBaseVideoURL(momentId: String, sourceVideoURL: URL) -> URL {
    guard let baseURL = localMomentFilterBaseVideoURL(for: momentId) else {
        return sourceVideoURL
    }
    if !FileManager.default.fileExists(atPath: baseURL.path) {
        try? FileManager.default.copyItem(at: sourceVideoURL, to: baseURL)
    }
    return FileManager.default.fileExists(atPath: baseURL.path) ? baseURL : sourceVideoURL
}

/// Deletes the filter-bake base snapshot, if any - same reasoning as
/// `invalidateMomentCropBase`, mirrored for color filters.
func invalidateMomentFilterBase(momentId: String) {
    guard let url = localMomentFilterBaseVideoURL(for: momentId) else { return }
    try? FileManager.default.removeItem(at: url)
}

/// 2026-10-01: Fade used to follow the same "frozen base, invalidated by
/// every other editor" pattern as Zoom/Overlay/Audio/Slideshow above -
/// removed after it was confirmed (via an actual end-to-end render, not
/// just code review) to have a real bug that class of editor doesn't:
/// when another editor (e.g. Zoom) ran *after* a fade had already been
/// applied, it correctly invalidated the fade's frozen base - but the
/// base then got *recreated from the currently-faded video*, since
/// that's whatever `resolvedMomentVideoURL` resolved to at that point.
/// That permanently baked the fade into the "pre-fade" snapshot itself,
/// so from then on toggling both switches off and re-applying just
/// reproduced the same fade forever - reported by the user as "applying
/// removal, but the fade doesn't actually go away."
///
/// The fix: Fade is not a destructive bake onto the shared edited video
/// at all. It writes its own separate file
/// (`localMomentFadedVideoURL`), read fresh from `resolvedMomentVideoURL`
/// (which never includes a fade - every other editor's own base/export
/// logic still treats it as the fade-free timeline) every time Apply
/// Fade runs, whether turning a fade on or off. There is no frozen base
/// to invalidate, so no other editor needs to know about Fade at all -
/// removing a fade is just deleting this one file.
func localMomentFadedVideoURL(for momentId: String) -> URL? {
    guard !momentId.isEmpty, let directory = momentsDirectory() else { return nil }
    return directory.appendingPathComponent("\(momentId)-faded.mov")
}

/// What should actually be played or shared: the faded version if one
/// exists (i.e. at least one of Fade In/Out is currently applied), else
/// the plain edited video. Every *editor's* own source/base resolution
/// still calls `resolvedMomentVideoURL` directly, never this - an editor
/// building on top of a baked-in fade is exactly the bug class this
/// whole mechanism exists to avoid. Only actual playback (the in-app
/// player, the dedicated playback viewer, share sheets, save-to-Camera-
/// Roll, duplicate) should resolve through this.
func resolvedMomentPlaybackURL(for momentId: String) -> URL? {
    if let faded = localMomentFadedVideoURL(for: momentId), FileManager.default.fileExists(atPath: faded.path) {
        return faded
    }
    return resolvedMomentVideoURL(for: momentId)
}

// MARK: - Local photo storage (same directory convention as video)

func localMomentPhotoURL(momentId: String, index: Int) -> URL? {
    guard !momentId.isEmpty, let directory = momentsDirectory() else { return nil }
    return directory.appendingPathComponent("\(momentId)-photo-\(index).jpg")
}

/// Camera captures (and some Photos-library assets) can carry an HDR gain
/// map. Displaying that as-is produces a real, ~0.8s brightness
/// "breathing" pulse on the thumbnail as iOS's HDR-to-SDR tone-mapping
/// re-negotiates - reported against the Moments detail screen and
/// confirmed via frame-by-frame brightness analysis of a screen
/// recording (both thumbnails pulsed in sync; the plain white background
/// and text around them stayed perfectly constant, ruling out a
/// display/auto-brightness cause). Round-tripping through UIImage's
/// re-encoder strips the gain map, so every path that saves a Moment
/// photo - the camera shutter and the PhotosPicker "+" button alike -
/// writes plain SDR to disk.
private func stripHDRGainMap(from data: Data) -> Data {
    guard let image = UIImage(data: data), let sdrData = image.jpegData(compressionQuality: 0.92) else {
        return data
    }
    return sdrData
}

@discardableResult
func saveLocalMomentPhoto(_ data: Data, momentId: String, index: Int) -> Bool {
    guard let destinationURL = localMomentPhotoURL(momentId: momentId, index: index) else { return false }
    do {
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try stripHDRGainMap(from: data).write(to: destinationURL, options: [.atomic])
        return true
    } catch {
        debugLog("❌ saveLocalMomentPhoto failed: \(error.localizedDescription)")
        return false
    }
}

// MARK: - AuthManager persistence

extension AuthManager {
    func saveMoment(_ moment: Moment, completion: @escaping (Result<Moment, Error>) -> Void) {
        guard let user = user else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])))
            return
        }

        let ref = Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("moments").document()

        var moment = moment
        moment.id = ref.documentID

        do {
            try ref.setData(from: moment) { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(moment))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    /// Turns a single photo into its own standalone `.photoCreation`
    /// Moment - same `buildVideoFromPhotos` + save + attach shape
    /// `MomentsLibraryView`'s shutter-capture path uses, pulled out here
    /// so "also add this photo to your Moments Library" (MomentDetailView,
    /// after attaching a phone-library photo to an existing video) has
    /// one shared implementation to call rather than a second copy of it.
    func createPhotoCreationMoment(
        photoData: Data,
        teamId: String?,
        playerId: String?,
        playerName: String?,
        completion: @escaping () -> Void
    ) {
        guard let image = UIImage(data: photoData) else {
            completion()
            return
        }
        buildVideoFromPhotos([image]) { [weak self] result in
            guard let self, case .success(let builtURL) = result else {
                completion()
                return
            }
            let newMoment = Moment(
                teamId: teamId,
                playerId: playerId,
                playerName: playerName,
                durationSeconds: defaultSlideshowPhotoDuration,
                photoCount: 1,
                momentKind: .photoCreation
            )
            self.saveMoment(newMoment) { result in
                if case .success(let saved) = result, let newId = saved.id {
                    saveLocalMomentVideo(from: builtURL, momentId: newId)
                    saveLocalMomentPhoto(photoData, momentId: newId, index: 0)
                }
                completion()
            }
        }
    }

    /// Partial update - callers pass only the fields they're changing.
    /// Used for Favorite/Game Info/photoCount so an edit to one field
    /// never touches the others.
    func updateMomentFields(momentId: String, fields: [String: Any], completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("moments").document(momentId)
            .updateData(fields) { error in
                completion(error)
            }
    }

    /// Trim and speed-ramp export both change a Moment's actual video
    /// duration but don't otherwise touch this field - without calling
    /// this after either edit, the list's displayed duration goes stale
    /// (still reflects whatever the Moment's duration was at recording
    /// time). Fire-and-forget by design, matching every other small
    /// field update in this app - callers don't block on it.
    func refreshMomentDuration(momentId: String, videoURL: URL, completion: (() -> Void)? = nil) {
        guard !momentId.isEmpty else {
            completion?()
            return
        }
        Task {
            let asset = AVURLAsset(url: videoURL)
            let loadedDuration = try? await asset.load(.duration)
            guard let seconds = loadedDuration?.seconds, seconds.isFinite else {
                await MainActor.run { completion?() }
                return
            }
            await MainActor.run {
                self.updateMomentFields(momentId: momentId, fields: ["durationSeconds": seconds]) { _ in
                    completion?()
                }
            }
        }
    }

    /// `overlays` is an array of Codable structs, not a primitive -
    /// updateMomentFields's plain [String: Any] shape can't carry that
    /// directly. Encoding through a tiny wrapper via Firestore.Encoder
    /// produces exactly the ["overlays": [[String: Any]]] shape
    /// updateData expects - the same mechanism saveMoment already trusts
    /// via setData(from:), aimed at one field instead of a whole document.
    func updateMomentOverlays(momentId: String, overlays: [OverlayItem], completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        struct OverlaysFieldWrapper: Encodable {
            var overlays: [OverlayItem]
        }

        do {
            let encoded = try Firestore.Encoder().encode(OverlaysFieldWrapper(overlays: overlays))
            Firestore.firestore()
                .collection("users").document(user.uid)
                .collection("moments").document(momentId)
                .updateData(encoded) { error in
                    completion(error)
                }
        } catch {
            completion(error)
        }
    }

    /// Same shape as `updateMomentOverlays` - `markupOverlays` is also
    /// an array of Codable structs, needing the same Firestore.Encoder
    /// wrapper trick.
    func updateMomentMarkupOverlays(momentId: String, markupOverlays: [MarkupOverlay], completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        struct MarkupOverlaysFieldWrapper: Encodable {
            var markupOverlays: [MarkupOverlay]
        }

        do {
            let encoded = try Firestore.Encoder().encode(MarkupOverlaysFieldWrapper(markupOverlays: markupOverlays))
            Firestore.firestore()
                .collection("users").document(user.uid)
                .collection("moments").document(momentId)
                .updateData(encoded) { error in
                    completion(error)
                }
        } catch {
            completion(error)
        }
    }

    /// Same shape as `updateMomentOverlays` - an array of Codable structs
    /// needs the same Firestore.Encoder wrapper trick.
    func updateMomentSpeedKeyframes(momentId: String, keyframes: [SpeedKeyframe], completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        struct SpeedKeyframesFieldWrapper: Encodable {
            var speedKeyframes: [SpeedKeyframe]
        }

        do {
            let encoded = try Firestore.Encoder().encode(SpeedKeyframesFieldWrapper(speedKeyframes: keyframes))
            Firestore.firestore()
                .collection("users").document(user.uid)
                .collection("moments").document(momentId)
                .updateData(encoded) { error in
                    completion(error)
                }
        } catch {
            completion(error)
        }
    }

    /// Same shape as `updateMomentOverlays`/`updateMomentSpeedKeyframes`.
    func updateMomentAudioOverlays(momentId: String, audioOverlays: [AudioOverlayItem], completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        struct AudioOverlaysFieldWrapper: Encodable {
            var audioOverlays: [AudioOverlayItem]
        }

        do {
            let encoded = try Firestore.Encoder().encode(AudioOverlaysFieldWrapper(audioOverlays: audioOverlays))
            Firestore.firestore()
                .collection("users").document(user.uid)
                .collection("moments").document(momentId)
                .updateData(encoded) { error in
                    completion(error)
                }
        } catch {
            completion(error)
        }
    }

    /// Same shape as `updateMomentAudioOverlays` - `originalVolumeKeyframes`
    /// is also an array of Codable structs, not a primitive
    /// `updateMomentFields` can carry directly.
    func updateMomentOriginalVolumeKeyframes(momentId: String, keyframes: [VolumeKeyframe], completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        struct OriginalVolumeKeyframesFieldWrapper: Encodable {
            var originalVolumeKeyframes: [VolumeKeyframe]
        }

        do {
            let encoded = try Firestore.Encoder().encode(OriginalVolumeKeyframesFieldWrapper(originalVolumeKeyframes: keyframes))
            Firestore.firestore()
                .collection("users").document(user.uid)
                .collection("moments").document(momentId)
                .updateData(encoded) { error in
                    completion(error)
                }
        } catch {
            completion(error)
        }
    }

    /// Same shape as `updateMomentOriginalVolumeKeyframes` -
    /// `originalMuteRegions` is also an array of Codable structs.
    func updateMomentOriginalMuteRegions(momentId: String, regions: [MuteRegion], completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        struct OriginalMuteRegionsFieldWrapper: Encodable {
            var originalMuteRegions: [MuteRegion]
        }

        do {
            let encoded = try Firestore.Encoder().encode(OriginalMuteRegionsFieldWrapper(originalMuteRegions: regions))
            Firestore.firestore()
                .collection("users").document(user.uid)
                .collection("moments").document(momentId)
                .updateData(encoded) { error in
                    completion(error)
                }
        } catch {
            completion(error)
        }
    }

    /// Same shape as `updateMomentOriginalMuteRegions` - `zoomRegions`
    /// is also an array of Codable structs.
    func updateMomentZoomRegions(momentId: String, regions: [ZoomRegion], completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        struct ZoomRegionsFieldWrapper: Encodable {
            var zoomRegions: [ZoomRegion]
        }

        do {
            let encoded = try Firestore.Encoder().encode(ZoomRegionsFieldWrapper(zoomRegions: regions))
            Firestore.firestore()
                .collection("users").document(user.uid)
                .collection("moments").document(momentId)
                .updateData(encoded) { error in
                    completion(error)
                }
        } catch {
            completion(error)
        }
    }

    /// `cropSettings` is always written as a concrete value (even
    /// `.original`), never a literal nil - same "off is a real value"
    /// discipline `fadeInEnabled`/`fadeOutEnabled` already use - so this
    /// never needs `FieldValue.delete()` or an Optional-aware wrapper.
    func updateMomentCropSettings(momentId: String, cropSettings: CropSettings, completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        struct CropSettingsFieldWrapper: Encodable {
            var cropSettings: CropSettings
        }

        do {
            let encoded = try Firestore.Encoder().encode(CropSettingsFieldWrapper(cropSettings: cropSettings))
            Firestore.firestore()
                .collection("users").document(user.uid)
                .collection("moments").document(momentId)
                .updateData(encoded) { error in
                    completion(error)
                }
        } catch {
            completion(error)
        }
    }

    /// Unlike `updateMomentCropSettings`, `nil` here is a real "remove the
    /// freeze frame" action, not a concrete "off" value - `FieldValue.delete()`
    /// actually clears the Firestore field rather than writing a sentinel.
    func updateMomentFreezeFrame(momentId: String, freezeFrame: FreezeFrame?, completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        guard let freezeFrame else {
            Firestore.firestore()
                .collection("users").document(user.uid)
                .collection("moments").document(momentId)
                .updateData(["freezeFrame": FieldValue.delete()]) { error in
                    completion(error)
                }
            return
        }

        struct FreezeFrameFieldWrapper: Encodable {
            var freezeFrame: FreezeFrame
        }

        do {
            let encoded = try Firestore.Encoder().encode(FreezeFrameFieldWrapper(freezeFrame: freezeFrame))
            Firestore.firestore()
                .collection("users").document(user.uid)
                .collection("moments").document(momentId)
                .updateData(encoded) { error in
                    completion(error)
                }
        } catch {
            completion(error)
        }
    }

    /// Same `FieldValue.delete()` shape as `updateMomentFreezeFrame` -
    /// "no filter" is a real removal, not a concrete off value, since
    /// there's no `.none` case on `FilterPreset`.
    func updateMomentFilterPreset(momentId: String, filterPreset: FilterPreset?, completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        guard let filterPreset else {
            Firestore.firestore()
                .collection("users").document(user.uid)
                .collection("moments").document(momentId)
                .updateData(["filterPreset": FieldValue.delete()]) { error in
                    completion(error)
                }
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("moments").document(momentId)
            .updateData(["filterPreset": filterPreset.rawValue]) { error in
                completion(error)
            }
    }

    /// Same shape as `updateMomentZoomRegions` - `slideshowSegments` is
    /// also an array of Codable structs.
    func updateMomentSlideshowSegments(momentId: String, segments: [SlideshowSegment], completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        struct SlideshowSegmentsFieldWrapper: Encodable {
            var slideshowSegments: [SlideshowSegment]
        }

        do {
            let encoded = try Firestore.Encoder().encode(SlideshowSegmentsFieldWrapper(slideshowSegments: segments))
            Firestore.firestore()
                .collection("users").document(user.uid)
                .collection("moments").document(momentId)
                .updateData(encoded) { error in
                    completion(error)
                }
        } catch {
            completion(error)
        }
    }

    func loadMoments(completion: @escaping ([Moment]) -> Void) {
        guard let user = user else {
            completion([])
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("moments")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                let moments: [Moment] = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: Moment.self)
                } ?? []
                completion(moments)
            }
    }

    /// Single-document counterpart to `loadMoments` - re-fetches one
    /// Moment fresh from Firestore. `MomentDetailView` holds its own
    /// `moment` as a `let` snapshot from whenever it was first opened;
    /// every editor's `initial...` parameter (overlays/speed keyframes/
    /// zoom regions/slideshow segments/mute regions) seeds from that same
    /// snapshot. Each editor persists its own changes to Firestore
    /// immediately (not just at its own "Export" tap), but nothing
    /// previously refreshed `moment` itself - so closing an editor after
    /// adding something (a mute region, say) and reopening it (or any
    /// other editor) later re-seeded from the ORIGINAL stale snapshot,
    /// silently discarding everything persisted since. Reported by the
    /// user as "the mute section usually does not bake in" - works
    /// immediately in the same session (the editor's own live @State is
    /// correct), breaks after leaving and coming back (the next editor
    /// instance re-seeds from stale data). `MomentDetailView` now calls
    /// this after every editor dismisses to keep `moment` current.
    func loadMoment(momentId: String, completion: @escaping (Moment?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(nil)
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("moments").document(momentId)
            .getDocument { snapshot, error in
                completion(snapshot.flatMap { try? $0.data(as: Moment.self) })
            }
    }

    func deleteMoment(momentId: String, completion: @escaping (Error?) -> Void) {
        guard let user = user, !momentId.isEmpty else {
            completion(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }

        Firestore.firestore()
            .collection("users").document(user.uid)
            .collection("moments").document(momentId)
            .delete { error in
                completion(error)
            }
    }
}

/// Mute regions, audio overlays, the original track's volume keyframes,
/// visual overlays (+ their keyframes), and zoom regions all store
/// absolute time-in-seconds positions against whatever the video's
/// timeline was when they were placed. Any edit that distorts that
/// timeline - Speed ramp (a source second no longer falls at the same
/// composite second once a range plays faster/slower) and Freeze-frame
/// (everything after the freeze point shifts forward by the hold
/// duration) alike - has to remap every one of those stored positions
/// through the exact same transform its own export just used to retime
/// the real audio/video tracks, or they're left pointing at a completely
/// different moment in the retimed result. Originally Speed-only
/// (`MomentSpeedEditorView`'s private `remapOtherTimeBasedEdits`,
/// reported by the user as "adding speed changes after adding mute
/// sections and audio overlays causes much glitch to the previously
/// added mutes and sounds"); generalized here so Freeze-frame reuses the
/// identical field list rather than a hand-copied duplicate - this list
/// has already grown twice as `Moment` gained fields, and a duplicate
/// copy is exactly the kind of thing that drifts the next time it grows
/// again.
///
/// Fetches the Moment fresh rather than trusting any locally-held state -
/// neither Speed nor Freeze's own editor knows about mute regions or
/// audio overlays at all; those live entirely in MomentAudioEditorView.
/// Only *position* fields are remapped - `fadeInSeconds`/`fadeOutSeconds`
/// are durations, and `trimStart`/`trimEnd` are intrinsic to an audio
/// overlay's own source asset, neither of which describes a position on
/// the Moment's own timeline.
func remapAllTimeBasedFields(momentId: String, authManager: AuthManager, transform: @escaping (Double) -> Double, completion: (() -> Void)? = nil) {
    guard !momentId.isEmpty else {
        completion?()
        return
    }
    authManager.loadMoment(momentId: momentId) { fresh in
        guard let fresh else {
            completion?()
            return
        }

        if let regions = fresh.originalMuteRegions, !regions.isEmpty {
            let remapped = regions.map { region -> MuteRegion in
                var copy = region
                copy.startTime = transform(region.startTime)
                copy.endTime = transform(region.endTime)
                return copy
            }
            authManager.updateMomentOriginalMuteRegions(momentId: momentId, regions: remapped) { _ in }
        }

        if let overlays = fresh.audioOverlays, !overlays.isEmpty {
            let remapped = overlays.map { overlay -> AudioOverlayItem in
                var copy = overlay
                copy.startTime = transform(overlay.startTime)
                if let keyframes = copy.volumeKeyframes {
                    copy.volumeKeyframes = keyframes.map { keyframe -> VolumeKeyframe in
                        var keyframeCopy = keyframe
                        keyframeCopy.time = transform(keyframe.time)
                        return keyframeCopy
                    }
                }
                return copy
            }
            authManager.updateMomentAudioOverlays(momentId: momentId, audioOverlays: remapped) { _ in }
        }

        if let keyframes = fresh.originalVolumeKeyframes, !keyframes.isEmpty {
            let remapped = keyframes.map { keyframe -> VolumeKeyframe in
                var copy = keyframe
                copy.time = transform(keyframe.time)
                return copy
            }
            authManager.updateMomentOriginalVolumeKeyframes(momentId: momentId, keyframes: remapped) { _ in }
        }

        // Visual overlays: startTime/endTime AND every keyframe's own
        // `time` are all absolute Moment-timeline seconds (see
        // Overlay.swift's `transform(at:)`/`isVisible(at:)`, which
        // compare a keyframe's `time` directly against the same
        // absolute `time` parameter with no offset by `startTime`).
        if let overlays = fresh.overlays, !overlays.isEmpty {
            let remapped = overlays.map { overlay -> OverlayItem in
                var copy = overlay
                copy.startTime = transform(overlay.startTime)
                copy.endTime = transform(overlay.endTime)
                copy.keyframes = overlay.keyframes.map { keyframe -> OverlayKeyframe in
                    var keyframeCopy = keyframe
                    keyframeCopy.time = transform(keyframe.time)
                    return keyframeCopy
                }
                return copy
            }
            authManager.updateMomentOverlays(momentId: momentId, overlays: remapped) { _ in }
        }

        // Zoom regions: just startTime/endTime - a region has no
        // keyframe sub-array, only its own two framing endpoints.
        if let regions = fresh.zoomRegions, !regions.isEmpty {
            let remapped = regions.map { region -> ZoomRegion in
                var copy = region
                copy.startTime = transform(region.startTime)
                copy.endTime = transform(region.endTime)
                return copy
            }
            authManager.updateMomentZoomRegions(momentId: momentId, regions: remapped) { _ in }
        }

        // Freeze's own recorded `timestamp` is a position too - if a
        // Speed ramp (or any future distorting edit) runs AFTER a freeze
        // was already applied, the freeze's already-baked pixels move
        // along with everything else in the re-exported video (it's
        // just ordinary content to that later edit), but without this,
        // the *stored* `timestamp` would keep pointing at its old
        // position - reopening the freeze editor would show the wrong
        // scrub point, and re-applying from there would bake a second,
        // wrongly-placed hold instead of adjusting the existing one.
        if let freezeFrame = fresh.freezeFrame {
            var copy = freezeFrame
            copy.timestamp = transform(freezeFrame.timestamp)
            authManager.updateMomentFreezeFrame(momentId: momentId, freezeFrame: copy) { _ in }
        }

        completion?()
    }
}

/// Removes everything local to a Moment - original video, edited video,
/// and any attached photos. Call after the Firestore doc itself is
/// deleted (see AuthManager.deleteMoment).
func removeAllLocalMomentFiles(momentId: String, photoCount: Int) {
    removeLocalMomentVideo(momentId: momentId)
    if let edited = localMomentEditedVideoURL(for: momentId) {
        try? FileManager.default.removeItem(at: edited)
    }
    invalidateOtherFrozenBases(momentId: momentId, except: [])
    // Plain deletion, not refreshFadeIfNeeded - the Moment itself is
    // being destroyed, there's nothing left to rebake a fade for.
    if let faded = localMomentFadedVideoURL(for: momentId) {
        try? FileManager.default.removeItem(at: faded)
    }
    for index in 0..<max(photoCount, 0) {
        if let photoURL = localMomentPhotoURL(momentId: momentId, index: index) {
            try? FileManager.default.removeItem(at: photoURL)
        }
    }
}

/// Saves a copy of a Moment's current video (faded version if a fade is
/// currently applied, else the plain edited version, else the original)
/// to the system Photos library.
func saveMomentVideoToCameraRoll(momentId: String, completion: @escaping (Result<Void, Error>) -> Void) {
    guard let url = resolvedMomentPlaybackURL(for: momentId) else {
        completion(.failure(NSError(domain: "Moment", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video file found for this Moment."])))
        return
    }

    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        guard status == .authorized || status == .limited else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "Moment", code: -2, userInfo: [NSLocalizedDescriptionKey: "Photos access is needed to save this video."])))
            }
            return
        }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    completion(.success(()))
                } else {
                    completion(.failure(error ?? NSError(domain: "Moment", code: -3, userInfo: [NSLocalizedDescriptionKey: "Couldn't save to Photos."])))
                }
            }
        }
    }
}
