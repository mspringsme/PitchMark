// Cost guardrails (approved 2026-11-24, clip brief phase 2):
//   3 each quota refusal at its edge, bad input refused; stream time = the
//     lesser of 3 h and the month's remainder; 40-viewer cap; the breaker
//     trips at the cap and falls back to $20
//   1 (server twin) gated features stay off whatever the flags doc says;
//     the kill switch leaves only interim sharing
// Runs against the compiled module: `npm test` builds first.
const test = require("node:test");
const assert = require("node:assert/strict");
const {
    clipLimits,
    streamLimits,
    checkClipQuota,
    checkStream,
    estimateDailySpendUSD,
    circuitBreaker,
    defaultDailySpendCapUSD,
    featureEnabled
} = require("../lib/guardrails.js");

const usage = (over = {}) => ({ personGameClips: 0, personGameSeconds: 0, teamDayClips: 0, teamMonthClips: 0, ...over });
const clip = (over = {}) => ({ seconds: 30, bytes: 9 * 1024 * 1024, ...over });

test("a normal clip is allowed", () => {
    assert.deepEqual(checkClipQuota(usage(), clip()), { ok: true });
});

test("clip length: 60 s allowed, 61 s refused", () => {
    assert.equal(checkClipQuota(usage(), clip({ seconds: 60 })).ok, true);
    assert.deepEqual(checkClipQuota(usage(), clip({ seconds: 61 })), { ok: false, reason: "clipTooLong" });
});

test("clip size: at the cap allowed, one byte over refused", () => {
    assert.equal(checkClipQuota(usage(), clip({ bytes: clipLimits.maxClipBytes })).ok, true);
    assert.deepEqual(checkClipQuota(usage(), clip({ bytes: clipLimits.maxClipBytes + 1 })), { ok: false, reason: "clipTooLarge" });
});

test("per person per game: 25th clip allowed, 26th refused", () => {
    assert.equal(checkClipQuota(usage({ personGameClips: 24 }), clip()).ok, true);
    assert.deepEqual(checkClipQuota(usage({ personGameClips: 25 }), clip()), { ok: false, reason: "personGameClips" });
});

test("per person per game: 10 minutes total", () => {
    assert.equal(checkClipQuota(usage({ personGameSeconds: 570 }), clip({ seconds: 30 })).ok, true);
    assert.deepEqual(checkClipQuota(usage({ personGameSeconds: 571 }), clip({ seconds: 30 })), { ok: false, reason: "personGameSeconds" });
});

test("per team per day and per month", () => {
    assert.equal(checkClipQuota(usage({ teamDayClips: clipLimits.perTeamPerDayClips - 1 }), clip()).ok, true);
    assert.deepEqual(checkClipQuota(usage({ teamDayClips: clipLimits.perTeamPerDayClips }), clip()), { ok: false, reason: "teamDayClips" });
    assert.equal(checkClipQuota(usage({ teamMonthClips: clipLimits.perTeamPerMonthClips - 1 }), clip()).ok, true);
    assert.deepEqual(checkClipQuota(usage({ teamMonthClips: clipLimits.perTeamPerMonthClips }), clip()), { ok: false, reason: "teamMonthClips" });
});

test("bad input is refused", () => {
    for (const bad of [clip({ seconds: 0 }), clip({ bytes: -1 }), clip({ seconds: NaN }), clip({ seconds: "30" })]) {
        assert.deepEqual(checkClipQuota(usage(), bad), { ok: false, reason: "invalidRequest" });
    }
    assert.deepEqual(checkClipQuota(usage({ teamDayClips: -5 }), clip()), { ok: false, reason: "invalidRequest" });
});

test("stream time is the lesser of 3 h and the month's remainder", () => {
    assert.deepEqual(checkStream({ teamMonthStreamSeconds: 0, activeViewers: 0 }, false), { ok: true, maxSeconds: streamLimits.maxStreamSeconds });
    const used = streamLimits.perTeamPerMonthStreamHours * 3600 - 1800;
    assert.deepEqual(checkStream({ teamMonthStreamSeconds: used, activeViewers: 0 }, false), { ok: true, maxSeconds: 1800 });
    assert.deepEqual(checkStream({ teamMonthStreamSeconds: used + 1800, activeViewers: 0 }, false), { ok: false, reason: "teamMonthHours" });
});

test("40-viewer cap", () => {
    assert.equal(checkStream({ teamMonthStreamSeconds: 0, activeViewers: 39 }, true).ok, true);
    assert.deepEqual(checkStream({ teamMonthStreamSeconds: 0, activeViewers: 40 }, true), { ok: false, reason: "viewerCap" });
    assert.deepEqual(checkStream({ teamMonthStreamSeconds: -1, activeViewers: 0 }, false), { ok: false, reason: "invalidRequest" });
});

test("spend estimate adds the parts and ignores nonsense", () => {
    const est = estimateDailySpendUSD({ storedGB: 30, deliveredMinutes: 1000, streamStoredMinutes: 0, moderatedMinutes: 100 });
    assert.ok(Math.abs(est - (30 * 0.015 / 30 + 1 + 1)) < 1e-9);
    assert.equal(estimateDailySpendUSD({ storedGB: -5, deliveredMinutes: NaN, streamStoredMinutes: 0, moderatedMinutes: 0 }), 0);
});

test("the breaker trips at the cap, not below", () => {
    assert.equal(circuitBreaker({ storedGB: 0, deliveredMinutes: 19_999, streamStoredMinutes: 0, moderatedMinutes: 0 }, 20).trip, false);
    assert.equal(circuitBreaker({ storedGB: 0, deliveredMinutes: 20_000, streamStoredMinutes: 0, moderatedMinutes: 0 }, 20).trip, true);
});

test("a missing or bad cap falls back to $20", () => {
    for (const cap of [undefined, 0, -3, NaN]) {
        assert.equal(circuitBreaker({ storedGB: 0, deliveredMinutes: 0, streamStoredMinutes: 0, moderatedMinutes: 0 }, cap).capUSD, defaultDailySpendCapUSD);
    }
    assert.equal(defaultDailySpendCapUSD, 20);
});

test("gated features stay off whatever the doc says", () => {
    const all = { cloudClips: true, fullGameVideo: true, viewerPass: true, contentSafety: true, gameFeeds: true, followAlerts: true };
    for (const f of ["cloudClips", "fullGameVideo", "viewerPass", "contentSafety"]) assert.equal(featureEnabled(all, f), false, f);
    assert.equal(featureEnabled(all, "gameFeeds"), true);
    assert.equal(featureEnabled(all, "interimClipSharing"), true);
});

test("no doc or the kill switch leaves only interim sharing", () => {
    for (const flags of [undefined, { gameFeeds: true, killSwitch: true }]) {
        assert.equal(featureEnabled(flags, "gameFeeds"), false);
        assert.equal(featureEnabled(flags, "followAlerts"), false);
        assert.equal(featureEnabled(flags, "interimClipSharing"), true);
    }
    assert.equal(featureEnabled({ interimClipSharing: false, killSwitch: true }, "interimClipSharing"), false);
});
