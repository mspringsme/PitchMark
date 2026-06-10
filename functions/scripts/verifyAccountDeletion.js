#!/usr/bin/env node

const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");

function readArg(name) {
    const prefixed = `--${name}=`;
    const inline = process.argv.find((arg) => arg.startsWith(prefixed));
    if (inline) {
        return inline.slice(prefixed.length).trim();
    }

    const index = process.argv.indexOf(`--${name}`);
    if (index >= 0 && process.argv[index + 1]) {
        return process.argv[index + 1].trim();
    }

    return "";
}

const uid = readArg("uid") || process.env.TEST_UID || "";
const email = (readArg("email") || process.env.TEST_EMAIL || "").toLowerCase();
const orderId = readArg("order") || process.env.TEST_ORDER_ID || "";
const projectId = readArg("project") || process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT || "";

if (!uid) {
    console.error("Usage: node scripts/verifyAccountDeletion.js --uid <firebase-uid> [--email user@example.com] [--order stripe_session_id] [--project firebase-project-id]");
    process.exit(2);
}

initializeApp({
    credential: applicationDefault(),
    ...(projectId ? { projectId } : {})
});

const auth = getAuth();
const db = getFirestore();
const failures = [];
const warnings = [];

function record(ok, label, detail = "") {
    const marker = ok ? "PASS" : "FAIL";
    const line = detail ? `${marker} ${label}: ${detail}` : `${marker} ${label}`;
    console.log(line);
    if (!ok) {
        failures.push(line);
    }
}

function warn(label, detail = "") {
    const line = detail ? `WARN ${label}: ${detail}` : `WARN ${label}`;
    console.log(line);
    warnings.push(line);
}

async function countQuery(label, query, expected = 0) {
    const snap = await query.count().get();
    const count = snap.data().count;
    record(count === expected, label, `found ${count}, expected ${expected}`);
    return count;
}

async function countRecursiveDocuments(ref) {
    let total = 0;
    const collections = await ref.listCollections();
    for (const collection of collections) {
        const docs = await collection.listDocuments();
        total += docs.length;
        for (const doc of docs) {
            total += await countRecursiveDocuments(doc);
        }
    }
    return total;
}

async function verifyAuthUserDeleted() {
    try {
        await auth.getUser(uid);
        record(false, "Firebase Auth user deleted", `auth user ${uid} still exists`);
    } catch (error) {
        if (error && error.code === "auth/user-not-found") {
            record(true, "Firebase Auth user deleted");
            return;
        }
        throw error;
    }
}

async function verifyPrivateTreeDeleted(label, docRef) {
    const snap = await docRef.get();
    const descendantCount = await countRecursiveDocuments(docRef);
    record(!snap.exists && descendantCount === 0, label, `doc exists=${snap.exists}, descendant docs=${descendantCount}`);
}

async function verifyRetailOrder() {
    await countQuery(
        "No retailOrders still linked by firebaseUid",
        db.collection("retailOrders").where("firebaseUid", "==", uid)
    );

    if (orderId) {
        const orderSnap = await db.collection("retailOrders").doc(orderId).get();
        if (!orderSnap.exists) {
            record(false, "Retail order retained", `retailOrders/${orderId} is missing`);
            return;
        }

        const data = orderSnap.data() || {};
        record(true, "Retail order retained", `retailOrders/${orderId} exists`);
        record((data.firebaseUid || "") === "", "Retail order unlinked", `firebaseUid=${JSON.stringify(data.firebaseUid || "")}`);
        record(data.accountDeleted === true, "Retail order marked accountDeleted", `accountDeleted=${JSON.stringify(data.accountDeleted)}`);
        return;
    }

    if (email) {
        const snap = await db.collection("retailOrders").where("customerEmail", "==", email).get();
        if (snap.empty) {
            warn("Retail order email lookup", `no orders found for ${email}; skip if this test account never placed a retail order`);
            return;
        }

        for (const doc of snap.docs) {
            const data = doc.data();
            const linkedUid = data.firebaseUid || "";
            const accountDeleted = data.accountDeleted === true;
            record(linkedUid === "" && accountDeleted, `Retail order ${doc.id} retained and unlinked`, `firebaseUid=${JSON.stringify(linkedUid)}, accountDeleted=${JSON.stringify(data.accountDeleted)}`);
        }
        return;
    }

    warn("Retail order retained/unlinked", "provide --order <stripe_session_id> or --email <customerEmail> if the test account placed a retail order");
}

async function main() {
    console.log(`Verifying deletion for uid=${uid}${email ? ` email=${email}` : ""}${orderId ? ` order=${orderId}` : ""}`);

    await verifyAuthUserDeleted();
    await verifyPrivateTreeDeleted("Private user tree deleted", db.collection("users").doc(uid));
    await verifyPrivateTreeDeleted("Checkout request tree deleted", db.collection("checkoutRequests").doc(uid));

    await countQuery("No owned top-level templates", db.collection("templates").where("ownerUid", "==", uid));
    await countQuery("No shared template UID references", db.collection("templates").where("sharedWith", "array-contains", uid));
    if (email) {
        await countQuery("No shared template email references", db.collection("templates").where("sharedWithEmails", "array-contains", email));
    } else {
        warn("Shared template email references", "provide --email to verify sharedWithEmails cleanup");
    }

    await countQuery("No owned pitchers", db.collection("pitchers").where("ownerUid", "==", uid));
    await countQuery("No claimed pitchers", db.collection("pitchers").where("claimedByUid", "==", uid));
    await countQuery("No shared pitcher references", db.collection("pitchers").where("sharedWith", "array-contains", uid));

    await countQuery("No invite tokens", db.collection("inviteTokens").where("ownerUid", "==", uid));
    await countQuery("No display invite tokens", db.collection("displayInviteTokens").where("ownerUid", "==", uid));
    await countQuery("No pitcher invite tokens", db.collection("pitcherInviteTokens").where("ownerUid", "==", uid));
    await countQuery("No join codes", db.collection("joinCodes").where("ownerUid", "==", uid));
    await countQuery("No owned live games", db.collection("liveGames").where("ownerUid", "==", uid));
    await countQuery("No live connection participant references", db.collection("liveGames").where("connection.participantUid", "==", uid));
    await countQuery("No live participant docs", db.collectionGroup("participants").where("uid", "==", uid));
    await countQuery("No live display participant docs", db.collectionGroup("displayParticipants").where("uid", "==", uid));
    await countQuery("No pitch events still attributed to deleted uid", db.collectionGroup("pitchEvents").where("createdByUid", "==", uid));
    await countQuery("No checkout rate-limit docs", db.collection("rateLimits").doc("checkout").collection("users").where("uid", "==", uid));

    await verifyRetailOrder();

    if (failures.length > 0) {
        console.error(`\nAccount deletion verification FAILED with ${failures.length} issue(s).`);
        process.exit(1);
    }

    console.log(`\nAccount deletion verification passed${warnings.length ? ` with ${warnings.length} warning(s)` : ""}.`);
}

main().catch((error) => {
    console.error("Verification failed with an unexpected error:");
    console.error(error);
    process.exit(1);
});
