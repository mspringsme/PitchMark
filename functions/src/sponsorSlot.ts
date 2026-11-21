// Team Sponsor slots: a team sells a season sponsorship to a local business
// itself; the coach then buys the slot that shows it in PitchMark. Kept free
// of Firebase so it can be tested on its own. The app twin is
// PitchMark/SponsorSlot.swift - keep the limits identical.
//
// Only the server creates a slot, and only after payment. The document holds
// what's shown (name, link, logo), whose team it is, its dates, and who paid -
// never anything about the team's players or families.

export const sponsorSlotProduct = {
    retailProductId: "team_sponsor_season",
    itemKind: "sponsorSlot",
    label: "Team Sponsor (One Season)",
    unitAmountCents: 2500,
    durationDays: 183
} as const;

export const sponsorLimits = {
    nameMax: 60,
    linkMax: 200,
    /** Base64 of a small JPEG/PNG, resized in the app. Must fit the 120k-character checkout snapshot. */
    logoMax: 100_000
} as const;

const teamIdPattern = /^[A-Za-z0-9_-]{1,128}$/;
const base64Pattern = /^[A-Za-z0-9+/]+={0,2}$/;

export type SponsorSnapshot = { teamId: string; name: string; link: string; logo: string };

export function validateSponsorSnapshot(json: unknown): { ok: true; value: SponsorSnapshot } | { ok: false; message: string } {
    if (typeof json !== "string" || json.length === 0) {
        return { ok: false, message: "The sponsor's details are missing." };
    }
    let parsed: unknown;
    try {
        parsed = JSON.parse(json);
    } catch {
        return { ok: false, message: "The sponsor's details couldn't be read." };
    }
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
        return { ok: false, message: "The sponsor's details couldn't be read." };
    }
    const data = parsed as Record<string, unknown>;
    const teamId = typeof data.teamId === "string" ? data.teamId : "";
    const name = typeof data.name === "string" ? data.name.trim() : "";
    const link = typeof data.link === "string" ? data.link.trim() : "";
    const logo = typeof data.logo === "string" ? data.logo : "";

    if (!teamIdPattern.test(teamId)) {
        return { ok: false, message: "Pick a team for the sponsor." };
    }
    if (name.length === 0 || name.length > sponsorLimits.nameMax) {
        return { ok: false, message: `The sponsor's name is 1 to ${sponsorLimits.nameMax} characters.` };
    }
    if (link.length > 0 && (link.length > sponsorLimits.linkMax || !isHttpsUrl(link))) {
        return { ok: false, message: "The sponsor's link must be an https web address." };
    }
    if (logo.length > sponsorLimits.logoMax || (logo.length > 0 && !base64Pattern.test(logo))) {
        return { ok: false, message: "The sponsor's logo is too large." };
    }
    return { ok: true, value: { teamId, name, link, logo } };
}

function isHttpsUrl(value: string): boolean {
    try {
        const url = new URL(value);
        return url.protocol === "https:" && url.hostname.length > 0;
    } catch {
        return false;
    }
}

export function sponsorSlotDocument(
    snapshot: SponsorSnapshot,
    input: { purchasedByUid: string; orderId: string; startsAt: Date }
): Record<string, unknown> {
    const endsAt = new Date(input.startsAt.getTime() + sponsorSlotProduct.durationDays * 86_400_000);
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
export function planSlotActivation(order: {
    itemKind?: unknown;
    paymentStatus?: unknown;
    fulfillmentState?: unknown;
    slotExists: boolean;
}): "activate" | "skip" | "hold" {
    if (order.itemKind !== sponsorSlotProduct.itemKind || order.slotExists) {
        return "skip";
    }
    if (order.fulfillmentState === "async_payment_failed" || order.paymentStatus !== "paid") {
        return "hold";
    }
    return "activate";
}
