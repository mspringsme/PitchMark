#!/usr/bin/env node

const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");

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

const uid = readArg("uid") || process.env.FIREBASE_UID || "";
const email = (readArg("email") || process.env.FIREBASE_EMAIL || "").trim().toLowerCase();
const projectId = readArg("project") || process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT || "";

if (!uid && !email) {
    console.error("Usage: node scripts/setAdminClaim.js --uid <firebase-uid> | --email <user@example.com> [--project firebase-project-id]");
    process.exit(2);
}

initializeApp({
    credential: applicationDefault(),
    ...(projectId ? { projectId } : {})
});

const auth = getAuth();

async function resolveUser() {
    if (uid) {
        return auth.getUser(uid);
    }

    return auth.getUserByEmail(email);
}

async function main() {
    const user = await resolveUser();
    const currentClaims = user.customClaims || {};
    const nextClaims = {
        ...currentClaims,
        admin: true
    };

    await auth.setCustomUserClaims(user.uid, nextClaims);

    console.log(`Admin claim set for uid=${user.uid}${user.email ? ` email=${user.email}` : ""}`);
    console.log("Next step: sign the account out and back in, or force a token refresh, so the app can see the new claim.");
}

main().catch((error) => {
    console.error("Failed to set admin claim:");
    console.error(error);
    process.exit(1);
});
