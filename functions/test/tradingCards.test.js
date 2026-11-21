// Trading cards server rules (approved 2026-11-19):
//   S1 a team order's price is computed here from the locked set's entries
//      and the number of sets; the set must be locked, have 2+ players, and
//      only its organizer can order it
//   S2 family packs are 12 or 24 cards, priced in code
//   S3 what prints is the art frozen at lock time (copied into the order's
//      own folder, from each entry's own art only)
//   S4 never print twice  [high risk - broken on purpose to prove the test]
// Runs against the compiled module: `npm test` builds first.
const test = require("node:test");
const assert = require("node:assert/strict");
const {
    tradingCardProducts,
    teamSetLimits,
    resolveFamilyPackRequest,
    planTeamSetOrder,
    frozenArtPath,
    isEntryArtPath
} = require("../lib/tradingCards.js");
const { planPrintSubmission } = require("../lib/seasonBook.js");
const { retailCatalog, requiredItemKindByProduct, digitalProductIds } = require("../lib/retailCatalog.js");

const UID = "parentUid";
const KEY = "order-key-0001";
// One entry per card; a family (ownerUid) may own several - siblings.
const art = (ownerUid, entryId, side) => `cardArt/team_1/set_1/${ownerUid}/${entryId}-${side}.png`;
const entry = (id, over = {}) => {
    const ownerUid = over.ownerUid ?? `owner_${id}`;
    return { id, ownerUid, consent: true, frontPath: art(ownerUid, id, "front"), backPath: art(ownerUid, id, "back"), ...over };
};
const plan = (over = {}) => planTeamSetOrder({
    uid: UID,
    teamId: "team_1",
    setId: "set_1",
    setCount: 13,
    set: { organizerUid: UID, status: "locked" },
    entries: [entry("a"), entry("b"), entry("c")],
    ...over
});

test("S1 a team order is priced per set, from the server's own count", () => {
    const result = plan();
    assert.equal(result.ok, true);
    assert.equal(result.value.priceCents, 13 * 1299);
    assert.deepEqual(result.value.players, ["a", "b", "c"]);
    // The function takes no price: nothing the app sends is a price.
    assert.equal(plan({ setCount: 1 }).value.priceCents, 1299);
});

test("S1 only the organizer, only a locked set", () => {
    assert.equal(plan({ uid: "someoneElse" }).ok, false);
    assert.equal(plan({ set: { organizerUid: UID, status: "open" } }).ok, false);
    assert.equal(plan({ set: { organizerUid: UID, status: "ordered" } }).ok, false);
    assert.equal(plan({ set: null }).ok, false);
});

test("S1 siblings: one family's two cards are both printed", () => {
    const result = plan({ entries: [entry("ava", { ownerUid: "smiths" }), entry("bea", { ownerUid: "smiths" })] });
    assert.equal(result.ok, true);
    assert.deepEqual(result.value.players, ["ava", "bea"]);
});

test("S1 an entry with no owner never prints", () => {
    const result = plan({ entries: [entry("a"), entry("b"), entry("c", { ownerUid: "" })] });
    assert.deepEqual(result.value.players, ["a", "b"]);
});

test("S1 at least 2 players with consent and both sides", () => {
    assert.equal(plan({ entries: [entry("a")] }).ok, false);
    assert.equal(plan({ entries: [entry("a"), entry("b", { consent: false })] }).ok, false);
    assert.equal(plan({ entries: [entry("a"), entry("b", { backPath: "" })] }).ok, false);
    const partial = plan({ entries: [entry("a"), entry("b"), entry("c", { consent: "yes" })] });
    assert.deepEqual(partial.value.players, ["a", "b"], "an entry without real consent was printed");
    const tooMany = Array.from({ length: teamSetLimits.maxPlayers + 1 }, (_, i) => entry(`p${i}`));
    assert.equal(plan({ entries: tooMany }).ok, false);
});

test("S1 set count is 1 to 60 whole sets", () => {
    for (const bad of [0, -1, 61, 2.5, "13", null]) {
        assert.equal(plan({ setCount: bad }).ok, false, `accepted ${String(bad)} sets`);
    }
    assert.equal(plan({ setCount: 60 }).ok, true);
});

test("S1 ids must be plain ids", () => {
    assert.equal(plan({ teamId: "../users/x" }).ok, false);
    assert.equal(plan({ setId: "" }).ok, false);
});

