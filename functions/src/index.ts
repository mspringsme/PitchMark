import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue, type Query } from "firebase-admin/firestore";
import Stripe from "stripe";

initializeApp();
const db = getFirestore();
const auth = getAuth();

type RetailCatalogItem = {
    priceId: string;
    label: string;
    unitAmountCents: number;
};

const retailCatalog: Record<string, RetailCatalogItem> = {
    grid_5x3: { priceId: "price_1TbQjpHGR9piiykPmnX6Lj5J", label: "Grid Key 5 x 3", unitAmountCents: 1200 },
    grid_3_5x2_75: { priceId: "price_1TbQkPHGR9piiykPAIvImeVz", label: "Grid Key 3.5 x 2.75", unitAmountCents: 1200 },
    grid_custom: { priceId: "price_1TbQkuHGR9piiykPFoJgsxTf", label: "Grid Key Custom", unitAmountCents: 1400 },
    sheet_8_5x11: { priceId: "price_1TbQmqHGR9piiykPAKJpnQQP", label: "Printable Sheet 8.5 x 11", unitAmountCents: 1200 }
};

const allowedItemKinds = new Set(["gridKey", "printableSheet", ""]);
const idempotencyKeyPattern = /^[a-zA-Z0-9._-]{8,80}$/;
const checkoutThrottleWindowMs = 60_000;
const checkoutThrottleMaxAttempts = 5;
const checkoutConfigVersion = "shipping_v1";
const accountDeletionBatchSize = 400;

function getStripeClient(): Stripe {
    const stripeSecretKey = process.env.STRIPE_SECRET_KEY;
    if (!stripeSecretKey) {
        throw new HttpsError("failed-precondition", "Missing STRIPE_SECRET_KEY environment variable.");
    }
    return new Stripe(stripeSecretKey, {
        apiVersion: "2024-06-20"
    });
}

function isStripeTestMode(): boolean {
    const stripeSecretKey = process.env.STRIPE_SECRET_KEY ?? "";
    return stripeSecretKey.startsWith("sk_test_");
}

function requireEnv(name: string): string {
    const value = process.env[name];
    if (!value) {
        throw new HttpsError("failed-precondition", `Missing ${name} environment variable.`);
    }
    return value;
}

function optionalEnv(name: string): string {
    return process.env[name]?.trim() ?? "";
}

function parseAllowedShippingCountries(raw: string): string[] {
    const defaults = ["US"];
    if (!raw) {
        return defaults;
    }
    const parsed = raw
        .split(",")
        .map((value) => value.trim().toUpperCase())
        .filter((value) => /^[A-Z]{2}$/.test(value));
    return parsed.length > 0 ? Array.from(new Set(parsed)) : defaults;
}

function readShippingAmountCents(name: string, fallback: number): number {
    const value = optionalEnv(name);
    if (!value) {
        return fallback;
    }
    const parsed = Number.parseInt(value, 10);
    if (!Number.isFinite(parsed) || parsed < 0) {
        throw new HttpsError("failed-precondition", `${name} must be a non-negative integer (cents).`);
    }
    return parsed;
}

function normalizeShippingAmountCents(value: number): number {
    return value <= 0 ? 1 : value;
}

function parseRequestData(data: unknown): Record<string, unknown> {
    if (!data || typeof data !== "object" || Array.isArray(data)) {
        throw new HttpsError("invalid-argument", "Request payload must be an object.");
    }
    return data as Record<string, unknown>;
}

function readOptionalString(
    data: Record<string, unknown>,
    key: string,
    maxLength: number
): string {
    const raw = data[key];
    if (raw == null) {
        return "";
    }
    if (typeof raw !== "string") {
        throw new HttpsError("invalid-argument", `${key} must be a string.`);
    }
    const value = raw.trim();
    if (value.length > maxLength) {
        throw new HttpsError("invalid-argument", `${key} exceeds ${maxLength} characters.`);
    }
    return value;
}

function sanitizeMetadataValue(value: string, maxLength: number): string {
    return value
        .replace(/[\u0000-\u001F\u007F]/g, " ")
        .replace(/\s+/g, " ")
        .trim()
        .slice(0, maxLength);
}

