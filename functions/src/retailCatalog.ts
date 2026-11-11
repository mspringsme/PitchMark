// What the store sells. Product ids match the app (Retail.swift,
// GridKeyPrint.swift).

export type RetailCatalogItem = {
    /** Empty = priced in code (price_data), no Stripe price object. */
    priceId: string;
    label: string;
    unitAmountCents: number;
};

export const retailCatalog: Record<string, RetailCatalogItem> = {
    grid_5x3: { priceId: "price_1TWMl2HGR9piiykP6OCTEeNJ", label: "Grid Key 5 x 3", unitAmountCents: 1200 },
    grid_3_5x2_75: { priceId: "price_1TWMlwHGR9piiykP0L1a4G1a", label: "Grid Key 3.5 x 2.75", unitAmountCents: 1200 },
    grid_custom: { priceId: "price_1TWMmuHGR9piiykPW7qo1LHY", label: "Grid Key Custom", unitAmountCents: 1400 },
    sheet_8_5x11: { priceId: "price_1TWMpLHGR9piiykPw9kDjvkm", label: "Printable Sheet 8.5 x 11", unitAmountCents: 1200 },
    // 14 cards at the size chosen in the app (user's price, 2026-11-08).
    sign_grid_custom: { priceId: "", label: "Batter & Runner Grid", unitAmountCents: 2000 },
    // 4 waterproof pocket calling cards cut from one 8.5 x 11 sheet (user's price, 2026-11-10).
    calling_card_waterproof: { priceId: "", label: "Waterproof Calling Cards (4)", unitAmountCents: 800 }
};

export const allowedItemKinds = new Set(["gridKey", "printableSheet", "signGrid", ""]);