test("S2 family packs are 12 or 24, priced in code", () => {
    const front = `bookUploads/${UID}/${KEY}/card-front.png`;
    const back = `bookUploads/${UID}/${KEY}/card-back.png`;
    const twelve = resolveFamilyPackRequest(UID, "card_family_12", front, back);
    assert.equal(twelve.ok && twelve.value.quantity, 12);
    assert.equal(twelve.ok && twelve.value.priceCents, 1499);
    const twentyFour = resolveFamilyPackRequest(UID, "card_family_24", front, back);
    assert.equal(twentyFour.ok && twentyFour.value.priceCents, 1999);
    assert.equal(resolveFamilyPackRequest(UID, "card_team_set", front, back).ok, false);
    assert.equal(resolveFamilyPackRequest(UID, "card_family_100", front, back).ok, false);
    assert.equal(retailCatalog.card_family_12.unitAmountCents, tradingCardProducts.card_family_12.unitAmountCents);
    assert.equal(retailCatalog.card_family_24.unitAmountCents, tradingCardProducts.card_family_24.unitAmountCents);
    assert.equal(retailCatalog.card_team_set.unitAmountCents, 1299);
    assert.equal(requiredItemKindByProduct.card_team_set, "cardTeamSet");
    assert.ok(!digitalProductIds.has("card_family_12"), "cards ship");
});

test("S2 a family pack's sides are the caller's own, from one order", () => {
    const mine = (side, key = KEY) => `bookUploads/${UID}/${key}/card-${side}.png`;
    assert.equal(resolveFamilyPackRequest(UID, "card_family_12", mine("front"), `bookUploads/other/${KEY}/card-back.png`).ok, false);
    assert.equal(resolveFamilyPackRequest(UID, "card_family_12", mine("front"), mine("back", "order-key-0002")).ok, false);
    assert.equal(resolveFamilyPackRequest(UID, "card_family_12", mine("back"), mine("front")).ok, false);
    assert.equal(resolveFamilyPackRequest(UID, "card_family_12", mine("front"), undefined).ok, false);
});

test("S3 what prints is copied into the order's own folder, from each entry's own art", () => {
    assert.equal(frozenArtPath(KEY, "ava", "front", art("smiths", "ava", "front")), `cardOrders/${KEY}/ava-front.png`);
    assert.equal(frozenArtPath(KEY, "ava", "back", "cardArt/team_1/set_1/smiths/ava-back.jpg"), `cardOrders/${KEY}/ava-back.jpg`);
    assert.equal(isEntryArtPath("team_1", "set_1", "smiths", "ava", art("smiths", "ava", "front")), true);
    assert.equal(isEntryArtPath("team_1", "set_1", "smiths", "ava", art("jones", "ava", "front")), false, "another family's folder");
    assert.equal(isEntryArtPath("team_1", "set_1", "smiths", "ava", art("smiths", "bea", "front")), false, "a sibling's card");
    assert.equal(isEntryArtPath("team_1", "set_1", "smiths", "ava", "cardArt/team_2/set_1/smiths/ava-front.png"), false, "another team");
    assert.equal(isEntryArtPath("team_1", "set_1", "smiths", "ava", "cardArt/team_1/set_1/smiths/../jones/ava-front.png"), false);
    assert.equal(isEntryArtPath("team_1", "set_1", "smiths", "ava", undefined), false);
});

// A stand-in for the webhook, as in seasonBook.test.js.
function deliver(order, events) {
    let prints = 0;
    for (const event of events) {
        order.fulfillmentState = event.state;
        order.paymentStatus = event.paymentStatus;
        if (planPrintSubmission(order) === "submit") {
            order.printSubmission = { state: "awaiting_manual" };
            prints += 1;
        }
    }
    return prints;
}

test("S4 HIGH RISK: a card order is never printed twice", () => {
    const paid = { state: "completed", paymentStatus: "paid" };
    for (const itemKind of ["cardFamilyPack", "cardTeamSet"]) {
        assert.equal(deliver({ itemKind }, [paid, paid, paid]), 1, `${itemKind}: a retry printed again`);
        assert.equal(deliver({ itemKind }, [
            { state: "completed", paymentStatus: "unpaid" },
            { state: "async_payment_succeeded", paymentStatus: "paid" },
            { state: "async_payment_succeeded", paymentStatus: "paid" }
        ]), 1, `${itemKind}: the async success printed twice`);
        assert.equal(deliver({ itemKind }, [{ state: "async_payment_failed", paymentStatus: "unpaid" }]), 0);
    }
});