function requireHttpsUrl(value: string, name: string): string {
    let parsed: URL;
    try {
        parsed = new URL(value);
    } catch {
        throw new HttpsError("failed-precondition", `${name} must be a valid URL.`);
    }
    if (parsed.protocol !== "https:") {
        throw new HttpsError("failed-precondition", `${name} must use https.`);
    }
    return parsed.toString();
}

async function enforceCheckoutRateLimit(uid: string): Promise<void> {
    const bucket = Math.floor(Date.now() / checkoutThrottleWindowMs);
    const key = `${uid}_${bucket}`;
    const ref = db.collection("rateLimits").doc("checkout").collection("users").doc(key);

    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const count = snap.exists ? Number(snap.data()?.count ?? 0) : 0;
        if (count >= checkoutThrottleMaxAttempts) {
            throw new HttpsError("resource-exhausted", "Too many checkout attempts. Please wait a minute and try again.");
        }
        tx.set(
            ref,
            {
                uid,
                count: count + 1,
                bucket,
                updatedAt: FieldValue.serverTimestamp(),
                expiresAt: Date.now() + (2 * checkoutThrottleWindowMs)
            },
            { merge: true }
        );
    });
}

function readOptionalIdempotencyKey(data: Record<string, unknown>): string {
    const raw = data.idempotencyKey;
    if (raw == null) {
        return "";
    }
    if (typeof raw !== "string") {
        throw new HttpsError("invalid-argument", "idempotencyKey must be a string.");
    }
    const value = raw.trim();
    if (!value) {
        return "";
    }
    if (!idempotencyKeyPattern.test(value)) {
        throw new HttpsError("invalid-argument", "idempotencyKey format is invalid.");
    }
    return value;
}

async function deleteQueryDocuments(query: Query): Promise<number> {
    let deleted = 0;

    while (true) {
        const snap = await query.limit(accountDeletionBatchSize).get();
        if (snap.empty) {
            return deleted;
        }

        const batch = db.batch();
        for (const doc of snap.docs) {
            batch.delete(doc.ref);
            deleted += 1;
        }
        await batch.commit();
    }
}

async function recursiveDeleteQueryDocuments(query: Query): Promise<number> {
    let deleted = 0;

    while (true) {
        const snap = await query.limit(25).get();
        if (snap.empty) {
            return deleted;
        }

        await Promise.all(snap.docs.map((doc) => db.recursiveDelete(doc.ref)));
        deleted += snap.docs.length;
    }
}

async function updateQueryDocuments(query: Query, updates: Record<string, unknown>): Promise<number> {
    let updated = 0;

    while (true) {
        const snap = await query.limit(accountDeletionBatchSize).get();
        if (snap.empty) {
            return updated;
        }

        const batch = db.batch();
        for (const doc of snap.docs) {
            batch.update(doc.ref, updates);
            updated += 1;
        }
        await batch.commit();
    }
}

async function deleteUserPresenceDocs(collectionName: "participants" | "displayParticipants", uid: string): Promise<number> {
    const liveGamesSnap = await db.collection("liveGames").get();
    let deleted = 0;

    for (const liveGameDoc of liveGamesSnap.docs) {
        const presenceRef = liveGameDoc.ref.collection(collectionName).doc(uid);
        const presenceSnap = await presenceRef.get();
        if (!presenceSnap.exists) {
            continue;
        }

        await presenceRef.delete();
        deleted += 1;
    }

    return deleted;
}

async function deleteDocumentsByScanningCollection(
    collectionName: string,
    predicate: (data: Record<string, unknown>) => boolean
): Promise<number> {
    const snap = await db.collection(collectionName).get();
    let deleted = 0;

    for (const doc of snap.docs) {
        const data = doc.data() as Record<string, unknown>;
        if (!predicate(data)) {
            continue;
        }

        await db.recursiveDelete(doc.ref);
        deleted += 1;
    }

    return deleted;
}

async function updateDocumentsByScanningCollection(
    collectionName: string,
    predicate: (data: Record<string, unknown>) => boolean,
    updates: Record<string, unknown>
): Promise<number> {
    const snap = await db.collection(collectionName).get();
    let updated = 0;

    for (const doc of snap.docs) {
        const data = doc.data() as Record<string, unknown>;
        if (!predicate(data)) {
            continue;
        }

        await doc.ref.set(updates, { merge: true });
        updated += 1;
    }

    return updated;
}

