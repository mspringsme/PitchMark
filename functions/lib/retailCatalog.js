"use strict";
// What the store sells. Product ids match the app (Retail.swift,
// GridKeyPrint.swift).
Object.defineProperty(exports, "__esModule", { value: true });
exports.allowedItemKinds = exports.requiredItemKindByProduct = exports.digitalProductIds = exports.retailCatalog = void 0;
exports.retailCatalog = {
    grid_5x3: { priceId: "price_1TWMl2HGR9piiykP6OCTEeNJ", label: "Grid Key 5 x 3", unitAmountCents: 1200 },
    grid_3_5x2_75: { priceId: "price_1TWMlwHGR9piiykP0L1a4G1a", label: "Grid Key 3.5 x 2.75", unitAmountCents: 1200 },
    grid_custom: { priceId: "price_1TWMmuHGR9piiykPW7qo1LHY", label: "Grid Key Custom", unitAmountCents: 1400 },
    sheet_8_5x11: { priceId: "price_1TWMpLHGR9piiykPw9kDjvkm", label: "Printable Sheet 8.5 x 11", unitAmountCents: 1200 },
    // 14 cards at the size chosen in the app (user's price, 2026-11-08).
    sign_grid_custom: { priceId: "", label: "Batter & Runner Grid", unitAmountCents: 2000 },
    // 4 waterproof pocket calling cards cut from one 8.5 x 11 sheet (user's price, 2026-11-10).
    calling_card_waterproof: { priceId: "", label: "Waterproof Calling Cards (4)", unitAmountCents: 800 },
    // Printed hardcover of a family's Moments (2026-11-19). The amount here is
    // the 30-page base; checkout prices each book by its page count
    // (seasonBookPriceCents), never from the app.
    season_book_hardcover: { priceId: "", label: "Season Book (Hardcover)", unitAmountCents: 4900 },
    // One season (183 days) of a team sponsor slot (2026-11-19). Digital: no shipping.
    team_sponsor_season: { priceId: "", label: "Team Sponsor (One Season)", unitAmountCents: 2500 },
    // Trading cards (2026-11-19, user's prices). A team set's amount is per
    // family set; checkout multiplies it by the sets ordered (planTeamSetOrder).
    card_family_12: { priceId: "", label: "Trading Cards - Family Pack (12)", unitAmountCents: 1499 },
    card_family_24: { priceId: "", label: "Trading Cards - Family Pack (24)", unitAmountCents: 1999 },
    card_team_set: { priceId: "", label: "Trading Cards - Team Set", unitAmountCents: 1299 }
};
/** Products that ship nothing - checkout collects no shipping address. */
exports.digitalProductIds = new Set(["team_sponsor_season"]);
/** Which item kind each new product must be ordered as. */
exports.requiredItemKindByProduct = {
    season_book_hardcover: "seasonBook",
    team_sponsor_season: "sponsorSlot",
    card_family_12: "cardFamilyPack",
    card_family_24: "cardFamilyPack",
    card_team_set: "cardTeamSet"
};
exports.allowedItemKinds = new Set(["gridKey", "printableSheet", "signGrid", "seasonBook", "sponsorSlot", "cardFamilyPack", "cardTeamSet", ""]);
