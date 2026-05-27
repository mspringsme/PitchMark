"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.stripeWebhook = exports.createRetailCheckoutSession = void 0;
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const app_1 = require("firebase-admin/app");
const firestore_1 = require("firebase-admin/firestore");
const stripe_1 = __importDefault(require("stripe"));
(0, app_1.initializeApp)();
const db = (0, firestore_1.getFirestore)();
const retailCatalog = {
    grid_5x3: { priceId: "price_1TbQjpHGR9piiykPmnX6Lj5J", label: "Grid Key 5 x 3" },
    grid_3_5x2_75: { priceId: "price_1TbQkPHGR9piiykPAIvImeVz", label: "Grid Key 3.5 x 2.75" },
    grid_custom: { priceId: "price_1TbQkuHGR9piiykPFoJgsxTf", label: "Grid Key Custom" },
    sheet_8_5x11: { priceId: "price_1TbQmqHGR9piiykPAKJpnQQP", label: "Printable Sheet 8.5 x 11" }
};
const allowedItemKinds = new Set(["gridKey", "printableSheet", ""]);
const idempotencyKeyPattern = /^[a-zA-Z0-9._-]{8,80}$/;
const checkoutThrottleWindowMs = 60_000;
const checkoutThrottleMaxAttempts = 5;
function getStripeClient() {
    const stripeSecretKey = process.env.STRIPE_SECRET_KEY;
    if (!stripeSecretKey) {
        throw new https_1.HttpsError("failed-precondition", "Missing STRIPE_SECRET_KEY environment variable.");
    }
    return new stripe_1.default(stripeSecretKey, {
        apiVersion: "2024-06-20"
    });
}
function requireEnv(name) {
    const value = process.env[name];
    if (!value) {
        throw new https_1.HttpsError("failed-precondition", `Missing ${name} environment variable.`);
    }
    return value;
}
function optionalEnv(name) {
    return process.env[name]?.trim() ?? "";
}
function parseRequestData(data) {
    if (!data || typeof data !== "object" || Array.isArray(data)) {
        throw new https_1.HttpsError("invalid-argument", "Request payload must be an object.");
    }
    return data;
}
function readOptionalString(data, key, maxLength) {
    const raw = data[key];
    if (raw == null) {
        return "";
    }
    if (typeof raw !== "string") {
        throw new https_1.HttpsError("invalid-argument", `${key} must be a string.`);
    }
    const value = raw.trim();
    if (value.length > maxLength) {
        throw new https_1.HttpsError("invalid-argument", `${key} exceeds ${maxLength} characters.`);
    }
    return value;
}
function sanitizeMetadataValue(value, maxLength) {
    return value
        .replace(/[\u0000-\u001F\u007F]/g, " ")
        .replace(/\s+/g, " ")
        .trim()
        .slice(0, maxLength);
}
function requireHttpsUrl(value, name) {
    let parsed;
    try {
        parsed = new URL(value);
    }
    catch {
        throw new https_1.HttpsError("failed-precondition", `${name} must be a valid URL.`);
    }
    if (parsed.protocol !== "https:") {
        throw new https_1.HttpsError("failed-precondition", `${name} must use https.`);
    }
    return parsed.toString();
}
async function enforceCheckoutRateLimit(uid) {
    const bucket = Math.floor(Date.now() / checkoutThrottleWindowMs);
    const key = `${uid}_${bucket}`;
    const ref = db.collection("rateLimits").doc("checkout").collection("users").doc(key);
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const count = snap.exists ? Number(snap.data()?.count ?? 0) : 0;
        if (count >= checkoutThrottleMaxAttempts) {
            throw new https_1.HttpsError("resource-exhausted", "Too many checkout attempts. Please wait a minute and try again.");
        }
        tx.set(ref, {
            uid,
            count: count + 1,
            bucket,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
            expiresAt: Date.now() + (2 * checkoutThrottleWindowMs)
        }, { merge: true });
    });
}
function readOptionalIdempotencyKey(data) {
    const raw = data.idempotencyKey;
    if (raw == null) {
        return "";
    }
    if (typeof raw !== "string") {
        throw new https_1.HttpsError("invalid-argument", "idempotencyKey must be a string.");
    }
    const value = raw.trim();
    if (!value) {
        return "";
    }
    if (!idempotencyKeyPattern.test(value)) {
        throw new https_1.HttpsError("invalid-argument", "idempotencyKey format is invalid.");
    }
    return value;
}
exports.createRetailCheckoutSession = (0, https_1.onCall)({ region: "us-central1" }, async (request) => {
    if (!request.auth?.uid) {
        throw new https_1.HttpsError("unauthenticated", "You must be signed in to purchase.");
    }
    const data = parseRequestData(request.data);
    const retailProductId = readOptionalString(data, "retailProductId", 64);
    const itemKind = readOptionalString(data, "itemKind", 32);
    const templateId = readOptionalString(data, "templateId", 128);
    const templateName = readOptionalString(data, "templateName", 120);
    const storeTemplateName = readOptionalString(data, "storeTemplateName", 120);
    const idempotencyKey = readOptionalIdempotencyKey(data);
    if (!retailProductId) {
        throw new https_1.HttpsError("invalid-argument", "retailProductId is required.");
    }
    if (!allowedItemKinds.has(itemKind)) {
        throw new https_1.HttpsError("invalid-argument", "itemKind is invalid.");
    }
    const catalogItem = retailCatalog[retailProductId];
    if (!catalogItem) {
        throw new https_1.HttpsError("invalid-argument", "Unknown retailProductId.");
    }
    if (idempotencyKey) {
        const idemRef = db.collection("checkoutRequests").doc(request.auth.uid).collection("keys").doc(idempotencyKey);
        const idemSnap = await idemRef.get();
        if (idemSnap.exists) {
            const previous = idemSnap.data() ?? {};
            const checkoutUrl = typeof previous.checkoutUrl === "string" ? previous.checkoutUrl : "";
            const sessionId = typeof previous.sessionId === "string" ? previous.sessionId : "";
            const displayName = typeof previous.displayName === "string" ? previous.displayName : catalogItem.label;
            if (checkoutUrl && sessionId) {
                return { checkoutUrl, sessionId, displayName };
            }
        }
    }
    const successUrl = requireHttpsUrl(requireEnv("STRIPE_CHECKOUT_SUCCESS_URL"), "STRIPE_CHECKOUT_SUCCESS_URL");
    const cancelUrl = requireHttpsUrl(requireEnv("STRIPE_CHECKOUT_CANCEL_URL"), "STRIPE_CHECKOUT_CANCEL_URL");
    await enforceCheckoutRateLimit(request.auth.uid);
    const stripe = getStripeClient();
    const metadata = {
        app: "PitchMark",
        firebaseUid: request.auth.uid,
        retailProductId: sanitizeMetadataValue(retailProductId, 64),
        itemKind: sanitizeMetadataValue(itemKind, 32),
        templateId: sanitizeMetadataValue(templateId, 128),
        templateName: sanitizeMetadataValue(templateName, 120),
        storeTemplateName: sanitizeMetadataValue(storeTemplateName, 120)
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
    }, idempotencyKey ? {
        idempotencyKey: `checkout_${request.auth.uid}_${idempotencyKey}`
    } : undefined);
    if (!session.url) {
        logger.error("Stripe checkout session created without URL", { retailProductId, uid: request.auth.uid });
        throw new https_1.HttpsError("internal", "Failed to create checkout URL.");
    }
    if (idempotencyKey) {
        const idemRef = db.collection("checkoutRequests").doc(request.auth.uid).collection("keys").doc(idempotencyKey);
        await idemRef.set({
            checkoutUrl: session.url,
            sessionId: session.id,
            displayName: catalogItem.label,
            retailProductId,
            itemKind,
            createdAt: firestore_1.FieldValue.serverTimestamp()
        }, { merge: true });
    }
    return {
        checkoutUrl: session.url,
        sessionId: session.id,
        displayName: catalogItem.label
    };
});
const checkoutWebhookHandlers = {
    "checkout.session.completed": async (event) => {
        const session = event.data.object;
        await persistRetailOrder(session, "completed");
    },
    "checkout.session.async_payment_succeeded": async (event) => {
        const session = event.data.object;
        await persistRetailOrder(session, "async_payment_succeeded");
    },
    "checkout.session.async_payment_failed": async (event) => {
        const session = event.data.object;
        await persistRetailOrder(session, "async_payment_failed");
    }
};
async function persistRetailOrder(session, fulfillmentState) {
    const metadata = session.metadata ?? {};
    const uid = metadata.firebaseUid ?? "";
    const sessionId = session.id;
    if (!sessionId) {
        logger.error("Stripe webhook missing session id", { fulfillmentState });
        return;
    }
    const orderRef = db.collection("retailOrders").doc(sessionId);
    await db.runTransaction(async (tx) => {
        const existingSnap = await tx.get(orderRef);
        const existing = existingSnap.exists ? existingSnap.data() ?? {} : {};
        const defaultFulfillmentStatus = fulfillmentState === "async_payment_failed" ? "payment_failed" : "new";
        tx.set(orderRef, {
            sessionId,
            fulfillmentState,
            checkoutStatus: session.status ?? "",
            paymentStatus: session.payment_status ?? "",
            amountSubtotal: session.amount_subtotal ?? null,
            amountTotal: session.amount_total ?? null,
            currency: session.currency ?? "",
            customerEmail: session.customer_details?.email ?? session.customer_email ?? "",
            customerName: session.customer_details?.name ?? "",
            customerPhone: session.customer_details?.phone ?? "",
            shippingName: session.shipping_details?.name ?? "",
            shippingAddress: session.shipping_details?.address ?? null,
            stripeCustomerId: typeof session.customer === "string" ? session.customer : "",
            paymentIntentId: typeof session.payment_intent === "string" ? session.payment_intent : "",
            firebaseUid: uid,
            retailProductId: metadata.retailProductId ?? "",
            itemKind: metadata.itemKind ?? "",
            templateId: metadata.templateId ?? "",
            templateName: metadata.templateName ?? "",
            storeTemplateName: metadata.storeTemplateName ?? "",
            fulfillmentStatus: typeof existing.fulfillmentStatus === "string" && existing.fulfillmentStatus
                ? existing.fulfillmentStatus
                : defaultFulfillmentStatus,
            shippingCarrier: typeof existing.shippingCarrier === "string" ? existing.shippingCarrier : "",
            trackingNumber: typeof existing.trackingNumber === "string" ? existing.trackingNumber : "",
            internalNotes: typeof existing.internalNotes === "string" ? existing.internalNotes : "",
            createdAt: existingSnap.exists ? (existing.createdAt ?? firestore_1.FieldValue.serverTimestamp()) : firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
            stripeCreatedAtMs: session.created ? session.created * 1000 : null
        }, { merge: true });
    });
}
exports.stripeWebhook = (0, https_1.onRequest)({ region: "us-central1" }, async (req, res) => {
    if (req.method !== "POST") {
        res.status(405).send("Method Not Allowed");
        return;
    }
    const signature = req.headers["stripe-signature"];
    const webhookSecret = optionalEnv("STRIPE_WEBHOOK_SECRET");
    if (!signature || Array.isArray(signature) || !webhookSecret) {
        logger.error("Stripe webhook misconfigured", {
            hasSignature: Boolean(signature),
            hasWebhookSecret: Boolean(webhookSecret)
        });
        res.status(400).send("Webhook misconfigured");
        return;
    }
    const stripe = getStripeClient();
    let event;
    try {
        event = stripe.webhooks.constructEvent(req.rawBody, signature, webhookSecret);
    }
    catch (error) {
        logger.error("Stripe webhook signature verification failed", error);
        res.status(400).send("Invalid signature");
        return;
    }
    const handler = checkoutWebhookHandlers[event.type];
    if (!handler) {
        logger.info("Ignoring unhandled Stripe event", { type: event.type });
        res.status(200).send({ received: true, ignored: true });
        return;
    }
    try {
        await handler(event);
        res.status(200).send({ received: true });
    }
    catch (error) {
        logger.error("Stripe webhook handler failed", { type: event.type, error });
        res.status(500).send("Webhook handler failed");
    }
});
