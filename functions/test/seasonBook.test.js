// Season Book server rules (approved 2026-11-19):
//   - checkout refuses a page count outside the product's range, and the
//     price comes from the page count, never from the app
//   - a Stripe retry (or the async event after `completed`) never prints a
//     second book  [high risk - broken on purpose to prove the test]
//   - an unpaid or failed payment never reaches the print partner
// Runs against the compiled module: `npm test` builds first.
const test = require("node:test");
const assert = require("node:assert/strict");
const {
    seasonBookProduct,
    seasonBookPriceCents,
    resolveSeasonBookRequest,
    planPrintSubmission,
    gelatoOrderPayload,
    seasonBookUploadPath
} = require("../lib/seasonBook.js");
const { retailCatalog, allowedItemKinds, digitalProductIds, requiredItemKindByProduct } = require("../lib/retailCatalog.js");

const UID = "coachUid123";
const PATH = seasonBookUploadPath(UID, "order-key-0001");

test("page count must be 30 to 200, in pairs", () => {
    for (const bad of [0, 28, 29, 31, 201, 202, 30.5, "30", null, undefined, -30]) {
        const result = resolveSeasonBookRequest(UID, bad, PATH);
        assert.equal(result.ok, false, `accepted ${String(bad)} pages`);
    }
    for (const good of [30, 32, 100, 200]) {
        assert.equal(resolveSeasonBookRequest(UID, good, PATH).ok, true, `refused ${good} pages`);
    }
});

test("the price comes from the page count only", () => {
    assert.equal(seasonBookPriceCents(30), 4900);
    assert.equal(seasonBookPriceCents(32), 5000);
    assert.equal(seasonBookPriceCents(200), 4900 + 85 * 100);
    assert.equal(seasonBookPriceCents(31), null);
    // resolveSeasonBookRequest takes no price argument at all: whatever the
    // app sends in its request is never read.
    assert.equal(resolveSeasonBookRequest.length, 3);
    const result = resolveSeasonBookRequest(UID, 40, PATH);
    assert.equal(result.ok && result.value.priceCents, 4900 + 5 * 100);
});

test("the upload must be the caller's own book file", () => {
    assert.equal(resolveSeasonBookRequest(UID, 30, seasonBookUploadPath("someoneElse", "order-key-0001")).ok, false);
    assert.equal(resolveSeasonBookRequest(UID, 30, `bookUploads/${UID}/order-key-0001/other.pdf`).ok, false);
    assert.equal(resolveSeasonBookRequest(UID, 30, `bookUploads/${UID}/../x/interior.pdf`).ok, false);
    assert.equal(resolveSeasonBookRequest(UID, 30, `bookUploads/${UID}/short/interior.pdf`).ok, false);
    assert.equal(resolveSeasonBookRequest(UID, 30, 42).ok, false);
});

// A stand-in for the webhook: Stripe delivers events, each runs the plan on
// the stored order, and a "submit" claims the order (as the transaction does)
// and counts one print.
function deliver(order, events) {
    let prints = 0;
    for (const event of events) {
        order.fulfillmentState = event.state;
        order.paymentStatus = event.paymentStatus;
        if (planPrintSubmission(order) === "submit") {
            order.printSubmission = { state: "submitting" };
            prints += 1;
        }
    }
    return prints;
}

test("HIGH RISK: a webhook retry never prints a second book", () => {
    const paid = { state: "completed", paymentStatus: "paid" };
    assert.equal(deliver({ itemKind: "seasonBook" }, [paid, paid, paid]), 1, "a retried completed event printed again");

    const asyncFlow = [
        { state: "completed", paymentStatus: "unpaid" },
        { state: "async_payment_succeeded", paymentStatus: "paid" },
        { state: "async_payment_succeeded", paymentStatus: "paid" }
    ];
    assert.equal(deliver({ itemKind: "seasonBook" }, asyncFlow), 1, "the async success printed twice");

    for (const state of ["submitting", "submitted", "failed", "awaiting_manual"]) {
        assert.equal(
            planPrintSubmission({ itemKind: "seasonBook", paymentStatus: "paid", fulfillmentState: "completed", printSubmission: { state } }),
            "skip",
            `re-submitted an order already ${state}`
        );
    }
});

test("an unpaid or failed payment never reaches the printer", () => {
    assert.equal(planPrintSubmission({ itemKind: "seasonBook", paymentStatus: "unpaid", fulfillmentState: "completed" }), "hold");
    assert.equal(planPrintSubmission({ itemKind: "seasonBook", paymentStatus: "paid", fulfillmentState: "async_payment_failed" }), "hold");
    assert.equal(planPrintSubmission({ itemKind: "seasonBook" }), "hold");
    assert.equal(deliver({ itemKind: "seasonBook" }, [
        { state: "completed", paymentStatus: "unpaid" },
        { state: "async_payment_failed", paymentStatus: "unpaid" }
    ]), 0);
});

test("other store items never go to the book printer", () => {
    for (const itemKind of ["gridKey", "signGrid", "sponsorSlot", "", undefined]) {
        assert.equal(planPrintSubmission({ itemKind, paymentStatus: "paid", fulfillmentState: "completed" }), "skip");
    }
});

test("the print order carries the book, its pages and the ship-to", () => {
    const body = gelatoOrderPayload({
        orderId: "cs_test_1",
        productUid: "photobooks-hardcover_x",
        fileUrl: "https://example.com/signed",
        pageCount: 40,
        shipping: {
            name: "Pat Lee Smith",
            email: "pat@example.com",
            phone: "555",
            address: { line1: "1 Main", line2: null, city: "Town", state: "CA", postal_code: "90000", country: "US" }
        }
    });
    assert.equal(body.orderReferenceId, "cs_test_1");
    assert.equal(body.items.length, 1);
    assert.equal(body.items[0].pageCount, 40);
    assert.equal(body.items[0].productUid, "photobooks-hardcover_x");
    assert.deepEqual(body.items[0].files, [{ type: "default", url: "https://example.com/signed" }]);
    assert.equal(body.shippingAddress.firstName, "Pat");
    assert.equal(body.shippingAddress.lastName, "Lee Smith");
    assert.equal(body.shippingAddress.postCode, "90000");
});

test("the catalog sells the book and the sponsor slot, and only as themselves", () => {
    assert.equal(retailCatalog.season_book_hardcover.unitAmountCents, seasonBookProduct.baseCents);
    assert.equal(retailCatalog.team_sponsor_season.unitAmountCents, 2500);
    assert.equal(retailCatalog.season_book_hardcover.priceId, "");
    assert.ok(allowedItemKinds.has("seasonBook") && allowedItemKinds.has("sponsorSlot"));
    assert.equal(requiredItemKindByProduct.season_book_hardcover, "seasonBook");
    assert.equal(requiredItemKindByProduct.team_sponsor_season, "sponsorSlot");
    assert.ok(digitalProductIds.has("team_sponsor_season"));
    assert.ok(!digitalProductIds.has("season_book_hardcover"), "a book needs a shipping address");
});
