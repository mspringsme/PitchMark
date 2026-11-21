// Team Sponsor server rules (approved 2026-11-19):
//   - a slot is created only after payment, once (webhook retries)
//   - a slot holds only the team, name, link, logo, its dates, who paid and
//     the order - nothing about players or families
// Runs against the compiled module: `npm test` builds first.
const test = require("node:test");
const assert = require("node:assert/strict");
const {
    sponsorSlotProduct,
    sponsorLimits,
    validateSponsorSnapshot,
    sponsorSlotDocument,
    planSlotActivation
} = require("../lib/sponsorSlot.js");

const snapshot = (over = {}) => JSON.stringify({ teamId: "team_1", name: "Main St Pizza", link: "https://pizza.example", logo: "", ...over });

test("a valid sponsor's details pass", () => {
    const result = validateSponsorSnapshot(snapshot());
    assert.equal(result.ok, true);
    assert.deepEqual(result.value, { teamId: "team_1", name: "Main St Pizza", link: "https://pizza.example", logo: "" });
});

test("bad sponsor details are refused", () => {
    const bad = [
        "", "not json", "[]", "null",
        snapshot({ teamId: "" }),
        snapshot({ teamId: "../users/x" }),
        snapshot({ name: "" }),
        snapshot({ name: "x".repeat(sponsorLimits.nameMax + 1) }),
        snapshot({ link: "http://plain.example" }),
        snapshot({ link: "javascript:alert(1)" }),
        snapshot({ logo: "not base64!" }),
        snapshot({ logo: "A".repeat(sponsorLimits.logoMax + 4) })
    ];
    for (const json of bad) {
        assert.equal(validateSponsorSnapshot(json).ok, false, `accepted ${json.slice(0, 60)}`);
    }
});

test("extra fields in the details never reach the slot", () => {
    const result = validateSponsorSnapshot(snapshot({ playerNames: ["Ava"], email: "x@y.z" }));
    assert.equal(result.ok, true);
    const doc = sponsorSlotDocument(result.value, { purchasedByUid: "coach", orderId: "cs_1", startsAt: new Date(0) });
    assert.deepEqual(
        Object.keys(doc).sort(),
        ["endsAt", "link", "logo", "name", "orderId", "purchasedByUid", "startsAt", "teamId"]
    );
});

test("a slot runs one season (183 days)", () => {
    const doc = sponsorSlotDocument(validateSponsorSnapshot(snapshot()).value, {
        purchasedByUid: "coach", orderId: "cs_1", startsAt: new Date("2026-03-01T00:00:00Z")
    });
    assert.equal((doc.endsAt - doc.startsAt) / 86_400_000, sponsorSlotProduct.durationDays);
});

test("a slot is activated only after payment, and only once", () => {
    const base = { itemKind: "sponsorSlot", fulfillmentState: "completed" };
    assert.equal(planSlotActivation({ ...base, paymentStatus: "paid", slotExists: false }), "activate");
    assert.equal(planSlotActivation({ ...base, paymentStatus: "paid", slotExists: true }), "skip");
    assert.equal(planSlotActivation({ ...base, paymentStatus: "unpaid", slotExists: false }), "hold");
    assert.equal(planSlotActivation({ itemKind: "sponsorSlot", fulfillmentState: "async_payment_failed", paymentStatus: "paid", slotExists: false }), "hold");
    assert.equal(planSlotActivation({ itemKind: "seasonBook", paymentStatus: "paid", fulfillmentState: "completed", slotExists: false }), "skip");
});
