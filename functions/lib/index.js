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
const gridKeyPrintSize_1 = require("./gridKeyPrintSize");
const retailCatalog_1 = require("./retailCatalog");
const storage_1 = require("firebase-admin/storage");
const seasonBook_1 = require("./seasonBook");
const tradingCards_1 = require("./tradingCards");
const sponsorSlot_1 = require("./sponsorSlot");
(0, app_1.initializeApp)();
const db = (0, firestore_1.getFirestore)();
const auth = (0, auth_1.getAuth)();
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
    if (!retailCatalog_1.allowedItemKinds.has(itemKind)) {
        throw new https_1.HttpsError("invalid-argument", "itemKind is invalid.");
    }
    const catalogItem = retailCatalog_1.retailCatalog[retailProductId];
    if (!catalogItem) {
        throw new https_1.HttpsError("invalid-argument", "Unknown retailProductId.");
    }
    // A season book or sponsor slot is only ever ordered as itself, and no
    // other product may borrow their item kinds.
    const requiredItemKind = retailCatalog_1.requiredItemKindByProduct[retailProductId] ?? null;
    const claimsSpecialKind = Object.values(retailCatalog_1.requiredItemKindByProduct).includes(itemKind);
    if ((requiredItemKind && itemKind !== requiredItemKind) || (!requiredItemKind && claimsSpecialKind)) {
        throw new https_1.HttpsError("invalid-argument", "itemKind doesn't match the product.");
    }
    let seasonBook = null;
    if (itemKind === seasonBook_1.seasonBookProduct.itemKind) {
        const resolved = (0, seasonBook_1.resolveSeasonBookRequest)(request.auth.uid, data.pageCount, data.uploadPath);
        if (!resolved.ok) {
            throw new https_1.HttpsError("invalid-argument", resolved.message);
        }
        const [uploaded] = await (0, storage_1.getStorage)().bucket().file(resolved.value.uploadPath).exists();
        if (!uploaded) {
            throw new https_1.HttpsError("failed-precondition", "The book hasn't finished uploading. Try again.");
        }
        seasonBook = resolved.value;
    }
    let sponsor = null;
    if (itemKind === sponsorSlot_1.sponsorSlotProduct.itemKind) {
        const validated = (0, sponsorSlot_1.validateSponsorSnapshot)(templateSnapshotJson);
        if (!validated.ok) {
            throw new https_1.HttpsError("invalid-argument", validated.message);
        }
        const teamSnap = await db.collection("teams").doc(validated.value.teamId).get();
        if (!teamSnap.exists || teamSnap.get("createdByUid") !== request.auth.uid) {
            throw new https_1.HttpsError("permission-denied", "Only the team's coach can buy its sponsor slot.");
        }
        sponsor = validated.value;
    }
    let familyPack = null;
    if (itemKind === "cardFamilyPack") {
        const resolved = (0, tradingCards_1.resolveFamilyPackRequest)(request.auth.uid, retailProductId, data.frontPath, data.backPath);
        if (!resolved.ok) {
            throw new https_1.HttpsError("invalid-argument", resolved.message);
        }
        const bucket = (0, storage_1.getStorage)().bucket();
        const [[front], [back]] = await Promise.all([
            bucket.file(resolved.value.frontPath).exists(),
            bucket.file(resolved.value.backPath).exists()
        ]);
        if (!front || !back) {
            throw new https_1.HttpsError("failed-precondition", "The card hasn't finished uploading. Try again.");
        }
        familyPack = resolved.value;
    }
    let teamSet = null;
    if (itemKind === "cardTeamSet") {
        if (!idempotencyKey) {
            throw new https_1.HttpsError("invalid-argument", "Update PitchMark to order a team set.");
        }
        const teamIdRaw = typeof data.teamId === "string" ? data.teamId : "";
        const setIdRaw = typeof data.setId === "string" ? data.setId : "";
        const setRef = teamIdRaw && setIdRaw
            ? db.collection("teams").doc(teamIdRaw).collection("cardSets").doc(setIdRaw)
            : null;
        const [setSnap, entriesSnap] = setRef
            ? await Promise.all([setRef.get(), setRef.collection("entries").get()])
            : [null, null];
        const entries = (entriesSnap?.docs ?? []).map((doc) => ({ ...doc.data(), id: doc.id }));
        const planned = (0, tradingCards_1.planTeamSetOrder)({
            uid: request.auth.uid,
            teamId: data.teamId,
            setId: data.setId,
            setCount: data.setCount,
            set: setSnap?.exists ? (setSnap.data() ?? {}) : null,
            entries
        });
        if (!planned.ok) {
            throw new https_1.HttpsError("failed-precondition", planned.message);
        }
        // What prints is the art as it stood when the set was locked: copy
        // each entry's two sides into this order's own folder.
        const bucket = (0, storage_1.getStorage)().bucket();
        const byId = new Map(entries.map((entry) => [entry.id, entry]));
        await Promise.all(planned.value.players.flatMap((entryId) => {
            const entry = byId.get(entryId) ?? {};
            const ownerUid = typeof entry.ownerUid === "string" ? entry.ownerUid : "";
            return ["front", "back"].map(async (side) => {
                const source = entry[`${side}Path`];
                if (!(0, tradingCards_1.isEntryArtPath)(planned.value.teamId, planned.value.setId, ownerUid, entryId, source)) {
                    throw new https_1.HttpsError("failed-precondition", "A card in this set is missing its art. Ask that family to submit again.");
                }
                await bucket.file(source).copy(bucket.file((0, tradingCards_1.frozenArtPath)(idempotencyKey, entryId, side, source)));
            });
        }));
        teamSet = { ...planned.value, folder: `cardOrders/${idempotencyKey}` };
    }
    const isDigital = retailCatalog_1.digitalProductIds.has(retailProductId);
    const unitAmountCents = seasonBook?.priceCents ?? familyPack?.priceCents ?? teamSet?.priceCents ?? catalogItem.unitAmountCents;
    const printSizeResolution = (0, gridKeyPrintSize_1.resolveGridKeyPrintSize)(retailProductId, data.printWidthInches, data.printHeightInches);
    if (!printSizeResolution.ok) {
        throw new https_1.HttpsError("invalid-argument", printSizeResolution.message);
    }
    const printSize = printSizeResolution.size;
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
        checkoutRequestKey: sanitizeMetadataValue(idempotencyKey, 80),
        ...(seasonBook ? {
            pageCount: String(seasonBook.pageCount),
            uploadPath: sanitizeMetadataValue(seasonBook.uploadPath, 400)
        } : {}),
        ...(sponsor ? { sponsorTeamId: sponsor.teamId } : {}),
        ...(familyPack ? {
            quantity: String(familyPack.quantity),
            cardFrontPath: sanitizeMetadataValue(familyPack.frontPath, 400),
            cardBackPath: sanitizeMetadataValue(familyPack.backPath, 400)
        } : {}),
        ...(teamSet ? {
            cardTeamId: teamSet.teamId,
            cardSetId: teamSet.setId,
            setCount: String(teamSet.setCount),
            playerCount: String(teamSet.players.length),
            cardOrderFolder: sanitizeMetadataValue(teamSet.folder, 200)
        } : {}),
        ...(printSize ? {
            printWidthInches: String(printSize.widthInches),
            printHeightInches: String(printSize.heightInches)
        } : {})
    };
    const lineItem = (stripeTestMode || !catalogItem.priceId) ? {
        quantity: 1,
        price_data: {
            currency: shippingCurrency,
            unit_amount: unitAmountCents,
            product_data: {
                name: catalogItem.label,
                description: isDigital ? "PitchMark team sponsor slot" : "PitchMark physical product"
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
                enabled: !isDigital
            },
            // A sponsor slot ships nothing, so it asks for no address.
            ...(isDigital ? {} : {
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
            })
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
                printWidthInches: printSize?.widthInches ?? null,
                printHeightInches: printSize?.heightInches ?? null,
                pageCount: seasonBook?.pageCount ?? null,
                uploadPath: seasonBook?.uploadPath ?? null,
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
    const printSize = (0, gridKeyPrintSize_1.printSizeFromMetadata)(metadata);
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
            printWidthInches: printSize?.widthInches ?? null,
            printHeightInches: printSize?.heightInches ?? null,
            pageCount: metadata.pageCount ? Number(metadata.pageCount) : null,
            uploadPath: metadata.uploadPath ?? "",
            quantity: metadata.quantity ? Number(metadata.quantity) : null,
            cardFrontPath: metadata.cardFrontPath ?? "",
            cardBackPath: metadata.cardBackPath ?? "",
            cardTeamId: metadata.cardTeamId ?? "",
            cardSetId: metadata.cardSetId ?? "",
            setCount: metadata.setCount ? Number(metadata.setCount) : null,
            playerCount: metadata.playerCount ? Number(metadata.playerCount) : null,
            cardOrderFolder: metadata.cardOrderFolder ?? "",
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
    await fulfillDigitalAndPrintOrders(orderRef);
}
// After an order is saved: activate a paid sponsor slot, or send a paid
// season book to the printer. Each decides inside a transaction on the order,
// so Stripe's retries and its paired completed/async events can't do either
// twice (planSlotActivation / planPrintSubmission).
async function fulfillDigitalAndPrintOrders(orderRef) {
    const order = (await orderRef.get()).data() ?? {};
    if (order.itemKind === sponsorSlot_1.sponsorSlotProduct.itemKind) {
        await activateSponsorSlot(orderRef);
    }
    else if (order.itemKind === seasonBook_1.seasonBookProduct.itemKind) {
        await submitSeasonBook(orderRef);
    }
    else if (order.itemKind === "cardFamilyPack" || order.itemKind === "cardTeamSet") {
        await claimCardOrderForPrinting(orderRef);
    }
}
// Trading cards have no print partner wired in yet (QPMN's API is
// unverified): a paid order is claimed once as awaiting_manual, the same
// print-once guard as the books, and a team set is marked ordered so its
// families see it went in.
async function claimCardOrderForPrinting(orderRef) {
    await db.runTransaction(async (tx) => {
        const order = (await tx.get(orderRef)).data() ?? {};
        if ((0, seasonBook_1.planPrintSubmission)(order) !== "submit") {
            return;
        }
        let setRef = null;
        if (order.itemKind === "cardTeamSet" && typeof order.cardTeamId === "string" && typeof order.cardSetId === "string"
            && order.cardTeamId && order.cardSetId) {
            setRef = db.collection("teams").doc(order.cardTeamId).collection("cardSets").doc(order.cardSetId);
            await tx.get(setRef);
        }
        tx.set(orderRef, {
            printSubmission: { state: "awaiting_manual", claimedAt: firestore_1.FieldValue.serverTimestamp() }
        }, { merge: true });
        if (setRef) {
            tx.set(setRef, { status: "ordered", orderId: orderRef.id, orderedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        }
    });
}
async function activateSponsorSlot(orderRef) {
    await db.runTransaction(async (tx) => {
        const order = (await tx.get(orderRef)).data() ?? {};
        const validated = (0, sponsorSlot_1.validateSponsorSnapshot)(order.orderedTemplateSnapshotJson);
        if (!validated.ok) {
            logger.error("Sponsor order has no valid sponsor details", { orderId: orderRef.id, message: validated.message });
            tx.set(orderRef, { fulfillmentStatus: "needs_attention" }, { merge: true });
            return;
        }
        const slotRef = db.collection("teams").doc(validated.value.teamId).collection("sponsors").doc(orderRef.id);
        const slotSnap = await tx.get(slotRef);
        const plan = (0, sponsorSlot_1.planSlotActivation)({
            itemKind: order.itemKind,
            paymentStatus: order.paymentStatus,
            fulfillmentState: order.fulfillmentState,
            slotExists: slotSnap.exists
        });
        if (plan !== "activate") {
            return;
        }
        tx.create(slotRef, (0, sponsorSlot_1.sponsorSlotDocument)(validated.value, {
            purchasedByUid: typeof order.firebaseUid === "string" ? order.firebaseUid : "",
            orderId: orderRef.id,
            startsAt: new Date()
        }));
        tx.set(orderRef, { fulfillmentStatus: "fulfilled", sponsorSlotPath: slotRef.path }, { merge: true });
    });
}
async function submitSeasonBook(orderRef) {
    const apiKey = optionalEnv("GELATO_API_KEY");
    const productUid = optionalEnv("GELATO_BOOK_PRODUCT_UID");
    const orderUrl = optionalEnv("GELATO_ORDER_URL") || "https://order.gelatoapis.com/v4/orders";
    const configured = Boolean(apiKey && productUid);
    // Claimed before any call to the printer: a second delivery sees the
    // claim and skips. Without the partner configured the order waits for a
    // person (awaiting_manual) instead of being lost.
    const order = await db.runTransaction(async (tx) => {
        const current = (await tx.get(orderRef)).data() ?? {};
        if ((0, seasonBook_1.planPrintSubmission)(current) !== "submit") {
            return null;
        }
        tx.set(orderRef, {
            printSubmission: {
                state: configured ? "submitting" : "awaiting_manual",
                claimedAt: firestore_1.FieldValue.serverTimestamp()
            }
        }, { merge: true });
        return current;
    });
    if (!order || !configured) {
        return;
    }
    try {
        const [fileUrl] = await (0, storage_1.getStorage)().bucket().file(String(order.uploadPath ?? "")).getSignedUrl({
            action: "read",
            expires: Date.now() + 7 * 86_400_000
        });
        const body = (0, seasonBook_1.gelatoOrderPayload)({
            orderId: orderRef.id,
            productUid,
            fileUrl,
            pageCount: Number(order.pageCount),
            shipping: {
                name: String(order.shippingName ?? ""),
                email: String(order.customerEmail ?? ""),
                phone: String(order.customerPhone ?? ""),
                address: order.shippingAddress ?? null
            }
        });
        const response = await fetch(orderUrl, {
            method: "POST",
            headers: { "Content-Type": "application/json", "X-API-KEY": apiKey },
            body: JSON.stringify(body)
        });
        const text = await response.text();
        if (!response.ok) {
            throw new Error(`print partner ${response.status}: ${text.slice(0, 300)}`);
        }
        let partnerOrderId = "";
        try {
            partnerOrderId = String(JSON.parse(text).id ?? "");
        }
        catch {
            partnerOrderId = "";
        }
        await orderRef.set({
            printSubmission: { state: "submitted", partnerOrderId, submittedAt: firestore_1.FieldValue.serverTimestamp() },
            fulfillmentStatus: "in_production"
        }, { merge: true });
    }
    catch (error) {
        // Never retried automatically: a person checks the partner first, so
        // a request that did reach them isn't printed twice.
        logger.error("Season book print submission failed", { orderId: orderRef.id, error });
        await orderRef.set({
            printSubmission: {
                state: "failed",
                error: error instanceof Error ? error.message.slice(0, 500) : "unknown",
                failedAt: firestore_1.FieldValue.serverTimestamp()
            },
            fulfillmentStatus: "needs_attention"
        }, { merge: true });
    }
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
