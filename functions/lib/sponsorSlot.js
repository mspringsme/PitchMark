"use strict";
// Team Sponsor slots: a team sells a season sponsorship to a local business
// itself; the coach then buys the slot that shows it in PitchMark. Kept free
// of Firebase so it can be tested on its own. The app twin is
// PitchMark/SponsorSlot.swift - keep the limits identical.
//
// Only the server creates a slot, and only after payment. The document holds
// what's shown (name, link, logo), whose team it is, its dates, and who paid -
// never anything about the team's players or families.
Object.defineProperty(exports, "__esModule", { value: true });
exports.sponsorLimits = exports.sponsorSlotProduct = void 0;
exports.validateSponsorSnapshot = validateSponsorSnapshot;
exports.sponsorSlotDocument = sponsorSlotDocument;
exports.planSlotActivation = planSlotActivation;
exports.sponsorSlotProduct = {
    retailProductId: "team_sponsor_season",
    itemKind: "sponsorSlot",
    label: "Team Sponsor (One Season)",
    unitAmountCents: 2500,
    durationDays: 183
};
exports.sponsorLimits = {
    nameMax: 60,
    linkMax: 200,
    /** Base64 of a small JPEG/PNG, resized in the app. Must fit the 120k-character checkout snapshot. */
    logoMax: 100_000
};
const teamIdPattern = /^[A-Za-z0-9_-]{1,128}$/;
const base64Pattern = /^[A-Za-z0-9+/]+={0,2}$/;
function validateSponsorSnapshot(json) {
    if (typeof json !== "string" || json.length === 0) {
        return { ok: false, message: "The sponsor's details are missing." };
    }
    let parsed;
    try {
        parsed = JSON.parse(json);
    }
    catch {
        return { ok: false, message: "The sponsor's details couldn't be read." };
    }
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
        return { ok: false, message: "The sponsor's details couldn't be read." };
    }
    const data = parsed;
    const teamId = typeof data.teamId === "string" ? data.teamId : "";
    const name = typeof data.name === "string" ? data.name.trim() : "";
    const link = typeof data.link === "string" ? data.link.trim() : "";
    const logo = typeof data.logo === "string" ? data.logo : "";
    if (!teamIdPattern.test(teamId)) {
        return { ok: false, message: "Pick a team for the sponsor." };
    }
    if (name.length === 0 || name.length > exports.sponsorLimits.nameMax) {
        return { ok: false, message: `The sponsor's name is 1 to ${exports.sponsorLimits.nameMax} characters.` };
    }
    if (link.length > 0 && (link.length > exports.sponsorLimits.linkMax || !isHttpsUrl(link))) {
        return { ok: false, message: "The sponsor's link must be an https web address." };
    }
    if (logo.length > exports.sponsorLimits.logoMax || (logo.length > 0 && !base64Pattern.test(logo))) {
        return { ok: false, message: "The sponsor's logo is too large." };
    }
    return { ok: true, value: { teamId, name, link, logo } };
}
function isHttpsUrl(value) {
    try {
        const url = new URL(value);
        return url.protocol === "https:" && url.hostname.length > 0;
    }
    catch {
        return false;
    }
}
function sponsorSlotDocument(snapshot, input) {
    const endsAt = new Date(input.startsAt.getTime() + exports.sponsorSlotProduct.durationDays * 86_400_000);
    return {
        teamId: snapshot.teamId,
        name: snapshot.name,
        link: snapshot.link,
        logo: snapshot.logo,
        startsAt: input.startsAt,
        endsAt,
        purchasedByUid: input.purchasedByUid,
        orderId: input.orderId
    };
}
/** `activate` only when paid and the slot doesn't exist yet (webhook retries). */
function planSlotActivation(order) {
    if (order.itemKind !== exports.sponsorSlotProduct.itemKind || order.slotExists) {
        return "skip";
    }
    if (order.fulfillmentState === "async_payment_failed" || order.paymentStatus !== "paid") {
        return "hold";
    }
    return "activate";
}
