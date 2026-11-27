#!/usr/bin/env node
// Prints the newest freeze/crash reports the app saved (HangReporter.swift),
// with the main thread's stack - the frames that were stuck.
//
//   node scripts/readDiagnostics.js --project pitchmark-fb9f8 [--email you@example.com] [--count 3]
//
// Without --email it reads every account's reports (newest first).

const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

const arg = (name) => {
    const i = process.argv.indexOf(`--${name}`);
    return i >= 0 ? process.argv[i + 1] : undefined;
};
const projectId = arg("project") || process.env.GCLOUD_PROJECT;
const count = Number(arg("count") || 3);
if (!projectId) {
    console.error("Usage: node scripts/readDiagnostics.js --project <id> [--email <email>] [--count N]");
    process.exit(2);
}
initializeApp({ credential: applicationDefault(), projectId });

// Flattens MetricKit's call-stack tree into lines, deepest call first.
function frames(tree) {
    const out = [];
    const walk = (nodes, depth) => {
        for (const n of nodes || []) {
            out.push(`${"  ".repeat(depth)}${n.binaryName || "?"}  +${n.offsetIntoBinaryTextSegment ?? "?"}  ${n.symbolName || ""}`.trimEnd());
            walk(n.subFrames, depth + 1);
        }
    };
    for (const thread of tree?.callStacks || []) {
        if (thread.threadAttributed) {
            out.push("— main / attributed thread —");
            walk(thread.callStackRootFrames, 0);
        }
    }
    return out.slice(0, 80);
}

(async () => {
    const db = getFirestore();
    let query = db.collectionGroup("diagnostics").orderBy("receivedAt", "desc").limit(count);
    const email = arg("email");
    if (email) {
        const user = await getAuth().getUserByEmail(email);
        query = db.collection("users").doc(user.uid).collection("diagnostics").orderBy("receivedAt", "desc").limit(count);
    }
    const snap = await query.get();
    if (snap.empty) return console.log("No reports yet.");
    for (const doc of snap.docs) {
        const d = doc.data();
        console.log(`\n=== ${d.kind} · ended ${d.endedAt?.toDate?.().toISOString()} · app ${d.appVersion} · ${doc.ref.path}`);
        let report = {};
        try { report = JSON.parse(d.report); } catch { console.log("(report truncated)"); }
        for (const hang of report.hangDiagnostics || []) {
            console.log(`hang: ${hang.diagnosticMetaData?.hangDuration || ""}`);
            frames(hang.callStackTree).forEach((l) => console.log(l));
        }
        for (const crash of report.crashDiagnostics || []) {
            console.log(`crash: ${crash.diagnosticMetaData?.exceptionType || ""} ${crash.diagnosticMetaData?.signal || ""}`);
            frames(crash.callStackTree).forEach((l) => console.log(l));
        }
    }
})().catch((e) => { console.error(e.message); process.exit(1); });
