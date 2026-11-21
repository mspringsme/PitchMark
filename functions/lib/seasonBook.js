"use strict";
// Season Book (printed keepsake) rules, kept free of Firebase so they can be
// tested on their own. The app twin is PitchMark/SeasonBook.swift - keep the
// page limits and price identical.
//
// Flow: the app uploads the finished interior PDF to
// bookUploads/{uid}/{orderKey}/interior.pdf, then asks for a checkout. The
// server prices the book from its page count (never from the app), and the
// Stripe webhook sends it to the print partner exactly once after payment.
Object.defineProperty(exports, "__esModule", { value: true });
exports.printedItemKinds = exports.seasonBookProduct = void 0;
exports.seasonBookPriceCents = seasonBookPriceCents;
exports.isValidSeasonBookPageCount = isValidSeasonBookPageCount;
exports.seasonBookUploadPath = seasonBookUploadPath;
exports.resolveSeasonBookRequest = resolveSeasonBookRequest;
exports.planPrintSubmission = planPrintSubmission;
exports.gelatoOrderPayload = gelatoOrderPayload;
exports.seasonBookProduct = {
    retailProductId: "season_book_hardcover",
    itemKind: "seasonBook",
    label: "Season Book (Hardcover)",
    minPages: 30,
    maxPages: 200,
    includedPages: 30,
    baseCents: 4900,
    /** Each 2 pages past the included 30. */
    extraPagePairCents: 100
};
function seasonBookPriceCents(pageCount) {
    if (!isValidSeasonBookPageCount(pageCount)) {
        return null;
    }
    const extraPairs = Math.max(0, pageCount - exports.seasonBookProduct.includedPages) / 2;
    return exports.seasonBookProduct.baseCents + extraPairs * exports.seasonBookProduct.extraPagePairCents;
}
function isValidSeasonBookPageCount(pageCount) {
    return typeof pageCount === "number"
        && Number.isInteger(pageCount)
        && pageCount >= exports.seasonBookProduct.minPages
        && pageCount <= exports.seasonBookProduct.maxPages
        && pageCount % 2 === 0;
}
const orderKeyPattern = "[A-Za-z0-9._-]{8,80}";
function seasonBookUploadPath(uid, orderKey) {
    return `bookUploads/${uid}/${orderKey}/interior.pdf`;
}
function resolveSeasonBookRequest(uid, pageCount, uploadPath) {
    if (!isValidSeasonBookPageCount(pageCount)) {
        return {
            ok: false,
            message: `A season book has ${exports.seasonBookProduct.minPages} to ${exports.seasonBookProduct.maxPages} pages, in pairs.`
        };
    }
    const escapedUid = uid.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const pathPattern = new RegExp(`^bookUploads/${escapedUid}/${orderKeyPattern}/interior\\.pdf$`);
    if (typeof uploadPath !== "string" || !pathPattern.test(uploadPath)) {
        return { ok: false, message: "The book's upload is missing or isn't yours." };
    }
    const priceCents = seasonBookPriceCents(pageCount);
    if (priceCents === null) {
        return { ok: false, message: "The book couldn't be priced." };
    }
    return { ok: true, value: { pageCount, uploadPath, priceCents } };
}
/** Store items printed by a print partner after payment. */
exports.printedItemKinds = new Set(["seasonBook", "cardFamilyPack", "cardTeamSet"]);
function planPrintSubmission(order) {
    if (typeof order.itemKind !== "string" || !exports.printedItemKinds.has(order.itemKind)) {
        return "skip";
    }
    if (order.printSubmission != null) {
        return "skip";
    }
    if (order.fulfillmentState === "async_payment_failed" || order.paymentStatus !== "paid") {
        return "hold";
    }
    return "submit";
}
/**
 * The print partner's order body (Gelato's order API). The product uid and
 * endpoint come from config, so a partner change doesn't touch this.
 */
function gelatoOrderPayload(input) {
    const [firstName, ...rest] = input.shipping.name.trim().split(/\s+/);
    const address = input.shipping.address ?? {};
    return {
        orderType: "order",
        orderReferenceId: input.orderId,
        customerReferenceId: input.orderId,
        currency: "USD",
        items: [
            {
                itemReferenceId: `${input.orderId}-book`,
                productUid: input.productUid,
                pageCount: input.pageCount,
                quantity: 1,
                files: [{ type: "default", url: input.fileUrl }]
            }
        ],
        shippingAddress: {
            firstName: firstName ?? "",
            lastName: rest.join(" "),
            addressLine1: address.line1 ?? "",
            addressLine2: address.line2 ?? "",
            city: address.city ?? "",
            state: address.state ?? "",
            postCode: address.postal_code ?? "",
            country: address.country ?? "",
            email: input.shipping.email,
            phone: input.shipping.phone
        }
    };
}
