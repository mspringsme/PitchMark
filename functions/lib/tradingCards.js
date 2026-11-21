"use strict";
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
Object.defineProperty(exports, "__esModule", { value: true });
exports.teamSetLimits = exports.tradingCardProducts = void 0;
exports.resolveFamilyPackRequest = resolveFamilyPackRequest;
exports.planTeamSetOrder = planTeamSetOrder;
exports.frozenArtPath = frozenArtPath;
exports.isEntryArtPath = isEntryArtPath;
exports.tradingCardProducts = {
    card_family_12: { itemKind: "cardFamilyPack", quantity: 12, unitAmountCents: 1499 },
    card_family_24: { itemKind: "cardFamilyPack", quantity: 24, unitAmountCents: 1999 },
    card_team_set: { itemKind: "cardTeamSet", quantity: 0, unitAmountCents: 1299 }
};
exports.teamSetLimits = {
    minPlayers: 2,
    maxPlayers: 40,
    minSets: 1,
    maxSets: 60
};
const idPattern = /^[A-Za-z0-9_-]{1,128}$/;
const orderKeyPattern = "[A-Za-z0-9._-]{8,80}";
function escapeRegex(value) {
    return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
/** A family pack: the card's two sides, uploaded for this order only. */
function resolveFamilyPackRequest(uid, retailProductId, frontPath, backPath) {
    const product = exports.tradingCardProducts[retailProductId];
    if (!product || product.itemKind !== "cardFamilyPack") {
        return { ok: false, message: "A family pack is 12 or 24 cards." };
    }
    const pattern = (side) => new RegExp(`^bookUploads/${escapeRegex(uid)}/${orderKeyPattern}/card-${side}\\.(png|jpg)$`);
    if (typeof frontPath !== "string" || !pattern("front").test(frontPath)
        || typeof backPath !== "string" || !pattern("back").test(backPath)) {
        return { ok: false, message: "The card's upload is missing or isn't yours." };
    }
    const folder = (path) => path.slice(0, path.lastIndexOf("/"));
    if (folder(frontPath) !== folder(backPath)) {
        return { ok: false, message: "The card's two sides must be one order." };
    }
    return { ok: true, value: { quantity: product.quantity, frontPath, backPath, priceCents: product.unitAmountCents } };
}
/**
 * A team set order. Priced here from the locked set's entries and the number
 * of sets - never from the app. Only the organizer, only a locked set, only
 * entries with consent and both sides.
 */
function planTeamSetOrder(input) {
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
        || setCount < exports.teamSetLimits.minSets || setCount > exports.teamSetLimits.maxSets) {
        return { ok: false, message: `Order ${exports.teamSetLimits.minSets} to ${exports.teamSetLimits.maxSets} sets.` };
    }
    const ready = input.entries.filter((entry) => entry.consent === true
        && typeof entry.ownerUid === "string" && entry.ownerUid.length > 0
        && typeof entry.frontPath === "string" && entry.frontPath.length > 0
        && typeof entry.backPath === "string" && entry.backPath.length > 0);
    if (ready.length < exports.teamSetLimits.minPlayers) {
        return { ok: false, message: `A team set needs at least ${exports.teamSetLimits.minPlayers} players' cards.` };
    }
    if (ready.length > exports.teamSetLimits.maxPlayers) {
        return { ok: false, message: `A team set holds up to ${exports.teamSetLimits.maxPlayers} players.` };
    }
    return {
        ok: true,
        value: {
            teamId: input.teamId,
            setId: input.setId,
            setCount,
            players: ready.map((entry) => entry.id).sort(),
            priceCents: setCount * exports.tradingCardProducts.card_team_set.unitAmountCents
        }
    };
}
/** Where a locked entry's art is copied for the order (what prints). */
function frozenArtPath(orderKey, entryId, side, sourcePath) {
    const extension = sourcePath.toLowerCase().endsWith(".jpg") || sourcePath.toLowerCase().endsWith(".jpeg") ? "jpg" : "png";
    return `cardOrders/${orderKey}/${entryId}-${side}.${extension}`;
}
/** The entry's art must be its own, in its owner's folder of this set. */
function isEntryArtPath(teamId, setId, ownerUid, entryId, path) {
    if (typeof path !== "string") {
        return false;
    }
    const pattern = new RegExp(`^cardArt/${escapeRegex(teamId)}/${escapeRegex(setId)}/${escapeRegex(ownerUid)}/${escapeRegex(entryId)}-(front|back)\\.(png|jpg)$`);
    return pattern.test(path);
}
