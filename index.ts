import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { initializeApp } from "firebase-admin/app";
import Stripe from "stripe";

initializeApp();

type RetailCatalogItem = {
    priceId: string;
    label: string;
};

const retailCatalog: Record<string, RetailCatalogItem> = {
    grid_5x3: { priceId: "price_grid_5x3", label: "Grid Key 5 x 3" },
    grid_3_5x2_75: { priceId: "price_grid_3_5x2_75", label: "Grid Key 3.5 x 2.75" },
    grid_custom: { priceId: "price_grid_custom", label: "Grid Key Custom" },
    sheet_8_5x11: { priceId: "price_sheet_8_5x11", label: "Printable Sheet 8.5 x 11" }
};

function getStripeClient(): Stripe {
    const stripeSecretKey = process.env.STRIPE_SECRET_KEY;
    if (!stripeSecretKey) {
        throw new HttpsError("failed-precondition", "Missing STRIPE_SECRET_KEY environment variable.");
    }
    return new Stripe(stripeSecretKey, {
        apiVersion: "2025-03-31.basil"
    });
}

function requireEnv(name: string): string {
    const value = process.env[name];
    if (!value) {
        throw new HttpsError("failed-precondition", `Missing ${name} environment variable.`);
    }
    return value;
}

export const createRetailCheckoutSession = onCall({ region: "us-central1" }, async (request) => {
    if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "You must be signed in to purchase.");
    }

    const data = request.data as Record<string, unknown>;
    const retailProductId = String(data.retailProductId ?? "").trim();
    const itemKind = String(data.itemKind ?? "").trim();
    const templateId = String(data.templateId ?? "").trim();
    const templateName = String(data.templateName ?? "").trim();
    const storeTemplateName = String(data.storeTemplateName ?? "").trim();

    if (!retailProductId) {
        throw new HttpsError("invalid-argument", "retailProductId is required.");
    }

    const catalogItem = retailCatalog[retailProductId];
    if (!catalogItem) {
        throw new HttpsError("invalid-argument", "Unknown retailProductId.");
    }

    const successUrl = requireEnv("STRIPE_CHECKOUT_SUCCESS_URL");
    const cancelUrl = requireEnv("STRIPE_CHECKOUT_CANCEL_URL");

    const stripe = getStripeClient();

    const metadata: Record<string, string> = {
        app: "PitchMark",
        firebaseUid: request.auth.uid,
        retailProductId,
        itemKind,
        templateId,
        templateName,
        storeTemplateName
    };

    const session = await stripe.checkout.sessions.create({
        mode: "payment",
        line_items: [
            {
                price: catalogItem.priceId,
                quantity: 1
            }
        ],
        success_url: successUrl,
        cancel_url: cancelUrl,
        metadata,
        payment_intent_data: {
            metadata
        },
        allow_promotion_codes: true
    });

    if (!session.url) {
        logger.error("Stripe checkout session created without URL", { retailProductId, uid: request.auth.uid });
        throw new HttpsError("internal", "Failed to create checkout URL.");
    }

    return {
        checkoutUrl: session.url,
        sessionId: session.id,
        displayName: catalogItem.label
    };
});
