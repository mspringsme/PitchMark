// Practice sessions (approved 2026-11-20):
//   R8 a coach's practice sessions and their pitches
//      (users/{uid}/practiceSessions/{id}, .../pitchEvents) are owner-only.
//   P4 (2026-11-20) the owner can archive and delete a session and its
//      pitches; nobody else can.
// No rules change was needed - the users/** catch-all covers them; this
// proves it stays that way.

import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, it } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { collection, deleteDoc, doc, getDoc, getDocs, setDoc } from "firebase/firestore";

const COACH = "coach";
const OTHER = "other";
let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const admin = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));
const session = { label: "Practice", pitcherId: "p1", pitcherName: "Ava", pitches: ["4 Seam"] };
const pitch = { pitch: "4 Seam", location: "Strike Up", isStrike: true };

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
});

describe("R8 practice sessions are owner-only", () => {
  it("the coach writes and reads their sessions and pitches", async () => {
    await assertSucceeds(setDoc(doc(db(COACH), "users", COACH, "practiceSessions", "s1"), session));
    await assertSucceeds(setDoc(doc(db(COACH), "users", COACH, "practiceSessions", "s1", "pitchEvents", "e1"), pitch));
    await assertSucceeds(getDocs(collection(db(COACH), "users", COACH, "practiceSessions")));
    await assertSucceeds(getDocs(collection(db(COACH), "users", COACH, "practiceSessions", "s1", "pitchEvents")));
  });

  it("the owner archives and deletes a session and its pitches", async () => {
    await admin(async (f) => {
      await setDoc(doc(f, "users", COACH, "practiceSessions", "s1"), session);
      await setDoc(doc(f, "users", COACH, "practiceSessions", "s1", "pitchEvents", "e1"), pitch);
    });
    await assertSucceeds(setDoc(doc(db(COACH), "users", COACH, "practiceSessions", "s1"), { ...session, archivedAt: new Date() }));
    await assertSucceeds(deleteDoc(doc(db(COACH), "users", COACH, "practiceSessions", "s1", "pitchEvents", "e1")));
    await assertSucceeds(deleteDoc(doc(db(COACH), "users", COACH, "practiceSessions", "s1")));
  });

  it("nobody else reads, lists, writes or deletes them", async () => {
    await admin(async (f) => {
      await setDoc(doc(f, "users", COACH, "practiceSessions", "s1"), session);
      await setDoc(doc(f, "users", COACH, "practiceSessions", "s1", "pitchEvents", "e1"), pitch);
    });
    await assertFails(getDoc(doc(db(OTHER), "users", COACH, "practiceSessions", "s1")));
    await assertFails(getDocs(collection(db(OTHER), "users", COACH, "practiceSessions")));
    await assertFails(getDocs(collection(db(OTHER), "users", COACH, "practiceSessions", "s1", "pitchEvents")));
    await assertFails(setDoc(doc(db(OTHER), "users", COACH, "practiceSessions", "s2"), session));
    await assertFails(setDoc(doc(db(OTHER), "users", COACH, "practiceSessions", "s1", "pitchEvents", "e2"), pitch));
    await assertFails(deleteDoc(doc(db(OTHER), "users", COACH, "practiceSessions", "s1")));
    await assertFails(deleteDoc(doc(db(OTHER), "users", COACH, "practiceSessions", "s1", "pitchEvents", "e1")));
    await assertFails(getDoc(doc(anon(), "users", COACH, "practiceSessions", "s1")));
  });
});
