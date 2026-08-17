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
exports.stripeWebhook = exports.createRetailCheckoutSession = exports.deleteAccount = exports.getSubscriptionEntitlement = exports.syncSubscriptionEntitlement = void 0;
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const app_1 = require("firebase-admin/app");
const auth_1 = require("firebase-admin/auth");
const firestore_1 = require("firebase-admin/firestore");
const app_store_server_library_1 = require("@apple/app-store-server-library");
const stripe_1 = __importDefault(require("stripe"));
const appleRootCertificates_1 = require("./appleRootCertificates");
(0, app_1.initializeApp)();
const db = (0, firestore_1.getFirestore)();
const auth = (0, auth_1.getAuth)();
const retailCatalog = {
    grid_5x3: { priceId: "price_1TWMl2HGR9piiykP6OCTEeNJ", label: "Grid Key 5 x 3", unitAmountCents: 1200 },
    grid_3_5x2_75: { priceId: "price_1TWMlwHGR9piiykP0L1a4G1a", label: "Grid Key 3.5 x 2.75", unitAmountCents: 1200 },
    grid_custom: { priceId: "price_1TWMmuHGR9piiykPW7qo1LHY", label: "Grid Key Custom", unitAmountCents: 1400 },
    sheet_8_5x11: { priceId: "price_1TWMpLHGR9piiykPw9kDjvkm", label: "Printable Sheet 8.5 x 11", unitAmountCents: 1200 }
};
const allowedItemKinds = new Set(["gridKey", "printableSheet", ""]);
const idempotencyKeyPattern = /^[a-zA-Z0-9._-]{8,80}$/;
const checkoutThrottleWindowMs = 60_000;
const checkoutThrottleMaxAttempts = 5;
const checkoutConfigVersion = "shipping_v1";
const accountDeletionBatchSize = 400;
const accountDeletionRecursiveBatchSize = 5;
const accountDeletionTaskConcurrency = 4;
// Destructive account deletion requires reauthentication within the last 10 minutes.
const accountDeletionRecentAuthWindowSeconds = 10 * 60;
const accountDeletionTombstonesCollection = "accountDeletionTombstones";
const pitchMarkStoreConfigs = [
    {
        bundleId: "com.pitchmark.app",
        appAppleId: 6791446420,
        productIds: new Set(["com.pitchmark.app.pro.annual"])
    },
    {
        bundleId: "app.Pitchmark-Display",
        appAppleId: 6785099266,
        productIds: new Set(["com.pitchmark.display.pro.annual"])
    }
];
const pitchMarkTransactionVerifiers = pitchMarkStoreConfigs.flatMap((config) => [
    {
        config,
        environment: app_store_server_library_1.Environment.PRODUCTION,
        verifier: new app_store_server_library_1.SignedDataVerifier(appleRootCertificates_1.appleRootCertificates, true, app_store_server_library_1.Environment.PRODUCTION, config.bundleId, config.appAppleId)
    },
    {
        config,
        environment: app_store_server_library_1.Environment.SANDBOX,
        verifier: new app_store_server_library_1.SignedDataVerifier(appleRootCertificates_1.appleRootCertificates, true, app_store_server_library_1.Environment.SANDBOX, config.bundleId)
    }
]);
async function verifyPitchMarkTransaction(signedTransaction) {
    for (const candidate of pitchMarkTransactionVerifiers) {
        try {
            const transaction = await candidate.verifier.verifyAndDecodeTransaction(signedTransaction);
            if (!transaction.productId || !candidate.config.productIds.has(transaction.productId)) {
                throw new https_1.HttpsError("invalid-argument", "The App Store product is not a PitchMark Pro subscription.");
            }
            return { transaction, config: candidate.config };
        }
        catch (error) {
            if (error instanceof https_1.HttpsError) {
                throw error;
            }
        }
    }
    throw new https_1.HttpsError("invalid-argument", "The App Store transaction could not be verified.");
}
function entitlementResponse(data) {
    const expiresAtMs = typeof data?.expiresAtMs === "number" ? data.expiresAtMs : null;
    const revoked = typeof data?.revocationDateMs === "number";
    const upgraded = data?.isUpgraded === true;
    return {
        active: expiresAtMs !== null && expiresAtMs > Date.now() && !revoked && !upgraded,
        expiresAtMs
    };
}
function getStripeClient() {
    const stripeSecretKey = process.env.STRIPE_SECRET_KEY;
    if (!stripeSecretKey) {
        throw new https_1.HttpsError("failed-precondition", "Missing STRIPE_SECRET_KEY environment variable.");
    }
    return new stripe_1.default(stripeSecretKey, {
        apiVersion: "2024-06-20"
    });
}
function isStripeTestMode() {
    const stripeSecretKey = process.env.STRIPE_SECRET_KEY ?? "";
    return stripeSecretKey.startsWith("sk_test_");
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
function parseAllowedShippingCountries(raw) {
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
function readShippingAmountCents(name, fallback) {
    const value = optionalEnv(name);
    if (!value) {
        return fallback;
    }
    const parsed = Number.parseInt(value, 10);
    if (!Number.isFinite(parsed) || parsed < 0) {
        throw new https_1.HttpsError("failed-precondition", `${name} must be a non-negative integer (cents).`);
    }
    return parsed;
}
function normalizeShippingAmountCents(value) {
    return value < 0 ? 0 : value;
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
    const tombstoneRef = accountDeletionTombstoneRef(uid);
    await db.runTransaction(async (tx) => {
        const [tombstoneSnapshot, snap] = await Promise.all([
            tx.get(tombstoneRef),
            tx.get(ref)
        ]);
        if (tombstoneSnapshot.exists) {
            throw new https_1.HttpsError("failed-precondition", "This account is being deleted.");
        }
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
async function deleteQueryDocuments(query) {
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
async function recursiveDeleteQueryDocuments(query) {
    let deleted = 0;
    while (true) {
        const snap = await query.limit(accountDeletionRecursiveBatchSize).get();
        if (snap.empty) {
            return deleted;
        }
        await Promise.all(snap.docs.map((doc) => db.recursiveDelete(doc.ref)));
        deleted += snap.docs.length;
    }
}
async function updateQueryDocuments(query, updates) {
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
async function runAccountDeletionTasks(summary, tasks) {
    let nextTaskIndex = 0;
    const workerCount = Math.min(accountDeletionTaskConcurrency, tasks.length);
    await Promise.all(Array.from({ length: workerCount }, async () => {
        while (nextTaskIndex < tasks.length) {
            const taskIndex = nextTaskIndex;
            nextTaskIndex += 1;
            const [name, operation] = tasks[taskIndex];
            summary[name] = await operation();
        }
    }));
}
async function preflightAccountDeletionCollectionGroupIndexes(uid) {
    await Promise.all([
        db.collectionGroup("participants").where("uid", "==", uid).limit(1).get(),
        db.collectionGroup("displayParticipants").where("uid", "==", uid).limit(1).get(),
        db.collectionGroup("pitchEvents").where("createdByUid", "==", uid).limit(1).get(),
        db.collectionGroup("pitchEvents").where("originalCreatedByUid", "==", uid).limit(1).get(),
        db.collectionGroup("games").where("resultSelection.createdByUid", "==", uid).limit(1).get(),
        db.collectionGroup("games").where("batterSideUpdatedBy", "==", uid).limit(1).get()
    ]);
}
function firebaseErrorCode(error) {
    return typeof error === "object" && error !== null && "code" in error
        ? String(error.code)
        : "";
}
function requireRecentAuthentication(authTimeClaim) {
    const authTimeSeconds = typeof authTimeClaim === "number"
        ? authTimeClaim
        : Number(authTimeClaim);
    const nowSeconds = Math.floor(Date.now() / 1000);
    const ageSeconds = nowSeconds - authTimeSeconds;
    if (!Number.isFinite(authTimeSeconds)
        || authTimeSeconds <= 0
        || ageSeconds < -60
        || ageSeconds > accountDeletionRecentAuthWindowSeconds) {
        throw new https_1.HttpsError("unauthenticated", "For your security, sign in again before deleting your account.");
    }
}
function accountDeletionTombstoneRef(uid) {
    return db.collection(accountDeletionTombstonesCollection).doc(uid);
}
async function assertAccountNotTombstoned(uid) {
    const snapshot = await accountDeletionTombstoneRef(uid).get();
    if (snapshot.exists) {
        throw new https_1.HttpsError("failed-precondition", "This account is being deleted.");
    }
}
async function writeAccountDeletionTombstone(uid) {
    const ref = accountDeletionTombstoneRef(uid);
    await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(ref);
        transaction.set(ref, {
            status: "blocked",
            lastAttemptAt: firestore_1.FieldValue.serverTimestamp(),
            ...(!snapshot.exists ? {
                blockedAt: firestore_1.FieldValue.serverTimestamp(),
                schemaVersion: 1
            } : {})
        }, { merge: true });
    });
}
async function accountEmail(uid, tokenEmail) {
    try {
        const userRecord = await auth.getUser(uid);
        return userRecord.email?.trim().toLowerCase() || tokenEmail;
    }
    catch (error) {
        if (firebaseErrorCode(error) === "auth/user-not-found") {
            return tokenEmail;
        }
        throw error;
    }
}
async function deleteLegacyOtpRequest(email) {
    const ref = db.collection("otpRequests").doc(email);
    const snapshot = await ref.get();
    await db.recursiveDelete(ref);
    return snapshot.exists ? 1 : 0;
}
exports.syncSubscriptionEntitlement = (0, https_1.onCall)({ region: "us-central1", timeoutSeconds: 30 }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "Sign in to verify your PitchMark Pro subscription.");
    }
    const data = parseRequestData(request.data);
    const signedTransaction = readOptionalString(data, "signedTransaction", 30_000);
    if (!signedTransaction) {
        throw new https_1.HttpsError("invalid-argument", "Missing signed App Store transaction.");
    }
    const { transaction, config } = await verifyPitchMarkTransaction(signedTransaction);
    const originalTransactionId = transaction.originalTransactionId?.trim() ?? "";
    const transactionId = transaction.transactionId?.trim() ?? "";
    const productId = transaction.productId?.trim() ?? "";
    const expiresAtMs = transaction.expiresDate;
    const signedDateMs = transaction.signedDate ?? Date.now();
    if (!originalTransactionId || !transactionId || !productId || typeof expiresAtMs !== "number") {
        throw new https_1.HttpsError("invalid-argument", "The App Store transaction is missing subscription details.");
    }
    const bindingRef = db.collection("subscriptionTransactionBindings").doc(originalTransactionId);
    const entitlementRef = db.collection("subscriptionEntitlements").doc(uid);
    const tombstoneRef = accountDeletionTombstoneRef(uid);
    const response = await db.runTransaction(async (firestoreTransaction) => {
        const [tombstoneSnapshot, bindingSnapshot, entitlementSnapshot] = await Promise.all([
            firestoreTransaction.get(tombstoneRef),
            firestoreTransaction.get(bindingRef),
            firestoreTransaction.get(entitlementRef)
        ]);
        if (tombstoneSnapshot.exists) {
            throw new https_1.HttpsError("failed-precondition", "This account is being deleted.");
        }
        const boundUid = bindingSnapshot.exists ? String(bindingSnapshot.data()?.uid ?? "") : "";
        if (boundUid && boundUid !== uid) {
            throw new https_1.HttpsError("permission-denied", "This App Store subscription is already connected to another PitchMark account.");
        }
        const existing = entitlementSnapshot.data();
        const existingSignedDateMs = typeof existing?.signedDateMs === "number"
            ? existing.signedDateMs
            : 0;
        const existingExpiresAtMs = typeof existing?.expiresAtMs === "number"
            ? existing.expiresAtMs
            : 0;
        const incomingIsActive = expiresAtMs > Date.now()
            && typeof transaction.revocationDate !== "number"
            && transaction.isUpgraded !== true;
        const existingIsActive = entitlementResponse(existing).active;
        const shouldReplace = !entitlementSnapshot.exists
            || signedDateMs >= existingSignedDateMs
            || (incomingIsActive && (!existingIsActive || expiresAtMs > existingExpiresAtMs));
        firestoreTransaction.set(bindingRef, {
            uid,
            originalTransactionId,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
            ...(!bindingSnapshot.exists ? { createdAt: firestore_1.FieldValue.serverTimestamp() } : {})
        }, { merge: true });
        if (shouldReplace) {
            firestoreTransaction.set(entitlementRef, {
                uid,
                active: incomingIsActive,
                bundleId: config.bundleId,
                environment: transaction.environment ?? "",
                expiresAtMs,
                isUpgraded: transaction.isUpgraded === true,
                originalTransactionId,
                productId,
                purchaseDateMs: transaction.purchaseDate ?? null,
                revocationDateMs: transaction.revocationDate ?? null,
                signedDateMs,
                transactionId,
                syncedAt: firestore_1.FieldValue.serverTimestamp()
            }, { merge: true });
            return { active: incomingIsActive, expiresAtMs };
        }
        return entitlementResponse(existing);
    });
    logger.info("PitchMark Pro entitlement synced", {
        uid,
        productId,
        bundleId: config.bundleId,
        active: response.active,
        expiresAtMs: response.expiresAtMs
    });
    return response;
});
exports.getSubscriptionEntitlement = (0, https_1.onCall)({ region: "us-central1" }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "Sign in to check your PitchMark Pro subscription.");
    }
    return db.runTransaction(async (transaction) => {
        const [tombstoneSnapshot, entitlementSnapshot] = await Promise.all([
            transaction.get(accountDeletionTombstoneRef(uid)),
            transaction.get(db.collection("subscriptionEntitlements").doc(uid))
        ]);
        if (tombstoneSnapshot.exists) {
            throw new https_1.HttpsError("failed-precondition", "This account is being deleted.");
        }
        return entitlementResponse(entitlementSnapshot.data());
    });
});
exports.deleteAccount = (0, https_1.onCall)({ region: "us-central1", timeoutSeconds: 540 }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "Please sign in again to delete your account.");
    }
    requireRecentAuthentication(request.auth?.token.auth_time);
    const startedAtMs = Date.now();
    const tokenEmail = typeof request.auth?.token.email === "string"
        ? request.auth.token.email.trim().toLowerCase()
        : "";
    const email = await accountEmail(uid, tokenEmail);
    const deletedAt = firestore_1.FieldValue.serverTimestamp();
    const summary = {};
    logger.info("Account deletion started", { uid });
    try {
        await preflightAccountDeletionCollectionGroupIndexes(uid);
    }
    catch (error) {
        logger.error("Account deletion preflight failed before data mutation", { uid, error });
        throw new https_1.HttpsError("unavailable", "Account deletion could not start. Please try again shortly.");
    }
    // This is the first mutation. Firestore rules use this retained document
    // as a durable barrier while Admin SDK cleanup continues and after Auth deletion.
    await writeAccountDeletionTombstone(uid);
    // Remove user-owned trees first. The follow-up reference cleanup then only
    // touches surviving documents, avoiding conflicting writes to trees that
    // are being recursively deleted.
    const ownedDataDeletionTasks = [
        ["ownedTemplates", () => recursiveDeleteQueryDocuments(db.collection("templates").where("ownerUid", "==", uid))],
        ["ownedPitchers", () => recursiveDeleteQueryDocuments(db.collection("pitchers").where("ownerUid", "==", uid))],
        ["inviteTokens", () => recursiveDeleteQueryDocuments(db.collection("inviteTokens").where("ownerUid", "==", uid))],
        ["displayInviteTokens", () => recursiveDeleteQueryDocuments(db.collection("displayInviteTokens").where("ownerUid", "==", uid))],
        ["pitcherInviteTokens", () => recursiveDeleteQueryDocuments(db.collection("pitcherInviteTokens").where("ownerUid", "==", uid))],
        ["joinCodes", () => recursiveDeleteQueryDocuments(db.collection("joinCodes").where("ownerUid", "==", uid))],
        ["liveGames", () => recursiveDeleteQueryDocuments(db.collection("liveGames").where("ownerUid", "==", uid))],
        ["checkoutRateLimits", () => deleteQueryDocuments(db.collection("rateLimits").doc("checkout").collection("users").where("uid", "==", uid))],
        ["subscriptionTransactionBindings", () => recursiveDeleteQueryDocuments(db.collection("subscriptionTransactionBindings").where("uid", "==", uid))]
    ];
    if (email) {
        ownedDataDeletionTasks.push(["otpRequest", () => deleteLegacyOtpRequest(email)]);
    }
    else {
        summary.otpRequest = 0;
    }
    await Promise.all([
        runAccountDeletionTasks(summary, ownedDataDeletionTasks),
        db.recursiveDelete(db.collection("checkoutRequests").doc(uid)),
        db.recursiveDelete(db.collection("subscriptionEntitlements").doc(uid)),
        db.recursiveDelete(db.collection("users").doc(uid))
    ]);
    const referenceCleanupTasks = [
        ["sharedTemplateUidRefs", () => updateQueryDocuments(db.collection("templates").where("sharedWith", "array-contains", uid), { sharedWith: firestore_1.FieldValue.arrayRemove(uid), updatedAt: deletedAt })],
        ["claimedPitchers", () => updateQueryDocuments(db.collection("pitchers").where("claimedByUid", "==", uid), { claimedByUid: firestore_1.FieldValue.delete(), updatedAt: deletedAt })],
        ["sharedPitcherRefs", () => updateQueryDocuments(db.collection("pitchers").where("sharedWith", "array-contains", uid), { sharedWith: firestore_1.FieldValue.arrayRemove(uid), updatedAt: deletedAt })],
        ["liveConnections", () => updateQueryDocuments(db.collection("liveGames").where("connection.participantUid", "==", uid), { connection: firestore_1.FieldValue.delete(), updatedAt: deletedAt })],
        ["livePendingSelections", () => updateQueryDocuments(db.collection("liveGames").where("pending.createdByUid", "==", uid), { pending: firestore_1.FieldValue.delete(), updatedAt: deletedAt })],
        ["liveResultSelections", () => updateQueryDocuments(db.collection("liveGames").where("resultSelection.createdByUid", "==", uid), { resultSelection: firestore_1.FieldValue.delete(), updatedAt: deletedAt })],
        ["liveBatterSideAttribution", () => updateQueryDocuments(db.collection("liveGames").where("batterSideUpdatedBy", "==", uid), { batterSideUpdatedBy: firestore_1.FieldValue.delete(), batterSideAccountDeletedAt: deletedAt })],
        ["legacyGameResultSelections", () => updateQueryDocuments(db.collectionGroup("games").where("resultSelection.createdByUid", "==", uid), { resultSelection: firestore_1.FieldValue.delete(), updatedAt: deletedAt })],
        ["legacyGameBatterSideAttribution", () => updateQueryDocuments(db.collectionGroup("games").where("batterSideUpdatedBy", "==", uid), { batterSideUpdatedBy: firestore_1.FieldValue.delete(), batterSideAccountDeletedAt: deletedAt })],
        ["createdPitchEvents", () => updateQueryDocuments(db.collectionGroup("pitchEvents").where("createdByUid", "==", uid), { createdByUid: "", creatorAccountDeletedAt: deletedAt })],
        ["originalCreatedPitchEvents", () => updateQueryDocuments(db.collectionGroup("pitchEvents").where("originalCreatedByUid", "==", uid), { originalCreatedByUid: "", creatorAccountDeletedAt: deletedAt })],
        ["retailOrdersUnlinked", () => updateQueryDocuments(db.collection("retailOrders").where("firebaseUid", "==", uid), { firebaseUid: "", accountDeleted: true, accountDeletedAt: deletedAt })]
    ];
    if (email) {
        referenceCleanupTasks.push(["sharedTemplateEmailRefs", () => updateQueryDocuments(db.collection("templates").where("sharedWithEmails", "array-contains", email), { sharedWithEmails: firestore_1.FieldValue.arrayRemove(email), updatedAt: deletedAt })]);
    }
    else {
        summary.sharedTemplateEmailRefs = 0;
    }
    await runAccountDeletionTasks(summary, referenceCleanupTasks);
    // Presence is deleted last so an active heartbeat has the smallest
    // possible window to recreate a document before the Auth account goes away.
    await runAccountDeletionTasks(summary, [
        ["liveParticipants", () => deleteQueryDocuments(db.collectionGroup("participants").where("uid", "==", uid))],
        ["liveDisplayParticipants", () => deleteQueryDocuments(db.collectionGroup("displayParticipants").where("uid", "==", uid))]
    ]);
    try {
        await auth.deleteUser(uid);
    }
    catch (error) {
        if (firebaseErrorCode(error) !== "auth/user-not-found") {
            logger.error("Firebase Auth user deletion failed", { uid, error });
            throw new https_1.HttpsError("internal", "Account data was removed, but sign-in deletion failed. Contact support.");
        }
    }
    logger.info("Account deleted", {
        uid,
        durationMs: Date.now() - startedAtMs,
        summary
    });
    return { success: true };
});
exports.createRetailCheckoutSession = (0, https_1.onCall)({ region: "us-central1" }, async (request) => {
    if (!request.auth?.uid) {
        throw new https_1.HttpsError("unauthenticated", "You must be signed in to purchase.");
    }
    await assertAccountNotTombstoned(request.auth.uid);
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
        throw new https_1.HttpsError("invalid-argument", "retailProductId is required.");
    }
    if (!allowedItemKinds.has(itemKind)) {
        throw new https_1.HttpsError("invalid-argument", "itemKind is invalid.");
    }
    const catalogItem = retailCatalog[retailProductId];
    if (!catalogItem) {
        throw new https_1.HttpsError("invalid-argument", "Unknown retailProductId.");
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
    const metadata = {
        app: "PitchMark",
        firebaseUid: request.auth.uid,
        retailProductId: sanitizeMetadataValue(retailProductId, 64),
        itemKind: sanitizeMetadataValue(itemKind, 32),
        templateId: sanitizeMetadataValue(templateId, 128),
        templateName: sanitizeMetadataValue(templateName, 120),
        storeTemplateName: sanitizeMetadataValue(storeTemplateName, 120),
        checkoutRequestKey: sanitizeMetadataValue(idempotencyKey, 80)
    };
    const lineItem = stripeTestMode ? {
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
    let session;
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
                allowed_countries: allowedShippingCountries
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
    }
    catch (error) {
        logger.error("Stripe checkout session create failed", error);
        const message = error instanceof Error ? error.message : "Unknown Stripe error";
        throw new https_1.HttpsError("internal", `Stripe checkout create failed: ${message}`);
    }
    if (!session.url) {
        logger.error("Stripe checkout session created without URL", { retailProductId, uid: request.auth.uid });
        throw new https_1.HttpsError("internal", "Failed to create checkout URL.");
    }
    // Avoid recreating the user's checkout-request tree if deletion began
    // while Stripe was creating the session.
    await assertAccountNotTombstoned(request.auth.uid);
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
        await db.runTransaction(async (transaction) => {
            const tombstoneSnapshot = await transaction.get(accountDeletionTombstoneRef(request.auth.uid));
            if (tombstoneSnapshot.exists) {
                throw new https_1.HttpsError("failed-precondition", "This account is being deleted.");
            }
            transaction.set(idemRef, {
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
                createdAt: firestore_1.FieldValue.serverTimestamp()
            }, { merge: true });
        });
    }
    // A final check also covers checkouts without an idempotency document.
    await assertAccountNotTombstoned(request.auth.uid);
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
    const checkoutRequestKey = metadata.checkoutRequestKey ?? "";
    const sessionId = session.id;
    if (!sessionId) {
        logger.error("Stripe webhook missing session id", { fulfillmentState });
        return;
    }
    const initiallyTombstoned = uid
        ? (await accountDeletionTombstoneRef(uid).get()).exists
        : false;
    let templateSnapshotJson = "";
    if (uid && checkoutRequestKey && !initiallyTombstoned) {
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
        }
        catch (error) {
            logger.error("Unable to load checkout request snapshot", { uid, checkoutRequestKey, error });
        }
    }
    const orderRef = db.collection("retailOrders").doc(sessionId);
    await db.runTransaction(async (tx) => {
        const [existingSnap, tombstoneSnapshot] = await Promise.all([
            tx.get(orderRef),
            uid ? tx.get(accountDeletionTombstoneRef(uid)) : Promise.resolve(null)
        ]);
        const existing = existingSnap.exists ? existingSnap.data() ?? {} : {};
        const accountDeleted = tombstoneSnapshot?.exists === true || existing.accountDeleted === true;
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
            firebaseUid: accountDeleted ? "" : uid,
            ...(accountDeleted ? {
                accountDeleted: true,
                accountDeletedAt: existing.accountDeletedAt ?? firestore_1.FieldValue.serverTimestamp()
            } : {}),
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