async function deletePitchEventsByScanningOwnerCollections(uid: string): Promise<number> {
    const liveGamesSnap = await db.collection("liveGames").get();
    const pitchersSnap = await db.collection("pitchers").get();
    const usersSnap = await db.collection("users").get();
    let updated = 0;

    for (const liveGameDoc of liveGamesSnap.docs) {
        const pitchEventsSnap = await liveGameDoc.ref.collection("pitchEvents").get();
        for (const eventDoc of pitchEventsSnap.docs) {
            const data = eventDoc.data() as Record<string, unknown>;
            if (data.createdByUid !== uid) {
                continue;
            }
            await eventDoc.ref.set({ createdByUid: "", creatorAccountDeletedAt: FieldValue.serverTimestamp() }, { merge: true });
            updated += 1;
        }
    }

    for (const pitcherDoc of pitchersSnap.docs) {
        const pitchEventsSnap = await pitcherDoc.ref.collection("pitchEvents").get();
        for (const eventDoc of pitchEventsSnap.docs) {
            const data = eventDoc.data() as Record<string, unknown>;
            if (data.createdByUid !== uid) {
                continue;
            }
            await eventDoc.ref.set({ createdByUid: "", creatorAccountDeletedAt: FieldValue.serverTimestamp() }, { merge: true });
            updated += 1;
        }
    }

    for (const userDoc of usersSnap.docs) {
        const gamesSnap = await userDoc.ref.collection("games").get();
        for (const gameDoc of gamesSnap.docs) {
            const eventsSnap = await gameDoc.ref.collection("pitchEvents").get();
            for (const eventDoc of eventsSnap.docs) {
                const data = eventDoc.data() as Record<string, unknown>;
                if (data.createdByUid !== uid) {
                    continue;
                }
                await eventDoc.ref.set({ createdByUid: "", creatorAccountDeletedAt: FieldValue.serverTimestamp() }, { merge: true });
                updated += 1;
            }
        }
    }

    return updated;
}

export const deleteAccount = onCall({ region: "us-central1", timeoutSeconds: 540 }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new HttpsError("unauthenticated", "Please sign in again to delete your account.");
    }

    const email = typeof request.auth?.token.email === "string"
        ? request.auth.token.email.trim().toLowerCase()
        : "";
    const deletedAt = FieldValue.serverTimestamp();
    const summary: Record<string, number> = {};

    summary.ownedTemplates = await deleteDocumentsByScanningCollection("templates", (data) => data.ownerUid === uid);
    summary.sharedTemplateUidRefs = await updateDocumentsByScanningCollection("templates", (data) => Array.isArray(data.sharedWith) && data.sharedWith.includes(uid), {
        sharedWith: FieldValue.arrayRemove(uid),
        updatedAt: deletedAt
    });
    if (email) {
        summary.sharedTemplateEmailRefs = await updateDocumentsByScanningCollection("templates", (data) => Array.isArray(data.sharedWithEmails) && data.sharedWithEmails.includes(email), {
            sharedWithEmails: FieldValue.arrayRemove(email),
            updatedAt: deletedAt
        });
    }

    summary.ownedPitchers = await deleteDocumentsByScanningCollection("pitchers", (data) => data.ownerUid === uid);
    summary.claimedPitchers = await updateDocumentsByScanningCollection("pitchers", (data) => data.claimedByUid === uid, {
        claimedByUid: FieldValue.delete(),
        updatedAt: deletedAt
    });
    summary.sharedPitcherRefs = await updateDocumentsByScanningCollection("pitchers", (data) => Array.isArray(data.sharedWith) && data.sharedWith.includes(uid), {
        sharedWith: FieldValue.arrayRemove(uid),
        updatedAt: deletedAt
    });

    summary.inviteTokens = await deleteDocumentsByScanningCollection("inviteTokens", (data) => data.ownerUid === uid);
    summary.displayInviteTokens = await deleteDocumentsByScanningCollection("displayInviteTokens", (data) => data.ownerUid === uid);
    summary.pitcherInviteTokens = await deleteDocumentsByScanningCollection("pitcherInviteTokens", (data) => data.ownerUid === uid);
    summary.joinCodes = await deleteDocumentsByScanningCollection("joinCodes", (data) => data.ownerUid === uid);
    summary.liveGames = await deleteDocumentsByScanningCollection("liveGames", (data) => data.ownerUid === uid);
    summary.liveConnections = await updateDocumentsByScanningCollection("liveGames", (data) => {
        const connection = data.connection as Record<string, unknown> | undefined;
        return (connection?.participantUid ?? "") === uid;
    }, {
        connection: FieldValue.delete(),
        updatedAt: deletedAt
    });
    summary.liveParticipants = await deleteUserPresenceDocs("participants", uid);
    summary.liveDisplayParticipants = await deleteUserPresenceDocs("displayParticipants", uid);
    summary.createdPitchEvents = await deletePitchEventsByScanningOwnerCollections(uid);
    summary.checkoutRateLimits = await deleteDocumentsByScanningCollection("rateLimits", () => false);
    summary.retailOrdersUnlinked = await updateDocumentsByScanningCollection("retailOrders", (data) => data.firebaseUid === uid, {
        firebaseUid: "",
        accountDeleted: true,
        accountDeletedAt: deletedAt
    });

    await db.recursiveDelete(db.collection("checkoutRequests").doc(uid));
    await db.recursiveDelete(db.collection("users").doc(uid));

    try {
        await auth.deleteUser(uid);
    } catch (error) {
        const code = typeof error === "object" && error !== null && "code" in error
            ? String((error as { code?: unknown }).code)
            : "";
        if (code !== "auth/user-not-found") {
            logger.error("Firebase Auth user deletion failed", { uid, error });
            throw new HttpsError("internal", "Account data was removed, but sign-in deletion failed. Contact support.");
        }
    }

    logger.info("Account deleted", { uid, summary });
    return { success: true };
});

