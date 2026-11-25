#!/usr/bin/env node
// Sets feature flags / the cost kill switch in appConfig/flags (2026-11-24).
// Apps can only read that document (firestore.rules: APP CONFIG), so it's
// changed here with admin credentials, or in the Firebase console.
//
//   node scripts/setAppFlags.js --project pitchmark-fb9f8 gameFeeds=true
//   node scripts/setAppFlags.js --project pitchmark-fb9f8 killSwitch=true
//
// Values are merged; other flags are left as they are. The four features
// behind the release gate stay off in the app whatever this says
// (AppFeatureFlags.releaseGateCleared).

const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const args = process.argv.slice(2);
const projectIndex = args.indexOf("--project");
const projectId = projectIndex >= 0 ? args[projectIndex + 1] : process.env.GCLOUD_PROJECT;
const pairs = args.filter((a, i) => a.includes("=") && i !== projectIndex + 1);

if (!projectId || pairs.length === 0) {
    console.error("Usage: node scripts/setAppFlags.js --project <id> name=true|false [...]");
    process.exit(2);
}

const allowed = new Set(["gameFeeds", "followAlerts", "interimClipSharing", "killSwitch",
    "cloudClips", "fullGameVideo", "viewerPass", "contentSafety"]);
const update = {};
for (const pair of pairs) {
    const [name, value] = pair.split("=");
    if (!allowed.has(name) || !["true", "false"].includes(value)) {
        console.error(`Unknown flag or value: ${pair}`);
        process.exit(2);
    }
    update[name] = value === "true";
}
update.updatedAt = FieldValue.serverTimestamp();

initializeApp({ credential: applicationDefault(), projectId });
getFirestore().collection("appConfig").doc("flags").set(update, { merge: true })
    .then(async () => {
        const snap = await getFirestore().collection("appConfig").doc("flags").get();
        const { updatedAt, ...flags } = snap.data();
        console.log("appConfig/flags:", JSON.stringify(flags));
    })
    .catch((error) => {
        console.error(error.message);
        process.exit(1);
    });
