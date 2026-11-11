// Runs against the compiled module: `npm test` builds first.
const test = require("node:test");
const assert = require("node:assert/strict");
const {
    resolveGridKeyPrintSize,
    printSizeFromMetadata,
    isValidCustomSize
} = require("../lib/gridKeyPrintSize.js");

test("standard products print at their own size, whatever the client sent", () => {
    assert.deepEqual(resolveGridKeyPrintSize("grid_5x3", undefined, undefined),
        { ok: true, size: { widthInches: 5, heightInches: 3 } });
    assert.deepEqual(resolveGridKeyPrintSize("grid_3_5x2_75", 7, 5),
        { ok: true, size: { widthInches: 3.5, heightInches: 2.75 } });
});

test("the printed sheet has no card size", () => {
    assert.deepEqual(resolveGridKeyPrintSize("sheet_8_5x11", undefined, undefined), { ok: true, size: null });
});

test("a custom order prints at the requested size", () => {
    assert.deepEqual(resolveGridKeyPrintSize("grid_custom", 4.25, 2.5),
        { ok: true, size: { widthInches: 4.25, heightInches: 2.5 } });
    assert.deepEqual(resolveGridKeyPrintSize("grid_custom", 3, 2),
        { ok: true, size: { widthInches: 3, heightInches: 2 } });
    assert.deepEqual(resolveGridKeyPrintSize("grid_custom", 7, 5),
        { ok: true, size: { widthInches: 7, heightInches: 5 } });
});

test("a custom order with no size is refused (old app builds)", () => {
    const result = resolveGridKeyPrintSize("grid_custom", undefined, undefined);
    assert.equal(result.ok, false);
    assert.match(result.message, /Update PitchMark/);
    assert.equal(resolveGridKeyPrintSize("grid_custom", null, null).ok, false);
});

test("a custom size out of range, off the quarter inch, or half-given is refused", () => {
    const bad = [[2.75, 3], [7.25, 3], [4, 1.75], [4, 5.25], [4.1, 3], [4, 2.6],
        [4, undefined], ["4", "3"], [NaN, 3], [Infinity, 3]];
    for (const [w, h] of bad) {
        assert.equal(resolveGridKeyPrintSize("grid_custom", w, h).ok, false, `${w} x ${h}`);
    }
});

test("every quarter inch in range is valid", () => {
    for (let w = 3; w <= 7; w += 0.25) {
        for (let h = 2; h <= 5; h += 0.25) {
            assert.ok(isValidCustomSize({ widthInches: w, heightInches: h }), `${w} x ${h}`);
        }
    }
});

test("the order reads the size back off the session metadata", () => {
    assert.deepEqual(printSizeFromMetadata({ printWidthInches: "4.25", printHeightInches: "2.5" }),
        { widthInches: 4.25, heightInches: 2.5 });
    assert.equal(printSizeFromMetadata({}), null);
    assert.equal(printSizeFromMetadata({ printWidthInches: "4.25" }), null);
    assert.equal(printSizeFromMetadata({ printWidthInches: "abc", printHeightInches: "2" }), null);
    assert.equal(printSizeFromMetadata({ printWidthInches: "0", printHeightInches: "2" }), null);
});

// Batter & Runner Grid (2026-11-08): sized like a custom key.
const { retailCatalog, allowedItemKinds } = require("../lib/retailCatalog.js");

test("a Batter & Runner Grid prints at the requested size", () => {
    assert.deepEqual(resolveGridKeyPrintSize("sign_grid_custom", 4.25, 2.5),
        { ok: true, size: { widthInches: 4.25, heightInches: 2.5 } });
    assert.deepEqual(resolveGridKeyPrintSize("sign_grid_custom", 7, 5),
        { ok: true, size: { widthInches: 7, heightInches: 5 } });
});

test("a Batter & Runner Grid with no size or a bad size is refused", () => {
    assert.equal(resolveGridKeyPrintSize("sign_grid_custom", undefined, undefined).ok, false);
    for (const [w, h] of [[2.75, 3], [7.25, 3], [4, 1.75], [4, 5.25], [4.1, 3], ["4", "3"], [4, undefined]]) {
        assert.equal(resolveGridKeyPrintSize("sign_grid_custom", w, h).ok, false, `${w} x ${h}`);
    }
});

test("the store sells the Batter & Runner Grid at $20, priced in code", () => {
    assert.deepEqual(retailCatalog.sign_grid_custom,
        { priceId: "", label: "Batter & Runner Grid", unitAmountCents: 2000 });
    assert.ok(allowedItemKinds.has("signGrid"));
    assert.ok(allowedItemKinds.has("gridKey"));
    assert.ok(allowedItemKinds.has("printableSheet"));
});