export const createRetailCheckoutSession = onCall({ region: "us-central1" }, async (request) => {
    if (!request.auth?.uid) {
        throw new HttpsError("unauthenticated", "You must be signed in to purchase.");
    }
    const stripeTestMode = isStripeTestMode();

    const data = parseRequestData(request.data);
    const retailProductId = readOptionalString(data, "retailProductId", 64);
    const itemKind = readOptionalString(data, "itemKind", 32);
    const templateId = readOptionalString(data, "templateId", 128);
    const templateName = readOptionalString(data, "templateName", 120);
    const storeTemplateName = readOptionalString(data, "storeTemplateName", 120);
    const templateSnapshotJson = readOptionalString(data, "templateSnapshotJson", 120000);
    const idempotencyKey = readOptionalIdempotencyKey(data);

    if (!retailProductId) {
        throw new HttpsError("invalid-argument", "retailProductId is required.");
    }

    if (!allowedItemKinds.has(itemKind)) {
        throw new HttpsError("invalid-argument", "itemKind is invalid.");
    }

    const catalogItem = retailCatalog[retailProductId];
    if (!catalogItem) {
        throw new HttpsError("invalid-argument", "Unknown retailProductId.");
    }

    if (idempotencyKey && !stripeTestMode) {
        const idemRef = db.collection("checkoutRequests").doc(request.auth.uid).collection("keys").doc(idempotencyKey);
        const idemSnap = await idemRef.get();
        if (idemSnap.exists) {
            const previous = idemSnap.data() ?? {};
            const previousConfigVersion = typeof previous.checkoutConfigVersion === "string" ? previous.checkoutConfigVersion : "";
            const checkoutUrl = typeof previous.checkoutUrl === "string" ? previous.checkoutUrl : "";
            const sessionId = typeof previous.sessionId === "string" ? previous.sessionId : "";
            const displayName = typeof previous.displayName === "string" ? previous.displayName : catalogItem.label;
            if (checkoutUrl && sessionId && previousConfigVersion === checkoutConfigVersion) {
                return { checkoutUrl, sessionId, displayName };
            }
        }
    }

    const successUrl = requireHttpsUrl(requireEnv("STRIPE_CHECKOUT_SUCCESS_URL"), "STRIPE_CHECKOUT_SUCCESS_URL");
    const cancelUrl = requireHttpsUrl(requireEnv("STRIPE_CHECKOUT_CANCEL_URL"), "STRIPE_CHECKOUT_CANCEL_URL");
    const allowedShippingCountries = parseAllowedShippingCountries(optionalEnv("STRIPE_SHIPPING_ALLOWED_COUNTRIES"));
    const shippingCurrency = optionalEnv("STRIPE_SHIPPING_CURRENCY").toLowerCase() || "usd";
    const standardShippingAmountCents = normalizeShippingAmountCents(readShippingAmountCents("STRIPE_SHIPPING_STANDARD_CENTS", 0));
    const expressShippingAmountCents = normalizeShippingAmountCents(readShippingAmountCents("STRIPE_SHIPPING_EXPRESS_CENTS", 1299));

    await enforceCheckoutRateLimit(request.auth.uid);

    const stripe = getStripeClient();

    const metadata: Record<string, string> = {
        app: "PitchMark",
        firebaseUid: request.auth.uid,
        retailProductId: sanitizeMetadataValue(retailProductId, 64),
        itemKind: sanitizeMetadataValue(itemKind, 32),
        templateId: sanitizeMetadataValue(templateId, 128),
        templateName: sanitizeMetadataValue(templateName, 120),
        storeTemplateName: sanitizeMetadataValue(storeTemplateName, 120),
        checkoutRequestKey: sanitizeMetadataValue(idempotencyKey, 80)
    };

    const lineItem: Stripe.Checkout.SessionCreateParams.LineItem = stripeTestMode ? {
        quantity: 1,
        price_data: {
            currency: shippingCurrency,
            unit_amount: catalogItem.unitAmountCents,
            product_data: {
                name: catalogItem.label,
                description: "PitchMark physical product"
            }
        }
    } : {
        price: catalogItem.priceId,
        quantity: 1
    };

    let session: Stripe.Checkout.Session;
    try {
        session = await stripe.checkout.sessions.create({
            mode: "payment",
            line_items: [
                lineItem
            ],
            success_url: successUrl,
            cancel_url: cancelUrl,
            billing_address_collection: "required",
            metadata,
            payment_intent_data: {
                metadata
            },
            allow_promotion_codes: true,
            phone_number_collection: {
                enabled: true
            },
            shipping_address_collection: {
                allowed_countries: allowedShippingCountries as Stripe.Checkout.SessionCreateParams.ShippingAddressCollection.AllowedCountry[]
            },
            shipping_options: [
                {
                    shipping_rate_data: {
                        type: "fixed_amount",
                        fixed_amount: {
                            amount: standardShippingAmountCents,
                            currency: shippingCurrency
                        },
                        display_name: "Standard Shipping",
                        delivery_estimate: {
                            minimum: { unit: "business_day", value: 5 },
                            maximum: { unit: "business_day", value: 8 }
                        }
                    }
                },
                {
                    shipping_rate_data: {
                        type: "fixed_amount",
                        fixed_amount: {
                            amount: expressShippingAmountCents,
                            currency: shippingCurrency
                        },
                        display_name: "Express Shipping",
                        delivery_estimate: {
                            minimum: { unit: "business_day", value: 2 },
                            maximum: { unit: "business_day", value: 3 }
                        }
                    }
                }
            ]
        }, (idempotencyKey && !stripeTestMode) ? {
            idempotencyKey: `checkout_${request.auth.uid}_${idempotencyKey}_${checkoutConfigVersion}`
        } : undefined);
    } catch (error) {
        logger.error("Stripe checkout session create failed", error);
        const message = error instanceof Error ? error.message : "Unknown Stripe error";
        throw new HttpsError("internal", `Stripe checkout create failed: ${message}`);
    }

    if (!session.url) {
        logger.error("Stripe checkout session created without URL", { retailProductId, uid: request.auth.uid });
        throw new HttpsError("internal", "Failed to create checkout URL.");
    }

    logger.info("Checkout session created", {
        uid: request.auth.uid,
        sessionId: session.id,
        retailProductId,
        stripeTestMode,
        shippingAddressCollection: session.shipping_address_collection ?? null,
        shippingOptionsCount: session.shipping_options?.length ?? 0,
        phoneCollectionEnabled: session.phone_number_collection?.enabled ?? null
    });

    if (idempotencyKey) {
        const idemRef = db.collection("checkoutRequests").doc(request.auth.uid).collection("keys").doc(idempotencyKey);
        await idemRef.set(
            {
                checkoutUrl: session.url,
                sessionId: session.id,
                displayName: catalogItem.label,
                retailProductId,
                itemKind,
                templateId,
                templateName,
                storeTemplateName,
                templateSnapshotJson,
                checkoutConfigVersion,
                stripeTestMode,
                createdAt: FieldValue.serverTimestamp()
            },
            { merge: true }
        );
    }

    return {
        checkoutUrl: session.url,
        sessionId: session.id,
        displayName: catalogItem.label
    };
});

