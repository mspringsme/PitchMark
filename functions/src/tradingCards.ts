// Trading cards (2026-11-19): a family's own pack of their player's card,
// and a team set - an organizer gathers every family's card and buys one
// set (one card of every player) per family, shipped to the organizer.
// Kept free of Firebase so it can be tested on its own. The app twin is
// PitchMark/TradingCard.swift - keep sizes and prices identical.
//
// Team sets live at teams/{teamId}/cardSets/{setId} with an entry per card
// (entries/{entryId}, owned by ownerUid - a family may add several, one per
// player); each entry's art is cardArt/{teamId}/{setId}/{ownerUid}/{entryId}-front|back.
// The rules freeze entries and art once the organizer locks the set; at
// checkout the server copies the locked art into the order's own folder, so
// what prints is what was locked.

export const tradingCardProducts = {
    card_family_12: { itemKind: "cardFamilyPack", quantity: 12, unitAmountCents: 1499 },
    card_family_24: { itemKind: "cardFamilyPack", quantity: 24, unitAmountCents: 1999 },
    card_team_set: { itemKind: "cardTeamSet", quantity: 0, unitAmountCents: 1299 }
} as const;

export type TradingCardProductId = keyof typeof tradingCardProducts;

export const teamSetLimits = {
    minPlayers: 2,
    maxPlayers: 40,
    minSets: 1,
    maxSets: 60
} as const;

const idPattern = /^[A-Za-z0-9_-]{1,128}$/;
const orderKeyPattern = "[A-Za-z0-9._-]{8,80}";

function escapeRegex(value: string): string {
    return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** A family pack: the card's two sides, uploaded for this order only. */
export function resolveFamilyPackRequest(
    uid: string,
    retailProductId: string,
    frontPath: unknown,
    backPath: unknown
): { ok: true; value: { quantity: number; frontPath: string; backPath: string; priceCents: number } } | { ok: false; message: string } {
    const product = tradingCardProducts[retailProductId as TradingCardProductId];
    if (!product || product.itemKind !== "cardFamilyPack") {
        return { ok: false, message: "A family pack is 12 or 24 cards." };
    }
    const pattern = (side: string) =>
        new RegExp(`^bookUploads/${escapeRegex(uid)}/${orderKeyPattern}/card-${side}\\.(png|jpg)$`);
    if (typeof frontPath !== "string" || !pattern("front").test(frontPath)
        || typeof backPath !== "string" || !pattern("back").test(backPath)) {
        return { ok: false, message: "The card's upload is missing or isn't yours." };
    }
    const folder = (path: string) => path.slice(0, path.lastIndexOf("/"));
    if (folder(frontPath) !== folder(backPath)) {
        return { ok: false, message: "The card's two sides must be one order." };
    }
    return { ok: true, value: { quantity: product.quantity, frontPath, backPath, priceCents: product.unitAmountCents } };
}

export type TeamSetEntry = { id: string; ownerUid?: unknown; consent?: unknown; frontPath?: unknown; backPath?: unknown };
export type TeamSet = { organizerUid?: unknown; status?: unknown };

/**
 * A team set order. Priced here from the locked set's entries and the number
 * of sets - never from the app. Only the organizer, only a locked set, only
 * entries with consent and both sides.
 */
export function planTeamSetOrder(input: {
    uid: string;
    teamId: unknown;
    setId: unknown;
    setCount: unknown;
    set: TeamSet | null;
    entries: TeamSetEntry[];
}): { ok: true; value: { teamId: string; setId: string; setCount: number; players: string[]; priceCents: number } } | { ok: false; message: string } {
    const { uid, set } = input;
    if (typeof input.teamId !== "string" || !idPattern.test(input.teamId)
        || typeof input.setId !== "string" || !idPattern.test(input.setId)) {
        return { ok: false, message: "Pick a team card set." };
    }
    if (!set) {
        return { ok: false, message: "That card set doesn't exist." };
    }
    if (set.organizerUid !== uid) {
        return { ok: false, message: "Only the set's organizer can order it." };
    }
    if (set.status !== "locked") {
        return { ok: false, message: set.status === "ordered" ? "This set was already ordered." : "Lock the set before ordering." };
    }
    const setCount = input.setCount;
    if (typeof setCount !== "number" || !Number.isInteger(setCount)
        || setCount < teamSetLimits.minSets || setCount > teamSetLimits.maxSets) {
        return { ok: false, message: `Order ${teamSetLimits.minSets} to ${teamSetLimits.maxSets} sets.` };
    }
    const ready = input.entries.filter((entry) =>
        entry.consent === true
        && typeof entry.ownerUid === "string" && entry.ownerUid.length > 0
        && typeof entry.frontPath === "string" && entry.frontPath.length > 0
        && typeof entry.backPath === "string" && entry.backPath.length > 0);
    if (ready.length < teamSetLimits.minPlayers) {
        return { ok: false, message: `A team set needs at least ${teamSetLimits.minPlayers} players' cards.` };
    }
    if (ready.length > teamSetLimits.maxPlayers) {
        return { ok: false, message: `A team set holds up to ${teamSetLimits.maxPlayers} players.` };
    }
    return {
        ok: true,
        value: {
            teamId: input.teamId,
            setId: input.setId,
            setCount,
            players: ready.map((entry) => entry.id).sort(),
            priceCents: setCount * tradingCardProducts.card_team_set.unitAmountCents
        }
    };
}

/** Where a locked entry's art is copied for the order (what prints). */
export function frozenArtPath(orderKey: string, entryId: string, side: "front" | "back", sourcePath: string): string {
    const extension = sourcePath.toLowerCase().endsWith(".jpg") || sourcePath.toLowerCase().endsWith(".jpeg") ? "jpg" : "png";
    return `cardOrders/${orderKey}/${entryId}-${side}.${extension}`;
}

/** The entry's art must be its own, in its owner's folder of this set. */
export function isEntryArtPath(teamId: string, setId: string, ownerUid: string, entryId: string, path: unknown): path is string {
    if (typeof path !== "string") {
        return false;
    }
    const pattern = new RegExp(
        `^cardArt/${escapeRegex(teamId)}/${escapeRegex(setId)}/${escapeRegex(ownerUid)}/${escapeRegex(entryId)}-(front|back)\\.(png|jpg)$`
    );
    return pattern.test(path);
}
