// Runs against the compiled module: `npm test` builds first.
const test = require("node:test");
const assert = require("node:assert/strict");
const { retailCatalog, allowedItemKinds } = require("../lib/retailCatalog.js");
const { resolveGridKeyPrintSize } = require("../lib/gridKeyPrintSize.js");

test("waterproof calling cards are $8, priced in code (2026-11-10)", () => {
    const item = retailCatalog.calling_card_waterproof;
    assert.ok(item, "missing from the catalog");
    assert.equal(item.unitAmountCents, 800);
    assert.equal(item.priceId, "");
    assert.ok(allowedItemKinds.has("signGrid"), "the card's design rides as a signGrid");
});

test("waterproof calling cards don't ask for a size", () => {
    assert.deepEqual(resolveGridKeyPrintSize("calling_card_waterproof", undefined, undefined), { ok: true, size: null });
    assert.deepEqual(resolveGridKeyPrintSize("calling_card_waterproof", 7, 5), { ok: true, size: null });
});