type StripeEventHandler = (event: Stripe.Event) => Promise<void>;

const checkoutWebhookHandlers: Record<string, StripeEventHandler> = {
    "checkout.session.completed": async (event) => {
        const session = event.data.object as Stripe.Checkout.Session;
        await persistRetailOrder(session, "completed");
    },
    "checkout.session.async_payment_succeeded": async (event) => {
        const session = event.data.object as Stripe.Checkout.Session;
        await persistRetailOrder(session, "async_payment_succeeded");
    },
    "checkout.session.async_payment_failed": async (event) => {
        const session = event.data.object as Stripe.Checkout.Session;
        await persistRetailOrder(session, "async_payment_failed");
    }
};

async function persistRetailOrder(
    session: Stripe.Checkout.Session,
    fulfillmentState: "completed" | "async_payment_succeeded" | "async_payment_failed"
): Promise<void> {
    const metadata = session.metadata ?? {};
    const uid = metadata.firebaseUid ?? "";
    const checkoutRequestKey = metadata.checkoutRequestKey ?? "";
    const sessionId = session.id;
    if (!sessionId) {
        logger.error("Stripe webhook missing session id", { fulfillmentState });
        return;
    }

    let templateSnapshotJson = "";
    if (uid && checkoutRequestKey) {
        try {
            const checkoutRequestSnap = await db
                .collection("checkoutRequests")
                .doc(uid)
                .collection("keys")
                .doc(checkoutRequestKey)
                .get();
            if (checkoutRequestSnap.exists) {
                const data = checkoutRequestSnap.data() ?? {};
                if (typeof data.templateSnapshotJson === "string") {
                    templateSnapshotJson = data.templateSnapshotJson;
                }
            }
        } catch (error) {
            logger.error("Unable to load checkout request snapshot", { uid, checkoutRequestKey, error });
        }
    }

    const orderRef = db.collection("retailOrders").doc(sessionId);
    await db.runTransaction(async (tx) => {
        const existingSnap = await tx.get(orderRef);
        const existing = existingSnap.exists ? existingSnap.data() ?? {} : {};
        const defaultFulfillmentStatus = fulfillmentState === "async_payment_failed" ? "payment_failed" : "new";
        const shippingName = session.shipping_details?.name
            ?? session.customer_details?.name
            ?? "";
        const shippingAddress = session.shipping_details?.address
            ?? session.customer_details?.address
            ?? null;

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
            shippingName,
            shippingAddress,
            stripeCustomerId: typeof session.customer === "string" ? session.customer : "",
            paymentIntentId: typeof session.payment_intent === "string" ? session.payment_intent : "",
            firebaseUid: uid,
            retailProductId: metadata.retailProductId ?? "",
            itemKind: metadata.itemKind ?? "",
            templateId: metadata.templateId ?? "",
            templateName: metadata.templateName ?? "",
            storeTemplateName: metadata.storeTemplateName ?? "",
            orderedTemplateSnapshotJson: templateSnapshotJson,
            fulfillmentStatus: typeof existing.fulfillmentStatus === "string" && existing.fulfillmentStatus
                ? existing.fulfillmentStatus
                : defaultFulfillmentStatus,
            shippingCarrier: typeof existing.shippingCarrier === "string" ? existing.shippingCarrier : "",
            trackingNumber: typeof existing.trackingNumber === "string" ? existing.trackingNumber : "",
            internalNotes: typeof existing.internalNotes === "string" ? existing.internalNotes : "",
            createdAt: existingSnap.exists ? (existing.createdAt ?? FieldValue.serverTimestamp()) : FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
            stripeCreatedAtMs: session.created ? session.created * 1000 : null
        }, { merge: true });
    });
}

export const stripeWebhook = onRequest({ region: "us-central1" }, async (req, res) => {
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
    let event: Stripe.Event;

    try {
        event = stripe.webhooks.constructEvent(req.rawBody, signature, webhookSecret);
    } catch (error) {
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
    } catch (error) {
        logger.error("Stripe webhook handler failed", { type: event.type, error });
        res.status(500).send("Webhook handler failed");
    }
});
