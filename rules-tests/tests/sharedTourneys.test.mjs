// Shared tourneys (approved 2026-11-17): a coach's read-only copy of a
// Round Robin / Tourney Info page at /sharedTourneys/{shareId}.
//   1 anyone signed in can open a copy by its id; signed out can't
//   2 nobody can list the collection
//   3 only the owner creates one, naming themselves, with a 32-64 hex id
//   4 a non-owner can't change or delete it; the owner can't hand it over
//   5 a follower's own items live on their own follow record only
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

const SHARE = "0123456789abcdef0123456789abcdef";
const COACH = "coach";
const PARENT = "parent";

let env;
const db = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const admin = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));
const copy = (ownerUid = COACH, name = "Summer Slam") => ({ ownerUid, name, notes: "" });

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

describe("1 opening a shared copy", () => {
  beforeEach(() => admin((f) => setDoc(doc(f, "sharedTourneys", SHARE), copy())));

  it("anyone signed in can open it by its id", async () => {
    await assertSucceeds(getDoc(doc(db(PARENT), "sharedTourneys", SHARE)));
    await assertSucceeds(getDoc(doc(db(COACH), "sharedTourneys", SHARE)));
  });

  it("signed out can't", async () => {
    await assertFails(getDoc(doc(anon(), "sharedTourneys", SHARE)));
  });

  it("opening a missing copy is allowed (the app shows No Longer Shared)", async () => {
    await assertSucceeds(getDoc(doc(db(PARENT), "sharedTourneys", "f".repeat(32))));
  });
});

describe("2 listing", () => {
  it("nobody can list the collection, owner included", async () => {
    await admin((f) => setDoc(doc(f, "sharedTourneys", SHARE), copy()));
    await assertFails(getDocs(collection(db(PARENT), "sharedTourneys")));
    await assertFails(getDocs(collection(db(COACH), "sharedTourneys")));
  });
});

describe("3 creating", () => {
  it("the owner creates one naming themselves", async () => {
    await assertSucceeds(setDoc(doc(db(COACH), "sharedTourneys", SHARE), copy()));
  });

  it("can't create one naming someone else", async () => {
    await assertFails(setDoc(doc(db(PARENT), "sharedTourneys", SHARE), copy(COACH)));
  });

  it("can't create one with no owner", async () => {
    await assertFails(setDoc(doc(db(COACH), "sharedTourneys", SHARE), { name: "x" }));
  });

  it("signed out can't create one", async () => {
    await assertFails(setDoc(doc(anon(), "sharedTourneys", SHARE), copy()));
  });

  it("the id must be 32-64 lowercase hex", async () => {
    await assertFails(setDoc(doc(db(COACH), "sharedTourneys", "abc123"), copy()));
    await assertFails(setDoc(doc(db(COACH), "sharedTourneys", "g".repeat(32)), copy()));
    await assertFails(setDoc(doc(db(COACH), "sharedTourneys", SHARE.toUpperCase()), copy()));
    await assertFails(setDoc(doc(db(COACH), "sharedTourneys", "a".repeat(65)), copy()));
    await assertSucceeds(setDoc(doc(db(COACH), "sharedTourneys", "a".repeat(64)), copy()));
  });
});

describe("4 changing and removing", () => {
  beforeEach(() => admin((f) => setDoc(doc(f, "sharedTourneys", SHARE), copy())));

  it("the owner updates it", async () => {
    await assertSucceeds(setDoc(doc(db(COACH), "sharedTourneys", SHARE), copy(COACH, "Renamed")));
  });

  it("someone else can't change it", async () => {
    await assertFails(updateDoc(doc(db(PARENT), "sharedTourneys", SHARE), { name: "Hacked" }));
    await assertFails(setDoc(doc(db(PARENT), "sharedTourneys", SHARE), copy(PARENT)));
  });

  it("the owner can't hand it to someone else", async () => {
    await assertFails(updateDoc(doc(db(COACH), "sharedTourneys", SHARE), { ownerUid: PARENT }));
  });

  it("only the owner removes it (Stop Sharing)", async () => {
    await assertFails(deleteDoc(doc(db(PARENT), "sharedTourneys", SHARE)));
    await assertSucceeds(deleteDoc(doc(db(COACH), "sharedTourneys", SHARE)));
  });
});

describe("5 a follower's own record", () => {
  const follow = (uid) => doc(db(uid), "users", PARENT, "followedTourneys", SHARE);

  it("the follower saves the link and their own items", async () => {
    await assertSucceeds(setDoc(follow(PARENT), { name: "Summer Slam", myItems: [{ id: "1", text: "Chairs", done: false }] }));
  });

  it("nobody else - the coach included - reads or writes it", async () => {
    await admin((f) => setDoc(doc(f, "users", PARENT, "followedTourneys", SHARE), { name: "x", myItems: [] }));
    await assertFails(getDoc(follow(COACH)));
    await assertFails(setDoc(follow(COACH), { myItems: [] }));
  });
});
