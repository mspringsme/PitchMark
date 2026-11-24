// App config (approved 2026-11-24, clip brief phase 2): /appConfig/{docId}
// holds the feature flags and the cost kill switch.
//   5 readable by anyone signed in; not signed out; never listed; no app
//     writes (create, update, delete)
//
// Expected values come from the approved rules list, not from running the
// rules.

import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, it } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { collection, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc } from "firebase/firestore";

let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const admin = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-pitchmark-rules",
    firestore: {
      rules: readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8"),
      host: "127.0.0.1",
      port: 8085,
    },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await admin((f) => setDoc(doc(f, "appConfig", "flags"), { gameFeeds: false, killSwitch: false }));
});

describe("5 app config", () => {
  it("anyone signed in reads the flags", async () => {
    await assertSucceeds(getDoc(doc(db("parent"), "appConfig", "flags")));
  });

  it("signed out can't", async () => {
    await assertFails(getDoc(doc(anon(), "appConfig", "flags")));
  });

  it("nobody lists it", async () => {
    await assertFails(getDocs(collection(db("parent"), "appConfig")));
  });

  it("no app writes it", async () => {
    const f = db("coach");
    await assertFails(updateDoc(doc(f, "appConfig", "flags"), { killSwitch: true }));
    await assertFails(setDoc(doc(f, "appConfig", "flags"), { gameFeeds: true }));
    await assertFails(setDoc(doc(f, "appConfig", "other"), { anything: 1 }));
    await assertFails(deleteDoc(doc(f, "appConfig", "flags")));
  });
});
