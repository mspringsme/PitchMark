"use strict";
// Cost guardrails for cloud clips and full-game video (brief: "Clip Feed,
// Game Feeds + Full-Game Video", section 5). Kept free of Firebase so it can
// be tested on its own. The app twin is PitchMark/CaptureGuardrails.swift -
// keep the limits identical.
//
// Providers bill after the fact and enforce no dollar cap, so every upload
// URL and stream start goes through these checks first (layer 2), and the
// running spend estimate trips the kill switch (layer 3). Nothing here is
// wired to an endpoint yet: the features it guards are built behind flags
// and stay off until the release gate.
Object.defineProperty(exports, "__esModule", { value: true });
exports.gatedFeatures = exports.releaseGateCleared = exports.defaultDailySpendCapUSD = exports.unitCosts = exports.streamLimits = exports.clipLimits = void 0;
exports.checkClipQuota = checkClipQuota;
exports.checkStream = checkStream;
exports.estimateDailySpendUSD = estimateDailySpendUSD;
exports.circuitBreaker = circuitBreaker;
exports.featureEnabled = featureEnabled;
exports.clipLimits = {
    /** Hard cap on one clip. */
    maxClipSeconds: 60,
    /** A 60 s 720p clip is about 18.7 MB; leave headroom for bitrate spikes. */
    maxClipBytes: 25 * 1024 * 1024,
    perPersonPerGameClips: 25,
    perPersonPerGameSeconds: 10 * 60,
    perTeamPerDayClips: 150,
    perTeamPerMonthClips: 2000
};
exports.streamLimits = {
    /** Streams auto-stop at about 3 hours. */
    maxStreamSeconds: 3 * 60 * 60,
    perTeamPerMonthStreamHours: 30,
    maxViewersPerStream: 40
};
/** Unit costs used for the running estimate (section 6; validate before launch). */
exports.unitCosts = {
    r2StoragePerGBMonth: 0.015,
    streamDeliveredPerMinute: 1 / 1000,
    streamStoredPer1000MinutesMonth: 5,
    moderationPerMinute: 0.01
};
/** The daily cap the circuit breaker starts at (brief: $15 to $25). */
exports.defaultDailySpendCapUSD = 20;
/** Checked before an upload URL is issued. The usage counts are what's
 *  already been used, not including this clip. */
function checkClipQuota(usage, request) {
    const nums = [request.seconds, request.bytes, usage.personGameClips, usage.personGameSeconds,
        usage.teamDayClips, usage.teamMonthClips];
    if (nums.some((n) => typeof n !== "number" || !Number.isFinite(n) || n < 0)) {
        return { ok: false, reason: "invalidRequest" };
    }
    if (request.seconds <= 0 || request.bytes <= 0)
        return { ok: false, reason: "invalidRequest" };
    if (request.seconds > exports.clipLimits.maxClipSeconds)
        return { ok: false, reason: "clipTooLong" };
    if (request.bytes > exports.clipLimits.maxClipBytes)
        return { ok: false, reason: "clipTooLarge" };
    if (usage.personGameClips + 1 > exports.clipLimits.perPersonPerGameClips)
        return { ok: false, reason: "personGameClips" };
    if (usage.personGameSeconds + request.seconds > exports.clipLimits.perPersonPerGameSeconds) {
        return { ok: false, reason: "personGameSeconds" };
    }
    if (usage.teamDayClips + 1 > exports.clipLimits.perTeamPerDayClips)
        return { ok: false, reason: "teamDayClips" };
    if (usage.teamMonthClips + 1 > exports.clipLimits.perTeamPerMonthClips)
        return { ok: false, reason: "teamMonthClips" };
    return { ok: true };
}
/** Checked before a stream starts (viewers = 0) or a viewer joins. The
 *  stream may run only as long as the month's remaining hours allow, and
 *  never past the auto-stop. */
function checkStream(usage, joiningViewer) {
    const { teamMonthStreamSeconds: used, activeViewers } = usage;
    if (![used, activeViewers].every((n) => typeof n === "number" && Number.isFinite(n) && n >= 0)) {
        return { ok: false, reason: "invalidRequest" };
    }
    if (joiningViewer) {
        return activeViewers + 1 > exports.streamLimits.maxViewersPerStream
            ? { ok: false, reason: "viewerCap" }
            : { ok: true, maxSeconds: 0 };
    }
    const remaining = exports.streamLimits.perTeamPerMonthStreamHours * 3600 - used;
    if (remaining <= 0)
        return { ok: false, reason: "teamMonthHours" };
    return { ok: true, maxSeconds: Math.min(exports.streamLimits.maxStreamSeconds, remaining) };
}
/** Our own estimate of today's spend in USD (layer 3). Monthly storage is
 *  spread over 30 days. Never negative. */
function estimateDailySpendUSD(usage) {
    const clean = (n) => (typeof n === "number" && Number.isFinite(n) && n > 0 ? n : 0);
    const storage = clean(usage.storedGB) * exports.unitCosts.r2StoragePerGBMonth / 30;
    const delivery = clean(usage.deliveredMinutes) * exports.unitCosts.streamDeliveredPerMinute;
    const streamStorage = clean(usage.streamStoredMinutes) / 1000 * exports.unitCosts.streamStoredPer1000MinutesMonth / 30;
    const moderation = clean(usage.moderatedMinutes) * exports.unitCosts.moderationPerMinute;
    return storage + delivery + streamStorage + moderation;
}
/** Trips at or past the cap. A missing, zero or nonsense cap falls back to
 *  the default rather than leaving spending unguarded. */
function circuitBreaker(usage, capUSD) {
    const cap = typeof capUSD === "number" && Number.isFinite(capUSD) && capUSD > 0 ? capUSD : exports.defaultDailySpendCapUSD;
    const estimate = estimateDailySpendUSD(usage);
    return { trip: estimate >= cap, estimateUSD: estimate, capUSD: cap };
}
/** The flags doc (`appConfig/flags`). Features gated on the release gate
 *  stay off whatever the doc says until `releaseGateCleared` is true here
 *  in code - a stray console edit can't turn on cloud video. */
exports.releaseGateCleared = false;
exports.gatedFeatures = ["cloudClips", "fullGameVideo", "viewerPass", "contentSafety"];
function featureEnabled(flags, feature) {
    if (!flags || flags.killSwitch === true) {
        // The kill switch degrades to scoring only; interim sharing is on-device and stays.
        return feature === "interimClipSharing" && (!flags || flags.interimClipSharing !== false);
    }
    if (exports.gatedFeatures.includes(feature) && !exports.releaseGateCleared)
        return false;
    if (feature === "interimClipSharing")
        return flags.interimClipSharing !== false;
    return flags[feature] === true;
}
