// Season Book (printed keepsake) rules, kept free of Firebase so they can be
// tested on their own. The app twin is PitchMark/SeasonBook.swift - keep the
// page limits and price identical.
//
// Flow: the app uploads the finished interior PDF to
// bookUploads/{uid}/{orderKey}/interior.pdf, then asks for a checkout. The
// server prices the book from its page count (never from the app), and the
// Stripe webhook sends it to the print partner exactly once after payment.

export const seasonBookProduct = {
    retailProductId: "season_book_hardcover",
    itemKind: "seasonBook",
    label: "Season Book (Hardcover)",
    minPages: 30,
    maxPages: 200,
    includedPages: 30,
    baseCents: 4900,
    /** Each 2 pages past the included 30. */
    extraPagePairCents: 100
} as const;

export function seasonBookPriceCents(pageCount: number): number | null {
    if (!isValidSeasonBookPageCount(pageCount)) {
        return null;
    }
    const extraPairs = Math.max(0, pageCount - seasonBookProduct.includedPages) / 2;
    return seasonBookProduct.baseCents + extraPairs * seasonBookProduct.extraPagePairCents;
}

export function isValidSeasonBookPageCount(pageCount: unknown): pageCount is number {
    return typeof pageCount === "number"
        && Number.isInteger(pageCount)
        && pageCount >= seasonBookProduct.minPages
        && pageCount <= seasonBookProduct.maxPages
        && pageCount % 2 === 0;
}

const orderKeyPattern = "[A-Za-z0-9._-]{8,80}";

export function seasonBookUploadPath(uid: string, orderKey: string): string {
    return `bookUploads/${uid}/${orderKey}/interior.pdf`;
}

export type SeasonBookRequest = { pageCount: number; uploadPath: string; priceCents: number };

export function resolveSeasonBookRequest(
    uid: string,
    pageCount: unknown,
    uploadPath: unknown
): { ok: true; value: SeasonBookRequest } | { ok: false; message: string } {
    if (!isValidSeasonBookPageCount(pageCount)) {
        return {
            ok: false,
            message: `A season book has ${seasonBookProduct.minPages} to ${seasonBookProduct.maxPages} pages, in pairs.`
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

/**
 * What the webhook does with a printed order (season book, trading cards). `submit` only when the
 * order is paid and nothing was ever sent to the printer - a Stripe retry,
 * or the async success event after `completed`, must never print twice.
 */
export type PrintSubmissionPlan = "submit" | "skip" | "hold";

export type PrintSubmissionOrder = {
    itemKind?: unknown;
    paymentStatus?: unknown;
    fulfillmentState?: unknown;
    printSubmission?: unknown;
};

/** Store items printed by a print partner after payment. */
export const printedItemKinds = new Set(["seasonBook", "cardFamilyPack", "cardTeamSet"]);

export function planPrintSubmission(order: PrintSubmissionOrder): PrintSubmissionPlan {
    if (typeof order.itemKind !== "string" || !printedItemKinds.has(order.itemKind)) {
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

export type ShippingDetails = {
    name: string;
    email: string;
    phone: string;
    address: {
        line1?: string | null;
        line2?: string | null;
        city?: string | null;
        state?: string | null;
        postal_code?: string | null;
        country?: string | null;
    } | null;
};

/**
 * The print partner's order body (Gelato's order API). The product uid and
 * endpoint come from config, so a partner change doesn't touch this.
 */
export function gelatoOrderPayload(input: {
    orderId: string;
    productUid: string;
    fileUrl: string;
    pageCount: number;
    shipping: ShippingDetails;
}): Record<string, unknown> {
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
