#!/usr/bin/env node

/**
 * Duplicate a Firestore document within the same collection.
 *
 * Usage:
 *   node scripts/duplicateDocument.js --collection <name> --id <sourceDocId> [--newId <newDocId>] [--subcollections] [--project <firebase-project-id>]
 *
 * Examples:
 *   node scripts/duplicateDocument.js --collection games --id abc123
 *   node scripts/duplicateDocument.js --collection games --id abc123 --newId abc123-copy
 *   node scripts/duplicateDocument.js --collection games --id abc123 --subcollections
 *
 * Auth: uses application-default credentials, same as the other scripts in this
 * folder. Run `gcloud auth application-default login` first if you haven't,
 * and make sure the active gcloud project matches --project (or set
 * GCLOUD_PROJECT / FIREBASE_PROJECT env vars).
 */

const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

function readArg(name) {
    const prefixed = `--${name}=`;
    const inline = process.argv.find((arg) => arg.startsWith(prefixed));
    if (inline) {
        return inline.slice(prefixed.length).trim();
    }

    const index = process.argv.indexOf(`--${name}`);
    if (index >= 0 && process.argv[index + 1] && !process.argv[index + 1].startsWith("--")) {
        return process.argv[index + 1].trim();
    }

    return "";
}

function hasFlag(name) {
    return process.argv.includes(`--${name}`);
}

const collection = readArg("collection");
const sourceId = readArg("id");
const explicitNewId = readArg("newId");
const includeSubcollections = hasFlag("subcollections");
const projectId = readArg("project") || process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT || "";

if (!collection || !sourceId) {
    console.error(
        "Usage: node scripts/duplicateDocument.js --collection <name> --id <sourceDocId> " +
        "[--newId <newDocId>] [--subcollections] [--project <firebase-project-id>]"
    );
    process.exit(2);
}

initializeApp({
    credential: applicationDefault(),
    ...(projectId ? { projectId } : {}),
});

const db = getFirestore();

/**
 * Recursively copy a document and (optionally) its subcollections to a new
 * document reference. Returns the number of documents copied.
 */
async function copyDocument(sourceRef, destRef, withSubcollections) {
    const snap = await sourceRef.get();
    if (!snap.exists) {
        throw new Error(`Source document not found: ${sourceRef.path}`);
    }

    await destRef.set(snap.data());
    let count = 1;

    if (withSubcollections) {
        const subcollections = await sourceRef.listCollections();
        for (const subcol of subcollections) {
            const docs = await subcol.get();
            for (const doc of docs.docs) {
                count += await copyDocument(doc.ref, destRef.collection(subcol.id).doc(doc.id), true);
            }
        }
    }

    return count;
}

async function main() {
    const sourceRef = db.collection(collection).doc(sourceId);
    const destRef = explicitNewId
        ? db.collection(collection).doc(explicitNewId)
        : db.collection(collection).doc(); // auto-generated ID

    const destSnap = await destRef.get();
    if (destSnap.exists) {
        console.error(`Refusing to overwrite existing document: ${destRef.path}`);
        process.exit(1);
    }

    console.log(`Copying ${sourceRef.path} -> ${destRef.path}${includeSubcollections ? " (with subcollections)" : ""} ...`);
    const count = await copyDocument(sourceRef, destRef, includeSubcollections);
    console.log(`Done. Copied ${count} document(s). New document ID: ${destRef.id}`);
}

main().catch((err) => {
    console.error("Failed:", err.message || err);
    process.exit(1);
});
